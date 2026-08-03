#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP="/Applications/GeForceNOW-Steam-Controller.app"
GFN_BUNDLE_ID="com.nvidia.gfnpc.mall"
INPUT_MONITORING_SETTINGS="x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print "Usage: ${0:t}"
    print
    print "Repairs the case where controller input works but vibration does not."
    print "The script verifies the patched app, resets only GFN's Input Monitoring"
    print "decision, then opens the app and the relevant System Settings pane."
    print
    print "Quit every GeForce NOW window before running this command."
    exit 0
fi

if (( $# > 0 )); then
    print -u2 "This command takes no arguments. Run ${0:t} --help for usage."
    exit 2
fi

if [[ ! -d "$APP" ]]; then
    print -u2 "Patched GeForce NOW app not found: $APP"
    exit 1
fi
for required_script in verify.zsh reset-gfn-container.zsh; do
    if [[ ! -x "$SCRIPT_DIR/$required_script" ]]; then
        print -u2 "Required executable script not found: $SCRIPT_DIR/$required_script"
        exit 1
    fi
done
for required_command in /bin/sleep /usr/bin/open /usr/bin/tccutil; do
    if [[ ! -x "$required_command" ]]; then
        print -u2 "Required command not found: $required_command"
        exit 1
    fi
done

verification_log="$(mktemp "${TMPDIR:-/tmp}/gfn-input-monitoring-verify.XXXXXX")"
cleanup() {
    [[ -n "${verification_log:-}" && -f "$verification_log" ]] &&
        rm -f "$verification_log"
}
trap cleanup EXIT

if ! "$SCRIPT_DIR/verify.zsh" "$APP" >"$verification_log" 2>&1; then
    print -u2 "The installed app is not a verified patched build."
    cat "$verification_log" >&2
    print -u2 "Run $SCRIPT_DIR/install.zsh before repairing Input Monitoring."
    exit 1
fi

"$SCRIPT_DIR/reset-gfn-container.zsh"
/usr/bin/tccutil reset ListenEvent "$GFN_BUNDLE_ID"

print
print "Input Monitoring was reset for GeForce NOW."
print "Opening $APP..."
/usr/bin/open "$APP"
/bin/sleep 1
print "Opening System Settings > Privacy & Security > Input Monitoring..."
/usr/bin/open "$INPUT_MONITORING_SETTINGS"
print
print "Enable GeForce NOW in Input Monitoring, then quit and reopen it once."
print "macOS may not show a separate permission prompt; use the opened settings pane."
print "No microphone, camera, Accessibility, or other privacy decision was reset."
