#!/bin/zsh

# replace_verified_app uses caller-provided run_admin and run_with_log helpers.
# remove_installed_app uses only caller-provided run_admin.

version_is_valid() {
    local version="$1"
    local -a parts
    parts=("${(@s:.:)version}")
    (( ${#parts[@]} > 0 )) || return 1

    local part
    for part in "${parts[@]}"; do
        [[ "$part" == <-> ]] || return 1
    done
}

version_is_older() {
    local candidate_version="$1"
    local installed_version="$2"
    local -a candidate_parts installed_parts
    candidate_parts=("${(@s:.:)candidate_version}")
    installed_parts=("${(@s:.:)installed_version}")

    version_is_valid "$candidate_version" || return 2
    version_is_valid "$installed_version" || return 2

    local count=${#candidate_parts[@]}
    (( ${#installed_parts[@]} > count )) && count=${#installed_parts[@]}
    local index candidate_part installed_part
    for (( index = 1; index <= count; ++index )); do
        candidate_part="${candidate_parts[index]:-0}"
        installed_part="${installed_parts[index]:-0}"
        if (( 10#$candidate_part < 10#$installed_part )); then
            return 0
        fi
        if (( 10#$candidate_part > 10#$installed_part )); then
            return 1
        fi
    done
    return 1
}

app_short_version() {
    local app="$1"
    local plist="$app/Contents/Info.plist"
    [[ -r "$plist" ]] || return 1
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$plist" 2>/dev/null
}

app_is_unpatched_source() {
    local app="$1"
    [[ -x "$app/Contents/MacOS/GeForceNOW" &&
       -f "$app/Contents/Frameworks/libGeronimo.dylib" &&
       ! -e "$app/Contents/Frameworks/libGeronimo.original.dylib" ]]
}

# Prints the safest available source app. Return values other than zero mean:
#   1: no usable source exists
#   2: a version could not be parsed
#   3: the installed copy is newer but still patched, so it cannot be a source
select_install_source() {
    local official_app="$1"
    local installed_app="$2"
    local official_version=""
    local installed_version=""

    if [[ -d "$official_app" ]]; then
        official_version="$(app_short_version "$official_app")" || return 2
        version_is_valid "$official_version" || return 2
    fi
    if [[ -d "$installed_app" ]]; then
        installed_version="$(app_short_version "$installed_app")" || return 2
        version_is_valid "$installed_version" || return 2
    fi

    if [[ -n "$official_version" && -n "$installed_version" ]]; then
        if version_is_older "$official_version" "$installed_version"; then
            if app_is_unpatched_source "$installed_app"; then
                print -r -- "$installed_app"
                return 0
            fi
            return 3
        else
            local comparison_status=$?
            (( comparison_status == 1 )) || return 2
        fi
    fi

    if [[ -n "$official_version" ]] && app_is_unpatched_source "$official_app"; then
        print -r -- "$official_app"
        return 0
    fi
    if [[ -n "$installed_version" ]] && app_is_unpatched_source "$installed_app"; then
        print -r -- "$installed_app"
        return 0
    fi
    return 1
}

extract_designated_requirement() {
    local codesign_output="$1"
    local requirement
    requirement="$(print -r -- "$codesign_output" | sed -n \
        -e 's/^# designated => //p' \
        -e 's/^designated => //p')" || return 1
    [[ -n "$requirement" ]] || return 1
    print -r -- "$requirement"
}

app_designated_requirement() {
    local app="$1"
    local codesign_output
    codesign_output="$(/usr/bin/codesign -d -r- "$app" 2>&1)" || return 1
    extract_designated_requirement "$codesign_output"
}

replace_verified_app() {
    local staged_app="$1"
    local target_app="$2"
    local verify_command="$3"
    local verification_log="$4"
    local backup_app=""

    if [[ ! -e "$staged_app" ]]; then
        print -u2 "Installation candidate not found: $staged_app"
        return 1
    fi

    if [[ -e "$target_app" ]]; then
        backup_app="${target_app}.install-backup-$$"
        if [[ -e "$backup_app" ]]; then
            print -u2 "Temporary backup path already exists: $backup_app"
            return 1
        fi
        run_admin mv "$target_app" "$backup_app" || return 1
    fi

    if ! run_admin mv "$staged_app" "$target_app"; then
        if [[ -n "$backup_app" && -e "$backup_app" ]]; then
            run_admin mv "$backup_app" "$target_app" || true
            print -u2 "The previous installed copy was restored."
        fi
        print -u2 "Installation failed."
        return 1
    fi

    if ! run_with_log "Installed verification" "$verification_log" \
        "$verify_command" "$target_app"; then
        if ! run_admin rm -rf -- "$target_app"; then
            print -u2 "Could not remove the failed installation."
            return 1
        fi
        if [[ -n "$backup_app" && -e "$backup_app" ]]; then
            if ! run_admin mv "$backup_app" "$target_app"; then
                print -u2 "Could not restore the previous installed copy."
                return 1
            fi
            print -u2 "The previous installed copy was restored."
        fi
        print -u2 "Installed verification failed."
        return 1
    fi

    if [[ -n "$backup_app" && -e "$backup_app" ]]; then
        run_admin rm -rf -- "$backup_app" || return 1
    fi
}

remove_installed_app() {
    local target_app="$1"

    if [[ ! -e "$target_app" ]]; then
        return 0
    fi
    if ! run_admin rm -rf -- "$target_app"; then
        print -u2 "Could not remove: $target_app"
        return 1
    fi
    if [[ -e "$target_app" ]]; then
        print -u2 "Uninstall failed: $target_app still exists."
        return 1
    fi
}
