# This is a wrapper to do lint checks
#
# All make targets related to lint are defined in this file.

##@ Lint

GITHUB_ACTION ?=
LINT_BUILD_TAGS ?= e2e,celvalidation,conformance,experimental,benchmark,resilience

.PHONY: lint
lint: ## Run all linter of code sources, including golint, yamllint, whitenoise lint and codespell.

# lint-deps is run separately in CI to separate the tooling install logs from the actual output logs generated
# by the lint tooling.
.PHONY: lint-deps
lint-deps: ## Everything necessary to lint

GOLANGCI_LINT_FLAGS ?=
.PHONY: lint.golint
lint: lint.golint
lint.golint:
	@$(LOG_TARGET)
	@go tool golangci-lint run $(GOLANGCI_LINT_FLAGS) --build-tags=$(LINT_BUILD_TAGS) --config=tools/linter/golangci-lint/.golangci.yml

.PHONY: lint.yamllint
lint: lint.yamllint
lint-deps: $(tools/yamllint)
lint.yamllint: $(tools/yamllint)
	@$(LOG_TARGET)
	$(tools/yamllint) --config-file=tools/linter/yamllint/.yamllint $$(git ls-files :*.yml :*.yaml | xargs -L1 dirname | sort -u)

CODESPELL_FLAGS ?= $(if $(GITHUB_ACTION),--disable-colors)
.PHONY: lint.codespell
lint: lint.codespell
lint-deps: $(tools/codespell)
lint.codespell: CODESPELL_SKIP := $(shell cat tools/linter/codespell/.codespell.skip | tr \\n ',')
lint.codespell: $(tools/codespell)
	@$(LOG_TARGET)
# This ::add-matcher/::remove-matcher business is based on
# https://github.com/codespell-project/actions-codespell/blob/2292753ad350451611cafcbabc3abe387491339a/entrypoint.sh
# We do this here instead of just using
# codespell-project/codespell-problem-matcher@v1 so that the matcher
# doesn't apply to the other linters that `make lint` also runs.
#
# This recipe is written a little awkwardly with everything running in
# one shell, this is because we want the ::remove-matcher lines to get
# printed whether or not it finds complaints.
	@PS4=; set -e; { \
	  if test -n "$$GITHUB_ACTION"; then \
	    printf '::add-matcher::$(CURDIR)/tools/linter/codespell/matcher.json\n'; \
	    trap "printf '::remove-matcher owner=codespell-matcher-default::\n::remove-matcher owner=codespell-matcher-specified::\n'" EXIT; \
	  fi; \
	  (set -x; $(tools/codespell) $(CODESPELL_FLAGS) --skip $(CODESPELL_SKIP) --ignore-words tools/linter/codespell/.codespell.ignorewords --check-filenames --check-hidden -q2); \
	}

.PHONY: lint.whitenoise
lint: lint.whitenoise
lint-deps: $(tools/whitenoise)
lint.whitenoise: $(tools/whitenoise)
	@$(LOG_TARGET)
	$(tools/whitenoise)


.PHONY: lint.shellcheck
lint: lint.shellcheck
lint-deps: $(tools/shellcheck)
lint.shellcheck: $(tools/shellcheck)
	@$(LOG_TARGET)
	$(tools/shellcheck) tools/hack/*.sh

.PHONY: fix-golint
fix-golint: lint.fix-golint ## Run golangci-lint and gci to automatically fix code lint issues

.PHONY: lint.fix-golint
lint.fix-golint:
	@$(LOG_TARGET)
	$(MAKE) lint.golint GOLANGCI_LINT_FLAGS="--fix"
	find . -name "*.go" | xargs go tool gci write --skip-generated -s Standard -s Default -s "Prefix(github.com/envoyproxy/gateway)"

.PHONY: gen-check
gen-check: format generate manifests protos go.testdata.complete
	@$(LOG_TARGET)
	@if [ ! -z "`git status --porcelain`" ]; then \
		$(call errorlog, ERROR: Some files need to be updated, please run 'make generate', 'make manifests' and 'make protos' to include any changed files to your PR); \
		git diff --exit-code; \
	fi

.PHONY: licensecheck
licensecheck: ## Check license headers are present.
	@$(LOG_TARGET)
	tools/boilerplate/verify-boilerplate.sh

.PHONY: latest-release-check
latest-release-check: ## Check if latest release and tag are created properly.
	@$(LOG_TARGET)
	sh tools/hack/check-latest-release.sh

.PHONY: lint.markdown
lint.markdown:
	markdownlint -c .github/markdown_lint_config.json site/content/*

.PHONY: lint.dependabot
lint: lint.dependabot
lint.dependabot: ## Check if dependabot configuration is valid
	@npx @bugron/validate-dependabot-yaml .github/dependabot.yml
