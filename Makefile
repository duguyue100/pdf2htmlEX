IMAGE := pdf2htmlex-builder
STATIC_IMAGE := pdf2htmlex-static
TAG ?= dev

# All building/testing happens inside docker. Never on the host.

.PHONY: build test shell static clean

# fast dev loop: shared-ish deps from source, dynamic system libs, smoke tested
build:
	docker build -t $(IMAGE):$(TAG) .

test: build
	@echo "build (including smoke test) passed"

shell:
	docker run --rm -it -v $(CURDIR):/work -w /work $(IMAGE):$(TAG) bash

# fully static release binary for this architecture (musl)
static:
	docker build -f Dockerfile.alpine-static -t $(STATIC_IMAGE) .
	mkdir -p dist
	docker run --rm $(STATIC_IMAGE) tar -cC /out . | tar -xC dist
	@echo "tarball in dist/"

clean:
	rm -rf build build-macos dist share/*.min.css share/pdf2htmlEX.min.js src/pdf2htmlEX-config.h src/util/css_const.h share/base.css share/fancy.css share/pdf2htmlEX.js pdf2htmlEX.1 test/test.py
