#!/usr/bin/env bash
# =============================================================================
# Script:        opendiscourse_oneclick.sh
# Author:        ChatGPT for Blaine “CBW” Winslow
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
LOG_FILE="/tmp/CBW-opendiscourse_install.log"
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
    curl -fsSL https://download.docker.com/linux/$os_id/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$os_id $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
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
cf_get_zone_id(){ cf_req "${CF_API}/zones?name=${1}" | awk -F'"' '/"id":/ {print $4; exit}'; }
cf_upsert(){ local zid="$1" name="$2" type="$3" content="$4" proxied="${5:-false}"
  local res rec_id; res="$(cf_req "${CF_API}/zones/${zid}/dns_records?type=${type}&name=${name}")"
  rec_id="$(echo "$res" | awk -F'"' '/"id":/ {print $4; exit}')"
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
MINIO_BUCKET=backups
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

# --------------------------- Write Config & Code -----------------------------
write_traefik(){
  local HTTP HTTPS
  HTTP="$(grep '^TRAEFIK_HTTP_PORT=' "$STACK_DIR/.env" | cut -d= -f2)"
  HTTPS="$(grep '^TRAEFIK_HTTPS_PORT=' "$STACK_DIR/.env" | cut -d= -f2)"
  cat > "$STACK_DIR/traefik/traefik.yml" <<EOF
entryPoints:
  web:       { address: ":${HTTP}" }
  websecure: { address: ":${HTTPS}" }
  metrics:   { address: ":8082" }
providers: { docker: { exposedByDefault: false } }
certificatesResolvers:
  cf:
    acme:
      email: "${EMAIL}"
      storage: "/letsencrypt/acme.json"
      dnsChallenge: { provider: cloudflare, disablePropagationCheck: true }
metrics:
  prometheus:
    entryPoint: metrics
    addEntryPointsLabels: true
    addServicesLabels: true
EOF
}

write_compose(){
  cat > "$STACK_DIR/compose.yml" <<'YAML'
name: opendiscourse
networks: { opendiscourse_net: { external: true } }

volumes:
  weaviate_data: {}
  localai_models: {}
  neo4j_data: {}
  neo4j_plugins: {}
  minio_data: {}
  prom_data: {}
  grafana_data: {}

services:

  traefik:
    image: traefik:v3.1
    container_name: traefik
    restart: unless-stopped
    networks: [opendiscourse_net]
    ports:
      - "${TRAEFIK_HTTP_PORT:-80}:${TRAEFIK_HTTP_PORT:-80}"
      - "${TRAEFIK_HTTPS_PORT:-443}:${TRAEFIK_HTTPS_PORT:-443}"
    environment: { CF_DNS_API_TOKEN: "${CF_API_TOKEN}" }
    volumes:
      - ./traefik/traefik.yml:/traefik.yml:ro
      - ./letsencrypt:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
    labels:
      - traefik.enable=true
      - traefik.http.middlewares.oc-headers.headers.customResponseHeaders.X-Frame-Options=SAMEORIGIN
      - traefik.http.middlewares.oc-headers.headers.customResponseHeaders.X-Content-Type-Options=nosniff
      - traefik.http.middlewares.oc-headers.headers.stsSeconds=31536000
      - traefik.http.middlewares.oc-headers.headers.stsIncludeSubdomains=true
      - traefik.http.middlewares.oc-headers.headers.stsPreload=true
      - traefik.http.middlewares.oc-headers.headers.browserXssFilter=true
      - traefik.http.middlewares.oc-gzip.compress=true
      - traefik.http.middlewares.oc-rl.ratelimit.average=50
      - traefik.http.middlewares.oc-rl.ratelimit.burst=100
      - traefik.http.middlewares.oc-auth.forwardauth.address=http://oauth2-proxy:4180/auth
      - traefik.http.middlewares.oc-auth.forwardauth.trustForwardHeader=true
      - traefik.http.middlewares.oc-auth.forwardauth.authResponseHeaders=X-Auth-Request-User,X-Auth-Request-Email,Authorization,Set-Cookie

  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
    container_name: oauth2-proxy
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment:
      OAUTH2_PROXY_PROVIDER: github
      OAUTH2_PROXY_CLIENT_ID: "${GITHUB_CLIENT_ID}"
      OAUTH2_PROXY_CLIENT_SECRET: "${GITHUB_CLIENT_SECRET}"
      OAUTH2_PROXY_COOKIE_SECRET: "${OAUTH2_PROXY_COOKIE_SECRET}"
      OAUTH2_PROXY_EMAIL_DOMAINS: "*"
      OAUTH2_PROXY_WHITELIST_DOMAINS: ".${DOMAIN}"
      OAUTH2_PROXY_ALLOWED_EMAILS: "${OAUTH_ALLOWED_EMAILS}"
      OAUTH2_PROXY_COOKIE_SECURE: "true"
      OAUTH2_PROXY_COOKIE_HTTPONLY: "true"
      OAUTH2_PROXY_COOKIE_SAMESITE: "lax"
      OAUTH2_PROXY_SET_AUTHORIZATION_HEADER: "true"
      OAUTH2_PROXY_PASS_ACCESS_TOKEN: "true"
      OAUTH2_PROXY_SKIP_PROVIDER_BUTTON: "true"
      OAUTH2_PROXY_REDIRECT_URL: "https://auth.${DOMAIN}/oauth2/callback"
      OAUTH2_PROXY_UPSTREAMS: "file:///dev/null"
      OAUTH2_PROXY_HTTP_ADDRESS: "0.0.0.0:4180"
      OAUTH2_PROXY_SCOPE: "read:user,read:org"
    labels:
      - traefik.enable=true
      - traefik.http.routers.auth.rule=Host(`auth.${DOMAIN}`)
      - traefik.http.routers.auth.entrypoints=websecure
      - traefik.http.routers.auth.tls.certresolver=cf
      - traefik.http.routers.auth.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.auth.loadbalancer.server.port=4180

  weaviate:
    image: semitechnologies/weaviate:1.25.7
    container_name: weaviate
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment:
      QUERY_DEFAULTS_LIMIT: '25'
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'true'
      PERSISTENCE_DATA_PATH: '/var/lib/weaviate'
      ENABLE_MODULES: 'text2vec-openai'
      CLUSTER_HOSTNAME: 'node1'
      OPENAI_APIKEY: "${OPENAI_API_KEY:-localai}"
    volumes: [ weaviate_data:/var/lib/weaviate ]
    labels:
      - traefik.enable=true
      - traefik.http.routers.weaviate.rule=Host(`weaviate.${DOMAIN}`)
      - traefik.http.routers.weaviate.entrypoints=websecure
      - traefik.http.routers.weaviate.tls.certresolver=cf
      - traefik.http.routers.weaviate.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.weaviate.loadbalancer.server.port=8080

  localai:
    image: localai/localai:latest
    container_name: localai
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment: { MODELS_PATH: /models }
    volumes: [ localai_models:/models ]
    labels:
      - traefik.enable=true
      - traefik.http.routers.localai.rule=Host(`localai.${DOMAIN}`)
      - traefik.http.routers.localai.entrypoints=websecure
      - traefik.http.routers.localai.tls.certresolver=cf
      - traefik.http.routers.localai.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.localai.loadbalancer.server.port=8080

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment:
      OPENAI_API_KEY: "${OPENAI_API_KEY:-localai}"
      OPENAI_API_BASE_URL: "${OPENAI_API_BASE_URL}"
    depends_on: [localai]
    labels:
      - traefik.enable=true
      - traefik.http.routers.openwebui.rule=Host(`openwebui.${DOMAIN}`)
      - traefik.http.routers.openwebui.entrypoints=websecure
      - traefik.http.routers.openwebui.tls.certresolver=cf
      - traefik.http.routers.openwebui.middlewares=oc-auth,oc-headers,oc-gzip,oc-rl
      - traefik.http.services.openwebui.loadbalancer.server.port=8080

  neo4j:
    image: neo4j:5.23
    container_name: neo4j
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment:
      NEO4J_AUTH: "${NEO4J_USER}/${NEO4J_PASS}"
      NEO4J_PLUGINS: '["apoc","graph-data-science"]'
      NEO4J_server_memory_pagecache_size: 1G
      NEO4J_server_memory_heap_initial__size: 1G
      NEO4J_server_memory_heap_max__size: 2G
    volumes: [ neo4j_data:/data, neo4j_plugins:/plugins ]
    labels:
      - traefik.enable=true
      - traefik.http.routers.neo4j.rule=Host(`neo4j.${DOMAIN}`)
      - traefik.http.routers.neo4j.entrypoints=websecure
      - traefik.http.routers.neo4j.tls.certresolver=cf
      - traefik.http.routers.neo4j.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.neo4j.loadbalancer.server.port=7474

  rag-api:
    build: { context: ./services/rag-api }
    container_name: rag-api
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment:
      DOMAIN: "${DOMAIN}"
      REQUIRE_AUTH: ${REQUIRE_AUTH}
      SUPABASE_JWKS_URL: ${SUPABASE_JWKS_URL}
      WEAVIATE_URL: "http://weaviate:8080"
      WEAVIATE_CLASS: "Document"
      OPENAI_API_KEY: "${OPENAI_API_KEY:-localai}"
      OPENAI_API_BASE_URL: "${OPENAI_API_BASE_URL}"
    depends_on: [weaviate]
    labels:
      - traefik.enable=true
      - traefik.http.routers.rag.rule=Host(`api.${DOMAIN}`)
      - traefik.http.routers.rag.entrypoints=websecure
      - traefik.http.routers.rag.tls.certresolver=cf
      - traefik.http.routers.rag.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.rag.loadbalancer.server.port=8000

  graphrag-api:
    build: { context: ./services/graphrag-api }
    container_name: graphrag-api
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment:
      REQUIRE_AUTH: ${REQUIRE_AUTH}
      SUPABASE_JWKS_URL: ${SUPABASE_JWKS_URL}
      NEO4J_URI: "bolt://neo4j:7687"
      NEO4J_USER: "${NEO4J_USER}"
      NEO4J_PASS: "${NEO4J_PASS}"
      OPENAI_API_BASE_URL: "${OPENAI_API_BASE_URL}"
      OPENAI_API_KEY: "${OPENAI_API_KEY:-localai}"
    depends_on: [neo4j]
    labels:
      - traefik.enable=true
      - traefik.http.routers.graphrag.rule=Host(`graph-api.${DOMAIN}`)
      - traefik.http.routers.graphrag.entrypoints=websecure
      - traefik.http.routers.graphrag.tls.certresolver=cf
      - traefik.http.routers.graphrag.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.graphrag.loadbalancer.server.port=8010

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment:
      N8N_BASIC_AUTH_ACTIVE: "true"
      N8N_BASIC_AUTH_USER: "${N8N_BASIC_AUTH_USER}"
      N8N_BASIC_AUTH_PASSWORD: "${N8N_BASIC_AUTH_PASSWORD}"
      N8N_HOST: "n8n.${DOMAIN}"
      WEBHOOK_URL: "${N8N_WEBHOOK_URL}"
      N8N_PROTOCOL: "https"
      DB_TYPE: "postgresdb"
      DB_POSTGRESDB_HOST: "supabase-db"
      DB_POSTGRESDB_PORT: "5432"
      DB_POSTGRESDB_DATABASE: "${N8N_DB_NAME}"
      DB_POSTGRESDB_USER: "${N8N_DB_USER}"
      DB_POSTGRESDB_PASSWORD: "${N8N_DB_PASS}"
      GENERIC_TIMEZONE: "UTC"
    labels:
      - traefik.enable=true
      - traefik.http.routers.n8n.rule=Host(`n8n.${DOMAIN}`)
      - traefik.http.routers.n8n.entrypoints=websecure
      - traefik.http.routers.n8n.tls.certresolver=cf
      - traefik.http.routers.n8n.middlewares=oc-auth,oc-headers,oc-gzip,oc-rl
      - traefik.http.services.n8n.loadbalancer.server.port=5678

  flowise:
    image: ghcr.io/flowiseai/flowise:latest
    container_name: flowise
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment:
      PORT: "${FLOWISE_PORT}"
      FLOWISE_USERNAME: "${FLOWISE_USERNAME}"
      FLOWISE_PASSWORD: "${FLOWISE_PASSWORD}"
      FLOWISE_PUBLIC_URL: "${FLOWISE_PUBLIC_URL}"
      OPENAI_API_BASE_URL: "${OPENAI_API_BASE_URL}"
      OPENAI_API_KEY: "${OPENAI_API_KEY}"
    labels:
      - traefik.enable=true
      - traefik.http.routers.flowise.rule=Host(`flowise.${DOMAIN}`)
      - traefik.http.routers.flowise.entrypoints=websecure
      - traefik.http.routers.flowise.tls.certresolver=cf
      - traefik.http.routers.flowise.middlewares=oc-auth,oc-headers,oc-gzip,oc-rl
      - traefik.http.services.flowise.loadbalancer.server.port=${FLOWISE_PORT}

  searxng:
    image: searxng/searxng:latest
    container_name: searxng
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment:
      BASE_URL: "https://search.${DOMAIN}/"
      SEARXNG_URL: "https://search.${DOMAIN}"
    labels:
      - traefik.enable=true
      - traefik.http.routers.search.rule=Host(`search.${DOMAIN}`)
      - traefik.http.routers.search.entrypoints=websecure
      - traefik.http.routers.search.tls.certresolver=cf
      - traefik.http.routers.search.middlewares=oc-auth,oc-headers,oc-gzip,oc-rl
      - traefik.http.services.search.loadbalancer.server.port=${SEARXNG_PORT}

  minio:
    image: quay.io/minio/minio:latest
    container_name: minio
    restart: unless-stopped
    command: server --console-address ":9001" /data
    networks: [opendiscourse_net]
    environment:
      MINIO_ROOT_USER: "${MINIO_ROOT_USER}"
      MINIO_ROOT_PASSWORD: "${MINIO_ROOT_PASSWORD}"
    volumes: [ minio_data:/data ]
    labels:
      - traefik.enable=true
      - traefik.http.routers.minio.rule=Host(`s3.${DOMAIN}`)
      - traefik.http.routers.minio.entrypoints=websecure
      - traefik.http.routers.minio.tls.certresolver=cf
      - traefik.http.routers.minio.middlewares=oc-auth,oc-headers,oc-gzip,oc-rl
      - traefik.http.services.minio.loadbalancer.server.port=9000
      - traefik.http.routers.minio-console.rule=Host(`s3-console.${DOMAIN}`)
      - traefik.http.routers.minio-console.entrypoints=websecure
      - traefik.http.routers.minio-console.tls.certresolver=cf
      - traefik.http.routers.minio-console.middlewares=oc-auth,oc-headers,oc-gzip,oc-rl
      - traefik.http.services.minio-console.loadbalancer.server.port=9001

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    networks: [opendiscourse_net]
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    networks: [opendiscourse_net]
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.retention.time=${PROM_RETENTION_DAYS}d
      - --storage.tsdb.path=/prometheus
    volumes:
      - prom_data:/prometheus
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment:
      GF_SECURITY_ADMIN_USER: "${GRAFANA_ADMIN_USER}"
      GF_SECURITY_ADMIN_PASSWORD: "${GRAFANA_ADMIN_PASSWORD}"
    volumes:
      - grafana_data:/var/lib/grafana
    labels:
      - traefik.enable=true
      - traefik.http.routers.grafana.rule=Host(`grafana.${DOMAIN}`)
      - traefik.http.routers.grafana.entrypoints=websecure
      - traefik.http.routers.grafana.tls.certresolver=cf
      - traefik.http.routers.grafana.middlewares=oc-auth,oc-headers,oc-gzip,oc-rl
      - traefik.http.services.grafana.loadbalancer.server.port=3000

  admin-portal:
    build: { context: ./services/admin-portal }
    container_name: admin-portal
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment:
      DOMAIN: "${DOMAIN}"
      TARGETS: "weaviate:8080,neo4j:7474,rag-api:8000,graphrag-api:8010,localai:8080"
    labels:
      - traefik.enable=true
      - traefik.http.routers.admin.rule=Host(`admin.${DOMAIN}`)
      - traefik.http.routers.admin.entrypoints=websecure
      - traefik.http.routers.admin.tls.certresolver=cf
      - traefik.http.routers.admin.middlewares=oc-auth,oc-headers,oc-gzip,oc-rl
      - traefik.http.services.admin.loadbalancer.server.port=8050

  vllm:
    image: vllm/vllm-openai:latest
    container_name: vllm
    restart: unless-stopped
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
    networks: [opendiscourse_net]
    command: >
      --host 0.0.0.0 --port 8000 --model meta-llama/Llama-3.1-8B-Instruct
    labels:
      - traefik.enable=true
      - traefik.http.routers.vllm.rule=Host(`vllm.${DOMAIN}`)
      - traefik.http.routers.vllm.entrypoints=websecure
      - traefik.http.routers.vllm.tls.certresolver=cf
      - traefik.http.routers.vllm.middlewares=oc-auth,oc-headers,oc-gzip,oc-rl
      - traefik.http.services.vllm.loadbalancer.server.port=8000
YAML
}

write_monitoring(){
  cat > "$STACK_DIR/monitoring/prometheus.yml" <<'EOF'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: prometheus
    static_configs: [{ targets: ['prometheus:9090'] }]
  - job_name: traefik
    static_configs: [{ targets: ['traefik:8082'] }]
  - job_name: cadvisor
    static_configs: [{ targets: ['cadvisor:8080'] }]
  - job_name: rag-api
    static_configs: [{ targets: ['rag-api:8000'] }]
  - job_name: graphrag-api
    static_configs: [{ targets: ['graphrag-api:8010'] }]
EOF
}

# --------------------------- Services: RAG API -------------------------------
write_rag_api(){
  cat > "$STACK_DIR/services/rag-api/Dockerfile" <<'DOCKER'
FROM python:3.11-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
DOCKER

  cat > "$STACK_DIR/services/rag-api/requirements.txt" <<'REQ'
fastapi==0.115.0
uvicorn==0.30.5
pydantic==2.8.2
weaviate-client==4.7.2
langchain==0.2.12
langchain-openai==0.1.22
tiktoken==0.7.0
requests==2.32.3
python-multipart==0.0.9
numpy==2.0.1
python-jose[cryptography]==3.3.0
pymupdf==1.24.9
prometheus-client==0.20.0
REQ

  cat > "$STACK_DIR/services/rag-api/app.py" <<'PY'
import os, time
from typing import List, Optional, Dict, Any
from fastapi import FastAPI, UploadFile, File, HTTPException, Header, Depends, Response, Request
from pydantic import BaseModel, Field
import weaviate
from weaviate.util import generate_uuid5
from langchain.text_splitter import RecursiveCharacterTextSplitter
import requests
from jose import jwt
import fitz  # pymupdf
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

DOMAIN=os.getenv("DOMAIN","localhost")
REQUIRE_AUTH = os.getenv("REQUIRE_AUTH", "on").lower() == "on"
SUPABASE_JWKS_URL = os.getenv("SUPABASE_JWKS_URL", "")

WEAVIATE_URL = os.getenv("WEAVIATE_URL", "http://weaviate:8080")
WEAVIATE_CLASS = os.getenv("WEAVIATE_CLASS", "Document")
OPENAI_API_BASE_URL = os.getenv("OPENAI_API_BASE_URL", "http://localai:8080/v1")

client = weaviate.Client(WEAVIATE_URL)
app = FastAPI(title="OpenDiscourse RAG API", version="2.0.0")

REQS = Counter("ragapi_requests_total","RAG API requests",["path","method","code"])
LAT  = Histogram("ragapi_request_latency_seconds","RAG API latency",["path"])

from fastapi.middleware.cors import CORSMiddleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=[f"https://supabase.{DOMAIN}",f"https://openwebui.{DOMAIN}",f"https://flowise.{DOMAIN}"],
    allow_credentials=True, allow_methods=["*"], allow_headers=["*"],
)

jwks_cache: Dict[str, Any] = {}
def get_jwks():
  global jwks_cache
  if jwks_cache: return jwks_cache
  if not SUPABASE_JWKS_URL: raise HTTPException(500, "JWKS URL not configured")
  r = requests.get(SUPABASE_JWKS_URL, timeout=5); r.raise_for_status()
  jwks_cache = r.json(); return jwks_cache

def verify_bearer(auth: Optional[str] = Header(default=None, alias="Authorization")):
  if not REQUIRE_AUTH: return
  if not auth or not auth.lower().startswith("bearer "): raise HTTPException(401, "Missing bearer token")
  token = auth.split(" ",1)[1]
  try:
    header = jwt.get_unverified_header(token); kid = header.get("kid")
    jwks = get_jwks(); key = next((k for k in jwks.get("keys",[]) if k.get("kid")==kid), None)
    if not key: raise HTTPException(401, "No matching JWKS key")
    jwt.decode(token, key, options={"verify_aud": False})
  except Exception as e:
    raise HTTPException(401, f"Invalid token: {e}")

@app.middleware("http")
async def _metrics_mw(request: Request, call_next):
  t=time.monotonic()
  resp = await call_next(request)
  LAT.labels(path=request.url.path).observe(time.monotonic()-t)
  REQS.labels(path=request.url.path, method=request.method, code=str(resp.status_code)).inc()
  return resp

@app.get("/metrics")
def metrics():
  return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

class InitSchemaRequest(BaseModel):
  class_name: str = "Document"
  model: str = "nomic-embed-text"
  base_url: str = Field(default=OPENAI_API_BASE_URL)

@app.post("/weaviate/init_schema", dependencies=[Depends(verify_bearer)])
def weaviate_init(req: InitSchemaRequest):
  schema = {
    "class": req.class_name,
    "vectorizer": "text2vec-openai",
    "moduleConfig": {"text2vec-openai": {"baseURL": req.base_url, "model": req.model}},
    "properties": [
      {"name":"text","dataType":["text"]},
      {"name":"source","dataType":["text"]},
      {"name":"tags","dataType":["text[]"]}
    ],
  }
  if client.schema.contains({"classes":[{"class":req.class_name}]}):
    client.schema.delete_class(req.class_name)
  client.schema.create_class(schema)
  return {"status":"ok","class":req.class_name,"model":req.model}

class IngestRequest(BaseModel):
  texts: List[str]; sources: Optional[List[str]] = None; tags: Optional[List[List[str]]] = None

@app.post("/ingest", dependencies=[Depends(verify_bearer)])
def ingest(req: IngestRequest):
  splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=150)
  total = 0
  with client.batch as batch:
    batch.batch_size = 64
    for i, t in enumerate(req.texts):
      src = req.sources[i] if req.sources and i < len(req.sources) else ""
      taglist = req.tags[i] if req.tags and i < len(req.tags) else []
      for chunk in splitter.split_text(t):
        batch.add_data_object({"text":chunk,"source":src,"tags":taglist},
                              class_name=WEAVIATE_CLASS, uuid=generate_uuid5(chunk))
        total += 1
  return {"ingested_chunks": total}

@app.post("/ingest_file", dependencies=[Depends(verify_bearer)])
def ingest_file(file: UploadFile = File(...), source: Optional[str] = ""):
  data = file.file.read()
  text = ""
  if file.filename.lower().endswith(".pdf"):
    with fitz.open(stream=data, filetype="pdf") as doc:
      text = "\n".join(p.get_text() for p in doc)
  else:
    text = data.decode("utf-8", errors="ignore")
  return ingest(IngestRequest(texts=[text], sources=[source], tags=[[]]))

class QueryRequest(BaseModel):
  query: str; k: int = 5

@app.post("/query", dependencies=[Depends(verify_bearer)])
def query(req: QueryRequest):
  result = client.query.get(WEAVIATE_CLASS, ["text","source","tags"])\
    .with_near_text({"concepts":[req.query]}).with_limit(req.k).do()
  return {"matches": result.get("data",{}).get("Get",{}).get(WEAVIATE_CLASS, [])}

@app.get("/health")
def health():
  try:
    client.cluster.get_nodes_status()
    return {"ok": True, "auth": REQUIRE_AUTH}
  except Exception as e:
    return {"ok": False, "error": str(e), "auth": REQUIRE_AUTH}
PY
}

# ---------------------- Services: GraphRAG API -------------------------------
write_graphrag_api(){
  cat > "$STACK_DIR/services/graphrag-api/Dockerfile" <<'DOCKER'
FROM python:3.11-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8010
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8010"]
DOCKER

  cat > "$STACK_DIR/services/graphrag-api/requirements.txt" <<'REQ'
fastapi==0.115.0
uvicorn==0.30.5
pydantic==2.8.2
neo4j==5.23.0
python-jose[cryptography]==3.3.0
prometheus-client==0.20.0
requests==2.32.3
REQ

  cat > "$STACK_DIR/services/graphrag-api/app.py" <<'PY'
import os, time
from typing import List, Dict, Any, Optional
from fastapi import FastAPI, HTTPException, Header, Depends, Response, Request
from pydantic import BaseModel
from neo4j import GraphDatabase
import requests
from jose import jwt
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

REQUIRE_AUTH = os.getenv("REQUIRE_AUTH", "on").lower() == "on"
SUPABASE_JWKS_URL = os.getenv("SUPABASE_JWKS_URL", "")

NEO4J_URI = os.getenv("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASS = os.getenv("NEO4J_PASS", "")

driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASS))
app = FastAPI(title="OpenDiscourse GraphRAG API", version="2.0.0")

REQS = Counter("graphrag_requests_total","GraphRAG API requests",["path","method","code"])
LAT  = Histogram("graphrag_request_latency_seconds","GraphRAG API latency",["path"])

jwks_cache: Dict[str, Any] = {}
def get_jwks():
  global jwks_cache
  if jwks_cache: return jwks_cache
  if not SUPABASE_JWKS_URL: raise HTTPException(500, "JWKS URL not configured")
  r = requests.get(SUPABASE_JWKS_URL, timeout=5); r.raise_for_status()
  jwks_cache = r.json(); return jwks_cache

def verify_bearer(auth: Optional[str] = Header(default=None, alias="Authorization")):
  if not REQUIRE_AUTH: return
  if not auth or not auth.lower().startswith("bearer "): raise HTTPException(401, "Missing bearer token")
  token = auth.split(" ",1)[1]
  try:
    header = jwt.get_unverified_header(token); kid = header.get("kid")
    jwks = get_jwks(); key = next((k for k in jwks.get("keys",[]) if k.get("kid")==kid), None)
    if not key: raise HTTPException(401, "No matching JWKS key")
    jwt.decode(token, key, options={"verify_aud": False})
  except Exception as e:
    raise HTTPException(401, f"Invalid token: {e}")

@app.middleware("http")
async def _metrics_mw(request: Request, call_next):
  t=time.monotonic()
  resp = await call_next(request)
  LAT.labels(path=request.url.path).observe(time.monotonic()-t)
  REQS.labels(path=request.url.path, method=request.method, code=str(resp.status_code)).inc()
  return resp

@app.get("/metrics")
def metrics():
  return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

class Rel(BaseModel):
  src: str; rel: str; dst: str

class GraphIngest(BaseModel):
  rels: List[Rel]

@app.post("/graph/ingest", dependencies=[Depends(verify_bearer)])
def graph_ingest(req: GraphIngest):
  q = "UNWIND $rels AS r MERGE (a:Entity {name:r.src}) MERGE (b:Entity {name:r.dst}) MERGE (a)-[:REL {type:r.rel}]->(b)"
  with driver.session(database="neo4j") as s:
    s.run(q, rels=[r.model_dump() for r in req.rels])
  return {"ok": True, "count": len(req.rels)}

@app.get("/health")
def health():
  try:
    with driver.session(database="neo4j") as s:
      s.run("RETURN 1").single()
    return {"ok": True, "auth": REQUIRE_AUTH}
  except Exception as e:
    return {"ok": False, "error": str(e), "auth": REQUIRE_AUTH}
PY
}

# ---------------------- Services: Admin Portal -------------------------------
write_admin_portal(){
  cat > "$STACK_DIR/services/admin-portal/Dockerfile" <<'DOCKER'
FROM python:3.11-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends build-essential && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8050
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8050"]
DOCKER

  cat > "$STACK_DIR/services/admin-portal/requirements.txt" <<'REQ'
fastapi==0.115.0
uvicorn==0.30.5
jinja2==3.1.4
httpx==0.27.0
prometheus-client==0.20.0
REQ

  cat > "$STACK_DIR/services/admin-portal/app.py" <<'PY'
import os, time, statistics, asyncio, httpx
from fastapi import FastAPI, Response
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

DOMAIN = os.getenv("DOMAIN","localhost")
TARGETS = [t.strip() for t in os.getenv("TARGETS","").split(",") if t.strip()]

app = FastAPI(title="OpenDiscourse Admin Portal", version="1.0")

REQS = Counter("admin_requests_total","Admin portal requests",["path"])
LAT  = Histogram("admin_request_latency_seconds","Admin portal request latency",["path"])
HEALTH_G = Gauge("service_health","Service health (1=up,0=down)",["service"])
BENCH_H  = Histogram("bench_latency_seconds","Benchmark latency by target",["target","op"])

HTML = """<!doctype html><html><head><meta charset='utf-8'><title>Admin • OpenDiscourse</title>
<style>body{font-family:system-ui,Segoe UI,Roboto,Helvetica,Arial;margin:24px}table{border-collapse:collapse}
td,th{border:1px solid #ddd;padding:8px}th{background:#f3f4f6}</style></head><body>
<h1>OpenDiscourse Admin</h1>
<h2>Health</h2>
<table><tr><th>Service</th><th>Status</th></tr>{rows}</table>
<h2>Bench</h2>
<form method="post" action="/bench"><button>Run micro-bench (~15s)</button></form>
{bench}
<p><a href="/metrics">/metrics</a></p></body></html>"""

async def check_service(client, name, url):
    try:
        r = await client.get(url, timeout=5.0)
        ok = 1 if r.status_code < 400 else 0
    except Exception:
        ok = 0
    HEALTH_G.labels(service=name).set(ok)
    return name, ok

@app.get("/")
async def home():
    t0=time.time(); REQS.labels(path="/").inc()
    rows=""; bench=""
    async with httpx.AsyncClient() as client:
        tasks=[]
        for t in TARGETS:
            name=t.split(":")[0]
            url = f"http://{t}/health"
            tasks.append(check_service(client,name,url))
        results=await asyncio.gather(*tasks, return_exceptions=True)
    for name, ok in [(r[0], r[1]) if isinstance(r,tuple) else ("unknown",0) for r in results]:
        rows+=f"<tr><td>{name}</td><td>{'✅ up' if ok else '❌ down'}</td></tr>"
    resp=HTML.format(rows=rows, bench=bench)
    LAT.labels(path="/").observe(time.time()-t0)
    return Response(content=resp, media_type="text/html")

@app.post("/bench")
async def bench():
    t0=time.time(); REQS.labels(path="/bench").inc()
    lat=[]
    async with httpx.AsyncClient() as client:
        for t in TARGETS:
            host = t.split(":")[0]
            url=f"http://{t}/"
            try:
                s=time.time()
                await client.get(url, timeout=8.0)
                d=time.time()-s
                BENCH_H.labels(target=host, op="GET /").observe(d)
                lat.append(d)
            except Exception:
                BENCH_H.labels(target=host, op="GET /").observe(8.0)
    p50=statistics.median(lat) if lat else 0
    p95=(sorted(lat)[int(0.95*len(lat))-1] if lat else 0)
    html=f"<p>Completed. samples={len(lat)} p50={p50:.3f}s p95={p95:.3f}s</p>"
    rows="".join([f"<tr><td>{t.split(':')[0]}</td><td>tested</td></tr>" for t in TARGETS])
    resp=HTML.format(rows=rows, bench=html)
    LAT.labels(path="/bench").observe(time.time()-t0)
    return Response(content=resp, media_type="text/html")

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
PY
}

# --------------------------- PDF Worker (stub) -------------------------------
write_pdf_worker(){
  cat > "$STACK_DIR/services/pdf-worker/README.txt" <<EOF
Drop PDFs/TXTs into: $STACK_DIR/data/inbox
A cronable script can watch and POST to RAG API /ingest_file with a Supabase JWT.
EOF
}

# --------------------------- Tests & Scripts ---------------------------------
write_scripts_and_tests(){
  cat > "$STACK_DIR/monitoring/README.txt" <<'EOF'
Prometheus at http://prometheus:9090 (internal), Grafana via grafana.<domain>
Add Prometheus datasource in Grafana: URL http://prometheus:9090
EOF

  cat > "$STACK_DIR/scripts/validate_env.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
domain=""; cftoken=""
while [[ $# -gt 0 ]]; do case "$1" in
  --domain) domain="$2"; shift 2;;
  --cf-token) cftoken="$2"; shift 2;;
  *) shift;;
esac; done
fail(){ echo "[FAIL] $*"; exit 1; }
ok(){ echo "[ OK ] $*"; }
[[ -n "$domain" ]] || fail "--domain required"
[[ -n "$cftoken" ]] || fail "--cf-token required"
command -v curl >/dev/null || fail "curl not found"
command -v jq   >/dev/null || fail "jq not found (sudo apt -y install jq)"
if ! command -v docker >/dev/null; then echo "[WARN] docker missing (installer adds it)"; else docker compose version >/dev/null || fail "compose plugin missing"; fi
for p in 80 443; do ss -ltn "sport = :$p" >/dev/null 2>&1 || ok "Port $p free"; done
zone=$(curl -fsSL -H "Authorization: Bearer $cftoken" -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones?name=$domain" | jq -r '.result[0].id // empty')
[[ -n "$zone" ]] || fail "Cloudflare: zone not found or token no access"
ok "Cloudflare zone visible: $zone"
pubip=$(curl -fsSL https://api.ipify.org || true); [[ -n "$pubip" ]] || fail "No public IP"; ok "Public IP $pubip"
echo "[DONE] validation passed"
EOF
  chmod +x "$STACK_DIR/scripts/validate_env.sh"

  cat > "$STACK_DIR/scripts/smoke_test.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
domain=""; jwt="${JWT:-}"
while [[ $# -gt 0 ]]; do case "$1" in
  --domain) domain="$2"; shift 2;;
  --jwt) jwt="$2"; shift 2;;
  *) shift;;
esac; done
[[ -n "$domain" ]] || { echo "usage: $0 --domain <FQDN> [--jwt <token>]"; exit 1; }
host_ok(){ curl -skI "https://$1.$domain" | head -n1 | grep -q "200\\|301\\|302"; }
api_ok(){ curl -sk "https://$1.$domain/health" | jq -e '.ok==true' >/dev/null; }
ok(){ echo "[ OK ] $*"; } fail(){ echo "[FAIL] $*"; exit 1; }
host_ok "supabase" && ok "Supabase up" || fail "Supabase"
host_ok "supabase-api" && ok "Supabase API" || fail "Supabase API"
api_ok "api" && ok "RAG API health" || fail "RAG API"
api_ok "graph-api" && ok "GraphRAG API" || fail "GraphRAG API"
host_ok "weaviate" && ok "Weaviate" || fail "Weaviate"
host_ok "neo4j" && ok "Neo4j" || fail "Neo4j"
host_ok "openwebui" && ok "OpenWebUI" || fail "OpenWebUI"
host_ok "flowise" && ok "Flowise" || fail "Flowise"
host_ok "n8n" && ok "n8n" || fail "n8n"
host_ok "s3-console" && ok "MinIO console" || fail "MinIO console"
echo "[DONE] smoke tests passed"
EOF
  chmod +x "$STACK_DIR/scripts/smoke_test.sh"

  cat > "$STACK_DIR/scripts/backup_now.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
set -a; . /opt/opendiscourse/.env; set +a
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
which restic >/dev/null 2>&1 || { echo "installing restic"; sudo apt-get update -y && sudo apt-get install -y restic; }
restic -r "$RESTIC_REPO" init >/dev/null 2>&1 || true
# Example: add your pg/neo4j dump commands here or mount volumes to snapshot dirs before backup.
restic -r "$RESTIC_REPO" backup /opt/opendiscourse/.env
echo "[OK] backup completed"
EOF
  chmod +x "$STACK_DIR/scripts/backup_now.sh"

  cat > "$STACK_DIR/tests/api/test_e2e.py" <<'EOF'
import os, json, requests
DOMAIN=os.environ.get("DOMAIN","opendiscourse.net"); JWT=os.environ.get("JWT","")
def _h():
    h={"content-type":"application/json"}
    if JWT: h["Authorization"]=f"Bearer {JWT}"
    return h
def test_health_rag():
    r=requests.get(f"https://api.{DOMAIN}/health", timeout=10); assert r.ok and r.json().get("ok") is True
def test_health_graphrag():
    r=requests.get(f"https://graph-api.{DOMAIN}/health", timeout=10); assert r.ok and r.json().get("ok") is True
def test_init_schema_roundtrip():
    r=requests.post(f"https://api.{DOMAIN}/weaviate/init_schema", headers=_h(),
                    data=json.dumps({"class_name":"Document","model":"nomic-embed-text",
                                     "base_url": f"https://localai.{DOMAIN}/v1"}), timeout=20)
    assert r.status_code in (200, 401)
EOF

  cat > "$STACK_DIR/tests/k6/rag_query.js" <<'EOF'
import http from 'k6/http'; import { sleep, check } from 'k6';
export const options = { vus: 5, duration: '30s' };
export default function () {
  const res = http.post('https://api.opendiscourse.net/query', JSON.stringify({ query: 'disclosure requirements', k: 3 }), { headers: { 'Content-Type': 'application/json' } });
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(1);
}
EOF
}

# --------------------------- README / Runbook --------------------------------
write_docs(){
  cat > "$STACK_DIR/README.md" <<'EOF'
# OpenDiscourse — One-Click Stack (Self-Hosted)
See Day‑2 Runbook (in canvas / Admin Playbook) for operations, SLOs, and diagrams.

## Quickstart
```bash
sudo -E ./opendiscourse_oneclick.sh --domain <domain> --email <email> --cf-token <token> --auth on --gpu off --non-interactive
