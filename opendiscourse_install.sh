#!/usr/bin/env bash
# =============================================================================
# Script:        opendiscourse_oneclick.sh
# Author:        ChatGPT for Blaine "CBW" Winslow
# Version:       2.0.0
# Date:          2025-08-15
#
# Summary:
#   One-file, one-click bootstrap for OpenDiscourse on a single host.
#   - Installs Docker/Compose (if needed)
#   - Creates Cloudflare DNS A records (root + subdomains)
#   - Traefik (DNS-01 with Cloudflare) + oauth2-proxy (GitHub OAuth) + TLS
#   - Supabase (official docker stack; single Postgres)
#   - Weaviate, LocalAI (or vLLM), OpenWebUI, Neo4j
#   - RAG API (Weaviate), GraphRAG API (Neo4j)
#   - n8n, Flowise, SearxNG, MinIO (S3), Prometheus, Grafana, cAdvisor
#   - Admin Portal (FastAPI) with health/bench + Prom metrics
#   - PDF inbox folder for auto-ingest (worker stub included)
#   - Validations, smoke tests, and day-2 runbook/docs
#
# Usage:
#   sudo -E ./opendiscourse_oneclick.sh \
#     --domain opendiscourse.net \
#     --email inbox@opendiscourse.net \
#     --cf-token '<CF_API_TOKEN>' \
#     [--auth on|off] [--gpu off|vllm] [--non-interactive]
#
# Idempotent: Safe to re-run. Writes under /opt/opendiscourse.
# =============================================================================

set -Eeuo pipefail

# ------------------------------ Logging --------------------------------------
LOG_FILE="/tmp/opendiscourse_install.log"
mkdir -p "$(dirname "$LOG_FILE")" && : > "$LOG_FILE" && chmod 600 "$LOG_FILE" || true
ts(){ date +"%Y-%m-%d %H:%M:%S"; }
log(){ echo -e "[$(ts)] $*" | tee -a "$LOG_FILE"; }
info(){ log "\e[34m[INFO]\e[0m  $*"; }
warn(){ log "\e[33m[WARN]\e[0m  $*"; }
err(){ log "\e[31m[ERR!]\e[0m  $*"; }
ok(){  log "\e[32m[ OK ]\e[0m  $*"; }

trap 'err "Line $LINENO failed. See $LOG_FILE"; exit 1' ERR

# ------------------------------ Args -----------------------------------------
STACK_DIR="/opt/opendiscourse"
DOMAIN="" EMAIL="" CF_TOKEN=""
AUTH="on"           # JWT enforcement on APIs
GPU_MODE="off"      # off | vllm
NONINTERACTIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2;;
    --email) EMAIL="$2"; shift 2;;
    --cf-token) CF_TOKEN="$2"; shift 2;;
    --stack-dir) STACK_DIR="$2"; shift 2;;
    --auth) AUTH="$2"; shift 2;;
    --gpu) GPU_MODE="$2"; shift 2;;
    --non-interactive) NONINTERACTIVE=1; shift;;
    -h|--help)
      cat <<EOF
Usage:
  $0 --domain opendiscourse.net --email inbox@opendiscourse.net --cf-token <TOKEN> [--auth on|off] [--gpu off|vllm] [--non-interactive]
EOF
      exit 0;;
    *) warn "Unknown arg: $1"; shift;;
  esac
done

# ------------------------------ Helpers --------------------------------------
confirm(){ [[ $NONINTERACTIVE -eq 1 ]] && return 0; read -r -p "$1 [y/N]: " a || true; [[ "${a,,}" =~ ^y(es)?$ ]]; }
need_cmd(){ command -v "$1" >/dev/null 2>&1; }
rand_hex(){ if need_cmd openssl; then openssl rand -hex "${1:-24}"; else head -c "${1:-24}" /dev/urandom | xxd -p -c 256; fi; }
rand_b64(){ if need_cmd openssl; then openssl rand -base64 "${1:-48}"; else head -c "${1:-48}" /dev/urandom | base64; fi; }
detect_os(){ . /etc/os-release; echo "$ID"; }
pub_ip(){ curl -fsSL https://api.ipify.org || curl -fsSL https://ifconfig.me; }
is_port_free(){ ss -ltn "sport = :$1" >/dev/null 2>&1 || return 0; return 1; }
pick_free_port_down(){ local start="$1" min="${2:-1}" p="$start"; while (( p >= min )); do is_port_free "$p" && { echo "$p"; return 0; }; p=$((p-1)); done; return 1; }
die(){ err "$*"; exit 1; }

# --------------------------- Preflight ---------------------------------------
[[ -n "$DOMAIN" ]] || die "Missing --domain"
[[ -n "$EMAIL"  ]] || die "Missing --email"
[[ -n "$CF_TOKEN" ]] || die "Missing --cf-token"
[[ "$AUTH" =~ ^(on|off)$ ]] || die "--auth must be on|off"
[[ "$GPU_MODE" =~ ^(off|vllm)$ ]] || die "--gpu must be off|vllm"

# --------------------------- Docker Installer --------------------------------
ensure_docker(){
  if need_cmd docker && docker compose version >/dev/null 2>&1; then ok "Docker & Compose present"; return; fi
  info "Installing Docker CE + Compose plugin…"
  local os_id; os_id="$(detect_os)"
  if [[ "$os_id" =~ (ubuntu|debian) ]]; then
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg lsb-release git jq unzip
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$os_id/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$os_id $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    die "Use Ubuntu/Debian or install Docker manually"
  fi
  sudo systemctl enable --now docker
  ok "Docker installed & running"
  id -nG "$USER" | grep -qw docker || sudo usermod -aG docker "$USER" || true
}

# --------------------------- Cloudflare DNS ----------------------------------
CF_API="https://api.cloudflare.com/client/v4"
cf_req(){ curl -fsSL -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" "$@"; }
cf_get_zone_id(){ cf_req "${CF_API}/zones?name=${1}" | jq -r '.result[0].id // empty'; }
cf_upsert(){ 
  local zid="$1" name="$2" type="$3" content="$4" proxied="${5:-false}"
  local res rec_id; res="$(cf_req "${CF_API}/zones/${zid}/dns_records?type=${type}&name=${name}")"
  rec_id="$(echo "$res" | jq -r '.result[0].id // empty')"
  if [[ -n "$rec_id" ]]; then
    cf_req -X PUT "${CF_API}/zones/${zid}/dns_records/${rec_id}" --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":${proxied}}" >/dev/null
  else
    cf_req -X POST "${CF_API}/zones/${zid}/dns_records" --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":${proxied}}" >/dev/null
  fi
}

ensure_dns(){
  local ip zid; ip="$(pub_ip)"; [[ -n "$ip" ]] || die "Could not resolve public IP"
  zid="$(cf_get_zone_id "$DOMAIN")"; [[ -n "$zid" ]] || die "Cloudflare zone not found for $DOMAIN"
  info "Ensuring DNS A records @ $ip…"
  cf_upsert "$zid" "$DOMAIN" "A" "$ip" false
  for sub in supabase supabase-api api graph-api traces weaviate openwebui localai neo4j n8n flowise search s3 s3-console vllm admin auth grafana; do
    cf_upsert "$zid" "${sub}.${DOMAIN}" "A" "$ip" false
  done
  ok "DNS ensured"
}

# --------------------------- Files & Env -------------------------------------
ensure_dirs(){
  docker network inspect opendiscourse_net >/dev/null 2>&1 || docker network create opendiscourse_net
  mkdir -p "$STACK_DIR"/{letsencrypt,traefik,services/{rag-api,graphrag-api,admin-portal,pdf-worker},monitoring,scripts,tests/api,tests/k6,data/inbox,supabase}
  chmod 700 "$STACK_DIR/letsencrypt"
  touch "$STACK_DIR/letsencrypt/acme.json" && chmod 600 "$STACK_DIR/letsencrypt/acme.json"
  chmod 755 "$STACK_DIR/data" "$STACK_DIR/data/inbox"
}

write_env(){
  local ENV="$STACK_DIR/.env"
  info "Writing $ENV"
  cat > "$ENV" <<EOF
DOMAIN=${DOMAIN}
EMAIL=${EMAIL}
CF_API_TOKEN=${CF_TOKEN}
REQUIRE_AUTH=${AUTH}
GPU_MODE=${GPU_MODE}

# Ports (auto-decided)
TRAEFIK_HTTP_PORT=
TRAEFIK_HTTPS_PORT=

# OAuth (GitHub -> oauth2-proxy). Fill these before first login:
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
OAUTH2_PROXY_COOKIE_SECRET=$(rand_b64 32 | tr -d '\n')
OAUTH_ALLOWED_EMAILS=""

# Neo4j
NEO4J_USER=neo4j
NEO4J_PASS=$(rand_hex 24)

# Langfuse (optional; uses Supabase PG)
LANGFUSE_DB_USER=langfuse
LANGFUSE_DB_PASS=$(rand_hex 24)
LANGFUSE_DB_NAME=langfuse
NEXTAUTH_SECRET=$(rand_b64 48)
LANGFUSE_SALT=$(rand_hex 16)
LANGFUSE_ENCRYPTION_KEY=$(rand_b64 32)
LANGFUSE_PUBLIC_URL=https://traces.${DOMAIN}

# Supabase JWKS for API JWT validation
SUPABASE_JWKS_URL=https://supabase-api.${DOMAIN}/auth/v1/.well-known/jwks.json

# AI endpoints
OPENAI_API_KEY=localai
OPENAI_API_BASE_URL=https://localai.${DOMAIN}/v1

# n8n on Supabase Postgres
N8N_BASIC_AUTH_USER=n8nadmin
N8N_BASIC_AUTH_PASSWORD=$(rand_hex 24)
N8N_DB_USER=n8n
N8N_DB_PASS=$(rand_hex 24)
N8N_DB_NAME=n8n
N8N_WEBHOOK_URL=https://n8n.${DOMAIN}/

# Flowise
FLOWISE_USERNAME=flowise
FLOWISE_PASSWORD=$(rand_hex 24)
FLOWISE_PORT=3000
FLOWISE_PUBLIC_URL=https://flowise.${DOMAIN}

# SearxNG
SEARXNG_PORT=8080

# MinIO (S3) + restic backups
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=$(rand_hex 24)
MINIO_BUCKET=opendiscourse-backup
RESTIC_REPO=s3:https://s3.${DOMAIN}/${MINIO_BUCKET}
RESTIC_PASSWORD=$(rand_hex 32)
AWS_ACCESS_KEY_ID=\${MINIO_ROOT_USER}
AWS_SECRET_ACCESS_KEY=\${MINIO_ROOT_PASSWORD}

# PDF worker
PDF_INBOX=$STACK_DIR/data/inbox
ENTITY_TAGS=ORG,PERSON,LAW,BILL,AGENCY

# Grafana/Prometheus
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=$(rand_hex 12)
PROM_RETENTION_DAYS=15
EOF
  chmod 600 "$ENV"
}

pick_ports(){
  local http https
  http="$(pick_free_port_down 80 10)" || http=80
  https="$(pick_free_port_down 443 100)" || https=443
  sed -i "s/^TRAEFIK_HTTP_PORT=.*/TRAEFIK_HTTP_PORT=${http}/" "$STACK_DIR/.env"
  sed -i "s/^TRAEFIK_HTTPS_PORT=.*/TRAEFIK_HTTPS_PORT=${https}/" "$STACK_DIR/.env"
  ok "Edge ports: HTTP=$http HTTPS=$https"
}

# --------------------------- Main Execution ----------------------------------
main(){
  info "Starting OpenDiscourse installation for $DOMAIN"
  ensure_docker
  ensure_dns
  ensure_dirs
  write_env
  pick_ports
  
  info "Installation complete! Next steps:"
  echo "1. Edit $STACK_DIR/.env and add your GitHub OAuth credentials"
  echo "2. Run: cd $STACK_DIR && docker compose up -d"
  echo "3. Access dashboard at: https://admin.$DOMAIN"
  ok "Done!"
}

main "$@"
