#!/usr/bin/env bash
#
# Prepare a release: bump VERSION in src/battery-notify, date the CHANGELOG, commit and tag.
# Pushing is left to you, so you can review first.
#
# Usage: scripts/release.sh <X.Y.Z>

set -euo pipefail

die() {
    echo "error: $*" >&2
    exit 1
}

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: $0 <X.Y.Z>"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

[[ "$(git branch --show-current)" == "main" ]] || die "releases are made from 'main'"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "working tree has uncommitted changes"
git rev-parse -q --verify "refs/tags/v$version" >/dev/null && die "tag v$version already exists"

grep -q '^## \[Unreleased\]' CHANGELOG.md || die "CHANGELOG.md has no '## [Unreleased]' section"
awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f && /[^[:space:]]/{found=1} END{exit !found}' CHANGELOG.md ||
    die "the [Unreleased] section of CHANGELOG.md is empty; describe the changes first"

sed -i "s/^VERSION=\".*\"/VERSION=\"$version\"/" src/battery-notify
sed -i "s/^## \[Unreleased\]/## [Unreleased]\n\n## [$version] - $(date +%F)/" CHANGELOG.md

git add src/battery-notify CHANGELOG.md
git commit --quiet -m "Release v$version"
git tag -a "v$version" -m "simple-battery-notify v$version"

echo "Created commit and tag v$version. Review with 'git show', then publish with:"
echo "    git push --follow-tags origin main"
