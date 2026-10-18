// ArcusBimRvBridge — C API between Arcus (Swift) and the licensed ODA BimRv SDK (C++).
//
// UNVERIFIED: written without access to the SDK; see Docs/RevitInterop.md ("Direct RVT/RFA import with the ODA BimRv SDK").
// This target is compiled only when ARCUS_ODA_BIMRV_SDK_DIR is set (see the Package.swift snippet in that document).
// No SDK headers, binaries or documentation are included in this repository.
#ifndef ARCUS_BIMRV_BRIDGE_H
#define ARCUS_BIMRV_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ArcusBimRvError {
    int code;
    char message[512];
} ArcusBimRvError;

/// Initializes the SDK once per process. Returns 0 on success.
int arcus_bimrv_initialize(ArcusBimRvError *error);

/// The SDK's version string, or NULL before initialization.
const char *arcus_bimrv_sdk_version(void);

/// Opens `revitPath` (.rvt, .rfa, .rte, .rft) read-only and writes an Arcus Exchange (.arcusx, schema 1.0) JSON
/// translation to `outPath`. The source file is never written. Returns 0 on success.
int arcus_bimrv_export_arcusx(const char *revitPath, const char *outPath, int includeMeshes, ArcusBimRvError *error);

/// Releases the SDK.
void arcus_bimrv_terminate(void);

#ifdef __cplusplus
}
#endif

#endif
