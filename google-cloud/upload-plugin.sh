#!/usr/bin/env bash
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required in .env}"
: "${GCP_REGION:?GCP_REGION is required in .env}"

PLUGIN_BUCKET="${PLUGIN_BUCKET:-hackathon-ai-memory-plugin}"
PLUGIN_SITE_DIR="${PLUGIN_SITE_DIR:-google-cloud/plugin-site}"
PLUGIN_PUBLIC_URL="${PLUGIN_PUBLIC_URL:-https://storage.googleapis.com/${PLUGIN_BUCKET}}"

if [[ ! -f "${PLUGIN_SITE_DIR}/marketplace.json" || ! -f "${PLUGIN_SITE_DIR}/plugins/ai-memory.zip" ]]; then
	echo "Missing rendered marketplace artifacts. Run: make render-plugin" >&2
	exit 1
fi

if gcloud storage buckets describe "gs://${PLUGIN_BUCKET}" \
	--project="${GCP_PROJECT_ID}" >/dev/null 2>&1; then
	echo "Bucket gs://${PLUGIN_BUCKET} already exists; skipping create."
else
	gcloud storage buckets create "gs://${PLUGIN_BUCKET}" \
		--project="${GCP_PROJECT_ID}" \
		--location="${GCP_REGION}" \
		--uniform-bucket-level-access
fi

gcloud storage buckets update "gs://${PLUGIN_BUCKET}" \
	--no-public-access-prevention \
	--web-main-page-suffix=index.html

gcloud storage buckets add-iam-policy-binding "gs://${PLUGIN_BUCKET}" \
	--member=allUsers \
	--role=roles/storage.objectViewer

gcloud storage rsync "${PLUGIN_SITE_DIR}" "gs://${PLUGIN_BUCKET}" \
	--recursive

echo "Plugin distribution URL: ${PLUGIN_PUBLIC_URL}/index.html"
