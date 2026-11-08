// Testa as regras do 5S (Gestão Planta 1): abertos, horas, resumo do período, setores e pessoas.
// Rodar:  node tests/cinco_s_core.test.cjs      (sem dependências; lê o código direto de src/App.jsx)
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'App.jsx'), 'utf8');
const ini = src.indexOf('/* ================= 5S — núcleo'), fim = src.indexOf('/* ================= 5S — telas');
assert(ini > 0 && fim > ini, 'núcleo do 5S não encontrado em src/App.jsx');
const C = new Function(src.slice(ini, fim) + '; return { C5_DIAS_ALERTA, C5_MAX_FOTOS, C5_TURNOS, c5Turno, c5TurnoRef, c5Fotos, c5Validos, c5Abertos, c5Horas, c5Chave, c5Setores, c5Resumo };')();
// o painel do desktop usa uma cópia idêntica do núcleo
const desk = fs.readFileSync(path.join(__dirname, '..', 'public', 'desktop', 'index.html'), 'utf8');
const di = desk.indexOf('/* ================= 5S — núcleo'), df = desk.indexOf('/* ================= 5S — painel');
assert(di > 0 && df > di, 'núcleo do 5S não encontrado no desktop');
assert.strictEqual(desk.slice(di, df), src.slice(ini, fim), 'o núcleo do 5S do desktop está diferente do app');

const T = (d, h) => new Date('2026-11-' + String(d).padStart(2, '0') + 'T' + String(h === undefined ? 12 : h).padStart(2, '0') + ':00:00-03:00').toISOString();
const AGORA = new Date(T(20, 12)).getTime();
const de = new Date(T(1, 0)).getTime(), ate = new Date('2026-12-01T00:00:00-03:00').getTime();
const rs = [
  { id: 'a', setor: 'Laminação', problema: 'p', abertoEm: T(2), abertoPorNome: 'Maria' },                                                        // aberto há 18 dias (antigo)
  { id: 'b', setor: 'laminacao ', problema: 'p', abertoEm: T(10), abertoPorNome: 'João', concluidoEm: T(11), concluidoPorNome: 'Ana', acao: 'x' },   // 24 h
  { id: 'c', setor: 'Expedição', problema: 'p', abertoEm: T(18), abertoPorNome: 'João' },                                                       // aberto há 2 dias
  { id: 'd', setor: 'Expedição', problema: 'p', abertoEm: T(5), abertoPorNome: 'Ana', concluidoEm: T(5, 18), concluidoPorNome: 'Ana', acao: 'y' }, // 6 h
  { id: 'x', setor: 'Oficina', problema: 'p', abertoEm: T(3), anulado: true },                                                                    // anulado: não conta
  { id: 'o', setor: 'Antigo', problema: 'p', abertoEm: '2026-09-01T12:00:00-03:00', concluidoEm: '2026-10-02T12:00:00-03:00', concluidoPorNome: 'Zé', acao: 'z' }, // fora do período
];
assert.deepStrictEqual(C.c5Validos(rs).map(r => r.id), ['a', 'b', 'c', 'd', 'o']);
assert.deepStrictEqual(C.c5Abertos(rs).map(r => r.id), ['a', 'c']);                                  // mais antigo primeiro, sem anulado nem concluído
assert.strictEqual(C.c5Horas(rs[1], AGORA), 24);                                                     // concluído: da abertura à conclusão
assert.strictEqual(C.c5Horas(rs[2], AGORA), 48);                                                     // aberto: até agora
assert.strictEqual(C.c5Horas({ abertoEm: T(10), concluidoEm: T(9) }, AGORA), 0);                     // nunca negativo
assert.strictEqual(C.c5Chave('  Laminação  '), C.c5Chave('LAMINACAO'));
assert.deepStrictEqual(C.c5Setores(rs), ['Expedição', 'Laminação', 'Antigo']);                       // mais usados primeiro (empate: ordem alfabética), sem Oficina (anulada)

const R = C.c5Resumo(rs, de, ate, AGORA);
assert.strictEqual(R.abertosP, 4);                                                                   // a, b, c, d abertos em novembro
assert.strictEqual(R.concluidosP, 2);                                                                // b, d (o foi em outubro)
assert.strictEqual(R.abertosAgora, 2);
assert.strictEqual(R.antigos, 1); assert.strictEqual(R.antigosLista[0].id, 'a');                      // aberto há mais de 7 dias
assert.strictEqual(R.tempoMedioH, (24 + 6) / 2);
const lam = R.porSetor.find(x => C.c5Chave(x.nome) === 'laminacao');
assert.deepStrictEqual([lam.abertos, lam.concluidos], [2, 1]);                                       // "Laminação" e "laminacao " são o mesmo setor
assert.strictEqual(lam.nome, 'Laminação');                                                           // mostra o nome com maiúscula/acento
const exp = R.porSetor.find(x => x.nome === 'Expedição'); assert.deepStrictEqual([exp.abertos, exp.concluidos], [2, 1]);
const ana = R.porPessoa.find(x => x.nome === 'Ana'); assert.deepStrictEqual([ana.abertos, ana.concluidos], [1, 2]);
assert.strictEqual(R.porPessoa.find(x => x.nome === 'Zé'), undefined);                               // concluiu fora do período
assert.strictEqual([...R.concluidosPorDia.values()].reduce((s, x) => s + x, 0), 2);
// período vazio e lista vazia não quebram
const V = C.c5Resumo([], de, ate, AGORA); assert.strictEqual(V.tempoMedioH, null); assert.strictEqual(V.abertosAgora, 0);
// várias fotos: a principal vem primeiro, depois as extras; vazio não conta
assert.strictEqual(C.C5_MAX_FOTOS, 5);
assert.deepStrictEqual(C.c5Fotos({ fotoAntes: 'a', fotosAntesExtra: ['b', 'c'] }, 'antes'), ['a', 'b', 'c']);
assert.deepStrictEqual(C.c5Fotos({ fotoAntes: 'a' }, 'antes'), ['a']);                                  // registro antigo (update_018), sem extras
assert.deepStrictEqual(C.c5Fotos({ fotoAntes: 'a', fotoDepois: 'd', fotosDepoisExtra: ['e'] }, 'depois'), ['d', 'e']);
assert.deepStrictEqual(C.c5Fotos({ fotoAntes: 'a' }, 'depois'), []);                                    // em aberto: sem fotos do depois
// turnos (cortes 07:10 / 15:10 / 23:10, no horário local da máquina)
const hm = (h, m) => new Date(2026, 10, 5, h, m).toISOString();
const casos = [[0,0,3],[7,9,3],[7,10,1],[12,0,1],[15,9,1],[15,10,2],[20,0,2],[23,9,2],[23,10,3],[23,59,3]];
casos.forEach(([h, m, t]) => assert.strictEqual(C.c5Turno(hm(h, m)), t, h + ':' + m + ' deveria ser o ' + t + 'º turno'));
assert.strictEqual(C.c5Turno(null), null); assert.strictEqual(C.c5Turno('lixo'), null);
assert.strictEqual(C.C5_TURNOS[2], '2º turno');
assert.strictEqual(C.c5TurnoRef({ abertoEm: hm(8, 0), concluidoEm: hm(16, 0) }), 2);                    // concluído: vale a conclusão
assert.strictEqual(C.c5TurnoRef({ abertoEm: hm(8, 0) }), 1);                                           // em aberto: vale a abertura
const RT = C.c5Resumo([
  { id: 't1', setor: 'A', abertoEm: new Date(2026, 10, 5, 8, 0).toISOString(), abertoPorNome: 'x' },
  { id: 't2', setor: 'A', abertoEm: new Date(2026, 10, 5, 23, 30).toISOString(), abertoPorNome: 'x', concluidoEm: new Date(2026, 10, 6, 6, 0).toISOString(), concluidoPorNome: 'y' },
], new Date(2026, 10, 1).getTime(), new Date(2026, 11, 1).getTime(), new Date(2026, 10, 20).getTime());
assert.deepStrictEqual(RT.porTurno, { 1: { abertos: 1, concluidos: 0 }, 2: { abertos: 0, concluidos: 0 }, 3: { abertos: 1, concluidos: 1 } });   // aberto 23:30 e concluído 06:00 = 3º turno
console.log('cinco_s_core: todos os testes passaram');
