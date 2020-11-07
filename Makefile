.PHONY: shellcheck build

build:
	./build.sh
shellcheck:
	@shellcheck bin/* build.sh
