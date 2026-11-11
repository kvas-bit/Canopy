#include "ShaderShared.h"

// -----------------------------------------------------------------------------
// Scene 5: Wild Meadow — Mixed Grasses, Slender Golden Seed Panicles,
//          Oxeye Daisies, Buttercups, Red Clover & Sunlit Cumulus Sky
// -----------------------------------------------------------------------------

inline float wildMeadowHeight(float2 xz) {
    float rollingHill = exp(-pow((xz.y + 1.8 - xz.x * 0.22) * 0.24, 2.0)) * 1.15;
    float crossSlope  = xz.x * 0.14 - xz.y * 0.045;
    float leftDip     = smoothstep(0.8, -4.2, xz.x - xz.y * 0.18) * -0.62;
    float undulations = (fbm2D(xz * 0.28 + float2(3.1, -1.7)) - 0.5) * 0.36;
    float tussockBump = (valueNoise2D(xz * 1.7) - 0.5) * 0.055;
    return rollingHill + crossSlope + leftDip + undulations + tussockBump - 0.62;
}

struct WildWindSample {
    float2 worldPushXZ;
    float gustWave;
    float flutter;
};

inline WildWindSample evaluateWildWind(
    float3 rootPos,
    float bladePhase,
    constant FrameUniforms& u,
    constant CursorImpulse* impulses
) {
    float2 windDir = normalize(u.windDirAndSpeed.xy + float2(0.82, -0.16));
    float2 windOffset = u.windDirAndSpeed.zw;
    float gustAmt = u.gustAndTurbulence.x;
    float turbAmt = u.gustAndTurbulence.y;
    float time = u.cameraRightAndTime.w;

    float2 advected = rootPos.xz * 0.26 - windOffset;
    float gustA = valueNoise2D(advected);
    float gustB = valueNoise2D(advected * 2.0 + float2(5.7, -2.9) - windOffset * 0.55);
    float gustRibbon = smoothstep(0.30, 0.80, gustA * 0.65 + gustB * 0.35);

    float2 crossDir = float2(-windDir.y, windDir.x);
    float wander = (valueNoise2D(rootPos.xz * 0.36 - windOffset * 0.45 + 9.1) - 0.5) * (0.06 + 0.10 * gustAmt);

    float bladeSway = sin(time * 0.90 + bladePhase * 6.28318 + dot(rootPos.xz, float2(1.4, 1.0)));
    float alongBreath = (bladeSway * 0.5 + 0.5) * (0.014 + 0.040 * gustRibbon * gustAmt);

    float2 pushXZ = windDir * (0.04 + gustRibbon * (0.11 + 0.32 * gustAmt) + alongBreath)
                  + crossDir * wander;

    float2 screenUV = projectWorldToScreenUV(rootPos + float3(0.0, 0.28, 0.0), u);
    if (screenUV.x > -0.15 && screenUV.x < 1.15 && screenUV.y > -0.15 && screenUV.y < 1.15) {
        float2 cursorUVPush = sampleCursorBreezeScreenUV(screenUV, impulses, u.cameraForwardAndAspect.w);
        float3 worldPush = u.cameraRightAndTime.xyz * cursorUVPush.x * 0.52
                         + normalize(float3(u.cameraForwardAndAspect.x, 0.0, u.cameraForwardAndAspect.z)) * cursorUVPush.y * 0.52;
        pushXZ += worldPush.xz;
    }

    float flutter = bladeSway * (0.005 + 0.013 * gustRibbon * (0.4 + turbAmt));

    WildWindSample s;
    s.worldPushXZ = pushXZ;
    s.gustWave = gustRibbon;
    s.flutter = flutter;
    return s;
}

inline float wildCloudFBM(float2 p) {
    float sum = 0.0;
    float amp = 0.52;
    float2x2 rot = float2x2(0.80, -0.60, 0.60, 0.80);
    for (int i = 0; i < 5; ++i) {
        sum += amp * valueNoise2D(p);
        p = rot * p * 2.07 + float2(17.3, 9.2);
        amp *= 0.50;
    }
    return sum;
}

struct WildBackdropOut {
    float4 position [[position]];
    float2 ndc;
};

vertex WildBackdropOut wildMeadowBackdropVertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    WildBackdropOut out;
    out.position = float4(pos[vid], 0.9999, 1.0);
    out.ndc = pos[vid];
    return out;
}

fragment float4 wildMeadowBackdropFragment(
    WildBackdropOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float4 worldFar = u.invViewProjMatrix * float4(in.ndc, 1.0, 1.0);
    float3 rayDir = normalize(worldFar.xyz / max(worldFar.w, 1e-5) - u.cameraPosAndFOV.xyz);
    float3 sunDir = normalize(u.sunDirAndIntensity.xyz);
    float warmth = u.sunColorAndWarmth.w;
    float time = u.cameraRightAndTime.w;

    float elev = clamp((rayDir.y + 0.14) * 2.2, 0.0, 1.0);
    float3 sky = mix(u.skyHorizonAndExposure.rgb, u.skyZenithAndFog.rgb, pow(elev, 0.68));

    float sunDot = max(dot(rayDir, sunDir), 0.0);
    float mieHaze = pow(1.0 - clamp(abs(rayDir.y + 0.04) * 2.8, 0.0, 1.0), 2.8);
    sky += u.sunColorAndWarmth.rgb * mieHaze * (0.08 + 0.14 * pow(sunDot, 3.0)) * u.sunDirAndIntensity.w * 0.25;
    sky += u.sunColorAndWarmth.rgb * pow(sunDot, 22.0) * 0.20 * u.sunDirAndIntensity.w * 0.24;

    if (rayDir.y > -0.18) {
        float domeY = max(rayDir.y + 0.24, 0.085);
        float2 skyPlane = rayDir.xz / domeY;
        float2 drift = float2(time * 0.0080, -time * 0.0032);

        float2 cumUV = skyPlane * 0.44 + drift + float2(1.6, -0.5);
        float baseDensity = wildCloudFBM(cumUV) * 0.80 + wildCloudFBM(cumUV * 2.3 + 4.7) * 0.28;
        float cloudShape = smoothstep(0.47, 0.79, baseDensity) * smoothstep(-0.14, 0.06, rayDir.y);

        if (cloudShape > 0.002) {
            float sunSample = wildCloudFBM(cumUV + sunDir.xz * 0.14);
            float selfShadow = clamp((sunSample - baseDensity) * 3.2 + 0.42, 0.0, 1.0);
            float lightLit = 1.0 - selfShadow * 0.74;

            float3 cloudShadowCol = mix(
                float3(0.020, 0.038, 0.072),
                mix(float3(0.26, 0.22, 0.30), float3(0.35, 0.44, 0.56), warmth),
                0.20 + 0.80 * warmth
            );
            float3 cloudBrightCol = mix(
                float3(0.10, 0.15, 0.24),
                u.sunColorAndWarmth.rgb * float3(1.10, 1.07, 1.02),
                0.22 + 0.78 * warmth
            );
            float3 cloudCol = mix(cloudShadowCol, cloudBrightCol, lightLit);
            sky = mix(sky, cloudCol, cloudShape * 0.84);
        }
    }

    return float4(sky, 1.0);
}

struct WildTerrainOut {
    float4 position [[position]];
    float3 worldPos;
    float linearDepth;
};

vertex WildTerrainOut wildMeadowTerrainVertex(
    uint vid [[vertex_id]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    const uint GRID_X = 96;
    const uint GRID_Z = 96;
    uint quadIdx = vid / 6;
    uint corner = vid % 6;
    uint gx = quadIdx % GRID_X;
    uint gz = quadIdx / GRID_X;

    uint2 offsets[6] = {
        uint2(0, 0), uint2(1, 0), uint2(0, 1),
        uint2(1, 0), uint2(1, 1), uint2(0, 1)
    };
    uint2 cell = uint2(gx, gz) + offsets[corner];
    float fx = float(cell.x) / float(GRID_X);
    float fz = float(cell.y) / float(GRID_Z);

    float z = mix(4.15, -11.2, fz);
    float spread = mix(0.35, 1.28, fz);
    float xCenter = mix(0.05, 0.55, fz);
    float x = xCenter + (fx - 0.5) * 11.4 * spread;
    float y = wildMeadowHeight(float2(x, z)) - 0.03;

    float3 worldPos = float3(x, y, z);
    WildTerrainOut out;
    out.position = u.viewProjMatrix * float4(worldPos, 1.0);
    out.worldPos = worldPos;
    out.linearDepth = length(worldPos - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 wildMeadowTerrainFragment(
    WildTerrainOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float patch = fbm2D(in.worldPos.xz * 2.4);
    float strawLitter = valueNoise2D(in.worldPos.xz * 9.5);
    float warmth = u.sunColorAndWarmth.w;

    float3 darkLoam  = mix(float3(0.004, 0.008, 0.008), float3(0.016, 0.022, 0.009), warmth);
    float3 dryThatch = mix(float3(0.010, 0.014, 0.012), float3(0.045, 0.042, 0.018), warmth);
    float3 mossSoil  = mix(float3(0.006, 0.016, 0.012), float3(0.022, 0.045, 0.012), warmth);

    float3 base = mix(darkLoam, mossSoil, patch);
    base = mix(base, dryThatch, smoothstep(0.55, 0.85, strawLitter) * 0.55);
    float3 lit = base * (0.45 + 0.35 * u.sunDirAndIntensity.w * 0.28);

    float3 V = normalize(u.cameraPosAndFOV.xyz - in.worldPos);
    lit = applyAerialFog(lit, in.linearDepth, -V, u);
    return float4(lit, 1.0);
}

struct WildGrassOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float3 tangent;
    float bladeT;
    float bladeCross;
    float speciesMix;
    float colorSeed;
    float gustHighlight;
    float linearDepth;
};

inline float3 wildBezier(float3 p0, float3 p1, float3 p2, float3 p3, float t) {
    float it = 1.0 - t;
    return it*it*it*p0 + 3.0*it*it*t*p1 + 3.0*it*t*t*p2 + t*t*t*p3;
}

inline float3 wildBezierTan(float3 p0, float3 p1, float3 p2, float3 p3, float t) {
    float it = 1.0 - t;
    return 3.0*it*it*(p1 - p0) + 6.0*it*t*(p2 - p1) + 3.0*t*t*(p3 - p2);
}

vertex WildGrassOut wildMeadowGrassVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms& u [[buffer(0)]],
    constant CursorImpulse* impulses [[buffer(1)]]
) {
    const uint COLS = 320;
    const uint ROWS = 264;
    uint col = iid % COLS;
    uint row = iid / COLS;

    float3 rnd = hash31(iid * 196613U + 17U);
    float2 rnd2 = hash21u(iid * 9781U + 53U);
    float rnd3 = hash11(iid * 49999U + 7U);

    float uCol = (float(col) + rnd.x) / float(COLS);
    float uRow = (float(row) + rnd.y) / float(ROWS);

    float zDepthBias = pow(uRow, 1.38);
    float z = mix(4.25, -12.4, zDepthBias);
    float frustumSpread = mix(0.38, 1.38, zDepthBias);
    float xCenter = mix(0.05, 0.55, zDepthBias);
    float x = xCenter + (uCol - 0.5) * 12.6 * frustumSpread;

    float2 tuftWarp = float2(
        valueNoise2D(float2(x, z) * 1.55 + float2(5.2, 8.1)) - 0.5,
        valueNoise2D(float2(x, z) * 1.55 + float2(16.4, -3.7)) - 0.5
    );
    x += tuftWarp.x * 0.14;
    z += tuftWarp.y * 0.14;

    float groundY = wildMeadowHeight(float2(x, z));
    float3 rootPos = float3(x, groundY - 0.03, z);

    float patchGrowth = valueNoise2D(float2(x, z) * 0.45 + float2(2.1, 8.4));
    bool isSeedCulm = (rnd3 > 0.89) && (patchGrowth > 0.40);
    bool isDryStraw = (!isSeedCulm) && (rnd3 > 0.74);

    float bladeHeight = isSeedCulm
        ? (0.64 + rnd.z * 0.34 + patchGrowth * 0.16)
        : (isDryStraw ? (0.30 + rnd.z * 0.28) : (0.38 + rnd.z * 0.42 + patchGrowth * 0.22));

    float distToCam = length(rootPos - u.cameraPosAndFOV.xyz);
    float lodWidthScale = clamp(distToCam * 0.076, 0.98, 1.90);
    float rawHalfW = isSeedCulm ? 0.0020 : (0.0032 + rnd2.x * 0.0022);
    float baseHalfWidth = rawHalfW * lodWidthScale;

    WildWindSample wind = evaluateWildWind(rootPos, rnd.x, u, impulses);

    float radialAngle = rnd2.y * 6.2831853 + tuftWarp.x * 1.6;
    float splayStrength = isSeedCulm ? (0.06 + rnd.y * 0.14) : (0.12 + pow(rnd.y, 0.8) * 0.34);
    float2 radialLean = float2(cos(radialAngle), sin(radialAngle)) * splayStrength * bladeHeight;

    float stiffness = isSeedCulm ? (1.35 + rnd.z * 0.55) : (0.58 + rnd.z * 0.85);
    float2 windDeflect = (wind.worldPushXZ / stiffness) * bladeHeight * 1.15
                       + float2(-wind.worldPushXZ.y, wind.worldPushXZ.x) * wind.flutter * bladeHeight;

    float2 totalReachXZ = radialLean + windDeflect;
    float reachMag = length(totalReachXZ);
    float maxReach = bladeHeight * 0.84;
    if (reachMag > maxReach) {
        totalReachXZ *= (maxReach / reachMag);
        reachMag = maxReach;
    }

    float erectness = sqrt(max(bladeHeight * bladeHeight - reachMag * reachMag * 0.62, bladeHeight * bladeHeight * 0.24));
    float droopAmt = isSeedCulm ? (0.08 + rnd2.x * 0.10) : (0.10 + pow(rnd2.x, 1.4) * 0.28);

    float3 p0 = rootPos;
    float3 p1 = rootPos + float3(totalReachXZ.x * 0.18, erectness * 0.48, totalReachXZ.y * 0.18);
    float3 p2 = rootPos + float3(totalReachXZ.x * 0.62, erectness * 0.92, totalReachXZ.y * 0.62);
    float3 p3 = rootPos + float3(totalReachXZ.x, erectness * (1.0 - droopAmt), totalReachXZ.y);

    const uint SEGMENTS = 7;
    uint seg = min(vid / 2, SEGMENTS);
    bool isTipCap = (vid == SEGMENTS * 2);
    float side = isTipCap ? 0.0 : ((vid % 2 == 0) ? -1.0 : 1.0);
    float t = isTipCap ? 1.0 : (float(seg) / float(SEGMENTS));

    float3 spinePos = wildBezier(p0, p1, p2, p3, t);
    float3 tangent = normalize(wildBezierTan(p0, p1, p2, p3, t) + float3(0.0, 1e-4, 0.0));

    float twist = radialAngle + t * (rnd.x - 0.5) * 1.8;
    float3 toCam = normalize(u.cameraPosAndFOV.xyz - spinePos);
    float3 naturalFace = normalize(float3(cos(twist), 0.15, sin(twist)));
    float3 widthAxis = normalize(cross(tangent, mix(naturalFace, toCam, 0.48)) + float3(1e-4, 0.0, 0.0));

    float taper;
    if (isSeedCulm) {
        float stemProfile = 0.70 * (1.0 - t * 0.35);
        float panicleEnv = sin(clamp((t - 0.72) / 0.28, 0.0, 1.0) * 3.14159);
        taper = stemProfile + panicleEnv * 1.65;
    } else {
        taper = (1.0 - pow(t, 1.55)) * (0.78 + 0.22 * smoothstep(0.0, 0.12, t));
    }
    if (isTipCap) taper = 0.0;

    float3 vertexWorld = spinePos + widthAxis * (side * baseHalfWidth * taper);
    float3 flatNormal = normalize(cross(widthAxis, tangent));
    if (dot(flatNormal, toCam) < 0.0) flatNormal = -flatNormal;
    float3 curvedNormal = normalize(flatNormal + widthAxis * (side * 0.52));

    WildGrassOut out;
    out.position = u.viewProjMatrix * float4(vertexWorld, 1.0);
    out.worldPos = vertexWorld;
    out.normal = curvedNormal;
    out.tangent = tangent;
    out.bladeT = t;
    out.bladeCross = side;
    out.speciesMix = isSeedCulm ? 0.95 : (isDryStraw ? 0.76 : 0.25);
    out.colorSeed = saturate(patchGrowth * 0.42 + rnd.x * 0.58);
    out.gustHighlight = wind.gustWave;
    out.linearDepth = length(vertexWorld - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 wildMeadowGrassFragment(
    WildGrassOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float3 V = normalize(u.cameraPosAndFOV.xyz - in.worldPos);
    float3 L = normalize(u.sunDirAndIntensity.xyz);
    float3 N = normalize(in.normal);
    float3 T = normalize(in.tangent);

    float t = saturate(in.bladeT);
    float warmth = u.sunColorAndWarmth.w;

    bool isSeedCulm = (in.speciesMix > 0.88);
    bool isDryStraw = (!isSeedCulm) && (in.speciesMix > 0.68);

    if (isSeedCulm && t > 0.72) {
        float spikePhase = sin(t * 145.0) * 0.5 + 0.5;
        if (abs(in.bladeCross) > 0.50 + 0.50 * spikePhase) {
            discard_fragment();
        }
    }

    float3 rootDark    = mix(float3(0.004, 0.010, 0.010), float3(0.010, 0.024, 0.007), warmth);
    float3 oliveGreen  = mix(float3(0.014, 0.038, 0.028), float3(0.046, 0.118, 0.022), warmth);
    float3 sageGreen   = mix(float3(0.018, 0.044, 0.038), float3(0.052, 0.132, 0.042), warmth);
    float3 freshTip    = mix(float3(0.028, 0.068, 0.048), float3(0.125, 0.220, 0.036), warmth);
    float3 wheatStraw  = mix(float3(0.032, 0.038, 0.042), float3(0.195, 0.158, 0.068), warmth);
    float3 seedGold    = mix(float3(0.042, 0.048, 0.055), float3(0.245, 0.198, 0.088), warmth);

    float3 albedo;
    if (isSeedCulm) {
        albedo = mix(mix(oliveGreen, wheatStraw, 0.35), seedGold, smoothstep(0.68, 0.82, t));
    } else if (isDryStraw) {
        albedo = mix(oliveGreen * 0.7, wheatStraw, smoothstep(0.15, 0.85, t));
    } else {
        float3 midLeaf = mix(oliveGreen, sageGreen, in.colorSeed);
        albedo = mix(rootDark, midLeaf, smoothstep(0.0, 0.50, t));
        albedo = mix(albedo, mix(freshTip, wheatStraw, smoothstep(0.82, 1.0, in.colorSeed) * 0.40), smoothstep(0.55, 1.0, t));
    }

    albedo *= (0.92 + 0.08 * sin(in.bladeCross * 18.0)) * (0.72 + 0.55 * in.colorSeed);

    float clumpShadow = smoothstep(0.20, 0.80, fbm2D(in.worldPos.xz * 0.85 + float2(3.7, -2.1)));
    float rootAO = mix(0.035, 1.0, pow(t, 1.05)) * (0.58 + 0.52 * clumpShadow);

    float ndl = saturate((dot(N, L) + 0.30) / 1.30);
    float3 sunRadiance = u.sunColorAndWarmth.rgb * u.sunDirAndIntensity.w;

    float backScatter = pow(saturate(dot(-V, L) * 0.5 + 0.5), 2.8);
    float translucency = (isSeedCulm && t > 0.70) ? 0.80 : (pow(t, 1.35) * 0.65);
    float3 sssTint = isSeedCulm ? seedGold : mix(albedo * 1.4, float3(0.22, 0.34, 0.045), 0.45 * warmth);
    float3 subsurface = sssTint * sunRadiance * (0.08 + 0.48 * backScatter) * translucency * rootAO;

    float3 H = normalize(L + V);
    float TdotH = dot(T, H);
    float cuticleSpec = pow(sqrt(max(0.0, 1.0 - TdotH * TdotH)), 48.0) * smoothstep(0.20, 0.90, t);
    float3 skySpec = mix(u.skyHorizonAndExposure.rgb, u.sunColorAndWarmth.rgb, 0.45)
                   * cuticleSpec * (0.35 + 0.65 * in.gustHighlight) * 0.16 * rootAO;

    float skyUp = saturate(N.y * 0.5 + 0.5);
    float3 skyFill = mix(u.groundBounceAndAmbient.rgb, u.skyZenithAndFog.rgb * 0.55 + u.skyHorizonAndExposure.rgb * 0.45, skyUp);
    float3 ambient = albedo * skyFill * (u.groundBounceAndAmbient.w * 1.35) * rootAO;
    float3 direct  = albedo * sunRadiance * ndl * 0.42 * rootAO;

    float3 color = ambient + direct + subsurface + skySpec;
    color = applyAerialFog(color, in.linearDepth, -V, u);
    return float4(color, 1.0);
}

struct WildFlowerOut {
    float4 position [[position]];
    float2 quadUV;
    float3 worldPos;
    float3 discNormal;
    float flowerType;
    float petalSeed;
    float linearDepth;
};

vertex WildFlowerOut wildMeadowFlowerVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms& u [[buffer(0)]],
    constant CursorImpulse* impulses [[buffer(1)]]
) {
    float3 rnd = hash31(iid * 2654435761U + 101U);
    float2 rnd2 = hash21u(iid * 40503U + 29U);

    bool isForegroundBokeh = (iid < 32U);
    float x;
    float z;
    bool culled = false;

    if (isForegroundBokeh) {
        x = mix(-1.45, 1.65, rnd.x);
        z = mix(3.35, 1.85, rnd.y);
    } else {
        uint idx = iid - 32U;
        const uint COLS = 72;
        const uint ROWS = 50;
        uint col = idx % COLS;
        uint row = idx / COLS;

        float uCol = (float(col) + rnd.x) / float(COLS);
        float uRow = (float(row) + rnd.y) / float(ROWS);

        float zBias = pow(uRow, 1.2);
        z = mix(2.4, -10.2, zBias);
        float spread = mix(0.42, 1.32, zBias);
        x = mix(0.08, 0.55, zBias) + (uCol - 0.5) * 11.4 * spread;

        float cluster = fbm2D(float2(x, z) * 0.65 + float2(-4.1, 2.8));
        culled = (cluster < 0.49 && rnd2.x > 0.16);
    }

    float groundY = wildMeadowHeight(float2(x, z));
    float3 rootPos = float3(x, groundY, z);
    WildWindSample wind = evaluateWildWind(rootPos, rnd.z, u, impulses);

    float stemHeight = isForegroundBokeh ? (0.34 + rnd.z * 0.28) : (0.32 + rnd.z * 0.36);
    float2 bendXZ = float2((rnd.x - 0.5) * 0.16, (rnd.y - 0.5) * 0.16)
                  + wind.worldPushXZ * 0.75
                  + float2(-wind.worldPushXZ.y, wind.worldPushXZ.x) * wind.flutter;
    float bendLen = min(length(bendXZ), stemHeight * 0.72);
    if (length(bendXZ) > 1e-4) bendXZ = normalize(bendXZ) * bendLen;

    float headY = sqrt(max(stemHeight * stemHeight - bendLen * bendLen * 0.65, 0.08));
    float3 blossomCenter = rootPos + float3(bendXZ.x, headY, bendXZ.y);

    float3 tiltDir = normalize(float3(bendXZ.x * 1.2 + (rnd2.x - 0.5) * 0.65, 0.72 + rnd2.y * 0.45, bendXZ.y * 1.2 + 0.35));
    float3 toCam = normalize(u.cameraPosAndFOV.xyz - blossomCenter);
    float3 flowerN = normalize(mix(tiltDir, toCam, isForegroundBokeh ? 0.65 : 0.32));
    float3 axisU = normalize(cross(float3(0.0, 1.0, 0.1), flowerN) + float3(1e-4, 0.0, 0.0));
    float3 axisV = normalize(cross(flowerN, axisU));

    float2 corners[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2( 1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
    };
    float2 q = corners[vid];

    float fType = (rnd2.y > 0.84) ? 1.0 : ((rnd2.y > 0.74) ? 2.0 : 0.0);
    float baseRadius = (fType > 0.5) ? (0.013 + rnd2.x * 0.008) : (0.016 + rnd2.x * 0.011);
    if (isForegroundBokeh) baseRadius *= 1.20;
    float radius = culled ? 0.0 : baseRadius;

    float cupDepth = (1.0 - dot(q, q)) * radius * 0.18;
    float3 worldPos = blossomCenter + (axisU * q.x + axisV * q.y) * radius - flowerN * cupDepth;

    WildFlowerOut out;
    out.position = culled ? float4(2.0, 2.0, 2.0, 1.0) : (u.viewProjMatrix * float4(worldPos, 1.0));
    out.quadUV = q;
    out.worldPos = worldPos;
    out.discNormal = flowerN;
    out.flowerType = fType;
    out.petalSeed = rnd.x;
    out.linearDepth = length(blossomCenter - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 wildMeadowFlowerFragment(
    WildFlowerOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float2 p = in.quadUV;
    float r = length(p);
    if (r > 1.0) discard_fragment();

    float angle = atan2(p.y, p.x) + in.petalSeed * 6.28318;
    float warmth = u.sunColorAndWarmth.w;
    float3 col;

    if (in.flowerType < 0.5) {
        float rays = 13.0;
        float petalWave = abs(cos(angle * rays * 0.5));
        if (r > 0.28 + 0.70 * pow(petalWave, 1.55)) discard_fragment();
        float centerDisc = 1.0 - smoothstep(0.22, 0.30, r);
        float floretBump = valueNoise2D(p * 26.0) * 0.22;
        float3 ivoryPetal = mix(float3(0.22, 0.30, 0.44), float3(1.18, 1.18, 1.10), 0.20 + 0.80 * warmth);
        float3 goldCenter = mix(float3(0.18, 0.16, 0.06), float3(0.92, 0.62, 0.10) * (0.85 + floretBump), 0.20 + 0.80 * warmth);
        col = mix(ivoryPetal * (0.74 + 0.26 * smoothstep(0.26, 0.90, r)), goldCenter, centerDisc);
    } else if (in.flowerType < 1.5) {
        float petalWave = cos(angle * 5.0) * 0.5 + 0.5;
        if (r > 0.68 + 0.26 * smoothstep(0.15, 0.85, petalWave)) discard_fragment();
        col = mix(float3(0.16, 0.18, 0.08), float3(1.05, 0.78, 0.08), 0.20 + 0.80 * warmth) * (0.75 + 0.45 * smoothstep(0.15, 0.75, r));
    } else {
        float fluff = valueNoise2D(p * 14.0 + in.petalSeed * 10.0);
        if (r > 0.72 + fluff * 0.24) discard_fragment();
        col = mix(float3(0.14, 0.12, 0.22), float3(0.68, 0.36, 0.52), 0.22 + 0.78 * warmth) * (0.65 + 0.55 * fluff);
    }

    float3 L = normalize(u.sunDirAndIntensity.xyz);
    float ndl = saturate(dot(normalize(in.discNormal), L) * 0.55 + 0.45);
    float3 sunRad = u.sunColorAndWarmth.rgb * u.sunDirAndIntensity.w;
    float3 lit = col * (u.skyHorizonAndExposure.rgb * 0.48 + sunRad * ndl * 0.32);

    float3 V = normalize(u.cameraPosAndFOV.xyz - in.worldPos);
    lit = applyAerialFog(lit, in.linearDepth, -V, u);
    return float4(lit, 1.0);
}
