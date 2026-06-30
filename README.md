# Schwarzschild Black Hole — Gravitational Lensing

Interactive real-time simulation of gravitational lensing around a Schwarzschild black hole, rendered entirely on GPU via WebGL2.

## Preview

![Black Hole Simulation](screenshot.png)

## Physics

### Schwarzschild Metric

The black hole is modeled by the Schwarzschild metric, the exact solution to Einstein's field equations for a spherical, non-rotating, uncharged body:

$$ds^2 = -\left(1 - \frac{r_s}{r}\right) c^2 dt^2 + \left(1 - \frac{r_s}{r}\right)^{-1} dr^2 + r^2 d\Omega^2$$

where $r_s = 2M$ is the Schwarzschild radius (the event horizon).

In this simulation, $c = 1$ (geometric units) and $r_s = 1.0$, so $M = 0.5$.

### Light Geodesics

Light follows null geodesics in spacetime. In the equatorial plane, the exact orbital equation is:

$$\frac{d^2u}{d\varphi^2} + u = 3Mu^2 \quad \text{where} \quad u = \frac{1}{r}$$

The $3Mu^2$ term is the relativistic correction — absent in Newtonian mechanics. This is what produces gravitational lensing.

### Simulation Parameters

| Parameter | Value | Meaning |
|-----------|--------|---------|
| $M$ | 0.5 | Black hole mass (geometric units, $r_s = 2M = 1.0$) |
| $\text{ALPHA}$ | 8.0 | Gravitational curvature factor |
| $b_\text{crit}$ | $\approx 6.93$ | Critical impact parameter (capture threshold) |
| $\text{DISK}_\text{IN}$ | 1.1 | Inner radius of the accretion disk |
| $\text{DISK}_\text{OUT}$ | 25.0 | Outer radius of the accretion disk |
| $\text{DISK}_\text{SIGMA}$ | 0.10 | Vertical disk thickness (Gaussian) |
| RK4 steps | 200 max | Maximum integration steps |
| Adaptive step | 0.01 → 1.5 | Step size (finer near the black hole) |

### Why ALPHA = 8.0?

In exact general relativity, the curvature factor would be $\text{ALPHA} = 3$ (corresponding to the $3Mu^2$ term in the orbital equation). The value $\text{ALPHA} = 8.0$ is **stronger than real physics** — it is chosen to make gravitational lensing effects **visually more prominent**.

This is an aesthetic trade-off: with $\text{ALPHA} = 3$, gravitational arcs are more subtle and less visible on screen. With $\text{ALPHA} = 8.0$, we get well-defined multiple images and photon rings.

> **Note**: The shadow radius is proportional to ALPHA. With ALPHA = 8, the capture radius is $b_\text{crit} = 3\sqrt{3} \cdot M \cdot \frac{\text{ALPHA}}{3} \approx 6.93$.

### Impact Parameter and Capture

The impact parameter $b = |\vec{r} \times \vec{v}|$ measures the minimum distance to the center if light were not bent. If $b < b_\text{crit}$, the ray is captured by the black hole — this is the shadow.

The shadow radius projected on screen is:

$$R_\text{shadow} = \frac{b_\text{crit}}{d_\text{cam} \cdot \tan(\text{FOV}/2)}$$

## Rendering

### Ray Marching (Backtrace)

Each pixel launches a ray from the camera toward the black hole. The ray is integrated step by step using **RK4** (4th-order Runge-Kutta):

$$\frac{d\vec{x}}{d\lambda} = \vec{v}, \quad \frac{d\vec{v}}{d\lambda} = -\frac{\text{ALPHA} \cdot M \cdot \vec{x}}{|\vec{x}|^3} - \frac{3M \cdot (\vec{v} \cdot \vec{x})}{|\vec{x}|^3} \cdot \vec{v}$$

The step $h$ is adaptive: smaller near the black hole (0.01) and larger far away (1.5), to optimize performance.

### Accretion Disk

The disk lies in the equatorial plane ($y = 0$), with:

- **Temperature**: $T \propto (1 - r/r_\text{out})^{3/4}$ — hotter inside (Stefan-Boltzmann law for an accretion disk)
- **Color**: blackbody — white-hot inside, orange/red outside
- **Doppler beaming**: $((1 + \beta\cos\varphi)/(1 - \beta\cos\varphi))^3$ — the approaching side is brighter (blueshifted)
- **Gravitational redshift**: $\sqrt{1 - r_s/r}$ — light loses energy escaping the gravitational well
- **Turbulence**: FBM (Fractional Brownian Motion) noise with rotation — realistic (Keplerian) or cinematic (rigid body) mode

### Background: Stars and Cosmic Filaments

- **Stars**: point noise on a 3D grid (hash per cell)
- **Cosmic filaments**: a blue band reminiscent of the Milky Way's galactic structure, generated with sinusoidal modulations. These represent large-scale cosmic web filaments — the faint, glowing structures that permeate intergalactic space and serve as the distant backdrop for the simulation.

### Performance

- Resolution reduced to 50% for performance
- Tone mapping: $c \mapsto c / (1 + c)$
- Optional CCD grid (pixelated effect)

## Controls

| Action | Control |
|--------|---------|
| θ/φ rotation | Click + drag |
| Zoom | Mouse wheel |
| Reset | R |
| Pause | Space |
| Disk inclination | Slider |
| Realistic rotation mode | Kepler checkbox |
| Shadow border | Checkbox |

## Docker

```bash
docker compose up --build
```

Access at `http://localhost:8080`.

## Stack

- HTML / CSS / Vanilla JavaScript
- WebGL2 (GLSL ES 300)
- Nginx (Docker)

## References

- Schwarzschild, K. (1916). Über das Gravitationsfeld eines Massenpunktes. *Sitzungsberichte der Königlich Preußischen Akademie der Wissenschaften*.
- Synge, J.L. (1966). *Relativity: The General Theory*. North-Holland.
- Luminet, J.P. (1979). Image of a spherical black hole with spherical accretion disk. *Astronomy & Astrophysics*, 75, 228–235.
- Bardeen, J.M. (1973). Timelike and null geodesics in the Kerr metric. In *Black Holes (Les Houches Sessions)*.
- Peebles, P.J.E. & Ratra, B. (2003). The cosmological constant and dark energy. *Reviews of Modern Physics*, 75(2), 559.
