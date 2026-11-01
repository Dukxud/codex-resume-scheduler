// Prevent the approved optical material or corrected tip from silently regressing.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {Script} = require('node:vm');

const root = path.resolve(__dirname, '..');
const reference = fs.readFileSync(path.join(root,'design','Aero-v3-hybrid-approved-v2.0.1.html'),'utf8');
const production = fs.readFileSync(path.join(root,'assets','AeroBar.html'),'utf8');
function script(source,id) {
  const match = source.match(new RegExp('<script id="'+id+'"[^>]*>([\\s\\S]*?)<\\/script>'));
  assert.ok(match,'Required shader/source '+id+' missing');
  return match[1];
}

test('production uses exact owner-approved vertex shader and corrected optical fragment',()=>{
  assert.equal(script(production,'v3vert'),script(reference,'v3vert'));
  // The approved 2.0.1 shader is unchanged except for a dedicated moving
  // specular reflection and its intensity uniform.
  const approved=script(reference,'hybridfrag');
  const augmented=script(production,'hybridfrag');
  const stripped=augmented
    .replace('uDepth,uCompact,uShimmer;','uDepth,uCompact;')
    .replace(/ \/\/ A wide, softly reflected studio light[\s\S]*?\*uShimmer;\r?\n/, '');
  assert.equal(stripped,approved);
  assert.match(augmented,/specularPatch/);
  assert.match(production,/getFrames:\(\)=>frames/);
  assert.match(production,/getSettings:\(\)=>/);
  assert.ok(!production.includes('hybrid&&aero)'));

  assert.match(script(production,'hybridfrag'),/Shared pixel-space capsule/);
  assert.match(script(production,'hybridfrag'),/float cov=1\.-smoothstep/);
});

test('production preserves captured Windows v1.8 bar pixels and compositor',()=>{
  assert.deepEqual(JSON.parse(script(production,'native-images')),
                   JSON.parse(script(reference,'native-images')));
  const a=reference.match(/function nativePaint\(([\s\S]*?)function drawNativeAll\(\)/);
  const b=production.match(/function nativePaint\(([\s\S]*?)function paintNative\(\)/);
  assert.ok(a&&b);
  assert.equal(a[1].trim(),b[1].replaceAll('aeroEnabled','aero').trim());
});

test('isolated WebView2 page is local and its host API is syntactically valid',()=>{
  const source=production.match(/<script>([\s\S]*?)<\/script><\/body>/);
  assert.ok(source);
  new Script(source[1]);
  assert.match(production,/Content-Security-Policy/);
  assert.match(production,/connect-src 'none'/);
  assert.match(source[1],/window\.chrome\.webview\.addEventListener\('message'/);
  assert.match(source[1],/window\.aeroBarProof/);
  assert.match(source[1],/requestAnimationFrame\(tick\)/);
  assert.equal((production.match(/getContext\('webgl2'/g)||[]).length,1);
  assert.match(source[1],/function updateCustomSprite/);
  assert.match(source[1],/selectedColor\.startsWith/);
});