# hermes-desktop-headless — developer targets
.PHONY: check smoke doctor install help

ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
CLI  := $(ROOT)bin/hermes-desktop-headless

help:
	@echo "targets: check smoke doctor install"

check:
	bash -n $(ROOT)bin/hermes-desktop-headless
	bash -n $(ROOT)lib/common.sh
	bash -n $(ROOT)scripts/install.sh
	bash -n $(ROOT)scripts/smoke-test.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -x \
	    -e SC1091 \
	    $(ROOT)bin/hermes-desktop-headless $(ROOT)lib/common.sh \
	    $(ROOT)scripts/install.sh $(ROOT)scripts/smoke-test.sh; \
	else \
	  echo "shellcheck not installed (optional)"; \
	fi

smoke: check
	$(ROOT)scripts/smoke-test.sh

doctor:
	$(CLI) doctor --install-hints

install:
	$(ROOT)scripts/install.sh
