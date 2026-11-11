#include "ShaderShared.h"

// -----------------------------------------------------------------------------
// Scene 4: Coastal Sand & Dune Reeds — Sculpted Dunes, Trapped Sand Hummocks,
//          360° Arching Marram Grass & Nodding Sea-Oat Seed Panicles
// -----------------------------------------------------------------------------

inline float duneTuftMask(float2 xz, thread float4& tuftVor) {
    tuftVor = voronoiSmooth2D(xz * 0.68, 0.18);
    float crestX = sin(xz.y * 0.28 + 0.65) * 1.45 + 0.25;
    float hollowBand = smoothstep(2.4, 0.5, abs(xz.x - crestX + 0.65));
    float patch = smoothstep(0.36, 0.52, fbm2D(xz * 0.42 + 4.1));
    return smoothstep(0.42, 0.10, tuftVor.x) * hollowBand * patch;
}

inline float duneHeight(float2 xz) {
    float crestX = sin(xz.y * 0.28 + 0.65) * 1.45 + 0.25;
    float across = xz.x - crestX;
    float crestProfile = 1.05 - sqrt(across * across + 0.035) * (across < 0.0 ? 0.34 : 0.44);
    float foreDune = exp(-pow((xz.y - 1.55 + xz.x * 0.22) * 0.52, 2.0)) * 0.42;
    float distantDune = exp(-pow((xz.y + 6.5 - xz.x * 0.18) * 0.28, 2.0)) * 1.15;

    // Real coastal physics: beach grass traps windblown sand into raised hummocks around clumps!
    float4 tv;
    float hummock = duneTuftMask(xz, tv) * 0.14;
    return crestProfile + foreDune + distantDune + hummock - 0.38;
}

inline float duneMicroRipple(float2 xz) {
    float crestX = sin(xz.y * 0.28 + 0.65) * 1.45 + 0.25;
    float windwardMask = smoothstep(0.6, -0.8, xz.x - crestX);

    float warp = fbm2D(xz * 1.15) * 2.6;
    float phase = (xz.x * 0.88 + xz.y * 0.46) * 22.0 + warp;
    float asymmetricWave = sin(phase) + 0.32 * sin(phase * 2.0 + 0.75);
    return asymmetricWave * 0.011 * (0.22 + 0.78 * windwardMask);
}

inline float3 duneMacroNormal(float2 xz) {
    const float e = 0.06;
    float hL = duneHeight(xz - float2(e, 0.0));
    float hR = duneHeight(xz + float2(e, 0.0));
    float hD = duneHeight(xz - float2(0.0, e));
    float hU = duneHeight(xz + float2(0.0, e));
    return normalize(float3(hL - hR, 2.0 * e, hD - hU));
}

inline float3 dunePerPixelNormal(float2 xz) {
    const float e = 0.014;
    float hL = duneHeight(xz - float2(e, 0.0)) + duneMicroRipple(xz - float2(e, 0.0));
    float hR = duneHeight(xz + float2(e, 0.0)) + duneMicroRipple(xz + float2(e, 0.0));
    float hD = duneHeight(xz - float2(0.0, e)) + duneMicroRipple(xz - float2(0.0, e));
    float hU = duneHeight(xz + float2(0.0, e)) + duneMicroRipple(xz + float2(0.0, e));
    return normalize(float3(hL - hR, 2.0 * e, hD - hU));
}

struct DuneBackdropOut {
    float4 position [[position]];
    float2 uv;
};

vertex DuneBackdropOut duneBackdropVertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    DuneBackdropOut out;
    out.position = float4(pos[vid], 0.9999, 1.0);
    out.uv = pos[vid] * 0.5 + 0.5;
    return out;
}

fragment float4 duneBackdropFragment(
    DuneBackdropOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float warmth = u.sunColorAndWarmth.w;
    float time = u.cameraRightAndTime.w;

    float3 seaZenith = mix(float3(0.008, 0.020, 0.048), float3(0.055, 0.155, 0.340), warmth);
    float3 amberMist = mix(float3(0.024, 0.042, 0.075), float3(0.420, 0.335, 0.265), warmth);

    float h = pow(saturate(in.uv.y * 1.32), 0.70);
    float3 sky = mix(amberMist, seaZenith, h);

    // Soft coastal marine-layer clouds drifting near horizon
    float2 cUV = float2(in.uv.x * 2.8 + time * 0.005, in.uv.y * 5.2);
    float clouds = fbm2D(cUV) * smoothstep(0.05, 0.32, in.uv.y) * smoothstep(0.85, 0.28, in.uv.y);
    float3 cloudTint = mix(float3(0.08, 0.12, 0.20), u.sunColorAndWarmth.rgb * 0.85, 0.25 + 0.75 * warmth);
    sky = mix(sky, cloudTint, smoothstep(0.32, 0.72, clouds) * 0.48);

    sky += u.sunColorAndWarmth.rgb * exp(-length(in.uv - float2(0.18, 0.62)) * 3.4) * 0.20 * u.sunDirAndIntensity.w * 0.30;
    return float4(sky, 1.0);
}

struct DuneTerrainOut {
    float4 position [[position]];
    float3 worldPos;
    float linearDepth;
};

vertex DuneTerrainOut duneTerrainVertex(
    uint vid [[vertex_id]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    const uint GX = 140;
    const uint GZ = 140;
    uint quad = vid / 6;
    uint corner = vid % 6;
    uint2 offs[6] = { uint2(0,0), uint2(1,0), uint2(0,1), uint2(1,0), uint2(1,1), uint2(0,1) };
    uint2 cell = uint2(quad % GX, quad / GX) + offs[corner];

    float x = mix(-6.8, 7.6, float(cell.x) / float(GX));
    float z = mix(4.5, -13.0, float(cell.y) / float(GZ));
    float y = duneHeight(float2(x, z));
    float3 wp = float3(x, y, z);

    DuneTerrainOut out;
    out.position = u.viewProjMatrix * float4(wp, 1.0);
    out.worldPos = wp;
    out.linearDepth = length(wp - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 duneTerrainFragment(
    DuneTerrainOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float3 N = dunePerPixelNormal(in.worldPos.xz);
    float3 macroN = duneMacroNormal(in.worldPos.xz);
    float3 V = normalize(u.cameraPosAndFOV.xyz - in.worldPos);
    float warmth = u.sunColorAndWarmth.w;

    float3 rakingSun = normalize(float3(-0.82, 0.24 + 0.16 * warmth, -0.45));
    float ndl = max(dot(N, rakingSun), 0.0);
    float slipShadow = smoothstep(-0.08, 0.22, dot(macroN, rakingSun));

    float4 tv;
    float tuftShadow = 1.0 - duneTuftMask(in.worldPos.xz, tv) * 0.35;

    float3 goldenSand = mix(float3(0.048, 0.062, 0.092), float3(0.320, 0.220, 0.135), 0.15 + 0.85 * warmth);
    float3 coolShadow = mix(float3(0.010, 0.018, 0.035), float3(0.055, 0.058, 0.078), 0.15 + 0.85 * warmth);

    float fineGrain = valueNoise2D(in.worldPos.xz * 85.0);
    float3 albedo = goldenSand * (0.88 + 0.24 * fineGrain) * tuftShadow;

    float3 sunRad = u.sunColorAndWarmth.rgb * u.sunDirAndIntensity.w;
    float2 sparkleCell = floor(in.worldPos.xz * 210.0);
    float3 sparkleRand = hash31(uint(abs(sparkleCell.x) * 1973.0 + abs(sparkleCell.y) * 9277.0));
    float3 facetN = normalize(N + (sparkleRand - 0.5) * 0.90);
    float3 H = normalize(rakingSun + V);
    float quartzSparkle = pow(max(dot(facetN, H), 0.0), 115.0) * step(0.86, sparkleRand.z) * slipShadow;

    float3 skyAmb = coolShadow * (0.85 + 0.45 * saturate(N.y)) * tuftShadow;
    float3 direct = albedo * sunRad * (ndl * 0.66 * slipShadow);
    float3 rimCrest = albedo * sunRad * pow(1.0 - saturate(dot(macroN, V)), 3.0) * slipShadow * 0.16;

    float3 col = skyAmb + direct + rimCrest + sunRad * quartzSparkle * 1.15;
    col = applyAerialFog(col, in.linearDepth, -V, u);
    return float4(col, 1.0);
}

// -----------------------------------------------------------------------------
// Pass 3: 36,000 Organic Coastal Marram Grasses & Sea-Oat Seed Panicles
// -----------------------------------------------------------------------------

struct ReedVertexOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float3 tangent;
    float reedT;
    float reedCross;
    float isSeedOat;
    float dryness;
    float linearDepth;
};

inline float3 reedBezier(float3 p0, float3 p1, float3 p2, float3 p3, float t) {
    float it = 1.0 - t;
    return it*it*it*p0 + 3.0*it*it*t*p1 + 3.0*it*t*t*p2 + t*t*t*p3;
}

inline float3 reedBezierTan(float3 p0, float3 p1, float3 p2, float3 p3, float t) {
    float it = 1.0 - t;
    return 3.0*it*it*(p1 - p0) + 6.0*it*t*(p2 - p1) + 3.0*t*t*(p3 - p2);
}

vertex ReedVertexOut duneReedVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms& u [[buffer(0)]],
    constant CursorImpulse* impulses [[buffer(1)]]
) {
    const uint COLS = 170;
    const uint ROWS = 140;
    uint col = iid % COLS;
    uint row = iid / COLS;

    float3 rnd = hash31(iid * 524287U + 31U);
    float2 rnd2 = hash21u(iid * 8191U + 73U);
    float rnd3 = hash11(iid * 131071U + 19U);

    float uCol = (float(col) + rnd.x) / float(COLS);
    float uRow = (float(row) + rnd.y) / float(ROWS);
    float zBias = pow(uRow, 1.18);
    float z = mix(3.4, -9.8, zBias);
    float x = mix(-0.35, 0.55, zBias) + (uCol - 0.5) * 9.8 * mix(0.45, 1.22, zBias);

    float4 tuft = voronoiSmooth2D(float2(x, z) * 0.68, 0.18);
    x += tuft.z * 0.28;
    z += tuft.w * 0.28;

    float crestX = sin(z * 0.28 + 0.65) * 1.45 + 0.25;
    bool nearCrestOrHollow = abs(x - crestX + 0.65) < 2.25;
    bool inTuft = nearCrestOrHollow && (tuft.x < 0.40) && (valueNoise2D(float2(x, z) * 0.42 + 4.1) > 0.38);

    bool isSeedOat = (rnd3 > 0.83);
    float groundY = duneHeight(float2(x, z));
    float3 rootPos = float3(x, groundY - 0.045, z);

    float height = isSeedOat ? (0.62 + rnd.z * 0.45) : (0.34 + rnd.z * 0.52) * (1.08 - tuft.x * 0.65);
    float distToCam = length(rootPos - u.cameraPosAndFOV.xyz);
    float halfWidth = (isSeedOat ? 0.0024 : (0.0030 + rnd2.x * 0.0018)) * clamp(distToCam * 0.078, 0.95, 1.85);

    float2 windDir = normalize(u.windDirAndSpeed.xy + float2(0.86, -0.15));
    float2 windOffset = u.windDirAndSpeed.zw;
    float gustAmt = u.gustAndTurbulence.x;
    float time = u.cameraRightAndTime.w;
    float2 advected = rootPos.xz * 0.25 - windOffset;
    float g1 = valueNoise2D(advected);
    float g2 = valueNoise2D(advected * 2.0 + float2(6.1, -2.4) - windOffset * 0.55);
    float gustRibbon = smoothstep(0.30, 0.80, g1 * 0.65 + g2 * 0.35);

    float2 crossDir = float2(-windDir.y, windDir.x);
    float wander = (valueNoise2D(rootPos.xz * 0.36 - windOffset * 0.45 + 6.4) - 0.5) * 0.09;
    float reedSway = sin(time * 0.95 + rnd.x * 6.28318 + dot(rootPos.xz, float2(1.4, 1.0))) * (0.008 + 0.020 * gustRibbon * gustAmt);
    float2 pushXZ = windDir * (0.06 + gustRibbon * (0.14 + 0.32 * gustAmt))
                  + crossDir * (wander + reedSway);

    float2 screenUV = projectWorldToScreenUV(rootPos + float3(0, 0.30, 0), u);
    if (screenUV.x > -0.15 && screenUV.x < 1.15 && screenUV.y > -0.15 && screenUV.y < 1.15) {
        float2 cPush = sampleCursorBreezeScreenUV(screenUV, impulses, u.cameraForwardAndAspect.w);
        pushXZ += (u.cameraRightAndTime.xyz * cPush.x + float3(0, 0, -cPush.y)).xz * 0.42;
    }

    // Full 360-degree radial fountain splay + outer drooping stems!
    float radialAz = rnd2.y * 6.2831853 + (tuft.y - 0.5) * 1.4;
    float radialSplay = (0.16 + pow(rnd.y, 0.75) * 0.42) * height;
    float2 reachXZ = float2(cos(radialAz), sin(radialAz)) * radialSplay
                   + pushXZ * height * (isSeedOat ? 0.95 : (0.55 + rnd.y * 0.50));

    float reachMag = min(length(reachXZ), height * 0.86);
    if (length(reachXZ) > 1e-4) reachXZ = normalize(reachXZ) * reachMag;

    float erectY = sqrt(max(height * height - reachMag * reachMag * 0.60, height * height * 0.22));
    // Outer dry blades droop deeply toward the sand!
    float droop = isSeedOat ? 0.16 : (0.14 + pow(rnd2.x, 1.2) * 0.42);

    float3 p0 = rootPos;
    float3 p1 = rootPos + float3(reachXZ.x * 0.18, erectY * 0.52, reachXZ.y * 0.18);
    float3 p2 = rootPos + float3(reachXZ.x * 0.64, erectY * 0.96, reachXZ.y * 0.64);
    float3 p3 = rootPos + float3(reachXZ.x, erectY * (1.0 - droop), reachXZ.y);

    const uint SEGS = 7;
    uint seg = min(vid / 2, SEGS);
    bool isCap = (vid == SEGS * 2);
    float side = isCap ? 0.0 : ((vid % 2 == 0) ? -1.0 : 1.0);
    float t = isCap ? 1.0 : (float(seg) / float(SEGS));

    float3 spine = reedBezier(p0, p1, p2, p3, t);
    float3 tang  = normalize(reedBezierTan(p0, p1, p2, p3, t) + float3(0, 1e-4, 0));

    float twist = radialAz + t * (rnd.x - 0.5) * 1.6;
    float3 toCam = normalize(u.cameraPosAndFOV.xyz - spine);
    float3 reedFace = normalize(float3(cos(twist), 0.15, sin(twist)));
    float3 sideAxis = normalize(cross(tang, mix(reedFace, toCam, 0.50)) + float3(1e-4, 0, 0));

    float taper;
    if (isSeedOat) {
        float panicle = sin(clamp((t - 0.72) / 0.28, 0.0, 1.0) * 3.14159);
        taper = 0.72 * (1.0 - t * 0.3) + panicle * 1.60;
    } else {
        taper = (1.0 - pow(t, 1.50)) * (0.78 + 0.22 * smoothstep(0.0, 0.12, t));
    }
    if (!inTuft || isCap) taper = 0.0;

    float3 wp = spine + sideAxis * (side * halfWidth * taper);

    ReedVertexOut out;
    out.position = inTuft ? (u.viewProjMatrix * float4(wp, 1.0)) : float4(2.0, 2.0, 2.0, 1.0);
    out.worldPos = wp;
    out.normal = normalize(cross(sideAxis, tang) + sideAxis * (side * 0.45));
    out.tangent = tang;
    out.reedT = t;
    out.reedCross = side;
    out.isSeedOat = isSeedOat ? 1.0 : 0.0;
    out.dryness = saturate(rnd.x * 0.65 + tuft.y * 0.35);
    out.linearDepth = length(wp - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 duneReedFragment(
    ReedVertexOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float t = saturate(in.reedT);
    if (in.isSeedOat > 0.5 && t > 0.71) {
        float spike = sin(t * 125.0) * 0.5 + 0.5;
        if (abs(in.reedCross) > 0.48 + 0.52 * spike) {
            discard_fragment();
        }
    }

    float3 V = normalize(u.cameraPosAndFOV.xyz - in.worldPos);
    float3 rakingSun = normalize(float3(-0.82, 0.32, -0.45));
    float warmth = u.sunColorAndWarmth.w;

    float3 seaGlaucous = mix(float3(0.018, 0.036, 0.042), float3(0.072, 0.112, 0.072), warmth);
    float3 oliveBlade  = mix(float3(0.025, 0.042, 0.038), float3(0.115, 0.135, 0.062), warmth);
    float3 bleachedOat = mix(float3(0.055, 0.065, 0.078), float3(0.310, 0.240, 0.135), warmth);

    float3 greenMix = mix(seaGlaucous, oliveBlade, in.dryness);
    float strawFrac = (in.isSeedOat > 0.5)
        ? smoothstep(0.55, 0.82, t)
        : saturate(pow(in.dryness, 1.4) * 0.75 + smoothstep(0.60, 1.0, t) * 0.45);
    float3 albedo = mix(greenMix, bleachedOat, strawFrac) * (0.76 + 0.45 * in.dryness);

    float ao = mix(0.18, 1.0, pow(t, 0.80));
    float ndl = saturate((dot(normalize(in.normal), rakingSun) + 0.30) / 1.30);

    float3 sunRad = u.sunColorAndWarmth.rgb * u.sunDirAndIntensity.w;
    float backLit = pow(saturate(dot(-V, rakingSun) * 0.5 + 0.5), 2.4);
    float3 H = normalize(rakingSun + V);
    float TdotH = dot(normalize(in.tangent), H);
    float sheen = pow(sqrt(max(0.0, 1.0 - TdotH * TdotH)), 46.0) * 0.18;

    float3 col = albedo * (u.skyZenithAndFog.rgb * 0.65 + sunRad * (ndl * 0.32 + backLit * 0.42 * t)) * ao
               + sunRad * sheen * ao;
    col = applyAerialFog(col, in.linearDepth, -V, u);
    return float4(col, 1.0);
}

// Pass 4: Saltation Sand Plume Skimming off Sharp Dune Crest
struct SandMistOut {
    float4 position [[position]];
    float2 quadUV;
    float3 tint;
    float alpha;
};

vertex SandMistOut duneSandMistVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float3 rnd = hash31(iid * 104729U + 3U);
    float time = u.cameraRightAndTime.w;
    float prog = fract(rnd.x + u.windDirAndSpeed.z * (0.14 + rnd.x * 0.12));
    float z = mix(2.5, -9.0, rnd.y);
    float crestX = sin(z * 0.28 + 0.65) * 1.45 + 0.25;
    float x = crestX - 0.35 + prog * 2.1;
    float y = duneHeight(float2(crestX, z)) + 0.02 + prog * 0.16 + sin(prog * 8.0 + rnd.z * 6.0) * 0.04;

    float3 center = float3(x, y, z);
    float2 corners[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2( 1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
    };
    float2 q = corners[vid];
    float3 wp = center + u.cameraRightAndTime.xyz * (q.x * 0.34) + u.cameraUpAndDelta.xyz * (q.y * 0.042);

    SandMistOut out;
    out.position = u.viewProjMatrix * float4(wp, 1.0);
    out.quadUV = q;
    out.tint = mix(float3(0.12, 0.18, 0.28), float3(0.85, 0.62, 0.38), u.sunColorAndWarmth.w);
    out.alpha = (0.025 + 0.08 * saturate(u.gustAndTurbulence.x)) * sin(prog * 3.14159);
    return out;
}

fragment float4 duneSandMistFragment(SandMistOut in [[stage_in]]) {
    float d = dot(in.quadUV, in.quadUV);
    if (d > 1.0) discard_fragment();
    float wisp = exp(-d * 3.0) * in.alpha;
    return float4(in.tint * wisp, 0.0);
}
