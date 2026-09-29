#!/usr/bin/env bash
#
# Publish packaging/aur/PKGBUILD to the AUR for an already-pushed tag.
#
# Usage: scripts/publish-aur.sh <version> [pkgrel]
#   version  Upstream version without the "v" (the tag v<version> must exist on GitHub).
#   pkgrel   Package release, default 1. Bump only for packaging-only fixes.
#
# Environment:
#   AUR_DRY_RUN=1   Do everything except the final `git push` to the AUR.
#   AUR_WORKDIR     Where to clone the AUR repo (default: a temporary directory).
#   AUR_REMOTE      AUR git URL (default: the real one; override for testing).
#
# Requires: git, makepkg, updpkgsums (pacman-contrib), and SSH access to aur@aur.archlinux.org.
# Used by both .github/workflows/release.yml and manual releases (see RELEASING.md).

set -euo pipefail

PKGNAME="simple-battery-notify"
AUR_REMOTE="${AUR_REMOTE:-ssh://aur@aur.archlinux.org/${PKGNAME}.git}"

die() {
    echo "error: $*" >&2
    exit 1
}

version="${1:-}"
pkgrel="${2:-1}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: $0 <X.Y.Z> [pkgrel]"
[[ "$pkgrel" =~ ^[1-9][0-9]*$ ]] || die "pkgrel must be a positive integer"

for cmd in git makepkg updpkgsums; do
    command -v "$cmd" >/dev/null || die "'$cmd' not found"
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="$repo_root/packaging/aur/PKGBUILD"
workdir="${AUR_WORKDIR:-$(mktemp -d)}"

echo ":: Cloning AUR repo into $workdir"
git clone --quiet "$AUR_REMOTE" "$workdir"
cd "$workdir"

cp "$template" PKGBUILD
sed -i -e "s/^pkgver=.*/pkgver=$version/" -e "s/^pkgrel=.*/pkgrel=$pkgrel/" PKGBUILD

echo ":: Updating checksums"
updpkgsums

echo ":: Verifying the package builds"
makepkg --cleanbuild --force --noconfirm --nodeps
rm -rf src pkg ./*.pkg.tar.*

makepkg --printsrcinfo >.SRCINFO

git add PKGBUILD .SRCINFO
if git diff --cached --quiet; then
    echo ":: Nothing changed; AUR already up to date."
    exit 0
fi

git -c user.name="${GIT_AUTHOR_NAME:-Davi Alves Sampaio}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-davialvessampaio00@gmail.com}" \
    commit --quiet -m "Update to $version-$pkgrel"
git --no-pager show --stat HEAD

if [[ "${AUR_DRY_RUN:-0}" == "1" ]]; then
    echo ":: Dry run: not pushing. Result is in $workdir"
    exit 0
fi

echo ":: Pushing to AUR"
git push origin HEAD:master
echo ":: Published $PKGNAME $version-$pkgrel"
