# Security Policy

## Supported Versions

Only the latest version published on
[Releases](https://github.com/julianamarques/firmdrop/releases) receives
security fixes.

| Version                | Supported |
| ---------------------- | --------- |
| Latest (1.0.x)         | Yes       |
| Earlier                | No        |

## Reporting a Vulnerability

Do not open a public issue to report vulnerabilities.

Use GitHub's private reporting: on the repository's **Security** tab, click
**Report a vulnerability**. The report is visible only to the maintainer until
a fix is published.

Whenever possible, include:

- A description of the problem and its impact.
- Steps to reproduce or a proof of concept.
- The FirmDrop and macOS versions.
- The model, region (CSC) and firmware version involved, if applicable.
- A suggested fix, if you have one.

## What to Expect

- Acknowledgment of the report within 7 days.
- An initial assessment and feedback on severity within 14 days.
- A fix published in a new version, crediting the reporter if they wish.

Because the project is maintained by one person, these timelines may vary; the
report will be followed through to the end.

## Scope

In scope:

- The app's code: communication with Samsung's servers, request signing,
  verification of the embedded `auth_param.dat`, resumable downloads, CRC32
  verification, decryption and writing files to disk.
- The update check and the links it opens.
- The USB installation integration, package selection and validation, ZIP
  import and the installation engine adapter.
- The use of the embedded `adb` to reboot the device into Download Mode.
- The build, packaging and release scripts.

Out of scope (report directly to the upstream projects):

- Vulnerabilities in Samsung's servers or firmware:
  [Samsung Mobile Security](https://security.samsungmobile.com).
- Vulnerabilities in `auth_param.dat` or Bifrost:
  [zacharee/SamloaderKotlin](https://github.com/zacharee/SamloaderKotlin).
- Problems in other flashing tools, such as Odin and Heimdall. For flaws in
  Brokkr, also notify the upstream project; problems in FirmDrop's integration
  remain in scope for this repository.
- Attacks that require physical access to an unlocked Mac.
- The Gatekeeper warning on first launch, caused by the app's local signing
  (known behavior, documented in the README).

## Security Considerations for Users

- The app has no accounts, collects no data and sends no telemetry. On the network,
  it only talks, always over HTTPS, to:
  - `fota-cloud-dn.ospserver.net`, `neofussvr.sslcs.cdngc.net` and
    `cloud-neofussvr.samsungmobile.com`, Samsung's servers, to look up
    versions and download firmware;
  - `api.github.com`, to check whether a new version of the app is out.
- `auth_param.dat` is embedded in the app, downloaded from a pinned Bifrost commit at
  build time. It is only used if its SHA-256 matches the value defined in the code;
  otherwise, the search fails.
- Firmware is downloaded straight from Samsung's servers, over HTTPS, and checked
  against the CRC32 they report before it is decrypted. The `.tar.md5` files inside the
  `.zip` end with an MD5, which the installation engine checks before writing. That MD5
  detects corrupted files, but does not prove their origin: whoever alters the package
  can recompute the MD5. The firmware's authenticity is verified by the device itself:
  with a locked bootloader, it rejects images without Samsung's signature.
- The app does not verify the origin of a ZIP or package imported from outside FirmDrop.
  Only use firmware downloaded by FirmDrop or from sources you trust.
- The embedded `adb` only talks to the device connected over USB. It starts with mDNS
  discovery turned off, so it does not look for devices on the local network. If
  FirmDrop started the ADB server, it stops it after the reboot; a server that was
  already running, from another app or the user, is left running.
- USB installation is experimental. The model read over ADB and the file names do not
  prove compatibility with the hardware or the bootloader revision. The app requires
  an explicit review before starting, uses a single USB connection and does not send
  a PIT.
- The app does not install updates on its own: it only opens the new version's `.dmg`
  link in the browser. Check that the address is
  `github.com/julianamarques/firmdrop` before downloading.
- Only download the app from this repository's Releases page.
