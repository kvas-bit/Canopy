#include "ShaderShared.h"

// -----------------------------------------------------------------------------
// Scene 3: Shallow Forest Stream (Discrete Rounded River Pebbles & F2-F1 Caustics)
// -----------------------------------------------------------------------------

inline float waterRippleField(
    float2 worldXZ,
    float2 screenUV,
    constant FrameUniforms& u,
    constant CursorImpulse* impulses
) {
    float time = u.cameraRightAndTime.w;
    // Steady, unhurried gravitational stream flow — barely modulated by CPU load
    float flowSpeed = 0.21 + u.gustAndTurbulence.z * 0.06;
    float2 flowDir = normalize(float2(0.88, 0.22));

    float2 p1 = worldXZ * 2.0 - flowDir * (time * flowSpeed * 1.15);
    float2 p2 = worldXZ * 4.6 - float2(flowDir.x * 0.8 - flowDir.y * 0.4, flowDir.y * 0.9 + flowDir.x * 0.3) * (time * flowSpeed * 1.65);
    float h = (fbm2D(p1) - 0.5) * 0.010 * (0.80 + 0.20 * u.gustAndTurbulence.x);
    h += (valueNoise2D(p2) - 0.5) * 0.0040;
    h += sin(worldXZ.x * 4.2 + sin(worldXZ.y * 2.5) * 1.2 - time * flowSpeed * 2.1) * 0.0022;

    // Subliminal, broad, slow-gliding surface swell from cursor breeze
    float aspect = u.cameraForwardAndAspect.w;
    for (int i = 0; i < MAX_CURSOR_IMPULSES; ++i) {
        float4 pr = impulses[i].posAndRadius;
        float strength = impulses[i].velAndStrength.z;
        if (strength <= 0.001) continue;

        float2 d = screenUV - pr.xy;
        d.x *= aspect;
        float dist = length(d);
        float age = pr.w;
        float ringRadius = 0.02 + age * 0.14;
        float ringEnv = exp(-pow((dist - ringRadius) * 11.5, 2.0)) * pow(1.0 - age, 2.2);
        float wave = sin((dist - ringRadius) * 38.0) * ringEnv * min(strength, 0.8) * 0.0028;
        h += wave;
    }

    return h;
}

// True F2 - F1 Voronoi ridge filament caustics
inline float causticFilament(float2 p) {
    float2 n = floor(p);
    float2 f = fract(p);
    float d1 = 8.0;
    float d2 = 8.0;
    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            float2 g = float2(float(i), float(j));
            float2 o = hash22(n + g);
            float2 r = g + o - f;
            float d = dot(r, r);
            if (d < d1) {
                d2 = d1;
                d1 = d;
            } else if (d < d2) {
                d2 = d;
            }
        }
    }
    float edge = sqrt(max(d2, 0.0)) - sqrt(max(d1, 0.0));
    return exp(-edge * 13.5);
}

inline float evaluateCaustics(float2 p, float time, float flowSpeed) {
    float2 flow = float2(time * flowSpeed * 0.42, time * 0.14);
    float2 warp = float2(fbm2D(p * 1.3 - flow * 0.5), fbm2D(p * 1.3 + 4.8 - flow * 0.5)) * 0.28;
    float c1 = causticFilament((p + warp) * 2.15 - flow);
    float c2 = causticFilament((p * float2x2(0.8, -0.6, 0.6, 0.8) - warp) * 3.05 - flow * 1.25 + 4.3);
    return c1 * 0.85 + c2 * 0.55;
}

struct PebbleLayerHit {
    float height;
    float3 normal;
    float stoneSeed;
    float rimAO;
};

inline PebbleLayerHit sampleDiscretePebbles(float2 uv, float scale, float heightAmp, float seedOffset) {
    float2 scaled = uv * scale;
    float2 baseCell = floor(scaled);
    float2 fracPos = fract(scaled);

    float bestH = -1.0;
    float3 bestN = float3(0.0, 1.0, 0.0);
    float bestSeed = 0.0;
    float bestRim = 0.0;

    for (int j = -1; j <= 1; ++j) {
        for (int i = -1; i <= 1; ++i) {
            float2 g = float2(float(i), float(j));
            float2 cellID = baseCell + g;
            float2 rndA = hash22(cellID + seedOffset);
            float2 rndB = hash22(cellID * 1.73 + seedOffset + 19.7);

            float2 center = g + 0.5 + (rndA - 0.5) * 0.34;
            float2 rel = fracPos - center;

            float angle = rndB.x * 3.14159;
            float cs = cos(angle);
            float sn = sin(angle);
            float2 rot = float2(rel.x * cs - rel.y * sn, rel.x * sn + rel.y * cs);

            float2 radii = float2(0.28 + rndA.x * 0.13, 0.22 + rndB.y * 0.11);
            float2 q = rot / radii;
            float r2 = dot(q, q);
            if (r2 < 1.0) {
                float smoothCap = pow(1.0 - r2, 0.62);
                float stoneH = smoothCap * heightAmp * (0.75 + 0.40 * rndB.y);
                if (stoneH > bestH) {
                    bestH = stoneH;
                    float2 localGrad = -1.24 * q / (radii * max(pow(1.0 - r2, 0.38), 0.22));
                    float2 worldGrad = float2(localGrad.x * cs + localGrad.y * sn, -localGrad.x * sn + localGrad.y * cs);
                    bestN = normalize(float3(-worldGrad.x * heightAmp * scale * 0.28, 1.0, -worldGrad.y * heightAmp * scale * 0.28));
                    bestSeed = fract(rndA.y * 0.67 + rndB.x * 0.33);
                    bestRim = smoothstep(0.0, 0.42, 1.0 - r2);
                }
            }
        }
    }

    PebbleLayerHit hit;
    hit.height = bestH;
    hit.normal = bestN;
    hit.stoneSeed = bestSeed;
    hit.rimAO = bestRim;
    return hit;
}

inline float3 stoneMineralColor(float seed, float2 pos, float warmth) {
    float mottling = fbm2D(pos * 18.0 + seed * 31.0);
    float grain = valueNoise2D(pos * 95.0 + seed * 57.0);
    float darkSpeck = step(0.74, grain);
    float lightSpeck = step(0.88, valueNoise2D(pos * 120.0 + seed * 13.0));

    float3 charcoalBasalt = float3(0.022, 0.024, 0.028);
    float3 coolRiverSlate = float3(0.048, 0.056, 0.064);
    float3 warmTerracotta = float3(0.165, 0.088, 0.048);
    float3 ochreSandstone = float3(0.185, 0.142, 0.088);
    float3 paleQuartzite  = float3(0.245, 0.232, 0.205);

    float3 c = charcoalBasalt;
    if (seed > 0.86) c = paleQuartzite;
    else if (seed > 0.68) c = ochreSandstone;
    else if (seed > 0.50) c = warmTerracotta;
    else if (seed > 0.26) c = coolRiverSlate;

    c *= (0.78 + 0.44 * mottling);
    c *= (1.0 - 0.24 * darkSpeck);
    c += lightSpeck * float3(0.05, 0.048, 0.042);

    float3 submergedMoss = mix(float3(0.012, 0.042, 0.024), float3(0.024, 0.078, 0.018), warmth);
    float mossMask = smoothstep(0.64, 0.86, fbm2D(pos * 1.1 + float2(-2.2, 5.1))) * step(seed, 0.45);
    return mix(c, submergedMoss, mossMask * 0.72);
}

inline void evaluateRiverbed(
    float2 bedXZ,
    thread float3& albedo,
    thread float3& bedNormal,
    thread float& bedElevation,
    float warmth
) {
    float fineGrain = valueNoise2D(bedXZ * 55.0);
    float coarseSand = fbm2D(bedXZ * 16.0);
    float baseSandH = -0.38 + (fbm2D(bedXZ * 0.65) - 0.5) * 0.10;
    float3 wetRiverSand = float3(0.028, 0.024, 0.019) * (0.65 + 0.70 * fineGrain) * (0.8 + 0.4 * coarseSand);

    float2 warped = bedXZ + float2(
        fbm2D(bedXZ * 0.68 + float2(2.3, -1.7)) - 0.5,
        fbm2D(bedXZ * 0.68 + float2(-5.1, 4.2)) - 0.5
    ) * 0.62;
    PebbleLayerHit gravel  = sampleDiscretePebbles(warped, 8.2, 0.028, 31.4);
    PebbleLayerHit pebbles = sampleDiscretePebbles(warped * float2x2(0.86, -0.50, 0.50, 0.86) + float2(0.37, 0.61), 3.7, 0.064, 7.1);
    PebbleLayerHit cobbles = sampleDiscretePebbles(warped * float2x2(0.78, 0.62, -0.62, 0.78) + float2(1.9, -0.8), 1.85, 0.102, 93.2);

    float h = baseSandH;
    float3 n = float3(0.0, 1.0, 0.0);
    float3 col = wetRiverSand;
    float ao = 0.36;

    if (gravel.height > 0.0) {
        h = baseSandH + gravel.height;
        n = gravel.normal;
        col = stoneMineralColor(gravel.stoneSeed, bedXZ, warmth);
        ao = 0.35 + 0.65 * gravel.rimAO;
    }
    if (pebbles.height > 0.006 && (baseSandH + pebbles.height) > h) {
        h = baseSandH + pebbles.height;
        n = pebbles.normal;
        col = stoneMineralColor(pebbles.stoneSeed, bedXZ * 0.9, warmth);
        ao = 0.30 + 0.70 * pebbles.rimAO;
    }
    if (cobbles.height > 0.014 && (baseSandH + cobbles.height) > h && cobbles.stoneSeed > 0.36) {
        h = baseSandH + cobbles.height;
        n = cobbles.normal;
        col = stoneMineralColor(cobbles.stoneSeed, bedXZ * 0.75, warmth);
        ao = 0.28 + 0.72 * cobbles.rimAO;
    }

    bedElevation = h;
    bedNormal = n;
    albedo = col * ao;
}

struct StreamWaterOut {
    float4 position [[position]];
    float3 worldPos;
    float linearDepth;
};

vertex StreamWaterOut streamSurfaceVertex(
    uint vid [[vertex_id]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    const uint GX = 128;
    const uint GZ = 128;
    uint quad = vid / 6;
    uint corner = vid % 6;
    uint2 offs[6] = { uint2(0,0), uint2(1,0), uint2(0,1), uint2(1,0), uint2(1,1), uint2(0,1) };
    uint2 cell = uint2(quad % GX, quad / GX) + offs[corner];

    float x = mix(-5.6, 5.8, float(cell.x) / float(GX));
    float z = mix(3.4, -7.8, float(cell.y) / float(GZ));
    float3 wp = float3(x, 0.0, z);

    StreamWaterOut out;
    out.position = u.viewProjMatrix * float4(wp, 1.0);
    out.worldPos = wp;
    out.linearDepth = length(wp - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 streamSurfaceFragment(
    StreamWaterOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]],
    constant CursorImpulse* impulses [[buffer(1)]]
) {
    float2 screenUV = in.position.xy * u.resolutionAndScene.zw;
    screenUV.y = 1.0 - screenUV.y;

    const float eps = 0.020;
    float hC = waterRippleField(in.worldPos.xz, screenUV, u, impulses);
    float hX = waterRippleField(in.worldPos.xz + float2(eps, 0.0), screenUV + float2(eps * 0.04, 0.0), u, impulses);
    float hZ = waterRippleField(in.worldPos.xz + float2(0.0, eps), screenUV + float2(0.0, eps * 0.04), u, impulses);
    float3 waterN = normalize(float3(hC - hX, eps, hC - hZ));

    float3 V = normalize(u.cameraPosAndFOV.xyz - in.worldPos);
    float3 L = normalize(float3(-0.42, 0.78, -0.46));
    float warmth = u.sunColorAndWarmth.w;

    float3 refractedRay = refract(-V, waterN, 1.0 / 1.333);
    if (length(refractedRay) < 0.001) {
        refractedRay = -V;
    }

    float approxDepth = 0.34;
    float2 hitXZ = in.worldPos.xz + refractedRay.xz * (approxDepth / max(-refractedRay.y, 0.28));

    float3 bedAlbedo;
    float3 bedNormal;
    float bedElev;
    evaluateRiverbed(hitXZ, bedAlbedo, bedNormal, bedElev, warmth);

    float waterColumn = max(hC - bedElev, 0.06);
    float pathLen = waterColumn / max(-refractedRay.y, 0.30);

    float3 sunRefract = normalize(refract(-L, float3(0.0, 1.0, 0.0), 1.0 / 1.333));
    float2 causticUV = hitXZ - sunRefract.xz * (waterColumn / max(-sunRefract.y, 0.35)) + waterN.xz * 0.65;
    float caustics = evaluateCaustics(causticUV, u.cameraRightAndTime.w, 0.22 + u.gustAndTurbulence.z * 0.06);

    float bedDiffuse = saturate(dot(bedNormal, -sunRefract) * 0.8 + 0.2);
    float3 bedHalf = normalize(-sunRefract + V);
    float wetStoneSpec = pow(max(dot(bedNormal, bedHalf), 0.0), 32.0) * 0.16;
    float3 sunRad = u.sunColorAndWarmth.rgb * u.sunDirAndIntensity.w;

    float canopyDapple = smoothstep(0.24, 0.74, fbm2D(hitXZ * 0.42 + float2(1.2, -0.8)));
    float sunVis = 0.32 + 0.68 * canopyDapple;

    float3 bedLit = bedAlbedo * (
        float3(0.12, 0.16, 0.18) * (0.45 + 0.55 * warmth)
        + sunRad * bedDiffuse * 0.58 * sunVis
        + sunRad * caustics * 1.45 * sunVis
    ) + sunRad * wetStoneSpec * (0.35 + caustics) * sunVis;

    float3 absorption = exp(-pathLen * float3(0.42, 0.15, 0.14) * 1.15);
    float3 creekScatter = mix(float3(0.004, 0.015, 0.020), float3(0.008, 0.032, 0.028), warmth);
    float3 underwaterCol = bedLit * absorption + creekScatter * (1.0 - absorption);

    float3 R = reflect(-V, waterN);
    float leafDapple = fbm2D(R.xz * 3.0 + float2(1.4, -2.2));
    float3 darkFoliageRefl = mix(float3(0.006, 0.014, 0.020), float3(0.014, 0.044, 0.016), warmth);
    float3 skyPatchRefl    = mix(float3(0.03, 0.06, 0.10), float3(0.18, 0.26, 0.24), warmth);
    float3 canopyRefl = mix(darkFoliageRefl, skyPatchRefl, smoothstep(0.52, 0.85, leafDapple));

    float fresnel = 0.02 + 0.98 * pow(1.0 - saturate(dot(waterN, V)), 5.0);
    float3 H = normalize(L + V);
    float sunGlint = min(pow(max(dot(waterN, H), 0.0), 320.0) * 2.2, 1.5);

    float3 finalCol = mix(underwaterCol, canopyRefl, clamp(fresnel * 0.82, 0.02, 0.62))
                    + sunRad * sunGlint;

    finalCol = applyAerialFog(finalCol, in.linearDepth, -V, u);
    return float4(finalCol, in.linearDepth);
}

// Pass 2: Sculpted Floating Autumn/Forest Leaves
struct LeafVertexOut {
    float4 position [[position]];
    float2 quadUV;
    float3 worldPos;
    float leafHue;
    float linearDepth;
};

vertex LeafVertexOut streamLeafVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms& u [[buffer(0)]],
    constant CursorImpulse* impulses [[buffer(1)]]
) {
    float3 rnd = hash31(iid * 65537U + 19U);
    float time = u.cameraRightAndTime.w;
    float speed = (0.12 + rnd.x * 0.08) * (0.85 + 0.15 * u.gustAndTurbulence.z);

    float prog = fract(rnd.x + time * speed * 0.022);
    float x = mix(-4.6, 5.0, prog);
    float z = mix(2.0, -5.4, rnd.y) + sin(prog * 6.283 + rnd.z * 5.0) * 0.30;
    float3 center = float3(x, 0.010, z);

    float2 screenUV = projectWorldToScreenUV(center, u);
    float h = waterRippleField(center.xz, screenUV, u, impulses);
    center.y = h + 0.006;

    float spin = time * (0.07 + (rnd.y - 0.5) * 0.10) + rnd.z * 6.283;
    float cs = cos(spin);
    float sn = sin(spin);

    float2 corners[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2( 1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
    };
    float2 q = corners[vid];
    float2 rotXZ = float2(q.x * cs - q.y * sn, q.x * sn + q.y * cs) * (0.046 + rnd.z * 0.022);
    float curlY = (q.x * q.x * 0.008 + q.y * q.y * 0.004);
    float3 wp = center + float3(rotXZ.x, curlY, rotXZ.y);

    LeafVertexOut out;
    out.position = u.viewProjMatrix * float4(wp, 1.0);
    out.quadUV = q;
    out.worldPos = wp;
    out.leafHue = rnd.y;
    out.linearDepth = length(wp - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 streamLeafFragment(
    LeafVertexOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float2 p = in.quadUV;
    float uLen = (p.y + 0.85) / 1.75;
    if (uLen < 0.0 || uLen > 1.0) discard_fragment();

    float widthProfile = sin(pow(uLen, 0.72) * 3.14159) * 0.50;
    float serration = sin(uLen * 32.0) * 0.022 * sin(uLen * 3.14159);
    if (abs(p.x) > widthProfile + serration) discard_fragment();

    float warmth = u.sunColorAndWarmth.w;
    float3 goldLeaf   = float3(0.28, 0.14, 0.018);
    float3 russetLeaf = float3(0.19, 0.052, 0.014);
    float3 oliveLeaf  = float3(0.038, 0.115, 0.020);

    float3 col = (in.leafHue > 0.68) ? oliveLeaf : mix(russetLeaf, goldLeaf, in.leafHue * 1.45);
    float midrib = exp(-abs(p.x) * 28.0) * 0.22;
    float curlShade = 0.78 + 0.28 * (1.0 - abs(p.x) / max(widthProfile, 0.05));
    col = col * curlShade * (0.88 + midrib);

    float3 lit = col * (u.skyZenithAndFog.rgb * 0.9 + u.sunColorAndWarmth.rgb * u.sunDirAndIntensity.w * (0.24 + 0.16 * warmth));
    return float4(lit, in.linearDepth);
}
