#!/bin/bash
# Install iMac 2019 (iMac19,2) audio fix on Manjaro/Arch Linux.
# Requires the patched cs8409 driver from davidjo/snd_hda_macbookpro to
# already be installed (see README.md). Run as root or with sudo.

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Installing iMac 2019 audio fix ==="

# 1. GPIO4 firmware patch (sets GPIO1/GPIO4/GPIO5 at codec init)
install -m 644 "$SCRIPT_DIR/imac2019-gpio4.fw" /lib/firmware/imac2019-gpio4.fw
echo "[OK] Installed /lib/firmware/imac2019-gpio4.fw"

# 2. modprobe config — do NOT use model=dolphin (wrong Dell fixup, causes
# severe amp over-amplification/distortion on this hardware; see README.md).
MODPROBE_CONF=/etc/modprobe.d/50-sound.conf
if ! grep -q "model=mbp143" "$MODPROBE_CONF" 2>/dev/null; then
    cat >> "$MODPROBE_CONF" <<'EOF'
options snd-intel-dspcfg dsp_driver=1
options snd-hda-intel model=mbp143 patch=imac2019-gpio4.fw power_save=0
EOF
    echo "[OK] Written modprobe config to $MODPROBE_CONF"
else
    echo "[OK] modprobe config already present in $MODPROBE_CONF"
fi

echo ""
echo "=== Done ==="
echo "Verify after reboot:"
echo "  modinfo snd-hda-codec-cs8409 | grep filename   # patched driver loaded?"
echo "  cat /sys/module/snd_hda_intel/parameters/model # model param took?"
echo "  speaker-test -c 2 -t sine -f 440 -l 1          # audio test, low volume first"
echo ""
echo "NOTE: takes effect after a full reboot."
