# iMac 2019 Audio Fix — Technical Notes

**Hardware:** Apple iMac19,2 (21.5" 4K Retina, 2019)
**OS:** Manjaro Linux, kernel 6.18.x

## History

1. **First problem (silence):** on the stock/mainline kernel `snd-hda-intel`/`cs8409` driver, the CS8409's
   Apple-specific fixups didn't fire and internal speakers stayed silent. An earlier version of this repo
   worked around it by forcing `model=dolphin` (a Dell Inspiron fixup) plus a systemd service to manually
   set GPIO4. This got sound working, but was never correct — see below.

2. **Root cause of loud/distorted audio:** after installing the community out-of-tree driver
   ([davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro), which has broader Cirrus
   codec support), audio with `model=dolphin` still forced was **very loud and distorted at every
   volume/gain setting**. Diagnosed by recording the actual analog signal
   (`parecord -d alsa_output.pci-0000_00_1f.3.analog-stereo.monitor`) while playing a clean −6dBFS test
   tone: measured peak was only −51.8dBFS with zero clipped samples digitally, yet it was audibly loud and
   distorted at the speaker. A true digital-silence WAV played back completely silent. Conclusion: real
   signal being wildly over-amplified in the analog stage — not digital clipping, not amp self-noise —
   downstream of anything ALSA/PipeWire volume controls can reach.

   Cause: `model=dolphin` forces the `CS8409_DOLPHIN` fixup (`SND_PCI_QUIRK(0x1028, 0x0ACF, "Dolphin",
   CS8409_DOLPHIN)` etc. in `cs8409-tables.c`, vendor `0x1028` = Dell), which applies Dell's own I2C
   amp-init register sequences (`dolphin_c0_init_reg_seq` / `dolphin_c1_init_reg_seq`) — wrong for this
   iMac's TAS5770L amp.

3. **The "mbp143" red herring:** the obvious fix looked like forcing a real Apple/iMac fixup by name. The
   driver source (`patch_cirrus/patch_cirrus_apple.h`) has a `CS8409_MBP143` fixup and a codec-subsystem
   quirk table with a commented-out entry for this exact subsystem ID:
   ```c
   //SND_PCI_QUIRK(0x106b, 0x0f00, "Imac 18,2", CS8409_MBP143),
   ```
   **This entire block is dead code.** It's guarded by `#ifdef APPLE_FIXUPS`, and `APPLE_FIXUPS` is never
   `#define`d anywhere in this driver's Makefile or build (checked `KBUILD_EXTRA_CFLAGS` and grepped the
   whole tree) — the block is explicitly commented in the source as "from a previous 8409 fixup - remove
   when see what need to be replaced by". The real, compiled `cs8409_models[]` table (in
   `cs8409-tables.c`) only has Dell model names: `bullseye`, `warlock`, `warlock mlk`,
   `warlock mlk dual mic`, `cyborg`, `dolphin`, `odin`. There is no `mbp143` in the actual running driver.

   So forcing `model=mbp143` works **not** because it selects a matching Apple fixup — no such compiled
   fixup exists — but because it's a string the driver can't match against anything in `cs8409_models[]`,
   so it silently skips forced model selection and falls through to generic HDA auto-configuration instead
   of applying Dolphin's wrong Dell I2C sequence. Omitting `model=` entirely would very likely produce the
   same result but hasn't been tested here — `model=mbp143` is what's confirmed working on this machine,
   so it's what's documented and installed.

## Current Fix (confirmed working)

`/etc/modprobe.d/50-sound.conf`:
```
options snd-intel-dspcfg dsp_driver=1
options snd-hda-intel model=mbp143 patch=imac2019-gpio4.fw power_save=0
```

`imac2019-gpio4.fw` (HDA patch file, sets GPIO4/1/5 at codec init — independent of the model= fixup
mechanism entirely, just raw GPIO verbs):
```
[codec]
0x10138409 0x106b0f00 0

[init_verbs]
0x01 0x716 0x32
0x01 0x717 0x32
0x01 0x715 0x32
```

GPIO bitmask `0x32` = GPIO1 (`0x02`, CS42L42-style reset, harmless/unused on this amp path) + GPIO4
(`0x10`, **TAS5770L speaker amp enable** — the actually load-bearing bit) + GPIO5 (`0x20`).

## Verification (after reboot)

```bash
# Confirm patched driver loaded from the DKMS/updates path, not stock
modinfo snd-hda-codec-cs8409 | grep filename

# Confirm model param took
cat /sys/module/snd_hda_intel/parameters/model

# Real signal test — low volume first, then higher
speaker-test -c 2 -t sine -f 440 -l 1
```

**Confirmed:** real-world listening test at 15% and 70% volume, plus real media playback (VLC) with live
volume changes, both clean — no distortion, fully controllable via the real hardware sink directly (no
PipeWire DSP shelf/gain workaround needed).

## Not needed

- Any custom mainline kernel patch. The earlier draft patch in this repo's history proposed a new
  `CS8409_IMAC_2019` fixup that **reused Dolphin's init path** — since Dolphin's I2C init is exactly the
  proven cause of the distortion bug, that approach was wrong and has been dropped rather than fixed
  forward.
- The old `imac-speaker-amp.sh` + `.service` (manual `hda-verb` GPIO4 script/systemd unit) — superseded by
  the `imac2019-gpio4.fw` firmware patch, which does the same thing automatically at codec-init time. Kept
  in this repo only as a documented fallback for setups not using the `patch=` mechanism.
