include .env
export

PLUGIN_BUCKET ?= hackathon-ai-memory-plugin
PLUGIN_SITE_DIR := google-cloud/plugin-site
PLUGIN_PUBLIC_URL := https://storage.googleapis.com/$(PLUGIN_BUCKET)/

.PHONY: create-plugin-bucket

create-plugin-bucket:
	@./google-cloud/create-plugin-bucket.sh
