# Privacy and permissions

Arcus is a local-only application.

## What Arcus does not do

- **No network access.** The source contains no `URLSession`, Network framework, socket or web-view use. The only URLs in the repository are the XML DTD reference in `Info.plist` and documentation links. Arcus does not check for updates: the Settings window says so, and `LocalOnlyUpdateProvider` always reports "disabled".
- **No analytics, telemetry, crash upload, advertising, tracking or sign-in.** Nothing in the app sends data anywhere.
- **No remote fonts or assets.** Arcus uses system fonts and SF Symbols only.
- **No privacy-protected resources.** `Info.plist` has no usage-description keys, and `script/build_and_run.sh` fails the build if one appears. Arcus never requests any of these:

  | Permission | Requested? |
  |---|---|
  | Accessibility (controlling other apps) | No |
  | Screen Recording | No |
  | Input Monitoring | No |
  | Full Disk Access | No |
  | Camera / Microphone | No |
  | Contacts / Calendars / Reminders | No |
  | Photos | No |
  | Location | No |
  | Bluetooth | No |
  | Automation (Apple Events) | No |

- **No login items, background agents or kernel/system extensions.** The only helper tools are the two DWG engines in
  `Arcus.app/Contents/Helpers/` (`arcus-dwg`, built on acadrust, and GNU LibreDWG's `dwg2dxf`). Arcus starts one only
  while it reads or writes a DWG you chose, on a private copy in a temporary folder; it exits when the conversion ends
  (or after a timeout, or when you cancel). They run locally with your user's permissions, make **no network
  connections** (neither binary calls any socket or name-resolution function: `nm -u` lists none), and receive only file
  paths as arguments. Nothing is downloaded at run time: both are built and signed when Arcus is built.

## Files Arcus reads and writes

| What | Where | When |
|---|---|---|
| Projects (`.arcus`) and families (`.arcusfamily`) | Wherever you save them | You save or autosave (NSDocument autosave in place) |
| Imported and linked files (IFC, DXF, DWG, PDF, images, CSV) | Their original locations | **Read only.** Linked sources are never modified; reload re-reads them. A DWG is copied to a private temporary folder (`$TMPDIR/Arcus-DWG-<uuid>/`, mode 0700) for the DWG engine and the folder is deleted afterwards |
| Exports (IFC, DXF, DWG, PDF, CSV) | The folder you choose | You export. DWG is written in a private temporary folder first and moved into place only after it reads back |
| Crash-recovery journal | `~/Library/Application Support/Arcus/Recovery/<document id>/` | While a document has unsaved changes. It is deleted when the document closes normally or you discard it at the recovery prompt |
| Preferences (workspace layout, snap distance, typed aliases, onboarding done; DWG export version and layers; the name of the last DWG read and which engine read it) | `~/Library/Preferences/com.local.Arcus.plist` (user defaults) | You change a setting |
| Window and panel layout | User defaults (autosave names) | Automatically |
| Diagnostics log and timings | Memory, plus the local macOS unified log (subsystem `com.local.arcus`, message text marked private; viewable in Console and never leaves the Mac) | Shown in **Manage → Diagnostics**. Written to a file only if you choose **Export**. The export is redacted: home-directory paths become `~`, account names become `<user>`, project names become `<project>`, and document file names keep only their extension |

Files open through the standard open and save panels, so macOS grants access to exactly what you pick. Arcus is not sandboxed in this local build (it is ad-hoc signed and not notarized), but it only touches the locations above.

## Linked libraries

The app links only Apple system frameworks (AppKit, SwiftUI, Foundation, CoreGraphics, CoreText, ImageIO, Metal, MetalKit, QuartzCore, CryptoKit, CoreTransferable, Observation) and the system `libsqlite3` and `libcompression`. You can check this with `otool -L build/Arcus.app/Contents/MacOS/Arcus`. There are no third-party SDKs. The DWG helpers link only `libSystem` (and `arcus-dwg` the system `libiconv`); `script/build_and_run.sh` refuses to bundle a helper that links anything outside `/usr/lib` or `/System`. A DWG-enabled build would link the licensed ODA Drawings SDK, which runs locally and has no network features that Arcus uses.

## How this was checked

- A source audit (`grep`) for networking, capture, location, contacts, calendars, photos, Bluetooth, accessibility-trust, screen-capture, HID, Apple Events, login items, analytics and telemetry APIs found none.
- `plutil -p build/Arcus.app/Contents/Info.plist` shows no `NS…UsageDescription` keys. `script/build_and_run.sh` enforces this on every build.
- `otool -L` lists only system libraries (above), for the app and both DWG helpers.
- `nm -u` on `arcus-dwg` and `dwg2dxf` lists no `socket`, `connect`, `getaddrinfo`, `gethostbyname`, `sendto` or `recvfrom` imports (checked 2026-10-19).
