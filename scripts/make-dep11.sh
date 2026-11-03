#!/bin/sh
# make-dep11.sh: builds the AppStream (DEP-11) data that lets KDE Discover and GNOME Software
# list the apps in this repository, with their name, icon, description and screenshots, and
# find them in search before they are installed.
#
# Usage:  scripts/make-dep11.sh <site folder> <empty work folder>
#
# Run it after dists/stable/main/binary-amd64/Packages exists and BEFORE the Release file is
# made, because apt only accepts files that Release lists (with their hashes). It writes:
#
#   dists/stable/main/dep11/Components-amd64.yml.gz/.xz   one entry per app (from its metainfo)
#   dists/stable/main/dep11/icons-*.tar.gz                the apps' icons, ready for Discover
#
# On a Debian computer, the "appstream" package's apt hook downloads these on every
# "apt update"; Discover reads them from there.
#
# An app is included only if its .deb contains a metainfo file in /usr/share/metainfo/
# (see each app's packaging/ folder). The keyring package has none and is skipped.
#
# Why a scratch copy of the packages: appstream-generator finds the files inside a package
# through its md5sums list, and cargo-deb (which builds our apps) does not write one. So the
# generator gets its own copy of each package with that list added. The published packages in
# pool/ are never changed: they stay byte-for-byte the files from the apps' GitHub releases,
# matching their SHA256SUMS. The DEP-11 data holds no package hashes, so it is valid for them.
#
# Needs (Debian packages): appstream-generator, librsvg2-common (to draw SVG icons), dpkg-dev,
# apt-utils.

set -eu

site=$(realpath "$1")
work=$(realpath "$2")
suite=stable
section=main
arch=amd64
out="$site/dists/$suite/$section/dep11"

# The work folder is thrown away after the run; it must start empty so no old state is reused.
if [ -n "$(ls -A "$work" 2>/dev/null)" ]; then
    echo "make-dep11: work folder $work is not empty" >&2
    exit 1
fi
mkdir -p "$work/archive/pool/$section" "$work/archive/dists/$suite/$section/binary-$arch" "$work/asgen"

# 1. Scratch copy of each package, with an md5sums list added when it has none.
: > "$work/expected-ids"
for deb in "$site/pool/$section"/*.deb; do
    name=$(basename "$deb")
    # Remember which apps should get an entry: the metainfo file name is the app's ID.
    dpkg-deb -c "$deb" | sed -n 's|.* \./usr/share/metainfo/\(.*\)\.metainfo\.xml$|\1|p' >> "$work/expected-ids"
    if dpkg-deb --ctrl-tarfile "$deb" | tar -t | grep -qx './md5sums'; then
        cp "$deb" "$work/archive/pool/$section/$name"
        continue
    fi
    tree="$work/unpacked"
    rm -rf "$tree"
    dpkg-deb -R "$deb" "$tree"
    # One "md5  path" line per regular file, paths relative to /, as dpkg itself writes them.
    (cd "$tree" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | LC_ALL=C sort |
        tr '\n' '\0' | xargs -0 -r md5sum > DEBIAN/md5sums)
    dpkg-deb --root-owner-group -Zxz -b "$tree" "$work/archive/pool/$section/$name" > /dev/null
    rm -rf "$tree"
done

# 2. A package index for the scratch archive (paths match the scratch copies).
(cd "$work/archive" && apt-ftparchive packages pool > "dists/$suite/$section/binary-$arch/Packages")
xz -9k "$work/archive/dists/$suite/$section/binary-$arch/Packages"

# 3. Run appstream-generator on the scratch archive.
#    * createScreenshotsStore=false and noDownloads=true: screenshots are not downloaded or
#      re-hosted; Discover loads them from the URLs in each app's metainfo (GitHub).
#    * Icons are rendered at the sizes Discover uses and shipped in the icon tarballs.
cat > "$work/asgen/asgen-config.json" <<EOF
{
  "ProjectName": "ProtonOS",
  "ArchiveRoot": "$work/archive",
  "MediaBaseUrl": "https://protonos-linux.github.io/apt/appstream/media",
  "Backend": "debian",
  "Features": { "createScreenshotsStore": false, "noDownloads": true, "optimizePNGSize": false },
  "Suites": { "$suite": { "sections": ["$section"], "architectures": ["$arch"] } },
  "Icons": { "48x48": { "cached": true }, "64x64": { "cached": true }, "128x128": { "cached": true } }
}
EOF
(cd "$work/asgen" && appstream-generator process "$suite")

# 4. Publish only what apt downloads: the component list and the icon tarballs.
#    The uncompressed copies are needed too: apt checks the unpacked file against the hash of
#    the uncompressed name in the Release file, and silently skips the index when that entry is
#    missing (the official Debian and Ubuntu archives list both for the same reason).
data="$work/asgen/export/data/$suite/$section"
mkdir -p "$out"
cp "$data"/Components-"$arch".yml.gz "$data"/Components-"$arch".yml.xz "$out/"
cp "$data"/icons-*.tar.gz "$out/"
for f in "$out"/Components-"$arch".yml.gz "$out"/icons-*.tar.gz; do
    gzip -dkf "$f"
done

# 5. Fail the build if a package that ships a metainfo file got no entry (for example a broken
#    metainfo file), instead of silently publishing a repository where it no longer shows in
#    Discover.
for id in $(sort -u "$work/expected-ids"); do
    if ! zcat "$out/Components-$arch.yml.gz" | grep -qx "ID: $id"; then
        echo "make-dep11: $id is missing from the AppStream data" >&2
        exit 1
    fi
done

echo "make-dep11: apps listed for Discover:"
zcat "$out/Components-$arch.yml.gz" | sed -n 's/^ID: /  /p'
