// Testa a regra de quando bloquear o app por biometria (src/App.jsx, bloco BIO-CORE).
// Rodar:  node tests/bio_core.test.cjs
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'App.jsx'), 'utf8');
const ini = src.indexOf('// ---- BIO-CORE-INICIO'), fim = src.indexOf('// ---- BIO-CORE-FIM');
assert(ini > 0 && fim > ini);
const { bioPrecisaBloquear, BIO_LIMITE_MS } = new Function(src.slice(ini, fim) + '; return { bioPrecisaBloquear, BIO_LIMITE_MS };')();
assert.strictEqual(BIO_LIMITE_MS, 60000);
assert.strictEqual(bioPrecisaBloquear(0, 1e9), false, 'nunca saiu: não bloqueia');
assert.strictEqual(bioPrecisaBloquear(1000, 1000 + 59000), false, 'menos de 1 min fora');
assert.strictEqual(bioPrecisaBloquear(1000, 1000 + 60000), false, 'exatamente 1 min ainda não');
assert.strictEqual(bioPrecisaBloquear(1000, 1000 + 60001), true, 'mais de 1 min');
assert.strictEqual(bioPrecisaBloquear(1000, 1000 + 5000, 3000), true, 'limite configurável');
console.log('bio_core: todos os testes passaram');
