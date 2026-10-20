# Arcus file formats

This document specifies the on-disk formats owned by `ArcusPersistence` and `ArcusServices`:

1. `.arcus`: project package (schema v3; v2 files open unchanged, and the legacy v1 layout is migrated on read)
2. `.arcusfamily`: loadable family package
3. Type catalog CSV
4. Crash-recovery journal
5. Versioning, compatibility and safety limits

All multi-byte integers are little-endian. All text is UTF-8. "SHA-256" means lowercase hex of the SHA-256 digest (64 characters).

---

## 1. `.arcus` project package (schema v3)

A `.arcus` document is a **directory package**:

```
Tower.arcus/
├── manifest.json          required; package identity, version gate and checksums
├── model.sqlite           required; the model (SQLite 3, rollback-journal mode, never WAL)
├── assets/                optional; content-keyed compressed blobs (reference drawings)
│   └── <sha256>.lzfse
├── thumbnails/
│   └── preview.png        optional; Finder/Open-panel preview
└── assistant/
    └── history.json       optional; the AI assistant's chats (§1.7)
```

No other files are written. Readers ignore unknown files, but `verify` reports assets that are not listed in the manifest. Readers never follow symbolic links inside a package: a symlinked `model.sqlite` or asset is treated as missing.

### 1.1 Saving

`ArcusPackage.write(_:to:info:)` builds every file in memory: the database is built in an in-memory SQLite connection and serialized with `sqlite3_serialize`. It writes the files into a staging directory on the destination volume (`FileManager` "item replacement directory"; a hidden `.arcus-save-<uuid>` sibling is the fallback) and `fsync`s each one. The staged package is then renamed into place when `url` is new, or swapped in with `FileManager.replaceItemAt` when `url` exists. A reader never sees a half-written package at `url`. `ArcusPackage.fileWrapper(_:info:)` returns the same files as a directory `FileWrapper` for `NSDocument` file-wrapper saving, where AppKit's safe-save does the atomic replacement.

### 1.2 `manifest.json`

A JSON object. It is written pretty-printed with sorted keys, and dates are ISO-8601 UTC with milliseconds, rounded (`2025-01-01T00:00:00.000Z`). Readers ignore unknown keys.

| Key | Type | Meaning |
|---|---|---|
| `format` | string | `com.local.arcus.project` (families: `com.local.arcus.family`) |
| `schemaVersion` | int | Layout version the writer used (currently **3**) |
| `minimumReaderVersion` | int | Oldest reader version that can read this package correctly (currently **3**) |
| `writerAppVersion` | string | Marketing version of the writing app (`CFBundleShortVersionString`, e.g. `1.0.0`) |
| `writerBuild` | string | Build number (`CFBundleVersion`) |
| `documentID` | UUID string | Stable document identity; preserved across saves (a "Save As" copy gets a new one) |
| `created` / `modified` | ISO-8601 string | Creation date (preserved) / time of this save |
| `elementCount` | int | Number of rows in `elements` |
| `checksums` | object | Relative path → SHA-256 of **critical files**: `model.sqlite` and every file in `assets/` (not the thumbnail, not the manifest itself) |
| `isTemplate` | bool, optional | `true` for a project saved with File ▸ Save as Template (`ArcusPackage.writeTemplate`). Absent in ordinary projects. Templates have no model-category elements; user templates live in `~/Library/Application Support/Arcus/Templates/` |

Checksum keys must be relative paths of at most 4 components. A component must be non-empty, at most 255 bytes, not `.`/`..`, contain no `..`, not start with `.`, and contain no `/`, `\`, `:` or control characters. A manifest listing any other path is rejected as corrupt.

### 1.3 `model.sqlite`: schema v2

Identification: `PRAGMA application_id = 0x504C4E54` ("PLNT") and `PRAGMA user_version = 2`. The file is a standard SQLite 3 database in rollback-journal (`DELETE`) mode, with header bytes 18–19 = 1. It never has `-wal`, `-shm` or `-journal` side files. Readers open it read-only with `mode=ro&immutable=1`, or deserialize it from memory for `FileWrapper` input, with `trusted_schema=OFF` and `cell_size_check=ON`.

```sql
PRAGMA foreign_keys = ON;
PRAGMA application_id = 1347178068;   -- 0x504C4E54
PRAGMA user_version = 2;
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE elements(id INTEGER PRIMARY KEY, category TEXT NOT NULL, kind TEXT NOT NULL,
                      revision INTEGER NOT NULL, data BLOB NOT NULL);
CREATE TABLE relations(element_id INTEGER NOT NULL REFERENCES elements(id) ON DELETE CASCADE,
                       related_id INTEGER NOT NULL REFERENCES elements(id) ON DELETE CASCADE,
                       role TEXT NOT NULL);
CREATE TABLE project(key TEXT PRIMARY KEY, data BLOB);
CREATE INDEX relations_by_element ON relations(element_id);
CREATE INDEX relations_by_related ON relations(related_id);
```

All rows are written in one transaction with prepared statements.

**`meta`** (informational; the manifest is authoritative): `schema_version` (`2`), `writer_app_version`, `writer_build`, `document_id`, `element_count`, `created`, `modified`.

**`elements`**: one row per element.
- `id`: `ElementID.raw` (ids above `Int64.max` are refused on write)
- `category`: `Category.rawValue` (e.g. `walls`)
- `kind`: `ElementKind.rawValue` (e.g. `wall`)
- `revision`: `Element.revision`, stored as the signed bit pattern
- `data`: the element encoding (§1.4)

`category`, `kind` and `revision` are denormalized copies for queries and diagnostics. The model is rebuilt from `data` only, and `verify` reports any disagreement.

**`relations`**: derived rows, one per reference from an element to another element that exists in the same file. Dangling references stay in the element data and are reported by `verify`. The table is used for queries, integrity checks and `ON DELETE CASCADE` tooling; readers do not need it to rebuild the model.

| `role` | Source field |
|---|---|
| `type` | `Element.typeID` |
| `level` | `Element.levelID` |
| `host` | `Element.hostID` |
| `ownerView` | `Element.ownerViewID` |
| `phaseCreated` / `phaseDemolished` | `Element.phaseCreated` / `phaseDemolished` |
| `designOption` | `Element.designOptionID` |
| `group` | `Element.groupID` |
| `tagTarget` | `TagData.taggedID` |
| `viewportView` | `ViewportData.viewID` |

**`project`**: project-wide values. Each `data` is JSON (§1.4).

| key | JSON value |
|---|---|
| `nextID` | number: `BIMModel.nextID` |
| `revision` | number: `BIMModel.revision` |
| `projectParameters` | array of `ParameterDefinition` |
| `viewSheetSets` | array of `ViewSheetSet` |
| `referenceDrawings` | object: model drawing key → asset file name in `assets/` |

On read, `nextID` is raised to at least `max(element id) + 1`.

### 1.4 Element and value encoding

`data` holds the `Codable` JSON of `ArcusDomain.Element`, encoded by `JSONEncoder` with:
- `outputFormatting = [.sortedKeys, .withoutEscapingSlashes]`, so identical values give identical bytes
- non-finite doubles as the strings `"+Infinity"`, `"-Infinity"` and `"NaN"`
- dates in Foundation's default form (seconds since 2001-01-01, as a number)
- enums with associated values in Swift's synthesized form, e.g. `{"wall":{"_0":{…}}}`; `ElementID` as a bare number; `ParameterID` as a string, also as a dictionary key

Measured on 5,176 elements (debug build, Apple silicon): parallel JSON encoding took 0.016 s for 2.8 MB. Serial binary property-list encoding took 0.10 s for 3.9 MB, so it is slower and larger than JSON. JSON stays the encoding: it is also diffable and inspectable with `sqlite3`.

Encoding and decoding are split across cores (`DispatchQueue.concurrentPerform`). Each row is checked against the size and nesting limits (§5.3) before decoding. Decoded elements must satisfy `Element.id == row id`, and their IFC GUID must be 22 characters from the IFC alphabet. Otherwise the file is reported as corrupt.

### 1.5 Assets

Reference drawings (`BIMModel.referenceDrawings`) are stored as compressed assets:

- **Payload**: the drawing's JSON (§1.4 encoder).
- **Name**: `<SHA-256 of the uncompressed payload>.lzfse`, or `.zlib` for zlib assets. The name is content-keyed, so identical drawings share one file. Names must be single safe path components (§1.2). Separators, `..`, hidden names and control characters are rejected as `.corrupt`.
- **Container**:

  | Offset | Size | Field |
  |---|---|---|
  | 0 | 4 | magic `PLZ1` |
  | 4 | 1 | algorithm: `1` = LZFSE, `2` = zlib (raw DEFLATE as produced by `Compression`'s `COMPRESSION_ZLIB`) |
  | 5 | 3 | reserved, 0 |
  | 8 | 8 | uncompressed size (UInt64) |
  | 16 | … | compressed stream |

- **Reading** (zip-bomb protection):
  1. The declared size must be ≤ `maxAssetBytes` (1 GiB).
  2. The declared/compressed ratio must be ≤ `maxCompressionRatio` (1000:1). Payloads up to 4 KiB are exempt.
  3. Decompression is streamed and aborts as soon as the output exceeds the declared size.
  4. The output must match the declared size exactly, and its SHA-256 must equal the file-name stem.

  Every asset must also be listed with a matching checksum in the manifest.

### 1.6 Thumbnail

`thumbnails/preview.png` is optional, is not checksummed, and is capped at 32 MiB on read (`ArcusPackage.readThumbnail`).

### 1.7 AI assistant history

`assistant/history.json` is optional (written only when the document has chats), is not checksummed, and is capped at
32 MiB on read (`ArcusPackage.readAssistantHistory`). It is the `AIHistory` JSON of `ArcusAssistant` (`version`, `chats`:
each chat's prompts, reply text, tool steps, plan, changes, models and token usage). Attached images are not stored,
only their names, and the API key never is. Readers that don't know it ignore it; Settings ▸ AI ▸ Clear All Chats and
the sidebar's Clear History empty it (the file is dropped on the next save). Nothing in it is sent unless that chat is
continued in the sidebar.

---

## 2. Legacy schema v1 (migrated on read)

Arcus builds with schema v1 wrote this layout. It is still read, migrated in memory, and written back as v2 on the next save. `Tests/PersistenceTests/Fixtures/v1/Sample.arcus` is a committed v1 fixture, and `expected.json` next to it holds its exact expected content.

- The manifest has the same keys, with `schemaVersion = 1`, `minimumReaderVersion = 1` and a `checksums` entry for `model.sqlite` only.
- There is no `assets/` directory; drawings are stored inline in the database.
- `model.sqlite` uses `PRAGMA user_version = 1`:

```sql
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);   -- also holds project values as JSON text
CREATE TABLE elements(id INTEGER PRIMARY KEY, category TEXT NOT NULL, data BLOB NOT NULL);
CREATE TABLE drawings(key TEXT PRIMARY KEY, data BLOB NOT NULL);   -- ReferenceDrawing JSON, uncompressed
```

`meta` keys: `schema_version` (`1`), `nextID`, `revision`, `projectParameters`, `viewSheetSets`. Each project value is stored as JSON text in `value`. The element `data` encoding is the same as in v2. v1 has no `kind`, `revision` or `relations`; those are derived when the model is written as v2.

Layout detection: `user_version = 1` or the presence of a `drawings` table means v1. `user_version ≥ 2` together with a `project` table means v2. Anything else is corrupt.

---

## 3. `.arcusfamily` family package

```
Door - Single Flush.arcusfamily/
├── manifest.json          format "com.local.arcus.family", schemaVersion 2, minimumReaderVersion 1 or 2
├── family.json            FamilyDefinition JSON (§1.4 encoder)
└── thumbnails/preview.png optional
```

- `checksums` contains `family.json`.
- `elementCount` is the number of family types.
- Re-writing a family at an existing URL keeps its `documentID` and `created` date.
- `FamilyPackage.readerVersion` is 2. Schema 2 is additive JSON: sweeps, blends and revolves (`FamilySolid.profile` cases `sweep`, `blend`, `revolve`), nested families (`nestedFamilies`, `nestedInstances`, `isShared`), EQ and locked dimensions (`isEquality`, `planeC`, `isLocked`) and per-view visibility (`visibleIn3D`, `visibleInFrontBack`, `visibleInLeftRight`).
- `minimumReaderVersion` is 2 only when the family uses one of those features (`FamilyDefinition.minimumReaderVersion`), so families that don't stay readable by schema-1 builds. Schema-1 families decode with defaults (visible everywhere, nothing nested, no locks).
- `FamilyDefinition.formatVersion` inside the JSON versions the family content model itself (currently 2).

Families placed in a project are ordinary elements (`ElementData.family`) inside `model.sqlite`, so a project needs no `families/` directory.

---

## 4. Type catalog CSV

`TypeCatalog.parse(_:family:)` / `TypeCatalog.export(_:)`

**Encoding and syntax**
- UTF-8; a leading BOM is ignored.
- RFC 4180: comma separator, fields containing `,`, `"` or line breaks are quoted, and `""` inside a quoted field is a literal quote.
- Lines end with CRLF (export) or LF (both accepted).
- `.` is the decimal separator. Exponent notation (`1e3`) is accepted. Thousands separators, `inf` and `nan` are rejected.

**Header (row 1)**
- The first cell is `Type Name` (also accepted: `Type`, `Name`, or empty).
- Every other cell has the form `Parameter Name [kind:unit]`, `Parameter Name [kind]` or `Parameter Name`. A bare name uses the family parameter's own kind with its default unit.

| kind | units (default first) | stored as |
|---|---|---|
| `length` | `mm`, `cm`, `m`, `in`, `ft` | metres |
| `area` | `m2`, `mm2`, `cm2`, `in2`, `ft2` (`²` accepted) | m² |
| `volume` | `m3`, `mm3`, `cm3`, `l`, `in3`, `ft3` | m³ |
| `angle` | `deg`, `rad` | radians |
| `slope` | `ratio`, `%` | rise/run |
| `percentage` | `%`, `fraction` | fraction |
| `number`, `currency` | none | double |
| `integer` | none | int |
| `text` | none | text; `choice` parameters must match one of their options |
| `bool` (`yes/no`) | none | `Yes`/`No`/`true`/`false`/`1`/`0`/`y`/`n` |

**Parsing rules**
- Metric conversions divide by exact powers of ten, so `900 [length:mm]` imports as exactly `0.9`.
- Negative lengths, areas and volumes are rejected.
- Header problems do not abort the import. The column is ignored and an error is reported as `Row 1: column N (…): …`. Header problems are:
  - an unknown parameter
  - an element-reference parameter
  - a formula-driven parameter
  - a kind that doesn't match the parameter
  - an unknown unit
  - a repeated parameter
- Row problems skip the type and are reported as `Row R: …`, where `R` is the 1-based line number in the file. Row problems are:
  - an empty type name
  - a duplicate type name
  - an invalid number, integer, yes/no value or choice
- Empty cells leave the parameter unset for that type. Blank lines are skipped.
- `parse` throws `TypeCatalog.CatalogError` only when the file is unusable as a whole:
  - it is not UTF-8
  - it is empty
  - the first header cell is wrong
  - it ends inside an unterminated quote
  - it has more than 100,000 rows or is over 64 MB

**Export**
- Export writes every non-formula, non-instance type parameter that a catalog can express.
- Lengths are written in mm, areas in m², volumes in m³ and angles in degrees.
- Numbers are written with up to 9 decimals, trailing zeros trimmed and no exponent notation.
- Export followed by parse reproduces metric values bit-for-bit.

---

## 5. Versioning, compatibility and limits

### 5.1 `schemaVersion` vs `minimumReaderVersion`

- `schemaVersion` is incremented for **any** change to the package layout, the SQL schema or value encoding.
- `minimumReaderVersion` is raised only when older readers can no longer read the file correctly. That covers changed meaning, removed or renamed tables and keys, and required new data. Purely additive changes keep it, and old readers ignore what they don't know.
- `ArcusPackage.readerVersion` (currently 3) is the highest `minimumReaderVersion` this build accepts. `ArcusPackage.oldestReadableSchema` is 1.
- Schema 3 keeps the schema-2 package and SQL layout (`model.sqlite` is still `user_version = 2`) and adds element data: ramps, Join Geometry constraints, roofs by extrusion, floor/roof shape points, family sweep/blend/revolve/nested forms, scope boxes, colour schemes, dimension chain styles and group array specs (the full list is on `ArcusPackage.currentSchemaVersion`). Every new field decodes with a default, so schema-2 files open unchanged (`Tests/PersistenceTests/Fixtures/v2` is a committed schema-2 document). Schema-3 files set `minimumReaderVersion = 3`, so schema-2 builds refuse them with the newer-format message instead of failing on element kinds they don't know.

**Reader decision**
1. `format` isn't the expected identifier, or the item isn't a directory with a manifest → `.notAPackage`.
2. `minimumReaderVersion > readerVersion` → `.newerFormat(requiredReader:writtenBy:)`. The message names the writing version, e.g. "was saved by Arcus 9.4.1 (build 9001) in a newer file format … install Arcus 9.4.1 or later … The file has not been changed." `readManifest` still succeeds, so the UI can show who wrote the file.
3. `schemaVersion < oldestReadableSchema` → `.unsupportedSchema`.
4. `schemaVersion > currentSchemaVersion` with a readable `minimumReaderVersion` → the file opens. `ArcusPackage.isNewerThanCurrent(manifest)` returns true, and the app should warn that saving will drop data this version doesn't understand.
5. Older schemas are migrated in memory; the file on disk is not rewritten until the user saves.

**Migration policy**
- Every schema change adds a reader path for the previous layout and a committed fixture with expected content, and bumps `currentSchemaVersion`.
- Migration is always read-side and in memory. Arcus never rewrites a document without an explicit save.
- Readers stay able to read at least the previous schema indefinitely.
- `Element` data is the Domain's `Codable` form. Domain types must decode older JSON; new stored properties need `decodeIfPresent` defaults, or old documents stop opening.

### 5.2 Error kinds

| `PersistenceError.Kind` | When | User message ends with |
|---|---|---|
| `notAPackage` | wrong item or format | "Choose a file with the .arcus extension…" |
| `newerFormat` | §5.1 step 2 | the version to install |
| `corrupt(detail)` | unreadable manifest or DB, undecodable element, bad asset name, missing file, id or GUID mismatch | "Use “Save Recovery Copy…” … or restore from a backup." |
| `checksumMismatch(path)` | SHA-256 differs from the manifest | "Use “Save Recovery Copy…” …" |
| `unsupportedSchema(v)` | schema below 1 | pre-release note |
| `io(message)` | file-system failures | the system reason |
| `limitExceeded(detail)` | §5.3 | "may be damaged or not a genuine Arcus document" |

**`verify(url)`** never throws. It returns an `IntegrityReport` built from these checks:
- the manifest
- every checksum
- unlisted assets
- `PRAGMA integrity_check`
- `PRAGMA foreign_key_check`
- element decoding
- id, category, kind and GUID consistency
- the element count
- dangling references
- `nextID` against the maximum id
- consistency of the `relations` table
- decoding of every asset

**`saveRecoveryCopy(from:to:info:)`** ignores checksum mismatches, which it reports.
1. It scans element rows in id order. On a damaged B-tree page it resumes after the last good id, and keeps skipping ahead with growing steps.
2. It keeps every element that decodes. Elements with invalid IFC GUIDs get deterministic replacement GUIDs.
3. It salvages each project value and drawing independently.
4. It writes a fresh v2 package at `dest`. The source is never modified.

The returned report's `recoveredElements + lostElements` equals the original element count.

### 5.3 Limits (`PersistenceLimits.default`)

| Limit | Default |
|---|---|
| elements per document | 5,000,000 |
| one element's `data` | 64 MiB |
| one `project` value | 256 MiB |
| decompressed asset | 1 GiB |
| compression ratio | 1000:1 |
| assets per document | 100,000 |
| `manifest.json` | 4 MiB (nesting ≤ 16) |
| JSON nesting depth (elements, project values, drawings, families) | 256 |
| thumbnail | 32 MiB |
| `family.json` | 256 MiB |
| type catalog rows | 100,000 |

Readers check sizes (`length(data)`, file sizes and declared sizes) before allocating. Truncated or garbage SQLite, garbage JSON and hostile nesting produce errors, never crashes. Files are read without memory mapping, so a file truncated during a read cannot cause `SIGBUS`.

---

## 6. Crash-recovery journal

`RecoveryJournal(baseDirectory:)`. The app passes `~/Library/Application Support/Arcus/Recovery`; tests pass temporary directories.

```
<base>/<documentID>/
├── session.json     identity and bookkeeping (JSON, sorted keys, rewritten atomically)
├── base.arcus      full .arcus snapshot of the model at begin — untitled documents only
└── journal.bin      append-only records
```

**`session.json`**

| Key | Meaning |
|---|---|
| `formatVersion` | `1` |
| `documentID` | the document's identity |
| `displayName` | name shown in the recovery panel |
| `savedPath` | saved document path (absent for untitled documents) |
| `savedBookmark` | base64 URL bookmark, used to find a moved file |
| `savedFingerprint` | `size`, `modificationDate`, `documentID`, `manifestModified` of the saved package |
| `hasBase` | whether `base.arcus` exists |
| `baseRevision` | model revision of the base |
| `created` | session start |
| `lastChange` | timestamp of the last record |
| `changeCount` | number of records |
| `cleanShutdown` | set when the session ended normally |
| `pid` | process that owns the session |
| `appVersion` | writer version |

**`journal.bin`** starts with the 8-byte header `PLNTJRN1`, followed by frames:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | payload length (UInt32, ≤ 1 GiB) |
| 4 | 4 | CRC-32 (IEEE, reflected, polynomial 0xEDB88320) of the payload |
| 8 | n | payload: JSON `{"v":1,"record":TransactionRecord,"drawings":{key: ReferenceDrawing}?}` |

`drawings` carries the content of the drawings named in `record.addedDrawings`, because transaction records hold only their keys.

**Protocol**

| Call | Effect |
|---|---|
| `begin` | Replaces any previous folder for the document. Untitled documents get a `base.arcus` snapshot. Saved documents record path, bookmark and fingerprint instead. |
| `append` | Writes the frame immediately, so it survives an app crash. `fsync` of the journal and the `session.json` update are coalesced to at most one per `syncInterval` (1 s) through a deferred task. The app must append every record it applies, including undo (`record.inverse`) and redo. |
| `flush` | Syncs immediately. |
| `markSaved` | Truncates `journal.bin` to its header, deletes `base.arcus`, and records the new saved file's identity; the saved file becomes the base. |
| `end` | Sets `cleanShutdown`, then deletes the folder. |
| `pendingRecoveries` | Lists leftover sessions, most recent `lastChange` first. |
| `recover` / `recoverWithReport` | Rebuilds the model: base + replay (see below). |
| `discard` | Deletes the folder. |

`pendingRecoveries` skips:
- sessions open in the same journal instance
- sessions whose `pid` belongs to another live process
- cleanly ended sessions, which it deletes

A saved document with zero records has nothing to recover, so its session is deleted. Untitled sessions are always listed. `RecoveryItem.problem` explains a truncated tail, a missing snapshot, or a saved file that is missing or has changed.

`recover` / `recoverWithReport` loads the base:
- `base.arcus` for untitled documents
- otherwise the saved file, found by path and then by bookmark

For a saved document, the saved file's manifest `documentID` and `modified` must still match the recorded fingerprint. If they don't, recovery refuses and keeps the journal. The base is never modified.

It then replays every complete frame with `BIMModel.apply(_:)`, inserting journaled drawings first. A truncated tail frame (length beyond EOF, or fewer than 8 header bytes) is ignored with a warning. A CRC or JSON failure stops the replay at the last good record, also with a warning. Changes whose `before` state doesn't match the base are counted in a warning. The recovered model is returned to the app, which opens it as a modified or untitled document. Recovery never overwrites the user's file.

---

## 7. Related services

- **External changes:** `ExternalChangeDetector.fingerprint(url)` returns a `FileFingerprint`. For packages it holds the size of `manifest.json` + `model.sqlite` (or `family.json`), the latest modification date, and the manifest's `documentID` and `modified`. For plain files it holds size and modification date. `hasChanged(url, since:)` compares a new fingerprint with an earlier one; a missing file counts as changed.
- **App version:** `AppVersionInfo.current` reads `CFBundleShortVersionString` / `CFBundleVersion` only from a `com.local.arcus*` bundle. Outside one (tests, tools) it returns `0.0.0` / `dev`.
- **Updates:** `LocalOnlyUpdateProvider` is never enabled and never uses the network. Updating means replacing `Arcus.app` with a newer local build.
- **Diagnostics:** `DiagnosticsLog` keeps an in-memory ring buffer mirrored to OSLog with private message redaction. `exportRedacted()` makes these replacements:

  | Original | Replaced with |
  |---|---|
  | home directory, `/private` + home directory, any `/Users/<name>` prefix | `~` |
  | account short and full names | `<user>` |
  | registered project names | `<project>` |
  | document-like file names (`.arcus`, `.ifc`, `.dwg`, `.dxf`, `.pdf`, `.csv`…) | `<file>.<ext>` |

  Project and file names are kept when the export is called with `includeProjectNames: true`. Messages are capped at 2,000 characters, and file contents are never logged.
