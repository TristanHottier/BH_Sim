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

#define PI           3.14159265359
#define M            0.5
#define EH           1.0          // Event horizon = 2M = 1.0
#define DISK_IN      3.0          // ISCO = 6M for Schwarzschild
#define DISK_OUT     15.0
#define DISK_SIGMA   0.02         // Thin disk, Interstellar-style limb darkening
#define MAX_R        500.0
#define MAX_STEPS    900

// Pré-calculés pour FBM rotation (évite cos/sin par octave)
#define FBM_ROT_C    0.8775825619  // cos(0.5)
#define FBM_ROT_S    0.4794255386  // sin(0.5)

uniform vec3  uCamPos;
uniform float uAspect;
uniform float uFOV;
uniform float uTime;
uniform float uDiskPsi;
uniform float uRealistic;

uniform vec3 camFwd() { return normalize(-uCamPos); }

vec3 camRight() {
    vec3 f = camFwd();
    vec3 up = (abs(f.y) < 0.999) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    return normalize(cross(up, f));
}

vec3 camUp() { return cross(camFwd(), camRight()); }

// Rotate point into disk frame (Y=0 plane), then rotate back.
// cosPsi/sinPsi passed as parameters — no global state.
vec3 diskToDiskFrame(vec3 p, float cosPsi, float sinPsi) {
    // Rotate around X axis: Y' = Y*c - Z*s, Z' = Y*s + Z*c
    return vec3(p.x, p.y * cosPsi - p.z * sinPsi, p.y * sinPsi + p.z * cosPsi);
}

vec3 diskToWorld(vec3 p, float cosPsi, float sinPsi) {
    // Inverse rotation (same as transpose for rotation around X)
    return vec3(p.x, p.y * cosPsi + p.z * sinPsi, -p.y * sinPsi + p.z * cosPsi);
}

// ── Turbulence animée du disque ──────────────────────────────────────────────
// Simule des structures spirales et des turbulences dans le gaz d'accrétion
// en décalant l'angle azimutal en fonction du rayon et du temps.

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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

// FBM sans mat2 : rotation explicite avec constantes pré-calculées
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        // Rotation explicite au lieu de mat2
        float px = p.x * FBM_ROT_C - p.y * FBM_ROT_S;
        float py = p.x * FBM_ROT_S + p.y * FBM_ROT_C;
        p = vec2(px, py) * 2.0;
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

// Facteur de turbulence : version choisie
float diskTurbulence(vec2 diskPos, float time) {
    if (uRealistic > 0.5) {
        return diskTurbulenceKepler(diskPos, time);
    }
    return diskTurbulenceCine(diskPos, time);
}

// ── Schwarzschild null geodesic acceleration (post-Newtonian) ───────────────
//
//   d²x⃗/dλ² = -(3M/r³) · [x⃗ - 4(x⃗·v⃗)v⃗]
//
//   r2 passed as parameter to avoid redundant dot(x,x) from caller.
//
//   This gives:
//     - Weak-field deflection: Δθ = 4M/b  (Einstein angle)
//     - Photon sphere at r = 3M = 1.5
//     - Critical impact parameter: b_crit = 3√3 M ≈ 2.598
vec3 gravAccel(vec3 x, vec3 v, float r2) {
    if (r2 < EH * EH * 0.1) return vec3(0.0);
    float r = sqrt(r2);
    float r3 = r2 * r;

    float coeff = -3.0 * M / r3;
    float vx = dot(v, x);

    // x⃗ - 4(x⃗·v⃗)v⃗
    vec3 correction = x - 4.0 * vx * v;

    return coeff * correction;
}

// ═══ Star field hash functions ═══
// Seeded with uCamPos.y for slight variation with camera height.

float hash1(vec3 p) {
    vec3 s = vec3(123.34, 456.21, 789.98);
    p = fract(p * s);
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

    return starColor;
}

// ── Shared nebula function (factorized from starfield + rayMarch) ────────────
vec3 nebula(vec3 dir, bool inStarfield) {
    // Nébuleuse : bruit sinusoïdal sur la sphère céleste
    float n1 = sin(dir.x * 3.0 + dir.y * 2.0 + dir.z * 1.5);
    float n2 = sin(dir.x * 5.0 - dir.y * 4.0 + dir.z * 3.0 + 1.0);
    float n3 = sin(dir.x * 7.0 + dir.y * 6.0 - dir.z * 5.0 + 2.0);
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

    if (inStarfield) {
        return nebColor * neb * 2.0;
    }

    // Voie lactée : bande colorée (seulement dans rayMarch, pas dans starfield)
    float band = abs(dir.y * 0.8 + dir.z * 0.6);
    float bandMask = smoothstep(0.15, 0.0, band);

    float angle = atan(dir.z, dir.x);
    float n1b = sin(angle * 3.0 + dir.y * 2.0);
    float n2b = sin(angle * 5.0 - dir.y * 3.0 + 1.0);
    float n3b = sin(angle * 8.0 + dir.y * 5.0 + 2.0);
    float nebB = (n1b * 0.5 + n2b * 0.3 + n3b * 0.2) * 0.5 + 0.5;
    nebB *= bandMask;

    float hueB = n1b * 0.5 + 0.5;
    vec3 nebColorB;
    if (hueB < 0.33) {
        nebColorB = mix(vec3(0.0, 0.05, 0.4), vec3(0.05, 0.15, 0.6), hueB * 3.0);
    } else if (hueB < 0.66) {
        nebColorB = mix(vec3(0.05, 0.15, 0.6), vec3(0.1, 0.3, 0.85), (hueB - 0.33) * 3.0);
    } else {
        nebColorB = mix(vec3(0.1, 0.3, 0.85), vec3(0.2, 0.45, 1.0), (hueB - 0.66) * 3.0);
    }

    return nebColor * neb * 2.0 + nebColorB * nebB * 0.8;
}

// ═══ Approximation réaliste d'un corps noir (Munnich 2004) ═══
// Convertit une température normalisée [0,1] en couleur RGB.
// Branchless : mix conditionnel sans if/else pour meilleure perf GPU.
vec3 blackbody(float t) {
    float temp = 1500.0 + t * 10500.0;
    float tt;

    // Phase rouge (1500–3500K)
    float maskR = step(temp, 3500.0);
    // Phase orange (3500–6000K)
    float maskO = step(3500.0, temp) * step(temp, 6000.0);
    // Phase blanc chaud (6000–9000K)
    float maskW = step(6000.0, temp) * step(temp, 9000.0);
    // Phase blanc (9000–12000K)
    float maskB = step(9000.0, temp);

    vec3 cR = mix(vec3(0.08, 0.02, 0.0), vec3(0.95, 0.3, 0.02), (temp - 1500.0) / 2000.0);
    vec3 cO = mix(vec3(0.95, 0.3, 0.02), vec3(1.0, 0.75, 0.25), (temp - 3500.0) / 2500.0);
    vec3 cW = mix(vec3(1.0, 0.75, 0.25), vec3(1.0, 0.95, 0.85), (temp - 6000.0) / 3000.0);
    vec3 cB = mix(vec3(1.0, 0.95, 0.85), vec3(0.9, 0.93, 1.0), (temp - 9000.0) / 3000.0);

    return cR * maskR + cO * maskO + cW * maskW + cB * maskB;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  RAY MARCHING 3D avec RK4
//
//  Intégration du système d'ordre 1 :
//    dx/dλ = v
//    dv/dλ = gravAccel(pos, v, r2)
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

    // Precompute disk tilt trig ONCE per pixel (not per step!)
    float cosPsi = cos(uDiskPsi);
    float sinPsi = sin(uDiskPsi);

    // Tracking pour l'anneau de photons
    float totalAngle = 0.0;
    float prevAzimuth = atan(pos.z, pos.x);
    bool tracking = true;

    int orbitCount = 0;
    float lastAngleThreshold = PI;
    bool stuck = false;

    // Impact parameter — Schwarzschild photon capture threshold
    // Photon sphere at r = 3M, critical impact parameter b_crit = 3√3 M
    // GR-corrected: b_GR = b / sqrt(1 - 2M/r_cam)
    vec3 crossProd = cross(ro, rd);
    float b = length(crossProd);
    float b_crit = 3.0 * sqrt(3.0) * M;
    float camDist = length(ro);
    bool captured = (b < b_crit * sqrt(max(0.01, 1.0 - EH / camDist)));

    bool rayInteracted = false;

    for (int i = 0; i < MAX_STEPS; i++) {
        float r2 = dot(pos, pos);
        float r = sqrt(r2);

        if (r < EH && captured) break;
        if (r < EH && !captured) { captured = true; break; }
        if (r > MAX_R) break;
        if (stuck) break;

        // ── Pas adaptatif — formule analytique au lieu de 8 if/else ──
        // h ≈ 0.01 * r^1.8, borné entre 0.005 et 2.0
        float h = clamp(0.01 * pow(r, 1.8), 0.005, 2.0);

        // RK4 — 4 evaluations of acceleration at intermediate positions
        // NOTE: NO normalize() on intermediate velocities — standard RK4
        vec3 a1 = gravAccel(pos, vel, r2);
        vec3 k1p = vel, k1v = a1;

        vec3 p2 = pos + 0.5*h*k1p;
        vec3 v2 = vel + 0.5*h*k1v;
        float r2_2 = dot(p2, p2);
        vec3 a2 = gravAccel(p2, v2, r2_2);
        vec3 k2p = vel + 0.5*h*k1v, k2v = a2;

        vec3 p3 = pos + 0.5*h*k2p;
        vec3 v3 = vel + 0.5*h*k2v;
        float r2_3 = dot(p3, p3);
        vec3 a3 = gravAccel(p3, v3, r2_3);
        vec3 k3p = vel + 0.5*h*k2v, k3v = a3;

        vec3 p4 = pos + h*k3p;
        vec3 v4 = vel + h*k3v;
        float r2_4 = dot(p4, p4);
        vec3 a4 = gravAccel(p4, v4, r2_4);
        vec3 k4p = vel + h*k3v, k4v = a4;

        prevPos = pos;
        pos = pos + (h/6.0) * (k1p + 2.0*k2p + 2.0*k3p + k4p);
        vel = normalize(vel + (h/6.0) * (k1v + 2.0*k2v + 2.0*k3v + k4v));

        // ── Tracking des orbites pour l'anneau de photons ──
        // Calculé une seule fois par étape, réutilisé pour intersection disque
        vec3 posD = diskToDiskFrame(pos, cosPsi, sinPsi);

        if (tracking && r > EH && r < 50.0) {
            vec3 lastPosD = diskToDiskFrame(lastPos, cosPsi, sinPsi);

            // Angle orbital : différence d'azimut dans le plan du disque
            float currentAzimuth = atan(posD.z, posD.x);
            float deltaAz = currentAzimuth - prevAzimuth;
            // Unwrap : gérer le saut -π → +π
            if (deltaAz > PI) deltaAz -= 2.0 * PI;
            if (deltaAz < -PI) deltaAz += 2.0 * PI;

            totalAngle += max(deltaAz, 0.0);
            prevAzimuth = currentAzimuth;

            // Compter les demi-tours complets (seuils de PI)
            float currentAngleThreshold = floor(totalAngle / PI);
            if (currentAngleThreshold > lastAngleThreshold) {
                orbitCount = int(currentAngleThreshold);
                lastAngleThreshold = currentAngleThreshold;
            }
            // Arrêter le tracking si on est loin ou trop proche
            if (r > 30.0 || r < EH) tracking = false;

            // Safeguard : orbites multiples → rayon piégé
            if (orbitCount > 3) stuck = true;
        }

        // ── Intersection disque (y=0, incliné par uDiskPsi) ──
        vec3 prevDisk = diskToDiskFrame(prevPos, cosPsi, sinPsi);
        float prevYDisk = prevDisk.y;

        if (prevYDisk * posD.y < 0.0) {
            float t = prevYDisk / (prevYDisk - posD.y);
            vec3 hitDisk = prevDisk + t * (posD - prevDisk);
            vec3 hit = diskToWorld(hitDisk, cosPsi, sinPsi);
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

                // Turbulence
                vec2 diskUV = hitDisk.xz;
                float turb = diskTurbulence(diskUV, uTime);
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
                    vTangentDisk.y * cosPsi + vTangentDisk.z * sinPsi,
                    -vTangentDisk.y * sinPsi + vTangentDisk.z * cosPsi
                );

                // Direction from disk hit to camera (in static frame at disk)
                vec3 dirCam = normalize(ro - hit);

                // cosφ = angle between velocity and photon direction (static frame)
                float cosPhi = dot(vTangent, dirCam);

                // Correct redshift factor: g = √(1-2M/r) / [γ(1 - β·cosφ)]
                float gamma = 1.0 / sqrt(max(0.01, 1.0 - beta * beta));
                float dopplerDenom = max(0.01, gamma * (1.0 - beta * cosPhi));
                float gravRedshiftFactor = sqrt(max(0.01, 1.0 - EH / hr));
                float g = gravRedshiftFactor / dopplerDenom;

                // Beaming: g^4 for integrated blackbody flux (correct for Planck spectrum)
                float beamingFactor = g * g * g * g;
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

                // Beer-Lambert accumulation — absorption depends on local optical depth
                float diskAbsorption = clamp(0.6 * zf * turbFactor, 0.05, 0.8);
                diskAcc += discCol * diskTransmittance * diskAbsorption;
                diskTransmittance *= (1.0 - diskAbsorption);
            }
        }
        prevPos = pos;
    }

    // Limiter
    diskAcc = clamp(diskAcc, 0.0, 10.0);
    diskTransmittance = max(diskTransmittance, 0.02);
    vec3 color;

    // Fond noir
    color = vec3(0.0);

    // ── Fond céleste ──
    // Utilise la direction FINALE du ray marching (pos - ro) au lieu de rd
    // corrigée par une deflection analytique — évite le double-comptage.
    vec3 dir;
    if (!captured && b > 0.01) {
        // Direction finale après courbure GR intégrée par le ray marching
        dir = normalize(pos - ro);
    } else {
        dir = rd;
    }

    // Nébuleuse factorisée (shared between starfield and background)
    color += nebula(dir, false);

    // Étoiles (seulement si le rayon n'a interagi avec le disque)
    if (!rayInteracted) {
        vec3 bg = starfield(dir);
        color = mix(color, bg, 0.3);
    }

    // Disque par-dessus
    color = mix(color, diskAcc, 1.0 - diskTransmittance);

    // Ombre du trou noir : rays captured and NOT passing through disk first
    // Seuil ramené à 0.95 avec blend doux au lieu de > 0.99 binaire
    if (captured) {
        float shadowAlpha = 1.0 - smoothstep(0.95, 1.0, diskTransmittance);
        color = mix(color, vec3(0.0), shadowAlpha);
    }

    // ── Tone mapping ──
    color = color / (1.0 + color);
    color = clamp(color, 0.0, 1.0);

    return vec4(color, 1.0);
}

void main() {
    vec2 uv = vPosition * 0.5 + 0.5;
    fragColor = rayMarch(uv);
}
