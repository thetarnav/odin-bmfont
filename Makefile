.DEFAULT_GOAL := run

.PHONY: run check test test-update

run:
	odin run example

check:
	odin check . -vet

test:
	odin test . -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true

test-update:
	BMFONT_UPDATE_SNAPSHOTS=1 odin test . -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true

