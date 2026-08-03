#!/bin/zsh
set -euo pipefail

TRANSACTION_LIBRARY="${1:?usage: test_app_transaction.zsh <transaction-library>}"
source "$TRANSACTION_LIBRARY"

version_is_older 2.0.86.124 2.0.87.130
! version_is_older 2.0.87.130 2.0.87.130
! version_is_older 2.0.88.1 2.0.87.130
version_is_older 2.0.87 2.0.87.1
if version_is_older 2.0.invalid 2.0.87.130; then
    print -u2 "malformed version unexpectedly compared successfully"
    exit 1
else
    version_status=$?
    [[ $version_status -eq 2 ]] || exit "$version_status"
fi

[[ "$(extract_designated_requirement $'Executable=/tmp/GFN\n# designated => cdhash H"abc"')" == \
   'cdhash H"abc"' ]]
[[ "$(extract_designated_requirement $'Executable=/tmp/GFN\ndesignated => identifier "com.example"')" == \
   'identifier "com.example"' ]]
if extract_designated_requirement 'Executable=/tmp/GFN' >/dev/null; then
    print -u2 "missing designated requirement was accepted"
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gfn-app-transaction-test.XXXXXX")"
cleanup() {
    [[ -n "${work_dir:-}" && -d "$work_dir" ]] && rm -rf "$work_dir"
}
trap cleanup EXIT

make_fake_app() {
    local app="$1"
    local version="$2"
    local patched="$3"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
    touch "$app/Contents/MacOS/GeForceNOW"
    chmod +x "$app/Contents/MacOS/GeForceNOW"
    touch "$app/Contents/Frameworks/libGeronimo.dylib"
    /usr/libexec/PlistBuddy -c \
        "Add :CFBundleShortVersionString string $version" \
        "$app/Contents/Info.plist" >/dev/null
    if [[ "$patched" == true ]]; then
        touch "$app/Contents/Frameworks/libGeronimo.original.dylib"
    fi
}

official_app="$work_dir/official.app"
self_updated_app="$work_dir/self-updated.app"
make_fake_app "$official_app" 2.0.87.130 false
make_fake_app "$self_updated_app" 2.0.87.131 false
[[ "$(select_install_source "$official_app" "$self_updated_app")" == \
   "$self_updated_app" ]]

newer_official_app="$work_dir/newer-official.app"
make_fake_app "$newer_official_app" 2.0.88.1 false
[[ "$(select_install_source "$newer_official_app" "$self_updated_app")" == \
   "$newer_official_app" ]]

installed_patched_app="$work_dir/installed-patched.app"
make_fake_app "$installed_patched_app" 2.0.89.1 true
if select_install_source "$newer_official_app" "$installed_patched_app" \
    >/dev/null; then
    print -u2 "newer patched app was selected as an installation source"
    exit 1
else
    selection_status=$?
    [[ $selection_status -eq 3 ]] || exit "$selection_status"
fi

missing_official_app="$work_dir/missing-official.app"
[[ "$(select_install_source "$missing_official_app" "$self_updated_app")" == \
   "$self_updated_app" ]]
if select_install_source "$missing_official_app" "$installed_patched_app" \
    >/dev/null; then
    print -u2 "patched app was selected when no unpatched source existed"
    exit 1
else
    selection_status=$?
    [[ $selection_status -eq 1 ]] || exit "$selection_status"
fi

run_admin() {
    "$@"
}

run_with_log() {
    local action="$1"
    local log_file="$2"
    shift 2

    if "$@" >"$log_file" 2>&1; then
        return 0
    fi
    return 1
}

target_app="$work_dir/installed.app"
staged_app="$work_dir/staged.app"
mkdir -p "$target_app" "$staged_app"
touch "$target_app/old-copy" "$staged_app/new-copy"

replace_verified_app "$staged_app" "$target_app" \
    /usr/bin/true "$work_dir/success.log"
[[ -f "$target_app/new-copy" ]]
[[ ! -e "$target_app/old-copy" ]]
[[ ! -e "$staged_app" ]]
[[ -z "$(find "$work_dir" -maxdepth 1 -name '*.install-backup-*' -print)" ]]

failed_staged_app="$work_dir/failed-staged.app"
mkdir -p "$failed_staged_app"
touch "$failed_staged_app/bad-copy"
if replace_verified_app "$failed_staged_app" "$target_app" \
    /usr/bin/false "$work_dir/failure.log" >/dev/null 2>&1; then
    print -u2 "verification failure unexpectedly installed the staged app"
    exit 1
fi
[[ -f "$target_app/new-copy" ]]
[[ ! -e "$target_app/bad-copy" ]]
[[ -z "$(find "$work_dir" -maxdepth 1 -name '*.install-backup-*' -print)" ]]

remove_installed_app "$target_app"
[[ ! -e "$target_app" ]]
remove_installed_app "$target_app"

print "app transaction tests passed"
