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
#define RS           1.0
#define M            0.5
#define ALPHA        8.0
#define EH           1.0
#define DISK_IN      3.0   // ISCO = 6M for Schwarzschild (M=0.5 → 3.0)
#define DISK_OUT     25.0
#define DISK_SIGMA   0.10
#define MAX_R        500.0
#define GM           0.5
#define TURB_N       6.0

uniform vec3  uCamPos;
uniform float uAspect;
uniform float uFOV;
uniform float uTime;
uniform vec2  uScreenPx;
uniform float uDiskPsi;
uniform float uRealistic;
uniform float uTimeOffset;
uniform float uSeed;
uniform float uShowShadow;


vec3 camFwd() { return normalize(-uCamPos); }

vec3 camRight() {
    vec3 f = camFwd();
    vec3 up = (abs(f.y) < 0.999) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    return normalize(cross(up, f));
}

vec3 camUp() { return cross(camFwd(), camRight()); }

// Rotate disk around X axis by uDiskPsi (tilts the disk plane)
// Original disk: Y=0 plane. Rotation around X tilts it
vec3 diskRotate(vec3 p) {
    float c = cos(uDiskPsi);
    float s = sin(uDiskPsi);
    // Rotate point around X axis: Y' = Y*c - Z*s, Z' = Y*s + Z*c
    return vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
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

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
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
    float t = time + uTimeOffset;

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
    float t = time + uTimeOffset;
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

vec3 gravAccel(vec3 x, vec3 v) {
    float r2 = dot(x, x);
    if (r2 < 0.001) return vec3(0.0);
    float r = sqrt(r2);
    float r3 = r2 * r;

    // Correct Schwarzschild light geodesic acceleration (post-Newtonian form):
    //   d²x⃗/dλ² = -(3M/r³) · [x⃗ - 4(x⃗·v⃗)v⃗]
    //
    // Radial term:  -3M/r³ · x⃗    (inward pull, coefficient 3M not ALPHA·M)
    // Velocity term: +12M/r³ · (x⃗·v⃗) · v⃗   (reduces inward pull when
    //   receding, increases when approaching — produces correct bending)
    //
    // This gives:
    //   - Weak-field deflection: Δθ = 4M/b  (Einstein angle)
    //   - Photon sphere at r = 3M = 1.5
    //   - Critical impact parameter: b_crit = 3√3 M ≈ 2.598

    float coeff = -3.0 * M / r3;
    float vx = dot(v, x);

    // x⃗ - 4(x⃗·v⃗)v⃗
    vec3 correction = x - 4.0 * vx * v;

    return coeff * correction;
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

    // ── Nébuleuse : bruit sinusoïdal sur la sphère céleste ──
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

    vec3 nebResult = nebColor * neb * 2.0;

    return nebResult + starColor;
}

// ═══ Approximation réaliste d'un corps noir (Munnich 2004) ═══
// Convertit une température normalisée [0,1] en couleur RGB.
// Utilise les équations de Munnich pour une approximation rapide
// de la loi de Planck, avec extrapolation linéaire au-delà de 6500K.
vec3 blackbody(float t) {
    // t ∈ [0, 1] → température effective [1000K, 10000K]
    float temp = 1000.0 + t * 9000.0;

    vec3 color;

    // Phase rouge (1000–2200K)
    if (temp <= 2200.0) {
        float tt = (temp - 1000.0) / 1200.0;
        color = mix(vec3(0.1, 0.02, 0.0), vec3(0.95, 0.35, 0.02), tt);
    }
    // Phase orange (2200–4000K)
    else if (temp <= 4000.0) {
        float tt = (temp - 2200.0) / 1800.0;
        color = mix(vec3(0.95, 0.35, 0.02), vec3(1.0, 0.75, 0.3), tt);
    }
    // Phase blanc chaud (4000–6500K)
    else if (temp <= 6500.0) {
        float tt = (temp - 4000.0) / 2500.0;
        color = mix(vec3(1.0, 0.75, 0.3), vec3(1.0, 0.95, 0.87), tt);
    }
    // Phase blanc froid (6500–10000K)
    else {
        float tt = (temp - 6500.0) / 3500.0;
        color = mix(vec3(1.0, 0.95, 0.87), vec3(0.85, 0.9, 1.0), tt);
    }

    return color;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  RAY MARCHING 3D avec RK4 CORRECT
//
//  Le problème du RK4 précédent était que la normalisation de vel annulait
//  la courbure. Solution : on ne normalise vel qu'au début, et on laisse
//  le RK4 mettre à jour la vélocité correctement.
//
//  Formulation : on intègre le système d'ordre 1 :
//    dx/dλ = v
//    dv/dλ = -3M·x/r³
//  Puis on normalise v à la fin de chaque pas RK4 complet.
//
//  La clé : le RK4 calcule k1v, k2v, k3v, k4v en évaluant l'accélération
//  à des positions intermédiaires. Ces accélérations sont NON nulles et
//  NON colinéaires avec v (car les positions intermédiaires ne sont pas
//  sur la ligne droite initiale). Donc v est bien modifié en direction.
// ═══════════════════════════════════════════════════════════════════════════════

vec4 rayMarch(vec2 uv) {
    vec2 px = uScreenPx;

    vec3 ro = uCamPos;
    float tanFov = tan(uFOV * 0.5);
    vec2 xy = (uv - 0.5) * vec2(uAspect, 1.0) * 2.0 * tanFov;
    vec3 rd = normalize(camFwd() + camRight() * xy.x + camUp() * xy.y);

    vec3 pos = ro;
    vec3 vel = rd;

    vec3 prevPos = ro;

    // Accumulation du disque — Beer-Lambert law avec transparence progressive
    vec3 diskAcc = vec3(0.0);
    float diskTransmittance = 1.0;
    float diskOpticalDepth = 0.0;

    // Tracking pour l'anneau de photons : compteur d'orbites
    float totalAngle = 0.0;
    vec3 lastPos = ro;
    bool tracking = true;

    // Tracking du nombre d'orbites complètes (pour artefact ordre 2)
    int orbitCount = 0;
    float lastAngleThreshold = PI;

    // Impact parameter — correct Schwarzschild photon capture threshold
    // Photon sphere at r = 3M, critical impact parameter b_crit = 3√3 M
    vec3 crossProd = cross(ro, rd);
    float b = length(crossProd);
    float b_crit = 3.0 * sqrt(3.0) * M;
    bool captured = (b < b_crit);

    // Flag: track whether ray has interacted with disk or been captured
    bool rayInteracted = false;

 for (int i = 0; i < 200; i++) {
        float r = length(pos);

        if (r < EH && captured) break;
        if (r < EH && !captured) { captured = true; break; }
        if (r > MAX_R) break;

   // ── Pas adaptatif ──
        float h;
        if (r < 2.0) h = 0.01;
        else if (r < 3.0) h = 0.015;
        else if (r < 6.0) h = 0.03;
        else if (r < 12.0) h = 0.15;
        else if (r < 30.0) h = 0.6;
        else h = 1.5;

   // RK4 — on évalue l'accélération à 4 positions intermédiaires
        // Chaque position intermédiaire est DÉCALÉE par rapport à la ligne droite,
        // donc l'accélération n'est PAS colinéaire avec vel → courbure réelle.
        vec3 a1 = gravAccel(pos, vel);
        vec3 k1p = vel, k1v = a1;

        vec3 p2 = pos + 0.5*h*k1p;
        vec3 v2 = vel + 0.5*h*k1v;
        vec3 a2 = gravAccel(p2, normalize(v2));
        vec3 k2p = vel + 0.5*h*k1v, k2v = a2;

        vec3 p3 = pos + 0.5*h*k2p;
        vec3 v3 = vel + 0.5*h*k2v;
        vec3 a3 = gravAccel(p3, normalize(v3));
        vec3 k3p = vel + 0.5*h*k2v, k3v = a3;

        vec3 p4 = pos + h*k3p;
        vec3 v4 = vel + h*k3v;
        vec3 a4 = gravAccel(p4, normalize(v4));
        vec3 k4p = vel + h*k3v, k4v = a4;

        prevPos = pos;
        pos = pos + (h/6.0) * (k1p + 2.0*k2p + 2.0*k3p + k4p);
        vel = normalize(vel + (h/6.0) * (k1v + 2.0*k2v + 2.0*k3v + k4v));

// ── Tracking des orbites pour l'anneau de photons ──
        if (tracking && r > EH && r < 50.0) {
            vec3 posD = diskRotate(pos);
            vec3 lastPosD = diskRotate(lastPos);
            vec3 deltaD = posD - lastPosD;

            // Angle balayé dans le plan du disque (X-Z plane of disk frame)
            float crossMag = abs(deltaD.x * lastPosD.z - deltaD.z * lastPosD.x);
            float dotXZ = dot(deltaD.xz, lastPosD.xz);
            // Use length of XZ projection for correct 2D angle in disk plane
            float angleStep = atan(crossMag, dotXZ / length(lastPosD.xz));
            totalAngle += max(angleStep, 0.0);
            lastPos = pos;

            // Compter les demi-tours complets (seuils de PI)
            float currentAngleThreshold = floor(totalAngle / PI);
            if (currentAngleThreshold > lastAngleThreshold) {
                orbitCount = int(currentAngleThreshold);
                lastAngleThreshold = currentAngleThreshold;
            }
            // Arrêter le tracking si on est loin ou trop proche
            if (r > 30.0 || r < EH) tracking = false;
        }

  // ── Intersection disque (y=0, incliné par uDiskPsi) ──
        // On transforme la position dans le repère du disque incliné
        vec3 posDisk = diskRotate(pos);
        vec3 prevDisk = diskRotate(prevPos);
        float prevYDisk = prevDisk.y;

        if (prevYDisk * posDisk.y < 0.0) {
            float t = prevYDisk / (prevYDisk - posDisk.y);
            vec3 hitDisk = prevDisk + t * (posDisk - prevDisk);
            // hitDisk est dans le repère du disque, on le remet dans le repère monde
            vec3 hit = diskRotate(hitDisk);
            // hitDisk.xz donne le rayon dans le plan du disque
            float hr = length(hitDisk.xz);

            if (hr >= DISK_IN && hr <= DISK_OUT) {
                rayInteracted = true;

                // Novikov-Thorne temperature profile: T ∝ (1 - r_in/r)^(3/4)
                float temp = pow(1.0 - DISK_IN / hr, 0.75);
                float profile = pow(1.0 - DISK_IN / hr, 0.1) * (1.0 - smoothstep(0.90, 0.995, DISK_IN / hr));
                float angle = atan(hitDisk.z, hitDisk.x);

                // Turbulence animée : module de densité du gaz
                vec2 diskUV = hitDisk.xz;
                float turb = diskTurbulence(diskUV, uTime);
                float turbFactor = 0.6 + 0.4 * turb; // 0.6..1.0
                vec3 discCol = blackbody(temp) * profile * turbFactor;

// ═══ Redshift total g = √(1-2M/r) / [γ(1-β·cosφ)] combiné + beaming ═══
                // Orbital velocity in Schwarzschild (measured by static observer):
                //   β = √(M / (r - 2M))   — diverges at photon sphere r = 2M
                float beta = sqrt(M / (hr - 2.0 * M));
                beta = clamp(beta, 0.0, 0.95);

                vec3 vTangentDisk = vec3(-sin(angle), 0.0, cos(angle));
                vec3 vTangent = vec3(
                    vTangentDisk.x,
                    vTangentDisk.y * cos(uDiskPsi) - vTangentDisk.z * sin(uDiskPsi),
                    vTangentDisk.y * sin(uDiskPsi) + vTangentDisk.z * cos(uDiskPsi)
                );
                vec3 dirCam = normalize(ro - hit);
                float cosPhi = dot(vTangent, dirCam);

                // Aberration of light: transform emission-frame angle to observer frame
                // cosφ_obs = (cosφ_em + β) / (1 + β·cosφ_em)
                float cosPhiObs = (cosPhi + beta) / (1.0 + beta * cosPhi);

                // Combined redshift factor g = √(1-2M/r) / (γ·(1-β·cosφ_obs))
                float gamma = 1.0 / sqrt(max(0.01, 1.0 - beta * beta));
                float dopplerDenom = max(0.01, gamma * (1.0 - beta * cosPhiObs));
                float gravRedshiftFactor = sqrt(max(0.01, 1.0 - EH / hr));
                float g = gravRedshiftFactor / dopplerDenom;

                // Beaming: flux factor = g³ for monochromatic flux
                float beamingFactor = g * g * g;
                beamingFactor = clamp(beamingFactor, 0.001, 5.0);
                discCol *= beamingFactor;

                // Color shift from redshift: mix towards red at high z
                vec3 hotColor = vec3(1.0, 0.95, 0.85);
                vec3 coolColor = vec3(0.85, 0.4, 0.1);
                discCol = mix(discCol, discCol * mix(coolColor, hotColor, gravRedshiftFactor), 0.3);

                float zf = exp(-hitDisk.y * hitDisk.y / (2.0 * DISK_SIGMA * DISK_SIGMA));
                discCol *= zf;

 // ═══ Anneau de photons + atténuation progressive des images d'ordre élevé ═══
                float numOrbits = totalAngle / (2.0 * PI);

                // Photon ring boost: smooth peak around numOrbits = 1.0
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

                // Beer-Lambert accumulation: each crossing contributes
                // weighted by current transmittance. Disk becomes optically
                // thick after several crossings.
                float diskAbsorption = 0.6;
                diskAcc += discCol * diskTransmittance * diskAbsorption;
                diskTransmittance *= (1.0 - diskAbsorption);
                diskOpticalDepth += diskAbsorption;
            }
        }
        prevPos = pos;
    }

    // Limiter
    diskAcc = clamp(diskAcc, 0.0, 3.0);
    diskTransmittance = max(diskTransmittance, 0.02);
   vec3 color;

   // Fond noir
    color = vec3(0.0);

    // ── Fond céleste : projeté dans la direction initiale du rayon (rd) ──
    // CORRECTION: utilise rd (direction initiale) au lieu de pos-ro
    // pour que le fond soit correctement projeté sur la sphère céleste.
    vec3 dir = rd;

    // Voie lactée : bande colorée passant par le centre (trou noir)
    // Distance à un grand cercle passant par le centre (plan incliné) — bande très fine
    float band = abs(dir.y * 0.8 + dir.z * 0.6); // plan incliné
    float bandMask = smoothstep(0.15, 0.0, band);   // bande très fine

    // Texture de la bande : sinusoides le long du plan
    float angle = atan(dir.z, dir.x);
    float n1 = sin(angle * 3.0 + dir.y * 2.0);
    float n2 = sin(angle * 5.0 - dir.y * 3.0 + 1.0);
    float n3 = sin(angle * 8.0 + dir.y * 5.0 + 2.0);
    float neb = (n1 * 0.5 + n2 * 0.3 + n3 * 0.2) * 0.5 + 0.5;
    neb *= bandMask;

    // Teinte bleue le long de la bande
    float hue = n1 * 0.5 + 0.5;
    vec3 nebColor;
    if (hue < 0.33) {
        nebColor = mix(vec3(0.0, 0.05, 0.4), vec3(0.05, 0.15, 0.6), hue * 3.0);
    } else if (hue < 0.66) {
        nebColor = mix(vec3(0.05, 0.15, 0.6), vec3(0.1, 0.3, 0.85), (hue - 0.33) * 3.0);
    } else {
        nebColor = mix(vec3(0.1, 0.3, 0.85), vec3(0.2, 0.45, 1.0), (hue - 0.66) * 3.0);
    }

    color += nebColor * neb * 0.8;

    // Étoiles par-dessus (seulement si le rayon n'a interagi avec rien)
    // CORRECTION: le fond n'est ajouté qu'aux rayons non-interagis
    if (!rayInteracted) {
        vec3 bg = starfield(dir);
        color = mix(color, bg, 0.3);
    }

    // Disque par-dessus (transparence gérée par diskTransmittance)
    color = mix(color, diskAcc, 1.0 - diskTransmittance);

    // Ombre du trou noir
    // Shadow: captured rays that didn't hit any disk region
    if (captured && diskOpticalDepth < 0.01) {
        color = vec3(0.0);
    }

  // ═══ Glow émissif du disque ═══
    {
        // Projeter le disque (anneau dans plan incliné) sur l'écran.
        // Le disque est dans le plan y=0, incliné par uDiskPsi autour de X.
        // Normal du plan incliné : n = (0, cosψ, sinψ)
        vec3 diskNormal = vec3(0.0, cos(uDiskPsi), sin(uDiskPsi));
        vec3 dir = normalize(pos - ro);
        // Distance signée du rayon au plan du disque
        float distPlane = dot(dir, diskNormal);
        // Si le rayon est proche du plan du disque, projeter sur l'écran
        if (abs(distPlane) < 0.08) {
            // Point d'intersection du rayon avec le plan du disque
            float tPlane = -dot(ro, diskNormal) / dot(dir, diskNormal);
            if (tPlane > 0.0) {
                vec3 hitPlane = ro + tPlane * dir;
                // Remettre dans le repère non incliné pour mesurer le rayon
                float c = cos(-uDiskPsi);
                float s = sin(-uDiskPsi);
                float rx = hitPlane.x;
                float ry = hitPlane.y * c - hitPlane.z * s;
                float rz = hitPlane.y * s + hitPlane.z * c;
                float r = length(vec2(rx, rz));
                // Bord intérieur et extérieur du disque
                float innerGlow = smoothstep(DISK_IN * 0.85, DISK_IN * 1.05, r) * smoothstep(DISK_IN * 1.5, DISK_IN * 1.05, r);
                float outerGlow = smoothstep(DISK_OUT * 1.05, DISK_OUT * 0.85, r) * smoothstep(DISK_OUT * 1.5, DISK_OUT * 0.85, r);
                float glow = (innerGlow + outerGlow) * 0.12;
                vec3 glowColor = mix(vec3(1.0, 0.6, 0.15), vec3(1.0, 0.35, 0.05), 1.0 - r / DISK_OUT) * glow;
                color += glowColor;
            }
        }
    }

  // ═══ Bord d'ombre + photon sphere glow ═══
    {
        float screenDist = length(xy);
        float camDistVal = length(ro);
        float R_shadow = b_crit / (camDistVal * tanFov);
        float r_normalized = screenDist / R_shadow;
        float shadowEdge = smoothstep(1.0, 1.08, r_normalized) * smoothstep(1.2, 1.0, r_normalized);
        color += vec3(0.12, 0.15, 0.25) * shadowEdge * 0.08;
    }

  // ═══ Cercle blanc délimitant l'ombre du trou noir ═══
    if (uShowShadow > 0.5) {
        float screenDist = length(xy);
        // Same screen-space conversion as the shadow edge glow above
        float R_shadow = b_crit / (length(ro) * tanFov);
        float r_normalized = screenDist / R_shadow;
        float border = smoothstep(0.985, 0.995, r_normalized) * smoothstep(1.005, 0.995, r_normalized);
        color += vec3(1.0) * border;
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
