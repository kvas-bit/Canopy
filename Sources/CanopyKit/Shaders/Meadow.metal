#include "ShaderShared.h"

// -----------------------------------------------------------------------------
// Scene 1: Grass-Swept Meadow (OG Lush Wind-Swept Emerald Fescue + Chamomile
//          paired with Real Atmospheric Cloud Sky & Crisp Hardware Depth)
// -----------------------------------------------------------------------------

inline float meadowHeight(float2 xz) {
    float diagSlope = xz.x * 0.24 - xz.y * 0.065;
    float mainSwell = exp(-pow((xz.y + 0.95 - xz.x * 0.34) * 0.42, 2.0)) * 0.68;
    float leftValley = smoothstep(0.15, -3.1, xz.x - xz.y * 0.25) * -0.92;
    float hummock = (fbm2D(xz * 0.38 + float2(4.2, -1.8)) - 0.5) * 0.38;
    float micro = (valueNoise2D(xz * 2.1) - 0.5) * 0.05;
    return diagSlope + mainSwell + leftValley + hummock + micro - 0.30;
}

struct MeadowWindSample {
    float2 worldPushXZ;
    float gustWave;
    float flutter;
};

inline MeadowWindSample evaluateMeadowWind(
    float3 rootPos,
    float bladePhase,
    constant FrameUniforms& u,
    constant CursorImpulse* impulses
) {
    float2 windDir = normalize(u.windDirAndSpeed.xy + float2(0.88, -0.14));
    float2 windOffset = u.windDirAndSpeed.zw;
    float gustAmt = u.gustAndTurbulence.x;
    float turbAmt = u.gustAndTurbulence.y;
    float time = u.cameraRightAndTime.w;

    // Pure CPU-integrated 2D advection (never accelerates over long uptime!)
    float2 advected = rootPos.xz * 0.28 - windOffset;
    float gustA = valueNoise2D(advected);
    float gustB = valueNoise2D(advected * 2.05 + float2(7.3, -3.1) - windOffset * 0.55);
    float gustRibbon = smoothstep(0.30, 0.80, gustA * 0.65 + gustB * 0.35);

    float2 crossDir = float2(-windDir.y, windDir.x);
    float wander = (valueNoise2D(rootPos.xz * 0.38 - windOffset * 0.45 + 11.4) - 0.5) * (0.06 + 0.10 * gustAmt);

    float bladeSway = sin(time * 0.95 + bladePhase * 6.28318 + dot(rootPos.xz, float2(1.5, 1.1)));
    float alongBreath = (bladeSway * 0.5 + 0.5) * (0.015 + 0.045 * gustRibbon * gustAmt);

    float2 pushXZ = windDir * (0.04 + gustRibbon * (0.12 + 0.34 * gustAmt) + alongBreath)
                  + crossDir * wander;

    float2 screenUV = projectWorldToScreenUV(rootPos + float3(0.0, 0.30, 0.0), u);
    if (screenUV.x > -0.15 && screenUV.x < 1.15 && screenUV.y > -0.15 && screenUV.y < 1.15) {
        float2 cursorUVPush = sampleCursorBreezeScreenUV(screenUV, impulses, u.cameraForwardAndAspect.w);
        float3 worldPush = u.cameraRightAndTime.xyz * cursorUVPush.x * 0.55
                         + normalize(float3(u.cameraForwardAndAspect.x, 0.0, u.cameraForwardAndAspect.z)) * cursorUVPush.y * 0.55;
        pushXZ += worldPush.xz;
    }

    float flutter = bladeSway * (0.005 + 0.014 * gustRibbon * (0.4 + turbAmt));

    MeadowWindSample s;
    s.worldPushXZ = pushXZ;
    s.gustWave = gustRibbon;
    s.flutter = flutter;
    return s;
}

inline float meadowCloudFBM(float2 p) {
    float sum = 0.0;
    float amp = 0.52;
    float2x2 rot = float2x2(0.80, -0.60, 0.60, 0.80);
    for (int i = 0; i < 5; ++i) {
        sum += amp * valueNoise2D(p);
        p = rot * p * 2.06 + float2(14.3, 8.7);
        amp *= 0.50;
    }
    return sum;
}

// -----------------------------------------------------------------------------
// Pass 1: Real Atmospheric Sky with Sunlit Billowy Cumulus & Distant Foothills
// -----------------------------------------------------------------------------

struct BackdropVertexOut {
    float4 position [[position]];
    float2 ndc;
};

vertex BackdropVertexOut meadowBackdropVertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    BackdropVertexOut out;
    out.position = float4(pos[vid], 0.9999, 1.0);
    out.ndc = pos[vid];
    return out;
}

fragment float4 meadowBackdropFragment(
    BackdropVertexOut in [[stage_in]],
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
    float horizonGlow = pow(1.0 - clamp(abs(rayDir.y + 0.04) * 2.8, 0.0, 1.0), 2.6);
    sky += u.sunColorAndWarmth.rgb * horizonGlow * (0.09 + 0.14 * pow(sunDot, 2.5)) * u.sunDirAndIntensity.w * 0.25;
    sky += u.sunColorAndWarmth.rgb * pow(sunDot, 20.0) * 0.20 * u.sunDirAndIntensity.w * 0.24;

    // Billowy sunlit cumulus & high cirrus clouds clearly visible across upper-left sky
    if (rayDir.y > -0.18) {
        float domeY = max(rayDir.y + 0.24, 0.085);
        float2 skyPlane = rayDir.xz / domeY;
        float2 drift = float2(time * 0.0075, -time * 0.003);

        float cirrus = meadowCloudFBM(skyPlane * 0.65 + drift * 0.45 + float2(3.4, 1.9));
        float cirrusMask = smoothstep(0.54, 0.84, cirrus) * smoothstep(-0.14, 0.10, rayDir.y);
        float3 cirrusTint = mix(float3(0.08, 0.14, 0.26), float3(0.95, 0.96, 0.98), 0.20 + 0.80 * warmth);
        sky = mix(sky, cirrusTint, cirrusMask * 0.30);

        float2 cumUV = skyPlane * 0.44 + drift + float2(1.8, -0.7);
        float baseDensity = meadowCloudFBM(cumUV) * 0.80 + meadowCloudFBM(cumUV * 2.35 + 5.1) * 0.28;
        float cloudShape = smoothstep(0.47, 0.79, baseDensity) * smoothstep(-0.14, 0.06, rayDir.y);

        if (cloudShape > 0.002) {
            float sunSample = meadowCloudFBM(cumUV + sunDir.xz * 0.14);
            float selfShadow = clamp((sunSample - baseDensity) * 3.4 + 0.42, 0.0, 1.0);
            float litFrac = 1.0 - selfShadow * 0.72;

            float3 cloudBaseShadow = mix(
                float3(0.022, 0.040, 0.078),
                mix(float3(0.28, 0.24, 0.32), float3(0.36, 0.45, 0.58), warmth),
                0.20 + 0.80 * warmth
            );
            float3 cloudSunlit = mix(
                float3(0.11, 0.16, 0.26),
                u.sunColorAndWarmth.rgb * float3(1.12, 1.09, 1.04),
                0.22 + 0.78 * warmth
            );
            float3 cloudCol = mix(cloudBaseShadow, cloudSunlit, litFrac);
            sky = mix(sky, cloudCol, cloudShape * 0.84);
        }
    }

    return float4(sky, 1.0);
}

// -----------------------------------------------------------------------------
// Pass 2: Dark Meadow Soil / Moss Undergrowth
// -----------------------------------------------------------------------------

struct TerrainVertexOut {
    float4 position [[position]];
    float3 worldPos;
    float linearDepth;
};

vertex TerrainVertexOut meadowTerrainVertex(
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

    // Keep terrain mesh strictly tucked inside the grass blade coverage footprint so bare ground never pokes past the horizon!
    float z = mix(4.15, -8.85, fz);
    float spread = mix(0.38, 1.18, fz);
    float xCenter = mix(0.12, 0.88, fz);
    float x = xCenter + (fx - 0.5) * 10.6 * spread;
    float y = meadowHeight(float2(x, z)) - 0.03;

    float3 worldPos = float3(x, y, z);
    TerrainVertexOut out;
    out.position = u.viewProjMatrix * float4(worldPos, 1.0);
    out.worldPos = worldPos;
    out.linearDepth = length(worldPos - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 meadowTerrainFragment(
    TerrainVertexOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float3 V = normalize(u.cameraPosAndFOV.xyz - in.worldPos);
    float warmth = u.sunColorAndWarmth.w;
    float patch = fbm2D(in.worldPos.xz * 2.5);
    float fineBlades = valueNoise2D(in.worldPos.xz * 28.0);
    // Match exact deep grass root shadow tone so terrain never shows as a contrasting flat floor
    float3 deepRootShadow = mix(float3(0.002, 0.008, 0.006), float3(0.005, 0.018, 0.004), warmth);
    float3 midRootGreen   = mix(float3(0.006, 0.020, 0.013), float3(0.014, 0.048, 0.008), warmth);
    float3 lit = mix(deepRootShadow, midRootGreen, patch * (0.45 + 0.55 * fineBlades))
               * (u.groundBounceAndAmbient.w * 0.85 + u.sunDirAndIntensity.w * 0.08);
    lit = applyAerialFog(lit, in.linearDepth, -V, u);
    return float4(lit, 1.0);
}

// -----------------------------------------------------------------------------
// Pass 3: 86,000 Lush Wind-Swept Emerald Fescue Blades (Natural Varied Splay)
// -----------------------------------------------------------------------------

struct GrassVertexOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float3 tangent;
    float bladeT;
    float bladeCross;
    float bladeTone;
    float gustHighlight;
    float linearDepth;
};

inline float3 evalCubicBezier(float3 p0, float3 p1, float3 p2, float3 p3, float t) {
    float it = 1.0 - t;
    return it * it * it * p0
         + 3.0 * it * it * t * p1
         + 3.0 * it * t * t * p2
         + t * t * t * p3;
}

inline float3 evalCubicBezierTangent(float3 p0, float3 p1, float3 p2, float3 p3, float t) {
    float it = 1.0 - t;
    return 3.0 * it * it * (p1 - p0)
         + 6.0 * it * t * (p2 - p1)
         + 3.0 * t * t * (p3 - p2);
}

vertex GrassVertexOut meadowGrassVertex(
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

    float uCol = (float(col) + rnd.x) / float(COLS);
    float uRow = (float(row) + rnd.y) / float(ROWS);

    float zDepthBias = pow(uRow, 1.34);
    float z = mix(4.25, -10.2, zDepthBias);
    float frustumSpread = mix(0.46, 1.34, zDepthBias);
    float xCenter = mix(0.08, 0.80, zDepthBias);
    float x = xCenter + (uCol - 0.5) * 12.6 * frustumSpread;

    // Continuous C1 noise warp for organic clumping (ZERO grid-cell boundary trenches!)
    float2 tuftWarp = float2(
        valueNoise2D(float2(x, z) * 1.65 + float2(3.1, 7.4)) - 0.5,
        valueNoise2D(float2(x, z) * 1.65 + float2(14.8, -2.9)) - 0.5
    );
    x += tuftWarp.x * 0.14;
    z += tuftWarp.y * 0.14;

    float groundY = meadowHeight(float2(x, z));
    float3 rootPos = float3(x, groundY - 0.03, z);

    float patchLush = valueNoise2D(float2(x, z) * 0.55 + float2(2.1, 8.4));
    bool tallShoot = (rnd2.y > 0.80);
    float bladeHeight = (0.44 + rnd.z * 0.38 + patchLush * 0.22 + (tallShoot ? 0.22 : 0.0));

    float distToCam = length(rootPos - u.cameraPosAndFOV.xyz);
    float lodBoost = clamp(distToCam * 0.080, 0.98, 1.85);
    float baseHalfWidth = (0.0032 + rnd2.x * 0.0018) * lodBoost;

    MeadowWindSample wind = evaluateMeadowWind(rootPos, rnd.x, u, impulses);

    float radialAngle = rnd2.y * 6.2831853 + tuftWarp.x * 1.8;
    float splayMag = (0.08 + rnd.y * 0.22) * bladeHeight;
    float2 naturalLean = float2(cos(radialAngle), sin(radialAngle)) * splayMag
                       + float2(0.11, -0.02) * bladeHeight;

    float stiffness = (tallShoot ? 1.15 : 0.78) + rnd.z * 0.58;
    float2 totalBendXZ = naturalLean + (wind.worldPushXZ / stiffness) * bladeHeight * 1.25;
    totalBendXZ += float2(-wind.worldPushXZ.y, wind.worldPushXZ.x) * wind.flutter * bladeHeight;

    float bendMag = length(totalBendXZ);
    float maxBend = bladeHeight * 0.80;
    if (bendMag > maxBend) {
        totalBendXZ *= (maxBend / bendMag);
        bendMag = maxBend;
    }

    float tipY = sqrt(max(bladeHeight * bladeHeight - bendMag * bendMag * 0.65, bladeHeight * bladeHeight * 0.26));
    float droop = 0.08 + pow(rnd2.x, 1.4) * 0.20;

    float3 p0 = rootPos;
    float3 p1 = rootPos + float3(totalBendXZ.x * 0.16, tipY * 0.46, totalBendXZ.y * 0.16);
    float3 p2 = rootPos + float3(totalBendXZ.x * 0.60, tipY * 0.90, totalBendXZ.y * 0.60);
    float3 p3 = rootPos + float3(totalBendXZ.x, tipY * (1.0 - droop), totalBendXZ.y);

    const uint SEGMENTS = 7;
    uint seg = min(vid / 2, SEGMENTS);
    bool isTipCap = (vid == SEGMENTS * 2);
    float side = isTipCap ? 0.0 : ((vid % 2 == 0) ? -1.0 : 1.0);
    float t = isTipCap ? 1.0 : (float(seg) / float(SEGMENTS));

    float3 spinePos = evalCubicBezier(p0, p1, p2, p3, t);
    float3 tangent = normalize(evalCubicBezierTangent(p0, p1, p2, p3, t) + float3(0.0, 1e-4, 0.0));

    float twist = radialAngle + t * (rnd.x - 0.5) * 1.5;
    float3 toCam = normalize(u.cameraPosAndFOV.xyz - spinePos);
    float3 bladeFace = normalize(float3(cos(twist), 0.12, sin(twist)));
    float3 widthAxis = normalize(cross(tangent, mix(bladeFace, toCam, 0.56)) + float3(1e-4, 0.0, 0.0));

    float taper = isTipCap ? 0.0 : ((1.0 - pow(t, 1.48)) * (0.76 + 0.24 * smoothstep(0.0, 0.10, t)));
    float3 vertexWorld = spinePos + widthAxis * (side * baseHalfWidth * taper);

    float3 flatNormal = normalize(cross(widthAxis, tangent));
    if (dot(flatNormal, toCam) < 0.0) {
        flatNormal = -flatNormal;
    }
    float3 curvedNormal = normalize(flatNormal + widthAxis * (side * 0.48));

    GrassVertexOut out;
    out.position = u.viewProjMatrix * float4(vertexWorld, 1.0);
    out.worldPos = vertexWorld;
    out.normal = curvedNormal;
    out.tangent = tangent;
    out.bladeT = t;
    out.bladeCross = side;
    out.bladeTone = saturate(patchLush * 0.45 + rnd.x * 0.55);
    out.gustHighlight = wind.gustWave;
    out.linearDepth = length(vertexWorld - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 meadowGrassFragment(
    GrassVertexOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float3 V = normalize(u.cameraPosAndFOV.xyz - in.worldPos);
    float3 L = normalize(u.sunDirAndIntensity.xyz);
    float3 N = normalize(in.normal);
    float3 T = normalize(in.tangent);

    float t = saturate(in.bladeT);
    float warmth = u.sunColorAndWarmth.w;

    float3 deepRoot  = mix(float3(0.003, 0.011, 0.009), float3(0.006, 0.024, 0.005), warmth);
    float3 richMidA  = mix(float3(0.010, 0.038, 0.024), float3(0.024, 0.095, 0.012), warmth);
    float3 richMidB  = mix(float3(0.016, 0.055, 0.030), float3(0.052, 0.162, 0.018), warmth);
    float3 sunlitTip = mix(float3(0.030, 0.092, 0.048), float3(0.145, 0.305, 0.030), warmth);

    float bladeVar = 0.62 + 0.68 * in.bladeTone;
    float3 midAlbedo = mix(richMidA, richMidB, in.bladeTone) * bladeVar;
    float3 albedo = mix(deepRoot, midAlbedo, smoothstep(0.0, 0.54, t));
    albedo = mix(albedo, sunlitTip * bladeVar, smoothstep(0.54, 1.0, t));

    float pocketShadow = smoothstep(0.22, 0.78, fbm2D(in.worldPos.xz * 0.92 + float2(3.7, -2.1)));
    float rootAO = mix(0.024, 1.0, pow(t, 1.18)) * (0.55 + 0.55 * pocketShadow);
    float edgeShade = 0.84 + 0.22 * (1.0 - abs(in.bladeCross));
    albedo *= edgeShade;

    float ndl = saturate((dot(N, L) + 0.32) / 1.32);
    float3 sunRadiance = u.sunColorAndWarmth.rgb * u.sunDirAndIntensity.w;

    float backScatter = pow(saturate(dot(-V, L) * 0.5 + 0.5), 2.6);
    float tipTranslucency = pow(t, 1.40) * (0.35 + 0.65 * in.gustHighlight);
    float3 sssTint = mix(float3(0.04, 0.15, 0.10), float3(0.22, 0.46, 0.036), warmth);
    float3 subsurface = sssTint * sunRadiance * (0.12 + 0.52 * backScatter) * tipTranslucency * rootAO * bladeVar;

    float3 H = normalize(L + V);
    float TdotH = dot(T, H);
    float sinTH = sqrt(max(0.0, 1.0 - TdotH * TdotH));
    float fiberSpec = pow(sinTH, 54.0) * smoothstep(0.22, 0.94, t);
    float gustSheen = 0.35 + 0.90 * in.gustHighlight;
    float3 specColor = mix(u.skyHorizonAndExposure.rgb * 0.55, u.sunColorAndWarmth.rgb, 0.55)
                     * fiberSpec * gustSheen * (0.08 * u.sunDirAndIntensity.w + 0.04) * rootAO;

    float3 ambient = albedo * (u.groundBounceAndAmbient.rgb * 1.1 + u.skyZenithAndFog.rgb * 0.36) * rootAO;
    float3 direct = albedo * sunRadiance * ndl * 0.36 * rootAO;
    float3 color = ambient + direct + subsurface + specColor;

    color = applyAerialFog(color, in.linearDepth, -V, u);
    return float4(color, 1.0);
}

// -----------------------------------------------------------------------------
// Pass 4: Delicate Chamomile / Meadow Daisies (With Close Foreground Bokeh!)
// -----------------------------------------------------------------------------

struct FlowerVertexOut {
    float4 position [[position]];
    float2 quadUV;
    float3 worldPos;
    float3 discNormal;
    float petalSeed;
    float linearDepth;
};

vertex FlowerVertexOut meadowFlowerVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms& u [[buffer(0)]],
    constant CursorImpulse* impulses [[buffer(1)]]
) {
    float3 rnd = hash31(iid * 2654435761U + 101U);
    float2 rnd2 = hash21u(iid * 40503U + 29U);

    bool isFgBokeh = (iid < 32U);
    float x;
    float z;
    bool culled = false;

    if (isFgBokeh) {
        x = mix(-1.35, 1.85, rnd.x);
        z = mix(3.75, 2.35, rnd.y);
    } else {
        uint idx = iid - 32U;
        const uint COLS = 74;
        const uint ROWS = 52;
        uint col = idx % COLS;
        uint row = idx / COLS;

        float uCol = (float(col) + rnd.x) / float(COLS);
        float uRow = (float(row) + rnd.y) / float(ROWS);

        float zBias = pow(uRow, 1.16);
        z = mix(3.1, -8.8, zBias);
        float spread = mix(0.45, 1.18, zBias);
        x = mix(0.18, 0.88, zBias) + (uCol - 0.5) * 10.4 * spread;

        float clusterA = fbm2D(float2(x, z) * 0.72 + float2(-4.1, 2.8));
        float clusterB = valueNoise2D(float2(x, z) * 1.85 + float2(7.3, -1.9));
        culled = ((clusterA * 0.7 + clusterB * 0.3) < 0.52 && rnd2.x > 0.14);
    }

    float groundY = meadowHeight(float2(x, z));
    float3 rootPos = float3(x, groundY, z);
    MeadowWindSample wind = evaluateMeadowWind(rootPos, rnd.z, u, impulses);

    float stemHeight = 0.36 + rnd.z * 0.34;
    float2 bendXZ = float2((rnd.x - 0.5) * 0.14 + 0.10, (rnd.y - 0.5) * 0.14 - 0.03)
                  + wind.worldPushXZ * 0.85
                  + float2(-wind.worldPushXZ.y, wind.worldPushXZ.x) * wind.flutter;
    float bendLen = min(length(bendXZ), stemHeight * 0.76);
    if (length(bendXZ) > 1e-4) bendXZ = normalize(bendXZ) * bendLen;

    float headY = sqrt(max(stemHeight * stemHeight - bendLen * bendLen * 0.68, 0.08));
    float3 blossomCenter = rootPos + float3(bendXZ.x, headY, bendXZ.y);

    float3 tiltDir = normalize(float3((rnd2.x - 0.5) * 0.55, 0.78 + rnd2.y * 0.35, 0.35));
    float3 toCam = normalize(u.cameraPosAndFOV.xyz - blossomCenter);
    float3 flowerN = normalize(mix(tiltDir, toCam, isFgBokeh ? 0.75 : 0.42));
    float3 axisU = normalize(cross(float3(0.0, 1.0, 0.1), flowerN) + float3(1e-4, 0, 0));
    float3 axisV = normalize(cross(flowerN, axisU));

    float2 corners[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2( 1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
    };
    float2 q = corners[vid];

    float radius = culled ? 0.0 : ((0.011 + rnd2.y * 0.009) * (isFgBokeh ? 1.35 : 1.0));
    float3 worldPos = blossomCenter + (axisU * q.x + axisV * q.y) * radius;

    FlowerVertexOut out;
    out.position = culled ? float4(2.0, 2.0, 2.0, 1.0) : (u.viewProjMatrix * float4(worldPos, 1.0));
    out.quadUV = q;
    out.worldPos = worldPos;
    out.discNormal = flowerN;
    out.petalSeed = rnd.x;
    out.linearDepth = length(blossomCenter - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 meadowFlowerFragment(
    FlowerVertexOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float2 p = in.quadUV;
    float r = length(p);
    if (r > 1.0) discard_fragment();

    float angle = atan2(p.y, p.x) + in.petalSeed * 6.28318;
    float rays = 11.0;
    float wave = abs(cos(angle * rays * 0.5));
    float outerRadius = 0.30 + 0.68 * pow(wave, 1.35);

    if (r > outerRadius) discard_fragment();

    float warmth = u.sunColorAndWarmth.w;
    float centerDisc = 1.0 - smoothstep(0.19, 0.31, r);
    float petalShadow = 0.72 + 0.28 * smoothstep(0.24, 0.86, r);

    float3 petalIvory = mix(float3(0.24, 0.34, 0.48), float3(1.22, 1.24, 1.14), 0.20 + 0.80 * warmth);
    float3 pollenCenter = mix(float3(0.18, 0.18, 0.08), float3(0.92, 0.68, 0.14), 0.22 + 0.78 * warmth);

    float3 col = mix(petalIvory * petalShadow, pollenCenter, centerDisc);
    col *= (0.40 + 0.44 * u.sunDirAndIntensity.w * 0.30);

    float3 V = normalize(u.cameraPosAndFOV.xyz - in.worldPos);
    col = applyAerialFog(col, in.linearDepth, -V, u);
    return float4(col, 1.0);
}

// -----------------------------------------------------------------------------
// Pass 5: Subtle Drifting Pollen & Soft Foreground Lens Bokeh Orbs
// -----------------------------------------------------------------------------

struct SeedVertexOut {
    float4 position [[position]];
    float2 quadUV;
    float3 tint;
    float alpha;
};

vertex SeedVertexOut meadowSeedVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float3 rnd = hash31(iid * 73856093U + 7U);
    float time = u.cameraRightAndTime.w;
    float netBoost = u.gustAndTurbulence.w;
    float activityGate = 0.38 + 0.62 * saturate(u.gustAndTurbulence.x * 0.5 + netBoost * 1.1);

    bool active = (rnd.z <= activityGate);
    bool fgBokehOrb = (iid < 14U);

    float driftDist = u.windDirAndSpeed.z * (0.12 + rnd.x * 0.16);
    float cycleX = fract(rnd.x + driftDist);
    float x = fgBokehOrb ? mix(-1.1, 1.4, cycleX) : mix(-3.8, 5.2, cycleX);
    float z = fgBokehOrb ? mix(3.8, 2.7, rnd.y) : (mix(2.8, -6.2, rnd.y) + sin(time * 0.38 + rnd.z * 9.0) * 0.32);
    float y = meadowHeight(float2(x, z)) + (fgBokehOrb ? (0.28 + rnd.z * 0.45) : (0.42 + rnd.z * 0.90))
            + sin(time * 0.58 + rnd.x * 12.0) * 0.11;

    float3 center = float3(x, y, z);
    float2 corners[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2( 1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
    };
    float2 q = corners[vid];
    float size = active ? (fgBokehOrb ? (0.026 + rnd.y * 0.022) : (0.008 + rnd.y * 0.007)) : 0.0;
    float3 worldPos = center + (u.cameraRightAndTime.xyz * q.x + u.cameraUpAndDelta.xyz * q.y) * size;

    SeedVertexOut out;
    out.position = active ? (u.viewProjMatrix * float4(worldPos, 1.0)) : float4(2.0, 2.0, 2.0, 1.0);
    out.quadUV = q;
    out.tint = mix(float3(0.25, 0.42, 0.58), float3(1.05, 1.08, 0.86), u.sunColorAndWarmth.w);
    float edgeFade = sin(cycleX * 3.14159);
    out.alpha = edgeFade * (fgBokehOrb
        ? (0.09 + 0.06 * sin(time * 0.4 + rnd.x * 6.28))
        : (0.24 + 0.20 * sin(time * 0.5 + rnd.x * 6.28)));
    return out;
}

fragment float4 meadowSeedFragment(SeedVertexOut in [[stage_in]]) {
    float r2 = dot(in.quadUV, in.quadUV);
    if (r2 > 1.0) discard_fragment();
    float disc = smoothstep(1.0, 0.60, sqrt(r2)) * (0.78 + 0.22 * r2);
    return float4(in.tint * disc * in.alpha, 0.0);
}
