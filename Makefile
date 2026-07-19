.PHONY: bootstrap format analyze test lint lint-test hook-test check proto proto-check marionette-install hooks-install hooks-uninstall

bootstrap:
	bash scripts/dart-tool.sh pub get
	bash scripts/dart-tool.sh run melos bootstrap
	bash scripts/git-hooks/install.sh

format:
	bash scripts/dart-tool.sh format --output=none --set-exit-if-changed .

analyze:
	bash scripts/dart-tool.sh analyze --fatal-infos .

test:
	bash scripts/quality/run-tests.sh

lint:
	bash scripts/lint/repository-boundaries.sh

lint-test:
	bash scripts/lint/test-repository-boundaries.sh

hook-test:
	bash scripts/git-hooks/test-pre-commit.sh

check: format analyze lint lint-test hook-test test

proto:
	bash scripts/proto/generate.sh

proto-check:
	bash scripts/proto/check.sh

marionette-install:
	bash scripts/dart-tool.sh pub global activate marionette_mcp 0.6.0

hooks-install:
	bash scripts/git-hooks/install.sh

hooks-uninstall:
	bash scripts/git-hooks/uninstall.sh
