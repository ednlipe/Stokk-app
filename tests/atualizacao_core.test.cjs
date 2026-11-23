// Testa as regras do aviso de atualização do APK (src/App.jsx, bloco "ATUALIZAÇÃO DO APK").
// Rodar:  node tests/atualizacao_core.test.cjs
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'App.jsx'), 'utf8');
const ini = src.indexOf('// ---- ATU-CORE-INICIO'), fim = src.indexOf('// ---- ATU-CORE-FIM');
assert(ini > 0 && fim > ini);
const { atuJsonOk, atuNovaVersao } = new Function(src.slice(ini, fim) + '; return { atuJsonOk, atuNovaVersao };')();
const R = 'dono/Stokk-app', sha = 'a'.repeat(64);
const ok = { versao: '1.7.2', codigo: 20, url: 'https://github.com/dono/Stokk-app/releases/download/apk-latest/STOKK.apk', sha256: sha, notas: 'x' };
assert(atuJsonOk(ok, R));
assert(!atuJsonOk(null, R) && !atuJsonOk('x', R) && !atuJsonOk(ok, ''));
assert(!atuJsonOk({ ...ok, url: 'http://github.com/dono/Stokk-app/releases/download/a/b.apk' }, R), 'só https');
assert(!atuJsonOk({ ...ok, url: 'https://evil.com/dono/Stokk-app/releases/download/a/b.apk' }, R), 'só do repositório');
assert(!atuJsonOk({ ...ok, url: 'https://github.com/outro/repo/releases/download/a/b.apk' }, R), 'outro repositório');
assert(!atuJsonOk({ ...ok, sha256: 'abc' }, R) && !atuJsonOk({ ...ok, sha256: undefined }, R), 'sha256 obrigatório');
assert(!atuJsonOk({ ...ok, codigo: 'x' }, R));
// Cloudflare: APK na pasta do site (base com https e terminada em "/")
const B = 'https://stokk.conta.workers.dev/apk/';
const cf = { ...ok, url: B + 'STOKK.apk' };
assert(atuJsonOk(cf, '', B) && atuJsonOk(cf, R, B), 'APK da pasta da Cloudflare');
assert(atuJsonOk(ok, R, B), 'durante a troca, a Release do GitHub continua valendo');
assert(!atuJsonOk(cf, R, ''), 'sem base configurada, só o GitHub');
assert(!atuJsonOk({ ...cf, url: 'https://stokk.conta.workers.dev.evil.com/apk/STOKK.apk' }, '', 'https://stokk.conta.workers.dev'), 'base sem "/" no fim não vale');
assert(!atuJsonOk({ ...cf, url: 'https://evil.com/apk/STOKK.apk' }, '', B), 'outro site');
assert(!atuJsonOk({ ...cf, url: 'http://stokk.conta.workers.dev/apk/STOKK.apk' }, '', 'http://stokk.conta.workers.dev/apk/'), 'só https');
assert(!atuJsonOk({ ...cf, sha256: 'abc' }, '', B), 'sha256 obrigatório também na Cloudflare');
// só avisa quando a versão remota é MAIOR (várias seguidas: só a última importa, porque o versao.json é sempre a última)
assert(atuNovaVersao(19, { codigo: 20 }) && atuNovaVersao(19, { codigo: 25 }));
assert(!atuNovaVersao(19, { codigo: 19 }) && !atuNovaVersao(19, { codigo: 18 }));
assert(!atuNovaVersao(undefined, { codigo: 20 }) && !atuNovaVersao(19, null) && !atuNovaVersao(19, {}));
console.log('atualizacao_core: todos os testes passaram');
