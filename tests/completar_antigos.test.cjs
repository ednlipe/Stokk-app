// Testa completarAntigos (adaptador do Supabase, src/App.jsx e public/desktop/index.html):
// quando a leitura com limite traz só as linhas mais recentes, as ocorrências em aberto antigas e o
// último local de equipamentos sem local recente têm que ser buscados à parte.
// Rodar:  node tests/completar_antigos.test.cjs      (banco simulado)
const fs = require('fs'), path = require('path'), assert = require('assert');
const app = fs.readFileSync(path.join(__dirname, '..', 'src', 'App.jsx'), 'utf8');
const desk = fs.readFileSync(path.join(__dirname, '..', 'public', 'desktop', 'index.html'), 'utf8');
const FIM = "}catch(err){ console.error('completarAntigos', table, err); }\n  }";
function bloco(src, nome){
  const ini = src.indexOf('  async function completarAntigos('), fim = src.indexOf(FIM, ini);
  assert(ini > 0 && fim > ini, 'completarAntigos não encontrado em ' + nome);
  return src.slice(ini, fim + FIM.length);
}
const bApp = bloco(app, 'App.jsx'), bDesk = bloco(desk, 'desktop');
assert.strictEqual(bApp, bDesk, 'completarAntigos diferente entre App.jsx e desktop/index.html');

// banco simulado: select/eq/is/order/limit, devolve {data, error}
function fakeSb(tabelas, log){
  return { from(t){
    const f = [], ord = []; let lim = null;
    const b = {
      select(){ return b; },
      eq(c, v){ f.push(r => r[c] === v); return b; },
      is(c, v){ f.push(r => (r[c] == null) === (v === null)); return b; },
      order(c, o){ ord.push([c, o && o.ascending === false ? -1 : 1]); return b; },
      limit(n){ lim = n; return b; },
      then(res, rej){
        log.push(t);
        let rows = (tabelas[t] || []).filter(r => f.every(fn => fn(r)));
        rows.sort((a, c) => { for (const [k, d] of ord){ if (a[k] < c[k]) return -d; if (a[k] > c[k]) return d; } return 0; });
        if (lim != null) rows = rows.slice(0, lim);
        return Promise.resolve({ data: rows.map(r => Object.assign({}, r)), error: null }).then(res, rej);
      }
    };
    return b;
  } };
}
function montar(tabelas){
  const log = [];
  const fn = new Function('sb', 'areaDaTabela', bApp + '\nreturn completarAntigos;')(fakeSb(tabelas, log), t => 'gestao');
  return { fn, log };
}

(async () => {
  const banco = {
    equipamentos: [{ id: 'E1', area: 'gestao' }, { id: 'E2', area: 'gestao' }, { id: 'E3', area: 'gestao' }, { id: 'X', area: 'trefila' }],
    ocorrencias: [
      { id: 'o-velha', equipamento_id: 'E1', liberada_em: null, anulado: false, area: 'gestao' },     // aberta, antiga
      { id: 'o-anul', equipamento_id: 'E2', liberada_em: null, anulado: true, area: 'gestao' },       // anulada: não volta
      { id: 'o-lib', equipamento_id: 'E2', liberada_em: '2026-01-02', anulado: false, area: 'gestao' }, // liberada: não volta
      { id: 'o-rec', equipamento_id: 'E3', liberada_em: null, anulado: false, area: 'gestao' },       // já veio na leitura
      { id: 'o-out', equipamento_id: 'X', liberada_em: null, anulado: false, area: 'trefila' },       // outra área
    ],
    equipamento_locais: [
      { id: 'l1', equipamento_id: 'E1', data_hora: '2026-01-01', timestamp: '2026-01-01', anulado: false, area: 'gestao' },
      { id: 'l2', equipamento_id: 'E1', data_hora: '2026-02-01', timestamp: '2026-02-01', anulado: false, area: 'gestao' }, // último válido de E1
      { id: 'l3', equipamento_id: 'E1', data_hora: '2026-03-01', timestamp: '2026-03-01', anulado: true, area: 'gestao' },  // anulado
      { id: 'l4', equipamento_id: 'E2', data_hora: '2026-11-01', timestamp: '2026-11-01', anulado: false, area: 'gestao' }, // já veio
    ],
  };

  // ocorrências: junta a aberta antiga, sem duplicar a que já veio e sem anulada, liberada ou de outra área
  { const { fn } = montar(banco);
    const data = [{ id: 'o-rec', equipamento_id: 'E3', liberada_em: null, anulado: false }];
    await fn('ocorrencias', data, 'gestao', 'id');
    assert.deepStrictEqual(data.map(r => r.id).sort(), ['o-rec', 'o-velha']); }

  // locais: E1 só tinha local anulado na leitura -> busca o último válido (l2); E2 já tem; E3 não tem nenhum
  { const { fn } = montar(banco);
    const data = [banco.equipamento_locais[2], banco.equipamento_locais[3]].map(r => Object.assign({}, r));
    await fn('equipamento_locais', data, 'gestao', 'id');
    assert.deepStrictEqual(data.map(r => r.id).sort(), ['l2', 'l3', 'l4']); }

  // outra tabela: não faz consulta nenhuma
  { const { fn, log } = montar(banco);
    const data = [{ id: 'a1' }];
    await fn('abastecimentos', data, 'gestao', 'id');
    assert.deepStrictEqual(data, [{ id: 'a1' }]); assert.strictEqual(log.length, 0); }

  // erro do banco: não quebra, mantém o que já tinha
  { const ruim = { from(){ const b = { select(){ return b; }, eq(){ return b; }, is(){ return b; }, then(res){ return Promise.resolve({ data: null, error: { message: 'x' } }).then(res); } }; return b; } };
    const fn = new Function('sb', 'areaDaTabela', bApp + '\nreturn completarAntigos;')(ruim, () => 'gestao');
    const err = console.error; console.error = () => {};
    const data = [{ id: 'o1' }]; await fn('ocorrencias', data, 'gestao', 'id');
    console.error = err;
    assert.deepStrictEqual(data, [{ id: 'o1' }]); }

  console.log('completar_antigos: todos os testes passaram');
})().catch(e => { console.error(e); process.exit(1); });
