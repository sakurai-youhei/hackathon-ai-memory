#!/usr/bin/env bash
# Create or skip ai-memory inference endpoints idempotently.
# EIS endpoints (jina-v3, jina-v5s) are pre-provisioned — only verified here.
# The e5 endpoint wraps the uploaded multilingual-e5-large trained model.
#
# Usage:
#   AI_MEMORY_MODELS="e5 jina_v3 jina_v5s" ./elastic-cloud/apply-inference-endpoints.sh
#
# Optional overrides:
#   E5_MODEL_ID          (default: multilingual-e5-large)
#   E5_INFERENCE_ID      (default: ai-memory-e5)
#   JINA_V3_INFERENCE_ID (default: .jina-embeddings-v3)
#   JINA_V5S_INFERENCE_ID (default: .jina-embeddings-v5-text-small)
set -euo pipefail

: "${ES_ENDPOINT:?ES_ENDPOINT is required in .env}"
: "${ES_API_KEY:?ES_API_KEY is required in .env}"

ES_ENDPOINT="${ES_ENDPOINT%/}"
AI_MEMORY_MODELS="${AI_MEMORY_MODELS:-e5 jina_v3 jina_v5s}"
E5_MODEL_ID="${E5_MODEL_ID:-multilingual-e5-large}"
E5_INFERENCE_ID="${E5_INFERENCE_ID:-ai-memory-e5}"
JINA_V3_INFERENCE_ID="${JINA_V3_INFERENCE_ID:-.jina-embeddings-v3}"
JINA_V5S_INFERENCE_ID="${JINA_V5S_INFERENCE_ID:-.jina-embeddings-v5-text-small}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

enabled() {
	[[ " ${AI_MEMORY_MODELS} " == *" ${1} "* ]]
}

request() {
	local method="$1" path="$2" output="$3"
	shift 3
	curl -fsS \
		--retry 3 \
		--retry-all-errors \
		--connect-timeout 15 \
		--max-time 300 \
		-X "${method}" \
		-H "Authorization: ApiKey ${ES_API_KEY}" \
		"$@" \
		-o "${output}" \
		"${ES_ENDPOINT}${path}"
}

# ------------------------------------------------------------------ e5

if enabled e5; then
	echo "Checking trained model ${E5_MODEL_ID}..."
	request GET "/_ml/trained_models/${E5_MODEL_ID}?include=definition_status" \
		"${WORK_DIR}/model.json"
	python3 - "${WORK_DIR}/model.json" "${E5_MODEL_ID}" <<'PY'
import json, sys
cfgs = json.load(open(sys.argv[1], encoding="utf-8")).get("trained_model_configs", [])
if not cfgs or cfgs[0].get("model_id") != sys.argv[2]:
    raise SystemExit(f"trained model {sys.argv[2]!r} not found — import it first with eland")
if not cfgs[0].get("fully_defined"):
    raise SystemExit(f"model {sys.argv[2]!r} is not fully_defined — re-run eland import")
print(f"  {sys.argv[2]} is fully_defined.")
PY

	echo "Checking inference endpoint ${E5_INFERENCE_ID}..."
	if curl -fsS --max-time 10 \
		-H "Authorization: ApiKey ${ES_API_KEY}" \
		-o "${WORK_DIR}/check.json" \
		"${ES_ENDPOINT}/_inference/text_embedding/${E5_INFERENCE_ID}" 2>/dev/null; then
		echo "  ${E5_INFERENCE_ID} already exists — skipped."
	else
		echo "Creating inference endpoint ${E5_INFERENCE_ID}..."
		request PUT "/_inference/text_embedding/${E5_INFERENCE_ID}?timeout=180s" \
			"${WORK_DIR}/e5.json" \
			-H 'Content-Type: application/json' \
			-d "{\"service\":\"elasticsearch\",\"service_settings\":{\"model_id\":\"${E5_MODEL_ID}\",\"num_threads\":1,\"adaptive_allocations\":{\"enabled\":true,\"min_number_of_allocations\":0,\"max_number_of_allocations\":8}},\"chunking_settings\":{\"strategy\":\"sentence\",\"max_chunk_size\":250,\"sentence_overlap\":1}}"
		echo "  ${E5_INFERENCE_ID} created."
	fi
fi

# ---------------------------------------------------------------- EIS

if enabled jina_v3; then
	echo "Verifying EIS endpoint ${JINA_V3_INFERENCE_ID}..."
	request GET "/_inference/text_embedding/${JINA_V3_INFERENCE_ID}" \
		"${WORK_DIR}/jina_v3.json"
	echo "  ${JINA_V3_INFERENCE_ID} is available."
fi

if enabled jina_v5s; then
	echo "Verifying EIS endpoint ${JINA_V5S_INFERENCE_ID}..."
	request GET "/_inference/text_embedding/${JINA_V5S_INFERENCE_ID}" \
		"${WORK_DIR}/jina_v5s.json"
	echo "  ${JINA_V5S_INFERENCE_ID} is available."
fi

echo "Inference endpoints ready."
