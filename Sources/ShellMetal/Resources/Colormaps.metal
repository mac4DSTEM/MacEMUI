//
//  Colormaps.metal
//  Role: GPU-side image display. A fullscreen-triangle vertex shader (no vertex
//        buffer — positions come from vertex_id) plus a fragment shader that
//        reads a single-channel, already-normalized result buffer and looks up
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
// img = the row-major image, size = (width, height), image = (low, span, encoding, 0) (`DisplayImage` in Swift). A buffer,
// not a texture: a 2D texture is limited to 16384 pixels a side, and larger images must draw (macTEM#562). Read NEAREST, as
// a clamp-to-edge nearest sampler would. Encoding 0: Float32 display values as given; 1 and 2: whole-number raw values in
// one or two bytes, normalised here as the CPU does, (v - low) / span, 0 for a flat image (`DisplayNormalization`).
// transfer = (kind, rangeLow, rangeSpan, 0) (`MetalImageView.DisplayTransfer`). Kind 0: the normalised value as it is. Kind 1:
// log10(1 + max(v, 0)) of the raw value v, normalised over the same of the raw range, as ImagoKit's
// `DisplayNormalization.normalizedLog` makes a pattern's log display values on the CPU (macEM#580). A Float32 image's raw
// value is rangeLow + n * rangeSpan.
fragment float4 colormapFragment(VOut in [[stage_in]],
                                 constant float4 &display [[buffer(0)]],
                                 device const uchar *img [[buffer(1)]],
                                 constant uint2 &size [[buffer(2)]],
                                 constant float4 &image [[buffer(3)]],
                                 constant float4 &transfer [[buffer(4)]],
                                 texture1d<float> lut [[texture(1)]])
{
    // rgba8 LUT is filterable → smooth color ramp.
    constexpr sampler lutSampler(address::clamp_to_edge, filter::linear);

    // Outside the image (zoomed out, panned, letterboxed) → transparent, so
    // what is behind the view shows.
    if (in.uv.x < 0.0 || in.uv.x > 1.0 || in.uv.y < 0.0 || in.uv.y > 1.0) {
        return float4(0.0);
    }

    uint x = min(uint(in.uv.x * float(size.x)), size.x - 1);
    uint y = min(uint(in.uv.y * float(size.y)), size.y - 1);
    uint i = y * size.x + x;
    uint encoding = uint(image.z);
    float raw;
    float value;   // the raw pixel value, for the log transfer
    if (encoding == 0) {
        raw = ((device const float *)img)[i];
        value = transfer.y + raw * transfer.z;
    } else {
        float v = encoding == 1 ? float(img[i]) : float(((device const ushort *)img)[i]);
        raw = image.y > 0.0 ? (v - image.x) / image.y : 0.0;
        value = v;
    }
    // Invalid/masked pixels arrive as a negative sentinel (see
    // FloatImage.invalidDisplayValue). They get a dedicated neutral gray,
    // never a colormap entry — "no data" must not look like a value.
    // A NaN is masked too. Tested on the bits: Metal compiles with fast math, where isnan() may be folded to false.
    if (raw < 0.0 || (as_type<uint>(raw) & 0x7fffffffu) > 0x7f800000u) {
        return float4(0.32, 0.32, 0.34, 1.0);
    }
    if (transfer.x == 1.0) {
        float lo = log10(1.0 + max(transfer.y, 0.0));
        float hi = log10(1.0 + max(transfer.y + transfer.z, 0.0));
        raw = hi > lo ? (log10(1.0 + max(value, 0.0)) - lo) / (hi - lo) : 0.0;
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
