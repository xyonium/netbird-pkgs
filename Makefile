SHELL := /bin/sh

.PHONY: test lint e2e build feed istore

test:
	bats tests

lint:
	sh -n packaging/netbird/netbird.init
	@files="$$(git ls-files 'scripts/*.sh')"; \
	if [ -n "$$files" ]; then shellcheck -s sh $$files; fi

e2e:
	bash tests/e2e.sh

build:
	scripts/build-netbird.sh --arch $${ARCH:-x86_64} --version $${VERSION:?} \
		--commit $${COMMIT:?} --source $${SOURCE:-src} --outdir $${OUTDIR:-dist}

feed:
	scripts/make-feed.sh --dir $${FEED:-dist/feed} --arch $${ARCH:-x86_64} --retain 2

istore:
	scripts/make-istore.sh --ipk-dir $${IPK_DIR:-dist} --outdir $${OUTDIR:-dist/istore} \
		--version $${VERSION:?} --pkg-release $${PKG_RELEASE:-1}
