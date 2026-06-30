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
#define DISK_IN      1.1
#define DISK_OUT     25.0
#define DISK_SIGMA   0.10
#define CCD          1.0
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
    float ca = cos(-t * 0.15);
    float sa = sin(-t * 0.15);
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

    // Composante radiale (attraction vers le centre)
    vec3 radial = -ALPHA * M * x / (r2 * r);

    // Composante tangentielle : la courbure des géodésiques
    // dépend aussi de la vitesse tangentielle.
    // Terme supplémentaire : -3M * (v·x) / r^3 * v
    // qui représente la déviation transversale de la lumière
    float vx = dot(v, x);
    vec3 tangential = -3.0 * M * vx / (r2 * r) * v;

    return radial + tangential;
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

vec3 blackbody(float t) {
    if (t > 0.7) return mix(vec3(0.6, 0.7, 1.0), vec3(1.0), (t - 0.7) / 0.3);
    if (t > 0.3) return mix(vec3(0.9, 0.5, 0.1), vec3(0.6, 0.7, 1.0), (t - 0.3) / 0.4);
    return mix(vec3(0.8, 0.15, 0.02), vec3(0.9, 0.5, 0.1), t / 0.3);
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

    float prevY = ro.y;
    vec3 prevPos = ro;

    // Accumulation directe du disque
    vec3 diskAcc = vec3(0.0);
    float diskOpacity = 0.0;
    bool diskInFront = false;

    // Tracking pour l'anneau de photons : compteur d'orbites
    float totalAngle = 0.0;
    vec3 lastPos = ro;
    bool tracking = true;

    // Tracking du nombre d'orbites complètes (pour artefact ordre 2)
    int orbitCount = 0;
    float lastAngleThreshold = PI;

    // Impact parameter
    vec3 crossProd = cross(ro, rd);
    float b = length(crossProd);
    float b_crit = 3.0 * sqrt(3.0) * M * (ALPHA / 3.0);
    bool captured = (b < b_crit);

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
            vec3 delta = pos - lastPos;
            // Angle balayé : |delta × lastPos| / |lastPos|²
            float crossMag = abs(delta.x * lastPos.y - delta.y * lastPos.x);
            float angleStep = atan(crossMag, dot(delta, lastPos) / length(lastPos));
            totalAngle += angleStep;
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
                float nr = (hr - DISK_IN) / (DISK_OUT - DISK_IN);
                float temp = pow(1.0 - nr, 0.75);
                float profile = pow(1.0 - nr, 0.1) * (1.0 - smoothstep(0.90, 0.995, nr));
                float angle = atan(hitDisk.z, hitDisk.x);
                
                // Turbulence animée : module de densité du gaz
                vec2 diskUV = hitDisk.xz;
                float turb = diskTurbulence(diskUV, uTime);
                float turbFactor = 0.6 + 0.4 * turb; // 0.6..1.0
                float vOrb = sqrt(GM / hr);
                float doppler = clamp(1.0 + vOrb * sin(angle) * 0.4, 0.3, 2.5);
                float redshift = sqrt(max(0.01, 1.0 - M / hr));
                vec3 discCol = blackbody(temp) * profile * doppler * redshift * 10.0 * turbFactor;

// ═══ Doppler + beaming relativiste dynamique ═══
                // Facteur Doppler : ((1 + β·cosφ) / (1 - β·cosφ))³
                // β = vitesse orbitale normalisée
                // cosφ = projection de la vitesse tangentielle sur la ligne de visée
                // La vitesse tangentielle du gaz est perpendiculaire au rayon radial :
                //   v_tan ∝ (-sin(angle), 0, cos(angle))
                // La ligne de visée depuis le point d'émission vers la caméra :
                //   dir_cam = normalize(ro - hit)
                // cosφ = dot(v_tan, dir_cam) / |v_tan|
                float beta = length(vec3(-sin(angle), 0.0, cos(angle))) * sqrt(GM / hr);
                beta = clamp(beta, 0.0, 0.5);
                vec3 vTangent = normalize(vec3(-sin(angle), 0.0, cos(angle)));
                vec3 dirCam = normalize(ro - hit);
                float cosPhi = dot(vTangent, dirCam);
                float dopplerFactor = pow((1.0 + beta * cosPhi) / (1.0 - beta * cosPhi), 3.0);
                dopplerFactor = clamp(dopplerFactor, 0.05, 8.0);
                discCol *= dopplerFactor;

  // ═══ Redshift gravitationnel radial ═══
                float gravRedshiftFactor = sqrt(max(0.01, 1.0 - EH / hr));
                discCol *= gravRedshiftFactor;
                vec3 hotColor = vec3(1.0, 0.95, 0.85);
                vec3 coolColor = vec3(0.85, 0.4, 0.1);
                discCol = mix(discCol, discCol * mix(coolColor, hotColor, gravRedshiftFactor), 0.3);

                float zf = exp(-hitDisk.y * hitDisk.y / (2.0 * DISK_SIGMA * DISK_SIGMA));
                discCol *= zf;

 // ═══ Anneau de photons + correction double arc ═══
                float numOrbits = totalAngle / (2.0 * PI);
                float photonRingBoost = 1.0;
                if (numOrbits >= 0.75 && numOrbits <= 1.25) {
                    photonRingBoost = 1.0 + 4.0 * (1.0 - abs(numOrbits - 1.0) / 0.25);
                }
                discCol *= clamp(photonRingBoost, 1.0, 5.0) * (numOrbits > 1.0 ? 0.2 : 1.0);

                diskInFront = true;
                diskOpacity += 0.3;
                diskAcc += discCol * 0.3;
            }
        }
        prevY = posDisk.y;
        prevPos = pos;
    }

    // Limiter
    diskAcc = clamp(diskAcc, 0.0, 2.0);
    diskOpacity = min(diskOpacity, 0.98);
   vec3 color;

   // Fond noir
    color = vec3(0.0);

    // Voie lactée : bande colorée passant par le centre (trou noir)
    vec3 dir = normalize(pos - ro);
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

    // Étoiles par-dessus
    vec3 bg = starfield(dir);
    color = mix(color, bg, 0.3);

    // Disque par-dessus
    color = mix(color, diskAcc, diskOpacity);

    // Ombre du trou noir
    if (captured && !diskInFront) {
        color = vec3(0.0);
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
        float R_shadow = b_crit / length(ro);
        float r_normalized = screenDist / R_shadow;
        float border = smoothstep(0.985, 0.995, r_normalized) * smoothstep(1.005, 0.995, r_normalized);
        color += vec3(1.0) * border;
    }

 

    // ── Grille CCD ──
    vec2 cellL = fract(px / CCD);
    float bX = step(cellL.x, 0.02) + step(1.0 - 0.02, cellL.x);
    float bY = step(cellL.y, 0.02) + step(1.0 - 0.02, cellL.y);
    color += vec3(max(bX, bY) * 0.03);

    // ── Tone mapping ──
    color = color / (1.0 + color);
    color = clamp(color, 0.0, 1.0);

    return vec4(color, 1.0);
}

void main() {
    vec2 uv = vPosition * 0.5 + 0.5;
    fragColor = rayMarch(uv);
}
