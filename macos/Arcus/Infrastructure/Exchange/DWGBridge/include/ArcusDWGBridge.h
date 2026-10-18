/*
 * ArcusDWGBridge — pure C API over the licensed ODA Drawings SDK (formerly Teigha) used by Arcus's DWG import.
 *
 * STATUS: UNVERIFIED. This bridge is compiled only when ARCUS_ODA_SDK_DIR points at a local, licensed ODA Drawings SDK
 * for macOS arm64 (see Docs/DWGSDKSetup.md). It has not been compiled or run on a machine with the SDK yet; treat it as
 * unverified until it is built against a licensed SDK and exercised with real DWG test files.
 *
 * Design: the bridge opens a DWG with the SDK and lets the SDK itself translate it to DXF (a private temporary file). Arcus's
 * native DXF reader then parses that translation, so DWG and DXF share one conversion path. The bridge additionally enumerates
 * proxy / custom / solid-modeling entities with their geometric extents and class names, keyed by handle, so Arcus can keep
 * them as reference boxes instead of dropping them.
 *
 * Thread safety: arcus_dwg_initialize must succeed before any other call. Open databases must not be shared between threads.
 */
#ifndef ARCUS_DWG_BRIDGE_H
#define ARCUS_DWG_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Error details returned by bridge calls (UTF-8, NUL-terminated).
typedef struct ArcusDWGError {
    int code;
    char message[1024];
} ArcusDWGError;

/// Opaque handle to an open DWG database.
typedef struct ArcusDWGDatabase ArcusDWGDatabase;

/// Information about one entity the DXF translation may not represent geometrically (proxy, custom, ACIS…).
typedef struct ArcusDWGObjectInfo {
    const char *handle;      /* hex handle, e.g. "2F1" */
    const char *typeName;    /* DXF name or original class name for proxies, e.g. "ACAD_PROXY_ENTITY", "AECC_COGO_POINT" */
    int hasExtents;          /* 1 when minX…maxY are valid (WCS, drawing units) */
    double minX, minY, maxX, maxY;
} ArcusDWGObjectInfo;

typedef void (*ArcusDWGObjectCallback)(const ArcusDWGObjectInfo *info, void *context);
/// Returns non-zero to cancel the enumeration.
typedef int (*ArcusDWGCancelCallback)(void *context);

/// Initializes the SDK (idempotent). Returns 0 on success; on failure fills `error`.
int arcus_dwg_initialize(ArcusDWGError *error);
/// Releases the SDK. Call only at process shutdown after all databases are closed.
void arcus_dwg_terminate(void);
/// SDK version string (static storage), or NULL before initialization.
const char *arcus_dwg_sdk_version(void);

/// Opens a DWG file read-only (UTF-8 path). Returns NULL on failure and fills `error`.
ArcusDWGDatabase *arcus_dwg_open(const char *utf8Path, ArcusDWGError *error);
/// Format version code of the opened file (e.g. "AC1032"), valid while the database is open.
const char *arcus_dwg_file_version(ArcusDWGDatabase *db);
/// Writes an ASCII DXF translation of the database to `utf8OutPath`. The source DWG is never modified. Returns 0 on success.
int arcus_dwg_write_dxf(ArcusDWGDatabase *db, const char *utf8OutPath, ArcusDWGError *error);
/// Enumerates proxy / custom / solid-modeling entities in all block table records (model, layouts, blocks).
/// Returns 0 on success, 2 when cancelled, 1 on error.
int arcus_dwg_enumerate_objects(ArcusDWGDatabase *db, ArcusDWGObjectCallback callback, ArcusDWGCancelCallback isCancelled,
                                 void *context, ArcusDWGError *error);
/// Closes the database.
void arcus_dwg_close(ArcusDWGDatabase *db);

#ifdef __cplusplus
}
#endif

#endif /* ARCUS_DWG_BRIDGE_H */
