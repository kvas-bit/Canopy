#include "ShaderShared.h"

// -----------------------------------------------------------------------------
// Scene 2: Misty Moss & Fern Floor — Pacific Northwest Old-Growth Forest
//          Layered 3D Redwood Trunks, Canopy Mist, 68k Woodland Grasses,
//          Multi-Frond Pinnate Sword Ferns & Wood Sorrel
// -----------------------------------------------------------------------------

inline float forestFloorHeight(float2 xz) {
    float trailHollow = -exp(-pow((xz.x - 0.15 + sin(xz.y * 0.25) * 0.65) * 0.52, 2.0)) * 0.24;
    float leftBank    = smoothstep(-0.2, -4.5, xz.x) * 0.52;
    float rightBank   = smoothstep(0.5, 4.8, xz.x) * 0.44;
    float hummocks    = (fbm2D(xz * 0.42 + float2(1.9, -2.4)) - 0.5) * 0.34;
    float mossPillow  = (valueNoise2D(xz * 1.8) - 0.5) * 0.065;
    return trailHollow + leftBank + rightBank + hummocks + mossPillow - 0.32;
}

inline float3 forestFloorNormal(float2 xz) {
    const float e = 0.06;
    float hL = forestFloorHeight(xz - float2(e, 0.0));
    float hR = forestFloorHeight(xz + float2(e, 0.0));
    float hD = forestFloorHeight(xz - float2(0.0, e));
    float hU = forestFloorHeight(xz + float2(0.0, e));
    return normalize(float3(hL - hR, 2.0 * e, hD - hU));
}

inline float2 evaluateForestBreeze(
    float3 pos,
    constant FrameUniforms& u,
    constant CursorImpulse* impulses
) {
    float2 windDir = normalize(u.windDirAndSpeed.xy + float2(0.80, 0.14));
    float2 windOffset = u.windDirAndSpeed.zw * 0.75;
    float gustAmt = u.gustAndTurbulence.x;
    float time = u.cameraRightAndTime.w;

    float2 advected = pos.xz * 0.26 - windOffset;
    float d1 = valueNoise2D(advected);
    float d2 = valueNoise2D(advected * 2.0 + float2(4.8, -2.3) - windOffset * 0.55);
    float draftRibbon = smoothstep(0.32, 0.82, d1 * 0.65 + d2 * 0.35);

    float2 crossDir = float2(-windDir.y, windDir.x);
    float eddy = (valueNoise2D(pos.xz * 0.42 - windOffset * 0.45 + float2(13.7, 5.9)) - 0.5) * 0.08;

    float localPhase = hash21(floor(pos.xz * 2.2)) * 6.28318;
    float swayA = sin(time * 0.85 + localPhase + pos.x * 1.1);
    float swayB = cos(time * 0.68 + localPhase * 1.7 + pos.z * 0.9);
    float2 gentle2DSway = float2(swayA, swayB) * (0.010 + 0.024 * draftRibbon * gustAmt);

    float2 push = windDir * (0.02 + draftRibbon * (0.09 + 0.22 * gustAmt))
                + crossDir * eddy
                + gentle2DSway;

    float2 screenUV = projectWorldToScreenUV(pos + float3(0.0, 0.22, 0.0), u);
    if (screenUV.x > -0.15 && screenUV.x < 1.15 && screenUV.y > -0.15 && screenUV.y < 1.15) {
        float2 cPush = sampleCursorBreezeScreenUV(screenUV, impulses, u.cameraForwardAndAspect.w);
        float3 worldPush = u.cameraRightAndTime.xyz * cPush.x * 0.42
                         + normalize(float3(u.cameraForwardAndAspect.x, 0.0, u.cameraForwardAndAspect.z)) * cPush.y * 0.42;
        push += worldPush.xz;
    }
    return push;
}

inline float3 evaluateForestMistColor(float2 screenUV, float3 rayDir, constant FrameUniforms& u) {
    float warmth = u.sunColorAndWarmth.w;
    float time = u.cameraRightAndTime.w;

    float3 deepWoodShadow = mix(float3(0.005, 0.012, 0.020), float3(0.016, 0.036, 0.026), warmth);
    float3 canopySkyGap   = mix(float3(0.028, 0.052, 0.088), float3(0.280, 0.380, 0.390), warmth);
    float3 lowMist        = mix(float3(0.018, 0.034, 0.052), float3(0.145, 0.205, 0.185), warmth);

    // Distant evergreen foliage silhouette texture in upper canopy
    float foliageTex = fbm2D(float2(rayDir.x * 7.5, rayDir.y * 9.0) + float2(2.3, 1.1));
    float foliageFine = valueNoise2D(float2(rayDir.x * 32.0, rayDir.y * 38.0));
    float skyOpening = smoothstep(-0.35, 0.45, -abs(rayDir.x - 0.08) * 1.35 + rayDir.y * 0.95 + (foliageTex - 0.5) * 0.55);
    skyOpening *= smoothstep(0.32, 0.68, foliageTex * 0.75 + foliageFine * 0.25);

    float3 col = mix(deepWoodShadow, canopySkyGap, skyOpening * 0.85);

    // Soft rolling valley mist near forest floor horizon
    float mistBand = exp(-pow((rayDir.y - 0.04) * 5.2, 2.0));
    float mistDrift = fbm2D(float2(rayDir.x * 3.2 - time * 0.012, rayDir.y * 4.0));
    col = mix(col, lowMist, mistBand * (0.45 + 0.40 * mistDrift));

    // Diagonal sunbeams filtering through upper canopy opening
    float beamCoord = (rayDir.x * 0.84 - rayDir.y * 0.54) * 6.2 + sin(time * 0.07) * 0.22;
    float beams = pow(valueNoise2D(float2(beamCoord, 1.7)), 3.0) * smoothstep(-0.05, 0.32, rayDir.y);
    col += u.sunColorAndWarmth.rgb * beams * (0.09 + 0.14 * warmth) * u.sunDirAndIntensity.w * 0.32;

    return col;
}

// -----------------------------------------------------------------------------
// Pass 1: Misty Forest Canopy & Sky-Gap Backdrop
// -----------------------------------------------------------------------------

struct MossBackdropOut {
    float4 position [[position]];
    float2 ndc;
};

vertex MossBackdropOut mossBackdropVertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    MossBackdropOut out;
    out.position = float4(pos[vid], 0.9999, 1.0);
    out.ndc = pos[vid];
    return out;
}

fragment float4 mossBackdropFragment(
    MossBackdropOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float4 worldFar = u.invViewProjMatrix * float4(in.ndc, 1.0, 1.0);
    float3 rayDir = normalize(worldFar.xyz / max(worldFar.w, 1e-5) - u.cameraPosAndFOV.xyz);
    float2 uv = in.ndc * 0.5 + 0.5;
    float3 col = evaluateForestMistColor(uv, rayDir, u);
    return float4(col, 1.0);
}

// -----------------------------------------------------------------------------
// Pass 2: 3D Old-Growth Redwood / Pine Tree Trunks & Canopy Boughs
// -----------------------------------------------------------------------------

struct TrunkVertexOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float2 barkUV;
    float trunkHeightFrac;
    float linearDepth;
};

vertex TrunkVertexOut mossTrunkVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    // Place trunks naturally on left/right sides of a central woodland clearing, receding into mist
    float3 rnd = hash31(iid * 8191U + 23U);
    float depthFrac = float(iid) / 29.0;
    float z = mix(-2.4, -17.5, pow(depthFrac, 0.88));

    float sideSign = (iid % 2U == 0U) ? -1.0 : 1.0;
    // Keep central clearing open near camera, closing slightly in the far distance
    float minClearance = mix(1.45, 0.35, depthFrac);
    float x = sideSign * (minClearance + rnd.x * mix(2.6, 5.8, depthFrac)) + (rnd.y - 0.5) * 0.6;

    float baseGroundY = forestFloorHeight(float2(x, z)) - 0.18;
    float baseRadius = 0.20 + rnd.z * 0.28 + depthFrac * 0.12;
    float trunkHeight = 7.5;

    const uint RAD_SEGS = 12;
    const uint H_SEGS = 6;
    uint quad = vid / 6;
    uint corner = vid % 6;
    uint rIdx = quad % RAD_SEGS;
    uint hIdx = quad / RAD_SEGS;

    uint2 offs[6] = { uint2(0,0), uint2(1,0), uint2(0,1), uint2(1,0), uint2(1,1), uint2(0,1) };
    uint2 cell = uint2(rIdx, hIdx) + offs[corner];

    float uAng = float(cell.x) / float(RAD_SEGS);
    float vH = float(cell.y) / float(H_SEGS);
    float theta = uAng * 6.2831853;

    // Root buttress flare near ground + subtle organic trunk lean
    float rootFlare = 1.0 + 0.45 * exp(-vH * 8.5) * (0.65 + 0.35 * sin(theta * 5.0 + rnd.x * 6.0));
    float taper = mix(1.0, 0.76, vH) * rootFlare;
    float r = baseRadius * taper;

    float2 lean = float2((rnd.x - 0.5) * 0.28, (rnd.y - 0.5) * 0.20) * vH * trunkHeight * 0.12;
    float3 radialDir = float3(cos(theta), 0.0, sin(theta));
    float3 wp = float3(x + lean.x, baseGroundY + vH * trunkHeight, z + lean.y) + radialDir * r;

    TrunkVertexOut out;
    out.position = u.viewProjMatrix * float4(wp, 1.0);
    out.worldPos = wp;
    out.normal = normalize(radialDir + float3(0.0, 0.08, 0.0));
    out.barkUV = float2(uAng * 4.0 + rnd.z * 5.0, vH * 6.5);
    out.trunkHeightFrac = vH;
    out.linearDepth = length(wp - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 mossTrunkFragment(
    TrunkVertexOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float3 V = normalize(u.cameraPosAndFOV.xyz - in.worldPos);
    float3 L = normalize(u.sunDirAndIntensity.xyz);
    float3 N = normalize(in.normal);
    float warmth = u.sunColorAndWarmth.w;

    // Deep vertical furrowed redwood / Douglas-fir bark
    float furrow = fbm2D(float2(in.barkUV.x * 7.5, in.barkUV.y * 1.8));
    float fineBark = valueNoise2D(float2(in.barkUV.x * 24.0, in.barkUV.y * 8.0));
    float3 barkDark = mix(float3(0.006, 0.008, 0.012), float3(0.024, 0.015, 0.010), warmth);
    float3 barkWarm = mix(float3(0.016, 0.020, 0.028), float3(0.072, 0.042, 0.024), warmth);
    float3 barkCol = mix(barkDark, barkWarm, smoothstep(0.28, 0.78, furrow) * (0.7 + 0.3 * fineBark));

    // Velvet green moss creeping up lower trunk & north/shaded side
    float mossHeightMask = smoothstep(0.42, 0.04, in.trunkHeightFrac + (furrow - 0.5) * 0.22);
    float mossPatch = smoothstep(0.35, 0.68, fbm2D(in.barkUV * 3.5));
    float3 trunkMoss = mix(float3(0.012, 0.042, 0.028), float3(0.036, 0.115, 0.024), warmth);
    float3 albedo = mix(barkCol, trunkMoss, saturate(mossHeightMask * (0.55 + 0.65 * mossPatch)));

    float ndl = max(dot(N, L), 0.0);
    float rimSun = pow(1.0 - saturate(dot(N, V)), 3.2) * max(dot(N, L) + 0.35, 0.0);
    float3 sunRad = u.sunColorAndWarmth.rgb * u.sunDirAndIntensity.w;

    float3 ambient = albedo * (u.groundBounceAndAmbient.rgb * 0.9 + u.skyZenithAndFog.rgb * 0.45);
    float3 direct  = albedo * sunRad * (ndl * 0.38 + rimSun * 0.42);
    float3 col = ambient + direct;

    // Strong woodland mist aerial perspective so distant trunks fade into misty layers
    float mistAmt = 1.0 - exp(-max(in.linearDepth - 2.2, 0.0) * 0.135);
    float3 mistTint = mix(float3(0.015, 0.030, 0.048), float3(0.125, 0.185, 0.170), warmth);
    col = mix(col, mistTint, clamp(mistAmt, 0.0, 0.92));

    return float4(col, 1.0);
}

// -----------------------------------------------------------------------------
// Pass 3: Mossy Humus & Pine-Needle Forest Floor
// -----------------------------------------------------------------------------

struct MossGroundOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float linearDepth;
};

vertex MossGroundOut mossTerrainVertex(
    uint vid [[vertex_id]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    const uint GX = 104;
    const uint GZ = 104;
    uint quad = vid / 6;
    uint corner = vid % 6;
    uint2 offs[6] = { uint2(0,0), uint2(1,0), uint2(0,1), uint2(1,0), uint2(1,1), uint2(0,1) };
    uint2 cell = uint2(quad % GX, quad / GX) + offs[corner];

    float x = mix(-6.5, 6.5, float(cell.x) / float(GX));
    float z = mix(4.2, -16.5, float(cell.y) / float(GZ));
    float y = forestFloorHeight(float2(x, z));
    float3 wp = float3(x, y, z);

    MossGroundOut out;
    out.position = u.viewProjMatrix * float4(wp, 1.0);
    out.worldPos = wp;
    out.normal = forestFloorNormal(wp.xz);
    out.linearDepth = length(wp - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 mossTerrainFragment(
    MossGroundOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float3 N = normalize(in.normal);
    float3 L = normalize(u.sunDirAndIntensity.xyz);
    float warmth = u.sunColorAndWarmth.w;

    float mossMap = fbm2D(in.worldPos.xz * 1.15);
    float needleLitter = valueNoise2D(in.worldPos.xz * 8.5);
    float dapple = smoothstep(0.38, 0.72, fbm2D(in.worldPos.xz * 0.55 + float2(1.4, -0.9)));

    float3 darkHumus  = mix(float3(0.004, 0.007, 0.009), float3(0.018, 0.014, 0.009), warmth);
    float3 pineLitter = mix(float3(0.008, 0.011, 0.014), float3(0.042, 0.026, 0.014), warmth);
    float3 lushMoss   = mix(float3(0.008, 0.032, 0.022), float3(0.028, 0.088, 0.018), warmth);

    float3 albedo = mix(darkHumus, pineLitter, needleLitter * 0.65);
    albedo = mix(albedo, lushMoss, smoothstep(0.38, 0.68, mossMap));

    float ndl = saturate((dot(N, L) + 0.30) / 1.30);
    float3 sunRad = u.sunColorAndWarmth.rgb * u.sunDirAndIntensity.w;
    float3 col = albedo * (u.groundBounceAndAmbient.rgb * 0.95 + sunRad * ndl * (0.12 + 0.32 * dapple));

    float mistAmt = 1.0 - exp(-max(in.linearDepth - 2.2, 0.0) * 0.135);
    float3 mistTint = mix(float3(0.015, 0.030, 0.048), float3(0.125, 0.185, 0.170), warmth);
    col = mix(col, mistTint, clamp(mistAmt, 0.0, 0.92));
    return float4(col, 1.0);
}

// -----------------------------------------------------------------------------
// Pass 4: 68,000 Natural Woodland Grasses & Sedges
// -----------------------------------------------------------------------------

struct WoodlandGrassOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float3 tangent;
    float bladeT;
    float bladeCross;
    float colorVar;
    float dappleLight;
    float linearDepth;
};

inline float3 bezier4(float3 p0, float3 p1, float3 p2, float3 p3, float t) {
    float it = 1.0 - t;
    return it*it*it*p0 + 3.0*it*it*t*p1 + 3.0*it*t*t*p2 + t*t*t*p3;
}

inline float3 bezier4Tangent(float3 p0, float3 p1, float3 p2, float3 p3, float t) {
    float it = 1.0 - t;
    return 3.0*it*it*(p1 - p0) + 6.0*it*t*(p2 - p1) + 3.0*t*t*(p3 - p2);
}

vertex WoodlandGrassOut mossGrassVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms& u [[buffer(0)]],
    constant CursorImpulse* impulses [[buffer(1)]]
) {
    const uint COLS = 280;
    const uint ROWS = 220;
    uint col = iid % COLS;
    uint row = iid / COLS;

    float3 rnd = hash31(iid * 314159U + 41U);
    float2 rnd2 = hash21u(iid * 27183U + 9U);

    float uCol = (float(col) + rnd.x) / float(COLS);
    float uRow = (float(row) + rnd.y) / float(ROWS);
    float zBias = pow(uRow, 1.32);
    float z = mix(4.05, -10.5, zBias);
    float spread = mix(0.40, 1.25, zBias);
    float x = (uCol - 0.5) * 10.6 * spread;

    float2 tuftWarp = float2(
        valueNoise2D(float2(x, z) * 1.6 + float2(4.2, 6.7)) - 0.5,
        valueNoise2D(float2(x, z) * 1.6 + float2(12.9, -4.1)) - 0.5
    );
    x += tuftWarp.x * 0.14;
    z += tuftWarp.y * 0.14;

    float groundY = forestFloorHeight(float2(x, z));
    float3 rootPos = float3(x, groundY - 0.025, z);

    float patchLush = valueNoise2D(float2(x, z) * 0.62 + float2(-2.1, 4.3));
    float height = 0.24 + rnd.z * 0.34 + patchLush * 0.16;

    float distToCam = length(rootPos - u.cameraPosAndFOV.xyz);
    float halfWidth = (0.0033 + rnd2.x * 0.0022) * clamp(distToCam * 0.080, 0.95, 1.95);

    float2 breeze = evaluateForestBreeze(rootPos, u, impulses);

    // 360-degree natural woodland tussock arch + soft droop
    float angle = rnd2.y * 6.2831853 + tuftWarp.x * 1.6;
    float2 splay = float2(cos(angle), sin(angle)) * (0.14 + rnd.y * 0.32) * height;
    float2 reach = splay + breeze * height * (0.85 + rnd.z * 0.55);
    float reachMag = min(length(reach), height * 0.82);
    if (length(reach) > 1e-4) reach = normalize(reach) * reachMag;

    float erectY = sqrt(max(height * height - reachMag * reachMag * 0.60, height * height * 0.25));
    float droop = 0.14 + pow(rnd2.x, 1.3) * 0.28;

    float3 p0 = rootPos;
    float3 p1 = rootPos + float3(reach.x * 0.18, erectY * 0.48, reach.y * 0.18);
    float3 p2 = rootPos + float3(reach.x * 0.64, erectY * 0.92, reach.y * 0.64);
    float3 p3 = rootPos + float3(reach.x, erectY * (1.0 - droop), reach.y);

    const uint SEGS = 6;
    uint seg = min(vid / 2, SEGS);
    bool isCap = (vid == SEGS * 2);
    float side = isCap ? 0.0 : ((vid % 2 == 0) ? -1.0 : 1.0);
    float t = isCap ? 1.0 : (float(seg) / float(SEGS));

    float3 spine = bezier4(p0, p1, p2, p3, t);
    float3 tang  = normalize(bezier4Tangent(p0, p1, p2, p3, t) + float3(0, 1e-4, 0));

    float twist = angle + t * (rnd.x - 0.5) * 1.5;
    float3 toCam = normalize(u.cameraPosAndFOV.xyz - spine);
    float3 bladeFace = normalize(float3(cos(twist), 0.15, sin(twist)));
    float3 sideAxis = normalize(cross(tang, mix(bladeFace, toCam, 0.50)) + float3(1e-4, 0, 0));
    float taper = isCap ? 0.0 : ((1.0 - pow(t, 1.50)) * (0.78 + 0.22 * smoothstep(0.0, 0.12, t)));
    float3 wp = spine + sideAxis * (side * halfWidth * taper);

    float dapple = smoothstep(0.38, 0.74, fbm2D(rootPos.xz * 0.55 + float2(1.4, -0.9)));

    WoodlandGrassOut out;
    out.position = u.viewProjMatrix * float4(wp, 1.0);
    out.worldPos = wp;
    out.normal = normalize(cross(sideAxis, tang) + sideAxis * (side * 0.45));
    out.tangent = tang;
    out.bladeT = t;
    out.bladeCross = side;
    out.colorVar = saturate(patchLush * 0.45 + rnd.x * 0.55);
    out.dappleLight = dapple;
    out.linearDepth = length(wp - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 mossGrassFragment(
    WoodlandGrassOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float3 V = normalize(u.cameraPosAndFOV.xyz - in.worldPos);
    float3 L = normalize(u.sunDirAndIntensity.xyz);
    float t = saturate(in.bladeT);
    float warmth = u.sunColorAndWarmth.w;

    float3 deepBase   = mix(float3(0.003, 0.009, 0.010), float3(0.008, 0.020, 0.008), warmth);
    float3 woodGreen  = mix(float3(0.010, 0.036, 0.026), float3(0.032, 0.095, 0.020), warmth);
    float3 sedgeOlive = mix(float3(0.016, 0.042, 0.030), float3(0.058, 0.115, 0.026), warmth);
    float3 russetTip  = mix(float3(0.024, 0.032, 0.038), float3(0.135, 0.105, 0.042), warmth);

    float3 midCol = mix(woodGreen, sedgeOlive, in.colorVar) * (0.72 + 0.55 * in.colorVar);
    float3 albedo = mix(deepBase, midCol, smoothstep(0.0, 0.55, t));
    if (in.colorVar > 0.80) {
        albedo = mix(albedo, russetTip, smoothstep(0.45, 1.0, t) * 0.65);
    }

    float ao = mix(0.04, 1.0, pow(t, 1.05));
    float3 sunRad = u.sunColorAndWarmth.rgb * u.sunDirAndIntensity.w;
    float sunFactor = 0.18 + 0.82 * in.dappleLight;

    float backGlow = pow(saturate(dot(-V, L) * 0.5 + 0.5), 2.4);
    float3 ambient = albedo * (u.groundBounceAndAmbient.rgb * 0.95 + u.skyZenithAndFog.rgb * 0.45) * ao;
    float3 direct  = albedo * sunRad * (0.22 + 0.55 * backGlow * t) * sunFactor * ao;
    float3 col = ambient + direct;

    float mistAmt = 1.0 - exp(-max(in.linearDepth - 2.2, 0.0) * 0.135);
    float3 mistTint = mix(float3(0.015, 0.030, 0.048), float3(0.125, 0.185, 0.170), warmth);
    col = mix(col, mistTint, clamp(mistAmt, 0.0, 0.92));
    return float4(col, 1.0);
}

// -----------------------------------------------------------------------------
// Pass 5: Multi-Frond Pinnate Sword Ferns (Polystichum munitum)
// -----------------------------------------------------------------------------

struct FernVertexOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float2 frondUV;     // x in [-1, 1] across pinnae, y in [0, 1] root-to-tip
    float dappleLight;
    float frondTone;
    float linearDepth;
};

vertex FernVertexOut mossFernVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms& u [[buffer(0)]],
    constant CursorImpulse* impulses [[buffer(1)]]
) {
    // 190 fern plants x 14 radiating fronds per rosette = 2,660 fronds
    const uint FRONDS_PER_PLANT = 14;
    uint plantID = iid / FRONDS_PER_PLANT;
    uint frondIdx = iid % FRONDS_PER_PLANT;

    float3 plantRnd = hash31(plantID * 104729U + 61U);
    float3 frondRnd = hash31(iid * 65537U + 13U);

    float z = mix(3.15, -9.8, pow(plantRnd.y, 1.12));
    float sideSpread = mix(0.45, 1.25, plantRnd.y);
    // Favor sides of clearing and base of trees while keeping natural scattered clumps
    float xRaw = (plantRnd.x - 0.5) * 9.6 * sideSpread;
    float x = xRaw + ((xRaw >= 0.0) ? 0.25 : -0.25);

    float groundY = forestFloorHeight(float2(x, z));
    float3 crownPos = float3(x, groundY + 0.01, z);

    bool innerRing = (frondIdx >= 9U);
    float az = (float(frondIdx) / float(innerRing ? 5.0 : 9.0)) * 6.2831853 + plantRnd.z * 6.28 + (frondRnd.x - 0.5) * 0.35;
    float frondLen = (innerRing ? 0.42 : 0.58) * (0.78 + 0.44 * plantRnd.z) * (0.88 + 0.24 * frondRnd.y);
    float maxHalfWidth = frondLen * 0.165;

    float2 breeze = evaluateForestBreeze(crownPos, u, impulses);
    float2 outwardDir = float2(cos(az), sin(az));
    float reachFactor = innerRing ? 0.62 : 0.84;
    float2 reachXZ = outwardDir * (frondLen * reachFactor) + breeze * frondLen * 0.65;

    float archHeight = frondLen * (innerRing ? 0.68 : 0.48);
    float tipHeight  = frondLen * (innerRing ? 0.42 : 0.14);

    float3 p0 = crownPos;
    float3 p1 = crownPos + float3(reachXZ.x * 0.25, archHeight * 0.85, reachXZ.y * 0.25);
    float3 p2 = crownPos + float3(reachXZ.x * 0.68, archHeight * 1.05, reachXZ.y * 0.68);
    float3 p3 = crownPos + float3(reachXZ.x, tipHeight, reachXZ.y);

    const uint SEGS = 8;
    uint seg = min(vid / 2, SEGS);
    bool isCap = (vid == SEGS * 2);
    float side = isCap ? 0.0 : ((vid % 2 == 0) ? -1.0 : 1.0);
    float t = isCap ? 1.0 : (float(seg) / float(SEGS));

    float3 spine = bezier4(p0, p1, p2, p3, t);
    float3 tang  = normalize(bezier4Tangent(p0, p1, p2, p3, t) + float3(0, 1e-4, 0));

    // Fern frond faces skyward along its arch!
    float3 horizontalOut = normalize(float3(outwardDir.x, 0.0, outwardDir.y));
    float3 widthAxis = normalize(cross(float3(0.0, 1.0, 0.0), horizontalOut) + float3(1e-4, 0, 0));
    float frondEnvelope = sin(pow(clamp(t, 0.02, 1.0), 0.65) * 3.14159);
    if (isCap) frondEnvelope = 0.0;

    float vFold = abs(side) * maxHalfWidth * frondEnvelope * 0.14;
    float3 wp = spine + widthAxis * (side * maxHalfWidth * frondEnvelope) + float3(0.0, vFold, 0.0);
    float3 frondN = normalize(cross(tang, widthAxis));
    if (frondN.y < 0.0) frondN = -frondN;

    float dapple = smoothstep(0.36, 0.76, fbm2D(crownPos.xz * 0.55 + float2(1.4, -0.9)));

    FernVertexOut out;
    out.position = u.viewProjMatrix * float4(wp, 1.0);
    out.worldPos = wp;
    out.normal = frondN;
    out.frondUV = float2(side, t);
    out.dappleLight = dapple;
    out.frondTone = frondRnd.z;
    out.linearDepth = length(wp - u.cameraPosAndFOV.xyz);
    return out;
}

fragment float4 mossFernFragment(
    FernVertexOut in [[stage_in]],
    constant FrameUniforms& u [[buffer(0)]]
) {
    float crossU = in.frondUV.x; // -1..1
    float alongV = saturate(in.frondUV.y); // 0..1
    float absX = abs(crossU);

    // Central woody-green rachis stem
    float stemHalfW = mix(0.065, 0.025, alongV);
    bool onStem = (absX <= stemHalfW);

    // 24 pairs of alternating serrated sword-fern pinnae (leaflets)!
    if (!onStem) {
        if (alongV < 0.08) discard_fragment();
        float sideOffset = (crossU > 0.0) ? 0.0 : 0.42;
        float pinnaCoord = alongV * 24.0 + sideOffset;
        float localV = fract(pinnaCoord) - 0.5;

        // Slight forward angle on each leaflet toward frond tip
        float angledV = localV - (absX - stemHalfW) * 0.24;
        float leafletHalfWidth = 0.36 * (1.0 - pow(absX, 1.45)) * (1.0 + 0.08 * sin(absX * 26.0));
        if (abs(angledV) > leafletHalfWidth) {
            discard_fragment();
        }
    }

    float3 V = normalize(u.cameraPosAndFOV.xyz - in.worldPos);
    float3 L = normalize(u.sunDirAndIntensity.xyz);
    float3 N = normalize(in.normal);
    if (dot(N, V) < 0.0) N = -N;
    float warmth = u.sunColorAndWarmth.w;

    float3 stemCol  = mix(float3(0.012, 0.026, 0.020), float3(0.048, 0.072, 0.022), warmth);
    float3 fernDeep = mix(float3(0.012, 0.045, 0.032), float3(0.038, 0.118, 0.024), warmth);
    float3 fernLush = mix(float3(0.022, 0.068, 0.045), float3(0.082, 0.195, 0.034), warmth);

    float3 leafCol = mix(fernDeep, fernLush, saturate(alongV * 0.65 + in.frondTone * 0.45));
    float3 albedo = onStem ? stemCol : leafCol;

    float crownAO = mix(0.18, 1.0, smoothstep(0.0, 0.35, alongV));
    float3 sunRad = u.sunColorAndWarmth.rgb * u.sunDirAndIntensity.w;
    float sunFactor = 0.20 + 0.80 * in.dappleLight;

    float ndl = saturate(dot(N, L) * 0.65 + 0.35);
    float backTrans = pow(saturate(dot(-V, L) * 0.5 + 0.5), 2.2) * (onStem ? 0.1 : 0.65);
    float3 H = normalize(L + V);
    float waxySpec = pow(max(dot(N, H), 0.0), 28.0) * 0.14 * sunFactor;

    float3 ambient = albedo * (u.groundBounceAndAmbient.rgb * 1.1 + u.skyZenithAndFog.rgb * 0.5) * crownAO;
    float3 direct  = albedo * sunRad * (ndl * 0.42 + backTrans * 0.48) * sunFactor * crownAO
                   + sunRad * waxySpec * crownAO;
    float3 col = ambient + direct;

    float mistAmt = 1.0 - exp(-max(in.linearDepth - 2.2, 0.0) * 0.135);
    float3 mistTint = mix(float3(0.015, 0.030, 0.048), float3(0.125, 0.185, 0.170), warmth);
    col = mix(col, mistTint, clamp(mistAmt, 0.0, 0.92));
    return float4(col, 1.0);
}

// -----------------------------------------------------------------------------
// Pass 6: Sunlit Forest Dust / Pollen Motes Drifting in Sunbeams
// -----------------------------------------------------------------------------

struct SporeVertexOut {
    float4 position [[position]];
    float2 quadUV;
    float3 tint;
    float alpha;
};

vertex SporeVertexOut mossSporeVertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant FrameUniforms& u [[buffer(0)]],
    constant CursorImpulse* impulses [[buffer(1)]]
) {
    float3 rnd = hash31(iid * 928371U + 13U);
    float2 rnd2 = hash21u(iid * 49157U + 7U);
    float time = u.cameraRightAndTime.w;

    // 3D lazy thermal convection & Brownian curl around a local forest sunbeam pocket (never on a 1D rail!)
    float anchorX = mix(-3.4, 3.6, rnd.x);
    float anchorZ = mix(2.6, -7.2, rnd.y);
    float baseFloor = forestFloorHeight(float2(anchorX, anchorZ));
    float anchorY = baseFloor + 0.35 + rnd.z * 1.85;

    float tSlow = time * (0.14 + rnd2.x * 0.10);
    float p1 = rnd.x * 6.28318;
    float p2 = rnd.y * 6.28318;
    float p3 = rnd.z * 6.28318;

    float3 curlOffset = float3(
        sin(tSlow * 1.10 + p1) * 0.28 + cos(tSlow * 0.67 + p2) * 0.16,
        sin(tSlow * 0.83 + p2) * 0.24 + cos(tSlow * 0.47 + p3) * 0.14,
        cos(tSlow * 0.91 + p3) * 0.26 + sin(tSlow * 0.59 + p1) * 0.15
    );
    float3 center = float3(anchorX, anchorY, anchorZ) + curlOffset;

    // Subtle cursor air stir when pointer brushes past floating dust
    float2 screenUV = projectWorldToScreenUV(center, u);
    if (screenUV.x > -0.1 && screenUV.x < 1.1 && screenUV.y > -0.1 && screenUV.y < 1.1) {
        float2 cSwirl = sampleCursorBreezeScreenUV(screenUV, impulses, u.cameraForwardAndAspect.w);
        center += (u.cameraRightAndTime.xyz * cSwirl.x + u.cameraUpAndDelta.xyz * cSwirl.y) * 0.32;
    }

    float2 corners[6] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
        float2( 1.0, -1.0), float2( 1.0,  1.0), float2(-1.0,  1.0)
    };
    float2 q = corners[vid];
    float radius = (iid < 14U) ? (0.020 + rnd.y * 0.018) : (0.0065 + rnd2.y * 0.0075);
    float3 wp = center + (u.cameraRightAndTime.xyz * q.x + u.cameraUpAndDelta.xyz * q.y) * radius;

    // Smooth glimmer as mote drifts through sunbeam and back into shade
    float sunbeamGlimmer = pow(0.5 + 0.5 * sin(time * (0.28 + rnd2.y * 0.22) + p3), 2.2);
    float warmth = u.sunColorAndWarmth.w;
    SporeVertexOut out;
    out.position = u.viewProjMatrix * float4(wp, 1.0);
    out.quadUV = q;
    out.tint = mix(float3(0.18, 0.42, 0.55), float3(0.95, 0.90, 0.65), warmth);
    out.alpha = ((iid < 14U) ? 0.08 : 0.20) * sunbeamGlimmer;
    return out;
}

fragment float4 mossSporeFragment(SporeVertexOut in [[stage_in]]) {
    float r2 = dot(in.quadUV, in.quadUV);
    if (r2 > 1.0) discard_fragment();
    float glow = smoothstep(1.0, 0.55, sqrt(r2)) * in.alpha;
    return float4(in.tint * glow, 0.0);
}
