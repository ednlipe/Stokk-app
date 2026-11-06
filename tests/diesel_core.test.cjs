// Testa as regras do Diesel (saldo do tanque, custo médio, consumo, alertas, resumo).
// Rodar:  node tests/diesel_core.test.cjs      (sem dependências; lê o código direto de src/App.jsx)
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'App.jsx'), 'utf8');
const ini = src.indexOf('/* ================= DIESEL — núcleo');
const fim = src.indexOf('/* ================= DIESEL — telas');
assert(ini > 0 && fim > ini, 'núcleo do diesel não encontrado em src/App.jsx');
const D = new Function(src.slice(ini, fim) + '; return { dslTanque, dslCustoParaAbastecer, dslUltimoAbastecimento, dslValidarMedidor, dslConsumo, dslAnomalia, dslDiasEntre, dslSemAbastecer, dslResumo, dslDiasRestantes, dslOcorrenciaAberta, dslOcorrenciaHoras, dslParadasResumo };')();
// o painel do desktop usa uma cópia idêntica do núcleo: se alguém mudar uma e esquecer a outra, o teste avisa
const desk = fs.readFileSync(path.join(__dirname, '..', 'public', 'desktop', 'index.html'), 'utf8');
const di = desk.indexOf('/* ================= DIESEL — núcleo'), df = desk.indexOf('/* ================= DIESEL — painel');
assert(di > 0 && df > di, 'núcleo do diesel não encontrado no desktop');
assert.strictEqual(desk.slice(di, df), src.slice(ini, fim), 'o núcleo do diesel do desktop está diferente do app');
const perto = (a, b, m) => assert.ok(Math.abs(a - b) < 1e-9, (m || '') + ' esperado ' + b + ' veio ' + a);
const dia = (d, h) => '2026-11-' + String(d).padStart(2, '0') + 'T' + String(h === undefined ? 12 : h).padStart(2, '0') + ':00:00-03:00';

// ---- saldo e custo médio ponderado
const ent = [
  { id: 'c1', tanqueId: 't1', dataHora: dia(1, 8), litros: 5000, precoLitro: 6.00, valorTotal: 30000 },
  { id: 'c2', tanqueId: 't1', dataHora: dia(10, 8), litros: 5000, precoLitro: 7.00, valorTotal: 35000 },
  { id: 'cx', tanqueId: 't1', dataHora: dia(11, 8), litros: 9999, precoLitro: 1, valorTotal: 9999, anulado: true },   // anulada: não conta
  { id: 'co', tanqueId: 't2', dataHora: dia(1, 8), litros: 100, precoLitro: 10, valorTotal: 1000 },                  // outro tanque
];
const ab = [
  { id: 'a1', tanqueId: 't1', equipamentoId: 'e1', dataHora: dia(5, 9), medidor: 100, litros: 1000, custoLitro: 6, custoTotal: 6000 },
  { id: 'a2', tanqueId: 't1', equipamentoId: 'e1', dataHora: dia(12, 9), medidor: 150, litros: 1000, custoLitro: 6.5, custoTotal: 6500 },
];
let t = D.dslTanque('t1', ent, ab, []);
perto(t.entradasL, 10000, 'entradas'); perto(t.saidasL, 2000, 'saídas'); perto(t.saldo, 8000, 'saldo');
// compra 1: 5000 a 6; saída 1000 → saldo 4000 @6; compra 2: (4000*6+5000*7)/9000 = 6,5555…
perto(D.dslTanque('t1', ent, ab, [], dia(9)).custoMedio, 6, 'custo antes da 2ª compra');
perto(D.dslTanque('t1', ent, ab, []).custoMedio, (4000 * 6 + 5000 * 7) / 9000, 'custo depois da 2ª compra');
perto(D.dslTanque('t1', ent, ab, [], dia(9)).saldo, 4000, 'saldo antes da 2ª compra');
assert.strictEqual(D.dslTanque('tZ', ent, ab, []).custoMedio, null);                         // tanque sem compra: sem custo
assert.strictEqual(D.dslTanque('tZ', ent, ab, []).saldo, 0);
// ajuste da régua: só conta quando ajustar = true
const med = [{ id: 'm1', tanqueId: 't1', dataHora: dia(13, 7), diferenca: -300, ajustar: true }, { id: 'm2', tanqueId: 't1', dataHora: dia(13, 8), diferenca: -999, ajustar: false }];
perto(D.dslTanque('t1', ent, ab, med).saldo, 7700, 'saldo com ajuste');
perto(D.dslTanque('t1', ent, ab, med).ajustesL, -300);
// saldo negativo (saída lançada antes da compra) conta como zero na média
const ent2 = [{ id: 'k', tanqueId: 'x', dataHora: dia(2), litros: 1000, precoLitro: 5, valorTotal: 5000 }];
const ab2 = [{ id: 's', tanqueId: 'x', equipamentoId: 'e', dataHora: dia(1), litros: 300, medidor: 1 }];
perto(D.dslTanque('x', ent2, ab2, []).custoMedio, 5, 'custo com saldo negativo'); perto(D.dslTanque('x', ent2, ab2, []).saldo, 700);
assert.strictEqual(D.dslCustoParaAbastecer('t1', ent, ab, []).toFixed(4), ((4000 * 6 + 5000 * 7) / 9000).toFixed(4));

// ---- medidor: não pode diminuir; troca de medidor libera; avisos
const eqH = { id: 'e1', medidor: 'h' }, eqK = { id: 'e2', medidor: 'km' };
assert.ok(D.dslValidarMedidor(eqH, { medidor: 100 }, 90, false).erro);
assert.deepStrictEqual(D.dslValidarMedidor(eqH, { medidor: 100 }, 90, true), {});
assert.ok(D.dslValidarMedidor(eqH, { medidor: 100 }, 100, false).aviso);
assert.ok(D.dslValidarMedidor(eqH, { medidor: 100 }, 900, false).aviso);          // andou 800 h: provável erro de digitação
assert.deepStrictEqual(D.dslValidarMedidor(eqH, { medidor: 100 }, 108, false), {});
assert.deepStrictEqual(D.dslValidarMedidor(eqH, null, 5, false), {});            // 1º abastecimento
assert.ok(D.dslValidarMedidor(eqH, null, '', false).erro);
assert.ok(D.dslValidarMedidor(eqK, { medidor: 1000 }, 500, false).erro.includes('km'));
assert.strictEqual(D.dslUltimoAbastecimento('e1', ab).id, 'a2');

// ---- consumo (máquina em L/h; caminhão em km/L)
const abE = [
  { id: '1', equipamentoId: 'e1', dataHora: dia(1), medidor: 100, litros: 80 },
  { id: '2', equipamentoId: 'e1', dataHora: dia(3), medidor: 110, litros: 50 },    // 10 h, 50 L → 5 L/h
  { id: '3', equipamentoId: 'e1', dataHora: dia(5), medidor: 130, litros: 80 },    // 20 h, 80 L → 4 L/h
  { id: '4', equipamentoId: 'e1', dataHora: dia(6), medidor: 5, litros: 10, trocaMedidor: true },   // troca: ignora
  { id: '5', equipamentoId: 'e1', dataHora: dia(8), medidor: 25, litros: 60 },     // 20 h, 60 L → 3 L/h
  { id: 'x', equipamentoId: 'e1', dataHora: dia(9), medidor: 999, litros: 999, anulado: true },
];
let c = D.dslConsumo(eqH, abE);
assert.strictEqual(c.unidade, 'L/h'); assert.strictEqual(c.intervalos.length, 3);
perto(c.media, (50 + 80 + 60) / (10 + 20 + 20), 'média ponderada L/h');   // soma litros ÷ soma horas, não média de médias
const abK = [{ id: '1', equipamentoId: 'e2', dataHora: dia(1), medidor: 1000, litros: 100 }, { id: '2', equipamentoId: 'e2', dataHora: dia(4), medidor: 1300, litros: 100 }, { id: '3', equipamentoId: 'e2', dataHora: dia(8), medidor: 1500, litros: 50 }];
c = D.dslConsumo(eqK, abK);
assert.strictEqual(c.unidade, 'km/L'); perto(c.media, 500 / 150, 'média km/L');
assert.strictEqual(D.dslConsumo(eqH, [abE[0]]).media, null);                      // 1 abastecimento só: sem consumo
// anomalia: último intervalo 50% pior que a média anterior
const mk = (n, d, l) => ({ id: 'z' + n, equipamentoId: 'e1', dataHora: dia(n), medidor: d, litros: l });
let seq = [mk(1, 0, 10), mk(2, 10, 50), mk(3, 20, 50), mk(4, 30, 50), mk(5, 40, 50)];
assert.strictEqual(D.dslAnomalia(D.dslConsumo(eqH, seq)), null);                  // 5 L/h em todos
seq.push(mk(6, 50, 100));                                                          // 10 L/h: o dobro
assert.ok(D.dslAnomalia(D.dslConsumo(eqH, seq)));
assert.strictEqual(D.dslAnomalia(D.dslConsumo(eqH, seq.slice(0, 3))), null);       // poucos dados: não avisa

// ---- dias parados (datas de Brasília) e alerta
const T = s => new Date(s).getTime();
assert.strictEqual(D.dslDiasEntre(T(dia(1, 8)), T(dia(1, 22))), 0);
assert.strictEqual(D.dslDiasEntre(T(dia(1, 23)), T(dia(3, 1))), 2);
assert.strictEqual(D.dslDiasEntre(T('2026-11-02T23:30:00-03:00'), T('2026-11-03T00:30:00-03:00')), 1);   // virou o dia em Brasília
// 2026-11-06 é sexta; 09 é segunda
assert.strictEqual(D.dslDiasEntre(T(dia(6)), T(dia(9)), false), 3);
assert.strictEqual(D.dslDiasEntre(T(dia(6)), T(dia(9)), true), 1);               // fim de semana não conta
const eqs = [
  { id: 'e1', codigo: 'PC01', ativo: true, alertaAtivo: true, diasAlerta: 2, criadoEm: dia(1) },
  { id: 'e2', codigo: 'CAM01', ativo: true, alertaAtivo: true, diasAlerta: 2, criadoEm: dia(1) },
  { id: 'e3', codigo: 'PARADA', ativo: true, alertaAtivo: false, diasAlerta: 2, criadoEm: dia(1) },
  { id: 'e4', codigo: 'INATIVA', ativo: false, alertaAtivo: true, diasAlerta: 2, criadoEm: dia(1) },
  { id: 'e5', codigo: 'NOVA', ativo: true, alertaAtivo: true, diasAlerta: 2, criadoEm: dia(9) },
  { id: 'e6', codigo: 'FDS', ativo: true, alertaAtivo: true, diasAlerta: 2, alertaDiasUteis: true, criadoEm: dia(1) },
];
const abs = [
  { id: 'a', equipamentoId: 'e1', dataHora: dia(7, 10) },                // 7/11
  { id: 'b', equipamentoId: 'e2', dataHora: dia(9, 10) },                // hoje
  { id: 'c', equipamentoId: 'e6', dataHora: dia(6, 10) },                // sexta
  { id: 'd', equipamentoId: 'e1', dataHora: dia(9, 11), anulado: true },  // anulada não "salva" o equipamento
];
const nomes = x => x.map(y => y.equipamento.codigo);
// dia 9 (segunda), meio-dia: PC01 parou no dia 7 = 2 dias (não passa de 2); nenhum alerta
assert.deepStrictEqual(nomes(D.dslSemAbastecer(eqs, abs, T(dia(9, 12)))), []);
// dia 10: PC01 = 3 dias → alerta; CAM01 = 1; PARADA/INATIVA nunca; NOVA conta do cadastro (dia 9 = 1); FDS (só dias úteis) sexta→terça = 2
let al = D.dslSemAbastecer(eqs, abs, T(dia(10, 12)));
assert.deepStrictEqual(nomes(al), ['PC01']); assert.strictEqual(al[0].dias, 3); assert.strictEqual(al[0].prazo, 2);
// dia 11: PC01 4, CAM01 2 (não), FDS 3 dias úteis (seg, ter, qua) → alerta; ordenado do mais parado
al = D.dslSemAbastecer(eqs, abs, T(dia(11, 12)));
assert.deepStrictEqual(nomes(al), ['PC01', 'FDS']);
// equipamento que nunca abasteceu conta a partir do cadastro: NOVA (criada dia 9) no dia 12 = 3 dias
assert.ok(nomes(D.dslSemAbastecer(eqs, abs, T(dia(12, 12)))).includes('NOVA'));
// prazo próprio do equipamento
assert.deepStrictEqual(nomes(D.dslSemAbastecer([{ id: 'e1', codigo: 'X', ativo: true, diasAlerta: 5, criadoEm: dia(1) }], abs, T(dia(11, 12)))), []);
assert.deepStrictEqual(nomes(D.dslSemAbastecer([{ id: 'e1', codigo: 'X', ativo: true, diasAlerta: 5, criadoEm: dia(1) }], abs, T(dia(13, 12)))), ['X']);

// ---- resumo do período
const eqAll = [{ id: 'e1', medidor: 'h' }, { id: 'e2', medidor: 'km' }];
const abR = [
  { id: '1', equipamentoId: 'e1', tanqueId: 't1', dataHora: dia(2), litros: 100, custoLitro: 6, custoTotal: 600 },
  { id: '2', equipamentoId: 'e1', tanqueId: 't1', dataHora: dia(3), litros: 50, custoLitro: null, custoTotal: null },     // sem compra registrada
  { id: '3', equipamentoId: 'e2', tanqueId: 't1', dataHora: dia(4), litros: 150, custoLitro: 8, custoTotal: 1200 },
  { id: '4', equipamentoId: 'e2', tanqueId: 't1', dataHora: dia(20), litros: 999, custoLitro: 8, custoTotal: 7992 },       // fora do período
  { id: '5', equipamentoId: 'e2', tanqueId: 't1', dataHora: dia(5), litros: 999, custoLitro: 8, custoTotal: 7992, anulado: true },
];
const res = D.dslResumo(eqAll, abR, ent, T(dia(1, 0)), T(dia(10, 0)));
assert.strictEqual(res.abastecimentos, 3); perto(res.litros, 300); perto(res.litrosPorAbastecimento, 100);
perto(res.gasto, 1800); perto(res.custoMedioLitro, 1800 / 250); perto(res.semCusto, 50);
// compras de todos os tanques no período: c1 (5000 L a 6) + co (100 L a 10); a c2 é do dia 10 (fora) e a cx está anulada
assert.strictEqual(res.compras, 2); perto(res.compradoL, 5100); perto(res.compradoValor, 31000); perto(res.precoMedioCompra, 31000 / 5100);
perto(res.porEquip.e1.litros, 150); perto(res.porEquip.e2.gasto, 1200);
assert.strictEqual(D.dslResumo(eqAll, abR, ent, T(dia(1, 0)), T(dia(10, 0)), 'e1').abastecimentos, 2);

// ---- dias restantes do tanque (consumo dos últimos 14 dias)
const abD = [{ tanqueId: 't1', dataHora: dia(8), litros: 700 }, { tanqueId: 't1', dataHora: dia(1), litros: 700 }];   // 1400 L em 14 dias = 100 L/dia
perto(D.dslDiasRestantes(2000, 't1', abD, T(dia(10, 12)), 14), 20, 'dias restantes');
assert.strictEqual(D.dslDiasRestantes(2000, 't1', [], T(dia(10, 12)), 14), null);

// ---- paradas e manutenção (ocorrências)
const oc = [
  { id: 'o1', equipamentoId: 'e1', motivo: 'Quebra / defeito', abertaEm: dia(3, 8), liberadaEm: dia(3, 14) },          // 6 h, liberada
  { id: 'o2', equipamentoId: 'e1', motivo: 'Hidráulico', abertaEm: dia(5, 8), liberadaEm: dia(6, 8) },                  // 24 h, liberada
  { id: 'o3', equipamentoId: 'e2', motivo: 'Quebra / defeito', abertaEm: dia(9, 12) },                                  // aberta
  { id: 'o4', equipamentoId: 'e2', motivo: 'Sem diesel', abertaEm: dia(4, 8), liberadaEm: dia(4, 10), anulado: true },    // anulada: não conta
  { id: 'o5', equipamentoId: 'e1', motivo: 'Quebra / defeito', abertaEm: dia(20, 8), liberadaEm: dia(20, 9) },           // fora do período
];
assert.strictEqual(D.dslOcorrenciaAberta('e2', oc).id, 'o3');
assert.strictEqual(D.dslOcorrenciaAberta('e1', oc), null);                         // e1 só tem liberadas
assert.strictEqual(D.dslOcorrenciaAberta('e2', [{ id: 'x', equipamentoId: 'e2', abertaEm: dia(1), anulado: true }]), null);   // anulada não está "em aberto"
perto(D.dslOcorrenciaHoras(oc[0]), 6, 'horas liberada'); perto(D.dslOcorrenciaHoras(oc[2], T(dia(10, 0))), 12, 'horas da aberta até agora');
perto(D.dslOcorrenciaHoras({ abertaEm: dia(5, 8), liberadaEm: dia(5, 7) }), 0, 'nunca negativa');
const pr = D.dslParadasResumo(oc, T(dia(1, 0)), T(dia(10, 0)), T(dia(10, 0)));
assert.strictEqual(pr.total, 3); assert.strictEqual(pr.abertas, 1); assert.strictEqual(pr.liberadas, 2);
perto(pr.horas, 6 + 24 + 12, 'horas totais'); perto(pr.tempoMedioH, 15, 'tempo médio só das liberadas');
assert.strictEqual(pr.porMotivo['Quebra / defeito'].n, 2); perto(pr.porMotivo['Quebra / defeito'].horas, 18); perto(pr.porEquip.e1.horas, 30);
assert.strictEqual(D.dslParadasResumo(oc, T(dia(1, 0)), T(dia(10, 0)), T(dia(10, 0)), 'e2').total, 1);
assert.strictEqual(D.dslParadasResumo([], 0, 1).tempoMedioH, null);
// equipamento com ocorrência em aberto não gera aviso de "sem abastecer"
assert.deepStrictEqual(nomes(D.dslSemAbastecer(eqs, abs, T(dia(12, 12)), [{ id: 'o9', equipamentoId: 'e1', abertaEm: dia(8) }])).includes('PC01'), false);
assert.ok(nomes(D.dslSemAbastecer(eqs, abs, T(dia(12, 12)), [])).includes('PC01'));

console.log('diesel_core: todos os testes passaram');
