//! Offscreen wgpu renderer for 3D views (Metal on macOS, DX12/Vulkan elsewhere): visual
//! styles, section box clipping and sun shadows. Each view renders into its own texture,
//! which egui displays as an image.

use eframe::egui;
use eframe::egui_wgpu::{self, wgpu};
use glam::{DVec3, Mat4, Vec3, Vec4};
use rc_core::mesh::MeshSet;
use rc_core::model::{Id, Project, VisualStyle};
use std::collections::{HashMap, HashSet};
use wgpu::util::DeviceExt;

const SHADER: &str = r#"
struct Uniforms {
    view_proj: mat4x4<f32>,
    light_vp: mat4x4<f32>,
    eye: vec4<f32>,
    light: vec4<f32>,
    // x: line depth bias, y: ortho flag, z: style (0 wire,1 hidden,2 shaded,3 consistent,4 realistic), w: shadows
    params: vec4<f32>,
    clip_min: vec4<f32>,
    clip_max: vec4<f32>,
};
@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var shadow_map: texture_depth_2d;
@group(0) @binding(2) var shadow_sampler: sampler_comparison;

struct VIn {
    @location(0) pos: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) color: vec4<f32>,
    @location(3) extra: vec4<f32>,
};
struct VOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) normal: vec3<f32>,
    @location(1) color: vec4<f32>,
    @location(2) world: vec3<f32>,
    @location(3) extra: vec4<f32>,
};

fn to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(2.2));
}

fn clipped(w: vec3<f32>) -> bool {
    if (u.clip_min.w < 0.5) { return false; }
    return any(w < u.clip_min.xyz) || any(w > u.clip_max.xyz);
}

@vertex
fn vs_main(v: VIn) -> VOut {
    var o: VOut;
    o.clip = u.view_proj * vec4<f32>(v.pos, 1.0);
    o.normal = v.normal;
    o.color = v.color;
    o.world = v.pos;
    o.extra = v.extra;
    return o;
}

fn shadow_factor(world: vec3<f32>, n: vec3<f32>) -> f32 {
    if (u.params.w < 0.5) { return 1.0; }
    let lp = u.light_vp * vec4<f32>(world + n * 0.02, 1.0);
    let ndc = lp.xyz / lp.w;
    let uv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || ndc.z > 1.0) { return 1.0; }
    var lit = 0.0;
    let texel = 1.0 / 2048.0;
    for (var dx = -1; dx <= 1; dx = dx + 1) {
        for (var dy = -1; dy <= 1; dy = dy + 1) {
            lit = lit + textureSampleCompareLevel(shadow_map, shadow_sampler, uv + vec2<f32>(f32(dx), f32(dy)) * texel, ndc.z - 0.0015);
        }
    }
    return lit / 9.0;
}

@fragment
fn fs_main(i: VOut) -> @location(0) vec4<f32> {
    if (clipped(i.world)) { discard; }
    let style = u.params.z;
    if (style < 1.5 && style > 0.5) {
        // Hidden line: plain white surfaces.
        return vec4<f32>(1.0, 1.0, 1.0, 1.0);
    }
    var n = normalize(i.normal);
    var to_eye = u.eye.xyz - i.world;
    if (u.params.y > 0.5) { to_eye = -u.eye.xyz; }
    if (dot(n, to_eye) < 0.0) { n = -n; }
    let base = to_linear(i.color.rgb);
    let l = normalize(u.light.xyz);
    let sh = shadow_factor(i.world, n);
    if (style > 2.5 && style < 3.5) {
        // Consistent colours: unlit, shadows only darken.
        let k = 0.55 + 0.45 * sh;
        return vec4<f32>(pow(base * k, vec3<f32>(1.0 / 2.2)), i.color.a);
    }
    let key = max(dot(n, l), 0.0) * sh;
    let fill = max(dot(n, normalize(vec3<f32>(-0.5, -0.7, 0.4))), 0.0);
    let sky = 0.5 + 0.5 * n.z;
    var c = base * (0.28 + 0.6 * key + 0.12 * fill + 0.16 * sky);
    if (style > 3.5) {
        // Realistic: specular highlight by material shininess (extra.x).
        let v = normalize(to_eye);
        let h = normalize(l + v);
        let spec = pow(max(dot(n, h), 0.0), 8.0 + 120.0 * i.extra.x) * (0.08 + 0.6 * i.extra.x) * sh;
        c = c + vec3<f32>(spec);
        // Gentle sky reflection on glass-like (transparent) materials.
        if (i.color.a < 0.99) { c = c + vec3<f32>(0.10, 0.13, 0.18) * (1.0 - abs(dot(n, v))); }
    }
    return vec4<f32>(pow(c, vec3<f32>(1.0 / 2.2)), i.color.a);
}

@vertex
fn vs_line(v: VIn) -> VOut {
    var o: VOut;
    var c = u.view_proj * vec4<f32>(v.pos, 1.0);
    c.z = c.z - u.params.x * c.w;
    o.clip = c;
    o.normal = v.normal;
    o.color = v.color;
    o.world = v.pos;
    o.extra = v.extra;
    return o;
}

@fragment
fn fs_line(i: VOut) -> @location(0) vec4<f32> {
    if (clipped(i.world)) { discard; }
    return i.color;
}

@vertex
fn vs_shadow(v: VIn) -> @builtin(position) vec4<f32> {
    return u.light_vp * vec4<f32>(v.pos, 1.0);
}
"#;

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct Vertex {
    pos: [f32; 3],
    normal: [f32; 3],
    color: [f32; 4],
    extra: [f32; 4],
}

#[repr(C)]
#[derive(Clone, Copy, bytemuck::Pod, bytemuck::Zeroable)]
struct Uniforms {
    view_proj: [[f32; 4]; 4],
    light_vp: [[f32; 4]; 4],
    eye: [f32; 4],
    light: [f32; 4],
    params: [f32; 4],
    clip_min: [f32; 4],
    clip_max: [f32; 4],
}

pub const COLOR_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;
const DEPTH_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Depth32Float;
const SAMPLES: u32 = 4;
const SHADOW_SIZE: u32 = 2048;

/// A camera in model millimetres.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Camera {
    pub eye: DVec3,
    pub target: DVec3,
    pub perspective: bool,
    /// Visible height in mm for orthographic cameras.
    pub ortho_height: f64,
}

impl Camera {
    pub fn up(&self) -> Vec3 {
        let dir = (self.target - self.eye).normalize_or(DVec3::Y).as_vec3();
        if dir.z.abs() > 0.999 { Vec3::Y } else { Vec3::Z }
    }

    pub fn view_matrix(&self) -> Mat4 {
        let s = 0.001;
        look_at_rh((self.eye * s).as_vec3(), (self.target * s).as_vec3(), self.up())
    }

    pub fn view_proj(&self, aspect: f32) -> Mat4 {
        let s = 0.001;
        let dist = ((self.target - self.eye).length() * s).max(0.1) as f32;
        let proj = if self.perspective {
            perspective_rh(45f32.to_radians(), aspect, (dist * 0.01).max(0.05), dist * 50.0 + 500.0)
        } else {
            let h = (self.ortho_height * s) as f32 / 2.0;
            let w = h * aspect;
            orthographic_rh(-w, w, -h, h, -(dist + ORTHO_DEPTH), dist + ORTHO_DEPTH)
        };
        proj * self.view_matrix()
    }

    /// World ray (origin, direction) through a point in normalised device coordinates.
    pub fn ray(&self, ndc_x: f64, ndc_y: f64, aspect: f32) -> (DVec3, DVec3) {
        let inv = self.view_proj(aspect).as_dmat4().inverse();
        let near = inv.project_point3(DVec3::new(ndc_x, ndc_y, 0.0)) * 1000.0;
        let far = inv.project_point3(DVec3::new(ndc_x, ndc_y, 0.9)) * 1000.0;
        (near, (far - near).normalize())
    }

    pub fn project(&self, p: DVec3, aspect: f32) -> DVec3 {
        self.view_proj(aspect).as_dmat4().project_point3(p * 0.001)
    }
}

const ORTHO_DEPTH: f32 = 300.0;

fn ortho_bias(cam: &Camera) -> f32 {
    let dist = ((cam.target - cam.eye).length() * 0.001) as f32;
    0.02 / (2.0 * (dist + ORTHO_DEPTH))
}

pub fn look_at_rh(eye: Vec3, center: Vec3, up: Vec3) -> Mat4 {
    let f = (center - eye).normalize();
    let s = f.cross(up).normalize();
    let u = s.cross(f);
    Mat4::from_cols(
        Vec4::new(s.x, u.x, -f.x, 0.0),
        Vec4::new(s.y, u.y, -f.y, 0.0),
        Vec4::new(s.z, u.z, -f.z, 0.0),
        Vec4::new(-s.dot(eye), -u.dot(eye), f.dot(eye), 1.0),
    )
}

fn perspective_rh(fov_y: f32, aspect: f32, near: f32, far: f32) -> Mat4 {
    let h = 1.0 / (fov_y / 2.0).tan();
    let w = h / aspect;
    let r = far / (near - far);
    Mat4::from_cols(Vec4::new(w, 0.0, 0.0, 0.0), Vec4::new(0.0, h, 0.0, 0.0), Vec4::new(0.0, 0.0, r, -1.0), Vec4::new(0.0, 0.0, r * near, 0.0))
}

fn orthographic_rh(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) -> Mat4 {
    let rw = 1.0 / (right - left);
    let rh = 1.0 / (top - bottom);
    let r = 1.0 / (near - far);
    Mat4::from_cols(
        Vec4::new(2.0 * rw, 0.0, 0.0, 0.0),
        Vec4::new(0.0, 2.0 * rh, 0.0, 0.0),
        Vec4::new(0.0, 0.0, r, 0.0),
        Vec4::new(-(left + right) * rw, -(top + bottom) * rh, r * near, 1.0),
    )
}

/// How a view is drawn.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct DrawSettings {
    pub style: VisualStyle,
    pub shadows: bool,
    /// Sun direction (towards the sun), world space.
    pub sun: DVec3,
    pub section_box: Option<(DVec3, DVec3)>,
    pub background: [f64; 3],
}

/// Element meshes kept on the CPU for picking, plus GPU buffers.
pub struct Scene {
    pub key: (u64, u64),
    pub meshes: Vec<(Id, MeshSet)>,
    pub bounds: Option<(DVec3, DVec3)>,
    opaque: Option<(wgpu::Buffer, u32)>,
    transparent: Option<(wgpu::Buffer, u32)>,
    edges: Option<(wgpu::Buffer, u32)>,
    /// Selection highlight overlay (rebuilt only when the selection changes).
    pub selection_key: u64,
    sel: Option<(wgpu::Buffer, u32)>,
    sel_edges: Option<(wgpu::Buffer, u32)>,
}

struct Target {
    size: [u32; 2],
    msaa: wgpu::Texture,
    resolve: wgpu::Texture,
    depth: wgpu::Texture,
    texture_id: Option<egui::TextureId>,
    uniforms: wgpu::Buffer,
    bind_group: wgpu::BindGroup,
    shadow: wgpu::Texture,
}

pub struct Renderer {
    state: egui_wgpu::RenderState,
    layout: wgpu::BindGroupLayout,
    tri: wgpu::RenderPipeline,
    tri_blend: wgpu::RenderPipeline,
    lines: wgpu::RenderPipeline,
    lines_no_depth: wgpu::RenderPipeline,
    shadow_pipe: wgpu::RenderPipeline,
    sampler: wgpu::Sampler,
    dummy_shadow: wgpu::Texture,
    targets: HashMap<Id, Target>,
}

fn srgb_color(rgb: [u8; 3], a: f32) -> [f32; 4] {
    [rgb[0] as f32 / 255.0, rgb[1] as f32 / 255.0, rgb[2] as f32 / 255.0, a]
}

impl Renderer {
    pub fn new(state: &egui_wgpu::RenderState) -> Renderer {
        let device = &state.device;
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some("rc-shader"), source: wgpu::ShaderSource::Wgsl(SHADER.into()) });
        let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("rc-uniforms"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
                    ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture { sample_type: wgpu::TextureSampleType::Depth, view_dimension: wgpu::TextureViewDimension::D2, multisampled: false },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry { binding: 2, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Comparison), count: None },
            ],
        });
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: Some("rc-layout"), bind_group_layouts: &[Some(&layout)], immediate_size: 0 });
        let attributes = wgpu::vertex_attr_array![0 => Float32x3, 1 => Float32x3, 2 => Float32x4, 3 => Float32x4];
        let buffers = [Some(wgpu::VertexBufferLayout { array_stride: std::mem::size_of::<Vertex>() as u64, step_mode: wgpu::VertexStepMode::Vertex, attributes: &attributes })];
        let make = |vs: &str, fs: &str, topology: wgpu::PrimitiveTopology, blend: bool, depth_write: bool, depth_test: bool| {
            device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("rc-pipeline"),
                layout: Some(&pipeline_layout),
                vertex: wgpu::VertexState { module: &shader, entry_point: Some(vs), compilation_options: Default::default(), buffers: &buffers },
                primitive: wgpu::PrimitiveState { topology, cull_mode: None, ..Default::default() },
                depth_stencil: Some(wgpu::DepthStencilState {
                    format: DEPTH_FORMAT,
                    depth_write_enabled: Some(depth_write),
                    depth_compare: Some(if depth_test { wgpu::CompareFunction::LessEqual } else { wgpu::CompareFunction::Always }),
                    stencil: Default::default(),
                    bias: Default::default(),
                }),
                multisample: wgpu::MultisampleState { count: SAMPLES, mask: !0, alpha_to_coverage_enabled: false },
                fragment: Some(wgpu::FragmentState {
                    module: &shader,
                    entry_point: Some(fs),
                    compilation_options: Default::default(),
                    targets: &[Some(wgpu::ColorTargetState { format: COLOR_FORMAT, blend: blend.then_some(wgpu::BlendState::ALPHA_BLENDING), write_mask: wgpu::ColorWrites::ALL })],
                }),
                multiview_mask: None,
                cache: None,
            })
        };
        let tri = make("vs_main", "fs_main", wgpu::PrimitiveTopology::TriangleList, false, true, true);
        let tri_blend = make("vs_main", "fs_main", wgpu::PrimitiveTopology::TriangleList, true, false, true);
        let lines = make("vs_line", "fs_line", wgpu::PrimitiveTopology::LineList, false, true, true);
        let lines_no_depth = make("vs_line", "fs_line", wgpu::PrimitiveTopology::LineList, true, false, false);
        let shadow_pipe = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("rc-shadow"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState { module: &shader, entry_point: Some("vs_shadow"), compilation_options: Default::default(), buffers: &buffers },
            primitive: wgpu::PrimitiveState { topology: wgpu::PrimitiveTopology::TriangleList, cull_mode: None, ..Default::default() },
            depth_stencil: Some(wgpu::DepthStencilState {
                format: DEPTH_FORMAT,
                depth_write_enabled: Some(true),
                depth_compare: Some(wgpu::CompareFunction::LessEqual),
                stencil: Default::default(),
                bias: wgpu::DepthBiasState { constant: 2, slope_scale: 2.0, clamp: 0.0 },
            }),
            multisample: wgpu::MultisampleState::default(),
            fragment: None,
            multiview_mask: None,
            cache: None,
        });
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("rc-shadow-sampler"),
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            compare: Some(wgpu::CompareFunction::LessEqual),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            ..Default::default()
        });
        let dummy_shadow = shadow_texture(device, 1);
        Renderer { state: state.clone(), layout, tri, tri_blend, lines, lines_no_depth, shadow_pipe, sampler, dummy_shadow, targets: HashMap::new() }
    }

    /// Uploads element meshes. `color_of` may override an element's colour (selection, phases).
    pub fn upload(&self, p: &Project, meshes: Vec<(Id, MeshSet)>, selection: &HashSet<Id>, key: (u64, u64), halftone: &HashSet<Id>) -> Scene {
        let mut opaque: Vec<Vertex> = Vec::new();
        let mut transparent: Vec<Vertex> = Vec::new();
        let mut lines: Vec<Vertex> = Vec::new();
        let mut bounds: Option<(DVec3, DVec3)> = None;
        for (id, set) in &meshes {
            let selected = selection.contains(id);
            let half = halftone.contains(id);
            if let Some((mn, mx)) = set.bounds() {
                bounds = Some(match bounds {
                    Some((a, b)) => (a.min(mn), b.max(mx)),
                    None => (mn, mx),
                });
            }
            for (mat_name, mesh) in &set.by_material {
                let mat = p.material(mat_name);
                let mut rgb = mat.map(|m| m.color).unwrap_or([200, 200, 200]);
                if half {
                    rgb = [(rgb[0] as u16 / 2 + 110) as u8, (rgb[1] as u16 / 2 + 110) as u8, (rgb[2] as u16 / 2 + 110) as u8];
                }
                if selected {
                    rgb = [64, 140, 255];
                }
                let alpha = mat.map(|m| m.opacity as f32).unwrap_or(1.0);
                let shine = mat.map(|m| m.shininess as f32).unwrap_or(0.1);
                let color = srgb_color(rgb, alpha);
                let target = if alpha < 0.99 { &mut transparent } else { &mut opaque };
                for tri in mesh.indices.chunks(3) {
                    let a = mesh.positions[tri[0] as usize];
                    let b = mesh.positions[tri[1] as usize];
                    let c = mesh.positions[tri[2] as usize];
                    let n = (b - a).cross(c - a).normalize_or_zero().as_vec3().to_array();
                    for q in [a, b, c] {
                        target.push(Vertex { pos: (q * 0.001).as_vec3().to_array(), normal: n, color, extra: [shine, 0.0, 0.0, 0.0] });
                    }
                }
                let edge_color = if selected { srgb_color([20, 70, 200], 1.0) } else if alpha < 0.99 { srgb_color([90, 110, 130], 1.0) } else { srgb_color([35, 35, 35], 1.0) };
                for (a, b) in feature_edges(mesh) {
                    for q in [a, b] {
                        lines.push(Vertex { pos: (q * 0.001).as_vec3().to_array(), normal: [0.0, 0.0, 1.0], color: edge_color, extra: [0.0; 4] });
                    }
                }
            }
        }
        let device = &self.state.device;
        let buf = |verts: &[Vertex], label: &str| -> Option<(wgpu::Buffer, u32)> {
            (!verts.is_empty()).then(|| {
                (device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some(label), contents: bytemuck::cast_slice(verts), usage: wgpu::BufferUsages::VERTEX }), verts.len() as u32)
            })
        };
        Scene {
            key,
            meshes: Vec::new(),
            bounds,
            opaque: buf(&opaque, "rc-opaque"),
            transparent: buf(&transparent, "rc-transparent"),
            edges: buf(&lines, "rc-edges"),
            selection_key: 0,
            sel: None,
            sel_edges: None,
        }
        .with_meshes(meshes)
    }

    /// Rebuilds the blue selection overlay from the cached meshes.
    pub fn set_selection(&self, scene: &mut Scene, selection: &HashSet<Id>, key: u64) {
        if scene.selection_key == key {
            return;
        }
        scene.selection_key = key;
        let mut tris: Vec<Vertex> = Vec::new();
        let mut lines: Vec<Vertex> = Vec::new();
        let fill = srgb_color([64, 140, 255], 1.0);
        let edge = srgb_color([20, 70, 200], 1.0);
        for (id, set) in &scene.meshes {
            if !selection.contains(id) {
                continue;
            }
            for mesh in set.by_material.values() {
                for tri in mesh.indices.chunks(3) {
                    let (a, b, c) = (mesh.positions[tri[0] as usize], mesh.positions[tri[1] as usize], mesh.positions[tri[2] as usize]);
                    let n = (b - a).cross(c - a).normalize_or_zero().as_vec3().to_array();
                    for q in [a, b, c] {
                        tris.push(Vertex { pos: (q * 0.001).as_vec3().to_array(), normal: n, color: fill, extra: [0.3, 0.0, 0.0, 0.0] });
                    }
                }
                for (a, b) in feature_edges(mesh) {
                    for q in [a, b] {
                        lines.push(Vertex { pos: (q * 0.001).as_vec3().to_array(), normal: [0.0, 0.0, 1.0], color: edge, extra: [0.0; 4] });
                    }
                }
            }
        }
        let device = &self.state.device;
        let buf = |verts: &[Vertex]| -> Option<(wgpu::Buffer, u32)> {
            (!verts.is_empty()).then(|| (device.create_buffer_init(&wgpu::util::BufferInitDescriptor { label: Some("rc-sel"), contents: bytemuck::cast_slice(verts), usage: wgpu::BufferUsages::VERTEX }), verts.len() as u32))
        };
        scene.sel = buf(&tris);
        scene.sel_edges = buf(&lines);
    }

    fn make_target(&self, size: [u32; 2]) -> Target {
        let device = &self.state.device;
        let tex = |label: &str, format: wgpu::TextureFormat, samples: u32, usage: wgpu::TextureUsages| {
            device.create_texture(&wgpu::TextureDescriptor {
                label: Some(label),
                size: wgpu::Extent3d { width: size[0], height: size[1], depth_or_array_layers: 1 },
                mip_level_count: 1,
                sample_count: samples,
                dimension: wgpu::TextureDimension::D2,
                format,
                usage,
                view_formats: &[],
            })
        };
        let msaa = tex("rc-msaa", COLOR_FORMAT, SAMPLES, wgpu::TextureUsages::RENDER_ATTACHMENT);
        let resolve = tex("rc-resolve", COLOR_FORMAT, 1, wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_SRC);
        let depth = tex("rc-depth", DEPTH_FORMAT, SAMPLES, wgpu::TextureUsages::RENDER_ATTACHMENT);
        let uniforms = device.create_buffer(&wgpu::BufferDescriptor { label: Some("rc-uniforms"), size: std::mem::size_of::<Uniforms>() as u64, usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
        let shadow = shadow_texture(device, SHADOW_SIZE);
        let bind_group = self.bind_group(&uniforms, &shadow);
        Target { size, msaa, resolve, depth, texture_id: None, uniforms, bind_group, shadow }
    }

    fn bind_group(&self, uniforms: &wgpu::Buffer, shadow: &wgpu::Texture) -> wgpu::BindGroup {
        let view = shadow.create_view(&Default::default());
        self.state.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("rc-bind"),
            layout: &self.layout,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: uniforms.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&view) },
                wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::Sampler(&self.sampler) },
            ],
        })
    }

    fn draw(&self, target: &Target, scene: &Scene, cam: &Camera, set: &DrawSettings) {
        let aspect = target.size[0] as f32 / target.size[1].max(1) as f32;
        let light = set.sun.normalize_or(DVec3::new(0.4, -0.6, 0.9)).as_vec3();
        let style_code = match set.style {
            VisualStyle::Wireframe => 0.0,
            VisualStyle::HiddenLine => 1.0,
            VisualStyle::Shaded => 2.0,
            VisualStyle::ConsistentColors => 3.0,
            VisualStyle::Realistic => 4.0,
        };
        let shadows = set.shadows && !matches!(set.style, VisualStyle::Wireframe | VisualStyle::HiddenLine) && scene.bounds.is_some();
        // Light camera fitted around the scene.
        let light_vp = match scene.bounds {
            Some((mn, mx)) => {
                let c = ((mn + mx) / 2.0 * 0.001).as_vec3();
                let r = ((mx - mn).length() * 0.001 / 2.0) as f32 + 1.0;
                let eye = c + light * r * 2.0;
                let up = if light.z.abs() > 0.99 { Vec3::Y } else { Vec3::Z };
                orthographic_rh(-r, r, -r, r, 0.01, r * 4.0) * look_at_rh(eye, c, up)
            }
            None => Mat4::IDENTITY,
        };
        let eye = (cam.eye * 0.001).as_vec3();
        let mut u = Uniforms {
            view_proj: cam.view_proj(aspect).to_cols_array_2d(),
            light_vp: light_vp.to_cols_array_2d(),
            eye: [eye.x, eye.y, eye.z, 1.0],
            light: [light.x, light.y, light.z, 0.0],
            params: [if cam.perspective { 0.0004 } else { ortho_bias(cam) }, if cam.perspective { 0.0 } else { 1.0 }, style_code, if shadows { 1.0 } else { 0.0 }],
            clip_min: [0.0; 4],
            clip_max: [0.0; 4],
        };
        if let Some((mn, mx)) = set.section_box {
            let (a, b) = ((mn * 0.001).as_vec3(), (mx * 0.001).as_vec3());
            u.clip_min = [a.x, a.y, a.z, 1.0];
            u.clip_max = [b.x, b.y, b.z, 1.0];
        }
        if !cam.perspective {
            let dir = (cam.target - cam.eye).normalize().as_vec3();
            u.eye = [dir.x, dir.y, dir.z, 0.0];
        }
        let queue = &self.state.queue;
        queue.write_buffer(&target.uniforms, 0, bytemuck::bytes_of(&u));
        let mut enc = self.state.device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("rc-encoder") });
        if shadows {
            let sview = target.shadow.create_view(&Default::default());
            let mut pass = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("rc-shadow-pass"),
                color_attachments: &[],
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment { view: &sview, depth_ops: Some(wgpu::Operations { load: wgpu::LoadOp::Clear(1.0), store: wgpu::StoreOp::Store }), stencil_ops: None }),
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
            pass.set_pipeline(&self.shadow_pipe);
            pass.set_bind_group(0, &self.dummy_bind(&target.uniforms), &[]);
            if let Some((vb, n)) = &scene.opaque {
                pass.set_vertex_buffer(0, vb.slice(..));
                pass.draw(0..*n, 0..1);
            }
        }
        {
            let msaa_view = target.msaa.create_view(&Default::default());
            let resolve_view = target.resolve.create_view(&Default::default());
            let depth_view = target.depth.create_view(&Default::default());
            let bg = set.background;
            let mut pass = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("rc-pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &msaa_view,
                    depth_slice: None,
                    resolve_target: Some(&resolve_view),
                    ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color { r: bg[0], g: bg[1], b: bg[2], a: 1.0 }), store: wgpu::StoreOp::Store },
                })],
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                    view: &depth_view,
                    depth_ops: Some(wgpu::Operations { load: wgpu::LoadOp::Clear(1.0), store: wgpu::StoreOp::Discard }),
                    stencil_ops: None,
                }),
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
            pass.set_bind_group(0, &target.bind_group, &[]);
            let wire = set.style == VisualStyle::Wireframe;
            if !wire {
                if let Some((vb, n)) = &scene.opaque {
                    pass.set_pipeline(&self.tri);
                    pass.set_vertex_buffer(0, vb.slice(..));
                    pass.draw(0..*n, 0..1);
                }
            }
            if set.style != VisualStyle::Realistic {
                if let Some((vb, n)) = &scene.edges {
                    pass.set_pipeline(if wire { &self.lines_no_depth } else { &self.lines });
                    pass.set_vertex_buffer(0, vb.slice(..));
                    pass.draw(0..*n, 0..1);
                }
            }
            // Selection overlay (same geometry, drawn on top with LessEqual depth).
            if let Some((vb, n)) = &scene.sel {
                if !wire {
                    pass.set_pipeline(&self.tri);
                    pass.set_vertex_buffer(0, vb.slice(..));
                    pass.draw(0..*n, 0..1);
                }
            }
            if let Some((vb, n)) = &scene.sel_edges {
                pass.set_pipeline(if wire { &self.lines_no_depth } else { &self.lines });
                pass.set_vertex_buffer(0, vb.slice(..));
                pass.draw(0..*n, 0..1);
            }
            if !wire {
                if let Some((vb, n)) = &scene.transparent {
                    pass.set_pipeline(&self.tri_blend);
                    pass.set_vertex_buffer(0, vb.slice(..));
                    pass.draw(0..*n, 0..1);
                }
            }
        }
        queue.submit([enc.finish()]);
    }

    /// Bind group for the shadow pass (the shadow map itself must not be bound while written).
    fn dummy_bind(&self, uniforms: &wgpu::Buffer) -> wgpu::BindGroup {
        self.bind_group(uniforms, &self.dummy_shadow)
    }

    pub fn render_view(&mut self, view: Id, size: [u32; 2], scene: &Scene, cam: &Camera, set: &DrawSettings) -> egui::TextureId {
        let size = [size[0].clamp(8, 8192), size[1].clamp(8, 8192)];
        if self.targets.get(&view).is_none_or(|t| t.size != size) {
            if let Some(old) = self.targets.remove(&view) {
                if let Some(id) = old.texture_id {
                    self.state.renderer.write().free_texture(&id);
                }
            }
            let t = self.make_target(size);
            self.targets.insert(view, t);
        }
        let target = self.targets.get(&view).unwrap();
        self.draw(target, scene, cam, set);
        let resolve_view = target.resolve.create_view(&Default::default());
        let mut renderer = self.state.renderer.write();
        let id = match target.texture_id {
            Some(id) => {
                renderer.update_egui_texture_from_wgpu_texture(&self.state.device, &resolve_view, wgpu::FilterMode::Linear, id);
                id
            }
            None => renderer.register_native_texture(&self.state.device, &resolve_view, wgpu::FilterMode::Linear),
        };
        drop(renderer);
        self.targets.get_mut(&view).unwrap().texture_id = Some(id);
        id
    }

    /// Renders off-screen and reads the pixels back (PDF and image export).
    pub fn render_to_rgb(&self, scene: &Scene, cam: &Camera, set: &DrawSettings, width: u32, height: u32) -> rc_core::pdf::Image {
        let target = self.make_target([width, height]);
        self.draw(&target, scene, cam, set);
        let bytes_per_row = (width * 4).div_ceil(256) * 256;
        let device = &self.state.device;
        let buffer = device.create_buffer(&wgpu::BufferDescriptor { label: Some("rc-readback"), size: (bytes_per_row * height) as u64, usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ, mapped_at_creation: false });
        let mut enc = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("rc-copy") });
        enc.copy_texture_to_buffer(
            wgpu::TexelCopyTextureInfo { texture: &target.resolve, mip_level: 0, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
            wgpu::TexelCopyBufferInfo { buffer: &buffer, layout: wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(bytes_per_row), rows_per_image: Some(height) } },
            wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
        );
        self.state.queue.submit([enc.finish()]);
        let (tx, rx) = std::sync::mpsc::channel();
        buffer.map_async(wgpu::MapMode::Read, .., move |r| {
            let _ = tx.send(r);
        });
        let _ = device.poll(wgpu::PollType::wait_indefinitely());
        let mut rgb = Vec::with_capacity((width * height * 3) as usize);
        if let Ok(Ok(())) = rx.recv() {
            if let Ok(view) = buffer.get_mapped_range(..) {
                for row in 0..height {
                    let start = (row * bytes_per_row) as usize;
                    for px in view[start..start + (width * 4) as usize].chunks(4) {
                        rgb.extend_from_slice(&px[..3]);
                    }
                }
            }
            buffer.unmap();
        }
        if rgb.len() != (width * height * 3) as usize {
            rgb = vec![255; (width * height * 3) as usize];
        }
        rc_core::pdf::Image { width, height, rgb }
    }

    pub fn forget(&mut self, view: Id) {
        if let Some(t) = self.targets.remove(&view) {
            if let Some(id) = t.texture_id {
                self.state.renderer.write().free_texture(&id);
            }
        }
    }
}

impl Scene {
    fn with_meshes(mut self, meshes: Vec<(Id, MeshSet)>) -> Scene {
        self.meshes = meshes;
        self
    }
}

fn shadow_texture(device: &wgpu::Device, size: u32) -> wgpu::Texture {
    device.create_texture(&wgpu::TextureDescriptor {
        label: Some("rc-shadow-map"),
        size: wgpu::Extent3d { width: size, height: size, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: DEPTH_FORMAT,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
        view_formats: &[],
    })
}

/// Edges between faces that meet at a crease, plus open boundaries.
fn feature_edges(mesh: &rc_core::mesh::Mesh) -> Vec<(DVec3, DVec3)> {
    let q = |v: DVec3| ((v.x * 2.0).round() as i64, (v.y * 2.0).round() as i64, (v.z * 2.0).round() as i64);
    let mut map: HashMap<((i64, i64, i64), (i64, i64, i64)), (DVec3, DVec3, Vec<DVec3>)> = HashMap::new();
    for tri in mesh.indices.chunks(3) {
        let p = [mesh.positions[tri[0] as usize], mesh.positions[tri[1] as usize], mesh.positions[tri[2] as usize]];
        let n = (p[1] - p[0]).cross(p[2] - p[0]).normalize_or_zero();
        for k in 0..3 {
            let (a, b) = (p[k], p[(k + 1) % 3]);
            let (ka, kb) = (q(a), q(b));
            let key = if ka < kb { (ka, kb) } else { (kb, ka) };
            map.entry(key).or_insert_with(|| (a, b, Vec::new())).2.push(n);
        }
    }
    map.into_values().filter(|(_, _, normals)| normals.len() == 1 || normals.iter().any(|n| n.dot(normals[0]) < 0.94)).map(|(a, b, _)| (a, b)).collect()
}

/// Ray cast against element meshes; returns the nearest hit inside the section box.
pub fn pick(scene: &Scene, origin: DVec3, dir: DVec3, clip: Option<(DVec3, DVec3)>) -> Option<(Id, DVec3)> {
    let mut best: Option<(f64, Id)> = None;
    let inside = |q: DVec3| clip.is_none_or(|(mn, mx)| q.cmpge(mn).all() && q.cmple(mx).all());
    for (id, set) in &scene.meshes {
        if let Some((mn, mx)) = set.bounds() {
            if !ray_box(origin, dir, mn - DVec3::splat(1.0), mx + DVec3::splat(1.0)) {
                continue;
            }
        }
        for mesh in set.by_material.values() {
            for tri in mesh.indices.chunks(3) {
                let (a, b, c) = (mesh.positions[tri[0] as usize], mesh.positions[tri[1] as usize], mesh.positions[tri[2] as usize]);
                if let Some(t) = ray_triangle(origin, dir, a, b, c) {
                    if best.is_none_or(|(bt, _)| t < bt) && inside(origin + dir * t) {
                        best = Some((t, *id));
                    }
                }
            }
        }
    }
    best.map(|b| (b.1, origin + dir * b.0))
}

fn ray_box(o: DVec3, d: DVec3, mn: DVec3, mx: DVec3) -> bool {
    let inv = DVec3::ONE / d;
    let t1 = (mn - o) * inv;
    let t2 = (mx - o) * inv;
    let tmin = t1.min(t2).max_element();
    let tmax = t1.max(t2).min_element();
    tmax >= tmin.max(0.0)
}

fn ray_triangle(o: DVec3, d: DVec3, a: DVec3, b: DVec3, c: DVec3) -> Option<f64> {
    let e1 = b - a;
    let e2 = c - a;
    let p = d.cross(e2);
    let det = e1.dot(p);
    if det.abs() < 1e-12 {
        return None;
    }
    let inv = 1.0 / det;
    let s = o - a;
    let u = s.dot(p) * inv;
    if !(0.0..=1.0).contains(&u) {
        return None;
    }
    let qv = s.cross(e1);
    let v = d.dot(qv) * inv;
    if v < 0.0 || u + v > 1.0 {
        return None;
    }
    let t = e2.dot(qv) * inv;
    (t > 1e-6).then_some(t)
}

/// Default orbit camera framing a bounding box.
pub fn frame_bounds(bounds: Option<(DVec3, DVec3)>, dir: DVec3, perspective: bool) -> Camera {
    let (mn, mx) = bounds.unwrap_or((DVec3::ZERO, DVec3::new(10000.0, 8000.0, 6000.0)));
    let c = (mn + mx) / 2.0;
    let r = (mx - mn).length().max(3000.0);
    let dir = dir.normalize_or(DVec3::new(-0.6, -0.9, 0.55));
    Camera { eye: c + dir * r * 1.25, target: c, perspective, ortho_height: r * 1.05 }
}

/// Sun direction (towards the sun) from azimuth (clockwise from north) and altitude in degrees.
pub fn sun_direction(azimuth: f64, altitude: f64) -> DVec3 {
    let (az, alt) = (azimuth.to_radians(), altitude.to_radians());
    DVec3::new(az.sin() * alt.cos(), az.cos() * alt.cos(), alt.sin())
}
