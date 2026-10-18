// ArcusDWGBridge.cpp — C API over the licensed ODA Drawings SDK.
//
// UNVERIFIED: written against the documented ODA Drawings (Teigha) API — OdDbDatabase via ExSystemServices /
// ExHostAppServices, readFile, block table records, OdDbEntity subclasses, OdDbProxyEntity, OdDbDimension — but NOT yet
// compiled or run: the SDK is licensed and not present on the development machine. Build it with ARCUS_ODA_SDK_DIR set
// (Docs/DWGSDKSetup.md) and run the DWG verification steps before shipping. Header names and link libraries differ between
// SDK releases; adjust the ODA section of Package.swift if the build reports missing headers or symbols.
//
// This file is compiled only when Package.swift finds ARCUS_ODA_SDK_DIR.

#include "ArcusDWGBridge.h"

#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_set>

#include "OdaCommon.h"
#include "OdString.h"
#include "OdAnsiString.h"
#include "RxObjectImpl.h"
#include "StaticRxObject.h"
#include "RxInit.h"
#include "RxDynamicModule.h"
#include "DbDatabase.h"
#include "DbEntity.h"
#include "DbBlockTable.h"
#include "DbBlockTableRecord.h"
#include "DbSymbolTable.h"
#include "DbProxyEntity.h"
#include "DbDimension.h"
#include "Ge/GeExtents3d.h"
#include "ExSystemServices.h"
#include "ExHostAppServices.h"
#include "OdError.h"

// Newer SDK releases require a license activation call. The activation header is supplied with your ODA membership
// (it is NOT part of the repository). If present on the include path, it is used automatically.
#if __has_include("OdActivationInfo")
#include "OdActivationInfo"
#define ARCUS_ODA_HAS_ACTIVATION 1
#endif

namespace {

class ArcusServices : public ExSystemServices, public ExHostAppServices {
protected:
    ODRX_USING_HEAP_OPERATORS(ExSystemServices);
};

OdStaticRxObject<ArcusServices> *g_services = nullptr;
std::mutex g_mutex;
bool g_initialized = false;
std::string g_version;

void setError(ArcusDWGError *e, int code, const std::string &msg) {
    if (!e) return;
    e->code = code;
    std::snprintf(e->message, sizeof(e->message), "%s", msg.c_str());
}

std::string utf8(const OdString &s) {
    // OdString holds UTF-16/32 code units (OdChar); encode to UTF-8 manually so the result does not depend on the
    // SDK's ANSI code page conversion.
    std::string out;
    const OdChar *p = s.c_str();
    for (int i = 0; i < s.getLength(); ++i) {
        unsigned long c = (unsigned long)p[i];
        if (sizeof(OdChar) == 2 && c >= 0xD800 && c <= 0xDBFF && i + 1 < s.getLength()) {
            unsigned long lo = (unsigned long)p[i + 1];
            if (lo >= 0xDC00 && lo <= 0xDFFF) { c = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00); ++i; }
        }
        if (c < 0x80) out += (char)c;
        else if (c < 0x800) { out += (char)(0xC0 | (c >> 6)); out += (char)(0x80 | (c & 0x3F)); }
        else if (c < 0x10000) { out += (char)(0xE0 | (c >> 12)); out += (char)(0x80 | ((c >> 6) & 0x3F)); out += (char)(0x80 | (c & 0x3F)); }
        else { out += (char)(0xF0 | (c >> 18)); out += (char)(0x80 | ((c >> 12) & 0x3F)); out += (char)(0x80 | ((c >> 6) & 0x3F)); out += (char)(0x80 | (c & 0x3F)); }
    }
    return out;
}

OdString fromUTF8(const char *s) {
    // Decode UTF-8 into OdChar code units (UTF-32 on macOS where OdChar is wchar_t).
    OdString out;
    const unsigned char *p = (const unsigned char *)s;
    while (*p) {
        unsigned long c = *p++;
        int extra = c >= 0xF0 ? 3 : c >= 0xE0 ? 2 : c >= 0xC0 ? 1 : 0;
        if (extra) c &= (0x3F >> extra);
        for (int k = 0; k < extra && (*p & 0xC0) == 0x80; ++k) c = (c << 6) | (*p++ & 0x3F);
        if (sizeof(OdChar) == 2 && c >= 0x10000) {
            c -= 0x10000;
            out += (OdChar)(0xD800 + (c >> 10));
            out += (OdChar)(0xDC00 + (c & 0x3FF));
        } else {
            out += (OdChar)c;
        }
    }
    return out;
}

std::string describe(const OdError &e) { return utf8(e.description()); }

// DXF names Arcus's DXF reader converts natively; anything else is reported with extents.
const std::unordered_set<std::string> &nativeTypes() {
    static const std::unordered_set<std::string> s = {
        "LINE", "LWPOLYLINE", "POLYLINE", "ARC", "CIRCLE", "ELLIPSE", "SPLINE", "POINT", "TEXT", "MTEXT", "HATCH",
        "SOLID", "TRACE", "INSERT", "ATTDEF", "ATTRIB", "DIMENSION", "ARC_DIMENSION", "LARGE_RADIAL_DIMENSION", "LEADER",
        "MULTILEADER", "IMAGE", "3DFACE", "VERTEX", "SEQEND",
    };
    return s;
}

} // namespace

struct ArcusDWGDatabase {
    OdDbDatabasePtr db;
    char version[8];
};

extern "C" int arcus_dwg_initialize(ArcusDWGError *error) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_initialized) return 0;
    try {
#ifdef ARCUS_ODA_HAS_ACTIVATION
        odActivate(ActInfo, ActKey);
#endif
        g_services = new OdStaticRxObject<ArcusServices>();
        odInitialize(g_services);
        g_version = utf8(g_services->versionString());
        g_initialized = true;
        return 0;
    } catch (const OdError &e) {
        setError(error, 1, "ODA initialization failed: " + describe(e));
    } catch (...) {
        setError(error, 1, "ODA initialization failed (unknown error).");
    }
    return 1;
}

extern "C" void arcus_dwg_terminate(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_initialized) return;
    try { odUninitialize(); } catch (...) {}
    delete g_services;
    g_services = nullptr;
    g_initialized = false;
}

extern "C" const char *arcus_dwg_sdk_version(void) {
    return g_initialized ? g_version.c_str() : nullptr;
}

extern "C" ArcusDWGDatabase *arcus_dwg_open(const char *utf8Path, ArcusDWGError *error) {
    if (!g_initialized) { setError(error, 1, "The ODA SDK is not initialized."); return nullptr; }
    if (!utf8Path) { setError(error, 1, "No file path."); return nullptr; }
    auto *h = new ArcusDWGDatabase();
    std::memset(h->version, 0, sizeof(h->version));
    // Version code from the file header (first six bytes, e.g. "AC1032").
    if (FILE *f = std::fopen(utf8Path, "rb")) {
        size_t n = std::fread(h->version, 1, 6, f);
        std::fclose(f);
        if (n != 6) h->version[0] = 0;
    }
    try {
        // Read-only, no code page conversion prompts, full load, allow other readers.
        h->db = g_services->readFile(fromUTF8(utf8Path), false, false, Oda::kShareDenyNo);
        if (h->db.isNull()) { setError(error, 1, "The SDK returned no database."); delete h; return nullptr; }
        return h;
    } catch (const OdError &e) {
        setError(error, 1, describe(e));
    } catch (...) {
        setError(error, 1, "Unknown error while reading the DWG file.");
    }
    delete h;
    return nullptr;
}

extern "C" const char *arcus_dwg_file_version(ArcusDWGDatabase *db) {
    return (db && db->version[0]) ? db->version : nullptr;
}

extern "C" int arcus_dwg_write_dxf(ArcusDWGDatabase *db, const char *utf8OutPath, ArcusDWGError *error) {
    if (!db || db->db.isNull() || !utf8OutPath) { setError(error, 1, "Invalid arguments."); return 1; }
    try {
        // Make sure every dimension has its graphics block ("*D…") so the DXF carries the dimension geometry.
        // This only changes the in-memory copy; the source DWG is never written.
        OdDbBlockTablePtr bt = db->db->getBlockTableId().safeOpenObject();
        for (OdDbSymbolTableIteratorPtr it = bt->newIterator(); !it->done(); it->step()) {
            OdDbBlockTableRecordPtr btr = it->getRecordId().safeOpenObject();
            for (OdDbObjectIteratorPtr ei = btr->newIterator(); !ei->done(); ei->step()) {
                OdDbEntityPtr ent = ei->objectId().openObject();
                if (ent.isNull() || !ent->isKindOf(OdDbDimension::desc())) continue;
                OdDbDimensionPtr dim = ent;
                if (dim->dimBlockId().isNull()) {
                    try {
                        dim->upgradeOpen();
                        dim->recomputeDimensionBlock(true);
                    } catch (...) {
                        // Leave it: Arcus falls back to the measurement text.
                    }
                }
            }
        }
        OdStreamBufPtr out = g_services->createFile(fromUTF8(utf8OutPath), Oda::kFileWrite, Oda::kShareDenyNo, Oda::kCreateAlways);
        // DXF 2010 (AC1024): UTF-8 text, all entity types Arcus reads, understood by every current CAD reader.
        db->db->writeFile(out, OdDb::kDxf, OdDb::vAC24, false, 16);
        return 0;
    } catch (const OdError &e) {
        setError(error, 1, describe(e));
    } catch (...) {
        setError(error, 1, "Unknown error while translating the DWG file.");
    }
    return 1;
}

extern "C" int arcus_dwg_enumerate_objects(ArcusDWGDatabase *db, ArcusDWGObjectCallback callback, ArcusDWGCancelCallback isCancelled,
                                             void *context, ArcusDWGError *error) {
    if (!db || db->db.isNull() || !callback) { setError(error, 1, "Invalid arguments."); return 1; }
    try {
        OdDbBlockTablePtr bt = db->db->getBlockTableId().safeOpenObject();
        unsigned long counter = 0;
        for (OdDbSymbolTableIteratorPtr it = bt->newIterator(); !it->done(); it->step()) {
            OdDbBlockTableRecordPtr btr = it->getRecordId().safeOpenObject();
            for (OdDbObjectIteratorPtr ei = btr->newIterator(); !ei->done(); ei->step()) {
                if ((++counter & 0x3FF) == 0 && isCancelled && isCancelled(context)) return 2;
                OdDbEntityPtr ent = ei->objectId().openObject();
                if (ent.isNull()) continue;
                std::string dxf = utf8(ent->isA()->dxfName());
                std::string type = dxf;
                bool isProxy = ent->isKindOf(OdDbProxyEntity::desc());
                if (isProxy) {
                    OdDbProxyEntityPtr px = ent;
                    std::string original = utf8(px->originalClassName());
                    if (!original.empty()) type = original;
                } else if (nativeTypes().count(dxf)) {
                    continue;
                }
                std::string handle = utf8(ent->handle().ascii());
                ArcusDWGObjectInfo info;
                std::memset(&info, 0, sizeof(info));
                info.handle = handle.c_str();
                info.typeName = type.c_str();
                OdGeExtents3d ext;
                if (ent->getGeomExtents(ext) == eOk && ext.isValidExtents()) {
                    info.hasExtents = 1;
                    info.minX = ext.minPoint().x; info.minY = ext.minPoint().y;
                    info.maxX = ext.maxPoint().x; info.maxY = ext.maxPoint().y;
                }
                callback(&info, context);
            }
        }
        return 0;
    } catch (const OdError &e) {
        setError(error, 1, describe(e));
    } catch (...) {
        setError(error, 1, "Unknown error while reading DWG objects.");
    }
    return 1;
}

extern "C" void arcus_dwg_close(ArcusDWGDatabase *db) {
    if (!db) return;
    try { db->db.release(); } catch (...) {}
    delete db;
}
