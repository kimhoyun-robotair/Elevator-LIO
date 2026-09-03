#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RULE_SOURCE="${SCRIPT_DIR}/99-orbbec-gemini-336l.rules"
RULE_TARGET="/etc/udev/rules.d/99-orbbec-gemini-336l.rules"

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Gemini 336L USB passthrough is supported by this helper on Linux hosts only." >&2
    exit 2
fi

if [[ ! -f "${RULE_SOURCE}" ]]; then
    echo "Missing udev rule: ${RULE_SOURCE}" >&2
    exit 2
fi

run_as_root=()
if [[ "${EUID}" -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        echo "sudo is required to install the host udev rule." >&2
        exit 2
    fi
    run_as_root=(sudo)
fi

"${run_as_root[@]}" install -m 0644 "${RULE_SOURCE}" "${RULE_TARGET}"
"${run_as_root[@]}" udevadm control --reload-rules
"${run_as_root[@]}" udevadm trigger --subsystem-match=usb

echo "Installed ${RULE_TARGET}"
echo "Unplug and reconnect the Gemini 336L once before launching the container."
