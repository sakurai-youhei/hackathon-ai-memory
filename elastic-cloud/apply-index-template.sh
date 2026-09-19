#!/usr/bin/env bash
# Apply the ai-memory index template idempotently and verify it resolves correctly.
set -euo pipefail

: "${ES_ENDPOINT:?ES_ENDPOINT is required in .env}"
: "${ES_API_KEY:?ES_API_KEY is required in .env}"

ES_ENDPOINT="${ES_ENDPOINT%/}"
TEMPLATE_ID="${AI_MEMORY_INDEX_TEMPLATE_ID:-ai-memory}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/index-template.json"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

request() {
	local method="$1" path="$2" output="$3"
	shift 3
	curl -fsS \
		--retry 3 \
		--retry-all-errors \
		--connect-timeout 15 \
		--max-time 60 \
		-X "${method}" \
		-H "Authorization: ApiKey ${ES_API_KEY}" \
		"$@" \
		-o "${output}" \
		"${ES_ENDPOINT}${path}"
}

echo "Applying index template ${TEMPLATE_ID}..."
request PUT "/_index_template/${TEMPLATE_ID}" "${WORK_DIR}/put.json" \
	-H 'Content-Type: application/json' \
	--data-binary "@${TEMPLATE_FILE}"

echo "Verifying index template ${TEMPLATE_ID}..."
request POST "/_index_template/_simulate_index/00000000-0000-0000-0000-000000000000-ai-memory" \
	"${WORK_DIR}/simulate.json"

python3 - "${WORK_DIR}/simulate.json" "${TEMPLATE_ID}" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
template = payload.get("template", {})
mappings = template.get("mappings", {})
if not mappings:
    raise SystemExit(f"index template {sys.argv[2]!r} produced no mappings")
props = mappings.get("properties", {})
required = {"@timestamp", "owner", "text", "title"}
missing = required - props.keys()
if missing:
    raise SystemExit(f"missing expected fields in resolved template: {missing}")
print(f"Index template {sys.argv[2]!r} applied and verified ({len(props)} fields resolved).")
PY
