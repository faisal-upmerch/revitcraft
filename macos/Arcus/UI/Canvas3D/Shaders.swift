import Foundation

/// Metal shading language source, compiled once per device and backend (see `ViewportPipelines`).
/// Struct layouts must match `GPUScene.swift` (`ViewportUniforms`, `PostUniforms`, `PackedVertex`, `OverlayVertex`);
/// `layout_probe` lets tests verify them.
///
/// Binding model (identical for the classic encoder and Metal 4 argument tables): vertex and fragment stages share
/// buffer indices — 0 vertices / post uniforms, 1 uniforms, 2 element states, 3 edges — and fragment textures
/// 0 shadow map / color, 1 depth, 2 ambient occlusion. No `setBytes`: every constant lives in a frame arena buffer.
nonisolated enum ViewportShaders {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct Vertex {
    packed_float3 position;   // relative to scene origin
    uint normal;              // snorm8 xyz, w byte = surface finish (bits 0-3 roughness, bit 4 metallic)
    uint element;             // element index
    uchar4 color;             // sRGB rgba8
};

struct Uniforms {
    float4x4 viewProj;
    float4x4 pick;            // identity, or the pick-region zoom applied after projection
    float4 eye;               // xyz eye (relative), w = 1 perspective
    float4 viewDir;           // xyz forward
    float4 lightDir;          // xyz direction toward the key light (the sun when shadows or Realistic are on)
    float4 clipPlanes[6];     // keep where dot(n, p) + d >= 0
    float4 selectionColor;    // linear
    float4 preselectColor;    // linear
    float4 edgeColor;         // linear rgb, a = mix toward material tint (0 = flat color)
    float4 capColor;          // linear
    float4 faceColor;         // linear, hidden-line face color
    float2 viewport;          // pixels (unzoomed)
    float edgeWidth;          // pixels
    float faceAlpha;          // transparent style alpha
    uint style;               // 0 wireframe, 1 hidden line, 2 shaded, 3 consistent colors, 4 transparent, 5 realistic
    uint clipEnabled;
    uint flags;               // bit0 increase contrast, bit1 cast shadows, bit2 sky background
    float edgePull;           // relative pull toward the eye for edges (perspective) / absolute (ortho, meters)
    float4x4 shadowMatrix;    // relative world -> shadow clip (xy ndc, z 0..1, near = 0)
    float4 camRight;          // xyz camera right (scaled by tan(fovX/2) in perspective)
    float4 camUp;             // xyz camera up (scaled by tan(fovY/2) in perspective)
    float4 sunColor;          // linear radiance of the sun (Realistic)
    float4 skyZenith;         // linear
    float4 skyHorizon;        // linear
    float4 groundColor;       // linear
    float4 backgroundTop;     // linear
    float4 backgroundBottom;  // linear
    float4 shadowParams;      // x shadow texel (uv), y normal offset (m), z depth bias (0..1 units), w PCF radius (texels)
    float4 lightParams;       // x exposure, y shadow strength, z ambient scale, w unused
    float4 selectionFace;     // linear: flat tint over selected faces (I1)
};

struct PostUniforms {
    float4 proj;              // x tan(fovX/2) or half width, y tan(fovY/2) or half height, z near (persp) / far (ortho), w far-near (ortho)
    float4 sizes;             // xy depth texture size, zw ambient occlusion texture size
    float4 ao;                // x radius (m), y intensity, z bias (relative to depth), w max radius (px)
    float4 silhouette;        // x half width (depth texels), y relative depth step, z absolute step (m), w strength
    float4 silhouetteColor;   // linear
    uint flags;               // bit0 ambient occlusion, bit1 silhouettes, bit2 perspective
    uint pad0;
    uint pad1;
    uint pad2;
};

struct FaceOut {
    float4 position [[position]];
    float clip [[clip_distance]] [6];
    float3 world;
    float3 normal;
    float4 color;
    uint element [[flat]];
    uint state [[flat]];
    uint finish [[flat]];
};

// Fragment-side view of FaceOut (clip distances are consumed by the rasterizer).
struct FaceIn {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float4 color;
    uint element [[flat]];
    uint state [[flat]];
    uint finish [[flat]];
};

static inline float3 srgbToLinear(float3 c) {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

static inline void applyClip(thread FaceOut &o, constant Uniforms &u, float3 p) {
    for (int i = 0; i < 6; i++) {
        o.clip[i] = u.clipEnabled != 0 ? dot(u.clipPlanes[i].xyz, p) + u.clipPlanes[i].w : 1.0;
    }
}

vertex FaceOut face_vertex(uint vid [[vertex_id]],
                           device const Vertex *verts [[buffer(0)]],
                           constant Uniforms &u [[buffer(1)]],
                           device const uchar *states [[buffer(2)]]) {
    Vertex v = verts[vid];
    FaceOut o;
    float3 p = float3(v.position);
    o.position = u.pick * (u.viewProj * float4(p, 1.0));
    o.world = p;
    o.normal = unpack_snorm4x8_to_float(v.normal).xyz;
    float4 c = float4(v.color) / 255.0;
    o.color = float4(srgbToLinear(c.rgb), c.a);
    o.element = v.element;
    o.state = states[v.element];
    o.finish = v.normal >> 24;
    applyClip(o, u, p);
    return o;
}

// MARK: Lighting helpers

constexpr sampler shadowSampler(coord::normalized, filter::linear, address::clamp_to_edge, compare_func::less_equal);

/// 1 = lit, 0 = in shadow. 3×3 bilinear PCF (soft edges); outside the map counts as lit.
static float shadowFactor(float3 world, float3 n, float ndl, constant Uniforms &u, depth2d<float> shadowMap) {
    float3 p = world + n * u.shadowParams.y * (1.5 - ndl);
    float4 sp = u.shadowMatrix * float4(p, 1.0);
    float3 s = sp.xyz / sp.w;
    float2 uv = float2(s.x * 0.5 + 0.5, 0.5 - s.y * 0.5);
    if (any(uv < 0.0) || any(uv > 1.0) || s.z >= 1.0) return 1.0;
    float ref = s.z - u.shadowParams.z;
    float t = u.shadowParams.x * u.shadowParams.w;
    float sum = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            sum += shadowMap.sample_compare(shadowSampler, uv + float2(x, y) * t, ref);
        }
    }
    return sum / 9.0;
}

static float3 skyColor(float3 d, constant Uniforms &u) {
    float e = d.z;
    if (e >= 0.0) return mix(u.skyHorizon.rgb, u.skyZenith.rgb, pow(saturate(e), 0.45));
    // Below the horizon: a soft haze fading into the ground tone.
    return mix(u.skyHorizon.rgb * 0.92, u.groundColor.rgb, pow(saturate(-e * 2.0), 0.7));
}

static float3 acesFilm(float3 x) {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

/// Simple physically based shading: GGX specular + Lambert diffuse under the sun, hemispherical sky irradiance and a
/// sky-gradient environment reflection; ACES filmic tone mapping.
static float3 shadeRealistic(float3 albedo, float3 n, float3 V, float3 L, float sh, uint finish, constant Uniforms &u) {
    float rough = max(0.06, float(finish & 15u) / 15.0);
    float metal = (finish & 16u) != 0u ? 1.0 : 0.0;
    float a = rough * rough;
    float a2 = a * a;
    float3 H = normalize(L + V);
    float NdotL = saturate(dot(n, L));
    float NdotV = max(dot(n, V), 1e-3);
    float NdotH = saturate(dot(n, H));
    float VdotH = saturate(dot(V, H));
    float3 F0 = mix(float3(0.04), albedo, metal);
    float3 F = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
    float dd = NdotH * NdotH * (a2 - 1.0) + 1.0;
    float D = a2 / (M_PI_F * dd * dd);
    float k = (rough + 1.0) * (rough + 1.0) / 8.0;
    float G = (NdotV / (NdotV * (1.0 - k) + k)) * (NdotL / (NdotL * (1.0 - k) + k));
    float3 spec = D * G * F / (4.0 * NdotV * max(NdotL, 1e-3));
    float3 kd = (1.0 - F) * (1.0 - metal);
    float3 direct = (kd * albedo / M_PI_F + spec) * u.sunColor.rgb * NdotL * sh;
    float3 irradiance = mix(u.groundColor.rgb * 0.7, (u.skyZenith.rgb + u.skyHorizon.rgb) * 0.5, n.z * 0.5 + 0.5) * u.lightParams.z;
    float3 R = reflect(-V, n);
    float3 env = mix(skyColor(R, u), irradiance, rough);
    float3 Fe = F0 + (max(float3(1.0 - rough), F0) - F0) * pow(1.0 - NdotV, 5.0);
    float3 ambient = kd * albedo * irradiance + env * Fe * (1.0 - 0.6 * rough);
    return acesFilm((direct + ambient) * u.lightParams.x);
}

fragment float4 face_fragment(FaceIn in [[stage_in]], constant Uniforms &u [[buffer(1)]],
                              depth2d<float> shadowMap [[texture(0)]]) {
    float3 toEye = u.eye.w > 0.5 ? normalize(u.eye.xyz - in.world) : -u.viewDir.xyz;
    // Geometric normal, oriented toward the viewer.
    float3 ng = cross(dfdx(in.world), dfdy(in.world));
    float lng = length(ng);
    ng = lng > 1e-12 ? ng / lng : toEye;
    if (dot(ng, toEye) < 0) ng = -ng;
    float3 n = in.normal;
    float ln = length(n);
    n = ln > 1e-4 ? n / ln : ng;
    bool back = dot(n, ng) < 0.0;
    if (back) n = -n;

    float3 L = normalize(u.lightDir.xyz);
    float ndl = dot(n, L);
    bool cap = u.clipEnabled != 0 && back;
    float sh = 1.0;
    if ((u.flags & 2u) != 0u && !cap) {
        sh = ndl > 0.0 ? shadowFactor(in.world, n, ndl, u, shadowMap) : 0.0;
    }
    // Direct-light visibility for the unlit styles (shadowed or facing away from the sun).
    float lightVis = mix(1.0, sh * step(0.0, ndl), u.lightParams.y);

    float4 base = in.color;
    float4 result;
    if (cap) {
        // Looking into a solid through the section box: flat cut color.
        result = float4(u.capColor.rgb, 1.0);
    } else if (u.style == 1) {
        result = float4(u.faceColor.rgb, base.a < 0.99 ? 0.35 : 1.0);
        if ((u.flags & 2u) != 0u) result.rgb *= mix(0.72, 1.0, lightVis);
    } else if (u.style == 3) {
        result = base;
        if ((u.flags & 2u) != 0u) result.rgb *= mix(0.6, 1.0, lightVis);
    } else if (u.style == 5) {
        result = float4(shadeRealistic(base.rgb, n, toEye, L, mix(1.0, sh, u.lightParams.y), in.finish, u), base.a);
    } else {
        float diffuse = max(ndl, 0.0) * mix(1.0, sh, u.lightParams.y);
        float hemi = n.z * 0.5 + 0.5;
        float3 sky = float3(1.0, 1.0, 1.02);
        float3 ground = float3(0.62, 0.60, 0.58);
        float3 ambient = mix(ground, sky, hemi);
        // Soft camera-facing fill keeps faces turned away from the key light legible.
        float fill = max(dot(n, toEye), 0.0);
        // With sun shadows the direct light carries more weight so shadows read clearly.
        float3 weights = (u.flags & 2u) != 0u ? float3(0.44, 0.56, 0.08) : float3(0.52, 0.40, 0.13);
        float3 lit = base.rgb * (ambient * weights.x + diffuse * weights.y + fill * weights.z);
        result = float4(lit, base.a);
        if (u.style == 4) result.a = min(base.a, u.faceAlpha);
    }
    // I1: as in RevitCraft, selected faces take a flat translucent blue in every visual style (125, 146, 202 over
    // white); pre-selection shows only on the edges.
    if (in.state & 1u) {
        result.rgb = mix(result.rgb, u.selectionFace.rgb, 0.8);
    }
    // Premultiplied alpha for blending.
    return float4(result.rgb * result.a, result.a);
}

// MARK: Shadow map (depth only, from the sun)

struct ShadowOut {
    float4 position [[position]];
    float clip [[clip_distance]] [6];
};

vertex ShadowOut shadow_vertex(uint vid [[vertex_id]],
                               device const Vertex *verts [[buffer(0)]],
                               constant Uniforms &u [[buffer(1)]]) {
    float3 p = float3(verts[vid].position);
    ShadowOut o;
    o.position = u.shadowMatrix * float4(p, 1.0);
    for (int i = 0; i < 6; i++) {
        o.clip[i] = u.clipEnabled != 0 ? dot(u.clipPlanes[i].xyz, p) + u.clipPlanes[i].w : 1.0;
    }
    return o;
}

// MARK: Edges (screen-space quads, one instance per edge)

struct EdgeOut {
    float4 position [[position]];
    float clip [[clip_distance]] [6];
    float4 color;
    uint element [[flat]];
};

struct EdgeIn {
    float4 position [[position]];
    float4 color;
    uint element [[flat]];
};

static inline float4 pullTowardEye(float3 p, constant Uniforms &u) {
    if (u.eye.w > 0.5) {
        p = p + (u.eye.xyz - p) * u.edgePull;
    } else {
        p = p - u.viewDir.xyz * u.edgePull;
    }
    return u.viewProj * float4(p, 1.0);
}

vertex EdgeOut edge_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                           device const Vertex *verts [[buffer(0)]],
                           constant Uniforms &u [[buffer(1)]],
                           device const uchar *states [[buffer(2)]],
                           device const uint *edges [[buffer(3)]]) {
    Vertex va = verts[edges[iid * 2]];
    Vertex vb = verts[edges[iid * 2 + 1]];
    float3 pa = float3(va.position), pb = float3(vb.position);
    float4 ca = pullTowardEye(pa, u);
    float4 cb = pullTowardEye(pb, u);
    // Clip the segment against the near plane (w > eps) so perspective lines never flip.
    const float eps = 1e-4;
    if (ca.w < eps && cb.w < eps) { ca = float4(0, 0, -2, 1); cb = ca; }
    else if (ca.w < eps) { float t = (eps - ca.w) / (cb.w - ca.w); ca = mix(ca, cb, t); pa = mix(pa, pb, t); }
    else if (cb.w < eps) { float t = (eps - cb.w) / (ca.w - cb.w); cb = mix(cb, ca, t); pb = mix(pb, pa, t); }

    bool atB = vid >= 2;
    float side = (vid & 1u) ? 1.0 : -1.0;
    float2 sa = ca.xy / ca.w * u.viewport * 0.5;
    float2 sb = cb.xy / cb.w * u.viewport * 0.5;
    float2 d = sb - sa;
    float len = length(d);
    float2 dir = len > 1e-5 ? d / len : float2(1, 0);
    float2 nrm = float2(-dir.y, dir.x);

    uint element = va.element;
    uint state = states[element];
    float width = u.edgeWidth * ((state & 1u) ? 3.0 : ((state & 2u) ? 1.6 : 1.0)); // I1: RevitCraft's thick selection edges
    // Extend slightly along the segment so joints close.
    float2 offset = nrm * side * width * 0.5 + dir * (atB ? 0.5 : -0.5) * width * 0.5;

    float4 c = atB ? cb : ca;
    float3 p = atB ? pb : pa;
    c.xy += offset / (u.viewport * 0.5) * c.w;

    EdgeOut o;
    o.position = u.pick * c;
    for (int i = 0; i < 6; i++) {
        o.clip[i] = u.clipEnabled != 0 ? dot(u.clipPlanes[i].xyz, p) + u.clipPlanes[i].w : 1.0;
    }
    o.element = element;
    float4 vc = float4(va.color) / 255.0;
    float3 tint = srgbToLinear(vc.rgb) * 0.42;
    float3 col = mix(u.edgeColor.rgb, tint, u.edgeColor.a);
    float alpha = 1.0;
    if (state & 1u) col = u.selectionColor.rgb * 0.85;
    else if (state & 2u) col = u.preselectColor.rgb;
    o.color = float4(col * alpha, alpha);
    return o;
}

fragment float4 edge_fragment(EdgeIn in [[stage_in]]) { return in.color; }

// MARK: Picking (element index + 1 and world position)

struct PickOut {
    uint id [[color(0)]];
    float4 position [[color(1)]];
};

fragment PickOut face_pick_fragment(FaceIn in [[stage_in]]) {
    PickOut o; o.id = in.element + 1; o.position = float4(in.world, 1.0); return o;
}

fragment PickOut edge_pick_fragment(EdgeIn in [[stage_in]]) {
    PickOut o; o.id = in.element + 1; o.position = float4(0, 0, 0, 0); return o;
}

// MARK: Background (canvas gradient, or sky for Realistic)

struct BackgroundOut { float4 position [[position]]; float2 ndc; };

vertex BackgroundOut background_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2) * 2.0 - 1.0;
    BackgroundOut o;
    o.position = float4(p, 0.0, 1.0);
    o.ndc = p;
    return o;
}

fragment float4 background_fragment(BackgroundOut in [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
    if ((u.flags & 4u) != 0u) {
        float3 c;
        if (u.eye.w > 0.5) {
            // Perspective: the sky seen along each pixel's ray, with a soft sun glow.
            float3 d = normalize(u.viewDir.xyz + u.camRight.xyz * in.ndc.x + u.camUp.xyz * in.ndc.y);
            c = skyColor(d, u);
            float s = saturate(dot(d, normalize(u.lightDir.xyz)));
            c += u.sunColor.rgb * (pow(s, 900.0) * 6.0 + pow(s, 12.0) * 0.06);
        } else {
            // Orthographic views have no horizon: a screen-space sky gradient.
            c = skyColor(float3(0, 0, mix(-0.04, 0.7, in.ndc.y * 0.5 + 0.5)), u);
        }
        return float4(acesFilm(c * u.lightParams.x), 1.0);
    }
    float t = smoothstep(0.0, 1.0, in.ndc.y * 0.5 + 0.5);
    return mix(u.backgroundBottom, u.backgroundTop, t);
}

// MARK: Overlay (section box outline, handles, pivot marker) — screen-space expanded, no depth test

struct OverlayVertex {
    float4 a;       // xyz position (relative)
    float4 b;       // xyz other endpoint (lines)
    float4 color;   // linear premultiplied
    float2 offset;  // lines: x = side; markers: pixel offset
    float width;    // pixels
    float mode;     // 0 line, 1 marker
};

struct OverlayOut { float4 position [[position]]; float4 color; };

vertex OverlayOut overlay_vertex(uint vid [[vertex_id]],
                                 device const OverlayVertex *verts [[buffer(0)]],
                                 constant Uniforms &u [[buffer(1)]]) {
    OverlayVertex v = verts[vid];
    float4 ca = u.viewProj * float4(v.a.xyz, 1.0);
    OverlayOut o;
    o.color = v.color;
    if (ca.w < 1e-4) { o.position = float4(0, 0, -2, 1); return o; }
    if (v.mode < 0.5) {
        float4 cb = u.viewProj * float4(v.b.xyz, 1.0);
        if (cb.w < 1e-4) { float t = (1e-4 - cb.w) / (ca.w - cb.w); cb = mix(cb, ca, t); }
        float2 sa = ca.xy / ca.w * u.viewport * 0.5;
        float2 sb = cb.xy / cb.w * u.viewport * 0.5;
        float2 d = sb - sa; float len = length(d);
        float2 dir = len > 1e-5 ? d / len : float2(1, 0);
        float2 nrm = float2(-dir.y, dir.x);
        ca.xy += nrm * v.offset.x * v.width * 0.5 / (u.viewport * 0.5) * ca.w;
    } else {
        ca.xy += v.offset / (u.viewport * 0.5) * ca.w;
    }
    ca.z = ca.w; // always in front (reversed-Z: 1 = near)
    o.position = ca;
    return o;
}

fragment float4 overlay_fragment(OverlayOut in [[stage_in]]) { return in.color; }

// MARK: Post processing (ambient occlusion, silhouettes, upscaled composite)

struct FullscreenOut { float4 position [[position]]; float2 uv; };

vertex FullscreenOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FullscreenOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

static inline float linearDepth(float z, constant PostUniforms &p) {
    if ((p.flags & 4u) != 0u) return p.proj.z / max(z + p.proj.w, 1e-7); // W2-CAM: proj.w > 0 with a far clip
    return p.proj.z - z * p.proj.w;
}

static inline float3 viewPosition(float2 uv, float d, constant PostUniforms &p) {
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    if ((p.flags & 4u) != 0u) return float3(ndc * p.proj.xy * d, -d);
    return float3(ndc * p.proj.xy, -d);
}

static inline float3 viewPositionAt(int2 c, depth2d<float> depth, constant PostUniforms &p, thread bool &valid) {
    int2 size = int2(p.sizes.xy);
    c = clamp(c, int2(0), size - 1);
    float z = depth.read(uint2(c));
    valid = z > 0.0;
    return viewPosition((float2(c) + 0.5) / p.sizes.xy, linearDepth(z, p), p);
}

/// Scalable ambient obscurance (Alchemy-style) on the resolved depth buffer; normals reconstructed from depth.
fragment float ao_fragment(FullscreenOut in [[stage_in]], constant PostUniforms &p [[buffer(0)]],
                           depth2d<float> depth [[texture(1)]]) {
    int2 size = int2(p.sizes.xy);
    int2 c = clamp(int2(in.uv * p.sizes.xy), int2(0), size - 1);
    bool ok;
    float3 P = viewPositionAt(c, depth, p, ok);
    if (!ok) return 1.0;
    bool v0, v1, v2, v3;
    float3 px1 = viewPositionAt(c + int2(1, 0), depth, p, v0);
    float3 px0 = viewPositionAt(c - int2(1, 0), depth, p, v1);
    float3 py1 = viewPositionAt(c + int2(0, 1), depth, p, v2);
    float3 py0 = viewPositionAt(c - int2(0, 1), depth, p, v3);
    float3 dx = (abs(px1.z - P.z) < abs(P.z - px0.z)) ? px1 - P : P - px0;
    float3 dy = (abs(py1.z - P.z) < abs(P.z - py0.z)) ? py1 - P : P - py0;
    float3 N = normalize(cross(dx, dy));
    if (dot(N, -P) < 0.0) N = -N;
    float d = -P.z;
    float pxPerMeter = (p.flags & 4u) != 0u ? p.sizes.y * 0.5 / (p.proj.y * d) : p.sizes.y * 0.5 / p.proj.y;
    float radius = p.ao.x;
    float rPx = clamp(radius * pxPerMeter, 2.0, p.ao.w);
    // Interleaved gradient noise rotates the sampling spiral per pixel; the composite blur removes the pattern.
    float noise = fract(52.9829189 * fract(dot(in.position.xy, float2(0.06711056, 0.00583715))));
    const int count = 12;
    float r2 = radius * radius;
    float sum = 0.0;
    for (int i = 0; i < count; i++) {
        float t = (float(i) + 0.5) / float(count);
        float angle = (t * 7.0 + noise) * 2.0 * M_PI_F;
        float2 off = float2(cos(angle), sin(angle)) * max(rPx * t, 1.0);
        bool sv;
        float3 Q = viewPositionAt(c + int2(round(off)), depth, p, sv);
        if (!sv) continue;
        float3 v = Q - P;
        float vv = dot(v, v);
        if (vv < 1e-6) continue;
        // Cosine of the sample direction above the tangent plane (minus an angle bias), faded out beyond the radius.
        float cosine = dot(v, N) * rsqrt(vv);
        float f = saturate(1.0 - vv / r2);
        sum += f * max(cosine - p.ao.z, 0.0);
    }
    float ao = saturate(1.0 - sum * p.ao.y * 2.5 / float(count));
    return ao * ao;
}

fragment float4 composite_fragment(FullscreenOut in [[stage_in]], constant PostUniforms &p [[buffer(0)]],
                                   texture2d<float> color [[texture(0)]],
                                   depth2d<float> depth [[texture(1)]],
                                   texture2d<float> occlusion [[texture(2)]]) {
    constexpr sampler linearSampler(coord::normalized, filter::linear, address::clamp_to_edge);
    float4 c = color.sample(linearSampler, in.uv);
    int2 size = int2(p.sizes.xy);
    int2 dc = clamp(int2(in.uv * p.sizes.xy), int2(0), size - 1);
    float z = depth.read(uint2(dc));
    if (z <= 0.0) return float4(c.rgb, 1.0);
    float d = linearDepth(z, p);
    if ((p.flags & 1u) != 0u) {
        // Depth-aware 3×3 blur of the half-resolution occlusion.
        float2 aoSize = p.sizes.zw;
        float2 ac = in.uv * aoSize - 0.5;
        int2 base = int2(round(ac));
        float sum = 0.0, weight = 0.0;
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                int2 t = clamp(base + int2(i, j), int2(0), int2(aoSize) - 1);
                int2 tc = clamp(int2((float2(t) + 0.5) / aoSize * p.sizes.xy), int2(0), size - 1);
                float zt = depth.read(uint2(tc));
                float dt = zt > 0.0 ? linearDepth(zt, p) : 1e9;
                float w = 1.0 / (1e-3 + abs(dt - d) / max(d, 1e-3) * 40.0);
                sum += occlusion.read(uint2(t)).r * w;
                weight += w;
            }
        }
        float ao = weight > 0.0 ? sum / weight : 1.0;
        c.rgb *= ao;
    }
    if ((p.flags & 2u) != 0u) {
        // Silhouettes: along four directions, the pixel sits on the near side of a depth step (the planar prediction
        // from its two neighbors lies clearly behind it) or next to the background. Sloped planes predict exactly.
        float w = p.silhouette.x;
        float2 dirs[4] = { float2(w, 0), float2(0, w), float2(w, w) * 0.7071, float2(w, -w) * 0.7071 };
        float threshold = max(p.silhouette.y * d, p.silhouette.z);
        float edge = 0.0;
        for (int k = 0; k < 4; k++) {
            int2 ca = clamp(int2(float2(dc) + dirs[k] + 0.5), int2(0), size - 1);
            int2 cb = clamp(int2(float2(dc) - dirs[k] + 0.5), int2(0), size - 1);
            float za = depth.read(uint2(ca)), zb = depth.read(uint2(cb));
            if (za <= 0.0 || zb <= 0.0) { edge = 1.0; break; }
            float step = 0.5 * (linearDepth(za, p) + linearDepth(zb, p)) - d;
            edge = max(edge, smoothstep(threshold, threshold * 2.0, step));
        }
        c.rgb = mix(c.rgb, p.silhouetteColor.rgb, edge * p.silhouette.w);
    }
    return float4(c.rgb, 1.0);
}

// MARK: Test support: struct sizes as the shader compiler sees them.

kernel void layout_probe(device uint *out [[buffer(0)]], uint tid [[thread_position_in_grid]]) {
    if (tid == 0) {
        out[0] = sizeof(Uniforms);
        out[1] = sizeof(PostUniforms);
        out[2] = sizeof(Vertex);
        out[3] = sizeof(OverlayVertex);
    }
}
"""#
}
