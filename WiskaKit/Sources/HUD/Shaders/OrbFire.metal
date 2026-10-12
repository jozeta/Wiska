#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The Magical Orb's fire: a white-hot core inside churning plasma, laced with bright veins and a
// ragged edge, fading to nothing before the window's edge. Layered value noise, warped by itself
// (domain warping) for the flames, and "ridged" (folded) noise for the thin veins.

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

static float fbm(float2 p) {
    float value = 0.0, amplitude = 0.5;
    const float2x2 turn = float2x2(1.6, 1.2, -1.2, 1.6);
    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p);
        p = turn * p;
        amplitude *= 0.5;
    }
    return value;
}

/// - phase: the flames' clock (advances slowly when idle, faster when busy).
/// - intensity: 0…1, how fiercely it burns.
/// - radius: the fireball's size, as a share of half the window.
/// - ripple: how far the voice's pitch bands push the edge out.
/// - outer / inner: the highlight colour's two ends; the core always burns towards white.
/// - bands: the voice's smoothed pitch bands (low → high), mapped around the edge: low at the top,
///   high at the bottom, mirrored left and right.
[[ stitchable ]] half4 orbFire(float2 position, half4 color, float2 size, float phase, float intensity,
                               float radius, float ripple, half3 outer, half3 inner,
                               device const float *bands, int count) {
    float2 p = (position - size * 0.5) / (min(size.x, size.y) * 0.5);
    float r = length(p);
    float angle = atan2(p.y, p.x);

    float band = 0.0;
    if (count > 1) {
        float x = (sin(angle) + 1.0) * 0.5 * float(count - 1);
        int i = int(floor(x));
        band = mix(bands[i], bands[min(i + 1, count - 1)], x - float(i));
    }

    float t = phase;
    float2 q = p * 2.4;
    float2 warp = float2(fbm(q + float2(0.0, t * 0.6)), fbm(q + float2(5.2, -t * 0.5)));
    float flames = fbm(q * 1.3 + 2.5 * warp + t * 0.3);
    float ridge = 1.0 - abs(2.0 * fbm(q * 2.1 + 3.0 * warp - t * 0.4) - 1.0);
    float fine = 1.0 - abs(2.0 * fbm(q * 3.6 - 2.0 * warp + t * 0.25) - 1.0);
    float veins = pow(ridge, 5.0) * 0.8 + pow(fine, 6.0) * 0.5;

    float edge = radius * (0.95 + 0.35 * flames + ripple * band);
    float body = smoothstep(edge, edge * 0.35, r) * (0.55 + flames);
    float core = exp(-r * r / (radius * radius * 0.12));
    float wisps = veins * smoothstep(edge * 1.3, edge * 0.45, r);
    float halo = exp(-r * r / (radius * radius * 1.1));

    float e = intensity;
    float light = core * (0.55 + 0.9 * e)
                + body * flames * (0.35 + 0.8 * e)
                + wisps * (0.55 + 1.1 * e)
                + halo * (0.18 + 0.5 * e);
    light *= smoothstep(1.0, 0.72, r);                     // nothing reaches the window's edge

    float3 colour = mix(float3(outer), float3(inner), clamp(body + wisps * 0.5, 0.0, 1.0));
    colour = mix(colour, float3(1.0), clamp(core * 1.1 + wisps * 0.35 * e, 0.0, 1.0));
    float alpha = clamp(light, 0.0, 1.0);
    return half4(half3(colour * alpha), half(alpha));
}
