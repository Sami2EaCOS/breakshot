'use strict';

const fs = require('fs');
const path = require('path');

const htmlPath = path.join(__dirname, '..', 'web_export', 'index.html');
let html = fs.readFileSync(htmlPath, 'utf8');

html = html.replace(
  /<meta name="viewport" content="[^"]*">/,
  '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0">'
);

html = html.replace(
  /html, body(?:, #canvas)? \{[\s\S]*?#canvas \{[\s\S]*?\}/,
  `html, body {
\tmargin: 0;
\tpadding: 0;
\tborder: 0;
\twidth: 100%;
\theight: 100%;
}

body {
\tdisplay: flex;
\tjustify-content: center;
\talign-items: center;
}

#canvas {
\tdisplay: block;
\twidth: 720px;
\theight: 1280px;
\timage-rendering: pixelated;
\timage-rendering: crisp-edges;
}`
);

html = html.replace('<canvas id="canvas">', '<canvas id="canvas" width="720" height="1280">');
html = html.replace(/"canvasResizePolicy":\d+/, '"canvasResizePolicy":0');

const fixedCanvasScript = `
<script>
(function () {
\tconst BASE_W = 720;
\tconst BASE_H = 1280;
\tconst STEPS = [1, 0.5, 0.25];
\tfunction resizeFixedCanvas() {
\t\tconst canvas = document.getElementById('canvas');
\t\tif (!canvas) return;
\t\tconst fit = Math.min(window.innerWidth / BASE_W, window.innerHeight / BASE_H);
\t\tlet scale = STEPS[STEPS.length - 1];
\t\tfor (const candidate of STEPS) {
\t\t\tif (candidate <= fit) {
\t\t\t\tscale = candidate;
\t\t\t\tbreak;
\t\t\t}
\t\t}
\t\tcanvas.style.width = Math.round(BASE_W * scale) + 'px';
\t\tcanvas.style.height = Math.round(BASE_H * scale) + 'px';
\t}
\twindow.addEventListener('resize', resizeFixedCanvas, { passive: true });
\twindow.addEventListener('orientationchange', resizeFixedCanvas, { passive: true });
\tdocument.addEventListener('DOMContentLoaded', resizeFixedCanvas);
\tresizeFixedCanvas();
}());
</script>`;

if (!html.includes('const BASE_W = 720;')) {
  html = html.replace('</body>', `${fixedCanvasScript}\n\t</body>`);
}

fs.writeFileSync(htmlPath, html);
