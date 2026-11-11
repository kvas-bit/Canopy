#include "ShaderShared.h"

struct PostVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex PostVertexOut postProcessVertex(uint vid [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    PostVertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = float2(positions[vid].x * 0.5 + 0.5, 0.5 - positions[vid].y * 0.5);
    return out;
}

inline float linearizeDepth(float ndcZ, float nearZ, float farZ) {
    float z = clamp(ndcZ, 0.0, 0.99995);
    return (nearZ * farZ) / max(farZ - z * (farZ - nearZ), 1e-4);
}

inline float computeBokehCoC(float linearDepth, constant FrameUniforms& u) {
    float focusDist = u.dofParams.x;
    float focusRange = u.dofParams.y;
    float maxRadius = u.dofParams.z * u.dofParams.w;

    float delta = abs(linearDepth - focusDist);
    if (linearDepth > focusDist) {
        float bgNorm = smoothstep(focusRange * 0.48, focusRange * 4.4, delta);
        return bgNorm * maxRadius * 0.70;
    } else {
        float fgNorm = smoothstep(focusRange * 0.28, focusRange * 1.50, delta);
        return fgNorm * maxRadius;
    }
}

inline float interleavedGradientNoise(float2 pixelPos) {
    return fract(52.9829189 * fract(dot(pixelPos, float2(0.06711056, 0.00583715))));
}

inline float3 acesFilmToneMap(float3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

inline float3 linearToSRGB(float3 c) {
    float3 lo = c * 12.92;
    float3 hi = 1.055 * pow(max(c, float3(0.0)), float3(1.0 / 2.4)) - 0.055;
    return select(hi, lo, c <= 0.0031308);
}

fragment float4 postProcessFragment(
    PostVertexOut in [[stage_in]],
    texture2d<half, access::sample> hdrSceneTex [[texture(0)]],
    depth2d<float, access::sample> depthTex [[texture(1)]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    constexpr sampler linearClamp(coord::normalized, address::clamp_to_edge, filter::linear);
    constexpr sampler pointClamp(coord::normalized, address::clamp_to_edge, filter::nearest);

    float nearZ = u.extraParams.z;
    float farZ = u.extraParams.w;

    float3 centerColor = max(float3(hdrSceneTex.sample(linearClamp, in.uv).rgb), float3(0.0));
    float centerNDC = depthTex.sample(pointClamp, in.uv);
    float centerDepth = linearizeDepth(centerNDC, nearZ, farZ);
    float centerCoC = computeBokehCoC(centerDepth, u);

    float2 pixelPos = in.uv * u.resolutionAndScene.xy;
    float2 texel = u.resolutionAndScene.zw;
    float maxCoC = u.dofParams.z * u.dofParams.w;

    float3 accumColor = centerColor;
    float accumWeight = 1.0;

    if (maxCoC > 0.55) {
        // Fast 4-tap early exit for in-focus pixels not overlapped by foreground bokeh
        bool needsGather = (centerCoC > 0.75);
        if (!needsGather) {
            float probeDist = maxCoC * 0.50;
            float2 probes[4] = {
                float2( probeDist, 0.0), float2(-probeDist, 0.0),
                float2(0.0,  probeDist), float2(0.0, -probeDist)
            };
            for (int p = 0; p < 4; ++p) {
                float pDepth = linearizeDepth(depthTex.sample(pointClamp, in.uv + probes[p] * texel), nearZ, farZ);
                if (pDepth < centerDepth - 0.35 && computeBokehCoC(pDepth, u) > 1.25) {
                    needsGather = true;
                    break;
                }
            }
        }

        if (needsGather) {
            const int TAP_COUNT = 38;
            const float GOLDEN_ANGLE = 2.39996323;
            float jitterAngle = interleavedGradientNoise(pixelPos) * 6.2831853;
            float searchRadius = clamp(max(centerCoC, maxCoC * 0.42), 0.0, maxCoC);

            for (int i = 1; i <= TAP_COUNT; ++i) {
                float fi = float(i);
                float rNorm = sqrt((fi - 0.35) / float(TAP_COUNT));
                float theta = fi * GOLDEN_ANGLE + jitterAngle;
                float2 unitOffset = float2(cos(theta), sin(theta)) * rNorm;
                float sampleDistPx = rNorm * searchRadius;
                float2 sampleUV = in.uv + unitOffset * searchRadius * texel;

                float tapNDC = depthTex.sample(pointClamp, sampleUV);
                float tapDepth = linearizeDepth(tapNDC, nearZ, farZ);
                float tapCoC = computeBokehCoC(tapDepth, u);

                float allowedCoC;
                if (tapDepth > centerDepth + 0.25) {
                    allowedCoC = min(centerCoC, tapCoC);
                } else if (centerDepth > tapDepth + 0.25) {
                    allowedCoC = tapCoC;
                } else {
                    allowedCoC = max(centerCoC, tapCoC);
                }

                float discCoverage = smoothstep(sampleDistPx - 1.15, sampleDistPx + 1.15, allowedCoC);
                if (discCoverage <= 0.001) continue;

                float3 tapColor = max(float3(hdrSceneTex.sample(linearClamp, sampleUV).rgb), float3(0.0));
                float luma = dot(tapColor, float3(0.2126, 0.7152, 0.0722));
                float bokehHighlight = 1.0 + smoothstep(0.55, 2.6, luma) * smoothstep(1.5, maxCoC, tapCoC) * 1.65;
                float apertureRing = 0.88 + 0.24 * smoothstep(0.60, 0.96, rNorm);
                float w = discCoverage * bokehHighlight * apertureRing;

                accumColor += tapColor * w;
                accumWeight += w;
            }
        }
    }

    float3 hdr = (accumColor / max(accumWeight, 0.001)) * u.skyHorizonAndExposure.w;

    float2 centered = in.uv - 0.5;
    centered.x *= u.cameraForwardAndAspect.w * 0.60;
    float vig = 1.0 - dot(centered, centered) * 0.24;
    hdr *= clamp(vig, 0.76, 1.0);

    float3 mapped = acesFilmToneMap(hdr);
    float3 srgb = linearToSRGB(mapped);

    float dither = (interleavedGradientNoise(pixelPos + fract(u.cameraRightAndTime.w) * 71.0) - 0.5) / 255.0;
    srgb = saturate(srgb + dither);

    return float4(srgb, 1.0);
}
