// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEM/Shaders/Colormaps.metal (macTEM@51c944c macTEM/Shaders/Colormaps.metal: folded in the 3-line comment on parameter structs)
// Changes: none to the shader code; now a ShellMetal package resource (library loads with makeDefaultLibrary(bundle: .module)).
// END MOVED FROM
//
//  Colormaps.metal
//  Role: GPU-side image display. A fullscreen-triangle vertex shader (no vertex
//        buffer — positions come from vertex_id) plus a fragment shader that
//        reads a single-channel, already-normalized result texture and looks up
//        its color in a 1D colormap LUT texture. Zoom, pan, rotation and mirroring
//        come from one affine map (pane-normalised position -> image uv).
//
//  Both the diffraction viewer and the real-space result viewer render through
//  this pipeline (see MetalImageView.swift).
//

#include <metal_stdlib>
using namespace metal;

struct VOut {
    float4 position [[position]];
    float2 uv;
};

// Parameters cross as plain float4 buffers (MetalImageView sets them with SIMD4<Float>). A parameter struct added here must
// stay byte-identical to its Swift twin (all 4-byte fields) and get a MemoryLayout test; none exists yet.
//
// xf = two rows (A00, A01, t0, 0), (A10, A11, t1, 0): image uv = A q + t, with q
// the pane-normalised position (0...1, origin top-left). Identity = whole image.
vertex VOut displayVertex(uint vid [[vertex_id]],
                          constant float4 *xf [[buffer(0)]])
{
    // One oversized triangle covering the viewport.
    const float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    // Matching UVs; v flipped so texture row 0 appears at the TOP.
    const float2 uvs[3] = { float2(0.0, 1.0),  float2(2.0, 1.0),  float2(0.0, -1.0) };

    VOut o;
    o.position = float4(pos[vid], 0.0, 1.0);
    float2 q = uvs[vid];
    o.uv = float2(dot(xf[0].xy, q) + xf[0].z,
                  dot(xf[1].xy, q) + xf[1].z);
    return o;
}

// display = (lo, hi, gamma, unused) in normalized [0,1] intensity.
fragment float4 colormapFragment(VOut in [[stage_in]],
                                 constant float4 &display [[buffer(0)]],
                                 texture2d<float> img [[texture(0)]],
                                 texture1d<float> lut [[texture(1)]])
{
    // r32Float data sampled NEAREST (not all GPUs filter r32Float).
    constexpr sampler dataSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    // rgba8 LUT is filterable → smooth color ramp.
    constexpr sampler lutSampler(address::clamp_to_edge, filter::linear);

    // Outside the image (zoomed out, panned, letterboxed) → transparent, so
    // what is behind the view shows.
    if (in.uv.x < 0.0 || in.uv.x > 1.0 || in.uv.y < 0.0 || in.uv.y > 1.0) {
        return float4(0.0);
    }

    float raw = img.sample(dataSampler, in.uv).r;
    // Invalid/masked pixels arrive as a negative sentinel (see
    // FloatImage.invalidDisplayValue). They get a dedicated neutral gray,
    // never a colormap entry — "no data" must not look like a value.
    if (raw < 0.0) {
        return float4(0.32, 0.32, 0.34, 1.0);
    }
    float v = clamp(raw, 0.0, 1.0);
    v = clamp((v - display.x) / max(display.y - display.x, 1e-6), 0.0, 1.0);
    v = pow(v, 1.0 / max(display.z, 0.05));
    float4 c = lut.sample(lutSampler, v);
    return float4(c.rgb, 1.0);
}

// Pre-colored results (DPC color wheel): sample the RGBA texture directly,
// no LUT. Same vertex shader / display transform as the scalar path.
fragment float4 rgbaFragment(VOut in [[stage_in]],
                             texture2d<float> img [[texture(0)]])
{
    constexpr sampler dataSampler(coord::normalized, address::clamp_to_edge, filter::nearest);

    if (in.uv.x < 0.0 || in.uv.x > 1.0 || in.uv.y < 0.0 || in.uv.y > 1.0) {
        return float4(0.0);
    }
    return float4(img.sample(dataSampler, in.uv).rgb, 1.0);
}
