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
const float DISK_SIGMA   = 0.02;         // Thin disk, Interstellar-style limb darkening
const float MAX_R        = 500.0;
const int MAX_STEPS      = 900;

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
    return fract(sin(dot(p, vec2(127.1 + uSeed * 991.0, 311.7 + uSeed * 743.0))) * 43758.5453);
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
    // Rotation by 0.5 rad (precomputed)
    mat2 rot = mat2(0.8775825619, 0.4794255386, -0.4794255386, 0.8775825619);
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = rot * p * 2.0;
        a *= 0.5;
    }
    return v;
}

// Facteur de turbulence : rotation différentielle réaliste (Kepler)
float diskTurbulenceKepler(vec2 diskPos, float time) {
    float r = length(diskPos);
    float a = atan(diskPos.y, diskPos.x);

    float omega = 12.0 / pow(max(r, 1.0), 1.5);
    float t = time;

    vec2 localUV = diskPos * 1.8;
    float ca = cos(-omega * t * 0.3);
    float sa = sin(-omega * t * 0.3);
    vec2 localRot = vec2(
        localUV.x * ca - localUV.y * sa,
        localUV.x * sa + localUV.y * ca
    );
    float n = fbm(localRot * 1.2);

    float spiral = 3.0 * log(max(r, 0.1)) + 2.0 * (a - omega * t);
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

// Facteur de turbulence : version choisie — factorisée (v1.4.0)
float diskTurbulence(vec2 diskPos, float time, bool realistic) {
    if (realistic) {
        return diskTurbulenceKepler(diskPos, time);
    }
    return diskTurbulenceCine(diskPos, time);
}

// ═══ Schwarzschild null geodesic acceleration (post-Newtonian 1st order) ═══
//
//   d²x⃗/dλ² = -(M/r³) · [x⃗ - 4(x⃗·v⃗)v⃗ + 3(x⃗·v⃗)²/r² · x⃗]
//
//   Radial term:        -M/r³ · x⃗              (inward pull)
//   Velocity term:      +4M/r³ · (x⃗·v⃗) · v⃗   (transverse deflection)
//   Quadratic term:     -3M/r⁵ · (x⃗·v⃗)² · x⃗  (nonlinear correction)
//
//   This gives:
//     - Weak-field deflection: Δθ = 4M/b  (Einstein angle)
//     - Photon sphere at r = 3M = 1.5
//     - Critical impact parameter: b_crit = 3√3 M ≈ 2.598
vec3 gravAccel(vec3 x, vec3 v) {
    float r2 = dot(x, x);
    // Softening instead of zero acceleration near center (v1.4.0)
    if (r2 < 0.001) r2 = 0.001;
    float r = sqrt(r2);
    float r3 = r2 * r;

    float vx = dot(v, x);

    // Correct 1PN Schwarzschild null geodesic acceleration:
    // a = -(M/r³)[x - 4(v·x)v + 3(v·x)²/r² · x]
    vec3 term1 = x;
    vec3 term2 = -4.0 * vx * v;
    vec3 term3 = 3.0 * (vx * vx / r2) * x;

    return -(M / r3) * (term1 + term2 + term3);
}

// ═══ Nébuleuse factorisée (v1.4.0) ═══
// Calcule la couleur et l'intensité de la nébuleuse à partir d'une direction.
vec3 nebulaColor(vec3 dir, float baseHueShift) {
    float n1 = sin(dir.x * 3.0 + dir.y * 2.0 + dir.z * 1.5 + baseHueShift);
    float n2 = sin(dir.x * 5.0 - dir.y * 4.0 + dir.z * 3.0 + 1.0 + baseHueShift);
    float n3 = sin(dir.x * 7.0 + dir.y * 6.0 - dir.z * 5.0 + 2.0 + baseHueShift);
    float neb = (n1 * 0.5 + n2 * 0.3 + n3 * 0.2) * 0.5 + 0.5;

    // Teinte bleu-violet-rose
    float hue = n1 * 0.5 + 0.5;
    vec3 nebColor;
    if (hue < 0.33) {
        nebColor = mix(vec3(0.1, 0.02, 0.35), vec3(0.25, 0.05, 0.45), hue * 3.0);
    } else if (hue < 0.66) {
        nebColor = mix(vec3(0.25, 0.05, 0.45), vec3(0.45, 0.1, 0.35), (hue - 0.33) * 3.0);
    } else {
        nebColor = mix(vec3(0.45, 0.1, 0.35), vec3(0.35, 0.15, 0.45), (hue - 0.66) * 3.0);
    }

    return nebColor * neb;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Étoiles — fond noir pur, étoiles blanches
// ═══════════════════════════════════════════════════════════════════════════════

float hash1(vec3 p) {
    p = fract(p * vec3(123.34, 456.21, 789.98));
    p += dot(p, p.yxz + 19.19);
    return fract((p.x + p.y) * p.z);
}

float hash2(vec3 p) {
    return fract(sin(dot(p, vec3(269.5, 183.3, 419.2))) * 43758.5453);
}

vec3 starfield(vec3 dir) {
    vec3 p = dir * 500.0;
    vec3 id = floor(p);

    float h1 = hash1(id);
    float star = smoothstep(0.9960, 0.99995, h1);
    float h2 = hash2(id);
    float bright = mix(0.5, 2.0, h2);
    float att = 1.0 / (1.0 + length(fract(p)) * 2.0);
    float sc = bright * star * att;

    float h3 = hash1(id * 2.718 + 50.0);
    sc += smoothstep(0.9940, 0.9998, h3) * 0.3;

    float h4 = hash1(id * 3.14159 + 200.0);
    sc += smoothstep(0.9930, 0.9999, h4) * 0.1;

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
//  RAY MARCHING 3D avec RK4
//
//  Intégration du système d'ordre 1 :
//    dx/dλ = v
//    dv/dλ = gravAccel(pos, v)
//  Normalisation de |v|=1 après chaque pas RK4 complet.
// ═══════════════════════════════════════════════════════════════════════════════

vec4 rayMarch(vec2 uv) {
    vec3 ro = uCamPos;
    float tanFov = tan(uFOV * 0.5);
    vec2 xy = (uv - 0.5) * vec2(uAspect, 1.0) * 2.0 * tanFov;
    vec3 rd = normalize(camFwd() + camRight() * xy.x + camUp() * xy.y);

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
    // GR-corrected: b_GR = b * sqrt(1 - 2M/r_cam)   (v1.4.0: * au lieu de /)
    // The local impact parameter at finite distance is b_loc = b_∞ / √(1-2M/r_cam)
    // So the condition b_loc < b_crit becomes: b < b_crit * √(1-2M/r_cam)
    vec3 crossProd = cross(ro, rd);
    float b = length(crossProd);
    float b_crit = 3.0 * sqrt(3.0) * M;
    float camDist = length(ro);
    float gravFactor = sqrt(max(0.01, 1.0 - EH / camDist));
    bool captured = (b < b_crit * gravFactor);  // v1.4.0: * au lieu de /

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
        // v1.4.0: k3p uses k3v (was k2p — corrupted RK4 fixed)
        vec3 a1 = gravAccel(pos, vel);
        vec3 k1p = vel, k1v = a1;

        vec3 p2 = pos + 0.5*h*k1p;
        vec3 v2 = vel + 0.5*h*k1v;
        vec3 a2 = gravAccel(p2, v2);
        vec3 k2v = a2;
        vec3 k2p = vel + 0.5*h*k2v;

        vec3 p3 = pos + 0.5*h*k2p;
        vec3 v3 = vel + 0.5*h*k2v;
        vec3 a3 = gravAccel(p3, v3);
        vec3 k3v = a3;
        vec3 k3p = vel + 0.5*h*k3v;   // v1.4.0: k3v au lieu de k2p

        vec3 p4 = pos + h*k3p;
        vec3 v4 = vel + h*k3v;
        vec3 a4 = gravAccel(p4, v4);
        vec3 k4p = vel + h*k3v;
        vec3 k4v = a4;

        prevPos = pos;
        pos = pos + (h/6.0) * (k1p + 2.0*k2p + 2.0*k3p + k4p);
        vel = normalize(vel + (h/6.0) * (k1v + 2.0*k2v + 2.0*k3v + k4v));

        // ── Tracking des orbites pour l'anneau de photons ──────────────────
        // diskFrame positions computed once per step (v1.4.0: avoid redundant calls)
        vec3 posDF = diskToDiskFrame(pos);
        vec3 prevDF = diskToDiskFrame(prevPos);

        if (tracking && r < 50.0) {
            vec3 posD = posDF;
            vec3 lastPosD = prevDF;
            vec3 deltaD = posD - lastPosD;

            // Angle balayé dans le plan du disque (X-Z plane of disk frame)
            float crossMag = abs(deltaD.x * lastPosD.z - deltaD.z * lastPosD.x);
            float dotXZ = dot(deltaD.xz, lastPosD.xz);
            float rXZ = max(length(lastPosD.xz), 0.01);
            float angleStep = atan(crossMag, dotXZ / rXZ);
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

        // ── Intersection disque (y=0, incliné par uDiskPsi) ────────────────
        // v1.4.0: réutilise posDF/prevDF calculés plus haut
        float prevYDisk = prevDF.y;

        if (prevYDisk * posDF.y < 0.0) {
            float t = prevYDisk / (prevYDisk - posDF.y);
            vec3 hitDisk = prevDF + t * (posDF - prevDF);
            vec3 hit = diskToWorld(hitDisk);
            float hr = length(hitDisk.xz);

            if (hr >= DISK_IN && hr <= DISK_OUT) {
                rayInteracted = true;

                // Novikov-Thorne temperature profile: T ∝ r^(-3/4) * (1 - sqrt(r_in/r))^(1/4)
                float nr = pow(hr, -0.75) * pow(1.0 - sqrt(DISK_IN / hr), 0.25);
                // Peak at r≈4.08, value≈0.214 for DISK_IN=3.0
                float tNorm = clamp(nr / 0.214 * 0.55, 0.0, 1.0);

                // Emissivity profile
                float profile = pow(1.0 - DISK_IN / hr, 0.1)
                              * (1.0 - smoothstep(0.90, 0.995, DISK_IN / hr));
                float angle = atan(hitDisk.z, hitDisk.x);

                // Turbulence — v1.4.0: appel factorisé avec paramètre
                float turb = diskTurbulence(hitDisk.xz, uTime, uRealistic > 0.5);
                float turbFactor = 0.6 + 0.4 * turb;
                vec3 discCol = blackbody(tNorm) * profile * turbFactor * 2.5;

                // ═══ Doppler beaming + gravitational redshift ═══
                // Orbital velocity measured by static observer in Schwarzschild:
                //   β = √(M / (r - 2M))
                float beta = sqrt(M / max(hr - 2.0 * M, 0.01));
                beta = clamp(beta, 0.0, 0.95);

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
                beamingFactor = clamp(beamingFactor, 0.001, 8.0);
                discCol *= beamingFactor;

                // Color shift from gravitational redshift
                vec3 hotColor = vec3(1.0, 0.95, 0.85);
                vec3 coolColor = vec3(0.85, 0.4, 0.1);
                discCol = mix(discCol, discCol * mix(coolColor, hotColor, gravRedshiftFactor), 0.3);

                // Vertical Gaussian profile
                float zf = exp(-hitDisk.y * hitDisk.y / (2.0 * DISK_SIGMA * DISK_SIGMA));
                discCol *= zf;

                // ═══ Photon ring boost + orbit falloff ═══
                float numOrbits = totalAngle / (2.0 * PI);

                // Photon ring boost: rays near 1 orbit get enhanced brightness
                float photonRingBoost = 1.0;
                if (numOrbits >= 0.5 && numOrbits <= 1.5) {
                    float ringWidth = 0.35;
                    photonRingBoost = 1.0 + 4.0 * smoothstep(ringWidth, 0.0, abs(numOrbits - 1.0));
                }

                // Smooth falloff for higher-order images
                float orbitFade = 1.0 - smoothstep(0.5, 2.0, numOrbits) * 0.85;
                float directFade = 1.0 - smoothstep(0.0, 0.3, numOrbits) * 0.1;
                float orbitFactor = orbitFade * directFade;

                discCol *= clamp(photonRingBoost, 1.0, 5.0) * orbitFactor;

                // Beer-Lambert accumulation
                float diskAbsorption = 0.6;
                diskAcc += discCol * diskTransmittance * diskAbsorption;
                diskTransmittance *= (1.0 - diskAbsorption);
            }
        }
        prevPos = pos;
    }

    // v1.4.0: clamp diskAcc removed — tone mapping handles the range
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

    // Nébuleuse background (factorisée v1.4.0)
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

    // ── Tone mapping — ACES (v1.4.0: remplace Reinhard c/(1+c)) ──
    color = (color * (2.51 * color + 0.03)) / (color * (2.43 * color + 0.59) + 0.14);
    color = clamp(color, 0.0, 1.0);

    return vec4(color, 1.0);
}

void main() {
    vec2 uv = vPosition * 0.5 + 0.5;
    fragColor = rayMarch(uv);
}
