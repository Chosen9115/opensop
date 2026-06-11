/* OpenSOP storytelling page.
   Three.js paints the background (domain-warped fbm + cursor trail buffer),
   GSAP ScrollTrigger choreographs the chapters, Lenis smooths the scroll.
   Each chapter owns a palette; scrolling blends shader uniforms and CSS
   custom properties through the same keyframes so type travels with paint. */

import * as THREE from 'three';

const { gsap, ScrollTrigger, Lenis } = window;
gsap.registerPlugin(ScrollTrigger);

const prefersReduced = matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ── palettes ──────────────────────────────────────────────
   a/b/c: paint pigments (dark → mid → bright). The rest drives CSS. */

const PALETTES = {
  prologue: { a: '#0d1120', b: '#2b3457', c: '#9a5f38', ink: '#e9e4d8', accent: '#d9a05b', panel: '#0a0c16', panelA: 0.42, faintA: 0.62, lineA: 0.18, btnText: '#14110a' },
  night:    { a: '#0a1218', b: '#1e3a44', c: '#4e8a82', ink: '#dfe7e3', accent: '#86b3a6', panel: '#081014', panelA: 0.45, faintA: 0.6,  lineA: 0.18, btnText: '#0c1418' },
  ember:    { a: '#1c0f0a', b: '#5a2719', c: '#c25a30', ink: '#f2e3d4', accent: '#e07a4a', panel: '#170d0a', panelA: 0.45, faintA: 0.66, lineA: 0.2,  btnText: '#1c0e08' },
  parchment:{ a: '#ece4d2', b: '#d8c8a6', c: '#b29066', ink: '#2a2118', accent: '#96541f', panel: '#fffbf0', panelA: 0.55, faintA: 0.78, lineA: 0.26, btnText: '#f4eede' },
  pine:     { a: '#0d1611', b: '#27452f', c: '#5f9a66', ink: '#e3e9dd', accent: '#a3c68c', panel: '#0a120e', panelA: 0.45, faintA: 0.62, lineA: 0.18, btnText: '#0e160f' },
  dawn:     { a: '#261c24', b: '#75414b', c: '#d98a5d', ink: '#f3e7da', accent: '#e0945f', panel: '#1e161c', panelA: 0.42, faintA: 0.66, lineA: 0.2,  btnText: '#221408' },
  sunrise:  { a: '#45291a', b: '#a35c32', c: '#f0b061', ink: '#fdf3e3', accent: '#f0b46a', panel: '#2e1c12', panelA: 0.4,  faintA: 0.74, lineA: 0.24, btnText: '#2a1708' },
};

const sections = gsap.utils.toArray('.scene');
const keys = sections.map((s) => s.dataset.palette);

/* ── three.js painted background ─────────────────────────── */

const canvas = document.getElementById('paint');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, depth: false, stencil: false });
const DPR = Math.min(window.devicePixelRatio || 1, 1.75);
renderer.setPixelRatio(DPR);

const quad = new THREE.PlaneGeometry(2, 2);
const camera = new THREE.Camera();

const VERT = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = vec4(position.xy, 0.0, 1.0);
  }
`;

const NOISE = /* glsl */ `
  float hash(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
  }
  float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
  }
  float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    mat2 rot = mat2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 5; i++) {
      v += a * noise(p);
      p = rot * p * 2.03;
      a *= 0.5;
    }
    return v;
  }
`;

const paintMaterial = new THREE.ShaderMaterial({
  vertexShader: VERT,
  fragmentShader: /* glsl */ `
    precision highp float;
    varying vec2 vUv;
    uniform float uTime;
    uniform vec2 uRes;
    uniform vec3 uColA, uColB, uColC;
    uniform sampler2D uTrail;
    ${NOISE}
    void main() {
      vec2 asp = vec2(uRes.x / uRes.y, 1.0);
      vec2 p = (vUv - 0.5) * asp * 1.7;
      float t = uTime * 0.045;
      float trail = texture2D(uTrail, vUv).r;

      vec2 q = vec2(fbm(p + t * 0.6), fbm(p + vec2(5.2, 1.3) - t * 0.4));
      vec2 r = vec2(fbm(p + 2.1 * q + vec2(1.7, 9.2) + 0.10 * t),
                    fbm(p + 2.1 * q + vec2(8.3, 2.8) - 0.07 * t));
      r += trail * 0.45 * vec2(cos(6.2831 * q.x), sin(6.2831 * q.y));
      float f = fbm(p + 2.0 * r);

      vec3 col = mix(uColA, uColB, smoothstep(0.2, 0.75, f));
      col = mix(col, uColC, smoothstep(0.38, 0.92, length(q)) * 0.9);

      float strokes = noise(vec2(p.x * 2.0 + r.x * 5.0, (p.y + r.y) * 52.0));
      col *= 1.0 + (strokes - 0.5) * 0.16;

      col += trail * uColC * 0.30;
      col = mix(col, vec3(1.0), trail * 0.07);

      col += (hash(vUv * uRes) - 0.5) * 0.045;

      float vig = smoothstep(1.4, 0.45, length((vUv - 0.5) * asp * 1.15));
      col *= mix(0.8, 1.0, vig);

      gl_FragColor = vec4(col, 1.0);
    }
  `,
  uniforms: {
    uTime: { value: 0 },
    uRes: { value: new THREE.Vector2(1, 1) },
    uColA: { value: new THREE.Color(PALETTES.prologue.a) },
    uColB: { value: new THREE.Color(PALETTES.prologue.b) },
    uColC: { value: new THREE.Color(PALETTES.prologue.c) },
    uTrail: { value: null },
  },
  depthTest: false,
  depthWrite: false,
});

const paintScene = new THREE.Scene();
paintScene.add(new THREE.Mesh(quad, paintMaterial));

/* cursor trail — ping-pong buffer: a fading brushstroke the paint reacts to */

const trailMaterial = new THREE.ShaderMaterial({
  vertexShader: VERT,
  fragmentShader: /* glsl */ `
    precision highp float;
    varying vec2 vUv;
    uniform sampler2D uPrev;
    uniform vec2 uMouse, uPrevMouse, uRes;
    uniform float uStrength;
    float sdSegment(vec2 p, vec2 a, vec2 b) {
      vec2 pa = p - a, ba = b - a;
      float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
      return length(pa - ba * h);
    }
    void main() {
      float prev = texture2D(uPrev, vUv).r * 0.957;
      vec2 asp = vec2(uRes.x / uRes.y, 1.0);
      float d = sdSegment(vUv * asp, uMouse * asp, uPrevMouse * asp);
      float splat = exp(-d * d * 750.0) * uStrength;
      gl_FragColor = vec4(vec3(min(prev + splat, 1.3)), 1.0);
    }
  `,
  uniforms: {
    uPrev: { value: null },
    uMouse: { value: new THREE.Vector2(-1, -1) },
    uPrevMouse: { value: new THREE.Vector2(-1, -1) },
    uRes: { value: new THREE.Vector2(1, 1) },
    uStrength: { value: 0 },
  },
  depthTest: false,
  depthWrite: false,
});

const trailScene = new THREE.Scene();
trailScene.add(new THREE.Mesh(quad, trailMaterial));

const rtOpts = {
  type: THREE.HalfFloatType,
  minFilter: THREE.LinearFilter,
  magFilter: THREE.LinearFilter,
  depthBuffer: false,
};
let rtA = new THREE.WebGLRenderTarget(2, 2, rtOpts);
let rtB = new THREE.WebGLRenderTarget(2, 2, rtOpts);

function resize() {
  const w = window.innerWidth;
  const h = window.innerHeight;
  renderer.setSize(w, h, false);
  paintMaterial.uniforms.uRes.value.set(w, h);
  trailMaterial.uniforms.uRes.value.set(w, h);
  const tw = Math.max(2, Math.round(w * 0.5));
  const th = Math.max(2, Math.round(h * 0.5));
  rtA.setSize(tw, th);
  rtB.setSize(tw, th);
}
resize();
window.addEventListener('resize', resize);

/* mouse — smoothed position + speed-driven brush strength */

const mouse = { x: 0.5, y: 0.5, tx: 0.5, ty: 0.5, speed: 0, seen: false };
window.addEventListener('pointermove', (e) => {
  mouse.tx = e.clientX / window.innerWidth;
  mouse.ty = 1 - e.clientY / window.innerHeight;
  if (!mouse.seen) {
    mouse.x = mouse.tx;
    mouse.y = mouse.ty;
    mouse.seen = true;
  }
});

let elapsed = 0;
function render(_t, deltaMS) {
  if (document.hidden) return;
  const dt = Math.min(deltaMS / 1000, 0.05);
  if (!prefersReduced) elapsed += dt;

  const px = mouse.x, py = mouse.y;
  mouse.x += (mouse.tx - mouse.x) * 0.16;
  mouse.y += (mouse.ty - mouse.y) * 0.16;
  const v = Math.hypot(mouse.x - px, mouse.y - py) / Math.max(dt, 1e-4);
  mouse.speed += (Math.min(v * 1.6, 1.0) - mouse.speed) * 0.1;

  if (!prefersReduced && mouse.seen) {
    trailMaterial.uniforms.uPrev.value = rtA.texture;
    trailMaterial.uniforms.uPrevMouse.value.set(px, py);
    trailMaterial.uniforms.uMouse.value.set(mouse.x, mouse.y);
    trailMaterial.uniforms.uStrength.value = 0.05 + mouse.speed * 0.55;
    renderer.setRenderTarget(rtB);
    renderer.render(trailScene, camera);
    renderer.setRenderTarget(null);
    [rtA, rtB] = [rtB, rtA];
  }

  paintMaterial.uniforms.uTime.value = elapsed;
  paintMaterial.uniforms.uTrail.value = rtA.texture;
  renderer.render(paintScene, camera);
}
gsap.ticker.add(render);

/* ── palette blending: shader uniforms + CSS variables ───── */

const colorCache = {};
for (const k of Object.keys(PALETTES)) {
  const p = PALETTES[k];
  colorCache[k] = {
    a: new THREE.Color(p.a), b: new THREE.Color(p.b), c: new THREE.Color(p.c),
    ink: new THREE.Color(p.ink), accent: new THREE.Color(p.accent),
    panel: new THREE.Color(p.panel), btnText: new THREE.Color(p.btnText),
    panelA: p.panelA, faintA: p.faintA, lineA: p.lineA,
  };
}

const scratch = { c1: new THREE.Color(), c2: new THREE.Color() };
const rootStyle = document.documentElement.style;
const css = (c) => `#${c.getHexString()}`;
const rgba = (c, a) =>
  `rgba(${Math.round(c.r * 255)}, ${Math.round(c.g * 255)}, ${Math.round(c.b * 255)}, ${a.toFixed(3)})`;

function applyPalette(fromKey, toKey, t) {
  const f = colorCache[fromKey];
  const g = colorCache[toKey];
  const u = paintMaterial.uniforms;
  u.uColA.value.copy(f.a).lerp(g.a, t);
  u.uColB.value.copy(f.b).lerp(g.b, t);
  u.uColC.value.copy(f.c).lerp(g.c, t);

  const ink = scratch.c1.copy(f.ink).lerp(g.ink, t);
  rootStyle.setProperty('--ink', css(ink));
  rootStyle.setProperty('--faint', rgba(ink, THREE.MathUtils.lerp(f.faintA, g.faintA, t)));
  rootStyle.setProperty('--line', rgba(ink, THREE.MathUtils.lerp(f.lineA, g.lineA, t)));
  rootStyle.setProperty('--accent', css(scratch.c2.copy(f.accent).lerp(g.accent, t)));
  rootStyle.setProperty('--panel', rgba(scratch.c2.copy(f.panel).lerp(g.panel, t), THREE.MathUtils.lerp(f.panelA, g.panelA, t)));
  rootStyle.setProperty('--btn-solid-text', css(scratch.c2.copy(f.btnText).lerp(g.btnText, t)));
}

applyPalette(keys[0], keys[0], 0);

/* ── smooth scroll ────────────────────────────────────────── */

if (!prefersReduced) {
  const lenis = new Lenis({ duration: 1.25, smoothWheel: true });
  lenis.on('scroll', ScrollTrigger.update);
  gsap.ticker.add((time) => lenis.raf(time * 1000));
  gsap.ticker.lagSmoothing(0);
}

/* ── scroll choreography ──────────────────────────────────── */

const RAIL_SYMBOLS = { prologue: '○', sunrise: '✦' };
const railNumeral = document.getElementById('rail-numeral');

/* One resolver owns the palette: as section i's top travels from the viewport
   bottom up to 30% from the top, blend palette i-1 → i. Evaluated centrally
   on every scroll so fast jumps can't leave a stale boundary trigger's color. */
let sectionTops = [];
const measureSections = () => {
  sectionTops = sections.map((s) => s.getBoundingClientRect().top + window.scrollY);
};
measureSections();
ScrollTrigger.addEventListener('refresh', measureSections);

function resolvePalette() {
  const H = window.innerHeight;
  const y = window.scrollY;
  for (let i = sections.length - 1; i >= 1; i--) {
    const start = sectionTops[i] - H;          // section top reaches viewport bottom
    const end = sectionTops[i] - H * 0.3;      // section top reaches 30% from viewport top
    if (y >= start) {
      const t = gsap.utils.clamp(0, 1, (y - start) / Math.max(end - start, 1));
      applyPalette(keys[i - 1], keys[i], t);
      return;
    }
  }
  applyPalette(keys[0], keys[0], 0);
}
ScrollTrigger.create({ onUpdate: resolvePalette, onRefresh: resolvePalette, start: 0, end: 'max' });

sections.forEach((sec, i) => {
  // chapter bookkeeping: body attribute + rail numeral
  ScrollTrigger.create({
    trigger: sec,
    start: 'top 55%',
    end: 'bottom 55%',
    onToggle: (self) => {
      if (!self.isActive) return;
      document.body.dataset.chapter = sec.id;
      const label = sec.dataset.numeral || RAIL_SYMBOLS[keys[i]] || '○';
      if (railNumeral.textContent !== label) {
        railNumeral.textContent = label;
        if (!prefersReduced) gsap.fromTo(railNumeral, { autoAlpha: 0, y: 8 }, { autoAlpha: 1, y: 0, duration: 0.5, ease: 'power2.out' });
      }
    },
  });

  if (prefersReduced) return;

  // cinematic entrance per scene
  const lines = sec.querySelectorAll('.l > span');
  const reveals = sec.querySelectorAll('.reveal');
  // the hero plays on load — a ScrollTrigger starting at exactly scroll 0 never fires
  const tl = gsap.timeline(
    i === 0 ? { delay: 0.15 } : { scrollTrigger: { trigger: sec, start: 'top 62%' } }
  );
  if (lines.length) {
    tl.from(lines, { yPercent: 115, duration: 1.15, ease: 'expo.out', stagger: 0.1, immediateRender: true }, 0);
  }
  if (reveals.length) {
    tl.from(reveals, { autoAlpha: 0, y: 26, duration: 0.9, ease: 'power3.out', stagger: 0.12, immediateRender: true }, 0.25);
  }

  // numerals drift slower than the text — painted depth
  const numeral = sec.querySelector('.numeral');
  if (numeral) {
    gsap.fromTo(numeral, { y: 110 }, {
      y: -110,
      ease: 'none',
      scrollTrigger: { trigger: sec, start: 'top bottom', end: 'bottom top', scrub: true },
    });
  }
});

// reading progress on the rail
gsap.to('.rail-fill', {
  scaleY: 1,
  ease: 'none',
  scrollTrigger: { trigger: document.body, start: 'top top', end: 'bottom bottom', scrub: 0.4 },
});

// fonts shift metrics; recompute trigger positions once they land
document.fonts?.ready.then(() => ScrollTrigger.refresh());

/* ── copy install command ─────────────────────────────────── */

const copyBtn = document.getElementById('copy-btn');
copyBtn.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(document.getElementById('install-cmd').textContent);
    copyBtn.textContent = 'copied';
  } catch {
    copyBtn.textContent = 'select it';
  }
  setTimeout(() => (copyBtn.textContent = 'copy'), 1800);
});
