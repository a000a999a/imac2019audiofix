# iMac 2019 (iMac19,2) Audio Fix for Linux

Fixes silent speakers on **Apple iMac 21.5" 4K Retina 2019 (iMac19,2)** running Linux (tested on Manjaro, kernel 6.12).

## Quick Install

```bash
git clone https://github.com/a000a999a/imac2019audio.git
cd imac2019audio
bash install.sh
reboot
```

## The Problem

Two separate bugs prevent audio from working out of the box:

### Bug 1 — CS42L42 sub-codecs never initialized

The iMac uses a **Cirrus Logic CS8409** HDA bridge chip which talks to two **CS42L42** amplifier chips over I2C. The Linux kernel's CS8409 driver has a "Dolphin" fixup that initializes these chips, but it only fires when the PCI subsystem ID is `0x106b:xxxx` (Apple vendor). On this iMac, the Intel HDA controller reports subsystem `0x8086:0x7270` (Intel generic), so the quirk never matches and the CS42L42 chips stay uninitialized → complete silence.

**Fix:** Force the Dolphin fixup by name via modprobe option.

### Bug 2 — Speaker amplifier stays in shutdown

Even after Bug 1 is fixed, internal speakers remain silent. The Dolphin fixup drives GPIO1 (CS42L42 C1 reset) and GPIO5 (CS42L42 C0 reset) HIGH, but leaves **GPIO4** as an input (LOW). GPIO4 is the enable pin for the speaker amplifier. With it LOW, the amp stays in hardware shutdown.

Headphones are unaffected (they go through the CS42L42 directly).

**Fix:** A systemd oneshot service drives GPIO4 HIGH after the sound card loads.

## Files

| File | Purpose |
|------|---------|
| `imac-speaker-amp.sh` | Sets GPIO4 HIGH on the HDA Audio Function Group (NID 0x01) |
| `imac-speaker-amp.service` | systemd unit that runs the script at boot |
| `install.sh` | Automated installer for both fixes |

## Manual Install

### Fix 1 — modprobe config

Add to `/etc/modprobe.d/50-sound.conf`:

```
options snd-intel-dspcfg dsp_driver=1
options snd-hda-intel model=dolphin
```

Reboot (or `sudo modprobe -r snd-hda-intel && sudo modprobe snd-hda-intel`).

### Fix 2 — GPIO4 speaker amp

```bash
sudo cp imac-speaker-amp.sh /usr/local/bin/imac-speaker-amp.sh
sudo chmod +x /usr/local/bin/imac-speaker-amp.sh
sudo cp imac-speaker-amp.service /etc/systemd/system/imac-speaker-amp.service
sudo systemctl daemon-reload
sudo systemctl enable --now imac-speaker-amp.service
```

### Verify

```bash
# CS42L42 init messages (requires Fix 1 + reboot)
sudo dmesg | grep -iE "dolphin|cs42l42|sub_codec"

# GPIO4 service status
systemctl status imac-speaker-amp.service

# Audio test
speaker-test -D default -c 2 -t sine -f 440 -l 1
```

## Hardware Details

| Component | Detail |
|-----------|--------|
| Machine | Apple iMac19,2 (21.5" 4K Retina, 2019) |
| HDA controller | Intel Cannon Lake PCH cAVS (`0x8086:a348`) |
| HDA subsystem | `0x8086:0x7270` (Intel generic — the root of Bug 1) |
| Codec | Cirrus Logic CS8409 (HDA bridge) |
| Codec subsystem | `0x106b:0x0f00` |
| Sub-codecs | CS42L42 × 2 at I2C 0x49 (speakers) |
| Speaker amp enable | CS8409 GPIO4 (bit 4, must be driven HIGH) |
| Dolphin GPIO1 | CS42L42 C1 reset (HIGH) |
| Dolphin GPIO5 | CS42L42 C0 reset (HIGH) |

## GPIO Bitmask Reference

```
0x02 = GPIO1  (CS42L42 C1 reset — set by Dolphin)
0x10 = GPIO4  (speaker amp enable — THIS fix)
0x20 = GPIO5  (CS42L42 C0 reset — set by Dolphin)
0x32 = GPIO1 + GPIO4 + GPIO5  (full correct state)
```
