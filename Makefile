include .env
export

PLUGIN_BUCKET ?= hackathon-ai-memory-plugin
PLUGIN_SITE_DIR := google-cloud/plugin-site
PLUGIN_PUBLIC_URL := https://storage.googleapis.com/$(PLUGIN_BUCKET)
VENV_PYTHON := .venv/bin/python
VENV_PYTHON_VERSION ?= 3.14

.PHONY: create-venv upload-plugin render-plugin bump-plugin-version

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
