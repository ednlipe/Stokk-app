// Testa o núcleo de turnos e linha do tempo dos locais (src/App.jsx, bloco LOC-CORE).
// Rodar:  TZ=America/Sao_Paulo node tests/locais_core.test.cjs
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'App.jsx'), 'utf8');
const ini = src.indexOf('// ---- LOC-CORE-INICIO'), fim = src.indexOf('// ---- LOC-CORE-FIM');
assert(ini > 0 && fim > ini);
const C = new Function(src.slice(ini, fim) + '; return { locTurnoJanela, locTurnosRecentes, locSegmentos, locAoVivo, locLinhaTurno, locTemRegistro, locPorSetor, locTurnosDoDia };')();
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

// ---- segmentos
const R = (id, eq, de, dataFim, extra) => Object.assign({ id, equipamentoId: eq, local: id, dataHora: iso(de), dataFim: dataFim ? iso(dataFim) : null, timestamp: iso(de) }, extra || {});
const locs = [
  R('A', 'pc', L(2026,11,10,6,0)),                         // começou antes do turno 1, sem fim
  R('B', 'pc', L(2026,11,10,9,30)),                        // fecha A às 09:30
  R('C', 'pc', L(2026,11,10,12,0), L(2026,11,10,13,0)),    // fecha B às 12:00; termina 13:00 -> vazio depois
  R('X', 'pc', L(2026,11,10,9,0), null, { anulado: true }), // anulado não conta
  R('E', 'emp', L(2026,11,10,8,0)),
];
const seg = C.locSegmentos(locs, 'pc');
assert.deepStrictEqual(seg.map(s => s.reg.id), ['A', 'B', 'C']);
assert.strictEqual(seg[0].fim, L(2026,11,10,9,30), 'o fim de A é o início de B');
assert.strictEqual(seg[1].fim, L(2026,11,10,12,0));
assert.strictEqual(seg[2].fim, L(2026,11,10,13,0));

// ---- linha do turno 1 (já terminou), depois do fim de C
const agora = L(2026,11,10,16,0);
let t = C.locLinhaTurno(locs, 'pc', L(2026,11,10,7,10), L(2026,11,10,15,10), agora);
assert.deepStrictEqual(t.map(x => x.vazio ? 'vazio' : x.reg.id), ['A', 'B', 'C', 'vazio']);
assert.strictEqual(t[0].de, L(2026,11,10,7,10), 'A é cortado no início do turno'); assert.strictEqual(t[0].antes, true);
assert.strictEqual(t[0].ate, L(2026,11,10,9,30));
assert.strictEqual(t[3].de, L(2026,11,10,13,0)); assert.strictEqual(t[3].ate, L(2026,11,10,15,10));
assert.ok(C.locTemRegistro(t));
// equipamento sem nada
t = C.locLinhaTurno(locs, 'nenhum', L(2026,11,10,7,10), L(2026,11,10,15,10), agora);
assert.deepStrictEqual(t.map(x => !!x.vazio), [true]); assert.ok(!C.locTemRegistro(t));
// E ficou aberto: continua depois do turno 1, e no turno 2 "já estava"
t = C.locLinhaTurno(locs, 'emp', L(2026,11,10,7,10), L(2026,11,10,15,10), agora);
assert.deepStrictEqual(t.map(x => x.vazio ? 'vazio' : x.reg.id), ['vazio', 'E']);
assert.strictEqual(t[1].depois, true); assert.strictEqual(t[1].emAndamento, false);
t = C.locLinhaTurno(locs, 'emp', L(2026,11,10,15,10), L(2026,11,10,23,10), agora);
assert.strictEqual(t.length, 1); assert.strictEqual(t[0].antes, true); assert.strictEqual(t[0].emAndamento, true);
assert.strictEqual(t[0].ate, agora, 'turno em andamento é cortado em "agora"');
// turno que cruza a meia-noite
const cruz = [R('N1', 'pc', L(2026,11,10,23,30)), R('N2', 'pc', L(2026,11,11,1,0))];
t = C.locLinhaTurno(cruz, 'pc', L(2026,11,10,23,10), L(2026,11,11,7,10), L(2026,11,11,8,0));
assert.deepStrictEqual(t.map(x => x.vazio ? 'vazio' : x.reg.id), ['vazio', 'N1', 'N2']);
assert.strictEqual(t[2].ate, L(2026,11,11,7,10)); assert.strictEqual(t[2].depois, true);
// anular um registro reabre o anterior
const anul = locs.map(l => l.id === 'B' ? Object.assign({}, l, { anulado: true }) : l);
assert.strictEqual(C.locSegmentos(anul, 'pc')[0].fim, L(2026,11,10,12,0), 'sem B, A vai até o início de C');

// ---- ao vivo
let v = C.locAoVivo(locs, 'emp', agora); assert.strictEqual(v.vivo, true); assert.strictEqual(v.reg.id, 'E');
v = C.locAoVivo(locs, 'pc', agora); assert.strictEqual(v.vivo, false, 'C terminou às 13:00'); assert.strictEqual(v.reg.id, 'C');
v = C.locAoVivo(locs, 'pc', L(2026,11,10,12,30)); assert.strictEqual(v.vivo, true);
v = C.locAoVivo(locs, 'nada', agora); assert.strictEqual(v.reg, null); assert.strictEqual(v.vivo, false);
// mesmo início: vale o lançado depois
const emp = [R('P', 'q', L(2026,11,10,9,0)), Object.assign(R('Q', 'q', L(2026,11,10,9,0)), { timestamp: iso(L(2026,11,10,9,1)) })];
assert.strictEqual(C.locAoVivo(emp, 'q', agora).reg.id, 'Q');

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
console.log('locais_core: todos os testes passaram');
