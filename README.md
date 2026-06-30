# Trou Noir de Schwarzschild — Lentille Gravitationnelle

Simulation interactive en temps réel de la lentille gravitationnelle autour d'un trou noir de Schwarzschild, rendu entièrement sur GPU via WebGL2.

## Fonctionnalités

- **Ray marching RK4** dans la métrique de Schwarzschild (200 pas, pas adaptatif)
- **Lentille gravitationnelle** physique avec déviation transversale de la lumière
- **Disque d'accrétion** avec :
  - Gradient de température (blanc chaud intérieur → orange extérieur)
  - Doppler beaming relativiste dynamique
  - Redshift gravitationnel
  - Anneau de photons (boost sur les orbites multiples)
  - Turbulence animée (mode réaliste Kepler ou cinématique)
- **Nébuleuse** de type voie lactée en arrière-plan
- **Champ d'étoiles** procédural
- **Ombre du trou noir** délimitée par un cercle blanc (optionnel)
- **Effet CCD** pixelisé sur le rendu

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

## Physique

Le ray marching résout les géodésiques de la lumière dans la métrique de Schwarzschild :

```
dx/dλ = v
dv/dλ = -ALPHA·M·x/|x|³ - 3M·(v·x)/|x|³ · v
```

Le terme `-3M·(v·x)/|x|³ · v` représente la déviation transversale de la lumière, essentielle pour reproduire correctement la lentille gravitationnelle.

L'impact parameter critique est `b_crit = 3√3·M·(ALPHA/3)`, au-delà duquel les rayons sont capturés par le trou noir.

## Rendu

- **WebGL2** (GLSL ES 300)
- Résolution réduite (50%) pour les performances
- Tone mapping `color / (1 + color)`
- Grille CCD optionnelle

## Docker

```bash
docker compose up --build
```

Accède à `http://localhost:8080`.

## Stack

- HTML / CSS / JavaScript vanilla
- WebGL2 (GLSL ES 300)
- Nginx (Docker)

## Capture

![Simulation Trou Noir](https://github.com/TristanHottier/BH_Sim/raw/main/screenshot.png)
