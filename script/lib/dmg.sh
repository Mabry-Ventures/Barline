#!/usr/bin/env bash

# Builds and verifies Barline's drag-to-Applications disk image with the
# system hdiutil. Signing, notarization, and stapling stay in release.sh.

barline_build_dmg() {
    local app="$1" dmg="$2" volume_name="$3"
    local staging
    [[ -d "$app/Contents" ]] || { printf 'error: not an app bundle: %s\n' "$app" >&2; return 1; }
    [[ ! -e "$dmg" ]] || { printf 'error: refusing to overwrite existing disk image: %s\n' "$dmg" >&2; return 1; }
    staging="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/barline-dmg.XXXXXX")" || return 1
    if ! /usr/bin/ditto "$app" "$staging/$(basename "$app")" ||
        ! /bin/ln -s /Applications "$staging/Applications" ||
        ! /usr/bin/hdiutil create -quiet -volname "$volume_name" -srcfolder "$staging" \
            -fs HFS+ -format UDZO -imagekey zlib-level=9 "$dmg"; then
        /bin/rm -rf "$staging"
        printf 'error: could not build disk image: %s\n' "$dmg" >&2
        return 1
    fi
    /bin/rm -rf "$staging"
}

# Requires at least one appcast enclosure and every enclosure URL to be exactly
# the expected zip. Release-note prose is ignored, so notes that mention the
# disk image cannot fail a valid release.
barline_require_zip_enclosures() {
    local appcast="$1" expected="$2"
    local urls url count=0
    urls="$(grep -oE '<enclosure[^>]*[[:space:]]url="[^"]*"' "$appcast" | sed -E 's/.*[[:space:]]url="([^"]*)"$/\1/' || true)"
    while IFS= read -r url; do
        [[ -n "$url" ]] || continue
        count=$((count + 1))
        if [[ "$url" != "$expected" ]]; then
            printf 'error: appcast enclosure is not the notarized zip: %s\n' "$url" >&2
            return 1
        fi
    done <<<"$urls"
    ((count > 0)) || { printf 'error: appcast has no enclosure\n' >&2; return 1; }
}

# Mounts the image read-only and requires exactly the app bundle and an
# Applications shortcut resolving to /Applications. Hidden volume metadata such
# as .fseventsd is not part of the visible layout and is ignored.
barline_require_dmg_layout() {
    local dmg="$1" app_name="$2"
    local mountpoint entry name status=0
    mountpoint="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/barline-dmg-mount.XXXXXX")" || return 1
    if ! /usr/bin/hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$mountpoint" "$dmg"; then
        /bin/rmdir "$mountpoint" 2>/dev/null || true
        printf 'error: could not mount disk image: %s\n' "$dmg" >&2
        return 1
    fi
    if [[ ! -d "$mountpoint/$app_name/Contents" ]]; then
        printf 'error: disk image is missing %s\n' "$app_name" >&2
        status=1
    elif [[ ! -L "$mountpoint/Applications" || "$(/usr/bin/readlink "$mountpoint/Applications")" != /Applications ]]; then
        printf 'error: disk image Applications shortcut must be a symlink to /Applications\n' >&2
        status=1
    else
        for entry in "$mountpoint"/*; do
            name="$(basename "$entry")"
            if [[ "$name" != "$app_name" && "$name" != Applications ]]; then
                printf 'error: unexpected disk image entry: %s\n' "$name" >&2
                status=1
            fi
        done
    fi
    /usr/bin/hdiutil detach -quiet "$mountpoint" || /usr/bin/hdiutil detach -quiet -force "$mountpoint" || true
    /bin/rmdir "$mountpoint" 2>/dev/null || true
    return "$status"
}
