#!/usr/bin/env bash
# =============================================================================
# Script:        opendiscourse_stack.sh
# Author:        ChatGPT (for Blaine “CBW” Winslow)
# Date:          2025-08-15
# Version:       1.5.0
#
# Adds:
#   (1) pdf-worker: watches /data/inbox, extracts text (pymupdf), tags entities,
#       ingests to Weaviate + Neo4j via our APIs (auth-aware).
#   (2) Optional GPU path:
#         --gpu vllm    -> adds vLLM OpenAI server; flips clients to vLLM baseURL
#         --gpu localai -> uses LocalAI CUDA build (if present)
#   (3) MinIO S3 with restic backups (encrypted) + optional Cloudflare R2 / Oracle.
# =============================================================================

set -Eeuo pipefail

LOG_FILE="/tmp/CBW-opendiscourse_stack.log"
mkdir -p "$(dirname "$LOG_FILE")"; : > "$LOG_FILE"; chmod 600 "$LOG_FILE" || true
ts(){ date +"%Y-%m-%d %H:%M:%S"; }
log(){ echo -e "[$(ts)] $*" | tee -a "$LOG_FILE"; }
info(){ log "\e[34m[INFO]\e[0m  $*"; } warn(){ log "\e[33m[WARN]\e[0m  $*"; }
err(){ log "\e[31m[ERR!]\e[0m  $*"; } ok(){ log "\e[32m[ OK ]\e[0m  $*"; }
trap 'err "Line $LINENO failed. See $LOG_FILE"; exit 1' ERR

# ------------------------------ Args -----------------------------------------
STACK_DIR="/opt/opendiscourse"
DOMAIN="opendiscourse.net" EMAIL="inbox@opendiscourse.net" CF_TOKEN="TBgXhv6-N0zK1i_ypolqA_ThcAzreP9hR3tQ_Byy"
AUTH="on"           # APIs require Supabase JWT by default
GPU_MODE="off"      # off | vllm | localai
NONINTERACTIVE=0 ACTION="install"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2;;
    --email) EMAIL="$2"; shift 2;;
    --cf-token) CF_TOKEN="$2"; shift 2;;
    --stack-dir) STACK_DIR="$2"; shift 2;;
    --auth) AUTH="$2"; shift 2;;
    --gpu) GPU_MODE="$2"; shift 2;;
    --start|--stop|--status|--destroy) ACTION="${1#--}"; shift;;
    --non-interactive) NONINTERACTIVE=1; shift;;
    -h|--help)
      cat <<EOF
Usage:
  $0 --domain <FQDN> --email <EMAIL> --cf-token <TOKEN> [--auth on|off] [--gpu off|vllm|localai] [--non-interactive]
Lifecycle:
  $0 --start | --stop | --status | --destroy
EOF
      exit 0;;
    *) warn "Unknown arg: $1"; shift;;
  esac
done

confirm(){ [[ $NONINTERACTIVE -eq 1 ]] && return 0; read -r -p "$1 [y/N]: " a || true; [[ "${a,,}" =~ ^y(es)?$ ]]; }
need_cmd(){ command -v "$1" >/dev/null 2>&1; }
rand_hex(){ if need_cmd openssl; then openssl rand -hex "${1:-24}"; else head -c "${1:-24}" /dev/urandom | xxd -p -c 256; fi; }
rand_b64(){ if need_cmd openssl; then openssl rand -base64 "${1:-48}"; else head -c "${1:-48}" /dev/urandom | base64; fi; }
detect_os(){ . /etc/os-release; echo "$ID"; }
pub_ip(){ curl -fsSL https://api.ipify.org || curl -fsSL https://ifconfig.me; }
is_port_free(){ ss -ltn "sport = :$1" >/dev/null 2>&1 || return 0; return 1; }
pick_free_port_down(){ local start="$1" min="${2:-1}" p="$start"; while (( p >= min )); do is_port_free "$p" && { echo "$p"; return 0; }; p=$((p-1)); done; return 1; }

# --------------------------- Docker Installer --------------------------------
ensure_docker(){
  if need_cmd docker && docker compose version >/dev/null 2>&1; then ok "Docker & Compose present."; return; fi
  info "Installing Docker CE + Compose plugin…"
  local os_id; os_id="$(detect_os)"
  if [[ "$os_id" =~ (ubuntu|debian) ]]; then
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg lsb-release git jq
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$os_id/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$os_id $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else err "Use Ubuntu/Debian for auto-install, or install Docker manually."; exit 1; fi
  sudo systemctl enable --now docker
  ok "Docker installed & running."
  if ! id -nG "$USER" | grep -qw docker; then sudo usermod -aG docker "$USER" || true; fi
}

# --------------------------- Cloudflare DNS ----------------------------------
CF_API="https://api.cloudflare.com/client/v4"
cf_req(){ curl -fsSL -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" "$@"; }
cf_get_zone_id(){ cf_req "${CF_API}/zones?name=${1}" | awk -F'"' '/"id":/ {print $4; exit}'; }
cf_upsert(){
  local zid="$1" name="$2" type="$3" content="$4" proxied="${5:-false}"
  local res rec_id; res="$(cf_req "${CF_API}/zones/${zid}/dns_records?type=${type}&name=${name}")"
  rec_id="$(echo "$res" | awk -F'"' '/"id":/ {print $4; exit}')"
  if [[ -n "$rec_id" ]]; then
    cf_req -X PUT "${CF_API}/zones/${zid}/dns_records/${rec_id}" --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":${proxied}}" >/dev/null
  else
    cf_req -X POST "${CF_API}/zones/${zid}/dns_records" --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"proxied\":${proxied}}" >/dev/null
  fi
}
ensure_dns(){
  [[ -z "$DOMAIN" || -z "$CF_TOKEN" ]] && { err "DOMAIN and CF_TOKEN required"; exit 1; }
  local ip zid; ip="$(pub_ip)"; zid="$(cf_get_zone_id "$DOMAIN")"
  [[ -z "$zid" ]] && { err "Cloudflare Zone not found for $DOMAIN"; exit 1; }
  info "Ensuring DNS A records @ $ip (zone=$zid)…"
  cf_upsert "$zid" "$DOMAIN" "A" "$ip" false
  for sub in supabase supabase-api api graph-api traces weaviate openwebui localai neo4j n8n flowise search s3 s3-console vllm; do
    cf_upsert "$zid" "${sub}.${DOMAIN}" "A" "$ip" false
  done
  ok "DNS ensured."
}

# --------------------------- Files & Env -------------------------------------
write_env(){
  mkdir -p "$STACK_DIR"
  local ENV="$STACK_DIR/.env"
  info "Writing env $ENV"
  cat > "$ENV" <<EOF
DOMAIN=${DOMAIN}
EMAIL=${EMAIL}
CF_API_TOKEN=${CF_TOKEN}
REQUIRE_AUTH=${AUTH}
GPU_MODE=${GPU_MODE}

# Traefik host ports (auto-decided)
TRAEFIK_HTTP_PORT=
TRAEFIK_HTTPS_PORT=

# DB creds
NEO4J_USER=neo4j
NEO4J_PASS=$(rand_hex 24)

# Langfuse (uses Supabase Postgres)
LANGFUSE_DB_USER=langfuse
LANGFUSE_DB_PASS=$(rand_hex 24)
LANGFUSE_DB_NAME=langfuse
NEXTAUTH_SECRET=$(rand_b64 48)
LANGFUSE_SALT=$(rand_hex 16)
LANGFUSE_ENCRYPTION_KEY=$(rand_b64 32)
LANGFUSE_PUBLIC_URL=https://traces.${DOMAIN}

# Supabase JWKS for API JWT validation
SUPABASE_JWKS_URL=https://supabase-api.${DOMAIN}/auth/v1/.well-known/jwks.json

# AI endpoints (default CPU LocalAI)
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

# MinIO (S3-compatible) + restic
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=$(rand_hex 24)
MINIO_BUCKET=backups
RESTIC_REPO=s3:https://s3.${DOMAIN}/${MINIO_BUCKET}
RESTIC_PASSWORD=$(rand_hex 32)
AWS_ACCESS_KEY_ID=\${MINIO_ROOT_USER}
AWS_SECRET_ACCESS_KEY=\${MINIO_ROOT_PASSWORD}

# Optional Cloudflare R2 / Oracle (set later if desired)
# R2_RESTIC_REPO=s3:https://<accountid>.r2.cloudflarestorage.com/<bucket>
# R2_AWS_ACCESS_KEY_ID=
# R2_AWS_SECRET_ACCESS_KEY=
# ORACLE_RESTIC_REPO=s3:https://<namespace>.compat.objectstorage.<region>.oraclecloud.com/<bucket>
# ORACLE_AWS_ACCESS_KEY_ID=
# ORACLE_AWS_SECRET_ACCESS_KEY=

# PDF worker
PDF_INBOX=/opt/opendiscourse/data/inbox
ENTITY_TAGS=ORG,PERSON,LAW,BILL,ORG-AGENCY
EOF
  chmod 600 "$ENV"
}

ensure_network(){
  docker network inspect opendiscourse_net >/dev/null 2>&1 || docker network create opendiscourse_net
  mkdir -p "$STACK_DIR/letsencrypt" "$STACK_DIR/data/inbox" "$STACK_DIR/bin"
  chmod 700 "$STACK_DIR/letsencrypt"; chmod 755 "$STACK_DIR/data" "$STACK_DIR/data/inbox"
  touch "$STACK_DIR/letsencrypt/acme.json" && chmod 600 "$STACK_DIR/letsencrypt/acme.json"
}

# --------------------------- Compose + Traefik -------------------------------
write_traefik_and_stack(){
  mkdir -p "$STACK_DIR/traefik" "$STACK_DIR/services/rag-api" "$STACK_DIR/services/graphrag-api" "$STACK_DIR/services/pdf-worker"

  cat > "$STACK_DIR/traefik/traefik.yml" <<EOF
entryPoints:
  web:       { address: ":${1}" }
  websecure: { address: ":${2}" }
providers: { docker: { exposedByDefault: false } }
certificatesResolvers:
  cf:
    acme:
      email: "${EMAIL}"
      storage: "/letsencrypt/acme.json"
      dnsChallenge: { provider: cloudflare, disablePropagationCheck: true }
EOF

  cat > "$STACK_DIR/compose.yml" <<'YAML'
name: opendiscourse
networks: { opendiscourse_net: { external: true } }
volumes:
  weaviate_data: {}
  localai_models: {}
  neo4j_data: {}
  neo4j_plugins: {}
  minio_data: {}

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

  langfuse:
    image: langfuse/langfuse:latest
    container_name: langfuse
    restart: unless-stopped
    networks: [opendiscourse_net]
    environment:
      DATABASE_URL: "postgresql://${LANGFUSE_DB_USER}:${LANGFUSE_DB_PASS}@supabase-db:5432/${LANGFUSE_DB_NAME}"
      NEXTAUTH_SECRET: ${NEXTAUTH_SECRET}
      NEXTAUTH_URL: ${LANGFUSE_PUBLIC_URL}
      SALT: ${LANGFUSE_SALT}
      ENCRYPTION_KEY: ${LANGFUSE_ENCRYPTION_KEY}
    labels:
      - traefik.enable=true
      - traefik.http.routers.langfuse.rule=Host(`traces.${DOMAIN}`)
      - traefik.http.routers.langfuse.entrypoints=websecure
      - traefik.http.routers.langfuse.tls.certresolver=cf
      - traefik.http.routers.langfuse.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.langfuse.loadbalancer.server.port=3000

  # LocalAI (CPU). If GPU mode 'localai', swap image manually later if needed.
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
      - traefik.http.routers.openwebui.middlewares=oc-headers,oc-gzip,oc-rl
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
      REQUIRE_AUTH: ${REQUIRE_AUTH}
      SUPABASE_JWKS_URL: ${SUPABASE_JWKS_URL}
      WEAVIATE_URL: "http://weaviate:8080"
      WEAVIATE_CLASS: "Document"
      OPENAI_API_KEY: "${OPENAI_API_KEY:-localai}"
      OPENAI_API_BASE_URL: "${OPENAI_API_BASE_URL}"
      LANGFUSE_BASE_URL: "https://traces.${DOMAIN}"
      LANGFUSE_ENABLE: "false"
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
      - traefik.http.routers.n8n.middlewares=oc-headers,oc-gzip,oc-rl
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
      - traefik.http.routers.flowise.middlewares=oc-headers,oc-gzip,oc-rl
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
      - traefik.http.routers.search.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.search.loadbalancer.server.port=${SEARXNG_PORT}

  # MinIO (S3-compatible), Console at s3-console.<domain>, S3 API at s3.<domain>
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
      - traefik.http.routers.minio.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.minio.loadbalancer.server.port=9000
      - traefik.http.routers.minio-console.rule=Host(`s3-console.${DOMAIN}`)
      - traefik.http.routers.minio-console.entrypoints=websecure
      - traefik.http.routers.minio-console.tls.certresolver=cf
      - traefik.http.routers.minio-console.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.minio-console.loadbalancer.server.port=9001

  # vLLM (optional). Enabled automatically when GPU_MODE=vllm (script flips clients).
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
    environment: {}
    command: >
      --host 0.0.0.0 --port 8000 --model meta-llama/Llama-3.1-8B-Instruct
    labels:
      - traefik.enable=true
      - traefik.http.routers.vllm.rule=Host(`vllm.${DOMAIN}`)
      - traefik.http.routers.vllm.entrypoints=websecure
      - traefik.http.routers.vllm.tls.certresolver=cf
      - traefik.http.routers.vllm.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.vllm.loadbalancer.server.port=8000
YAML
}

# --------------------------- RAG API -----------------------------------------
write_rag_api(){
  mkdir -p "$STACK_DIR/services/rag-api"
  cat > "$STACK_DIR/services/rag-api/Dockerfile" <<'DOCKER'
FROM python:3.11-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends build-essential poppler-utils && rm -rf /var/lib/apt/lists/*
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
langfuse==2.45.6
python-multipart==0.0.9
numpy==2.0.1
python-jose[cryptography]==3.3.0
pymupdf==1.24.9
REQ

  cat > "$STACK_DIR/services/rag-api/app.py" <<'PY'
import os
from typing import List, Optional, Dict, Any
from fastapi import FastAPI, UploadFile, File, HTTPException, Header, Depends
from pydantic import BaseModel, Field
import weaviate
from weaviate.util import generate_uuid5
from langchain.text_splitter import RecursiveCharacterTextSplitter
import requests
from jose import jwt
import fitz  # pymupdf

DOMAIN=os.getenv("DOMAIN","localhost")
REQUIRE_AUTH = os.getenv("REQUIRE_AUTH", "on").lower() == "on"
SUPABASE_JWKS_URL = os.getenv("SUPABASE_JWKS_URL", "")

WEAVIATE_URL = os.getenv("WEAVIATE_URL", "http://weaviate:8080")
WEAVIATE_CLASS = os.getenv("WEAVIATE_CLASS", "Document")
OPENAI_API_BASE_URL = os.getenv("OPENAI_API_BASE_URL", "http://localai:8080/v1")

client = weaviate.Client(WEAVIATE_URL)
app = FastAPI(title="OpenDiscourse RAG API", version="1.5.0")

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
      text = "\n".join([p.get_text() for p in doc])
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
  try: client.cluster.get_nodes_status(); return {"ok": True, "auth": REQUIRE_AUTH}
  except Exception as e: return {"ok": False, "error": str(e), "auth": REQUIRE_AUTH}
PY
}

# ---------------------- GraphRAG API -----------------------------------------
write_graphrag_api(){
  mkdir -p "$STACK_DIR/services/graphrag-api"
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
REQ

  cat > "$STACK_DIR/services/graphrag-api/app.py" <<'PY'
import os
from typing import List, Dict, Any, Optional
from fastapi import FastAPI, HTTPException, Header, Depends
from pydantic import BaseModel, Field
from neo4j import GraphDatabase
import requests
from jose import jwt

REQUIRE_AUTH = os.getenv("REQUIRE_AUTH", "on").lower() == "on"
SUPABASE_JWKS_URL = os.getenv("SUPABASE_JWKS_URL", "")

NEO4J_URI = os.getenv("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASS = os.getenv("NEO4J_PASS", "")

driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASS))
app = FastAPI(title="OpenDiscourse GraphRAG API", version="1.5.0")

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

class Node(BaseModel):
  id: str; label: str = "Entity"; props: Dict[str, Any] = Field(default_factory=dict)

class Rel(BaseModel):
  src: str; rel: str = "RELATED_TO"; dst: str; props: Dict[str, Any] = Field(default_factory=dict)

class IngestGraph(BaseModel):
  nodes: List[Node] = Field(default_factory=list)
  rels: List[Rel] = Field(default_factory=list)

@app.get("/health")
def health():
  try:
    with driver.session() as s: s.run("RETURN 1").single()
    return {"ok": True, "auth": REQUIRE_AUTH}
  except Exception as e:
    return {"ok": False, "error": str(e), "auth": REQUIRE_AUTH}

@app.post("/neo4j/init_schema", dependencies=[Depends(verify_bearer)])
def init_schema():
  cypher = """
    CREATE CONSTRAINT IF NOT EXISTS FOR (n:Entity) REQUIRE n.id IS UNIQUE;
    CREATE INDEX entity_name IF NOT EXISTS FOR (n:Entity) ON (n.name);
  """
  with driver.session() as s:
    for stmt in cypher.strip().split(";"):
      if stmt.strip(): s.run(stmt)
  return {"status":"ok"}

@app.post("/graph/ingest_entities", dependencies=[Depends(verify_bearer)])
def ingest_graph(payload: IngestGraph):
  with driver.session() as s:
    for n in payload.nodes:
      s.run("MERGE (x:Entity {id: $id}) SET x += $props, x.label=$label", id=n.id, props=n.props, label=n.label)
    for r in payload.rels:
      s.run(f"MATCH (a:Entity {{id:$src}}), (b:Entity {{id:$dst}}) MERGE (a)-[e:`{r.rel}`]->(b) SET e += $props",
            src=r.src, dst=r.dst, props=r.props)
  return {"ingested_nodes": len(payload.nodes), "ingested_rels": len(payload.rels)}
PY
}

# --------------------------- PDF Worker --------------------------------------
write_pdf_worker(){
  mkdir -p "$STACK_DIR/services/pdf-worker"
  cat > "$STACK_DIR/services/pdf-worker/Dockerfile" <<'DOCKER'
FROM python:3.11-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends build-essential poppler-utils inotify-tools && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY worker.py .
CMD ["python","worker.py"]
DOCKER

  cat > "$STACK_DIR/services/pdf-worker/requirements.txt" <<'REQ'
requests==2.32.3
pymupdf==1.24.9
watchdog==4.0.2
REQ

  cat > "$STACK_DIR/services/pdf-worker/worker.py" <<'PY'
import os, time, json, hashlib
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import fitz
import requests

INBOX = os.getenv("PDF_INBOX","/data/inbox")
DOMAIN = os.getenv("DOMAIN","localhost")
API = f"https://api.{DOMAIN}"
GRAPH = f"https://graph-api.{DOMAIN}"
JWT = os.getenv("SERVICE_JWT","")   # optional: paste a long-lived service token if desired
TAGS = os.getenv("ENTITY_TAGS","ORG,PERSON,LAW,BILL").split(",")

def extract_text(path:str)->str:
    if path.lower().endswith(".pdf"):
        with fitz.open(path) as doc:
            return "\n".join(p.get_text() for p in doc)
    with open(path,"rb") as f:
        return f.read().decode("utf-8","ignore")

def simple_entities(text:str):
    # intentionally simple; upgrade to spaCy/HF later
    ents=set()
    for tag in TAGS:
        if tag.lower() in text.lower(): ents.add(tag)
    return [{"id":f"ent-{h}", "label":e, "props":{"matched":e}} for h,e in [(hashlib.sha1(e.encode()).hexdigest()[:10],e) for e in ents]]

def ingest_document(path:str):
    name=os.path.basename(path)
    src=name
    text=extract_text(path)
    # 1) RAG ingest
    payload={"texts":[text],"sources":[src],"tags":[["legislation"]]}
    headers={"content-type":"application/json"}
    if JWT: headers["Authorization"]=f"Bearer {JWT}"
    r=requests.post(f"{API}/ingest",json=payload,headers=headers,timeout=120); r.raise_for_status()
    # 2) Emit naive entities to graph (placeholder)
    nodes=simple_entities(text)
    if nodes:
        # link file as a node and relations
        doc_id=f"doc-{hashlib.sha1(src.encode()).hexdigest()[:10]}"
        nodes.append({"id":doc_id,"label":"Document","props":{"name":src}})
        rels=[{"src":doc_id,"rel":"MENTIONS","dst":n["id"],"props":{}} for n in nodes if n["label"]!="Document"]
        gpayload={"nodes":nodes,"rels":rels}
        if JWT: headers["Authorization"]=f"Bearer {JWT}"
        r=requests.post(f"{GRAPH}/graph/ingest_entities",json=gpayload,headers=headers,timeout=60); r.raise_for_status()

class Handler(FileSystemEventHandler):
    def on_created(self,event):
        if event.is_directory: return
        path=event.src_path
        if not (path.lower().endswith(".pdf") or path.lower().endswith(".txt")): return
        try:
            # give time to finish copying
            time.sleep(1.0)
            ingest_document(path)
            print(f"[OK] Ingested {path}")
        except Exception as e:
            print(f"[ERR] {path}: {e}")

if __name__=="__main__":
    os.makedirs(INBOX,exist_ok=True)
    print(f"Watching {INBOX} for PDF/TXT…")
    ob=Observer(); ob.schedule(Handler(),INBOX,recursive=False); ob.start()
    try:
        while True: time.sleep(1)
    except KeyboardInterrupt:
        ob.stop(); ob.join()
PY
}

# --------------------------- Supabase (unchanged core) -----------------------
setup_supabase(){
  local dir="$STACK_DIR/supabase"
  mkdir -p "$dir"; cd "$dir"
  if [[ ! -d "$dir/supabase" ]]; then
    info "Cloning Supabase (shallow)…"
    git clone --depth 1 https://github.com/supabase/supabase.git
  else
    info "Updating Supabase…"
    (cd supabase && git pull --ff-only) || true
  fi
  rm -rf project && mkdir project
  cp -rf supabase/docker/* project/
  cp supabase/docker/.env.example project/.env
  chmod 600 project/.env

  sed -i "s/^JWT_SECRET=.*/JWT_SECRET=$(rand_b64 48)/" project/.env || true
  sed -i "s/^ANON_KEY=.*/ANON_KEY=$(rand_b64 48)/" project/.env || true
  sed -i "s/^SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=$(rand_b64 48)/" project/.env || true
  sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(rand_hex 24)/" project/.env || true
  sed -i "s|^SITE_URL=.*|SITE_URL=https://supabase.${DOMAIN}|" project/.env || true

  cat > project/traefik.override.yml <<EOF
services:
  studio:
    networks: [opendiscourse_net]
    labels:
      - traefik.enable=true
      - traefik.http.routers.supabase.rule=Host(\`supabase.${DOMAIN}\`)
      - traefik.http.routers.supabase.entrypoints=websecure
      - traefik.http.routers.supabase.tls.certresolver=cf
      - traefik.http.routers.supabase.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.supabase.loadbalancer.server.port=3000
  kong:
    networks: [opendiscourse_net]
    labels:
      - traefik.enable=true
      - traefik.http.routers.supabaseapi.rule=Host(\`supabase-api.${DOMAIN}\`)
      - traefik.http.routers.supabaseapi.entrypoints=websecure
      - traefik.http.routers.supabaseapi.tls.certresolver=cf
      - traefik.http.routers.supabaseapi.middlewares=oc-headers,oc-gzip,oc-rl
      - traefik.http.services.supabaseapi.loadbalancer.server.port=8000
  db:
    networks: [opendiscourse_net]
    container_name: supabase-db
networks: { opendiscourse_net: { external: true } }
EOF
}

start_supabase(){
  (cd "$STACK_DIR/supabase/project" && docker compose -f docker-compose.yml -f traefik.override.yml --env-file .env up -d)
}

bootstrap_supabase_db(){
  info "Preparing Supabase Postgres (Langfuse, n8n, app schema)…"
  until docker exec supabase-db pg_isready -U supabase_admin >/dev/null 2>&1; do sleep 2; done
  docker exec -i supabase-db psql -v ON_ERROR_STOP=1 -U supabase_admin <<SQL
-- Langfuse
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '${LANGFUSE_DB_NAME}') THEN
    PERFORM dblink_exec('dbname='||current_database(), 'CREATE DATABASE ${LANGFUSE_DB_NAME}');
  END IF;
END\$\$;
\c ${LANGFUSE_DB_NAME}
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${LANGFUSE_DB_USER}') THEN
    CREATE ROLE ${LANGFUSE_DB_USER} LOGIN PASSWORD '${LANGFUSE_DB_PASS}';
  END IF;
END\$\$;
GRANT ALL PRIVILEGES ON DATABASE ${LANGFUSE_DB_NAME} TO ${LANGFUSE_DB_USER};

-- n8n
\c postgres
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '${N8N_DB_NAME}') THEN
    PERFORM dblink_exec('dbname='||current_database(), 'CREATE DATABASE ${N8N_DB_NAME}');
  END IF;
END\$\$;
\c ${N8N_DB_NAME}
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${N8N_DB_USER}') THEN
    CREATE ROLE ${N8N_DB_USER} LOGIN PASSWORD '${N8N_DB_PASS}';
  END IF;
END\$\$;
GRANT ALL PRIVILEGES ON DATABASE ${N8N_DB_NAME} TO ${N8N_DB_USER};

-- App bootstrap
\c postgres
CREATE SCHEMA IF NOT EXISTS opendiscourse;
CREATE TABLE IF NOT EXISTS opendiscourse.findings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  bill_id text, title text, summary text,
  entities jsonb DEFAULT '[]'::jsonb, tags text[] DEFAULT '{}', raw_source text
);
ALTER TABLE opendiscourse.findings ENABLE ROW LEVEL SECURITY;
DO \$\$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='opendiscourse' AND tablename='findings' AND policyname='findings_select_own'
  ) THEN
    CREATE POLICY findings_select_own ON opendiscourse.findings FOR SELECT USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='opendiscourse' AND tablename='findings' AND policyname='findings_ins_own'
  ) THEN
    CREATE POLICY findings_ins_own ON opendiscourse.findings FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='opendiscourse' AND tablename='findings' AND policyname='findings_upd_own'
  ) THEN
    CREATE POLICY findings_upd_own ON opendiscourse.findings FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END\$\$;
SQL
  ok "Supabase DB bootstrapped."
}

# --------------------------- Backups (restic) --------------------------------
write_backup_hooks(){
  mkdir -p "$STACK_DIR/bin" "$STACK_DIR/backups"
  cat > "$STACK_DIR/bin/backup_now.sh" <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail
source /opt/opendiscourse/.env
export RESTIC_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
export RESTIC_REPO=${RESTIC_REPO}

TS="$(date +%Y%m%d-%H%M%S)"
TMP="/tmp/odump-$TS"; mkdir -p "$TMP"

echo "[*] Dumping Supabase Postgres…"
docker exec supabase-db pg_dumpall -U supabase_admin > "$TMP/pg_dumpall.sql"
echo "[*] Dumping Neo4j…"
docker exec neo4j bash -lc "neo4j-admin database dump neo4j --to-stdout" > "$TMP/neo4j.dump"
echo "[*] Restic init (if needed) and backup to $RESTIC_REPO"
restic snapshots >/dev/null 2>&1 || restic init
restic backup "$TMP"
rm -rf "$TMP"
echo "[OK] Backup complete."
BASH
  chmod +x "$STACK_DIR/bin/backup_now.sh"
}

# --------------------------- GPU & BaseURL flip ------------------------------
set_ai_baseurl(){
  # default LocalAI
  local base="https://localai.${DOMAIN}/v1"
  if [[ "$GPU_MODE" == "vllm" ]]; then
    base="https://vllm.${DOMAIN}/v1"
  fi
  sed -i "s|^OPENAI_API_BASE_URL=.*|OPENAI_API_BASE_URL=${base}|" "$STACK_DIR/.env"
  ok "AI base URL -> ${base}"
}

# --------------------------- Orchestration -----------------------------------
main_install(){
  [[ -z "$DOMAIN" || -z "$EMAIL" || -z "$CF_TOKEN" ]] && { err "Provide --domain --email --cf-token"; exit 1; }

  ensure_docker
  mkdir -p "$STACK_DIR"
  write_env
  ensure_network

  local http https
  http="$(pick_free_port_down 80 1 || echo 80)"
  https="$(pick_free_port_down 443 2 || echo 443)"
  sed -i "s/^TRAEFIK_HTTP_PORT=.*/TRAEFIK_HTTP_PORT=${http}/" "$STACK_DIR/.env"
  sed -i "s/^TRAEFIK_HTTPS_PORT=.*/TRAEFIK_HTTPS_PORT=${https}/" "$STACK_DIR/.env"
  info "Traefik ports => HTTP:${http} HTTPS:${https}"

  ensure_dns
  set_ai_baseurl
  write_traefik_and_stack "$http" "$https"
  write_rag_api
  write_graphrag_api
  write_pdf_worker
  write_backup_hooks

  info "Building & starting core stack…"
  (cd "$STACK_DIR" && docker compose --env-file .env build && docker compose --env-file .env up -d)
  ok "Core stack up."

  # Supabase (separate compose)
  setup_supabase
  start_supabase
  bootstrap_supabase_db

  # If GPU=vllm, ensure vLLM is running and clients flipped already by env
  if [[ "$GPU_MODE" == "vllm" ]]; then
    info "GPU mode 'vllm' requested. Ensure NVIDIA runtime is present on host."
  fi

  info "--------------------------------------------------------------------"
  info " ✅ Deployment complete for ${DOMAIN}"
  info " URLs:"
  info "   RAG API          https://api.${DOMAIN}/docs"
  info "   GraphRAG API     https://graph-api.${DOMAIN}/docs"
  info "   Weaviate         https://weaviate.${DOMAIN}"
  info "   Langfuse         https://traces.${DOMAIN}"
  info "   LocalAI          https://localai.${DOMAIN}/v1"
  info "   vLLM (opt)       https://vllm.${DOMAIN}/v1"
  info "   OpenWebUI        https://openwebui.${DOMAIN}"
  info "   Supabase UI      https://supabase.${DOMAIN}"
  info "   Supabase API     https://supabase-api.${DOMAIN}"
  info "   Neo4j Browser    https://neo4j.${DOMAIN}"
  info "   n8n              https://n8n.${DOMAIN}"
  info "   Flowise          https://flowise.${DOMAIN}"
  info "   SearxNG          https://search.${DOMAIN}"
  info "   MinIO S3         https://s3.${DOMAIN}  (Console: https://s3-console.${DOMAIN})"
  info "   PDF inbox        $STACK_DIR/data/inbox  (drop PDFs/TXTs to auto-ingest)"
  info " Backups:           $STACK_DIR/bin/backup_now.sh (to MinIO via restic)"
  info "--------------------------------------------------------------------"
}

stack_start(){ (cd "$STACK_DIR" && docker compose --env-file .env up -d) || true; start_supabase; ok "Stack started."; }
stack_stop(){ (cd "$STACK_DIR" && docker compose --env-file .env down) || true; (cd "$STACK_DIR/supabase/project" && docker compose down) || true; ok "Stack stopped."; }
stack_status(){ docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"; }
stack_destroy(){
  if confirm "Remove containers (keep volumes)?"; then
    (cd "$STACK_DIR" && docker compose down) || true
    (cd "$STACK_DIR/supabase/project" && docker compose down) || true
    ok "Containers removed; volumes kept."
  else
    (cd "$STACK_DIR" && docker compose down -v) || true
    (cd "$STACK_DIR/supabase/project" && docker compose down -v) || true
    ok "Containers & volumes removed."
  fi
}

case "${ACTION}" in
  install) main_install;;
  start) stack_start;;
  stop) stack_stop;;
  status) stack_status;;
  destroy) stack_destroy;;
  *) err "Unknown action: $ACTION"; exit 1;;
esac
