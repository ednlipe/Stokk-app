// Testa o agrupamento do menu por ambiente (src/App.jsx, bloco "MENU POR AMBIENTE").
// Rodar:  node tests/menu_core.test.cjs
const fs = require('fs'), path = require('path'), assert = require('assert');
const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'App.jsx'), 'utf8');
const ini = src.indexOf('// ---- MENU-CORE-INICIO'), fim = src.indexOf('// ---- MENU-CORE-FIM');
assert(ini > 0 && fim > ini);
const { menuGrupos, areasColapsadas, rotuloAmbiente } = new Function(src.slice(ini, fim) + '; return { menuGrupos, areasColapsadas, rotuloAmbiente };')();
const G = [{ id: 'lam', nome: 'Laminação Planta 1', modulos: [{ area: 'planta1', nome: 'Inventário' }, { area: 'gestao_p1', nome: '5S' }, { area: 'gestao', nome: 'Veículos móveis' }] }];
const A = (...ids) => ids.map(id => ({ id, nome: 'N-' + id }));
// APK: nada muda
assert.deepStrictEqual(menuGrupos(A('planta1', 'gestao_p1'), true, G), []);
assert.deepStrictEqual(areasColapsadas(A('planta1', 'gestao_p1', 'trefila'), true, G).map(i => i.id), ['planta1', 'gestao_p1', 'trefila']);
// precisa de 2+ módulos do grupo
assert.deepStrictEqual(menuGrupos(A('planta1', 'trefila'), false, G), []);
assert.strictEqual(menuGrupos(A('planta1', 'gestao'), false, G).length, 1);
// colapsa: um item para o grupo, na posição da 1ª área do grupo; as outras áreas ficam como estão
let it = areasColapsadas(A('trefila', 'gestao_p1', 'planta1', 'gestao'), false, G);
assert.deepStrictEqual(it.map(i => i.nome), ['N-trefila', 'Laminação Planta 1']);
assert.strictEqual(it[1].id, 'planta1', 'o item do grupo aponta para a 1ª área do grupo na ordem dos módulos (Inventário)');
assert.deepStrictEqual(it[1].membros.sort(), ['gestao', 'gestao_p1', 'planta1']);
it = areasColapsadas(A('gestao_p1', 'gestao'), false, G);
assert.strictEqual(it.length, 1); assert.strictEqual(it[0].id, 'gestao_p1', 'sem Inventário, abre pelo 5S');
// rótulo do topo
const g = menuGrupos(A('planta1', 'gestao_p1'), false, G)[0];
assert.strictEqual(rotuloAmbiente(g, 'gestao_p1', 'x'), 'Laminação Planta 1 › 5S');
assert.strictEqual(rotuloAmbiente(null, 'trefila', 'Trefila'), 'Trefila');
console.log('menu_core: todos os testes passaram');
