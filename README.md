# iMac 2019 (iMac19,2) Audio Fix for Linux

Fixes audio on **Apple iMac 21.5" 4K Retina 2019 (iMac19,2)** running Linux (tested on Manjaro, kernel 6.18).

There have been two, unrelated bugs in this machine's Linux audio history. This repo documents both,
including a corrected understanding of the second one after an earlier fix turned out to be wrong.

## Quick Install

```bash
git clone git@github.com:a000a999a/imac2019audiofix.git
cd imac2019audiofix
sudo ./install.sh
reboot
```

**Prerequisite:** you need the patched `snd-hda-codec-cs8409` driver from
[davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) installed first
(`sudo ./install.cirrus.driver.sh` from that repo, then reboot once before running `install.sh` here).
The stock/mainline kernel driver's Cirrus CS8409 support is not sufficient for this hardware.

## Bug 1 — Speaker amp stays in shutdown (GPIO4)

The iMac's **Cirrus Logic CS8409** HDA bridge drives a **TAS5770L** speaker amplifier. The amp's enable
pin is wired to the codec's **GPIO4**, which is left as an input (LOW) by default — the amp never comes
out of hardware shutdown, so internal speakers are silent (headphones are unaffected; they don't go
through this amp).

**Fix:** an HDA firmware "patch" file (`imac2019-gpio4.fw`) that sets GPIO4 (and GPIO1/GPIO5) HIGH via
init verbs at codec-init time, loaded through the `patch=` modprobe option — no separate script or
service required.

## Bug 2 — Forcing `model=dolphin` badly over-amplifies and distorts audio

An earlier version of this fix (see git history) forced `model=dolphin` to get the CS8409 driver
initializing anything at all under the stock kernel driver. **This was wrong and is not recommended.**

`dolphin` selects the `CS8409_DOLPHIN` fixup, which is for the **Dell Inspiron "Dolphin"** platform — a
different vendor, different amp, different I2C init register sequences. Forcing it onto this iMac's
TAS5770L applies Dell's amp-gain I2C init values, not Apple's. Confirmed by direct signal analysis: with
`model=dolphin` forced, true digital silence played completely silent, but a clean low-level tone came
out loud and distorted at the speaker — i.e. real over-amplification happening in the analog stage,
downstream of anything ALSA/PipeWire volume controls can reach.

**Fix:** don't force `dolphin`. In practice, forcing `model=mbp143` also works and is what's currently
deployed — but note this is **not** because `mbp143`/`CS8409_MBP143` is an active Apple/iMac fixup in
this driver build. It's dead code: the entire `CS8409_MBP143` quirk table in
`patch_cirrus/patch_cirrus_apple.h` is guarded by `#ifdef APPLE_FIXUPS`, and `APPLE_FIXUPS` is never
defined anywhere in this driver's Makefile/build — it's explicitly marked in the source as legacy code
kept "for reference." The real compiled model table (`cs8409-tables.c`) only recognizes Dell model names
(`bullseye`, `warlock`, `cyborg`, `dolphin`, `odin`, etc.) — no iMac/MacBookPro entry exists at all.

So `model=mbp143` works simply because it's an **unrecognized string**: the driver can't match it to any
compiled fixup, silently skips forced model selection, and falls through to generic HDA auto-configuration
instead of forcibly applying Dolphin's wrong Dell I2C amp-init sequence. Omitting `model=` entirely would
very likely produce the same result, but that hasn't been tested on this machine — `model=mbp143` is
what's confirmed working, so that's what's documented and installed here.

## Current Confirmed Configuration

`/etc/modprobe.d/50-sound.conf`:
```
options snd-intel-dspcfg dsp_driver=1
options snd-hda-intel model=mbp143 patch=imac2019-gpio4.fw power_save=0
```

Verified end-to-end: real hardware sink (`alsa_output.pci-0000_00_1f.3.analog-stereo`) plays cleanly at
both low and high volume via `speaker-test`, and via real playback (VLC) with live volume changes — no
distortion, fully controllable. No PipeWire DSP volume workaround is needed.

## Files

| File | Purpose |
|------|---------|
| `imac2019-gpio4.fw` | HDA patch firmware: sets GPIO4 (speaker amp enable) + GPIO1/GPIO5 at codec init |
| `install.sh` | Installs the modprobe config and firmware patch file |
| `imac-speaker-amp.sh` / `.service` | **Legacy fallback** — a systemd oneshot that sets the same GPIO bits via `hda-verb` after boot, for use without the firmware `patch=` mechanism (e.g. plain mainline kernel). Not installed by `install.sh`; kept for reference. |

## Manual Install

```bash
sudo cp imac2019-gpio4.fw /lib/firmware/imac2019-gpio4.fw
sudo tee /etc/modprobe.d/50-sound.conf <<'EOF'
options snd-intel-dspcfg dsp_driver=1
options snd-hda-intel model=mbp143 patch=imac2019-gpio4.fw power_save=0
EOF
sudo reboot
```

### Verify

```bash
# Confirm the patched driver loaded (not the stock kernel one)
modinfo snd-hda-codec-cs8409 | grep filename

# Confirm the model parameter took
cat /sys/module/snd_hda_intel/parameters/model

# Audio test — try at low volume first
speaker-test -c 2 -t sine -f 440 -l 1
```

## Hardware Details

| Component | Detail |
|-----------|--------|
| Machine | Apple iMac19,2 (21.5" 4K Retina, 2019) |
| HDA controller | Intel Cannon Lake PCH cAVS (`0x8086:a348`) |
| HDA controller subsystem | `0x8086:0x7270` (Intel generic — doesn't match any Dell PCI-subsystem quirk) |
| Codec | Cirrus Logic CS8409 (vendor ID `0x10138409`) |
| Codec subsystem | `0x106b:0x0f00` |
| Speaker amp | TAS5770L, I2C-controlled, enabled via GPIO4 |
| GPIO bitmask | `0x32` = GPIO1 (`0x02`) + GPIO4 (`0x10`) + GPIO5 (`0x20`) |
