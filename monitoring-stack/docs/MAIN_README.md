# 0) ensure DNS zone @ Cloudflare and create token (Zone:Read + DNS:Edit)
# 1) put `opendiscourse_stack.sh` at repo root
# 2) run validations
./scripts/validate_env.sh --domain opendiscourse.net --cf-token '<CF_TOKEN>'

# 3) deploy (CPU)
sudo -E bash ./opendiscourse_stack.sh \
  --domain opendiscourse.net --email inbox@opendiscourse.net \
  --cf-token '<CF_TOKEN>' --auth on --non-interactive

#    OR deploy (GPU + vLLM)
sudo -E bash ./opendiscourse_stack.sh \
  --domain opendiscourse.net --email inbox@opendiscourse.net \
  --cf-token '<CF_TOKEN>' --auth on --gpu vllm --non-interactive

# 4) smoke test
./scripts/smoke_test.sh --domain opendiscourse.net

You’ll get:

Supabase (Studio/API): https://supabase.opendiscourse.net / https://supabase-api.opendiscourse.net

RAG API (Weaviate): https://api.opendiscourse.net/docs

GraphRAG API (Neo4j): https://graph-api.opendiscourse.net/docs

Weaviate: https://weaviate.opendiscourse.net

Neo4j Browser: https://neo4j.opendiscourse.net

LocalAI: https://localai.opendiscourse.net/v1

vLLM (opt): https://vllm.opendiscourse.net/v1

OpenWebUI: https://openwebui.opendiscourse.net

Langfuse: https://traces.opendiscourse.net

Flowise: https://flowise.opendiscourse.net

n8n: https://n8n.opendiscourse.net

SearxNG: https://search.opendiscourse.net

MinIO S3: https://s3.opendiscourse.net (console at https://s3-console.opendiscourse.net)

PDF inbox (drop PDFs/TXTs to auto‑ingest): /opt/opendiscourse/data/inbox

Philosophy

Boringly simple > clever: one host, Traefik edge, one Postgres (Supabase) for everything that needs SQL, Weaviate for vectors, Neo4j for graph.

Self‑hosted by default: LocalAI/vLLM for models; MinIO for S3; no paid APIs required.

Same‑box orchestration: everything dockerized, predictable, and easy to back up/restore.

Secure without lockout: HTTPS everywhere, JWT on APIs (toggle with --auth off if you must), RLS on app tables, admin UIs protected via basic auth or per‑service logins.

Observability hooks ready: Langfuse optional; logs via docker logs + simple diag script.

Upgradable in place: re‑run installer safely; idempotent by design.

Architecture
High‑Level

flowchart LR
    user((User)) -- HTTPS --> CF[Cloudflare DNS]
    CF --> T[Traefik]
    T --> SB[Supabase API/Studio]
    T --> RAG[RAG API (FastAPI)]
    T --> GR[GraphRAG API (FastAPI)]
    T --> WVT[Weaviate]
    T --> NEO[Neo4j]
    T --> LAI[LocalAI / vLLM]
    T --> OWU[OpenWebUI]
    T --> LFS[Langfuse]
    T --> N8N[n8n]
    T --> FWS[Flowise]
    T --> SRX[SearxNG]
    T --> S3[MinIO S3 + Console]

    RAG -->|vector search| WVT
    RAG -->|embeddings| LAI
    GR -->|Bolt| NEO
    SB -. Postgres .- LFS
    N8N -. Postgres .- SB

RAG Flow (PDF → Insights)

sequenceDiagram
  participant U as You
  participant F as PDF Worker
  participant A as RAG API
  participant V as Weaviate
  participant L as LocalAI/vLLM
  participant G as GraphRAG API
  participant N as Neo4j

  U->>F: drop file in /opt/opendiscourse/data/inbox
  F->>A: POST /ingest (chunks) [JWT]
  A->>L: embed (OpenAI-compatible)
  A->>V: upsert chunks
  F->>G: POST /graph/ingest_entities [JWT]
  G->>N: MERGE nodes/relations
  U->>A: POST /query {query:"What are disclosure rules?"}
  A->>V: near_text semantic search
  V->>A: top-k chunks
  A->>U: answers + citations


What’s installed where

Edge: Traefik + Cloudflare DNS‑01 ACME (wildcard TLS)

Auth & Data: Supabase full stack (single Postgres), RLS enabled

Vectors: Weaviate (text2vec-openai module pointing to LocalAI/vLLM)

LLM: LocalAI (CPU by default) or vLLM (GPU) as OpenAI‑compatible endpoint

Graph: Neo4j (APOC + GDS)

APIs:

/api RAG (Weaviate)

/graph-api GraphRAG (Neo4j)
Both validate Supabase JWTs by default.

Automation: n8n (on Supabase PG)

Pipelines/UI: Flowise; OpenWebUI

Search: SearxNG

Telemetry: optional Langfuse (on Supabase PG)

Object store: MinIO (S3 & console)

Ingestion: pdf‑worker watches inbox to auto‑ingest PDFs/TXTs

Pre‑requisites

A fresh Ubuntu/Debian server (Hetzner works great)

Your domain in Cloudflare, with an API token (Zone:Read + DNS:Edit)

Ports 80/443 reachable from the internet

Optional:

NVIDIA driver & container runtime (for --gpu vllm)

Vaultwarden (Bitwarden‑compatible) if you want local secrets vault (instructions below)