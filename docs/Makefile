all: build

node_modules: package.json package-lock.json
	npm ci

build: node_modules
	npm run build

dev: node_modules
	npm run dev

.PHONY: all build dev
