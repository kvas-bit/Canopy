#ifndef SHADER_SHARED_H
#define SHADER_SHARED_H

#include <metal_stdlib>
using namespace metal;

#define MAX_CURSOR_IMPULSES 16
#define MSAA_SAMPLE_COUNT 4

struct CursorImpulse {
    float4 posAndRadius;   // xy = UV (0..1, bottom-left), z = radius, w = age (0..1)
    float4 velAndStrength; // xy = UV velocity, z = strength, w = unused
};

struct FrameUniforms {
    float4x4 viewProjMatrix;
    float4x4 invViewProjMatrix;
    float4 cameraPosAndFOV;        // xyz = camPos, w = tanHalfFOV
    float4 cameraForwardAndAspect; // xyz = forward, w = aspect
    float4 cameraRightAndTime;     // xyz = right, w = time
    float4 cameraUpAndDelta;       // xyz = up, w = dt

    float4 sunDirAndIntensity;     // xyz = toSun, w = sunIntensity
    float4 sunColorAndWarmth;      // rgb = sunColor, w = warmth (0..1)
    float4 skyZenithAndFog;        // rgb = zenith, w = fogDensity
    float4 skyHorizonAndExposure;  // rgb = horizon, w = exposure
    float4 groundBounceAndAmbient; // rgb = bounce, w = ambientStrength

    float4 windDirAndSpeed;        // xy = windDirXZ, zw = integrated windOffsetXZ
    float4 gustAndTurbulence;      // x = gust, y = turbulence, z = cpuLoad, w = netBurst
    float4 cursorCurrent;          // xy = cursorUV, zw = cursorVel
    float4 dofParams;              // x = focusDist, y = focusRange, z = maxBokehPx, w = apertureScale
    float4 resolutionAndScene;     // xy = w,h, zw = 1/w, 1/h
    float4 extraParams;            // x = sceneIdx, y = cursorScale, z = nearZ, w = farZ
};

inline float hash11(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffff);
}

inline float2 hash21u(uint n) {
    uint n2 = n * 1664525U + 1013904223U;
    return float2(hash11(n), hash11(n2));
}

inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

inline float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

inline float3 hash31(uint n) {
    return float3(
        hash11(n * 747796405U + 2891336453U),
        hash11(n * 1597334677U + 3812015801U),
        hash11(n * 2798796415U + 198491317U)
    );
}

inline float valueNoise2D(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i + float2(0.0, 0.0));
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

inline float3 valueNoise2DGrad(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    float a = hash21(i + float2(0.0, 0.0));
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));

    float k0 = a;
    float k1 = b - a;
    float k2 = c - a;
    float k3 = a - b - c + d;

    float val = k0 + k1 * u.x + k2 * u.y + k3 * u.x * u.y;
    float2 grad = du * (float2(k1, k2) + k3 * u.yx);
    return float3(val, grad.x, grad.y);
}

inline float fbm2D(float2 p) {
    float sum = 0.0;
    float amp = 0.5;
    float2x2 rot = float2x2(0.80, -0.60, 0.60, 0.80);
    for (int i = 0; i < 4; ++i) {
        sum += amp * valueNoise2D(p);
        p = rot * p * 2.03 + float2(13.7, 7.1);
        amp *= 0.5;
    }
    return sum;
}

inline float4 voronoiSmooth2D(float2 x, float smoothness) {
    float2 n = floor(x);
    float2 f = fract(x);
    float4 m = float4(8.0, 0.0, 0.0, 0.0);
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            float2 g = float2(float(i), float(j));
            float2 o = hash22(n + g);
            float2 r = g - f + o;
            float d = dot(r, r);
            float h = smoothstep(-1.0, 1.0, (m.x - d) / max(smoothness, 0.001));
            m.x = mix(m.x, d, h) - h * (1.0 - h) * smoothness * 0.35;
            m.yzw = mix(m.yzw, float3(hash21(n + g + 19.1), r.x, r.y), h);
        }
    }
    return float4(sqrt(max(m.x, 0.0)), m.yzw);
}

inline float2 projectWorldToScreenUV(float3 worldPos, constant FrameUniforms& u) {
    float4 clip = u.viewProjMatrix * float4(worldPos, 1.0);
    if (clip.w <= 0.05) {
        return float2(-10.0, -10.0);
    }
    float2 ndc = clip.xy / clip.w;
    return ndc * 0.5 + 0.5;
}

inline float2 sampleCursorBreezeScreenUV(
    float2 uv,
    constant CursorImpulse* impulses,
    float aspect
) {
    float2 total = float2(0.0);
    for (int i = 0; i < MAX_CURSOR_IMPULSES; ++i) {
        float4 pr = impulses[i].posAndRadius;
        float4 vs = impulses[i].velAndStrength;
        float strength = vs.z;
        if (strength <= 0.001) continue;

        float2 diff = uv - pr.xy;
        diff.x *= aspect;
        float r = max(pr.z, 0.025);
        float d2 = dot(diff, diff) / (r * r);
        if (d2 > 6.5) continue;

        float radial = exp(-d2 * 1.35);
        float age = pr.w;
        // Critically damped smooth relaxation (zero back-and-forth bounce)
        float envelope = smoothstep(0.0, 0.06, age) * pow(1.0 - age, 2.5);
        float2 pushDir = vs.xy * 0.52 + (diff / (sqrt(dot(diff, diff)) + 0.05)) * 0.16;
        total += pushDir * (strength * radial * envelope);
    }
    return clamp(total, float2(-0.75), float2(0.75));
}

inline float3 evaluateBackdropSky(float3 rayDir, constant FrameUniforms& u) {
    float upFactor = clamp(rayDir.y * 1.6 + 0.22, 0.0, 1.0);
    float3 sky = mix(u.skyHorizonAndExposure.rgb, u.skyZenithAndFog.rgb, pow(upFactor, 0.75));
    float sunDot = max(dot(normalize(rayDir), u.sunDirAndIntensity.xyz), 0.0);
    sky += u.sunColorAndWarmth.rgb * pow(sunDot, 7.0) * 0.28 * u.sunDirAndIntensity.w * 0.25;
    sky += u.sunColorAndWarmth.rgb * pow(sunDot, 48.0) * 0.35 * u.sunDirAndIntensity.w * 0.22;
    return sky;
}

inline float3 applyAerialFog(float3 color, float dist, float3 rayDir, constant FrameUniforms& u) {
    float fogAmount = 1.0 - exp(-dist * u.skyZenithAndFog.w);
    float3 fogTint = evaluateBackdropSky(rayDir, u);
    return mix(color, fogTint, clamp(fogAmount, 0.0, 0.88));
}

#endif
