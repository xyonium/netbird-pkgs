SHELL := /bin/sh

.PHONY: test lint

test:
	bats tests

lint:
	sh -n packaging/netbird/netbird.init
	@files="$$(git ls-files 'scripts/*.sh')"; \
	if [ -n "$$files" ]; then shellcheck -s sh $$files; fi
