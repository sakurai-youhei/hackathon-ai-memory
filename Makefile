include .env
export

PLUGIN_BUCKET ?= hackathon-ai-memory-plugin
PLUGIN_SITE_DIR := google-cloud/plugin-site
PLUGIN_PUBLIC_URL := https://storage.googleapis.com/$(PLUGIN_BUCKET)
KIBANA_API_KEY_CREATE_URL := $(patsubst %/,%,$(KB_ENDPOINT))/app/management/security/api_keys/create
VENV_PYTHON := .venv/bin/python
VENV_PYTHON_VERSION ?= 3.14

# Which embedding models to enable. Space-separated: e5 bge_m3 qwen3
# Default to e5 only (works immediately; BGE-M3/Qwen3 need TEI on Cloud Run).
AI_MEMORY_MODELS ?= e5
# Cloud Run region for TEI services (co-located with Elasticsearch in asia-northeast1).
TEI_REGION ?= asia-northeast1
TEI_IMAGE ?= ghcr.io/huggingface/text-embeddings-inference:cpu-1.9

.PHONY: create-venv upload-plugin render-plugin bump-plugin-version issue-api-key setup-elasticsearch deploy-tei

create-venv: $(VENV_PYTHON)

$(VENV_PYTHON):
	uv venv --python $(VENV_PYTHON_VERSION) .venv

upload-plugin: render-plugin
	@./google-cloud/upload-plugin.sh

bump-plugin-version: $(VENV_PYTHON)
	@$(VENV_PYTHON) google-cloud/bump-plugin-version.py
	@$(MAKE) upload-plugin

render-plugin: $(VENV_PYTHON)
	@test -n "$(ES_ENDPOINT)" || (echo "ES_ENDPOINT is required in .env" >&2; exit 1)
	@test -n "$(KB_ENDPOINT)" || (echo "KB_ENDPOINT is required in .env" >&2; exit 1)
	@test -n "$(PLUGIN_PUBLIC_URL)" || (echo "PLUGIN_PUBLIC_URL is required" >&2; exit 1)
	@$(VENV_PYTHON) -c "import jinja2" 2>/dev/null || $(VENV_PYTHON) -m pip install jinja2
	@PLUGIN_PUBLIC_URL="$(PLUGIN_PUBLIC_URL)" $(VENV_PYTHON) google-cloud/render-plugin.py

issue-api-key:
	@test -n "$(KB_ENDPOINT)" || (echo "KB_ENDPOINT is required in .env" >&2; exit 1)
	@test -n "$(uuid)" || (echo "Usage: make issue-api-key uuid=<UUID>" >&2; exit 2)
	@python3 elastic-cloud/render-api-key-instructions.py

setup-elasticsearch: $(VENV_PYTHON)
	@test -n "$(ES_ENDPOINT)" || (echo "ES_ENDPOINT is required in .env" >&2; exit 1)
	@test -n "$(ES_API_KEY)" || (echo "ES_API_KEY is required in .env" >&2; exit 1)
	@$(VENV_PYTHON) -c "import jinja2" 2>/dev/null || $(VENV_PYTHON) -m pip install jinja2
	@AI_MEMORY_MODELS="$(AI_MEMORY_MODELS)" VENV_PYTHON="$(VENV_PYTHON)" \
		./elastic-cloud/setup-elasticsearch.sh

deploy-tei:
	@test -n "$(GCP_PROJECT_ID)" || (echo "GCP_PROJECT_ID is required in .env" >&2; exit 1)
	@test -n "$(TEI_API_KEY)" || (echo "TEI_API_KEY is required in .env" >&2; exit 1)
	@AI_MEMORY_MODELS="$(AI_MEMORY_MODELS)" TEI_REGION="$(TEI_REGION)" TEI_IMAGE="$(TEI_IMAGE)" ./google-cloud/deploy-tei.sh
