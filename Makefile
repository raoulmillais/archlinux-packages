.PHONY: shellcheck build

clean:
	sudo rm -rf {out,work}
build:
	sudo ./build.sh
shellcheck:
	@shellcheck bin/* build.sh
