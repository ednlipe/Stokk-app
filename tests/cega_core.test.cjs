// Testa as regras da contagem cega (leitura da etiqueta, leitura da planilha do Protheus, comparação).
// Rodar:  node tests/cega_core.test.cjs      (sem dependências; lê o código direto de src/App.jsx)
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'App.jsx'), 'utf8');
const ini = src.indexOf('/* ================= CONTAGEM CEGA — núcleo');
const fim = src.indexOf('/* ================= CONTAGEM CEGA — telas');
assert(ini > 0 && fim > ini, 'núcleo da contagem cega não encontrado em src/App.jsx');
const C = new Function(src.slice(ini, fim) + '; return { cegaLerEtiqueta, cegaLerPlanilha, cegaComparar };')();

// ---- etiqueta: volume(8) + corrida(6) + peso(4) + código do produto (termina na bitola) + peças
let r = C.cegaLerEtiqueta('PCI00096PCI0032202TPAIQ092B4.20100');
assert.deepStrictEqual([r.lote, r.corrida, r.pesoKg, r.produto, r.pecas, r.revisar], ['PCI00096', 'PCI003', 2202, 'TPAIQ092B4.20', 100, false]);
r = C.cegaLerEtiqueta('PCJ00041PCJ0052775TPAIQ196B5.0060');
assert.deepStrictEqual([r.lote, r.corrida, r.pesoKg, r.produto, r.pecas], ['PCJ00041', 'PCJ005', 2775, 'TPAIQ196B5.00', 60]);
r = C.cegaLerEtiqueta('XYZ12345ABC1230987TXYZB10.0012');          // letras diferentes, peso com zero à esquerda, bitola de 2 dígitos
assert.deepStrictEqual([r.lote, r.corrida, r.pesoKg, r.produto, r.pecas], ['XYZ12345', 'ABC123', 987, 'TXYZB10.00', 12]);
r = C.cegaLerEtiqueta(' pcj00041\r\n ');                           // código curto de baixo da etiqueta
assert.deepStrictEqual([r.lote, r.curto], ['PCJ00041', true]);
r = C.cegaLerEtiqueta('PCI00096PCI0032202TPAIQ092');               // sem bitola: lote ok, mas marcado para revisar
assert.ok(r.revisar && r.lote === 'PCI00096');
assert.ok(C.cegaLerEtiqueta('abc').desconhecido);
assert.strictEqual(C.cegaLerEtiqueta(''), null);

// ---- planilha do Protheus (blocos "Produto:" + linhas de saldo; toneladas -> kg; linhas repetidas)
const rows = [
  ['Produto:', null, 'TPAIQ092B4.20', '-', 'TELA Q92', 'UM:', 'TL', 'Tipo:', 'PA'],
  ['Saldo', 'Saldo Inicial', 'Armazém: 93', 'PCI00096', 2.202, 2.202],
  ['Saldo', 'Saldo Inicial', 'Armazém: 93', 'PCI00097', 2.1, 4.302],
  ['Saldo', 'Saldo Inicial', 'Armazém: 93', 'PCI00096', 2.202, 6.504],   // repetida
  ['Saída', '2026-10-10', 'Pedido de Venda', '135486', 'Firme', '93', null, 14, -3],
  ['Produto:', null, 'TPAIQ196B5.00', '-', 'TELA Q196', 'UM:', 'TL', 'Tipo:', 'PA'],
  ['Saldo', 'Saldo Inicial', 'Armazém: 97', 'PCJ00050', 1.5, 1.5],
];
const p = C.cegaLerPlanilha(rows);
assert.strictEqual(p.itens.length, 3); assert.strictEqual(p.repetidas, 1);
assert.deepStrictEqual(p.itens.map(i => [i.lote, i.armazem, i.pesoKg]), [['PCI00096', '93', 2202], ['PCI00097', '93', 2100], ['PCJ00050', '97', 1500]]);

// ---- comparação
const cont = [
  { lote: 'PCI00096', pesoKg: 2202, produto: 'TPAIQ092B4.20' },   // confere
  { lote: 'PCI00097', pesoKg: 2150 },                              // peso diferente (+50)
  { lote: 'ZZZ00001', pesoKg: 1000 },                              // sobrando
  { lote: 'PCJ00050', pesoKg: 1500 },                              // está no armazém 97
];
let c = C.cegaComparar(cont, p.itens, new Set(['93']));
assert.deepStrictEqual([c.conferem.length, c.pesoDiferente.length, c.sobrando.length, c.outroArmazem.length, c.faltando.length], [1, 1, 1, 1, 0]);
assert.strictEqual(c.pesoDiferente[0].diferenca, 50);
c = C.cegaComparar(cont.slice(0, 1), p.itens, new Set());
assert.deepStrictEqual(c.faltando.map(x => x.lote).sort(), ['PCI00097', 'PCJ00050']);
console.log('contagem cega: todos os testes passaram');
