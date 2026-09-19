#!/usr/bin/env bash
# Apply all ai-memory component templates idempotently.
# Semantic templates are applied unconditionally; missing inference endpoints
# are silently tolerated at template-apply time (fail only at ingest time).
set -euo pipefail

: "${ES_ENDPOINT:?ES_ENDPOINT is required in .env}"
: "${ES_API_KEY:?ES_API_KEY is required in .env}"

ES_ENDPOINT="${ES_ENDPOINT%/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/component-templates"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

put_template() {
	local name="$1" file="$2"
	curl -fsS \
		--retry 3 \
		--retry-all-errors \
		--connect-timeout 15 \
		--max-time 60 \
		-X PUT \
		-H "Authorization: ApiKey ${ES_API_KEY}" \
		-H 'Content-Type: application/json' \
		--data-binary "@${file}" \
		-o "${WORK_DIR}/${name}.json" \
		"${ES_ENDPOINT}/_component_template/${name}"
	echo "  ${name} applied."
}

echo "Applying component templates..."
put_template "ai-memory@settings" "${TEMPLATES_DIR}/ai-memory@settings.json"
put_template "ai-memory@mappings" "${TEMPLATES_DIR}/ai-memory@mappings.json"
put_template "ai-memory@semantic-e5" "${TEMPLATES_DIR}/ai-memory@semantic-e5.json"
put_template "ai-memory@semantic-jina-v3" "${TEMPLATES_DIR}/ai-memory@semantic-jina-v3.json"
put_template "ai-memory@semantic-jina-v5s" "${TEMPLATES_DIR}/ai-memory@semantic-jina-v5s.json"
echo "Component templates applied."
