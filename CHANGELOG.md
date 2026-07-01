# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.1] — 2026-07-01

### Fixed — Physics / Documentation

- **README MAX_STEPS**: all occurrences now correctly say 900 (was inconsistently 300 in some places).
- **README 1PN formula**: corrected `-(3M/r³)[x - 4(x·v)v]` → `-(M/r³)[x - 4(x·v)v + 3(x·v)²/r² · x]` to match shader
  and `docs/physics.md`.
- **README camera distance**: 45.0 → 40.0 (matches `CAM_DEFAULT_DIST`).
- **README zoom range**: 35–100 → 33–100 (matches `CAM_DIST_MIN`).
- **README adaptive step**: 0.005 → 2.0 → 0.005 → 4.0 (matches shader range).

### Changed — Shader

- **MAX_STEPS**: confirmed at 900 (CHANGELOG v1.4.0 claimed "reduced to 300" but the shader was never changed; docs now correctly say 900).
- **SOFTEN_R2**: commented out as dead code (horizon capture at `r < EH` always fires first).
- **nebulaColor()**: vectorized `if/else` → `step`/`mix` (consistent with `blackbody()` pattern).

### Fixed — JS

- **fetchWithTimeout**: replaced non-portable `AbortSignal.timeout()` + `err.name === 'TimeoutError'` with clean
  `AbortController` pattern.
- **ESLint rules**: `no-unused-vars`, `prefer-const`, `eqeqeq` → `error` (was `warn`, letting violations pass CI).

### Added — Accessibility

- **Canvas**: added `tabindex="0"` for keyboard focus.
- **FPS counter**: added `aria-live="polite" aria-atomic="true"`.

### Added — PWA

- **Icons**: `icon-192.png` and `icon-512.png` generated (black hole with photon ring, matching favicon).
- **manifest.json**: added `"scope": "/"`.

### Improved — CSS

- **HUD**: added `backdrop-filter: blur(8px)` for readability over variable backgrounds.

### Improved — Infrastructure

- **CI**: added `actions/cache@v4` for `node_modules/`, added `docker build --no-cache` step.
- **Nginx**: added `server_tokens off;`, removed deprecated `X-XSS-Protection` header.
- **.gitignore**: removed unused sections (Terraform, coverage, TLS certs, temp files, pnpm logs) — 49→17 lines.

### Fixed — Metadata

- **version.json**: `"commit": "HEAD"` → real commit hash.
- **CHANGELOG**: resolved `2026-06-xx` placeholder → `2026-06-15`.
- **README**: `Latest commit: pending` → actual commit link.

---

## [1.5.0] — 2026-07-01

### Changed

- **Version bump**: 1.4.0 → 1.5.0.

---

## [1.4.0] — 2026-07-01

### Fixed — Physics

- **RK4 integrator**: corrected k2Pos, k3Pos, k4Pos to use raw velocity (`vel`) instead of velocity-corrected
  predictions. This is now a standard RK4 for the 1st-order system `dx/dλ=v, dv/dλ=a(x,v)`.
- **Removed velocity normalization** (`normalize(vel)`) after each RK4 step. For null geodesics, the 1PN acceleration
  structure preserves the direction without artificial energy injection/removal.
- **Impact parameter GR correction**: clarified formula — `b < b_crit * √(1-2M/r_cam)` is the correct capture condition
  at finite camera distance.
- **Softening**: added named `SOFTEN_R2` constant for singularity avoidance in `gravAccel`.

### Changed — Shader

- **MAX_STEPS**: reduced from 900 to 300 (adaptive steps reach far field quickly; early-out conditions terminate most
  rays at 50-200 steps).
- **FBM rotation matrix**: moved from per-call `mat2` construction to global `const mat2 FBM_ROT`. Eliminates ~50
  redundant matrix multiplications per pixel.
- **Magic numbers**: extracted all hardcoded values into named `const float` constants (`TEMP_PEAK`, `TEMP_SCALE`,
  `BETA_MAX`, `BEAM_MIN`, `BEAM_MAX`, `RING_WIDTH`, `RING_BOOST`, `STAR_DENSITY`, etc.).
- **RK4 variable naming**: `k1p/k1v` → `k1Pos/k1Vel` for clarity.
- **Hash constants**: extracted to named constants (`HASH_SEED_A` through `HASH_SEED_H`) with documentation.
- **Star thresholds**: extracted to named constants (`STAR_DENSITY`, `STAR_BRIGHTNESS`, `STAR_Faint_1`, `STAR_Faint_2`).

### Fixed — Documentation

- **README version**: synchronized to `v1.4.0` (was `v1.3.0`).
- **1PN acceleration formula**: corrected README to match actual code — `-(M/r³)[x - 4(v·x)v + 3(v·x)²/r² · x]` (removed
  erroneous factor 3, added quadratic term).
- **Impact parameter**: clarified GR correction in README to match code.
- **Removed `v1.4.0` version comments** from shader (no longer needed).

### Added — Infrastructure

- **MIT License** added.
- **package.json** with project metadata.
- **.eslintrc** with strict rules for vanilla JS.
- **.prettierrc** for code formatting.
- **nginx.conf** with security headers (CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy).
- **Docker healthcheck** added.
- **Docker resource limits** in docker-compose.yml.
- **PWA manifest.json** for installability.
- **CHANGELOG.md** (Keep a Changelog format).

### Improved — CI

- Workflow updated with ESLint and hadolint steps.

---

## [1.3.0] — 2026-06-15

### Added

- ACES filmic tone mapping (replaced Reinhard).
- Nebula color factorization.
- Disk turbulence with realistic/Kepler mode.
- Blackbody color vectorization.
- AbortController timeout on version fetch.
- Full reset on R key.
- Passive resize listener.
- Hoisted camInfoEl reference.
- Single parseFloat in slider handler.

### Fixed

- Removed `resetHudFade` from render loop.
- Removed diskAcc clamp.
- Removed redundant `diskToDiskFrame` calls.

[1.4.0]: https://github.com/TristanHottier/BH_Sim/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/TristanHottier/BH_Sim/compare/v1.2.0...v1.3.0
