#version 300 es
precision highp float;

in vec2 vPosition;
out vec4 fragColor;

// ═══════════════════════════════════════════════════════════════════════════════
//  Trou Noir de Schwarzschild — Lentille gravitationnelle
//
//  Méthode hybride :
//    1. En 2D (plan équatorial), on résout l'équation orbitale exacte :
//       d²u/dφ² + u = 3Mu²   (u = 1/r)
//    2. On projette le résultat en 3D avec l'inclinaison de la caméra
//    3. Le disque d'accrétion est dans le plan équatorial
//
//  L'équation orbitale est EXACTE pour les géodésiques dans le plan
//  équatorial de Schwarzschild. Le terme 3Mu² est la correction relativiste.
// ═══════════════════════════════════════════════════════════════════════════════

const float PI           = 3.14159265359;
const float M            = 0.5;
const float EH           = 1.0;          // Event horizon = 2M = 1.0
const float DISK_IN      = 3.0;          // ISCO = 6M for Schwarzschild
const float DISK_OUT     = 15.0;
const float DISK_SIGMA   = 0.02;         // Thin disk, Interstellar-style vertical thickness
const float MAX_R        = 500.0;
const int   MAX_STEPS    = 900;          // Max integration steps (adaptive steps reach far field quickly)

// ── Softening ────────────────────────────────────────────────────────────────
// const float SOFTEN_R2  = 0.001;        // DEAD CODE: horizon capture (r < EH) breaks before r² < 0.001

// ── Blackbody normalization ─────────────────────────────────────────────────
const float TEMP_PEAK    = 0.214;        // Empirical peak normalization for visual range (Novikov-Thorne profile at r≈4.08, DISK_IN=3.0)
const float TEMP_SCALE   = 0.55;         // Normalize peak to 1.0, then scale down for visual range

// ── Disk optical properties ─────────────────────────────────────────────────
const float BETA_MAX     = 0.95;         // Clamp orbital velocity to avoid division by zero in gamma
const float BEAM_MIN     = 0.001;        // Minimum beaming factor to avoid zero-flux artifacts
const float BEAM_MAX     = 8.0;          // Maximum beaming factor to avoid overflow
const float COLOR_MIX    = 0.3;          // Mix factor for gravitational redshift color shift
const float DISK_ABS     = 0.3;          // Beer-Lambert absorption per disk intersection (0.3 = optically thin, 0.6 = too opaque)

// ── Photon ring ─────────────────────────────────────────────────────────────
const float RING_WIDTH   = 0.35;         // Width of photon ring boost region (in orbit units)
const float RING_BOOST   = 4.0;          // Max brightness multiplier at 1 orbit
const float ORBIT_FADE_START = 0.5;      // Start fading higher-order images
const float ORBIT_FADE_END   = 2.0;      // Fully faded beyond this orbit count
const float DIRECT_FADE_MAX  = 0.1;      // Max fade for direct (0-orbit) rays

// ── Star field thresholds ───────────────────────────────────────────────────
const float STAR_DENSITY   = 0.9960;     // Primary star cell density threshold
const float STAR_BRIGHTNESS= 0.99995;    // Primary star brightness threshold
const float STAR_Faint_1   = 0.9940;     // Faint star layer 1 threshold
const float STAR_Faint_2   = 0.9930;     // Faint star layer 2 threshold

// ── Hash seed constants ─────────────────────────────────────────────────────
// Prime-based seeds for spatial hashing — chosen to minimize visible patterns
const float HASH_SEED_A  = 127.1;
const float HASH_SEED_B  = 311.7;
const float HASH_SCALE   = 43758.5453;   // Knuth's multiplicative hash constant
const float HASH_SEED_C  = 123.34;
const float HASH_SEED_D  = 456.21;
const float HASH_SEED_E  = 789.98;
const float HASH_SEED_F  = 269.5;
const float HASH_SEED_G  = 183.3;
const float HASH_SEED_H  = 419.2;

// ── FBM rotation constant ───────────────────────────────────────────────────
// mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.5)) — rotation by 0.5 rad per octave
const mat2 FBM_ROT = mat2(0.8775825619, 0.4794255386, -0.4794255386, 0.8775825619);

uniform vec3  uCamPos;
uniform float uAspect;
uniform float uFOV;
uniform float uTime;
uniform float uDiskPsi;
uniform float uDiskCos;          // cos(diskPsi) — precomputed in JS
uniform float uDiskSin;          // sin(diskPsi) — precomputed in JS
uniform float uRealistic;
uniform float uSeed;

// ── Rotate point into disk frame (Y=0 plane), then rotate back ───────────────
// Uses precomputed uDiskCos/uDiskSin uniforms (no sin/cos per pixel)

vec3 diskToDiskFrame(vec3 p) {
    // Rotate around X axis: Y' = Y*c - Z*s, Z' = Y*s + Z*c
    return vec3(p.x, p.y * uDiskCos - p.z * uDiskSin, p.y * uDiskSin + p.z * uDiskCos);
}

vec3 diskToWorld(vec3 p) {
    // Inverse rotation (same as transpose for rotation around X)
    return vec3(p.x, p.y * uDiskCos + p.z * uDiskSin, -p.y * uDiskSin + p.z * uDiskCos);
}

// ── Turbulence animée du disque ──────────────────────────────────────────────
// Simule des structures spirales et des turbulences dans le gaz d'accrétion
// en décalant l'angle azimutal en fonction du rayon et du temps.

float hash(vec2 p) {
    // Pre-multiplied seed offsets (computed once in JS as uniforms would be, but here fused)
    vec2 seedOffset = vec2(uSeed * 991.0, uSeed * 743.0);
    return fract(sin(dot(p, vec2(HASH_SEED_A + seedOffset.x, HASH_SEED_B + seedOffset.y))) * HASH_SCALE);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Precomputed rotation matrix for FBM — computed once per FBM call, not per octave
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = FBM_ROT * p * 2.0;
        a *= 0.5;
    }
    return v;
}

// Facteur de turbulence : rotation différentielle réaliste (Kepler)
float diskTurbulenceKepler(vec2 diskPos, float time) {
    float r = length(diskPos);
    float a = atan(diskPos.y, diskPos.x);

    float omega = 12.0 / pow(max(r, 1.0), 1.5);
    float omegaT = omega * time;

    vec2 localUV = diskPos * 1.8;
    float ca = cos(-omegaT * 0.3);
    float sa = sin(-omegaT * 0.3);
    vec2 localRot = vec2(
        localUV.x * ca - localUV.y * sa,
        localUV.x * sa + localUV.y * ca
    );
    float n = fbm(localRot * 1.2);

    float spiral = 3.0 * log(max(r, 0.1)) + 2.0 * (a - omegaT);
    float spiralStr = sin(spiral + n * 3.0) * 0.5 + 0.5;

    float fine = noise(localRot * 8.0);

    return mix(n, spiralStr, 0.8) * 0.7 + fine * 0.3;
}

// Facteur de turbulence : rotation cinématique (bloc rigide)
float diskTurbulenceCine(vec2 diskPos, float time) {
    float t = time;
    float ca = cos(-t * 0.5);
    float sa = sin(-t * 0.5);
    vec2 rotPos = vec2(
        diskPos.x * ca - diskPos.y * sa,
        diskPos.x * sa + diskPos.y * ca
    );

    float r = length(rotPos);
    float aRot = atan(rotPos.y, rotPos.x);
    vec2 uv = vec2(aRot * 2.0, log(max(r, 0.1)) * 2.0);

    float n = fbm(uv * 1.5);

    float spiral = 3.0 * log(max(r, 0.1)) + 2.0 * aRot;
    float spiralStr = sin(spiral + n * 3.0) * 0.5 + 0.5;

    float fine = noise(uv * 8.0);

    return mix(n, spiralStr, 0.8) * 0.7 + fine * 0.3;
}

// Turbulence selector — switches between Kepler and rigid-body rotation
float diskTurbulence(vec2 diskPos, float time, bool realistic) {
    if (realistic) {
        return diskTurbulenceKepler(diskPos, time);
    }
    return diskTurbulenceCine(diskPos, time);
}

// ═══ Nebula color from direction ═══
// Computes nebula color and intensity from a viewing direction.
vec3 nebulaColor(vec3 dir, float baseHueShift) {
    float n1 = sin(dir.x * 3.0 + dir.y * 2.0 + dir.z * 1.5 + baseHueShift);
    float n2 = sin(dir.x * 5.0 - dir.y * 4.0 + dir.z * 3.0 + 1.0 + baseHueShift);
    float n3 = sin(dir.x * 7.0 + dir.y * 6.0 - dir.z * 5.0 + 2.0 + baseHueShift);
    float neb = (n1 * 0.5 + n2 * 0.3 + n3 * 0.2) * 0.5 + 0.5;

    // Teinte bleu-violet-rose (vectorized with step/mix, consistent with blackbody())
    float hue = n1 * 0.5 + 0.5;
    float s1 = step(hue, 0.33);
    float s2 = step(hue, 0.66);
    vec3 nebColor = vec3(0.0);
    nebColor += mix(vec3(0.1, 0.02, 0.35), vec3(0.25, 0.05, 0.45), clamp(hue * 3.0, 0.0, 1.0)) * s1;
    nebColor += mix(vec3(0.25, 0.05, 0.45), vec3(0.45, 0.1, 0.35), clamp((hue - 0.33) * 3.0, 0.0, 1.0)) * (1.0 - s1) * s2;
    nebColor += mix(vec3(0.45, 0.1, 0.35), vec3(0.35, 0.15, 0.45), clamp((hue - 0.66) * 3.0, 0.0, 1.0)) * (1.0 - s2);

    return nebColor * neb;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Étoiles — fond noir pur, étoiles blanches
// ═══════════════════════════════════════════════════════════════════════════════

float hash1(vec3 p) {
    // Seed constants for 3D spatial hashing
    p = fract(p * vec3(HASH_SEED_C, HASH_SEED_D, HASH_SEED_E));
    p += dot(p, p.yxz + 19.19);
    return fract((p.x + p.y) * p.z);
}

float hash2(vec3 p) {
    return fract(sin(dot(p, vec3(HASH_SEED_F, HASH_SEED_G, HASH_SEED_H))) * HASH_SCALE);
}

vec3 starfield(vec3 dir) {
    vec3 p = dir * 500.0;
    vec3 id = floor(p);

    float h1 = hash1(id);
    float star = smoothstep(STAR_DENSITY, STAR_BRIGHTNESS, h1);
    float h2 = hash2(id);
    float bright = mix(0.5, 2.0, h2);
    float att = 1.0 / (1.0 + length(fract(p)) * 2.0);
    float sc = bright * star * att;

    float h3 = hash1(id * 2.718 + 50.0);
    sc += smoothstep(STAR_Faint_1, 0.9998, h3) * 0.3;

    float h4 = hash1(id * 3.14159 + 200.0);
    sc += smoothstep(STAR_Faint_2, 0.9999, h4) * 0.1;

    // Légère teinte bleutée pour mieux ressortir sur les reflets
    vec3 starColor = vec3(sc * 5.0) * vec3(0.95, 0.97, 1.0);

    // Nébuleuse (factorisée v1.4.0)
    vec3 nebResult = nebulaColor(dir, 0.0);

    return nebResult + starColor;
}

// ═══ Approximation réaliste d'un corps noir (Munnich 2004) ═══
// Convertit une température normalisée [0,1] en couleur RGB.
// Vectorisé avec step/mix au lieu de if/else (v1.4.0)
vec3 blackbody(float t) {
    float temp = 1500.0 + t * 10500.0;
    float tt = clamp((temp - 1500.0) / 10500.0, 0.0, 1.0);

    // Phase rouge (1500–3500K) : tt < 0.1905
    // Phase orange (3500–6000K) : 0.1905 ≤ tt < 0.4286
    // Phase blanc chaud (6000–9000K) : 0.4286 ≤ tt < 0.7143
    // Phase blanc (9000–12000K) : tt ≥ 0.7143
    float s1 = step(tt, 0.190476);
    float s2 = step(tt, 0.428571);
    float s3 = step(tt, 0.714286);

    vec3 c1 = vec3(0.08, 0.02, 0.0);
    vec3 c2 = vec3(0.95, 0.3, 0.02);
    vec3 c3 = vec3(1.0, 0.75, 0.25);
    vec3 c4 = vec3(1.0, 0.95, 0.85);
    vec3 c5 = vec3(0.9, 0.93, 1.0);

    vec3 color = mix(c1, c2, clamp((tt - 0.0) / 0.190476, 0.0, 1.0)) * s1
               + mix(c2, c3, clamp((tt - 0.190476) / 0.238095, 0.0, 1.0)) * (1.0 - s1) * s2
               + mix(c3, c4, clamp((tt - 0.428571) / 0.285714, 0.0, 1.0)) * (1.0 - s2) * s3
               + mix(c4, c5, clamp((tt - 0.714286) / 0.285714, 0.0, 1.0)) * (1.0 - s3);

    return color;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Camera helpers
// ═══════════════════════════════════════════════════════════════════════════════

vec3 camFwd() { return normalize(-uCamPos); }

vec3 camRight() {
    vec3 f = camFwd();
    vec3 up = (abs(f.y) < 0.999) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    return normalize(cross(up, f));
}

vec3 camUp() { return cross(camFwd(), camRight()); }

// ═══════════════════════════════════════════════════════════════════════════════
//  RAY MARCHING 3D with RK4
//
//  Integrate 1st-order system:
//    dx/dλ = v
//    dv/dλ = gravAccel(pos, v)
//  Velocity magnitude is preserved by the 1PN acceleration structure
//  (no explicit normalization needed for null geodesics).
// ═══════════════════════════════════════════════════════════════════════════════

vec4 rayMarch(vec2 uv) {
    vec3 ro = uCamPos;
    float tanFov = tan(uFOV * 0.5);
    vec2 xy = (uv - 0.5) * vec2(uAspect, 1.0) * 2.0 * tanFov;

    // Memoize camera basis vectors — camFwd() called 3x otherwise
    vec3 fwd = camFwd();
    vec3 right = camRight();
    vec3 up = cross(fwd, right);
    vec3 rd = normalize(fwd + right * xy.x + up * xy.y);

    vec3 pos = ro;
    vec3 vel = rd;
    vec3 prevPos = ro;

    // Accumulation du disque — Beer-Lambert law
    vec3 diskAcc = vec3(0.0);
    float diskTransmittance = 1.0;

    // Tracking pour l'anneau de photons
    float totalAngle = 0.0;
    vec3 lastPos = ro;
    bool tracking = true;

    int orbitCount = 0;
    float lastAngleThreshold = PI;
    bool stuck = false;

    // Impact parameter — Schwarzschild photon capture threshold
    // Photon sphere at r = 3M, critical impact parameter b_crit = 3√3 M
    // Local impact parameter at finite distance: b_loc = b_∞ / √(1-2M/r_cam)
    // Capture condition b_loc < b_crit → b < b_crit * √(1-2M/r_cam)
    vec3 crossProd = cross(ro, rd);
    float b = length(crossProd);
    float b_crit = 3.0 * sqrt(3.0) * M;
    float camDist = length(ro);
    float gravFactor = sqrt(max(0.01, 1.0 - EH / camDist));
    bool captured = (b < b_crit * gravFactor);

    bool rayInteracted = false;

    for (int i = 0; i < MAX_STEPS; i++) {
        float r = length(pos);

        // ── Early-out conditions ────────────────────────────────────────────
        if (r < EH) break;                          // Horizon — unified capture
        if (r > MAX_R) break;                       // Too far
        if (stuck) break;                            // Orbit safeguard

        // Early escape: if ray is far and moving monotonically away
        if (r > 40.0) {
            float radialVel = dot(pos, vel) / r;
            if (radialVel > 0.5) break;             // Moving away fast → escape
        }

        // ── Pas adaptatif ───────────────────────────────────────────────────
        float h;
        if (r < 1.2) h = 0.005;
        else if (r < 1.5) h = 0.01;
        else if (r < 2.0) h = 0.02;
        else if (r < 3.0) h = 0.04;
        else if (r < 6.0) h = 0.08;
        else if (r < 12.0) h = 0.2;
        else if (r < 30.0) h = 0.8;
        else if (r < 60.0) h = 2.0;               // Extended range
        else h = 4.0;                               // Far field — minimal bending

        // RK4 — 4 evaluations of acceleration at intermediate positions
        // Standard RK4 for 1st-order system: dx/dλ=v, dv/dλ=a(x,v)
        // Inlined gravAccel with shared r2/r/r3 between stages for performance
        // kNPos = velocity (unchanged), kNVel = acceleration at stage N

        // Stage 1
        float r2_1 = dot(pos, pos);
        float r_1 = sqrt(r2_1);
        float r3_1 = r2_1 * r_1;
        float vx_1 = dot(vel, pos);
        vec3 k1Vel = -(M / r3_1) * (pos + (-4.0 * vx_1 * vel) + (3.0 * (vx_1 * vx_1 / r2_1) * pos));
        vec3 k1Pos = vel;

        // Stage 2
        vec3 p2 = pos + 0.5*h*k1Pos;
        vec3 v2 = vel + 0.5*h*k1Vel;
        float r2_2 = dot(p2, p2);
        float r_2 = sqrt(r2_2);
        float r3_2 = r2_2 * r_2;
        float vx_2 = dot(v2, p2);
        vec3 k2Vel = -(M / r3_2) * (p2 + (-4.0 * vx_2 * v2) + (3.0 * (vx_2 * vx_2 / r2_2) * p2));
        vec3 k2Pos = v2;

        // Stage 3
        vec3 p3 = pos + 0.5*h*k2Pos;
        vec3 v3 = vel + 0.5*h*k2Vel;
        float r2_3 = dot(p3, p3);
        float r_3 = sqrt(r2_3);
        float r3_3 = r2_3 * r_3;
        float vx_3 = dot(v3, p3);
        vec3 k3Vel = -(M / r3_3) * (p3 + (-4.0 * vx_3 * v3) + (3.0 * (vx_3 * vx_3 / r2_3) * p3));
        vec3 k3Pos = v3;

        // Stage 4
        vec3 p4 = pos + h*k3Pos;
        vec3 v4 = vel + h*k3Vel;
        float r2_4 = dot(p4, p4);
        float r_4 = sqrt(r2_4);
        float r3_4 = r2_4 * r_4;
        float vx_4 = dot(v4, p4);
        vec3 k4Vel = -(M / r3_4) * (p4 + (-4.0 * vx_4 * v4) + (3.0 * (vx_4 * vx_4 / r2_4) * p4));
        vec3 k4Pos = v4;

        prevPos = pos;
        pos = pos + (h/6.0) * (k1Pos + 2.0*k2Pos + 2.0*k3Pos + k4Pos);
        vel = vel + (h/6.0) * (k1Vel + 2.0*k2Vel + 2.0*k3Vel + k4Vel);

        // ── Photon orbit tracking ──────────────────────────────────────────
        // Count angle swept in disk plane to detect photon ring orbits
        vec3 posDF = diskToDiskFrame(pos);
        vec3 prevDF = diskToDiskFrame(prevPos);

        if (tracking && r < 50.0) {
            vec3 posD = posDF;
            vec3 lastPosD = prevDF;
            vec3 deltaD = posD - lastPosD;

            // Angle balayé dans le plan du disque (X-Z plane of disk frame)
            // Using acos instead of atan2 for GPU performance (~80-128 cycles saved per call)
            float dotXZ = dot(deltaD.xz, lastPosD.xz);
            float rXZ = max(length(lastPosD.xz), 0.01);
            float angleStep = acos(clamp(dotXZ / rXZ, -1.0, 1.0));
            totalAngle += max(angleStep, 0.0);
            lastPos = pos;

            // Compter les demi-tours complets (seuils de PI)
            float currentAngleThreshold = floor(totalAngle / PI);
            if (currentAngleThreshold > lastAngleThreshold) {
                orbitCount = int(currentAngleThreshold);
                lastAngleThreshold = currentAngleThreshold;
            }
            // Arrêter le tracking si on est loin
            if (r > 30.0) tracking = false;

            // Safeguard : orbites multiples → rayon piégé
            if (orbitCount > 5) stuck = true;
        }

        // ── Disk intersection (y=0, tilted by uDiskPsi) ────────────────────
        // Reuse posDF/prevDF computed in orbit tracking section
        float prevYDisk = prevDF.y;

        if (prevYDisk * posDF.y < 0.0) {
            float t = prevYDisk / (prevYDisk - posDF.y);
            vec3 hitDisk = prevDF + t * (posDF - prevDF);
            vec3 hit = diskToWorld(hitDisk);
            float hr = length(hitDisk.xz);

            if (hr >= DISK_IN && hr <= DISK_OUT) {
                rayInteracted = true;

                // Novikov-Thorne temperature profile: T ∝ r^(-3/4) * (1 - sqrt(r_in/r))^(1/4)
                float tempProfile = pow(hr, -0.75) * pow(1.0 - sqrt(DISK_IN / hr), 0.25);
                // Normalized temperature: peak at r≈4.08 for DISK_IN=3.0
                float tNorm = clamp(tempProfile / TEMP_PEAK * TEMP_SCALE, 0.0, 1.0);

                // Emissivity profile — Novikov-Thorne radial flux: F(r) ∝ r⁻³(1 - √(r_in/r))
                // Visual gain factor applied for visual range (not a physical parameter)
                float profile = (1.0 - sqrt(DISK_IN / hr))
                              * (1.0 - smoothstep(0.90, 0.995, DISK_IN / hr));
                profile *= 3.0;
                float angle = atan(hitDisk.z, hitDisk.x);

                // Turbulence factorized call
                float turb = diskTurbulence(hitDisk.xz, uTime, uRealistic > 0.5);
                float turbFactor = 0.6 + 0.4 * turb;
                vec3 discCol = blackbody(tNorm) * profile * turbFactor * 2.5;

                // ═══ Doppler beaming + gravitational redshift ═══
                // Orbital velocity measured by static observer in Schwarzschild:
                //   β = √(M / (r - 2M))
                float beta = sqrt(M / max(hr - 2.0 * M, 0.01));
                beta = clamp(beta, 0.0, BETA_MAX);

                // Tangential velocity (azimuthal direction in disk frame)
                vec3 vTangentDisk = vec3(-sin(angle), 0.0, cos(angle));
                // Transform to world space
                vec3 vTangent = vec3(
                    vTangentDisk.x,
                    vTangentDisk.y * uDiskCos + vTangentDisk.z * uDiskSin,
                    -vTangentDisk.y * uDiskSin + vTangentDisk.z * uDiskCos
                );

                // Direction from disk hit to camera (in static frame at disk)
                vec3 dirCam = normalize(ro - hit);

                // cosφ = angle between velocity and photon direction (static frame)
                float cosPhi = dot(vTangent, dirCam);

                // Correct redshift factor: g = √(1-2M/r) / [γ(1 - β·cosφ)]
                // Uses cosφ directly (emission angle in static frame) — no aberration needed.
                float gamma = 1.0 / sqrt(max(0.01, 1.0 - beta * beta));
                float dopplerDenom = max(0.01, gamma * (1.0 - beta * cosPhi));
                float gravRedshiftFactor = sqrt(max(0.01, 1.0 - EH / hr));
                float g = gravRedshiftFactor / dopplerDenom;

                // Beaming: g³ for monochromatic flux
                float beamingFactor = g * g * g;
                beamingFactor = clamp(beamingFactor, BEAM_MIN, BEAM_MAX);
                discCol *= beamingFactor;

                // Color shift from gravitational redshift
                vec3 hotColor = vec3(1.0, 0.95, 0.85);
                vec3 coolColor = vec3(0.85, 0.4, 0.1);
                discCol = mix(discCol, discCol * mix(coolColor, hotColor, gravRedshiftFactor), COLOR_MIX);

                // Vertical Gaussian profile
                float zf = exp(-hitDisk.y * hitDisk.y / (2.0 * DISK_SIGMA * DISK_SIGMA));
                discCol *= zf;

                // ═══ Photon ring boost + orbit falloff ═══
                float numOrbits = totalAngle / (2.0 * PI);

                // Photon ring boost: rays near 1 orbit get enhanced brightness
                float photonRingBoost = 1.0;
                if (numOrbits >= 0.5 && numOrbits <= 1.5) {
                    photonRingBoost = 1.0 + RING_BOOST * smoothstep(RING_WIDTH, 0.0, abs(numOrbits - 1.0));
                }

                // Smooth falloff for higher-order images
                float orbitFade = 1.0 - smoothstep(ORBIT_FADE_START, ORBIT_FADE_END, numOrbits) * 0.85;
                float directFade = 1.0 - smoothstep(0.0, 0.3, numOrbits) * DIRECT_FADE_MAX;
                float orbitFactor = orbitFade * directFade;

                discCol *= clamp(photonRingBoost, 1.0, 5.0) * orbitFactor;

                // Beer-Lambert accumulation
                diskAcc += discCol * diskTransmittance * DISK_ABS;
                diskTransmittance *= (1.0 - DISK_ABS);
            }
        }
        prevPos = pos;
    }

    // Prevent zero transmittance artifacts
    diskTransmittance = max(diskTransmittance, 0.02);

    vec3 color;

    // Fond noir
    color = vec3(0.0);

    // ── Fond céleste ──
    // Le ray marching a déjà intégré la courbure GR.
    // Pour les fonds non-interagis, on utilise la direction initiale rd
    // corrigée par une deflection faible en champ lointain.
    vec3 dir = rd;
    if (!captured && b > 0.01) {
        // Approximate deflection angle: Δθ = 4M / b
        float deflection = 4.0 * M / b;
        vec3 toCenter = normalize(-ro);
        vec3 deflectionDir = normalize(toCenter - dot(toCenter, rd) * rd);
        dir = normalize(rd + deflectionDir * deflection);
    }

    // Voie lactée : bande colorée
    float band = abs(dir.y * 0.8 + dir.z * 0.6);
    float bandMask = smoothstep(0.15, 0.0, band);

    float angle = atan(dir.z, dir.x);
    float n1 = sin(angle * 3.0 + dir.y * 2.0);
    float n2 = sin(angle * 5.0 - dir.y * 3.0 + 1.0);
    float n3 = sin(angle * 8.0 + dir.y * 5.0 + 2.0);
    float neb = (n1 * 0.5 + n2 * 0.3 + n3 * 0.2) * 0.5 + 0.5;
    neb *= bandMask;

    // Background nebula
    vec3 nebColor = nebulaColor(dir, 3.0) * neb * 0.8;

    color += nebColor;

    // Étoiles (seulement si le rayon n'a interagi avec le disque)
    if (!rayInteracted) {
        vec3 bg = starfield(dir);
        color = mix(color, bg, 0.3);
    }

    // Disque par-dessus
    color = mix(color, diskAcc, 1.0 - diskTransmittance);

    // Ombre du trou noir : rays captured and NOT passing through disk first
    if (captured && diskTransmittance > 0.99) {
        color = vec3(0.0);
    }

    // ── Tone mapping — ACES filmic (replaces Reinhard) ──
    color = (color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14);
    color = clamp(color, 0.0, 1.0);

    return vec4(color, 1.0);
}

void main() {
    vec2 uv = vPosition * 0.5 + 0.5;
    fragColor = rayMarch(uv);
}
