# hermes-desktop-headless — developer targets
.PHONY: check smoke doctor install everyday apply-patches help

ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
CLI  := $(ROOT)bin/hermes-desktop-headless

help:
	@echo "targets: check smoke doctor install everyday apply-patches"

check:
	bash -n $(ROOT)bin/hermes-desktop-headless
	bash -n $(ROOT)bin/hermes-update
	bash -n $(ROOT)lib/common.sh
	bash -n $(ROOT)scripts/install.sh
	bash -n $(ROOT)scripts/smoke-test.sh
	bash -n $(ROOT)scripts/apply-desktop-patches.sh
	bash -n $(ROOT)scripts/verify-everyday.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -x -e SC1091 \
	    $(ROOT)bin/hermes-desktop-headless $(ROOT)lib/common.sh \
	    $(ROOT)scripts/install.sh $(ROOT)scripts/smoke-test.sh \
	    $(ROOT)scripts/apply-desktop-patches.sh $(ROOT)scripts/verify-everyday.sh; \
	else \
	  echo "shellcheck not installed (optional)"; \
	fi

smoke: check
	$(ROOT)scripts/smoke-test.sh

everyday:
	$(ROOT)scripts/verify-everyday.sh

apply-patches:
	$(ROOT)scripts/apply-desktop-patches.sh --dry-run

doctor:
	$(CLI) doctor --install-hints

install:
	$(ROOT)scripts/install.sh
