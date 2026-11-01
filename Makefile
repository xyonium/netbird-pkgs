SHELL := /bin/sh

.PHONY: test lint e2e

test:
	bats tests

lint:
	sh -n packaging/netbird/netbird.init
	@files="$$(git ls-files 'scripts/*.sh')"; \
	if [ -n "$$files" ]; then shellcheck -s sh $$files; fi

e2e:
	bash tests/e2e.sh
