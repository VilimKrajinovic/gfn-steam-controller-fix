#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OFFICIAL_APP="/Applications/GeForceNOW.app"
TARGET_APP="/Applications/GeForceNOW-Steam-Controller.app"
TARGET_PARENT="${TARGET_APP:h}"
GFN_BUNDLE_ID="com.nvidia.gfnpc.mall"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print "Usage: ${0:t}"
    print
    print "Builds, verifies, and installs the patched GeForce NOW app at:"
    print "  $TARGET_APP"
    print
    print "Uses the official app, or a newer self-updated unpatched copy, as"
    print "a read-only source. Shared user data is not modified."
    print "A changed signature resets only GFN's stale Input Monitoring decision."
    print "Administrator access may be requested to write to /Applications."
    exit 0
fi

if (( $# > 0 )); then
    print -u2 "This command takes no arguments. Run ${0:t} --help for usage."
    exit 2
fi

for required_script in build.zsh verify.zsh reset-gfn-container.zsh; do
    if [[ ! -x "$SCRIPT_DIR/$required_script" ]]; then
        print -u2 "Required executable script not found: $SCRIPT_DIR/$required_script"
        exit 1
    fi
done
if [[ ! -r "$SCRIPT_DIR/lib/app-transaction.zsh" ]]; then
    print -u2 "Required library not found: $SCRIPT_DIR/lib/app-transaction.zsh"
    exit 1
fi
source "$SCRIPT_DIR/lib/app-transaction.zsh"

for required_command in cat mktemp mv rm sed; do
    if ! command -v "$required_command" >/dev/null; then
        print -u2 "Required command not found: $required_command"
        exit 1
    fi
done
for required_command in /usr/bin/codesign /usr/bin/tccutil; do
    if [[ ! -x "$required_command" ]]; then
        print -u2 "Required command not found: $required_command"
        exit 1
    fi
done

if SOURCE_APP="$(select_install_source "$OFFICIAL_APP" "$TARGET_APP")"; then
    :
else
    source_status=$?
    case "$source_status" in
        1)
            print -u2 "No usable unpatched GeForce NOW source was found."
            print -u2 "Install or update $OFFICIAL_APP, then try again."
            ;;
        2)
            print -u2 "Could not read a valid GeForce NOW version from the available apps."
            ;;
        3)
            target_version="$(app_short_version "$TARGET_APP" 2>/dev/null || print unknown)"
            print -u2 "The installed patched copy ($target_version) is newer than the official app."
            print -u2 "Update $OFFICIAL_APP before rebuilding it."
            ;;
        *)
            print -u2 "Could not select a GeForce NOW source (status $source_status)."
            ;;
    esac
    exit 1
fi

source_version="$(app_short_version "$SOURCE_APP")"
if [[ "${SOURCE_APP:A}" == "${TARGET_APP:A}" ]]; then
    print "Using self-updated GeForce NOW $source_version as the read-only source."
else
    print "Using official GeForce NOW $source_version as the read-only source."
fi

previous_requirement=""
if [[ -d "$TARGET_APP" ]]; then
    if ! previous_requirement="$(app_designated_requirement "$TARGET_APP")"; then
        print -u2 "Could not read the installed app's code requirement."
        exit 1
    fi
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gfn-steam-controller-install.XXXXXX")"
cleanup() {
    [[ -n "${work_dir:-}" && -d "$work_dir" ]] && rm -rf "$work_dir"
}
trap cleanup EXIT

run_with_log() {
    local action="$1"
    local log_file="$2"
    shift 2

    if "$@" >"$log_file" 2>&1; then
        return 0
    fi

    print -u2 "$action failed. Diagnostic output follows:"
    cat "$log_file" >&2
    return 1
}

staged_app="$work_dir/GeForceNOW-Steam-Controller.app"
print "Building the patched GeForce NOW app..."
run_with_log "Build" "$work_dir/build.log" \
    "$SCRIPT_DIR/build.zsh" "$SOURCE_APP" "$staged_app"
print "Verifying the installation candidate..."
run_with_log "Candidate verification" "$work_dir/candidate-verification.log" \
    "$SCRIPT_DIR/verify.zsh" "$staged_app"
if ! candidate_requirement="$(app_designated_requirement "$staged_app")"; then
    print -u2 "Could not read the candidate app's code requirement."
    exit 1
fi
input_monitoring_reset_needed=false
if [[ "$candidate_requirement" != "$previous_requirement" ]]; then
    input_monitoring_reset_needed=true
fi

# Recheck immediately before replacing an installed copy. This refuses to
# proceed while a GFN window or streamer is active and clears only the
# same-user resident container that can retain the previous app's libraries.
"$SCRIPT_DIR/reset-gfn-container.zsh"

use_sudo=false
if [[ ! -w "$TARGET_PARENT" ]]; then
    if ! command -v sudo >/dev/null; then
        print -u2 "Administrator access is required, but sudo was not found."
        exit 1
    fi
    print "Administrator access is required to install into /Applications."
    sudo -v
    use_sudo=true
fi

run_admin() {
    if [[ "$use_sudo" == true ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

print "Verifying the installed app..."
replace_verified_app "$staged_app" "$TARGET_APP" \
    "$SCRIPT_DIR/verify.zsh" "$work_dir/installed-verification.log"

input_monitoring_reset=false
if [[ "$input_monitoring_reset_needed" == true ]]; then
    print "The app signature changed; resetting GFN's stale Input Monitoring decision..."
    if /usr/bin/tccutil reset ListenEvent "$GFN_BUNDLE_ID"; then
        input_monitoring_reset=true
    else
        print -u2 "Could not reset Input Monitoring automatically."
        print -u2 "Run $SCRIPT_DIR/repair-input-monitoring.zsh before testing vibration."
    fi
fi

print
print "Installed and verified:"
print "  $TARGET_APP"
print "Open it from Finder's Applications folder or run:"
print "  open ${(q)TARGET_APP}"
if [[ "$input_monitoring_reset" == true ]]; then
    print
    print "Input Monitoring was reset because the app signature changed."
    print "Open GeForce NOW once, then enable it in System Settings > Privacy & Security"
    print "> Input Monitoring. macOS may not show a separate permission prompt."
    print "Quit and reopen GeForce NOW once before testing vibration."
fi
