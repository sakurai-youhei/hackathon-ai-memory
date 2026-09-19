#!/usr/bin/env bash
# Setup script for ai-memory Elasticsearch assets.
# Idempotent: safe to re-run. Never deletes existing resources.
#
# Usage:
#   AI_MEMORY_MODELS="e5" ./elastic-cloud/setup-elasticsearch.sh          # e5 only (default)
#   AI_MEMORY_MODELS="e5 bge_m3 qwen3" ./elastic-cloud/setup-elasticsearch.sh
#
# Required in .env (sourced by Makefile via 'include .env; export'):
#   ES_ENDPOINT, ES_API_KEY
#
# Required in .env when bge_m3 or qwen3 is enabled:
#   BGE_M3_URL, QWEN3_URL, TEI_API_KEY
#
# Optional overrides:
#   BGE_M3_INFERENCE_ID (default: ai-memory-bge-m3)
#   QWEN3_INFERENCE_ID  (default: ai-memory-qwen3)
#   E5_INFERENCE_ID     (default: ai-memory-e5)
#   E5_MODEL_ID         (default: multilingual-e5-large)
set -euo pipefail

: "${ES_ENDPOINT:?ES_ENDPOINT is required in .env}"
: "${ES_API_KEY:?ES_API_KEY is required in .env}"

ES_ENDPOINT="${ES_ENDPOINT%/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AI_MEMORY_MODELS="${AI_MEMORY_MODELS:-e5}"
E5_MODEL_ID="${E5_MODEL_ID:-multilingual-e5-large}"
E5_INFERENCE_ID="${E5_INFERENCE_ID:-ai-memory-e5}"
BGE_M3_INFERENCE_ID="${BGE_M3_INFERENCE_ID:-ai-memory-bge-m3}"
QWEN3_INFERENCE_ID="${QWEN3_INFERENCE_ID:-ai-memory-qwen3}"
BGE_M3_URL="${BGE_M3_URL:-}"
QWEN3_URL="${QWEN3_URL:-}"
TEI_API_KEY="${TEI_API_KEY:-}"

ENABLED_MODELS=()

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
	ENABLED_MODELS+=("e5")
fi

# ------------------------------------------------------- 2. TEI reachability

smoke_tei() {
	# smoke_tei <label> <url>
	local label="$1" url="$2"
	echo "  Smoke-testing ${label} at ${url%/v1/embeddings}..."
	local status
	status="$(curl -sS -o /dev/null -w '%{http_code}' \
		--max-time 60 \
		-H "Authorization: Bearer ${TEI_API_KEY}" \
		-H 'Content-Type: application/json' \
		"${url}" \
		-d '{"input":["health probe"]}')"
	if [[ "${status}" != "200" ]]; then
		echo "  [FAIL] ${label} returned HTTP ${status}." >&2
		echo "         Deploy TEI first: make deploy-tei AI_MEMORY_MODELS='${AI_MEMORY_MODELS}'" >&2
		echo "         Elasticsearch validates inference endpoints with a live call — TEI must be warm." >&2
		exit 1
	fi
	echo "  [OK]   ${label} is reachable (HTTP 200)."
}

if enabled bge_m3 || enabled qwen3; then
	echo
	echo "--- TEI reachability checks ---"
	: "${TEI_API_KEY:?TEI_API_KEY is required in .env when bge_m3 or qwen3 is in AI_MEMORY_MODELS}"
fi

if enabled bge_m3; then
	: "${BGE_M3_URL:?BGE_M3_URL is required in .env when bge_m3 is in AI_MEMORY_MODELS}"
	smoke_tei "BGE-M3 TEI" "${BGE_M3_URL}"

	# Egress probe: verify Elasticsearch can reach the external TEI endpoint.
	# Uses a throwaway inference ID that is deleted immediately after the test.
	echo "  Egress probe: checking ES -> BGE-M3 TEI connectivity..."
	PROBE_ID="zz-egress-probe-$$"
	PROBE_BODY="{\"service\":\"custom\",\"service_settings\":{\"url\":\"${BGE_M3_URL}\",\"headers\":{\"Authorization\":\"Bearer ${TEI_API_KEY}\",\"Content-Type\":\"application/json\"},\"request\":\"{\\\"input\\\": \\\${input}}\",\"response\":{\"json_parser\":{\"text_embeddings\":\"\$.data[*].embedding[*]\",\"embedding_type\":\"float\"}},\"batch_size\":1},\"chunking_settings\":{\"strategy\":\"none\"}}"
	es_request PUT "/_inference/text_embedding/${PROBE_ID}?timeout=120s" "${PROBE_BODY}"
	PROBE_STATUS="${ES_HTTP_STATUS}"
	rm -f "${ES_RESPONSE_FILE}"
	if [[ "${PROBE_STATUS}" == "200" ]]; then
		# Clean up the probe endpoint
		es_request DELETE "/_inference/text_embedding/${PROBE_ID}"
		rm -f "${ES_RESPONSE_FILE}"
		echo "  [OK]   Elasticsearch can reach TEI (custom service egress confirmed)."
	else
		echo "  [WARN] Egress probe failed (HTTP ${PROBE_STATUS})." >&2
		echo "         Elasticsearch Serverless may block outbound custom service calls." >&2
		echo "         If bge_m3/qwen3 inference endpoint creation also fails, fall back to EIS:" >&2
		echo "           BGE_M3_INFERENCE_ID=.jina-embeddings-v3 QWEN3_INFERENCE_ID=.jina-embeddings-v5-text-small make setup-elasticsearch" >&2
		echo "         Continuing with caution..." >&2
	fi
	ENABLED_MODELS+=("bge_m3")
fi

if enabled qwen3; then
	: "${QWEN3_URL:?QWEN3_URL is required in .env when qwen3 is in AI_MEMORY_MODELS}"
	smoke_tei "Qwen3 TEI" "${QWEN3_URL}"
	ENABLED_MODELS+=("qwen3")
fi

# -------------------------------------------------- 3. inference endpoints

echo
echo "--- Inference endpoints ---"

if enabled e5; then
	ensure_inference "${E5_INFERENCE_ID}" "text_embedding" \
		"{\"service\":\"elasticsearch\",\"service_settings\":{\"model_id\":\"${E5_MODEL_ID}\",\"num_threads\":1,\"adaptive_allocations\":{\"enabled\":true,\"min_number_of_allocations\":0,\"max_number_of_allocations\":8}},\"chunking_settings\":{\"strategy\":\"sentence\",\"max_chunk_size\":250,\"sentence_overlap\":1}}"
fi

if enabled bge_m3; then
	ensure_inference "${BGE_M3_INFERENCE_ID}" "text_embedding" \
		"{\"service\":\"custom\",\"service_settings\":{\"url\":\"${BGE_M3_URL}\",\"headers\":{\"Authorization\":\"Bearer \${api_key}\",\"Content-Type\":\"application/json\"},\"request\":\"{\\\"input\\\": \\\${input}}\",\"response\":{\"json_parser\":{\"text_embeddings\":\"\$.data[*].embedding[*]\",\"embedding_type\":\"float\"}},\"secret_parameters\":{\"api_key\":\"${TEI_API_KEY}\"},\"batch_size\":16},\"chunking_settings\":{\"strategy\":\"none\"}}"
fi

if enabled qwen3; then
	ensure_inference "${QWEN3_INFERENCE_ID}" "text_embedding" \
		"{\"service\":\"custom\",\"service_settings\":{\"url\":\"${QWEN3_URL}\",\"headers\":{\"Authorization\":\"Bearer \${api_key}\",\"Content-Type\":\"application/json\"},\"request\":\"{\\\"input\\\": \\\${input}}\",\"response\":{\"json_parser\":{\"text_embeddings\":\"\$.data[*].embedding[*]\",\"embedding_type\":\"float\"}},\"secret_parameters\":{\"api_key\":\"${TEI_API_KEY}\"},\"batch_size\":8},\"chunking_settings\":{\"strategy\":\"none\"}}"
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

if enabled bge_m3; then
	put_component_template "ai-memory@semantic-bge-m3" \
		"${SCRIPT_DIR}/component-templates/ai-memory@semantic-bge-m3.json"
fi

if enabled qwen3; then
	put_component_template "ai-memory@semantic-qwen3" \
		"${SCRIPT_DIR}/component-templates/ai-memory@semantic-qwen3.json"
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

# Build a mapping body containing only the semantic fields that are now enabled.
BACKFILL_PROPS="{}"

if enabled e5; then
	BACKFILL_PROPS="$(python3 -c "
import json
props=json.loads('${BACKFILL_PROPS}')
props['semantic_e5']={'type':'semantic_text','inference_id':'${E5_INFERENCE_ID}','chunking_settings':{'strategy':'sentence','max_chunk_size':250,'sentence_overlap':1}}
print(json.dumps(props))
")"
fi

if enabled bge_m3; then
	BACKFILL_PROPS="$(python3 -c "
import json
props=json.loads('${BACKFILL_PROPS}')
props['semantic_bge_m3']={'type':'semantic_text','inference_id':'${BGE_M3_INFERENCE_ID}','chunking_settings':{'strategy':'recursive','max_chunk_size':300,'separator_group':'markdown'}}
print(json.dumps(props))
")"
fi

if enabled qwen3; then
	BACKFILL_PROPS="$(python3 -c "
import json
props=json.loads('${BACKFILL_PROPS}')
props['semantic_qwen3']={'type':'semantic_text','inference_id':'${QWEN3_INFERENCE_ID}','chunking_settings':{'strategy':'none'}}
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
	echo "  semantic_e5    <- ${E5_INFERENCE_ID} (multilingual-e5-large, in-cluster)"
fi
if enabled bge_m3; then
	echo "  semantic_bge_m3 <- ${BGE_M3_INFERENCE_ID} (BGE-M3, TEI at ${BGE_M3_URL})"
fi
if enabled qwen3; then
	echo "  semantic_qwen3  <- ${QWEN3_INFERENCE_ID} (Qwen3-Embedding-0.6B, TEI at ${QWEN3_URL})"
fi
echo
echo "Next steps:"
echo "  1. Onboard a user:  make onboard-user UUID=<uuid>  (issues an API key)"
echo "  2. Smoke test:      POST <uuid>-ai-memory/_doc with a text field"
echo "  3. Query:           GET <uuid>-ai-memory/_search with a semantic retriever"
echo
echo "To enable more models later:"
echo "  make deploy-tei AI_MEMORY_MODELS='bge_m3 qwen3'"
echo "  make setup-elasticsearch AI_MEMORY_MODELS='e5 bge_m3 qwen3'"
