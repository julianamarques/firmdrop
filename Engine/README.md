# FirmDrop flash engine

This directory is a separate **GPL-3.0-or-later** command-line adapter for
[Brokkr](https://github.com/Gabriel2392/brokkr-flash), pinned to
`f7ae23067b4ee6c2e0211a1dee563f4be991cb4d` (2.4.11). FirmDrop communicates with
it through process arguments and stdout/stderr, without linking to Brokkr.

The adapter uses the native macOS IOKit USB transport, requires one explicitly
selected device with a matching registry connection ID, verifies TAR/MD5 packages,
emits progress, and never uploads a PIT or requests a repartition. The strict-mapping patch
rejects incomplete partition mappings before any partition write and names the
images without a PIT entry. Package metadata under `meta-data/` (for example
`fota.zip` and `super_used_size.txt`) has no partition and is not flashed. `--probe` only opens a
protocol session, reads its version, and ends the session without rebooting or
writing partitions. It does not establish firmware/model compatibility.
After a session ends without a reboot, the bootloader no longer answers the
`ODIN`/`LOKE` handshake while it stays in Download Mode. Like Heimdall's
`--resume`, the resume-session patch lets `--probe --resume` and
`--flash --resume` skip only that handshake and continue with the same session
requests. The app passes `--resume` only after a successful probe on the same
USB connection.
The macOS SDK patch removes a legacy pre-macOS 12 port-constant fallback; this
build requires macOS 26 and uses `kIOMainPortDefault` directly.

`--flash` accepts four `--file` arguments in BL/AP/CP/CSC order and requires
`--target` and `--connection` from `--list`. `--preserve` refuses USERDATA images;
`--no-reboot` keeps Download Mode after success. `--verify` validates the same four
files offline. These are private integration arguments, not the upstream CLI.

USB discovery and the Odin protocol 3 handshake were validated on a Galaxy S25
SM-S931B running One UI 9 (`S931BXXUCDZIF`). The phone entered Download Mode through
`adb reboot download` with Maintenance Mode active. On 2026-10-10 the same device was
flashed end to end with One UI 9 (Android 17, `S931BXXUCDZIF`) using the full CSC,
after a probe and `--flash --resume`. The same day a Galaxy A05s SM-A057M was flashed
end to end with One UI 7 (Android 15, `A057MUBUGDZH1`) using the full CSC, after entering
Download Mode with the hardware buttons. These are two devices with one firmware each;
they do not establish compatibility with other models, versions or HOME_CSC installs.
Firmware filename checks in the app are not device identification or anti-rollback
verification. ADB is a separate executable bundled and invoked by the Swift app.

## Rebuild the bundled binary

Run `bash scripts/build-flash-engine.sh [--universal]` in the FirmDrop repository.
Only Xcode Command Line Tools, Git and the macOS SDK are needed; no Qt or Homebrew
libraries are required. Dependencies are pinned by full Git commit IDs.

Every packaged app includes `Contents/Resources/flash-engine-source.tar.gz`,
containing the complete engine and dependency sources, their licenses, the adapter,
its patch and this build script. After extracting that archive, run:

```sh
bash adapter/build.sh "$PWD" "$PWD/output" --universal
```

The resulting executable is `output/firmdrop-flash`. The sources build offline.
The original Brokkr GPL license is in `brokkr/LICENSE`. The adapter files and patch
are distributed under GPL-3.0-or-later; the Swift app retains its Apache 2.0 license.
