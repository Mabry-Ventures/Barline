#!/usr/bin/env bash

# Source only. Barline ships for Apple Silicon only. Prebuilt dependencies such
# as Sparkle arrive as universal binaries, so release packaging removes every
# non-Apple Silicon slice and then requires each Mach-O file in the app bundle
# to contain only arm64 or arm64e code.

barline_is_apple_silicon_arch() {
    [[ "$1" == arm64 || "$1" == arm64e ]]
}

# Prints each regular Mach-O file under a bundle. Symlinked framework paths are
# skipped so every binary is processed exactly once.
barline_bundle_macho_files() {
    local file
    while IFS= read -r -d '' file; do
        if /usr/bin/lipo -archs "$file" >/dev/null 2>&1; then
            printf '%s\n' "$file"
        fi
    done < <(/usr/bin/find "$1" -type f -print0)
}

barline_thin_bundle_to_apple_silicon() {
    local bundle="$1" file arch mode tmp
    local kept=() removed=()
    [[ -d "$bundle" ]] || { printf 'error: bundle not found for Apple Silicon thinning\n' >&2; return 1; }
    while IFS= read -r file; do
        kept=()
        removed=()
        for arch in $(/usr/bin/lipo -archs "$file"); do
            if barline_is_apple_silicon_arch "$arch"; then
                kept+=("$arch")
            else
                removed+=("$arch")
            fi
        done
        ((${#removed[@]})) || continue
        ((${#kept[@]})) || {
            printf 'error: %s has no Apple Silicon slice\n' "${file#"$bundle"/}" >&2
            return 1
        }
        tmp="$file.apple-silicon.$$"
        if ((${#kept[@]} == 1)); then
            /usr/bin/lipo "$file" -thin "${kept[0]}" -output "$tmp" || { /bin/rm -f "$tmp"; return 1; }
        else
            /usr/bin/lipo "$file" -extract_family arm64 -output "$tmp" 2>/dev/null ||
                /usr/bin/lipo "$file" -remove "${removed[0]}" -output "$tmp" || { /bin/rm -f "$tmp"; return 1; }
        fi
        mode="$(/usr/bin/stat -f %Lp "$file")"
        /bin/chmod u+w "$file"
        /bin/cat "$tmp" >"$file"
        /bin/chmod "$mode" "$file"
        /bin/rm -f "$tmp"
        printf 'Removed %s from %s\n' "${removed[*]}" "${file#"$bundle"/}"
    done < <(barline_bundle_macho_files "$bundle")
}

barline_require_apple_silicon_bundle() {
    local bundle="$1" file arch count=0 bad=0
    while IFS= read -r file; do
        count=$((count + 1))
        for arch in $(/usr/bin/lipo -archs "$file"); do
            if ! barline_is_apple_silicon_arch "$arch"; then
                printf 'error: %s contains %s\n' "${file#"$bundle"/}" "$arch" >&2
                bad=$((bad + 1))
            fi
        done
    done < <(barline_bundle_macho_files "$bundle")
    ((count)) || { printf 'error: no Mach-O files found for Apple Silicon validation\n' >&2; return 1; }
    ((bad == 0)) || return 1
    printf 'Apple Silicon only: %d Mach-O files verified\n' "$count"
}
