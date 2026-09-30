# Releasing

This repo is **upstream**. The AUR package lives in a separate git repo
(`ssh://aur@aur.archlinux.org/simple-battery-notify.git`) that holds only `PKGBUILD` and
`.SRCINFO`. The source of truth for packaging is
[`packaging/aur/PKGBUILD`](packaging/aur/PKGBUILD); its `pkgver`, `pkgrel`
and checksums are filled in at publish time, so never edit them by hand there.

## Versioning rules

- The version is `VERSION="X.Y.Z"` in `src/battery-notify`. It is changed only by
  `scripts/release.sh`.
- [SemVer](https://semver.org/): bump **MAJOR** for incompatible CLI or config
  changes, **MINOR** for new features, **PATCH** for fixes.
- Tags before 2.0 have no `v` (`1.0.0` … `1.0.5`); leave them as they are.
- Tags are annotated, named `vX.Y.Z`, and point at the "Release vX.Y.Z" commit
  on `main`. **Never move or delete a pushed tag**: the AUR checksum is of that
  tag's tarball. If a release is broken, release a new PATCH version.
- AUR `pkgrel` is `1` for each new version. Bump it only when the packaging
  changes but the upstream code does not.
- While working, add entries under `## [Unreleased]` in `CHANGELOG.md`.

## Scripts

| Script | Does |
|---|---|
| `scripts/release.sh X.Y.Z` | Sets `VERSION`, turns `[Unreleased]` into `[X.Y.Z] - date` in the changelog, commits "Release vX.Y.Z", creates tag `vX.Y.Z`. Does not push. |
| `scripts/release-notes.sh X.Y.Z` | Prints the changelog entry for X.Y.Z (used as the GitHub Release notes). |
| `scripts/publish-aur.sh X.Y.Z [pkgrel]` | Clones the AUR repo, fills in the template, updates checksums, test-builds, writes `.SRCINFO`, commits and pushes. `AUR_DRY_RUN=1` skips the push. |

## Normal release

```bash
git switch main && git pull
# make sure CHANGELOG.md [Unreleased] describes the changes
make integration CHARGER=1          # real UPower checks, on your desktop (CI can't)
scripts/release.sh 1.1.0            # commit + tag, local only
git show                            # review
git push --follow-tags origin main  # pushing the tag starts the workflow
```

The workflow [`.github/workflows/release.yml`](.github/workflows/release.yml)
then runs three jobs (watch them in the repo's **Actions** tab):

1. **check**: the tag exists, matches `VERSION` in `src/battery-notify`, and has a
   changelog entry. If anything is wrong, nothing is published.
2. **github-release**: creates the GitHub Release with the changelog entry as notes.
3. **aur**: runs `scripts/publish-aur.sh` in an Arch Linux container.

Every step is commented in the workflow file. Re-running a failed workflow is
safe (Actions → the run → "Re-run failed jobs"): an existing release is kept,
and the AUR is not touched if it is already up to date.

## Packaging-only fix (pkgrel bump)

Commit the change to `packaging/aur/PKGBUILD` on `main`, then **Actions →
Release → Run workflow**, branch `main`, `version` = current release,
`pkgrel` = `2` (then 3, ...). Only **check** and **aur** run.

Or manually: `scripts/publish-aur.sh 1.1.0 2`.

## One-time setup

### Your own AUR SSH access (for manual publishing)

Check it works: `ssh aur@aur.archlinux.org help` should list commands. If not:

1. `ssh-keygen -t ed25519 -f ~/.ssh/aur`
2. Add to `~/.ssh/config`:
   ```
   Host aur.archlinux.org
     User aur
     IdentityFile ~/.ssh/aur
   ```
3. Paste `~/.ssh/aur.pub` into <https://aur.archlinux.org> → My Account →
   SSH Public Key.

### The `AUR_SSH_PRIVATE_KEY` secret (for the workflow)

Use a separate key only for CI, so it can be revoked on its own.

1. `ssh-keygen -t ed25519 -f ~/.ssh/aur_ci -C "simple-battery-notify GitHub Actions" -N ""`
   (no passphrase: CI cannot type one).
2. Add `~/.ssh/aur_ci.pub` to your AUR account, on a new line below your
   personal key (the field accepts several keys, one per line).
3. Copy the private key (`cat ~/.ssh/aur_ci`, including the BEGIN/END lines)
   into GitHub: repo **Settings → Secrets and variables → Actions → New
   repository secret**, name `AUR_SSH_PRIVATE_KEY`.
4. Delete `~/.ssh/aur_ci` and `~/.ssh/aur_ci.pub` locally; GitHub keeps its copy.

To revoke CI access, remove that public key from your AUR account.

If publishing fails with `Permission denied (publickey)`, the AUR does not know
the key in the secret. The "Set up build user and SSH" step logs that key's
fingerprint; compare it with `ssh-keygen -lf ~/.ssh/aur_ci.pub`, and check that
the public key is saved on your AUR account (the page needs "Update" clicked).

## Manual release

Use this when Actions is down, the workflow is broken, or you want to bypass
it. Each section below is what the workflow job of the same name does.
Requires `pacman-contrib`, `github-cli` (run `gh auth login` once) and your
AUR SSH key.

If you don't want the workflow to run as well, disable it first:
Actions → Release → "..." → Disable workflow.

```bash
scripts/release.sh 1.1.0
git push --follow-tags origin main
V=1.1.0
```

### Job 1: check

```bash
git rev-parse --verify "refs/tags/v$V"            # the tag exists
git show "v$V:src/battery-notify" | grep '^VERSION='    # must print VERSION="1.1.0"
scripts/release-notes.sh "$V"                     # the changelog entry exists
```

### Job 2: github-release

```bash
scripts/release-notes.sh "$V" > /tmp/notes.md
gh release create "v$V" --title "v$V" --notes-file /tmp/notes.md --verify-tag
```

Or on GitHub: Releases → Draft a new release → choose the tag → paste the notes.

### Job 3: aur

```bash
AUR_DRY_RUN=1 scripts/publish-aur.sh "$V"   # optional rehearsal; prints where the result is
scripts/publish-aur.sh "$V"
```

What `publish-aur.sh` does, one command at a time:

```bash
git clone ssh://aur@aur.archlinux.org/simple-battery-notify.git /tmp/aur-simple-battery-notify
cp packaging/aur/PKGBUILD /tmp/aur-simple-battery-notify/
cd /tmp/aur-simple-battery-notify
sed -i -e "s/^pkgver=.*/pkgver=$V/" -e "s/^pkgrel=.*/pkgrel=1/" PKGBUILD
updpkgsums                          # downloads the tag tarball, writes sha256sums
makepkg --cleanbuild --force        # test build
makepkg --printsrcinfo > .SRCINFO   # the AUR requires this to match PKGBUILD
git add PKGBUILD .SRCINFO
git commit -m "Update to $V-1"
git push origin HEAD:master         # the AUR only accepts the master branch
```

## Testing locally

```bash
make check                                                   # shellcheck + shfmt, same as CI
make test                                                    # bats test suite, same as CI
make integration                                             # real UPower checks (CHARGER=1: unplug/replug too)
make DESTDIR="$PWD/stage" PREFIX=/usr install && find stage  # what gets installed
AUR_DRY_RUN=1 scripts/publish-aur.sh X.Y.Z                   # full AUR build of a tag, no push (tags vX.Y.Z only:
                                                             # the old ones have no Makefile)
```
