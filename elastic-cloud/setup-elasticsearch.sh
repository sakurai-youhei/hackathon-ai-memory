#!/usr/bin/env bash
# Setup script for ai-memory Elasticsearch assets.
# Idempotent: safe to re-run. Never deletes existing resources.
#
# Usage:
#   AI_MEMORY_MODELS="e5" ./elastic-cloud/setup-elasticsearch.sh
#   AI_MEMORY_MODELS="e5 jina_v3 jina_v5s" ./elastic-cloud/setup-elasticsearch.sh
#
# Required in .env (sourced by Makefile via 'include .env; export'):
#   ES_ENDPOINT, ES_API_KEY
#
# Optional overrides:
#   E5_INFERENCE_ID      (default: ai-memory-e5)
#   E5_MODEL_ID          (default: multilingual-e5-large)
#   JINA_V3_INFERENCE_ID (default: .jina-embeddings-v3)
#   JINA_V5S_INFERENCE_ID (default: .jina-embeddings-v5-text-small)
set -euo pipefail

: "${ES_ENDPOINT:?ES_ENDPOINT is required in .env}"
: "${ES_API_KEY:?ES_API_KEY is required in .env}"

ES_ENDPOINT="${ES_ENDPOINT%/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AI_MEMORY_MODELS="${AI_MEMORY_MODELS:-e5}"
E5_MODEL_ID="${E5_MODEL_ID:-multilingual-e5-large}"
E5_INFERENCE_ID="${E5_INFERENCE_ID:-ai-memory-e5}"
JINA_V3_INFERENCE_ID="${JINA_V3_INFERENCE_ID:-.jina-embeddings-v3}"
JINA_V5S_INFERENCE_ID="${JINA_V5S_INFERENCE_ID:-.jina-embeddings-v5-text-small}"

# ------------------------------------------------------------------ helpers

es_request() {
	# es_request <METHOD> <PATH> [BODY]
	# Sets ES_HTTP_STATUS and writes body to ES_RESPONSE_FILE.
	local method="$1" path="$2" body="${3:-}"
	ES_RESPONSE_FILE="$(mktemp)"
	local curl_args=(
		-sS
		-o "${ES_RESPONSE_FILE}"
		-w '%{http_code}'
		-X "${method}"
		-H "Authorization: ApiKey ${ES_API_KEY}"
		--max-time 180
	)
	if [[ -n "${body}" ]]; then
		curl_args+=(-H 'Content-Type: application/json' -d "${body}")
	fi
	ES_HTTP_STATUS="$(curl "${curl_args[@]}" "${ES_ENDPOINT}${path}")"
}

es_ok() {
	# es_ok <METHOD> <PATH> [BODY] — exits on non-2xx
	es_request "$@"
	if [[ "${ES_HTTP_STATUS}" != 2* ]]; then
		echo "ERROR: ${1} ${2} returned HTTP ${ES_HTTP_STATUS}" >&2
		cat "${ES_RESPONSE_FILE}" >&2
		echo >&2
		rm -f "${ES_RESPONSE_FILE}"
		exit 1
	fi
}

es_body() {
	cat "${ES_RESPONSE_FILE}"
	rm -f "${ES_RESPONSE_FILE}"
}

enabled() {
	# enabled <model-key> — true if key is in AI_MEMORY_MODELS
	[[ " ${AI_MEMORY_MODELS} " == *" ${1} "* ]]
}

ensure_inference() {
	# ensure_inference <inference_id> <task_type> <body_json>
	local id="$1" task="$2" body="$3"
	es_request GET "/_inference/${task}/${id}"
	if [[ "${ES_HTTP_STATUS}" == "200" ]]; then
		echo "  [SKIP] Inference endpoint ${id} already exists."
		rm -f "${ES_RESPONSE_FILE}"
		return 0
	fi
	rm -f "${ES_RESPONSE_FILE}"
	echo "  [PUT]  Creating inference endpoint ${id}..."
	es_ok PUT "/_inference/${task}/${id}?timeout=180s" "${body}"
	rm -f "${ES_RESPONSE_FILE}"
	echo "  [OK]   Created inference endpoint ${id}."
}

check_eis_endpoint() {
	# check_eis_endpoint <inference_id> — verifies EIS endpoint is available
	local id="$1"
	es_request GET "/_inference/text_embedding/${id}"
	if [[ "${ES_HTTP_STATUS}" != "200" ]]; then
		rm -f "${ES_RESPONSE_FILE}"
		echo "  [FAIL] EIS endpoint ${id} not found." >&2
		echo "         This endpoint should be pre-provisioned in Elastic Serverless." >&2
		exit 1
	fi
	rm -f "${ES_RESPONSE_FILE}"
	echo "  [OK]   EIS endpoint ${id} is available."
}

put_component_template() {
	# put_component_template <name> <file>
	local name="$1" file="$2"
	echo "  [PUT]  Component template ${name}..."
	es_ok PUT "/_component_template/${name}" "$(cat "${file}")"
	rm -f "${ES_RESPONSE_FILE}"
	echo "  [OK]   Applied component template ${name}."
}

# --------------------------------------------------------------- 0. preflight

echo "=== ai-memory Elasticsearch setup ==="
echo "Endpoint : ${ES_ENDPOINT}"
echo "Models   : ${AI_MEMORY_MODELS}"
echo

echo "--- Preflight ---"
es_ok GET "/"
CLUSTER_VERSION="$(python3 -c "import json,sys;d=json.load(open('${ES_RESPONSE_FILE}'));print(d['version']['number'],d['version']['build_flavor'])")"
rm -f "${ES_RESPONSE_FILE}"
echo "  [OK]   Connected: ${CLUSTER_VERSION}"

# --------------------------------------------------------------- 1. e5 model

if enabled e5; then
	echo
	echo "--- multilingual-e5-large model check ---"
	es_request GET "/_ml/trained_models/${E5_MODEL_ID}?include=definition_status"
	if [[ "${ES_HTTP_STATUS}" != "200" ]]; then
		rm -f "${ES_RESPONSE_FILE}"
		echo "  [FAIL] Trained model ${E5_MODEL_ID} not found." >&2
		echo "         Import it first (Python <3.14 required):" >&2
		echo "           uv venv --python 3.13 .venv-eland" >&2
		echo "           .venv-eland/bin/pip install 'eland[pytorch]'" >&2
		echo "           .venv-eland/bin/eland_import_hub_model \\" >&2
		echo "             --url '${ES_ENDPOINT}' --es-api-key '<key>' \\" >&2
		echo "             --hub-model-id intfloat/multilingual-e5-large \\" >&2
		echo "             --task-type text_embedding --start" >&2
		exit 1
	fi
	FULLY_DEFINED="$(python3 -c "
import json,sys
cfg=json.load(open('${ES_RESPONSE_FILE}'))['trained_model_configs'][0]
print('true' if cfg.get('fully_defined') else 'false')
")"
	rm -f "${ES_RESPONSE_FILE}"
	if [[ "${FULLY_DEFINED}" != "true" ]]; then
		echo "  [FAIL] Model ${E5_MODEL_ID} is not fully_defined. Re-run the import." >&2
		exit 1
	fi
	echo "  [OK]   ${E5_MODEL_ID} is fully_defined."
fi

# ------------------------------------------------------- 2. EIS availability

if enabled jina_v3 || enabled jina_v5s; then
	echo
	echo "--- EIS endpoint availability ---"
fi

if enabled jina_v3; then
	check_eis_endpoint "${JINA_V3_INFERENCE_ID}"
fi

if enabled jina_v5s; then
	check_eis_endpoint "${JINA_V5S_INFERENCE_ID}"
fi

# -------------------------------------------------- 3. inference endpoints

echo
echo "--- Inference endpoints ---"

if enabled e5; then
	ensure_inference "${E5_INFERENCE_ID}" "text_embedding" \
		"{\"service\":\"elasticsearch\",\"service_settings\":{\"model_id\":\"${E5_MODEL_ID}\",\"num_threads\":1,\"adaptive_allocations\":{\"enabled\":true,\"min_number_of_allocations\":0,\"max_number_of_allocations\":8}},\"chunking_settings\":{\"strategy\":\"sentence\",\"max_chunk_size\":250,\"sentence_overlap\":1}}"
fi

if enabled jina_v3 || enabled jina_v5s; then
	echo "  [SKIP] EIS endpoints (${JINA_V3_INFERENCE_ID}, ${JINA_V5S_INFERENCE_ID}) are pre-provisioned — no PUT required."
fi

# ------------------------------------------- 4. component templates

echo
echo "--- Component templates ---"

put_component_template "ai-memory@settings" \
	"${SCRIPT_DIR}/component-templates/ai-memory@settings.json"

put_component_template "ai-memory@mappings" \
	"${SCRIPT_DIR}/component-templates/ai-memory@mappings.json"

if enabled e5; then
	put_component_template "ai-memory@semantic-e5" \
		"${SCRIPT_DIR}/component-templates/ai-memory@semantic-e5.json"
fi

if enabled jina_v3; then
	put_component_template "ai-memory@semantic-jina-v3" \
		"${SCRIPT_DIR}/component-templates/ai-memory@semantic-jina-v3.json"
fi

if enabled jina_v5s; then
	put_component_template "ai-memory@semantic-jina-v5s" \
		"${SCRIPT_DIR}/component-templates/ai-memory@semantic-jina-v5s.json"
fi

# ----------------------------------------------- 5. index template

echo
echo "--- Index template ---"
echo "  [PUT]  Index template ai-memory (priority 550)..."
es_ok PUT "/_index_template/ai-memory" \
	"$(cat "${SCRIPT_DIR}/index-template.json")"
rm -f "${ES_RESPONSE_FILE}"
echo "  [OK]   Applied index template ai-memory."

# ----------------------------------------------- 6. ingest pipeline

echo
echo "--- Ingest pipeline ---"
echo "  [PUT]  Ingest pipeline ai-memory..."
es_ok PUT "/_ingest/pipeline/ai-memory" \
	"$(cat "${SCRIPT_DIR}/ingest-pipeline.json")"
rm -f "${ES_RESPONSE_FILE}"
echo "  [OK]   Applied ingest pipeline ai-memory."

# ------------------------------------ 7. backfill mappings on existing indices

echo
echo "--- Backfill: updating mappings on existing *-ai-memory indices ---"

BACKFILL_PROPS="{}"

if enabled e5; then
	BACKFILL_PROPS="$(python3 -c "
import json
props=json.loads('${BACKFILL_PROPS}')
props['semantic_e5']={'type':'semantic_text','inference_id':'${E5_INFERENCE_ID}','chunking_settings':{'strategy':'sentence','max_chunk_size':250,'sentence_overlap':1}}
print(json.dumps(props))
")"
fi

if enabled jina_v3; then
	BACKFILL_PROPS="$(python3 -c "
import json
props=json.loads('${BACKFILL_PROPS}')
props['semantic_jina_v3']={'type':'semantic_text','inference_id':'${JINA_V3_INFERENCE_ID}','chunking_settings':{'strategy':'recursive','max_chunk_size':300,'separator_group':'markdown'}}
print(json.dumps(props))
")"
fi

if enabled jina_v5s; then
	BACKFILL_PROPS="$(python3 -c "
import json
props=json.loads('${BACKFILL_PROPS}')
props['semantic_jina_v5s']={'type':'semantic_text','inference_id':'${JINA_V5S_INFERENCE_ID}','chunking_settings':{'strategy':'none'}}
print(json.dumps(props))
")"
fi

BACKFILL_BODY="{\"properties\":${BACKFILL_PROPS}}"

es_request GET "/_cat/indices/*-ai-memory?h=index"
EXISTING_INDICES="$(cat "${ES_RESPONSE_FILE}" | tr -d '\r')"
rm -f "${ES_RESPONSE_FILE}"

BACKFILL_COUNT=0
if [[ -n "${EXISTING_INDICES}" ]]; then
	while IFS= read -r index; do
		[[ -z "${index}" ]] && continue
		echo "  [PUT]  Mapping update on ${index}..."
		es_ok PUT "/${index}/_mapping" "${BACKFILL_BODY}"
		rm -f "${ES_RESPONSE_FILE}"
		echo "  [OK]   Updated ${index}."
		BACKFILL_COUNT=$((BACKFILL_COUNT + 1))
	done <<< "${EXISTING_INDICES}"
fi

if [[ "${BACKFILL_COUNT}" -eq 0 ]]; then
	echo "  [SKIP] No existing *-ai-memory indices found."
fi

# ------------------------------------------------------------ 8. summary

echo
echo "=== Setup complete ==="
echo
echo "Enabled semantic slots:"
if enabled e5; then
	echo "  semantic_e5      <- ${E5_INFERENCE_ID} (multilingual-e5-large, in-cluster elasticsearch service)"
fi
if enabled jina_v3; then
	echo "  semantic_jina_v3 <- ${JINA_V3_INFERENCE_ID} (Jina Embeddings v3, EIS)"
fi
if enabled jina_v5s; then
	echo "  semantic_jina_v5s <- ${JINA_V5S_INFERENCE_ID} (Jina Embeddings v5 Text Small, EIS)"
fi
echo
echo "Next steps:"
echo "  1. Onboard a user:  make onboard-user UUID=<uuid>  (issues an API key)"
echo "  2. Smoke test:      POST <uuid>-ai-memory/_doc with a text field"
echo "  3. Query:           GET <uuid>-ai-memory/_search with a semantic retriever"
