// ═══════════════════════════════════════════════════════════════════════════════
//  Schwarzschild Black Hole — 2D Gravitational Lensing
//
//  Backtrace ray marching in the Schwarzschild metric.
//  CCD: each 5×5 pixel block shares the same ray.
// ═══════════════════════════════════════════════════════════════════════════════

const canvas = document.getElementById('glCanvas');
const gl = canvas.getContext('webgl2', { antialias: false, alpha: false });

if (!gl) {
    document.body.innerHTML = '<h1 style="color:#f88;text-align:center;margin-top:40vh">WebGL 2 required</h1>';
    throw new Error('WebGL2 required');
}

// ── Camera ────────────────────────────────────────────────────────────────────
let camTheta = 100.0 * 3.14159265359 / 180.0;
let camPhi   = 80.0 * 3.14159265359 / 180.0;
let camDist  = 45.0;
let diskPsi  = 0.0;
let realisticMode = false;
let showShadow = false;

let paused   = false;
let simTime  = 0.0;
let isDragging = false;
let lastMouse = { x: 0, y: 0 };

let frameCount = 0;
let lastFpsTime = performance.now();
let currentFps = 0;

// HUD fade
let hudTimeout;
const hud = document.getElementById('hud');
function resetHudFade() {
    hud.classList.add('active');
    hud.classList.remove('fade');
    clearTimeout(hudTimeout);
    hudTimeout = setTimeout(() => hud.classList.add('fade'), 4000);
}
resetHudFade();

// ── Shader compilation ────────────────────────────────────────────────────────
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

// ── Load shaders ──────────────────────────────────────────────────────────────
async function loadShaderFile(path) {
    const resp = await fetch(path);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${path}`);
    return await resp.text();
}

let vertexSrc, fragmentSrc;

Promise.all([
    loadShaderFile('shaders/vertex.glsl'),
    loadShaderFile('shaders/fragment.glsl')
]).then(([vs, fs]) => {
    vertexSrc = vs;
    fragmentSrc = fs;
    init();
}).catch(err => {
    console.error('Failed to load shaders:', err);
    document.body.innerHTML = `<h1 style="color:#f88;text-align:center;margin-top:40vh;font-family:sans-serif">
        Shader load error.<br>Run via local server.<br><small>${err.message}</small></h1>`;
});

// ── Fullscreen quad ──────────────────────────────────────────────────────────
const quadVAO = gl.createVertexArray();
const quadVBO = gl.createBuffer();
gl.bindBuffer(gl.ARRAY_BUFFER, quadVBO);
gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, 1,1]), gl.STATIC_DRAW);
gl.bindVertexArray(quadVAO);
gl.enableVertexAttribArray(0);
gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
gl.bindVertexArray(null);

// ── Resize ────────────────────────────────────────────────────────────────────
function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 1);
    canvas.width  = Math.floor(window.innerWidth * dpr * 0.5);
    canvas.height = Math.floor(window.innerHeight * dpr * 0.5);
    gl.viewport(0, 0, canvas.width, canvas.height);
}
window.addEventListener('resize', resize);

// ── Render loop ──────────────────────────────────────────────────────────────
let prog, loc;

function render() {
    resetHudFade();

    if (!paused) {
        simTime += 0.016;
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
    gl.uniform1f(loc.uRealistic, realisticMode ? 1.0 : 0.0);
    gl.uniform1f(loc.uTimeOffset, 0.0);
    gl.uniform1f(loc.uSeed, realisticMode ? 1.0 : 0.0);
    gl.uniform1f(loc.uShowShadow, showShadow ? 1.0 : 0.0);
    gl.uniform1f(loc.uAspect, canvas.width / canvas.height);
    gl.uniform1f(loc.uFOV, Math.PI / 3);
    gl.uniform1f(loc.uTime, simTime);
    gl.uniform2f(loc.uScreenPixel, gl.drawingBufferWidth, gl.drawingBufferHeight);

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

    // HUD
    frameCount++;
    const now = performance.now();
    if (now - lastFpsTime >= 500) {
        currentFps = Math.round(frameCount / ((now - lastFpsTime) / 1000));
        frameCount = 0;
        lastFpsTime = now;
        document.getElementById('fps').textContent = `FPS: ${currentFps}`;
        document.getElementById('camInfo').textContent =
            `θ: ${(camTheta * 180 / Math.PI).toFixed(1)}°  φ: ${(camPhi * 180 / Math.PI).toFixed(1)}°  ψd: ${(diskPsi * 180 / Math.PI).toFixed(1)}°  d: ${camDist.toFixed(1)}`;
    }

    requestAnimationFrame(render);
}

function init() {
    prog = createProgram(vertexSrc, fragmentSrc);
    if (!prog) {
        document.body.innerHTML = '<h1 style="color:#f88;text-align:center;margin-top:40vh">Shader compilation failed</h1>';
        return;
    }
    const l = {};
    const n = gl.getProgramParameter(prog, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) {
        const info = gl.getActiveUniform(prog, i);
        l[info.name] = gl.getUniformLocation(prog, info.name);
    }
    loc = l;

    resize();
    requestAnimationFrame(render);
}

// ── Mouse controls ───────────────────────────────────────────────────────────
canvas.addEventListener('mousedown', (e) => {
    if (e.button === 0) { isDragging = true; lastMouse.x = e.clientX; lastMouse.y = e.clientY; }
});
window.addEventListener('mousemove', (e) => {
    if (!isDragging) return;
    camTheta -= (e.clientX - lastMouse.x) * 0.005;
    camPhi = Math.max(0.001, Math.min(Math.PI - 0.001, camPhi + (e.clientY - lastMouse.y) * 0.005));
    lastMouse.x = e.clientX; lastMouse.y = e.clientY;
});
window.addEventListener('mouseup', () => { isDragging = false; });
canvas.addEventListener('wheel', (e) => {
    e.preventDefault();
    camDist *= 1.0 + e.deltaY * 0.001;
    camDist = Math.max(35.0, Math.min(100.0, camDist));
}, { passive: false });

// ── Touch controls ───────────────────────────────────────────────────────────
let lastPinchDist = 0;
canvas.addEventListener('touchstart', (e) => {
    if (e.touches.length === 1) {
        isDragging = true;
        lastMouse.x = e.touches[0].clientX;
        lastMouse.y = e.touches[0].clientY;
    } else if (e.touches.length === 2) {
        isDragging = false;
        const dx = e.touches[0].clientX - e.touches[1].clientX;
        const dy = e.touches[0].clientY - e.touches[1].clientY;
        lastPinchDist = Math.sqrt(dx * dx + dy * dy);
    }
}, { passive: false });
canvas.addEventListener('touchmove', (e) => {
    e.preventDefault();
    if (e.touches.length === 2) {
        // Pinch zoom
        const dx = e.touches[0].clientX - e.touches[1].clientX;
        const dy = e.touches[0].clientY - e.touches[1].clientY;
        const pinchDist = Math.sqrt(dx * dx + dy * dy);
        const delta = pinchDist - lastPinchDist;
        camDist *= 1.0 - delta * 0.005;
        camDist = Math.max(35.0, Math.min(100.0, camDist));
        lastPinchDist = pinchDist;
    } else if (isDragging && e.touches.length === 1) {
        const dx = e.touches[0].clientX - lastMouse.x;
        const dy = e.touches[0].clientY - lastMouse.y;
        camTheta -= dx * 0.005;
        camPhi = Math.max(0.001, Math.min(Math.PI - 0.001, camPhi + dy * 0.005));
        lastMouse.x = e.touches[0].clientX; lastMouse.y = e.touches[0].clientY;
    }
}, { passive: false });
canvas.addEventListener('touchend', () => { isDragging = false; });

// ── Keyboard ─────────────────────────────────────────────────────────────────
window.addEventListener('keydown', (e) => {
    if (e.key === 'r' || e.key === 'R') {
        camTheta = 100.0 * 3.14159265359 / 180.0; camPhi = 80.0 * 3.14159265359 / 180.0; camDist = 45.0; diskPsi = 0.0;
        sliderPsiDisk.value = 0; valPsiDisk.textContent = '0.0°';
    }
    if (e.key === ' ') { e.preventDefault(); paused = !paused; }
});

// ── Mouse drag → update HUD camInfo live ────────────────────────────────────
window.addEventListener('mousemove', () => {
    if (!isDragging) return;
    document.getElementById('camInfo').textContent =
        `θ: ${(camTheta * 180 / Math.PI).toFixed(1)}°  φ: ${(camPhi * 180 / Math.PI).toFixed(1)}°  ψd: ${(diskPsi * 180 / Math.PI).toFixed(1)}°  d: ${camDist.toFixed(1)}`;
});

 // ── Slider ψ disque ──────────────────────────────────────────────────────────
const sliderPsiDisk    = document.getElementById('sliderPsiDisk');
const valPsiDisk       = document.getElementById('valPsiDisk');
const checkRealistic   = document.getElementById('checkRealistic');
const checkShadow      = document.getElementById('checkShadow');

sliderPsiDisk.addEventListener('input', () => {
    diskPsi = parseFloat(sliderPsiDisk.value) * Math.PI / 180.0;
    valPsiDisk.textContent = parseFloat(sliderPsiDisk.value).toFixed(1) + '°';
    document.getElementById('camInfo').textContent =
        `θ: ${(camTheta * 180 / Math.PI).toFixed(1)}°  φ: ${(camPhi * 180 / Math.PI).toFixed(1)}°  ψd: ${(diskPsi * 180 / Math.PI).toFixed(1)}°  d: ${camDist.toFixed(1)}`;
});

checkRealistic.addEventListener('change', () => {
    realisticMode = checkRealistic.checked;
    gl.uniform1f(loc.uRealistic, realisticMode ? 1.0 : 0.0);
    gl.uniform1f(loc.uTimeOffset, -simTime);
    gl.uniform1f(loc.uSeed, realisticMode ? 1.0 : 0.0);
});

checkShadow.addEventListener('change', () => {
    showShadow = checkShadow.checked;
    gl.uniform1f(loc.uShowShadow, showShadow ? 1.0 : 0.0);
});


