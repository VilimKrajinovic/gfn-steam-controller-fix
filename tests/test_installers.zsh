#!/bin/zsh
set -euo pipefail

INSTALL_SCRIPT="${1:?usage: test_installers.zsh <install-script> <uninstall-script> <repair-script>}"
UNINSTALL_SCRIPT="${2:?usage: test_installers.zsh <install-script> <uninstall-script> <repair-script>}"
REPAIR_SCRIPT="${3:?usage: test_installers.zsh <install-script> <uninstall-script> <repair-script>}"

install_help="$("$INSTALL_SCRIPT" --help)"
[[ "$install_help" == *'Usage:'* ]]
[[ "$install_help" == *'/Applications/GeForceNOW-Steam-Controller.app'* ]]
[[ "$install_help" == *'newer self-updated unpatched copy'* ]]
[[ "$install_help" == *'Input Monitoring'* ]]

uninstall_help="$("$UNINSTALL_SCRIPT" --help)"
[[ "$uninstall_help" == *'Usage:'* ]]
[[ "$uninstall_help" == *'/Applications/GeForceNOW-Steam-Controller.app'* ]]
[[ "$uninstall_help" == *'Removes only the patched app'* ]]

repair_help="$("$REPAIR_SCRIPT" --help)"
[[ "$repair_help" == *'Usage:'* ]]
[[ "$repair_help" == *'controller input works but vibration does not'* ]]
[[ "$repair_help" == *'Input Monitoring'* ]]
[[ "$repair_help" == *'System Settings pane'* ]]

for script in "$INSTALL_SCRIPT" "$UNINSTALL_SCRIPT" "$REPAIR_SCRIPT"; do
    if "$script" unexpected-argument >/dev/null 2>&1; then
        print -u2 "${script:t} accepted an unexpected argument"
        exit 1
    else
        exit_status=$?
        [[ $exit_status -eq 2 ]] || exit "$exit_status"
    fi
done

print "installer argument tests passed"
