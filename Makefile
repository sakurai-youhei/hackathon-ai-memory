include .env
export

PLUGIN_BUCKET ?= hackathon-ai-memory-plugin
PLUGIN_SITE_DIR := google-cloud/plugin-site
PLUGIN_PUBLIC_URL := https://storage.googleapis.com/$(PLUGIN_BUCKET)/index.html
VENV_PYTHON := .venv/bin/python
VENV_PYTHON_VERSION ?= 3.14

.PHONY: create-venv upload-plugin render-plugin

create-venv: $(VENV_PYTHON)

$(VENV_PYTHON):
	uv venv --python $(VENV_PYTHON_VERSION) .venv

upload-plugin:
	@./google-cloud/upload-plugin.sh

render-plugin: $(VENV_PYTHON)
	@test -n "$(KB_ENDPOINT)" || (echo "KB_ENDPOINT is required in .env" >&2; exit 1)
	@$(VENV_PYTHON) -c "import jinja2" 2>/dev/null || $(VENV_PYTHON) -m pip install jinja2
	@$(VENV_PYTHON) google-cloud/render-plugin.py
