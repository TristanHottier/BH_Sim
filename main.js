// ═══════════════════════════════════════════════════════════════════════════════
//  Schwarzschild Black Hole — 2D Gravitational Lensing
//
//  Backtrace ray marching in the Schwarzschild metric.
//  Full-resolution ray per pixel.
// ═══════════════════════════════════════════════════════════════════════════════
'use strict';

// ── Service Worker registration (PWA installability on Chrome/Edge) ──────────
if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('sw.js')
            .then(() => console.log('BH_Sim: Service Worker registered'))
            .catch((err) => console.warn('BH_Sim: SW registration failed:', err));
    });
}

// ── DOM references ──────────────────────────────────────────────────────────
const canvas = document.getElementById('glCanvas');
const gl = canvas.getContext('webgl2', { antialias: false, alpha: false });
const hud = document.getElementById('hud');
const fpsEl = document.getElementById('fps');
const camInfoEl = document.getElementById('camInfo');
const VERSION_TAG = document.getElementById('version');
const sliderPsiDisk = document.getElementById('sliderPsiDisk');
const valPsiDisk = document.getElementById('valPsiDisk');
const checkRealistic = document.getElementById('checkRealistic');
const inputResolution = document.getElementById('inputResolution');
const valResolution = document.getElementById('valResolution');
const loading = document.getElementById('loading');

// ── WebGL error handling ────────────────────────────────────────────────────
if (!gl) {
    const err = document.createElement('div');
    err.style.cssText = 'color:#f88;text-align:center;margin-top:40vh;font-family:sans-serif;padding:20px;';
    err.innerHTML =
        '<h2>WebGL 2 required</h2><p>Your browser does not support WebGL 2.<br>Please try a modern browser.</p>';
    document.body.appendChild(err);
    document.body.style.overflow = 'auto';
    throw new Error('WebGL2 required');
}

// ── Camera constants (single source of truth) ───────────────────────────────
const CAM_DEFAULT_THETA = (100.0 * Math.PI) / 180.0;
const CAM_DEFAULT_PHI = (80.0 * Math.PI) / 180.0;
const CAM_DEFAULT_DIST = 40.0;
const CAM_DIST_MIN = 33.0;
const CAM_DIST_MAX = 100.0;
const CAM_SENSITIVITY = 0.005;
const HUD_FADE_DELAY = 4000; // ms before HUD fades
const FPS_UPDATE_INTERVAL = 250; // ms between FPS DOM updates
const RENDER_DT_CAP = 0.1; // cap delta-time at 100ms

// ── Camera state ────────────────────────────────────────────────────────────
let camTheta = CAM_DEFAULT_THETA;
let camPhi = CAM_DEFAULT_PHI;
let camDist = CAM_DEFAULT_DIST;
let diskPsi = 0.0;
let realisticMode = false;
let resolutionPercent = 75;

let paused = false;
let simTime = 0.0;
let isDragging = false;
let lastMouseX = 0;
let lastMouseY = 0;

let frameCount = 0;
let lastFpsTime = performance.now();
let currentFps = 0;

// ── HUD fade — reactive only on user events ─────────────────────────────────
let hudTimeout;
const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

function resetHudFade() {
    hud.classList.add('active');
    hud.classList.remove('fade');
    clearTimeout(hudTimeout);
    if (!prefersReducedMotion.matches) {
        hudTimeout = setTimeout(() => hud.classList.add('fade'), HUD_FADE_DELAY);
    }
}
resetHudFade();

// ── Version system — with fallback timeout ──────────────────────────────────
let appVersion = 'v?.?.?'; // eslint-disable-line no-unused-vars
let appCommit = '?'; // eslint-disable-line no-unused-vars

function setVersion(v, commit) {
    appVersion = v;
    appCommit = commit;
    if (VERSION_TAG) {
        VERSION_TAG.textContent = v;
        VERSION_TAG.title = commit ? `Commit ${commit}` : '';
    }
    console.log(`BH_Sim ${v} (${commit})`);
}

// Portable fetch with timeout using AbortController
function fetchWithTimeout(url, timeoutMs) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    return fetch(url, { signal: controller.signal }).finally(() => clearTimeout(timer));
}

fetchWithTimeout('version.json', 5000)
    .then((r) => (r.ok ? r.json() : Promise.reject('not found')))
    .then((meta) => {
        const ver = 'v' + meta.version;
        const short = meta.commit ? meta.commit.slice(0, 7) : '?';
        setVersion(ver, short);
    })
    .catch(() => {
        if (VERSION_TAG && VERSION_TAG.textContent && VERSION_TAG.textContent.startsWith('v')) {
            setVersion(VERSION_TAG.textContent, '?');
        } else {
            console.warn('BH_Sim: Could not load version.json');
        }
    });

// ── Shader compilation ──────────────────────────────────────────────────────
function compileShader(src, type) {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
        console.error('Shader compile error:', gl.getShaderInfoLog(s));
        return null;
    }
    return s;
}

function createProgram(vsSrc, fsSrc) {
    const vs = compileShader(vsSrc, gl.VERTEX_SHADER);
    const fs = compileShader(fsSrc, gl.FRAGMENT_SHADER);
    if (!vs || !fs) return null;
    const p = gl.createProgram();
    gl.attachShader(p, vs);
    gl.attachShader(p, fs);
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
        console.error('Program link error:', gl.getProgramInfoLog(p));
        return null;
    }
    return p;
}

// ── Load shaders ────────────────────────────────────────────────────────────
async function loadShaderFile(path) {
    const resp = await fetch(path);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${path}`);
    return await resp.text();
}

let vertexSrc, fragmentSrc;

Promise.all([loadShaderFile('shaders/vertex.glsl'), loadShaderFile('shaders/fragment.glsl')])
    .then(([vs, fs]) => {
        vertexSrc = vs;
        fragmentSrc = fs;
        init();
        if (loading) loading.classList.add('hidden');
    })
    .catch((err) => {
        console.error('Failed to load shaders:', err);
        if (loading) loading.classList.add('hidden');
        const errDiv = document.createElement('div');
        errDiv.style.cssText = 'color:#f88;text-align:center;margin-top:40vh;font-family:sans-serif;padding:20px;';
        errDiv.textContent = `Shader load error.\nRun via local server.\n\n${err.message}`;
        document.body.appendChild(errDiv);
        document.body.style.overflow = 'auto';
    });

// ── Fullscreen quad ────────────────────────────────────────────────────────
const quadVAO = gl.createVertexArray();
const quadVBO = gl.createBuffer();
gl.bindBuffer(gl.ARRAY_BUFFER, quadVBO);
gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
gl.bindVertexArray(quadVAO);
gl.enableVertexAttribArray(0);
gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
gl.bindVertexArray(null);

// ── Resize — passive: true ──────────────────────────────────────────────────
let resizeScheduled = false;
function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const scale = (resolutionPercent / 100) * dpr;
    canvas.width = Math.floor(window.innerWidth * scale);
    canvas.height = Math.floor(window.innerHeight * scale);
    gl.viewport(0, 0, canvas.width, canvas.height);
    resizeScheduled = false;
}

function scheduleResize() {
    if (!resizeScheduled) {
        resizeScheduled = true;
        requestAnimationFrame(resize);
    }
}
window.addEventListener('resize', scheduleResize, { passive: true });

// ── Camera info formatting ──────────────────────────────────────────────────
function formatCamInfo() {
    const thetaDeg = ((camTheta * 180) / Math.PI).toFixed(1);
    const phiDeg = ((camPhi * 180) / Math.PI).toFixed(1);
    const psiDeg = ((diskPsi * 180) / Math.PI).toFixed(1);
    const pause = paused ? ' ⏸' : '';
    return `θ: ${thetaDeg}°  φ: ${phiDeg}°  ψd: ${psiDeg}°  d: ${camDist.toFixed(1)}${pause}`;
}

// ── Render loop ─────────────────────────────────────────────────────────────
let prog, loc;
let lastFrameTime = performance.now();

function render(now) {
    // Delta-time animation (frame-rate independent)
    const dt = Math.min((now - lastFrameTime) / 1000, RENDER_DT_CAP);
    lastFrameTime = now;

    if (!paused) {
        simTime += dt;
    }

    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clearColor(0, 0, 0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    gl.useProgram(prog);
    gl.bindVertexArray(quadVAO);

    const camPos = [
        camDist * Math.sin(camPhi) * Math.sin(camTheta),
        camDist * Math.cos(camPhi),
        camDist * Math.sin(camPhi) * Math.cos(camTheta)
    ];

    gl.uniform3fv(loc.uCamPos, camPos);
    gl.uniform1f(loc.uDiskPsi, diskPsi);
    gl.uniform1f(loc.uDiskCos, Math.cos(diskPsi));
    gl.uniform1f(loc.uDiskSin, Math.sin(diskPsi));
    gl.uniform1f(loc.uRealistic, realisticMode ? 1.0 : 0.0);
    gl.uniform1f(loc.uSeed, realisticMode ? 1.0 : 0.0);
    gl.uniform1f(loc.uAspect, canvas.width / canvas.height);
    gl.uniform1f(loc.uFOV, Math.PI / 3);
    gl.uniform1f(loc.uTime, simTime);

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

    // HUD — FPS and camera info
    frameCount++;
    if (now - lastFpsTime >= FPS_UPDATE_INTERVAL) {
        currentFps = Math.round(frameCount / ((now - lastFpsTime) / 1000));
        frameCount = 0;
        lastFpsTime = now;
        if (fpsEl) fpsEl.textContent = `FPS: ${currentFps}`;
        if (camInfoEl) camInfoEl.textContent = formatCamInfo();
    }

    requestAnimationFrame(render);
}

function init() {
    prog = createProgram(vertexSrc, fragmentSrc);
    if (!prog) {
        const errDiv = document.createElement('div');
        errDiv.style.cssText = 'color:#f88;text-align:center;margin-top:40vh;font-family:sans-serif;padding:20px;';
        errDiv.textContent = 'Shader compilation failed. Check browser console.';
        document.body.appendChild(errDiv);
        document.body.style.overflow = 'auto';
        return;
    }

    // Resolve uniform locations — fail gracefully if any are missing
    const l = {};
    const n = gl.getProgramParameter(prog, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) {
        const info = gl.getActiveUniform(prog, i);
        const loc = gl.getUniformLocation(prog, info.name);
        if (!loc) {
            console.warn(`Uniform "${info.name}" not found in program`);
        }
        l[info.name] = loc;
    }
    // Verify all expected uniforms are present
    const expected = ['uCamPos', 'uAspect', 'uFOV', 'uTime', 'uDiskPsi', 'uDiskCos', 'uDiskSin', 'uRealistic', 'uSeed'];
    for (const name of expected) {
        if (!l[name]) {
            console.error(`Missing uniform: ${name}`);
        }
    }
    loc = l;

    resize();
    requestAnimationFrame(render);
}

// ── Mouse controls ──────────────────────────────────────────────────────────
canvas.addEventListener('mousedown', (e) => {
    if (e.button === 0) {
        isDragging = true;
        lastMouseX = e.clientX;
        lastMouseY = e.clientY;
    }
});
window.addEventListener('mousemove', (e) => {
    if (!isDragging) return;
    camTheta -= (e.clientX - lastMouseX) * CAM_SENSITIVITY;
    camPhi = Math.max(
        (10.0 * Math.PI) / 180.0,
        Math.min((170.0 * Math.PI) / 180.0, camPhi + (e.clientY - lastMouseY) * CAM_SENSITIVITY)
    );
    lastMouseX = e.clientX;
    lastMouseY = e.clientY;
});
window.addEventListener('mouseup', () => {
    isDragging = false;
});
canvas.addEventListener(
    'wheel',
    (e) => {
        e.preventDefault();
        camDist *= 1.0 + e.deltaY * 0.001;
        camDist = Math.max(CAM_DIST_MIN, Math.min(CAM_DIST_MAX, camDist));
    },
    { passive: false }
);

// ── Touch controls ──────────────────────────────────────────────────────────
let lastPinchDist = 0;
canvas.addEventListener(
    'touchstart',
    (e) => {
        if (e.touches.length === 1) {
            isDragging = true;
            lastMouseX = e.touches[0].clientX;
            lastMouseY = e.touches[0].clientY;
        } else if (e.touches.length === 2) {
            isDragging = false;
            const dx = e.touches[0].clientX - e.touches[1].clientX;
            const dy = e.touches[0].clientY - e.touches[1].clientY;
            lastPinchDist = Math.sqrt(dx * dx + dy * dy);
        }
        resetHudFade();
    },
    { passive: false }
);
canvas.addEventListener(
    'touchmove',
    (e) => {
        e.preventDefault();
        if (e.touches.length === 2) {
            const dx = e.touches[0].clientX - e.touches[1].clientX;
            const dy = e.touches[0].clientY - e.touches[1].clientY;
            const pinchDist = Math.sqrt(dx * dx + dy * dy);
            const delta = pinchDist - lastPinchDist;
            camDist *= 1.0 - delta * 0.003;
            camDist = Math.max(CAM_DIST_MIN, Math.min(CAM_DIST_MAX, camDist));
            lastPinchDist = pinchDist;
        } else if (isDragging && e.touches.length === 1) {
            const dx = e.touches[0].clientX - lastMouseX;
            const dy = e.touches[0].clientY - lastMouseY;
            camTheta -= dx * CAM_SENSITIVITY;
            camPhi = Math.max(
                (10.0 * Math.PI) / 180.0,
                Math.min((170.0 * Math.PI) / 180.0, camPhi + dy * CAM_SENSITIVITY)
            );
            lastMouseX = e.touches[0].clientX;
            lastMouseY = e.touches[0].clientY;
        }
        resetHudFade();
    },
    { passive: false }
);
canvas.addEventListener('touchend', () => {
    isDragging = false;
});

// ── Keyboard ────────────────────────────────────────────────────────────────
window.addEventListener('keydown', (e) => {
    resetHudFade();

    if (e.key === 'r' || e.key === 'R') {
        // Full reset
        camTheta = CAM_DEFAULT_THETA;
        camPhi = CAM_DEFAULT_PHI;
        camDist = CAM_DEFAULT_DIST;
        diskPsi = 0.0;
        realisticMode = false;
        resolutionPercent = 75;
        sliderPsiDisk.value = 0;
        valPsiDisk.textContent = '0.0°';
        checkRealistic.checked = false;
        inputResolution.value = 75;
        valResolution.textContent = '75%';
        if (camInfoEl) camInfoEl.textContent = formatCamInfo();
        scheduleResize();
    }
    if (e.key === ' ') {
        e.preventDefault();
        paused = !paused;
    }
});

// ── Slider ψ disque ─────────────────────────────────────────────────────────
sliderPsiDisk.addEventListener('input', () => {
    const deg = parseFloat(sliderPsiDisk.value);
    diskPsi = (deg * Math.PI) / 180.0;
    valPsiDisk.textContent = deg.toFixed(1) + '°';
    if (camInfoEl) camInfoEl.textContent = formatCamInfo();
});

checkRealistic.addEventListener('change', () => {
    realisticMode = checkRealistic.checked;
    if (loc) {
        gl.uniform1f(loc.uRealistic, realisticMode ? 1.0 : 0.0);
        gl.uniform1f(loc.uSeed, realisticMode ? 1.0 : 0.0);
    }
});

inputResolution.addEventListener('input', () => {
    let val = parseInt(inputResolution.value, 10);
    if (isNaN(val)) val = 75;
    val = Math.max(10, Math.min(100, val));
    resolutionPercent = val;
    valResolution.textContent = val + '%';
    scheduleResize();
});
