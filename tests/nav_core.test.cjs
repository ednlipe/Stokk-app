// Testa a contagem de novidades das abas (src/App.jsx, bloco NAV-CORE). Rodar: node tests/nav_core.test.cjs
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'App.jsx'), 'utf8');
const a = src.indexOf('// ---- NAV-CORE-INICIO'), b = src.indexOf('// ---- NAV-CORE-FIM'); assert(a > 0 && b > a);
const { navNovidades } = new Function(src.slice(a, b) + '; return { navNovidades };')();
const it = (t, por) => ({ t, por });
assert.strictEqual(navNovidades([it(10,'x'), it(20,'y'), it(30,'eu')], 'eu', 15), 1, 'só o que é depois da última visita e de outra pessoa');
assert.strictEqual(navNovidades([it(15,'x')], 'eu', 15), 0, 'no mesmo instante não conta');
assert.strictEqual(navNovidades([it(20,null)], 'eu', 15), 1, 'registro de sistema (sem autor) conta');
assert.strictEqual(navNovidades([], 'eu', 0), 0); assert.strictEqual(navNovidades(null, 'eu', 0), 0);
assert.strictEqual(navNovidades([it(0,'x')], 'eu', 0), 0, 'data inválida (0) nunca conta');
console.log('nav_core: todos os testes passaram');
