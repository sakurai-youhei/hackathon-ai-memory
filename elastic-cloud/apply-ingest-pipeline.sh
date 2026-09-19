#!/usr/bin/env bash
# Apply and smoke-test the ai-memory ingest pipeline.
set -euo pipefail

: "${ES_ENDPOINT:?ES_ENDPOINT is required in .env}"
: "${ES_API_KEY:?ES_API_KEY is required in .env}"

ES_ENDPOINT="${ES_ENDPOINT%/}"
MODEL_ID="${E5_MODEL_ID:-multilingual-e5-large}"
PIPELINE_ID="${AI_MEMORY_PIPELINE_ID:-ai-memory}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_FILE="${SCRIPT_DIR}/ingest-pipeline.json"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

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

echo "Checking trained model ${MODEL_ID}..."
request GET "/_ml/trained_models/${MODEL_ID}" "${WORK_DIR}/model.json"
python3 - "${WORK_DIR}/model.json" "${MODEL_ID}" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
models = payload.get("trained_model_configs", [])
if len(models) != 1 or models[0].get("model_id") != sys.argv[2]:
    raise SystemExit(f"trained model {sys.argv[2]!r} was not found")
config = models[0].get("inference_config", {}).get("text_embedding", {})
if config.get("embedding_size") != 1024:
    raise SystemExit("expected a 1024-dimensional text_embedding model")
PY

request GET "/_ml/trained_models/${MODEL_ID}/_stats" "${WORK_DIR}/stats.json"
MODEL_STATE="$(
	python3 - "${WORK_DIR}/stats.json" <<'PY'
import json
import sys

stats = json.load(open(sys.argv[1], encoding="utf-8"))["trained_model_stats"][0]
print(stats.get("deployment_stats", {}).get("state", "stopped"))
PY
)"

if [[ "${MODEL_STATE}" != "started" ]]; then
	echo "Starting model deployment ${MODEL_ID}..."
	request POST "/_ml/trained_models/${MODEL_ID}/deployment/_start?wait_for=started&timeout=300s" \
		"${WORK_DIR}/start.json"
fi

echo "Applying ingest pipeline ${PIPELINE_ID}..."
request PUT "/_ingest/pipeline/${PIPELINE_ID}" "${WORK_DIR}/put.json" \
	-H 'Content-Type: application/json' \
	--data-binary "@${PIPELINE_FILE}"

echo "Smoke-testing Japanese and English embeddings separately..."
request POST "/_ingest/pipeline/${PIPELINE_ID}/_simulate" "${WORK_DIR}/simulate.json" \
	-H 'Content-Type: application/json' \
	--data-binary '{"docs":[{"_index":"00000000-0000-0000-0000-000000000000-ai-memory","_source":{"text":"昨日の会議で決まった新しい検索機能の仕様を記憶してください。"}},{"_index":"00000000-0000-0000-0000-000000000000-ai-memory","_source":{"text":"Remember the specification for the new search feature agreed in the meeting yesterday."}}]}'

python3 - "${WORK_DIR}/simulate.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
docs = payload.get("docs", [])
if len(docs) != 2:
    raise SystemExit(f"expected two simulated documents, got {len(docs)}")

embeddings = []
for language, doc in zip(("Japanese", "English"), docs, strict=True):
    if "error" in doc:
        raise SystemExit(f"{language} inference failed: {json.dumps(doc['error'], ensure_ascii=False)}")
    source = doc["doc"]["_source"]
    embedding = source.get("embedding", {}).get("e5")
    if not isinstance(embedding, list) or len(embedding) != 1024:
        raise SystemExit(
            f"{language} inference did not produce embedding.e5 with 1024 dimensions"
        )
    if not any(value != 0 for value in embedding):
        raise SystemExit(f"{language} inference produced an all-zero embedding")
    embeddings.append(embedding)

if embeddings[0] == embeddings[1]:
    raise SystemExit("Japanese and English inputs unexpectedly produced identical embeddings")

print("Japanese embedding: OK (1024 dimensions)")
print("English embedding:  OK (1024 dimensions)")
print("Applied multilingual E5 embedding pipeline successfully.")
PY
