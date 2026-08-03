# Vaakya — standard entry points.
# Usage: make build | make test | make bundle | make clean
# The sandbox flag is baked in because restricted shells on this machine block
# SwiftPM's sandbox-exec (harmless on normal terminals).

.PHONY: build test bundle package audit clean

build:
	SWIFTPM_DISABLE_SANDBOX=1 Scripts/build.sh

test:
	SWIFTPM_DISABLE_SANDBOX=1 Scripts/test.sh

bundle:
	Scripts/bundle.sh

package: build
	Scripts/package.sh

audit: build
	Scripts/audit-release.sh

clean:
	swift package clean
	rm -rf build dist
