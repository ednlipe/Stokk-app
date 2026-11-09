// Testa as regras de contagem/texto do Stokkbook (src/App.jsx, bloco "STOKKBOOK").
// Rodar:  node tests/stokkbook_core.test.cjs
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'App.jsx'), 'utf8');
const ini = src.indexOf('// ---- SBK-CORE-INICIO'), fim = src.indexOf('// ---- SBK-CORE-FIM');
assert(ini > 0 && fim > ini);
const { sbkResumoReacoes, sbkQuemReagiu, sbkNovos, sbkQuando } = new Function(src.slice(ini, fim) + '; return { sbkResumoReacoes, sbkQuemReagiu, sbkNovos, sbkQuando };')();
const R = [
  { post_id: 1, user_id: 'a', user_nome: 'Ana', emoji: 'palmas', criado_em: '2026-11-09T10:00:00Z' },
  { post_id: 1, user_id: 'b', user_nome: 'Beto', emoji: 'palmas', criado_em: '2026-11-09T10:01:00Z' },
  { post_id: 1, user_id: 'c', user_nome: 'Caio', emoji: 'foguete', criado_em: '2026-11-09T10:02:00Z' },
  { post_id: 1, user_id: 'd', user_nome: 'Duda', emoji: 'confete', criado_em: '2026-11-09T10:03:00Z' },
  { post_id: 2, user_id: 'a', user_nome: 'Ana', emoji: 'joia', criado_em: '2026-11-09T10:04:00Z' },
];
let r = sbkResumoReacoes(R, 1, 'c');
assert.deepStrictEqual(r.por, { palmas: 2, foguete: 1, confete: 1 }); assert.strictEqual(r.meu, 'foguete'); assert.strictEqual(r.total, 4);
r = sbkResumoReacoes(R, 2, 'zzz'); assert.strictEqual(r.meu, null); assert.strictEqual(r.total, 1);
assert.strictEqual(sbkResumoReacoes([], 1, 'a').total, 0);
// quem reagiu
assert.strictEqual(sbkQuemReagiu(R, 2, 'x'), 'Ana');
assert.strictEqual(sbkQuemReagiu(R.slice(0, 2), 1, 'x'), 'Ana e Beto');
assert.strictEqual(sbkQuemReagiu(R.slice(0, 3), 1, 'x'), 'Ana, Beto e Caio');
assert.strictEqual(sbkQuemReagiu(R, 1, 'x'), 'Ana, Beto e mais 2');
assert.strictEqual(sbkQuemReagiu(R, 1, 'c'), 'Você, Ana e mais 2', 'a própria pessoa vem primeiro');
assert.strictEqual(sbkQuemReagiu(R, 99, 'c'), '');
assert.strictEqual(sbkQuemReagiu([{ post_id: 1, user_id: 'q', emoji: 'joia' }], 1, 'x'), 'Alguém');
// selo de novidades: só posts novos, não ocultos, e não os da própria pessoa
const P = [
  { id: 1, autor_id: 'a', criado_em: '2026-11-09T12:00:00Z', oculto: false },
  { id: 2, autor_id: 'me', criado_em: '2026-11-09T12:05:00Z', oculto: false },
  { id: 3, autor_id: 'b', criado_em: '2026-11-09T12:10:00Z', oculto: true },
  { id: 4, autor_id: 'c', criado_em: '2026-11-09T09:00:00Z', oculto: false },
];
assert.strictEqual(sbkNovos(P, new Date('2026-11-09T11:00:00Z').getTime(), 'me'), 1);
assert.strictEqual(sbkNovos(P, new Date('2026-11-09T08:00:00Z').getTime(), 'me'), 2);
assert.strictEqual(sbkNovos(P, new Date('2026-11-09T13:00:00Z').getTime(), 'me'), 0);
assert.strictEqual(sbkNovos(null, 0, 'me'), 0);
// tempo relativo
const agora = new Date('2026-11-09T12:00:00Z').getTime(), ha = m => new Date(agora - m * 60000).toISOString();
assert.strictEqual(sbkQuando(ha(0.2), agora), 'agora'); assert.strictEqual(sbkQuando(ha(5), agora), 'há 5 min');
assert.strictEqual(sbkQuando(ha(150), agora), 'há 2 h'); assert.strictEqual(sbkQuando(ha(1500), agora), 'ontem');
assert.strictEqual(sbkQuando(ha(5000), agora), null); assert.strictEqual(sbkQuando('lixo', agora), '');
console.log('stokkbook_core: todos os testes passaram');
