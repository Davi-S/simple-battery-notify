#!/usr/bin/env bash
#
# Print the CHANGELOG.md section of one version, to use as GitHub Release notes.
# Fails if the section is missing or empty.
#
# Usage: scripts/release-notes.sh <X.Y.Z>

set -euo pipefail

version="${1:?usage: $0 <X.Y.Z>}"
changelog="$(dirname "${BASH_SOURCE[0]}")/../CHANGELOG.md"

# Lines after "## [X.Y.Z]" up to the next "## [" heading.
notes="$(awk -v heading="## [$version]" '
    index($0, heading) == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found' "$changelog")"

if [[ -z "${notes//[[:space:]]/}" ]]; then
    echo "error: no CHANGELOG.md entry for $version" >&2
    exit 1
fi

printf '%s\n' "$notes"
