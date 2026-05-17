'use strict';

const fs = require('fs');
const path = require('path');

const htmlPath = path.join(__dirname, '..', 'web_export', 'index.html');
let html = fs.readFileSync(htmlPath, 'utf8');

html = html.replace(
  /<meta name="viewport" content="[^"]*">/,
  '<meta name="viewport" content="width=720, user-scalable=no, initial-scale=1.0">'
);

html = html.replace(
  /html, body, #canvas \{[\s\S]*?#canvas \{\s*display: block;\s*\}/,
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
\twidth: 720px !important;
\theight: 1280px !important;
\timage-rendering: pixelated;
\timage-rendering: crisp-edges;
}`
);

html = html.replace('<canvas id="canvas">', '<canvas id="canvas" width="720" height="1280">');
html = html.replace(/"canvasResizePolicy":\d+/, '"canvasResizePolicy":0');

fs.writeFileSync(htmlPath, html);
