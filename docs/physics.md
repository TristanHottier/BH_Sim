# Physics Reference — BH_Sim

> **Disclaimer**: This is a **visual simulation**, not a scientific tool. Several approximations are made for real-time
> performance. See the [README](../README.md#known-limitations) for the full list.

---

## Schwarzschild Metric

The black hole is modelled by the Schwarzschild metric, the exact solution to Einstein's field equations for a
spherical, non-rotating, uncharged body:

$$ds^2 = -\left(1 - \frac{r_s}{r}\right) c^2 dt^2 + \left(1 - \frac{r_s}{r}\right)^{-1} dr^2 + r^2 d\Omega^2$$

where $r_s = 2M$ is the Schwarzschild radius (the event horizon).

In this simulation: $c = 1$ (geometric units), $r_s = 1.0$, so $M = 0.5$.

### Key radii

| Quantity                  | Formula                        | Value   |
| ------------------------- | ------------------------------ | ------- |
| Event horizon             | $r_s = 2M$                     | 1.0     |
| Photon sphere             | $r_{ph} = 3M$                  | 1.5     |
| ISCO (Schwarzschild)      | $r_{\text{ISCO}} = 6M$         | 3.0     |
| Critical impact parameter | $b_{\text{crit}} = 3\sqrt{3}M$ | ≈ 2.598 |

---

## Null Geodesics

### Orbital equation

In the equatorial plane, the exact orbital equation for null geodesics is:

$$\frac{d^2u}{d\varphi^2} + u = 3Mu^2 \quad \text{where} \quad u = \frac{1}{r}$$

The $3Mu^2$ term is the relativistic correction — absent in Newtonian mechanics.

### Post-Newtonian 1st-order acceleration

The spatial trajectory is integrated using the 1PN acceleration form:

$$\frac{d^2\vec{x}}{d\lambda^2} = -\frac{M}{r^3} \left[\vec{x} - 4(\vec{x} \cdot \vec{v})\vec{v} + 3\frac{(\vec{x} \cdot \vec{v})^2}{r^2} \vec{x}\right]$$

Three terms:

1. **Radial**: $-M/r^3 \cdot \vec{x}$ — inward pull
2. **Velocity-dependent**: $+4M/r^3 \cdot (\vec{x} \cdot \vec{v}) \cdot \vec{v}$ — transverse deflection
3. **Quadratic**: $-3M/r^5 \cdot (\vec{x} \cdot \vec{v})^2 \cdot \vec{x}$ — nonlinear GR correction

This gives the correct weak-field deflection $\Delta\theta = 4M/b$ (Einstein angle).

> **Limitation**: The 1PN approximation is valid in weak field ($r \gg M$). Near the photon sphere ($r \approx 1.5$),
> the approximation deviates from the exact geodesic solution.

### RK4 Integration

The system is integrated as a 1st-order system:

$$\frac{d\vec{x}}{d\lambda} = \vec{v}, \quad \frac{d\vec{v}}{d\lambda} = \vec{a}(\vec{x}, \vec{v})$$

Standard 4th-order Runge-Kutta:

$$ \begin{aligned}
\vec{k}_1^{\text{pos}} &= \vec{v}, & \vec{k}_1^{\text{vel}} &= \vec{a}(\vec{x}, \vec{v}) \\
\vec{k}_2^{\text{pos}} &= \vec{v}, & \vec{k}_2^{\text{vel}} &= \vec{a}(\vec{x} + \tfrac{h}{2}\vec{k}_1^{\text{pos}}, \vec{v} + \tfrac{h}{2}\vec{k}_1^{\text{vel}}) \\
\vec{k}_3^{\text{pos}} &= \vec{v}, & \vec{k}_3^{\text{vel}} &= \vec{a}(\vec{x} + \tfrac{h}{2}\vec{k}_2^{\text{pos}}, \vec{v} + \tfrac{h}{2}\vec{k}_2^{\text{vel}}) \\
\vec{k}_4^{\text{pos}} &= \vec{v}, & \vec{k}_4^{\text{vel}} &= \vec{a}(\vec{x} + h\vec{k}_3^{\text{pos}}, \vec{v} + h\vec{k}_3^{\text{vel}})
\end{aligned}$$

$$\begin{aligned}
\vec{x}_{n+1} &= \vec{x}_n + \frac{h}{6}(\vec{k}_1^{\text{pos}} + 2\vec{k}_2^{\text{pos}} + 2\vec{k}_3^{\text{pos}} + \vec{k}_4^{\text{pos}}) \\
\vec{v}_{n+1} &= \vec{v}_n + \frac{h}{6}(\vec{k}_1^{\text{vel}} + 2\vec{k}_2^{\text{vel}} + 2\vec{k}_3^{\text{vel}} + \vec{k}_4^{\text{vel}})
\end{aligned}$$

No velocity normalization is applied — the 1PN acceleration structure preserves the null direction.

### Adaptive step size

| Distance $r$ | Step $h$ |
|-------------|---------|
| $r < 1.2$ | 0.005 |
| $1.2 < r < 1.5$ | 0.01 |
| $1.5 < r < 2.0$ | 0.02 |
| $2.0 < r < 3.0$ | 0.04 |
| $3.0 < r < 6.0$ | 0.08 |
| $6.0 < r < 12.0$ | 0.2 |
| $12.0 < r < 30.0$ | 0.8 |
| $30.0 < r < 60.0$ | 2.0 |
| $r > 60.0$ | 4.0 |

---

## Impact Parameter & Capture

The impact parameter $b = |\vec{r} \times \vec{v}|$ measures the angular momentum per unit energy.

At finite camera distance $r_{\text{cam}}$, the local impact parameter relates to the asymptotic one by:

$$b_{\text{loc}} = \frac{b_\infty}{\sqrt{1 - \frac{2M}{r_{\text{cam}}}}}$$

A ray is captured if $b_{\text{loc}} < b_{\text{crit}}$, which translates to:

$$b_\infty < b_{\text{crit}} \cdot \sqrt{1 - \frac{2M}{r_{\text{cam}}}}$$

---

## Accretion Disk

### Novikov-Thorne temperature profile

For a thin accretion disk around a Schwarzschild black hole:

$$T(r) \propto r^{-3/4} \left(1 - \sqrt{\frac{r_{\text{in}}}{r}}\right)^{1/4}$$

The inner edge ($r = r_{\text{in}} = r_{\text{ISCO}} = 6M$) has $T = 0$ (boundary condition). The temperature peaks at $r \approx 1.36 \cdot r_{\text{in}}$.

### Orbital velocity

Measured by a static observer at radius $r$:

$$\beta = \sqrt{\frac{M}{r - 2M}}$$

### Combined redshift factor

The combined gravitational + Doppler redshift factor for an emitter in circular orbit:

$$g = \frac{\sqrt{1 - \frac{2M}{r}}}{\gamma(1 - \beta \cos\varphi)}$$

where:
- $\gamma = (1 - \beta^2)^{-1/2}$ — Lorentz factor
- $\varphi$ — angle between gas velocity and photon direction (in the static frame)

### Doppler beaming

The monochromatic flux is boosted by $g^3$:

$$F_\nu^{\text{obs}} = g^3 \cdot F_\nu^{\text{emit}}$$

(Gravitational redshift contributes one $g$, Doppler shift contributes two: photon energy and arrival rate.)

---

## Background Deflection

For rays not interacting with the disk, an approximate weak-field deflection is applied:

$$\Delta\theta = \frac{4M}{b}$$

This shifts the background sky direction toward the black hole center.

---

## References

- Carroll, S.M. (2004). *Spacetime and Geometry*. Addison-Wesley. (Ch. 5-6)
- Weinberg, S. (1972). *Gravitation and Cosmology*. Wiley. (Eq. 8.3.11-12)
- Cunningham, C.T. (1975). *The effects of Doppler boosting, beam- ing, and gravitational reddening on the spectra of disks around black holes*. ApJ, 199, 112.
- Lasota, J.-P. (2001). *The astrophysics of black hole binaries*. GRG, 33, 451.
- Luminet, J.P. (1979). *Image of a spherical black hole with spherical accretion disk*. A&A, 75, 228.
- James et al. (2015). *Dressing a black hole for the big screen*. JOSS, 1(1), 5.
- Munnich, M. (2004). *Blackbody color approximation*. ShaderX 2.
$$
