.DEFAULT_GOAL := run

.PHONY: run check

run:
	odin run example

check:
	odin check . -vet
