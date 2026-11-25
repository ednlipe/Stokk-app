// Testa a releitura do tempo real no adaptador do Supabase (createSupabaseDB em src/App.jsx e
// public/desktop/index.html): o evento relê com a ordem e o limite da assinatura, eventos seguidos
// viram no máximo 2 leituras, resposta atrasada não sobrescreve a mais nova e completarAntigos roda
// no evento para ocorrências, locais e 5S. NÃO testa a entrega de eventos pelo Supabase (isso só com o banco real).
// Banco simulado; quem decide quando cada resposta chega é o teste (sem depender de tempo).
// Rodar:  node tests/realtime_core.test.cjs
const fs = require('fs'), path = require('path'), assert = require('assert');
const fontes = {
  app: fs.readFileSync(path.join(__dirname, '..', 'src', 'App.jsx'), 'utf8'),
  desktop: fs.readFileSync(path.join(__dirname, '..', 'public', 'desktop', 'index.html'), 'utf8'),
};
function trecho(src, ini, fim, nome){
  const i = src.indexOf(ini), f = src.indexOf(fim, i);
  assert(i >= 0 && f > i, ini.trim() + ' não encontrado em ' + nome);
  return src.slice(i, f + fim.length);
}
// a releitura do realtime tem que ser a mesma nos dois arquivos
const rel = n => trecho(fontes[n], '  function releituraRealtime(', '\n  }\n', n);
assert.strictEqual(rel('app'), rel('desktop'), 'releituraRealtime diferente entre App.jsx e desktop/index.html');

const snake = s => s.replace(/[A-Z]/g, c => '_' + c.toLowerCase());
const camel = s => s.replace(/_([a-z0-9])/g, (_, c) => c.toUpperCase());
const objToCamel = o => { const r = {}; for (const k in o) r[camel(k)] = o[k]; return r; };
const tick = () => new Promise(r => setImmediate(r));

// banco simulado: cada consulta fica na fila até o teste soltar (soltar/soltarTudo)
function montar(src, nome, banco){
  const fila = [], log = [], canais = {};
  const sb = {
    channel(){ const c = { on(_e, f, cb){ canais[f.table] = cb; return c; }, subscribe(){ return c; } }; return c; },
    from(t){
      const f = [], ord = []; let rng = null, lim = null;
      const b = {
        select(){ return b; },
        eq(c, v){ f.push(r => r[c] === v); return b; },
        is(c, v){ f.push(r => (r[c] == null) === (v === null)); return b; },
        order(c, o){ ord.push(c + ':' + (o && o.ascending === false ? 'desc' : 'asc')); return b; },
        range(a, z){ rng = [a, z]; return b; },
        limit(n){ lim = n; return b; },
        then(res, rej){
          // a foto dos dados é tirada na hora da consulta, como no banco de verdade
          let rows = (banco[t] || []).filter(r => f.every(fn => fn(r)));
          rows.sort((a, c) => { for (const o of ord){ const [k, d] = o.split(':'); const s = d === 'desc' ? -1 : 1;
            if (a[k] < c[k]) return -s; if (a[k] > c[k]) return s; } return 0; });
          if (rng) rows = rows.slice(rng[0], rng[1] + 1);
          if (lim != null) rows = rows.slice(0, lim);
          const erro = banco.__erro && banco.__erro(t);
          const q = { t, ord, rng };
          log.push(q);
          return new Promise(ok => { q.soltar = () => ok(erro ? { data: null, error: { message: erro } } : { data: rows.map(r => Object.assign({}, r)), error: null }); fila.push(q); }).then(res, rej);
        },
      };
      return b;
    },
  };
  const state = {};
  const ctx = { sb, state, PK: { movimentos: 'id', sessoes: 'id', producoes: 'id', volumes: 'lote' }, camelToSnake: snake, objToCamel,
    objToSnake: x => x, areaDaTabela: () => null, toast: m => { throw new Error('toast inesperado: ' + m); },
    DIESEL_TABLES: [], SOMENTE_INSERIR: [], updExecutar(){}, updMsg(){} };
  const codigo = trecho(src, 'function createSupabaseDB(){', '\n}\n', nome);
  const db = new Function(...Object.keys(ctx), codigo + '\nreturn createSupabaseDB();')(...Object.values(ctx));
  // solta a consulta i da fila (0 = a mais antiga ainda pendente) e deixa o código andar
  async function soltar(i){ await tick(); const q = fila.splice(i, 1)[0]; assert(q, 'nenhuma consulta pendente'); q.soltar(); await tick(); await tick(); }
  async function soltarTudo(){ for (let n = 0; n < 50; n++){ await tick(); if (!fila.length){ await tick(); if (!fila.length) return; } else await soltar(0); } throw new Error('consultas sem fim'); }
  return { db, log, fila, canais, state, soltar, soltarTudo };
}

(async () => {
  for (const [nome, src] of Object.entries(fontes)){
    // 1) movimentos: o evento relê com a ordem desc e o limite da assinatura
    { const banco = { movimentos: Array.from({ length: 10 }, (_, i) => ({ id: 'm' + i, timestamp: 100 + i })) };
      const s = montar(src, nome, banco);
      let ult = null;
      s.db.collection('movimentos').orderBy('timestamp', 'desc').limit(3).onSnapshot(x => { ult = x.docs.map(d => d.id); });
      await s.soltarTudo();
      assert.deepStrictEqual(ult, ['m9', 'm8', 'm7'], nome + ': leitura inicial');
      banco.movimentos.push({ id: 'mX', timestamp: 999 });
      s.log.length = 0; s.canais.movimentos(); await s.soltarTudo();
      assert.deepStrictEqual(ult, ['mX', 'm9', 'm8'], nome + ': evento perdeu a ordem ou o limite');
      assert.strictEqual(s.log.length, 1, nome + ': evento deveria fazer 1 consulta');
      assert.deepStrictEqual(s.log[0].ord, ['timestamp:desc', 'id:asc']);
      assert.deepStrictEqual(s.log[0].rng, [0, 2]); }

    // 2) rajada: 6 eventos com uma releitura em andamento = 1 em andamento + 1 no fim
    { const banco = { sessoes: [{ id: 's1', iniciado_em: 1, ativo: true }] };
      const s = montar(src, nome, banco);
      s.db.collection('sessoes').orderBy('iniciadoEm', 'desc').limit(100).onSnapshot(() => {});
      await s.soltarTudo(); s.log.length = 0;
      for (let i = 0; i < 6; i++) s.canais.sessoes();
      await tick();
      assert.strictEqual(s.fila.length, 1, nome + ': eventos seguidos abriram leituras em paralelo');
      await s.soltarTudo();
      assert.strictEqual(s.log.length, 2, nome + ': rajada deveria virar 2 leituras, foram ' + s.log.length);
      s.log.length = 0; s.canais.sessoes(); await s.soltarTudo();
      assert.strictEqual(s.log.length, 1, nome + ': depois da rajada, um evento = uma leitura'); }

    // 3) resposta atrasada: a leitura inicial responde DEPOIS da do evento e não pode sobrescrever
    { const banco = { producoes: [{ id: 'p1', iniciado_em: 1 }] };
      const s = montar(src, nome, banco);
      let ult = null, vezes = 0;
      s.db.collection('producoes').orderBy('iniciadoEm', 'desc').limit(1000).onSnapshot(x => { ult = x.docs.map(d => d.id); vezes++; });
      await tick();
      banco.producoes.push({ id: 'p2', iniciado_em: 2 });
      s.canais.producoes(); await tick();
      assert.strictEqual(s.fila.length, 2);
      await s.soltar(1);                         // a do evento (mais nova) chega primeiro
      assert.deepStrictEqual(ult, ['p2', 'p1']);
      await s.soltar(0);                         // a inicial (antiga, sem p2) chega depois
      assert.deepStrictEqual(ult, ['p2', 'p1'], nome + ': resposta atrasada sobrescreveu a mais nova');
      assert.strictEqual(vezes, 1, nome + ': a resposta descartada não deveria avisar a tela'); }

    // 4) erro atrasado não apaga dados bons nem deixa aviso de erro
    { const banco = { ocorrencias: [{ id: 'o1', aberta_em: 1, liberada_em: null, anulado: false }] };
      let falhar = true; banco.__erro = t => (t === 'ocorrencias' && falhar ? 'rede caiu' : null);
      const s = montar(src, nome, banco);
      let ult = null;
      s.db.collection('ocorrencias').orderBy('abertaEm', 'desc').limit(3000).onSnapshot(x => { ult = x.docs.map(d => d.id); });
      await tick(); falhar = false;              // a inicial já saiu com erro; a do evento vai dar certo
      s.canais.ocorrencias(); await tick();
      await s.soltar(1); await s.soltar(0);
      assert.deepStrictEqual(ult, ['o1'], nome + ': erro atrasado apagou a lista');
      assert.strictEqual(s.state.paradasErr, null, nome + ': erro atrasado deixou aviso na tela'); }

    // 5) ocorrências com o limite atingido: o evento mantém a ocorrência aberta antiga (completarAntigos)
    { const banco = { ocorrencias: [
        { id: 'o0', aberta_em: 1, liberada_em: null, anulado: false },
        { id: 'o1', aberta_em: 2, liberada_em: 5, anulado: false },
        { id: 'o2', aberta_em: 3, liberada_em: 6, anulado: false } ] };
      const s = montar(src, nome, banco);
      let ult = null;
      s.db.collection('ocorrencias').orderBy('abertaEm', 'desc').limit(2).onSnapshot(x => { ult = x.docs.map(d => d.id).sort(); });
      await s.soltarTudo();
      assert.deepStrictEqual(ult, ['o0', 'o1', 'o2']);
      banco.ocorrencias.push({ id: 'o3', aberta_em: 4, liberada_em: 7, anulado: false });
      s.canais.ocorrencias(); await s.soltarTudo();
      assert.deepStrictEqual(ult, ['o0', 'o2', 'o3'], nome + ': evento perdeu a ocorrência aberta antiga'); }

    // 5b) locais com o limite atingido: o evento mantém o último local válido de equipamento sem local recente
    { const banco = {
        equipamentos: [{ id: 'E1' }, { id: 'E2' }],
        equipamento_locais: [
          { id: 'l0', equipamento_id: 'E1', data_hora: 1, timestamp: 1, anulado: false },   // último válido de E1 (antigo)
          { id: 'lx', equipamento_id: 'E1', data_hora: 2, timestamp: 2, anulado: true },    // anulado: não conta
          { id: 'l1', equipamento_id: 'E2', data_hora: 5, timestamp: 5, anulado: false },
          { id: 'l2', equipamento_id: 'E2', data_hora: 6, timestamp: 6, anulado: false } ] };
      const s = montar(src, nome, banco);
      let ult = null;
      s.db.collection('equipamento_locais').orderBy('dataHora', 'desc').limit(2).onSnapshot(x => { ult = x.docs.map(d => d.id).sort(); });
      await s.soltarTudo();
      assert.deepStrictEqual(ult, ['l0', 'l1', 'l2'], nome + ': leitura inicial dos locais');
      banco.equipamento_locais.push({ id: 'l3', equipamento_id: 'E2', data_hora: 7, timestamp: 7, anulado: false });
      s.log.length = 0; s.canais.equipamento_locais(); await s.soltarTudo();
      assert.deepStrictEqual(ult, ['l0', 'l2', 'l3'], nome + ': evento perdeu o local antigo de E1 (ou passou do limite)');
      assert(s.log.some(q => q.t === 'equipamentos'), nome + ': evento não rodou o completarAntigos dos locais'); }

    // 5c) 5S com o limite atingido: o evento mantém o 5S em aberto antigo (e não traz o anulado)
    { const banco = { cinco_s: [
        { id: 'c0', aberto_em: 1, concluido_em: null, anulado: false },   // em aberto, antigo
        { id: 'cx', aberto_em: 2, concluido_em: null, anulado: true },    // anulado: não volta
        { id: 'c1', aberto_em: 3, concluido_em: 4, anulado: false },
        { id: 'c2', aberto_em: 5, concluido_em: 6, anulado: false } ] };
      const s = montar(src, nome, banco);
      let ult = null;
      s.db.collection('cinco_s').orderBy('abertoEm', 'desc').limit(2).onSnapshot(x => { ult = x.docs.map(d => d.id).sort(); });
      await s.soltarTudo();
      assert.deepStrictEqual(ult, ['c0', 'c1', 'c2'], nome + ': leitura inicial do 5S');
      banco.cinco_s.push({ id: 'c3', aberto_em: 7, concluido_em: 8, anulado: false });
      s.canais.cinco_s(); await s.soltarTudo();
      assert.deepStrictEqual(ult, ['c0', 'c2', 'c3'], nome + ': evento perdeu o 5S em aberto antigo (ou passou do limite)'); }

    // 6) tabela sem limite (volumes): o evento continua lendo tudo, em páginas de 1000
    { const banco = { volumes: Array.from({ length: 2500 }, (_, i) => ({ lote: 'v' + String(i).padStart(4, '0') })) };
      const s = montar(src, nome, banco);
      let qtd = 0;
      s.db.collection('volumes').onSnapshot(x => { qtd = x.docs.length; });
      await s.soltarTudo(); s.log.length = 0;
      s.canais.volumes(); await s.soltarTudo();
      assert.strictEqual(qtd, 2500, nome + ': volumes incompletos');
      assert.deepStrictEqual(s.log.map(q => q.rng), [[0, 999], [1000, 1999], [2000, 2999]]); }

    console.log('ok  ' + nome);
  }
  console.log('realtime_core: todos os testes passaram');
})().catch(e => { console.error(e); process.exit(1); });
