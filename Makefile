# Vaakya Work Safe. Local dictation only.
# `make build` never installs, kills processes, or uses a keychain identity.

.PHONY: build test bundle install package audit clean

build:
	Scripts/build.sh

test:
	Scripts/test.sh

bundle:
	Scripts/bundle.sh

install: build
	Scripts/install-work-safe.sh

package: build
	Scripts/package.sh

audit: build
	Scripts/audit-release.sh

clean:
	swift package clean
	rm -rf build dist
