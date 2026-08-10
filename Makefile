# Vaakya standard entry points.
# `make build` only creates build/Vaakya.app. Installation is explicit.

.PHONY: build test bundle install package audit clean

build:
	Scripts/build.sh

test:
	Scripts/test.sh

bundle:
	Scripts/bundle.sh

install: build
	Scripts/install-user.sh

package: build
	Scripts/package.sh

audit: build
	Scripts/audit-release.sh

clean:
	swift package clean
	rm -rf build dist
