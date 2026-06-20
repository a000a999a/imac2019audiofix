#!/bin/bash
# Install iMac 2019 speaker amp fix on Manjaro/Arch Linux.
# Run as root or with sudo.

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Installing iMac 2019 audio fix ==="

# 1. modprobe config
MODPROBE_CONF=/etc/modprobe.d/50-sound.conf
if ! grep -q "model=dolphin" "$MODPROBE_CONF" 2>/dev/null; then
    echo "options snd-intel-dspcfg dsp_driver=1" >> "$MODPROBE_CONF"
    echo "options snd-hda-intel model=dolphin"   >> "$MODPROBE_CONF"
    echo "[OK] Written modprobe config to $MODPROBE_CONF"
else
    echo "[OK] modprobe config already present in $MODPROBE_CONF"
fi

# 2. Speaker amp enable script
install -m 755 "$SCRIPT_DIR/imac-speaker-amp.sh" /usr/local/bin/imac-speaker-amp.sh
echo "[OK] Installed /usr/local/bin/imac-speaker-amp.sh"

# 3. systemd service
install -m 644 "$SCRIPT_DIR/imac-speaker-amp.service" /etc/systemd/system/imac-speaker-amp.service
systemctl daemon-reload
systemctl enable --now imac-speaker-amp.service
echo "[OK] imac-speaker-amp.service enabled and started"

echo ""
echo "=== Done ==="
echo "Verify: systemctl status imac-speaker-amp.service"
echo "Test:   speaker-test -D default -c 2 -t sine -f 440 -l 1"
echo ""
echo "NOTE: The modprobe change takes effect after a full reboot."
echo "If this is a fresh install, reboot now to complete the fix."
