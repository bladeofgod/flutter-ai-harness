.PHONY: setup flutter-sdk bootstrap format analyze test integration-test integration-runner-test spec-check spec-test lint lint-test hook-test evidence-lint evidence-test harness-check harness-test check proto proto-check marionette-install hooks-install hooks-uninstall

setup: flutter-sdk
	$(MAKE) bootstrap

flutter-sdk:
	bash scripts/prepare-flutter.sh

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

integration-test:
	INTEGRATION_DEVICE="$(INTEGRATION_DEVICE)" bash scripts/quality/run-integration-tests.sh

integration-runner-test:
	bash scripts/quality/test-integration-runner.sh

spec-check:
	bash scripts/dart-tool.sh run tool/validate_ui_specs.dart

spec-test:
	bash scripts/quality/test-ui-specs.sh

lint:
	bash scripts/lint/repository-boundaries.sh

lint-test:
	bash scripts/lint/test-repository-boundaries.sh

hook-test:
	bash scripts/git-hooks/test-pre-commit.sh

evidence-lint:
	bash scripts/quality/evidence-lint.sh

evidence-test:
	bash scripts/quality/test-evidence.sh

harness-check:
	bash scripts/dart-tool.sh run tool/harness_check.dart

harness-test:
	bash scripts/quality/test-harness.sh

check: format analyze harness-check spec-check lint lint-test harness-test spec-test integration-runner-test hook-test evidence-lint evidence-test proto-check test

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
