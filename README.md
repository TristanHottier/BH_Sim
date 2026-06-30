# Trou Noir de Schwarzschild — Lentille Gravitationnelle

Simulation interactive en temps réel de la lentille gravitationnelle autour d'un trou noir de Schwarzschild, rendu entièrement sur GPU via WebGL2.

## Aperçu

![Simulation Trou Noir](screenshot.png)

## Physique

### Métrique de Schwarzschild

Le trou noir est modélisé par la métrique de Schwarzschild, la solution exacte des équations d'Einstein pour un corps sphérique, non-rotatif et sans charge :

$$ds^2 = -\left(1 - \frac{r_s}{r}\right) c^2 dt^2 + \left(1 - \frac{r_s}{r}\right)^{-1} dr^2 + r^2 d\Omega^2$$

où $r_s = 2M$ est le rayon de Schwarzschild (l'horizon des événements).

Dans cette simulation, $c = 1$ (unités géométriques) et $r_s = 1.0$, donc $M = 0.5$.

### Géodésiques de la lumière

La lumière suit les géodésiques nulles de l'espace-temps. Dans le plan équatorial, l'équation orbitale exacte est :

$$\frac{d^2u}{d\varphi^2} + u = 3Mu^2 \quad \text{où} \quad u = \frac{1}{r}$$

Le terme $3Mu^2$ est la correction relativiste — absent en mécanique newtonienne. C'est ce terme qui produit la lentille gravitationnelle.

### Paramètres de la simulation

| Paramètre | Valeur | Signification |
|-----------|--------|---------------|
| $M$ | 0.5 | Masse du trou noir (unités géométriques, $r_s = 2M = 1.0$) |
| $\text{ALPHA}$ | 8.0 | Facteur de courbure gravitationnelle |
| $b_\text{crit}$ | $\approx 6.93$ | Impact parameter critique (seuil de capture) |
| $\text{DISK}_\text{IN}$ | 1.1 | Rayon intérieur du disque d'accrétion |
| $\text{DISK}_\text{OUT}$ | 25.0 | Rayon extérieur du disque d'accrétion |
| $\text{DISK}_\text{SIGMA}$ | 0.10 | Épaisseur verticale du disque (Gaussienne) |
| RK4 pas | 200 max | Nombre maximum de pas d'intégration |
| Pas adaptatif | 0.01 → 1.5 | Taille de pas (raffini près du trou noir) |

### Pourquoi ALPHA = 8.0 ?

En relativité générale exacte, le facteur de courbure serait $\text{ALPHA} = 3$ (correspondant au terme $3Mu^2$ de l'équation orbitale). La valeur $\text{ALPHA} = 8.0$ est **plus forte que la physique réelle** — elle est choisie pour rendre les effets de lentille gravitationnelle **visuellement plus marqués**.

C'est un compromis esthétique : avec $\text{ALPHA} = 3$, les arcs gravitationnels sont plus subtils et moins visibles à l'écran. Avec $\text{ALPHA} = 8.0$, on obtient des images multiples et des anneaux de photons bien définis.

> **Note** : Le rayon de l'ombre est proportionnel à ALPHA. Avec ALPHA = 8, le rayon de capture est $b_\text{crit} = 3\sqrt{3} \cdot M \cdot \frac{\text{ALPHA}}{3} \approx 6.93$.

### Impact parameter et capture

L'impact parameter $b = |\vec{r} \times \vec{v}|$ mesure la distance minimale au centre si la lumière n'était pas courbée. Si $b < b_\text{crit}$, le rayon est capturé par le trou noir — c'est l'ombre.

Le rayon de l'ombre projeté sur l'écran est :

$$R_\text{shadow} = \frac{b_\text{crit}}{d_\text{cam} \cdot \tan(\text{FOV}/2)}$$

## Rendu

### Ray marching (backtrace)

Chaque pixel lance un rayon depuis la caméra vers le trou noir. Le rayon est intégré pas à pas avec un **RK4** (Runge-Kutta d'ordre 4) :

$$\frac{d\vec{x}}{d\lambda} = \vec{v}, \quad \frac{d\vec{v}}{d\lambda} = -\frac{\text{ALPHA} \cdot M \cdot \vec{x}}{|\vec{x}|^3} - \frac{3M \cdot (\vec{v} \cdot \vec{x})}{|\vec{x}|^3} \cdot \vec{v}$$

Le pas $h$ est adaptatif : plus petit près du trou noir (0.01) et plus grand loin (1.5), pour optimiser les performances.

### Disque d'accrétion

Le disque est dans le plan équatorial ($y = 0$), avec :

- **Température** : $T \propto (1 - r/r_\text{out})^{3/4}$ — plus chaud à l'intérieur (loi de Stefan-Boltzmann pour un disque d'accrétion)
- **Couleur** : corps noir (blackbody) — blanc chaud à l'intérieur, orange/rouge à l'extérieur
- **Doppler beaming** : $((1 + \beta\cos\varphi)/(1 - \beta\cos\varphi))^3$ — le côté qui approche est plus brillant (décalé vers le bleu)
- **Redshift gravitationnel** : $\sqrt{1 - r_s/r}$ — la lumière perd de l'énergie en s'échappant du puits gravitationnel
- **Turbulence** : bruit FBM (Fractional Brownian Motion) avec rotation — mode réaliste (Kepler) ou cinématique (bloc rigide)

### Nébuleuse et étoiles

- **Étoiles** : bruit ponctuel sur une grille 3D (hash par cellule)
- **Nébuleuse** : bande colorée de type voie lactée, avec sinusoides pour les structures

### Performance

- Résolution réduite à 50% pour les performances
- Tone mapping : $c \mapsto c / (1 + c)$
- Grille CCD optionnelle (effet pixelisé)

## Contrôle

| Action | Contrôle |
|--------|----------|
| Rotation θ/φ | Clic + glisser |
| Zoom | Molette |
| Réinitialiser | R |
| Pause | Espace |
| Inclinaison du disque | Slider |
| Mode rotation réaliste | Checkbox Kepler |
| Bordure ombre | Checkbox |

## Docker

```bash
docker compose up --build
```

Accède à `http://localhost:8080`.

## Stack

- HTML / CSS / JavaScript vanilla
- WebGL2 (GLSL ES 300)
- Nginx (Docker)

## Références

- Schwarzschild, K. (1916). Über das Gravitationsfeld eines Massenpunktes.
- Synge, J.L. (1966). *Relativity: The General Theory*.
- Luminet, J.P. (1979). Image of a spherical black hole with spherical accretion disk. *Astronomy & Astrophysics*, 75, 228.
- Bardeen, J.M. (1973). Timelike and null geodesics in the Kerr metric.
