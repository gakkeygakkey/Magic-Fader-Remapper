# Magic Fader Remapper (MF-RM)

[日本語](README.ja.md) · English

A macOS menu bar utility for **PLATANE Magic Fader and Pro Tools**. It translates selected HUI MIDI messages to make automation and send control more convenient, without modifying the controller firmware or Pro Tools.

```text
Magic Fader ⇄ MF-RM ⇄ Pro Tools
```

An independent GAKKEY LAB project, not an official PLATANE or Avid application. PLATANE has permitted use of its product imagery and logo for this project; see [Artwork and trademarks](THIRD_PARTY_NOTICES.md).

## Download and requirements

- [Download 2026.10.3 (DMG)](https://github.com/gakkeygakkey/gakkey-lab-site/releases/download/MF-RM-2026.10.3/Magic-Fader-Remapper-2026.10.3.dmg) · [Release page](https://github.com/gakkeygakkey/gakkey-lab-site/releases/tag/MF-RM-2026.10.3)
- **macOS 15.6 or later**. The distributed app is a universal binary for Apple silicon and Intel Macs.
- Magic Fader in HUI mode and Pro Tools with HUI support. Trim requires an edition of Pro Tools that supports Trim automation.
- English and Japanese interface.

The existing DMG is currently hosted in the GAKKEY LAB website repository. This repository contains the app source. Older macOS versions have not been verified.

## Features

All feature switches are **OFF on a clean first launch**. Enable what you need; settings and the last successful controller connection are remembered.

| Setting | Behavior |
| --- | --- |
| Rec Ready → Touch / Read | Alternates Touch and Read using the track's Rec Ready button. Its LED follows automation feedback. |
| Transport Record → Trim | Toggles Trim with the transport Record button, with LED feedback. |
| Loop → Flip | Controls send level with the motorized fader using HUI Flip. Loop LED indicates Flip. Returning from Flip selects Pan to restore the normal display and fader assignment. |
| Restore Last Send | Optionally recalls the last selected send when entering Flip; defaults to Send A if none is remembered. |
| Rewind / FF → Select Send | Selects previous/next send, cycling A–E, regardless of Flip state. Stop retains its normal function. |
| Solo Release Repair | Adds a missing Solo Release about 50 ms after Press; see limitations below. |
| Click → Fader Refresh (experimental) | Moves the physical fader by about 5% of its position range and returns it after about 100 ms, to help relieve persistent motor buzzing. |

Hover over a setting to see its explanation and corresponding physical button. Diagram colors show **enabled mappings**, not live LED states. Diagnostics & MIDI Log offers optional capture, copy, and clear controls; routing continues with capture OFF.

## Setup

1. Open the DMG, drag **MF-RM** to **Applications**, and launch it.
2. Click the **fader icon in the menu bar**, then **Settings…**.
3. Put Magic Fader in HUI mode. In **Connection**, select Magic Fader for both Input and Output, then **Connect**.
4. In Pro Tools, enable **MF-RM** in **MIDI Input Devices**. On first installation this may be unchecked, hiding it from the HUI input list.
5. In **Peripherals → MIDI Controllers**, set Type to **HUI**, Receive From and Send To to **MF-RM**, and channels to **8**. Do not also configure a direct HUI connection to the same Magic Fader.
6. Enable the desired switches in MF-RM. Leave the app running while using this route.

The saved controller reconnects when the same MIDI endpoints return. If its identity changes, select and connect it again. Quitting removes the virtual MIDI ports; to use the controller without MF-RM, restore the direct connection in Pro Tools.

## Behavior and limitations

### Solo Release Repair

Testing with Magic Fader firmware **2.11** found Solo Press without its corresponding Release. In Pro Tools **X-OR** Solo Mode, using hardware Solo could leave **Shift+S unable to turn Solo off**. In **Momentary**, Solo could remain active after releasing the button. The reported Shift+S issue did not occur in Latch mode.

The repair resolved the X-OR/Shift+S issue in the author's setup. Its synthetic Release after about 50 ms **does not represent the physical release timing** and does not reproduce hold-to-solo behavior in Momentary mode.

PLATANE confirmed the missing Release and reported a firmware fix in development in October 2026. This is a dated report, not a claim about the latest firmware. If your firmware sends Release correctly, leave the repair OFF and verify X-OR and Momentary directly. Mute and other unverified buttons do not receive this repair.

### Fader Refresh

Use while stopped, with your hand off the fader. Refresh movement/return commands go **only to Magic Fader**, not Pro Tools. Normal bidirectional routing remains active; this is not an isolation or blocking mode. A touch or a new fader-position message from Pro Tools cancels refresh so normal operation takes priority.

The target is the last selected HUI channel, matching Magic Fader's retained target when an out-of-bank track is selected. A known position is required first. The author has relieved buzzing without changing Pro Tools fader values in actual use; this is an experimental workaround, not a repair for mechanical or power-supply problems.

### Flip and routing

- Send selection covers **A–E**; F–J selection is not implemented.
- HUI Flip also changes relevant Mute/V-Pot assignments. Check the target send before writing automation.
- Turning a mapping OFF restores its original button role; it does not necessarily undo an already selected Pro Tools automation or Flip mode.
- MF-RM does not generate proxy HUI ping replies. Keep the actual controller connected.
- “Connected” describes the controller connection, not proof of a working Pro Tools HUI session.

## Build from source

The project/scheme retains the original name **HUI-RM**; the product is **MF-RM.app**, and its MIDI ports are **MF-RM**. Bundle ID `com.gakkey.HUI-RM` is retained to preserve settings.

1. Open `HUI-RM.xcodeproj` in Xcode. Source-release preparation uses **Xcode 27.1**; older toolchains have not been verified. The project includes an Icon Composer `.icon` asset.
2. Select the **HUI-RM** scheme and **My Mac**. For a signed build, select your own team in Signing & Capabilities; the saved team belongs to the original developer.
3. Build and run. The shared scheme selects English for Xcode launches. Change Scheme → Run → Options → App Language to test Japanese or the system language.

Compilation check without signing or launching, from the repository root:

```sh
xcodebuild -project HUI-RM.xcodeproj -scheme HUI-RM -configuration Release -destination 'generic/platform=macOS' -derivedDataPath /tmp/MFRM-build CODE_SIGNING_ALLOWED=NO build
```

Standalone message-processing checks live in `Tests/`. For example:

```sh
xcrun swiftc -module-cache-path /tmp/MFRM-swift-cache HUI-RM/RecAutomationRemapper.swift HUI-RM/EventListTransport.swift Tests/EventListTransportChecks.swift -o /tmp/MFRM-transport-checks
/tmp/MFRM-transport-checks
```

These checks do not replace physical-controller and Pro Tools testing. [Historical development notes](docs/development-history.md) preserve earlier experiments and may describe superseded behavior.

## Feedback and contributions

Built primarily for the author's mixing workflow and also used by other Magic Fader users. Reports and contributions are welcome; broader hardware, Pro Tools, and macOS compatibility is not guaranteed.

Include macOS, Pro Tools and firmware versions, enabled settings, exact steps, and a short MIDI log when relevant. For Solo issues include **Latch / X-OR / Momentary**. Check screenshots and logs for session/track names before sharing publicly.

## License

Original source code and documentation use the [MIT License](LICENSE). **Product artwork, logos and trademarks are excluded**; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Permission for this project is not a blanket license to reuse PLATANE branding in other products.
