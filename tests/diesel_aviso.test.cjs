// Testa os avisos da Gestão na Edge Function (supabase/functions/avisar-conferencias/index.ts):
//   - "equipamento sem abastecer" (montarDiesel), que ignora equipamento com ocorrência em aberto;
//   - "parada/manutenção aberta ou liberada" (montarOcorrencia): quem recebe, o texto, e as travas.
// Rodar:  node tests/diesel_aviso.test.cjs      (Node 22.13+: tira os tipos do TypeScript; banco simulado)
const fs = require('fs'), path = require('path'), assert = require('assert'), { stripTypeScriptTypes } = require('node:module');
const src = fs.readFileSync(path.join(__dirname, '..', '..', 'supabase', 'functions', 'avisar-conferencias', 'index.ts'), 'utf8');
const ini = src.indexOf('const MS_DIA'), fim = src.indexOf('Deno.serve(');
assert(ini > 0 && fim > ini, 'bloco da Gestão não encontrado na Edge Function');
const js = stripTypeScriptTypes(src.slice(ini, fim));
const T = s => new Date(s).getTime(), dia = (d, h) => '2026-11-' + String(d).padStart(2, '0') + 'T' + String(h === undefined ? 12 : h).padStart(2, '0') + ':00:00-03:00';

// banco simulado: tabelas em memória com select/eq/is/gte/maybeSingle/update
function fakeSb(tabelas) {
  const from = nome => {
    const q = { filtros: [], op: 'select', patch: null };
    const passa = r => q.filtros.every(f => f.tipo === 'eq' ? r[f.c] === f.v : f.tipo === 'is' ? (r[f.c] ?? null) === f.v : true);
    const rows = () => (tabelas[nome] || []);
    q.select = () => q; q.order = () => q; q.limit = () => q; q.gte = () => q;
    q.eq = (c, v) => { q.filtros.push({ tipo: 'eq', c, v }); return q; };
    q.is = (c, v) => { q.filtros.push({ tipo: 'is', c, v }); return q; };
    q.update = patch => { q.op = 'update'; q.patch = patch; return q; };
    q.maybeSingle = async () => ({ data: rows().filter(passa)[0] ?? null, error: null });
    q.then = res => { let data = rows().filter(passa); if (q.op === 'update') data.forEach(r => Object.assign(r, q.patch)); res({ data, error: null }); };
    return q;
  };
  return { from };
}
async function rodar(tabelas, agora, corpo, ...args) {
  const sb = fakeSb(tabelas);
  const areasEsupervisores = async () => ({ nomes: new Map([['gestao', 'Gestão']]), sups: new Map([['gestao', ['sup1', 'sup2']]]) });
  const realNow = Date.now; Date.now = () => agora;
  try { return await new Function('sb', 'areasEsupervisores', 'a', 'b', 'c', js + '; ' + corpo)(sb, areasEsupervisores, ...args); } finally { Date.now = realNow; }
}
const erro = async p => { try { await p; } catch (e) { return e; } assert.fail('devia dar erro'); };

(async () => {
  // ---------- sem abastecer ----------
  const eqs = [
    { id: 'e1', codigo: 'PC01', dias_alerta: 2, alerta_dias_uteis: false, criado_em: dia(1), area: 'gestao', ativo: true, alerta_ativo: true },
    { id: 'e2', codigo: 'CAM01', dias_alerta: 2, alerta_dias_uteis: false, criado_em: dia(1), area: 'gestao', ativo: true, alerta_ativo: true },
    { id: 'e3', codigo: 'FDS', dias_alerta: 2, alerta_dias_uteis: true, criado_em: dia(1), area: 'gestao', ativo: true, alerta_ativo: true },
    { id: 'e4', codigo: 'NOVA', dias_alerta: 2, alerta_dias_uteis: false, criado_em: dia(5), area: 'gestao', ativo: true, alerta_ativo: true },
  ];
  const abs = [{ equipamento_id: 'e1', data_hora: dia(7, 10), anulado: false }, { equipamento_id: 'e2', data_hora: dia(9, 10), anulado: false }, { equipamento_id: 'e3', data_hora: dia(6, 10), anulado: false }];  // 06/11 é sexta
  const dsl = (agora, ocs) => rodar({ equipamentos: eqs, abastecimentos: abs, ocorrencias: ocs || [] }, agora, 'return montarDiesel();');
  let r = await dsl(T(dia(9, 12)));             // segunda: PC01 parou há 2 dias (não passa de 2); NOVA (cadastro dia 5) = 4 dias
  assert.strictEqual(r.total, 1); assert.deepStrictEqual([...r.msgs.keys()].sort(), ['sup1', 'sup2']);
  assert.ok(r.msgs.get('sup1').texto.includes('NOVA (4 dias)') && !r.msgs.get('sup1').texto.includes('PC01'), r.msgs.get('sup1').texto);
  r = await dsl(T(dia(11, 12)));                // quarta: PC01 4 dias, NOVA 6, FDS 3 dias úteis; CAM01 2 (não)
  assert.strictEqual(r.total, 3);
  assert.strictEqual(r.msgs.get('sup1').texto, 'NOVA (6 dias), PC01 (4 dias), FDS (3 dias).');   // FDS conta só dias úteis
  // PC01 está em manutenção (ocorrência aberta): não é falta de abastecimento
  r = await dsl(T(dia(11, 12)), [{ equipamento_id: 'e1', liberada_em: null, anulado: false }]);
  assert.strictEqual(r.msgs.get('sup1').texto, 'NOVA (6 dias), FDS (3 dias).');
  // ocorrência já liberada não esconde nada
  r = await dsl(T(dia(11, 12)), [{ equipamento_id: 'e1', liberada_em: dia(10), anulado: false }]);
  assert.strictEqual(r.total, 3);

  // ---------- aviso de ocorrência ----------
  const agora = T(dia(10, 12));
  const base = () => ({
    ocorrencias: [
      { id: 'o1', area: 'gestao', equipamento_id: 'e1', equipamento_codigo: 'PC01', categoria: 'manutencao', motivo: 'Hidráulico', descricao: 'vazando óleo', aberta_em: dia(10, 11), criado_em: '2026-11-10T11:50:00-03:00', aberta_por: 'op1', aberta_por_nome: 'Maria', aviso_abertura_em: null, anulado: false },
      { id: 'o2', area: 'gestao', equipamento_id: 'e2', equipamento_codigo: 'CAM01', categoria: 'parada', motivo: 'Sem diesel', descricao: 'x', aberta_em: dia(10, 7), criado_em: dia(10, 7), aberta_por: 'op1', aberta_por_nome: 'Maria', aviso_abertura_em: dia(10, 7), anulado: false,
        liberada_em: dia(10, 11), liberada_registro_em: '2026-11-10T11:55:00-03:00', liberada_por: 'sup1', motivo_liberacao: 'Reparo concluído', servico_realizado: 'completou o diesel', recebido_por: 'João', aviso_liberacao_em: null },
    ],
    equipamentos: [{ id: 'e1', codigo: 'PC01', nome: 'Pá' }, { id: 'e2', codigo: 'CAM01', nome: 'Caminhão' }],
    profiles: [{ id: 'op1', ativo: true, area: 'gestao' }, { id: 'sup1', ativo: true, area: 'gestao' }, { id: 'fora', ativo: true, area: 'trefila' }, { id: 'bloq', ativo: false, area: 'gestao' }],
    usuario_areas: [],
  });
  const oc = (t, uid, id, ev) => rodar(t, agora, 'return montarOcorrencia(a, b, c);', uid, id, ev);

  // abertura: quem abriu avisa; recebem os supervisores (menos quem abriu); texto sai do banco
  let t = base(); r = await oc(t, 'op1', 'o1', 'abertura');
  assert.deepStrictEqual([...r.msgs.keys()].sort(), ['sup1', 'sup2']);
  assert.strictEqual(r.msgs.get('sup1').titulo, '🔧 PC01 em manutenção');
  assert.strictEqual(r.msgs.get('sup1').texto, 'Hidráulico: vazando óleo (aberto por Maria).');
  assert.ok(t.ocorrencias[0].aviso_abertura_em, 'reservou o aviso');
  r = await oc(t, 'op1', 'o1', 'abertura');                                      // segunda chamada: não repete
  assert.strictEqual(r.msgs.size, 0);
  // parada (não manutenção) tem outro título
  t = base(); t.ocorrencias[0].categoria = 'parada'; r = await oc(t, 'op1', 'o1', 'abertura');
  assert.strictEqual(r.msgs.get('sup1').titulo, '⏸ PC01 parado');
  // supervisor que abriu não recebe o próprio aviso
  t = base(); t.ocorrencias[0].aberta_por = 'sup1'; t.profiles.push(); r = await oc(t, 'sup1', 'o1', 'abertura');
  assert.deepStrictEqual([...r.msgs.keys()], ['sup2']);
  // travas da abertura
  t = base(); assert.strictEqual((await erro(oc(t, 'sup1', 'o1', 'abertura'))).status, 403);       // outro usuário tentando avisar
  assert.strictEqual((await erro(oc(t, 'fora', 'o1', 'abertura'))).status, 403);                    // de outra área
  assert.strictEqual((await erro(oc(t, 'bloq', 'o1', 'abertura'))).status, 403);                    // conta bloqueada
  assert.strictEqual((await erro(oc(t, 'op1', 'nao-existe', 'abertura'))).status, 404);
  assert.strictEqual((await erro(oc(t, 'op1', 'o1', 'qualquer'))).status, 400);
  t.ocorrencias[0].criado_em = dia(10, 9); assert.strictEqual((await erro(oc(t, 'op1', 'o1', 'abertura'))).status, 409);   // aberta há 3 h: tarde demais
  t = base(); t.ocorrencias[0].anulado = true; assert.strictEqual((await erro(oc(t, 'op1', 'o1', 'abertura'))).status, 404);
  assert.strictEqual(t.ocorrencias[0].aviso_abertura_em, null, 'falha não reserva o aviso');

  // liberação: avisa supervisores + quem abriu (menos quem liberou); texto com serviço, quem pegou e tempo
  t = base(); r = await oc(t, 'sup1', 'o2', 'liberacao');
  assert.deepStrictEqual([...r.msgs.keys()].sort(), ['op1', 'sup2']);
  assert.strictEqual(r.msgs.get('op1').titulo, '✅ CAM01 liberado');
  assert.strictEqual(r.msgs.get('op1').texto, 'Reparo concluído — completou o diesel. Pegou: João. Ficou parado 4 h.');
  r = await oc(t, 'sup1', 'o2', 'liberacao'); assert.strictEqual(r.msgs.size, 0);
  // travas da liberação
  t = base(); assert.strictEqual((await erro(oc(t, 'op1', 'o2', 'liberacao'))).status, 403);        // só quem liberou avisa
  assert.strictEqual((await erro(oc(t, 'sup1', 'o1', 'liberacao'))).status, 403);                   // o1 nem foi liberada
  t.ocorrencias[1].liberada_registro_em = dia(10, 8); assert.strictEqual((await erro(oc(t, 'sup1', 'o2', 'liberacao'))).status, 409);

  console.log('diesel_aviso: todos os testes passaram');
})().catch(e => { console.error(e.stack || e); process.exit(1); });
