// Testa a Edge Function admin-usuarios (supabase/functions/admin-usuarios/index.ts): quem pode chamar,
// criar, atualizar (áreas/papel/bloqueio), trocar senha, travas de si mesmo e do outro administrador.
// Rodar:  node tests/admin_usuarios.test.cjs      (Node 22.13+; banco simulado)
const fs = require('fs'), path = require('path'), assert = require('assert'), { stripTypeScriptTypes } = require('node:module');
const src = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'functions', 'admin-usuarios', 'index.ts'), 'utf8');
const ini = src.indexOf('// ---- ADM-CORE-INICIO'), fim = src.indexOf('// ---- ADM-CORE-FIM');
assert(ini > 0 && fim > ini, 'bloco não encontrado');
const js = stripTypeScriptTypes(src.slice(ini, fim));
const tratar = new Function(js + '; return tratar;')();

function novoBanco() {
  const T = {
    profiles: [
      { id: 'adm', nome: 'Felipe', role: 'supervisor', ativo: true, admin: true, area: 'trefila' },
      { id: 'adm2', nome: 'Outro Adm', role: 'supervisor', ativo: true, admin: true, area: 'trefila' },
      { id: 'u1', nome: 'Ana', role: 'operador', ativo: true, admin: false, area: 'trefila' },
      { id: 'sup', nome: 'Sup', role: 'supervisor', ativo: true, admin: false, area: 'trefila' },
      { id: 'bloq', nome: 'Bloq', role: 'supervisor', ativo: false, admin: true, area: 'trefila' },
    ],
    usuario_areas: [{ user_id: 'adm', area: 'trefila' }, { user_id: 'u1', area: 'trefila' }, { user_id: 'u1', area: 'gestao' }],
    areas: [{ id: 'trefila', nome: 'Trefila', ativa: true }, { id: 'gestao', nome: 'Gestão', ativa: true }, { id: 'gestao_p1', nome: 'Gestão P1', ativa: true }, { id: 'velha', nome: 'Velha', ativa: false }],
    admin_acoes: [],
  };
  const authUsers = [
    { id: 'adm', email: 'felipe@x.com' }, { id: 'adm2', email: 'o@x.com' }, { id: 'u1', email: 'ana@x.com' },
    { id: 'sup', email: 'sup@x.com' }, { id: 'bloq', email: 'b@x.com' },
  ];
  const tokens = { tadm: 'adm', tadm2: 'adm2', tu1: 'u1', tsup: 'sup', tbloq: 'bloq' };
  const falhas = { insertAreas: false };
  let seq = 0;
  const from = nome => {
    const q = { f: [], op: 'select', v: null };
    const passa = r => q.f.every(([c, v]) => r[c] === v);
    q.select = () => q; q.order = () => q;
    q.eq = (c, v) => { q.f.push([c, v]); return q; };
    q.insert = v => { q.op = 'insert'; q.v = v; return q; };
    q.upsert = v => { q.op = 'upsert'; q.v = v; return q; };
    q.update = v => { q.op = 'update'; q.v = v; return q; };
    q.delete = () => { q.op = 'delete'; return q; };
    const exec = () => {
      const tb = T[nome];
      if (q.op === 'insert') {
        if (nome === 'usuario_areas' && falhas.insertAreas) return { data: null, error: { message: 'falha simulada' } };
        [].concat(q.v).forEach(r => tb.push({ ...r })); return { data: null, error: null };
      }
      if (q.op === 'upsert') { const i = tb.findIndex(r => r.id === q.v.id); if (i >= 0) Object.assign(tb[i], q.v); else tb.push({ admin: false, ...q.v }); return { data: null, error: null }; }
      if (q.op === 'update') { tb.filter(passa).forEach(r => Object.assign(r, q.v)); return { data: null, error: null }; }
      if (q.op === 'delete') { T[nome] = tb.filter(r => !passa(r)); return { data: null, error: null }; }
      return { data: tb.filter(passa).map(r => ({ ...r })), error: null };
    };
    q.maybeSingle = async () => { const r = exec(); return { data: r.data[0] ?? null, error: null }; };
    q.then = (res, rej) => { try { res(exec()); } catch (e) { rej && rej(e); } };
    return q;
  };
  const auth = {
    getUser: async jwt => tokens[jwt] ? { data: { user: { id: tokens[jwt], email: tokens[jwt] + '@x.com' } }, error: null } : { data: null, error: { message: 'bad' } },
    admin: {
      listUsers: async () => ({ data: { users: authUsers.map(u => ({ ...u, last_sign_in_at: null, created_at: '2026-01-01' })) }, error: null }),
      createUser: async ({ email, password }) => {
        if (authUsers.some(u => u.email === email)) return { data: null, error: { message: 'User already registered' } };
        const id = 'n' + (++seq); authUsers.push({ id, email, senha: password }); return { data: { user: { id } }, error: null };
      },
      updateUserById: async (id, v) => { const u = authUsers.find(x => x.id === id); if (!u) return { error: { message: 'nao' } }; u.senha = v.password; return { error: null }; },
      deleteUser: async id => { const i = authUsers.findIndex(x => x.id === id); if (i >= 0) authUsers.splice(i, 1); return { error: null }; },
    },
  };
  return { sb: { from, auth }, T, authUsers, falhas };
}
const R = (b, jwt, corpo) => tratar(b.sb, jwt, corpo);

(async () => {
  // ---- quem pode chamar ----
  let b = novoBanco();
  for (const jwt of ['', 'lixo', 'tu1', 'tsup', 'tbloq']) assert((await R(b, jwt, { acao: 'listar' })).erro, 'deveria negar: ' + jwt);
  assert.strictEqual((await R(b, 'tadm', { acao: 'xyz' })).erro, 'Ação desconhecida.');

  // ---- listar ----
  let r = await R(b, 'tadm', { acao: 'listar' });
  assert(r.ok && r.usuarios.length === 5);
  const ana = r.usuarios.find(u => u.id === 'u1');
  assert.deepStrictEqual(ana.areas.sort(), ['gestao', 'trefila']); assert.strictEqual(ana.email, 'ana@x.com');
  assert.strictEqual(r.usuarios.find(u => u.id === 'bloq').ativo, false);
  assert.strictEqual(r.areas.length, 4);

  // ---- criar ----
  const ok = { acao: 'criar', nome: 'Beto', email: ' Beto@X.com ', senha: 'abcd1234', role: 'operador', areas: ['gestao_p1', 'trefila'] };
  for (const [campo, v] of [['nome', 'a'], ['email', 'xx'], ['senha', '123'], ['role', 'admin'], ['areas', []], ['areas', ['velha']], ['areas', ['naoexiste']]])
    assert((await R(b, 'tadm', { ...ok, [campo]: v })).erro, 'devia recusar ' + campo);
  assert.strictEqual(b.authUsers.length, 5, 'recusas não criam conta');
  r = await R(b, 'tadm', ok); assert(r.ok, JSON.stringify(r)); assert.strictEqual(r.email, 'beto@x.com');
  let p = b.T.profiles.find(x => x.id === r.id);
  assert(p.ativo === true && p.role === 'operador' && p.admin === false && p.area === 'gestao_p1' && p.nome === 'Beto');
  assert.deepStrictEqual(b.T.usuario_areas.filter(x => x.user_id === r.id).map(x => x.area), ['gestao_p1', 'trefila']);
  assert.strictEqual(b.T.admin_acoes.length, 1); assert(!JSON.stringify(b.T.admin_acoes).includes('abcd1234'), 'senha não pode ir para o registro');
  assert(/já existe/i.test((await R(b, 'tadm', ok)).erro));
  // falha no meio: desfaz tudo
  b.falhas.insertAreas = true;
  r = await R(b, 'tadm', { ...ok, email: 'c@x.com' }); assert(r.erro && /nada foi criado/.test(r.erro));
  assert(!b.authUsers.some(u => u.email === 'c@x.com') && !b.T.profiles.some(x => x.nome === 'Beto' && x.area === 'gestao_p1' && x.id !== p.id));
  b.falhas.insertAreas = false;

  // ---- atualizar ----
  b = novoBanco();
  r = await R(b, 'tadm', { acao: 'atualizar', id: 'u1', areas: ['gestao_p1', 'gestao'], role: 'supervisor' }); assert(r.ok, JSON.stringify(r));
  assert.deepStrictEqual(b.T.usuario_areas.filter(x => x.user_id === 'u1').map(x => x.area).sort(), ['gestao', 'gestao_p1']);
  p = b.T.profiles.find(x => x.id === 'u1'); assert.strictEqual(p.area, 'gestao_p1'); // área principal removida (trefila) -> primeira da nova lista
  assert.strictEqual(p.role, 'supervisor');
  r = await R(b, 'tadm', { acao: 'atualizar', id: 'u1', ativo: false }); assert(r.ok);
  assert.strictEqual(b.T.profiles.find(x => x.id === 'u1').ativo, false);
  assert.strictEqual(b.T.admin_acoes.at(-1).acao, 'bloquear');
  await R(b, 'tadm', { acao: 'atualizar', id: 'u1', ativo: true }); assert.strictEqual(b.T.admin_acoes.at(-1).acao, 'reativar');
  assert((await R(b, 'tadm', { acao: 'atualizar', id: 'u1', areas: [] })).erro);
  assert((await R(b, 'tadm', { acao: 'atualizar', id: 'u1', areas: ['velha'] })).erro);
  assert((await R(b, 'tadm', { acao: 'atualizar', id: 'u1', role: 'dono' })).erro);
  assert((await R(b, 'tadm', { acao: 'atualizar', id: 'zzz', nome: 'Xx' })).erro);
  assert((await R(b, 'tadm', { acao: 'atualizar', id: 'u1' })).semMudanca);
  // travas
  assert(/bloquear a sua/.test((await R(b, 'tadm', { acao: 'atualizar', id: 'adm', ativo: false })).erro));
  assert(/próprio papel/.test((await R(b, 'tadm', { acao: 'atualizar', id: 'adm', role: 'operador' })).erro));
  assert(/tirar áreas/.test((await R(b, 'tadm', { acao: 'atualizar', id: 'adm', areas: ['gestao'] })).erro));
  assert((await R(b, 'tadm', { acao: 'atualizar', id: 'adm', areas: ['trefila', 'gestao', 'gestao_p1'] })).ok, 'pode acrescentar área a si mesmo');
  assert(/outro administrador/i.test((await R(b, 'tadm', { acao: 'atualizar', id: 'adm2', ativo: false })).erro));
  assert(/outro administrador/i.test((await R(b, 'tadm', { acao: 'atualizar', id: 'adm2', role: 'operador' })).erro));
  // nunca muda admin
  await R(b, 'tadm', { acao: 'atualizar', id: 'u1', admin: true, nome: 'Ana Maria' });
  assert.strictEqual(b.T.profiles.find(x => x.id === 'u1').admin, false); assert.strictEqual(b.T.profiles.find(x => x.id === 'u1').nome, 'Ana Maria');

  // ---- senha ----
  assert((await R(b, 'tadm', { acao: 'senha', id: 'u1', senha: '123' })).erro);
  assert((await R(b, 'tadm', { acao: 'senha', id: 'u1', senha: 'novaSenha9' })).ok);
  assert.strictEqual(b.authUsers.find(u => u.id === 'u1').senha, 'novaSenha9');
  assert(!JSON.stringify(b.T.admin_acoes).includes('novaSenha9'));
  assert.strictEqual(b.T.admin_acoes.at(-1).acao, 'senha');
  console.log('admin_usuarios: tudo certo');
})().catch(e => { console.error(e); process.exit(1); });
