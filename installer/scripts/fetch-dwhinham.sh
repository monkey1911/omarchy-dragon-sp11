#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Download the Surface Pro 11 packages the installer takes from Dale Whinham's
# repository (github.com/dwhinham/archlinux-repo, see upstream.lock), and check
# every package signature against the pinned key.
#
# usage: fetch-dwhinham.sh OUT_DIR
#   OUT_DIR/ receives <pkg>.pkg.tar.zst and .sig for each package below, and
#   OUT_DIR/versions.txt ("name version" lines). Needs curl, gpg, git, tar.
#
# The newest version of each package is whatever the repository database
# lists; the kernel must be at least SP11_MIN_LINUX_SP11.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

out="${1:?usage: fetch-dwhinham.sh OUT_DIR}"
load_lock
for t in curl gpg git tar; do
	command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"
done

packages=(
	linux-sp11
	linux-sp11-headers
	linux-sp11-dtbs
	dwhinham-keyring
	sp11-ath12k-board
	sp11-audioreach-topology
	alsa-ucm-conf-sp11
	sp11-grab-fw
	sp11-mac-fixup
)

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
mkdir -p "$out"

# --- the signing key, from the pinned keyring commit --------------------------
info "dwhinham key from $DWHINHAM_KEYRING_REPO @ $DWHINHAM_KEYRING_SHA"
git -C "$work" init -q keyring
git -C "$work/keyring" remote add origin "$DWHINHAM_KEYRING_REPO"
git -C "$work/keyring" fetch -q --depth 1 origin "$DWHINHAM_KEYRING_SHA" ||
	die "cannot fetch $DWHINHAM_KEYRING_SHA"
git -C "$work/keyring" show "$DWHINHAM_KEYRING_SHA:dwhinham-keyring/dwhinham.gpg" >"$work/dwhinham.gpg"
export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --import "$work/dwhinham.gpg"
gpg --batch --with-colons --list-keys "$DWHINHAM_KEY_FPR" >/dev/null 2>&1 ||
	die "the keyring at $DWHINHAM_KEYRING_SHA does not hold $DWHINHAM_KEY_FPR"

# verify FILE: detached signature FILE.sig made by the pinned primary key.
verify() {
	local f="$1" status
	[[ -f $f.sig ]] || die "$(basename "$f") has no signature"
	status="$(gpg --batch --status-fd 1 --verify "$f.sig" "$f" 2>/dev/null)" ||
		die "bad signature: $(basename "$f")"
	# VALIDSIG <signing fpr> ... <primary key fpr> is the last field.
	awk -v want="$DWHINHAM_KEY_FPR" '
		$2 == "VALIDSIG" && toupper($NF) == toupper(want) { ok = 1 }
		END { exit !ok }
	' <<<"$status" || die "$(basename "$f") is not signed by $DWHINHAM_KEY_FPR"
}

# --- the database -------------------------------------------------------------
db="$DWHINHAM_REPO_NAME.db"
info "database $DWHINHAM_REPO_URL/$db"
curl -fsSL --retry 3 -o "$work/$db" "$DWHINHAM_REPO_URL/$db"
if curl -fsSL --retry 3 -o "$work/$db.sig" "$DWHINHAM_REPO_URL/$db.sig" 2>/dev/null; then
	verify "$work/$db"
else
	echo "    (the database is unsigned; every package is checked below)"
fi
mkdir -p "$work/db"
tar -xzf "$work/$db" -C "$work/db"

# desc_field DESC FIELD: first value of %FIELD% in a pacman desc file.
desc_field() {
	awk -v f="%$2%" '$0 == f { getline; print; exit }' "$1"
}

: >"$out/versions.txt"
for name in "${packages[@]}"; do
	desc=""
	for d in "$work"/db/*/desc; do
		if [[ $(desc_field "$d" NAME) == "$name" ]]; then
			desc="$d"
			break
		fi
	done
	[[ -n $desc ]] || die "$name is not in the $DWHINHAM_REPO_NAME database"
	file="$(desc_field "$desc" FILENAME)"
	version="$(desc_field "$desc" VERSION)"
	sha="$(desc_field "$desc" SHA256SUM)"
	[[ $file =~ ^[A-Za-z0-9@._+-]+\.pkg\.tar\.zst$ ]] || die "unexpected file name for $name: $file"
	info "$name $version"
	curl -fsSL --retry 3 -o "$out/$file" "$DWHINHAM_REPO_URL/$file"
	curl -fsSL --retry 3 -o "$out/$file.sig" "$DWHINHAM_REPO_URL/$file.sig"
	if [[ -n $sha ]]; then
		echo "$sha  $out/$file" | sha256sum -c --quiet - || die "$file does not match the database checksum"
	fi
	verify "$out/$file"
	echo "$name $version" >>"$out/versions.txt"
done

# Floor: refuse an older kernel than upstream.lock names.
got="$(awk '$1 == "linux-sp11" { print $2 }' "$out/versions.txt")"
[[ "$(printf '%s\n%s\n' "$SP11_MIN_LINUX_SP11" "$got" | sort -V | tail -n 1)" == "$got" ]] ||
	die "linux-sp11 $got is older than $SP11_MIN_LINUX_SP11"
info "fetched ${#packages[@]} packages from [$DWHINHAM_REPO_NAME] into $out"
