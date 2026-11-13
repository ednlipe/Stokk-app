// Testa o núcleo de turnos e linha do tempo dos locais (src/App.jsx, bloco LOC-CORE).
// Rodar:  TZ=America/Sao_Paulo node tests/locais_core.test.cjs
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'App.jsx'), 'utf8');
const ini = src.indexOf('// ---- LOC-CORE-INICIO'), fim = src.indexOf('// ---- LOC-CORE-FIM');
assert(ini > 0 && fim > ini);
const C = new Function(src.slice(ini, fim) + '; return { locTurnoJanela, locTurnosRecentes, locSegmentos, locAoVivo, locLinhaTurno, locTemRegistro, locPorSetor, locTurnosDoDia, locTexto, LOC_LOCAIS, LOC_PARADA, locEhParada, locSituacao, locCortes, locLinhasPlanilha };')();
const L = (y, m, d, h, mi) => new Date(y, m - 1, d, h, mi).getTime();
const iso = ms => new Date(ms).toISOString();

// ---- janelas de turno
let j = C.locTurnoJanela(L(2026,11,10,10,46));
assert.strictEqual(j.turno, 1); assert.strictEqual(j.ini, L(2026,11,10,7,10)); assert.strictEqual(j.fim, L(2026,11,10,15,10));
j = C.locTurnoJanela(L(2026,11,10,15,10)); assert.strictEqual(j.turno, 2, '15:10 já é 2º turno');
j = C.locTurnoJanela(L(2026,11,10,15,9)); assert.strictEqual(j.turno, 1);
j = C.locTurnoJanela(L(2026,11,10,23,10)); assert.strictEqual(j.turno, 3); assert.strictEqual(j.fim, L(2026,11,11,7,10));
j = C.locTurnoJanela(L(2026,11,11,2,0)); assert.strictEqual(j.turno, 3, '02:00 é 3º turno do dia anterior');
assert.strictEqual(j.ini, L(2026,11,10,23,10)); assert.strictEqual(j.fim, L(2026,11,11,7,10));
j = C.locTurnoJanela(L(2026,11,11,7,9)); assert.strictEqual(j.turno, 3); j = C.locTurnoJanela(L(2026,11,11,7,10)); assert.strictEqual(j.turno, 1);
j = C.locTurnoJanela(L(2026,12,31,23,30)); assert.strictEqual(j.fim, L(2027,1,1,7,10), 'vira o ano');
const rec = C.locTurnosRecentes(L(2026,11,10,10,46), 4);
assert.deepStrictEqual(rec.map(x => x.turno), [1, 3, 2, 1]);
assert.strictEqual(rec[1].ini, L(2026,11,9,23,10)); assert.strictEqual(rec[0].ini, rec[1].fim, 'turnos seguidos, sem buraco');

// ---- segmentos (sem fim informado, o registro termina sozinho na troca de turno)
const R = (id, eq, de, dataFim, extra) => Object.assign({ id, equipamentoId: eq, local: id, dataHora: iso(de), dataFim: dataFim ? iso(dataFim) : null, timestamp: iso(de) }, extra || {});
const locs = [
  R('A', 'pc', L(2026,11,10,6,0)),                         // 3º turno, sem fim: termina às 07:10
  R('B', 'pc', L(2026,11,10,9,30)),                        // 1º turno, sem fim, mas C começa 12:00
  R('C', 'pc', L(2026,11,10,12,0), L(2026,11,10,13,0)),    // fim informado: 13:00
  R('X', 'pc', L(2026,11,10,9,0), null, { anulado: true }), // anulado não conta
  R('E', 'emp', L(2026,11,10,8,0)),                        // sem fim: termina às 15:10
  R('F', 'emp', L(2026,11,10,14,0), L(2026,11,10,16,0)),   // fim informado ATRAVESSA a troca de turno e é respeitado
];
const seg = C.locSegmentos(locs, 'pc');
assert.deepStrictEqual(seg.map(s => s.reg.id), ['A', 'B', 'C']);
assert.strictEqual(seg[0].fim, L(2026,11,10,7,10), 'A sem fim termina no corte do 3º turno (07:10), não vai até B');
assert.strictEqual(seg[0].auto, true); assert.strictEqual(seg[2].auto, false);
assert.strictEqual(seg[1].fim, L(2026,11,10,12,0), 'o próximo registro (C) corta B');
assert.strictEqual(seg[2].fim, L(2026,11,10,13,0));
const sEmp = C.locSegmentos(locs, 'emp');
assert.strictEqual(sEmp[0].fim, L(2026,11,10,14,0), 'F começa 14:00 e corta E');
assert.strictEqual(sEmp[1].fim, L(2026,11,10,16,0), 'fim informado depois da troca de turno é respeitado');
assert.strictEqual(C.locSegmentos([R('S','pc',L(2026,11,10,15,10))], 'pc')[0].fim, L(2026,11,10,23,10), 'começou no corte: pertence ao turno novo');

// ---- linha do turno 1 (já terminou)
const agora = L(2026,11,10,16,0);
let t = C.locLinhaTurno(locs, 'pc', L(2026,11,10,7,10), L(2026,11,10,15,10), agora);
assert.deepStrictEqual(t.map(x => x.vazio ? 'vazio' : x.reg.id), ['vazio', 'B', 'C', 'vazio'], 'A (do 3º turno) não entra; 07:10–09:30 sem registro');
assert.strictEqual(t[0].de, L(2026,11,10,7,10)); assert.strictEqual(t[0].ate, L(2026,11,10,9,30));
assert.strictEqual(t[1].de, L(2026,11,10,9,30)); assert.strictEqual(t[1].ate, L(2026,11,10,12,0));
assert.strictEqual(t[3].de, L(2026,11,10,13,0)); assert.strictEqual(t[3].ate, L(2026,11,10,15,10));
assert.ok(C.locTemRegistro(t));
t = C.locLinhaTurno(locs, 'nenhum', L(2026,11,10,7,10), L(2026,11,10,15,10), agora);
assert.deepStrictEqual(t.map(x => !!x.vazio), [true]); assert.ok(!C.locTemRegistro(t));
// E: 08:00 até 15:10 (corte); F: 14:00–16:00 atravessa para o turno 2
t = C.locLinhaTurno(locs, 'emp', L(2026,11,10,7,10), L(2026,11,10,15,10), agora);
assert.deepStrictEqual(t.map(x => x.vazio ? 'vazio' : x.reg.id), ['vazio', 'E', 'F']);
assert.strictEqual(t[2].depois, true, 'F continua depois do fim do turno 1');
t = C.locLinhaTurno(locs, 'emp', L(2026,11,10,15,10), L(2026,11,10,23,10), agora);
assert.deepStrictEqual(t.map(x => x.vazio ? 'vazio' : x.reg.id), ['F']); assert.strictEqual(t[0].antes, true); assert.strictEqual(t[0].ate, L(2026,11,10,16,0));
// turno em andamento é cortado em "agora"
t = C.locLinhaTurno([R('G','pc',L(2026,11,10,15,30))], 'pc', L(2026,11,10,15,10), L(2026,11,10,23,10), agora);
assert.deepStrictEqual(t.map(x => x.vazio ? 'vazio' : x.reg.id), ['vazio', 'G']); assert.strictEqual(t[1].emAndamento, true); assert.strictEqual(t[1].ate, agora);
// turno que cruza a meia-noite: N1 vai até N2; N2 termina no corte das 07:10
const cruz = [R('N1', 'pc', L(2026,11,10,23,30)), R('N2', 'pc', L(2026,11,11,1,0))];
t = C.locLinhaTurno(cruz, 'pc', L(2026,11,10,23,10), L(2026,11,11,7,10), L(2026,11,11,8,0));
assert.deepStrictEqual(t.map(x => x.vazio ? 'vazio' : x.reg.id), ['vazio', 'N1', 'N2']);
assert.strictEqual(t[2].ate, L(2026,11,11,7,10)); assert.strictEqual(t[2].depois, false);
// anular um registro reabre o anterior (A sem fim continua terminando no corte; C não é afetado)
const anul = locs.map(l => l.id === 'B' ? Object.assign({}, l, { anulado: true }) : l);
assert.deepStrictEqual(C.locSegmentos(anul, 'pc').map(s => s.reg.id), ['A', 'C']);
// lançar várias vezes, fora de ordem, no fim do turno: ordena pelo início
const fora = [R('Z2', 'pc', L(2026,11,10,11,0), L(2026,11,10,13,0)), R('Z1', 'pc', L(2026,11,10,8,0), L(2026,11,10,11,0)), R('Z3', 'pc', L(2026,11,10,13,0), L(2026,11,10,15,10))];
t = C.locLinhaTurno(fora, 'pc', L(2026,11,10,7,10), L(2026,11,10,15,10), agora);
assert.deepStrictEqual(t.map(x => x.vazio ? 'vazio' : x.reg.id), ['vazio', 'Z1', 'Z2', 'Z3']);

// ---- ao vivo
let v = C.locAoVivo(locs, 'emp', L(2026,11,10,10,0)); assert.strictEqual(v.vivo, true); assert.strictEqual(v.reg.id, 'E');
v = C.locAoVivo(locs, 'pc', L(2026,11,10,10,0)); assert.strictEqual(v.vivo, true, 'B em andamento no 1º turno'); assert.strictEqual(v.reg.id, 'B');
v = C.locAoVivo([R('E2','emp',L(2026,11,10,8,0))], 'emp', L(2026,11,10,15,10)); assert.strictEqual(v.vivo, false, 'na troca de turno o ao vivo para'); assert.strictEqual(v.auto, true); assert.strictEqual(v.reg.id, 'E2');
v = C.locAoVivo([R('E2','emp',L(2026,11,10,8,0))], 'emp', L(2026,11,10,15,9)); assert.strictEqual(v.vivo, true, 'um minuto antes ainda está ao vivo');
v = C.locAoVivo(locs, 'pc', agora); assert.strictEqual(v.vivo, false, 'C terminou às 13:00'); assert.strictEqual(v.auto, false); assert.strictEqual(v.reg.id, 'C');
v = C.locAoVivo(locs, 'pc', L(2026,11,10,12,30)); assert.strictEqual(v.vivo, true);
v = C.locAoVivo(locs, 'emp', L(2026,11,10,15,30)); assert.strictEqual(v.vivo, true, 'F com fim informado às 16:00 continua vivo no turno 2');
v = C.locAoVivo(locs, 'nada', agora); assert.strictEqual(v.reg, null); assert.strictEqual(v.vivo, false);
// mesmo início: vale o lançado depois
const emp = [R('P', 'q', L(2026,11,10,9,0)), Object.assign(R('Q', 'q', L(2026,11,10,9,0)), { timestamp: iso(L(2026,11,10,9,1)) })];
assert.strictEqual(C.locAoVivo(emp, 'q', L(2026,11,10,10,0)).reg.id, 'Q');
// "Continuar": quem voltar a lançar no turno novo, com o início na hora certa, volta a ficar ao vivo
const cont = [R('K1','pc',L(2026,11,10,8,0)), R('K2','pc',L(2026,11,10,15,40))];
v = C.locAoVivo(cont, 'pc', L(2026,11,10,16,0)); assert.strictEqual(v.vivo, true); assert.strictEqual(v.reg.id, 'K2');
t = C.locLinhaTurno(cont, 'pc', L(2026,11,10,15,10), L(2026,11,10,23,10), L(2026,11,10,16,0));
assert.deepStrictEqual(t.map(x => x.vazio ? 'vazio' : x.reg.id), ['vazio', 'K2'], '15:10–15:40 sem registro até alguém lançar');

// ---- setores
const eqs = [{ id: 1, codigo: 'EMP02', setor: 'Expedição' }, { id: 2, codigo: 'PC01', setor: 'Pátio de Tarugo' }, { id: 3, codigo: 'EMP01', setor: 'Expedição' },
             { id: 4, codigo: 'CAM01', setor: 'Pátio de Tarugo' }, { id: 5, codigo: 'X', setor: null }, { id: 6, codigo: 'OFF', setor: 'Pátio de Tarugo', ativo: false }, { id: 7, codigo: 'Z', setor: 'Oficina' }];
const g = C.locPorSetor(eqs);
assert.deepStrictEqual(g.map(x => x.setor), ['Pátio de Tarugo', 'Expedição', 'Oficina', 'Sem setor']);
assert.deepStrictEqual(g[0].equips.map(e => e.codigo), ['CAM01', 'PC01']); assert.deepStrictEqual(g[1].equips.map(e => e.codigo), ['EMP01', 'EMP02']);
// ---- turnos de um dia
let dd = C.locTurnosDoDia(L(2026,11,10,12,0), L(2026,11,10,16,0));
assert.deepStrictEqual(dd.map(x=>x.turno), [1,2], 'hoje: só os que já começaram');
dd = C.locTurnosDoDia(L(2026,11,9,12,0), L(2026,11,10,16,0));
assert.deepStrictEqual(dd.map(x=>x.turno), [1,2,3], 'ontem: os três');
assert.strictEqual(dd[2].ini, L(2026,11,9,23,10)); assert.strictEqual(dd[2].fim, L(2026,11,10,7,10), '3º de ontem termina hoje de manhã');
assert.deepStrictEqual(C.locTurnosDoDia(L(2026,11,11,12,0), L(2026,11,10,16,0)), [], 'futuro: nenhum');
// ---- o desktop usa a MESMA cópia do núcleo
const desk = fs.readFileSync(path.join(__dirname, '..', 'public', 'desktop', 'index.html'), 'utf8');
const di = desk.indexOf('// ---- LOC-CORE-INICIO'), df = desk.indexOf('// ---- LOC-CORE-FIM');
assert(di > 0 && df > di, 'núcleo no desktop');
assert.strictEqual(desk.slice(di, df), src.slice(ini, fim), 'LOC-CORE do desktop difere do app');
// ---- local fixo + atividade
assert.deepStrictEqual(C.LOC_LOCAIS, ['Planta 1','Planta 2','Trefila']);
assert.strictEqual(C.locTexto({ local:'Planta 1', atividade:'carregando tarugo' }), 'Planta 1 · carregando tarugo');
assert.strictEqual(C.locTexto({ local:'Pátio 2' }), 'Pátio 2', 'registro antigo, sem atividade');
assert.strictEqual(C.locTexto(null), '');
// ---- cortes no formato da planilha (meia-noite + turnos)
const cz = C.locCortes(L(2026,10,10,21,50), L(2026,10,11,8,0)).map(([a,b]) => [new Date(a).toTimeString().slice(0,5), new Date(b).toTimeString().slice(0,5)]);
assert.deepStrictEqual(cz, [['21:50','23:10'],['23:10','00:00'],['00:00','07:10'],['07:10','08:00']], JSON.stringify(cz));
assert.deepStrictEqual(C.locCortes(L(2026,10,10,8,0), L(2026,10,10,9,0)).length, 1, 'dentro de um turno: uma linha');
assert.strictEqual(C.locCortes(L(2026,10,10,7,10), L(2026,10,10,7,10)).length, 0, 'período vazio');
const ag2 = L(2026,10,12,12,0);
const plan = C.locLinhasPlanilha([R('P1','pc',L(2026,10,10,21,50),L(2026,10,11,8,0)), R('P2','pc',L(2026,10,11,10,0)), R('P3','pc',L(2026,10,12,11,0))], 'pc', L(2026,10,1,0,0), L(2026,11,1,0,0), ag2);
assert.strictEqual(plan.filter(x => x.reg.id === 'P1').length, 4);
assert.strictEqual(plan.filter(x => x.reg.id === 'P2').length, 1, 'P2 sem fim: só até 15:10 do mesmo dia');
assert.strictEqual(plan.filter(x => x.reg.id === 'P2')[0].ate, L(2026,10,11,15,10));
const ult = plan[plan.length-1]; assert.strictEqual(ult.reg.id, 'P3'); assert.strictEqual(ult.aberto, true, 'em andamento: término em branco'); assert.strictEqual(ult.ate, ag2);
assert.strictEqual(plan.filter(x => x.aberto).length, 1);
// recorte pelo período pedido
const plan2 = C.locLinhasPlanilha([R('Q','pc',L(2026,10,10,6,0),L(2026,10,10,20,0))], 'pc', L(2026,10,10,12,0), L(2026,10,10,14,0), ag2);
assert.strictEqual(plan2.length, 1); assert.strictEqual(plan2[0].de, L(2026,10,10,12,0)); assert.strictEqual(plan2[0].ate, L(2026,10,10,14,0));
// ---- máquina parada + situação (manutenção vence)
const vv = C.locAoVivo([R('M1','pc',L(2026,11,10,9,0),null,{ local: C.LOC_PARADA })], 'pc', L(2026,11,10,10,0));
assert.strictEqual(C.locEhParada(vv.reg), true); assert.strictEqual(C.locSituacao(vv, null), 'parada');
assert.strictEqual(C.locSituacao(vv, { categoria:'manutencao' }), 'manut', 'ocorrência aberta vence');
assert.strictEqual(C.locSituacao(vv, { categoria:'parada' }), 'parado');
assert.strictEqual(C.locSituacao(C.locAoVivo(locs,'emp',L(2026,11,10,10,0)), null), 'vivo');
assert.strictEqual(C.locSituacao(C.locAoVivo(locs,'pc',agora), null), 'sem');
assert.strictEqual(C.locSituacao(C.locAoVivo([], 'x', agora), null), 'nada');
assert.strictEqual(C.locTexto(vv.reg), 'Máquina parada');
console.log('locais_core: todos os testes passaram');
