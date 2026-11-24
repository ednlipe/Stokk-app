// Testa a "falha silenciosa" do update (bloco UPD-CORE em src/App.jsx e public/desktop/index.html).
// A RLS do Supabase não dá erro quando barra um UPDATE: só altera 0 linhas. O update tem que avisar.
// Rodar:  node tests/update_core.test.cjs
const fs = require('fs'), path = require('path'), assert = require('assert');
const raiz = path.join(__dirname, '..');
function bloco(arq){
  const src = fs.readFileSync(path.join(raiz, arq), 'utf8');
  const ini = src.indexOf('// ---- UPD-CORE-INICIO'), fim = src.indexOf('// ---- UPD-CORE-FIM');
  assert(ini > 0 && fim > ini, 'UPD-CORE não encontrado em ' + arq);
  return src.slice(ini, fim);
}
const app = bloco('src/App.jsx'), desk = bloco('public/desktop/index.html');
assert.strictEqual(app, desk, 'UPD-CORE do app e do desktop têm que ser idênticos');
const { updExecutar, updMsg, UPD_SEM_LINHAS } = new Function(app + '; return { updExecutar, updMsg, UPD_SEM_LINHAS };')();

// imita o query builder do supabase-js: .select(coluna) devolve a promessa com { data, error }
function consulta(resposta){
  const q = { pediu: null, select(col){ q.pediu = col; return Promise.resolve(resposta); } };
  return q;
}

(async () => {
  // 1 linha alterada: passa e devolve 1
  const q1 = consulta({ data: [{ id: 'lo_1' }], error: null });
  assert.strictEqual(await updExecutar(q1, 'id'), 1);
  assert.strictEqual(q1.pediu, 'id', 'tem que pedir de volta só a coluna da chave');

  // várias linhas também passam
  assert.strictEqual(await updExecutar(consulta({ data: [{ id: 1 }, { id: 2 }], error: null }), 'id'), 2);

  // 0 linhas (RLS barrou, prazo de 48 h vencido, registro de outra pessoa...): erro com a mensagem em português
  for (const resp of [{ data: [], error: null }, { data: null, error: null }, { error: null }]){
    await assert.rejects(updExecutar(consulta(resp), 'id'), e => {
      assert.strictEqual(e.semLinhas, true);
      assert.strictEqual(e.message, UPD_SEM_LINHAS);
      return true;
    });
  }
  assert(/não tem permissão/.test(UPD_SEM_LINHAS) && /Atualize a tela/.test(UPD_SEM_LINHAS));

  // erro do banco continua sendo o erro do banco (não vira "sem linhas")
  const erroBanco = { message: 'violates check constraint', code: '23514' };
  await assert.rejects(updExecutar(consulta({ data: null, error: erroBanco }), 'id'), e => e === erroBanco);

  // updMsg: mensagem própria só para "sem linhas"; os outros erros ficam com a mensagem da tela
  assert.strictEqual(updMsg(Object.assign(new Error(UPD_SEM_LINHAS), { semLinhas: true }), 'padrão'), UPD_SEM_LINHAS);
  assert.strictEqual(updMsg(new Error('rede'), 'padrão'), 'padrão');
  assert.strictEqual(updMsg(null, 'padrão'), 'padrão');

  // os dois doc().update() (app e desktop) usam o UPD-CORE
  for (const arq of ['src/App.jsx', 'public/desktop/index.html']){
    const src = fs.readFileSync(path.join(raiz, arq), 'utf8');
    const i = src.indexOf('async update(dataObj){');
    assert(i > 0, 'doc().update não encontrado em ' + arq);
    assert(src.slice(i, i + 500).includes('updExecutar(q,'), arq + ': doc().update tem que passar pelo updExecutar');
  }

  console.log('update_core: todos os testes passaram');
})().catch(e => { console.error(e); process.exit(1); });
