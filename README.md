# Polaris2048Fix.app — SwiftUI v0.3 (preview-only)

**Experimental source code, not a Metal fix and not a ready-made signed `.app`.**

### v0.3 change

The v0.2 GPU list was **not** hardware detection: it only checked `DeviceProperties/Add` entries containing `model`/`device_type`. v0.3 adds read-only IORegistry AMD hardware detection, allows manually specifying a PCI path when no `DeviceProperties` entry exists, and supports preview creation for a new Add entry. It does **not** derive the exact OpenCore ACPI PCI path automatically. The ioreg values can be spoofed by boot properties and must not be confused with physical PCI configuration register readings.

This is a native SwiftUI app for macOS 13+ (including Tahoe x86_64), authored as an Xcode project. It generates a **local, non-installed OpenCore config candidate** from a known working modified RX 580 2048SP VBIOS image while leaving the physical stock VBIOS untouched.

## What the GUI does

1. Open the app: it now scans AMD PCI devices through the read-only `ioreg` output and displays vendor/device IDs. This hardware list **does not imply OpenCore PCI path discovery**.
2. Select an existing OpenCore `config.plist`. It lists known GPU-like entries. If your new EFI has no Radeon entry, manually enter the **verified real** PCI path into the text box, then continue.
3. Confirm that the chosen path corresponds to your GPU. Do **not** copy example paths blindly.
4. Select your own known-working `RX580 Mod.rom` (262,144 bytes). The program requires its exact SHA-256 `483b9fb9eaccd3cfdbb440389127c47c5decdc9e081cb624ffa0e3b952a42fba` and checks signature/patch bytes. **No VBIOS is redistributed in this source package.**
5. Select a *local folder inside your user home directory*, not an EFI partition and not the directory of the source config.
6. Confirm test-only usage, click **Gerar prévia e backup**.

The app creates a new uniquely named local folder containing:

- `config.original.backup.plist` — byte-identical copy of selected OpenCore config.
- `config.polaris-preview.plist` — full candidate config including `DeviceProperties/Add/<selected path>/ATY,bin_image` as the first **65,536 bytes** of the verified ROM and `device-id` as **Data `DF670000`**.
- `report.json` — metadata without SMBIOS secrets, marking this as preview only.

The app **does not** ask for root, mount or modify an EFI, change SIP, inject into a running system, install kernel extensions, modify firmware, or reboot. The original selected config is never overwritten.

## Build on macOS with Xcode

Open `Polaris2048Fix.xcodeproj` in Xcode, choose scheme `Polaris2048Fix`, destination **My Mac**, click Build / Run. There is no app binary in this archive. For a command line build:

```sh
xcodebuild -project Polaris2048Fix.xcodeproj \
  -scheme Polaris2048Fix -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath ./Build \
  CODE_SIGNING_ALLOWED=NO build
```

The unsigned development build should be at `Build/Build/Products/Debug/Polaris2048Fix.app`. A local unsigned Xcode build is for your own testing, not for public distribution; signing and notarization are separate tasks.

## Validate candidate before any hardware test

```sh
python3 Tools/verify_candidate.py /path/to/Polaris2048Fix-Preview-... \
  --pci-path 'PciRoot(0x0)/Pci(0x3,0x0)/Pci(0x0,0x0)'
```

The PCI path above is from an **old supplied config** and may be wrong on a newly installed system. The verifier confirms only that the two intended OpenCore property keys changed. It is not a substitute for a matching-version `ocvalidate`, EFI recovery media, IORegistry checks, or actual acceleration tests.

## Fundamental limitations

- `ATY,bin_image` is **not** a physical ROM replacement; PCI Device ID registers still report the physical GPU ID, and the ROM has already run during firmware initialization.
- OpenCore `DeviceProperties` may fail to inject such a large data blob or may not affect all AMD driver paths. No guarantee that this configuration enables Metal on a stock `0x6FDF` RX 580 2048SP.
- The matching ROM SHA-256 identifies *one user's modified ROM*, not a universal patch for every RX 580 2048SP board. Do not deploy this on other board revisions without specific analysis.
- This code was developed outside macOS; the `.xcodeproj` and SwiftUI app **have not been compiled or launched in Xcode here**. Static source and plist/integrity smoke checks are supplied instead. Xcode may reveal SDK-specific issues to correct.
- The `config.plist` can contain serial numbers and identifiers. Do not post your complete configuration publicly without redacting them.

## Future development (not implemented)

A later, **separate** installer can request administrator authorization via an appropriately registered and signed helper (for example, `SMAppService` with XPC). Such an installer must first establish actual boot compatibility with a USB test EFI and create a tested recovery/rollback plan. Root authorization is **not needed for this preview app**.

## GitHub Actions

A workflow is included in `.github/workflows/build.yml` to build the **source app** on `macos-26-intel` and upload an unsigned ZIP artifact. GitHub Actions success confirms that the UI compiles, not that a runtime GPU is detected or Metal works. Do not upload personal ROM or SMBIOS settings to a public repository.
