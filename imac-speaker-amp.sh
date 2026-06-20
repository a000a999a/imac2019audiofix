#!/bin/bash
# Enable iMac 2019 (iMac19,2) speaker amplifier.
# The CS8409 HDA bridge's Dolphin fixup leaves GPIO4 as an input (LOW).
# GPIO4 must be driven HIGH to enable the TAS5770L speaker amp.
# GPIO1 and GPIO5 are already set by Dolphin (CS42L42 resets); we include
# them here so this script is self-contained and safe to re-run.

HDA=/dev/snd/hwC0D0
AFG=0x01

# Wait for the hwdep device to appear (can take a moment after module load)
for i in $(seq 1 20); do
    [ -e "$HDA" ] && break
    sleep 0.5
done

if [ ! -e "$HDA" ]; then
    echo "imac-speaker-amp: $HDA not found after 10s" >&2
    exit 1
fi

# GPIO bitmask:
#   bit1 = GPIO1 (0x02) — CS42L42 C1 reset, HIGH
#   bit4 = GPIO4 (0x10) — speaker amp enable, HIGH
#   bit5 = GPIO5 (0x20) — CS42L42 C0 reset, HIGH
MASK=0x32   # GPIO1 + GPIO4 + GPIO5

hda-verb "$HDA" $AFG 0x717 $MASK   # SET_GPIO_MASK
hda-verb "$HDA" $AFG 0x71F $MASK   # SET_GPIO_DIRECTION (all outputs)
hda-verb "$HDA" $AFG 0x715 $MASK   # SET_GPIO_DATA (all HIGH)

echo "imac-speaker-amp: GPIO4 (speaker amp) enabled"
