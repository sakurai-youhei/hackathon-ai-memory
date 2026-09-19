#!/usr/bin/env bash
# Deploy Text Embeddings Inference (TEI) services to Cloud Run for BGE-M3 and Qwen3-Embedding.
#
# Usage:
#   AI_MEMORY_MODELS="bge_m3 qwen3" ./google-cloud/deploy-tei.sh
#
# Required in .env:
#   GCP_PROJECT_ID, TEI_API_KEY
#
# Optional:
#   TEI_REGION  (default: asia-northeast1 — co-located with Elasticsearch)
#   TEI_IMAGE   (default: ghcr.io/huggingface/text-embeddings-inference:cpu-1.9)
#   BGE_M3_URL  (printed on success; set this in .env after the first deploy)
#   QWEN3_URL   (printed on success; set this in .env after the first deploy)
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required in .env}"
: "${TEI_API_KEY:?TEI_API_KEY is required in .env}"

AI_MEMORY_MODELS="${AI_MEMORY_MODELS:-bge_m3 qwen3}"
TEI_REGION="${TEI_REGION:-asia-northeast1}"
TEI_IMAGE="${TEI_IMAGE:-ghcr.io/huggingface/text-embeddings-inference:cpu-1.9}"

enabled() {
	[[ " ${AI_MEMORY_MODELS} " == *" ${1} "* ]]
}

echo "=== TEI Cloud Run deployment ==="
echo "Project : ${GCP_PROJECT_ID}"
echo "Region  : ${TEI_REGION}"
echo "Image   : ${TEI_IMAGE}"
echo "Models  : ${AI_MEMORY_MODELS}"
echo

# Enable Cloud Run API if not already enabled.
echo "--- Enabling Cloud Run Admin API ---"
gcloud services enable run.googleapis.com --project="${GCP_PROJECT_ID}"
echo "  [OK]   Cloud Run Admin API is enabled."
echo

# ----------------------------------------------------------------- BGE-M3

if enabled bge_m3; then
	echo "--- Deploying TEI for BGE-M3 ---"
	echo "  Model  : BAAI/bge-m3 (XLM-RoBERTa 568M, CPU)"
	echo "  CPU    : 4 vCPU / 8 GiB"
	echo "  Min    : 1 (required: cold start ~60-150s would kill inference validation)"
	gcloud run deploy tei-bge-m3 \
		--project="${GCP_PROJECT_ID}" \
		--region="${TEI_REGION}" \
		--image="${TEI_IMAGE}" \
		--set-env-vars="MODEL_ID=BAAI/bge-m3,API_KEY=${TEI_API_KEY},MAX_CLIENT_BATCH_SIZE=32,AUTO_TRUNCATE=true" \
		--cpu=4 \
		--memory=8Gi \
		--concurrency=4 \
		--min-instances=1 \
		--max-instances=2 \
		--no-cpu-throttling \
		--timeout=300 \
		--allow-unauthenticated \
		--quiet
	BGE_M3_SERVICE_URL="$(gcloud run services describe tei-bge-m3 \
		--project="${GCP_PROJECT_ID}" \
		--region="${TEI_REGION}" \
		--format='value(status.url)')"
	BGE_M3_EMBED_URL="${BGE_M3_SERVICE_URL}/v1/embeddings"
	echo "  [OK]   tei-bge-m3 deployed."
	echo "         BGE_M3_URL=${BGE_M3_EMBED_URL}"
	echo
fi

# --------------------------------------------------------------- Qwen3-0.6B

if enabled qwen3; then
	echo "--- Deploying TEI for Qwen3-Embedding-0.6B ---"
	echo "  Model  : Qwen/Qwen3-Embedding-0.6B (causal LM, CPU)"
	echo "  CPU    : 8 vCPU / 16 GiB (causal LM last-token pooling is heavier than encoder)"
	echo "  Min    : 1 (required: cold start ~60-150s would kill inference validation)"
	gcloud run deploy tei-qwen3-06b \
		--project="${GCP_PROJECT_ID}" \
		--region="${TEI_REGION}" \
		--image="${TEI_IMAGE}" \
		--set-env-vars="MODEL_ID=Qwen/Qwen3-Embedding-0.6B,API_KEY=${TEI_API_KEY},MAX_CLIENT_BATCH_SIZE=16,AUTO_TRUNCATE=true" \
		--cpu=8 \
		--memory=16Gi \
		--concurrency=2 \
		--min-instances=1 \
		--max-instances=2 \
		--no-cpu-throttling \
		--timeout=300 \
		--allow-unauthenticated \
		--quiet
	QWEN3_SERVICE_URL="$(gcloud run services describe tei-qwen3-06b \
		--project="${GCP_PROJECT_ID}" \
		--region="${TEI_REGION}" \
		--format='value(status.url)')"
	QWEN3_EMBED_URL="${QWEN3_SERVICE_URL}/v1/embeddings"
	echo "  [OK]   tei-qwen3-06b deployed."
	echo "         QWEN3_URL=${QWEN3_EMBED_URL}"
	echo
fi

# ---------------------------------------------------------------- summary

echo "=== TEI deployment complete ==="
echo
echo "Add the following to your .env (they are not there yet):"
if enabled bge_m3; then
	echo "  BGE_M3_URL=${BGE_M3_EMBED_URL}"
fi
if enabled qwen3; then
	echo "  QWEN3_URL=${QWEN3_EMBED_URL}"
fi
echo
echo "Then run:"
echo "  make setup-elasticsearch AI_MEMORY_MODELS='${AI_MEMORY_MODELS}'"
echo
echo "Note: TEI services are billed per vCPU-second with --no-cpu-throttling and min-instances=1."
echo "      Stop them when not needed: gcloud run services update tei-bge-m3 --min-instances=0 --region=${TEI_REGION}"
