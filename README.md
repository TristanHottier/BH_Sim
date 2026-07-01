# Schwarzschild Black Hole — Gravitational Lensing

Interactive real-time simulation of gravitational lensing around a Schwarzschild black hole, rendered entirely on GPU
via WebGL2.

This project visualises how gravity bends light near a non-rotating black hole, producing the iconic photon ring,
gravitational arcs, and the dark "shadow" at the centre. The accretion disk displays Doppler beaming, gravitational
redshift, and procedural turbulence.

> **Inspired by**: the first image of M87* by the Event Horizon Telescope (2019) and the black hole sequence in
> _Interstellar_ (2014), based on physicist Kip Thorne's equations.

## Table of Contents

- [Version](#version)
- [Preview](#preview)
- [Physics](#physics)
- [Rendering](#rendering)
- [Controls](#controls)
- [Running the Simulation](#running-the-simulation)
    - [GitHub Pages (recommended)](#github-pages-recommended)
    - [Docker (local)](#docker-local)
    - [Local (any static server)](#local-any-static-server)
- [Known Limitations](#known-limitations)
- [Stack](#stack)
- [License](#license)

## Version

| Field               | Value      |
| ------------------- | ---------- |
| **Current version** | `v1.6.1`   |
| **Latest commit**   | pending    |
| **Release date**    | 2026-07-01 |

Version history is tracked via [Git tags](https://github.com/TristanHottier/BH_Sim/tags) and reflected in the HUD badge
during runtime. See [`version.json`](version.json) for machine-readable metadata.

## Preview

![Black Hole Simulation](screenshot.png)

## Physics

For the complete physics reference (metric, geodesics, accretion disk, redshift), see
[docs/physics.md](docs/physics.md).

### Quick summary

The simulation uses the **Schwarzschild metric** ($M = 0.5$, $r_s = 1.0$) with **null geodesics** integrated via **RK4**
(4th-order Runge-Kutta) with **adaptive step sizing**. The accretion disk follows the **Novikov-Thorne** thin-disk model
with **Doppler beaming** ($g^3$) and **gravitational redshift**.

Key parameters:

| Parameter                | Value | Meaning                            |
| ------------------------ | ----- | ---------------------------------- |
| $M$                      | 0.5   | Black hole mass ($r_s = 2M = 1.0$) |
| $\text{DISK}_\text{IN}$  | 3.0   | ISCO = 6M                          |
| $\text{DISK}_\text{OUT}$ | 15.0  | Outer disk radius                  |
| MAX_STEPS                | 900   | Max RK4 steps (adaptive)           |
| FOV                      | 60°   | Field of view                      |

The black hole is modelled by the Schwarzschild metric, the exact solution to Einstein's field equations for a
spherical, non-rotating, uncharged body:

$$ds^2 = -\left(1 - \frac{r_s}{r}\right) c^2 dt^2 + \left(1 - \frac{r_s}{r}\right)^{-1} dr^2 + r^2 d\Omega^2$$

where $r_s = 2M$ is the Schwarzschild radius (the event horizon).

In this simulation, $c = 1$ (geometric units) and $r_s = 1.0$, so $M = 0.5$.

### Light Geodesics

Light follows null geodesics in spacetime. In the equatorial plane, the exact orbital equation is:

$$\frac{d^2u}{d\varphi^2} + u = 3Mu^2 \quad \text{where} \quad u = \frac{1}{r}$$

The $3Mu^2$ term is the relativistic correction — absent in Newtonian mechanics. This is what produces gravitational
lensing.

The spatial trajectory is integrated using the post-Newtonian acceleration form:

$$\frac{d^2\vec{x}}{d\lambda^2} = -\frac{M}{r^3} \left[\vec{x} - 4(\vec{x} \cdot \vec{v})\vec{v} + 3\frac{(\vec{x} \cdot \vec{v})^2}{r^2} \vec{x}\right]$$

This gives:

- Weak-field deflection: $\Delta\theta = 4M/b$ (Einstein angle)
- Photon sphere at $r = 3M = 1.5$
- Critical impact parameter: $b_\text{crit} = 3\sqrt{3}M \approx 2.598$

### Simulation Parameters

| Parameter                  | Value           | Meaning                                                      |
| -------------------------- | --------------- | ------------------------------------------------------------ |
| $M$                        | 0.5             | Black hole mass (geometric units, $r_s = 2M = 1.0$)          |
| $b_\text{crit}$            | $\approx 2.598$ | Critical impact parameter (capture threshold)                |
| $\text{DISK}_\text{IN}$    | 3.0             | Inner radius of the accretion disk (Schwarzschild ISCO = 6M) |
| $\text{DISK}_\text{OUT}$   | 15.0            | Outer radius of the accretion disk                           |
| $\text{DISK}_\text{SIGMA}$ | 0.02            | Vertical disk thickness (Gaussian)                           |
| RK4 steps                  | 900 max         | Maximum integration steps (adaptive)                         |
| Adaptive step              | 0.005 → 4.0     | Step size (finer near the black hole)                        |

### Impact Parameter and Capture

The impact parameter $b = |\vec{r} \times \vec{v}|$ measures the minimum distance to the center if light were not bent.
If $b < b_\text{crit}$, the ray is captured by the black hole — this is the shadow.

The GR-corrected impact parameter at finite camera distance is:

$$b_\text{GR} = \frac{b}{\sqrt{1 - \frac{2M}{r_\text{cam}}}}$$

A ray is captured if $b_\text{GR} < b_\text{crit}$.

### Design Choices: Physics vs. Visuals

This simulation uses standard Schwarzschild physics. Some parameters are adjusted for visual clarity:

- **$\text{DISK}_\text{IN} = 3.0$**: the standard Schwarzschild ISCO ($6M$ where $M = 0.5$). The disk starts at the
  innermost stable circular orbit.
- **$\text{DISK}_\text{OUT} = 15.0$**: chosen to keep the disk compact and visually focused, well within the ray
  marching limit ($MAX_R = 500$).
- **$\text{DISK}_\text{SIGMA} = 0.02$**: thin disk approximation, similar to the Interstellar rendering. Real accretion
  disks have $H/r \sim 0.01$–$0.1$, so this is within a realistic range.
- **$M = 0.5$** ($r_s = 1.0$): arbitrary mass scale. The simulation is dimensionless — only ratios matter.

## Rendering

The entire rendering pipeline is a **single-pass ray marcher** in the fragment shader:

1. Each pixel launches a ray from the camera.
2. The ray is integrated using **RK4** with **adaptive step sizing** (900 max steps).
3. Ray-disk intersections are accumulated via **Beer-Lambert** law.
4. **ACES filmic tone mapping** compresses the dynamic range.

Key rendering features:

- **Doppler beaming** ($g^3$) — approaching side brighter, receding side dimmer
- **Gravitational redshift** — inner disk reddened
- **Photon ring boost** — visual enhancement for rays orbiting ~1×
- **Procedural turbulence** — FBM noise with Kepler or rigid-body rotation
- **Star field** — hash-based 3D grid with 3 brightness layers
- **Nebula** — violet-pink background overlay

> For detailed rendering equations, see [docs/physics.md](docs/physics.md).

## Controls

| Action                  | Control                                 |
| ----------------------- | --------------------------------------- |
| θ/φ rotation            | Click + drag / single-finger drag       |
| Zoom                    | Mouse wheel / pinch-to-zoom (2 fingers) |
| Reset                   | R                                       |
| Pause                   | Space                                   |
| Disk inclination        | Slider (tilt around X axis)             |
| Realistic rotation mode | Kepler checkbox                         |

### Camera Parameters (default)

| Parameter | Value | Description                              |
| --------- | ----- | ---------------------------------------- |
| $\theta$  | 100°  | Azimuthal angle (around Z axis)          |
| $\phi$    | 80°   | Polar angle (from Z axis) — near edge-on |
| Distance  | 40.0  | Camera distance from black hole          |
| FOV       | 60°   | Field of view                            |

Zoom range: 33–100 units. Polar angle range: 0.001°–179.999° (0° to 180°). Reset (R key): restores all defaults.

## Running the Simulation

### GitHub Pages (recommended)

The simulation is hosted directly on GitHub Pages — no setup required:

**https://tristanhottier.github.io/BH_Sim/**

### Docker (local)

```bash
docker compose up --build
```

Access at `http://localhost:8080`.

### Local (any static server)

Serve the project root with any HTTP server:

```bash
# Python
python -m http.server 8080

# Node.js
npx serve .

# PHP
php -S localhost:8080
```

Access at `http://localhost:8080`.

> **Note**: Opening `index.html` directly via `file://` will not work, as the GLSL shaders are loaded via `fetch()`.

## Known Limitations

This is a **visual simulation**, not a scientific tool. See [docs/physics.md](docs/physics.md) for the full physics
reference.

1. **Schwarzschild metric only**: the black hole is non-rotating. Real astrophysical black holes spin (Kerr metric),
   which produces frame-dragging and an asymmetric shadow.
2. **1PN acceleration**: valid in weak field ($r \gg M$). Near the photon sphere ($r \approx 1.5$), the approximation
   deviates from exact geodesics.
3. **No disk self-gravity**: the disk's mass is negligible compared to the black hole.
4. **No volumetric rendering**: the disk is a thin emissive surface. Self-occultation is approximated via Beer-Lambert
   accumulation.
5. **No polarization**: real black hole images carry polarisation information from synchrotron emission.
6. **Single-pass rendering**: no multi-pass bloom or anti-aliasing.
7. **900 RK4 steps max** (adaptive): most rays terminate at 50–200 steps via early-out conditions. An orbit safeguard
   (>5 orbits) prevents infinite loops.

## Stack

- **HTML5** — semantic structure with viewport meta for mobile support
- **CSS3** — fullscreen canvas, HUD with auto-fade, responsive media queries (mobile-first)
- **Vanilla JavaScript** — WebGL2 context management, camera controls, render loop with delta-time
- **WebGL2 (GLSL ES 300)** — vertex shader (fullscreen quad), fragment shader (all physics + rendering)
- **Nginx** — Docker container for static file serving
- **ESLint + Prettier** — code quality and formatting

## License

[MIT License](LICENSE) — Copyright (c) 2026 Tristan Hottier

## References

See [docs/physics.md](docs/physics.md) for complete physics references.

Key sources:

- Luminet, J.P. (1979). _Image of a spherical black hole with spherical accretion disk_. A&A, 75, 228–235.
- Event Horizon Telescope Collaboration (2019). _First M87 EHT Results. I. The Shadow_. ApJL, 875(1), L1.
- James et al. (2015). _Dressing a black hole for the big screen_. JOSS, 1(1), 5.
- Thorne, K. (1995). _Black Holes and Time Warps_. W.W. Norton & Company.
