# OpenSOP landing page

A storytelling scroll site: five chapters from [`MANIFESTO.md`](../MANIFESTO.md) and
[`README.md`](../README.md), each with its own painted color world.

- **Three.js** — full-screen paint shader (domain-warped fbm + a cursor trail buffer the
  pigment reacts to)
- **GSAP ScrollTrigger** — chapter entrances and the palette crossfades between scenes
- **Lenis** — smooth scrolling

No build step — three static files, libraries pinned from CDN. In keeping with the CLI:
the files are the site.

## Preview locally

Modules don't load over `file://`, so serve the directory:

```bash
python3 -m http.server 8000 -d site
# open http://localhost:8000
```

## Editing

- Chapter copy lives in `index.html` (one `<section class="scene">` per chapter).
- Colors live in the `PALETTES` map at the top of `main.js` — `a/b/c` are the shader
  pigments, the rest drive CSS custom properties so type travels with the paint.
- The page respects `prefers-reduced-motion`: no smooth-scroll hijack, no entrance
  animation, a still background.
