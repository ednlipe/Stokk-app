// Edge Function "admin-usuarios": tela Usuários do app (só para administrador).
// Ações (corpo JSON {acao, ...}): listar | criar | atualizar | senha
// Segurança: o app envia o login (JWT) de quem está logado; aqui confere-se, com a chave de serviço,
// se essa conta está ativa e com profiles.admin = true ANTES de qualquer coisa. O campo admin NUNCA muda por aqui.
// Nada é apagado: bloquear = profiles.ativo = false. Toda ação é gravada em public.admin_acoes (sem senhas).
// Resposta sempre 200 com {ok:true,...} ou {erro:"texto"} (o app mostra o texto).
// Pré-requisito: update_020_admin.sql. (SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY existem automaticamente.)
import { createClient } from 'npm:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// ---- ADM-CORE-INICIO (testado em tests/admin_usuarios.test.cjs) ----
const PAPEIS = ['operador', 'supervisor'];
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

class ErroNegocio extends Error {}
const falha = (msg: string) => new ErroNegocio(msg);

function limparAreas(v: any): string[] {
  return Array.isArray(v) ? [...new Set(v.map((x) => String(x)))] : [];
}

async function registrar(sb: any, adm: any, acao: string, alvoId: string | null, alvoEmail: string | null, detalhe: any) {
  try {
    await sb.from('admin_acoes').insert({
      admin_id: adm.id, admin_nome: adm.nome, acao, alvo_id: alvoId, alvo_email: alvoEmail, detalhe: detalhe || null,
    });
  } catch (_e) { /* o registro não pode derrubar a ação já feita */ }
}

async function areasAtivas(sb: any): Promise<Set<string>> {
  const r = await sb.from('areas').select('id,ativa');
  if (r.error) throw falha('Não consegui ler as áreas: ' + r.error.message);
  return new Set((r.data || []).filter((a: any) => a.ativa !== false).map((a: any) => a.id));
}

async function quemChama(sb: any, jwt: string) {
  if (!jwt) throw falha('Sem login.');
  const u = await sb.auth.getUser(jwt);
  if (u.error || !u.data || !u.data.user) throw falha('Login inválido ou expirado. Entre de novo.');
  const p = await sb.from('profiles').select('id,nome,ativo,admin').eq('id', u.data.user.id).maybeSingle();
  if (p.error) throw falha('Não consegui conferir o seu perfil (rodou o update_020?): ' + p.error.message);
  if (!p.data || p.data.ativo !== true || p.data.admin !== true) throw falha('Só o administrador pode usar esta tela.');
  return { id: p.data.id, nome: p.data.nome || u.data.user.email || '' };
}

async function listar(sb: any) {
  const [pr, ua, ar] = await Promise.all([
    sb.from('profiles').select('id,nome,role,ativo,admin,area,criado_em'),
    sb.from('usuario_areas').select('user_id,area'),
    sb.from('areas').select('id,nome,ativa'),
  ]);
  for (const r of [pr, ua, ar]) if (r.error) throw falha('Erro ao listar: ' + r.error.message);
  const emails = new Map<string, any>();
  for (let pagina = 1; pagina <= 20; pagina++) {
    const l = await sb.auth.admin.listUsers({ page: pagina, perPage: 1000 });
    if (l.error) throw falha('Erro ao ler os e-mails: ' + l.error.message);
    const us = (l.data && l.data.users) || [];
    us.forEach((u: any) => emails.set(u.id, u));
    if (us.length < 1000) break;
  }
  const porUsuario = new Map<string, string[]>();
  (ua.data || []).forEach((r: any) => { if (!porUsuario.has(r.user_id)) porUsuario.set(r.user_id, []); porUsuario.get(r.user_id)!.push(r.area); });
  const usuarios = (pr.data || []).map((p: any) => {
    const u = emails.get(p.id) || {};
    const areas = new Set(porUsuario.get(p.id) || []);
    if (p.area) areas.add(p.area);
    return {
      id: p.id, nome: p.nome || '', email: u.email || '', role: p.role, ativo: p.ativo === true, admin: p.admin === true,
      areas: [...areas], ultimoAcesso: u.last_sign_in_at || null, criadoEm: p.criado_em || u.created_at || null,
    };
  });
  usuarios.sort((a: any, b: any) => String(a.nome).localeCompare(String(b.nome), 'pt-BR'));
  return { ok: true, usuarios, areas: (ar.data || []).map((a: any) => ({ id: a.id, nome: a.nome, ativa: a.ativa !== false })) };
}

async function criar(sb: any, adm: any, c: any) {
  const nome = String(c.nome || '').trim();
  const email = String(c.email || '').trim().toLowerCase();
  const senha = String(c.senha || '');
  const role = String(c.role || 'operador');
  const areas = limparAreas(c.areas);
  if (nome.length < 2 || nome.length > 80) throw falha('Informe o nome (2 a 80 letras).');
  if (!EMAIL_RE.test(email)) throw falha('E-mail inválido.');
  if (senha.length < 8 || senha.length > 72) throw falha('A senha precisa ter de 8 a 72 caracteres.');
  if (!PAPEIS.includes(role)) throw falha('Papel inválido.');
  if (!areas.length) throw falha('Escolha pelo menos uma área.');
  const ativas = await areasAtivas(sb);
  if (areas.some((a) => !ativas.has(a))) throw falha('Há área inexistente ou desativada na lista.');

  const cu = await sb.auth.admin.createUser({ email, password: senha, email_confirm: true, user_metadata: { nome } });
  if (cu.error || !cu.data || !cu.data.user) {
    const m = (cu.error && cu.error.message) || '';
    throw falha(/already|registered|exists/i.test(m) ? 'Já existe uma conta com esse e-mail.' : 'Não consegui criar a conta: ' + m);
  }
  const id = cu.data.user.id;
  try {
    const up = await sb.from('profiles').upsert({ id, nome, role, ativo: true, area: areas[0] });
    if (up.error) throw new Error(up.error.message);
    const ins = await sb.from('usuario_areas').insert(areas.map((a) => ({ user_id: id, area: a })));
    if (ins.error) throw new Error(ins.error.message);
  } catch (e: any) {
    try { await sb.from('usuario_areas').delete().eq('user_id', id); } catch (_x) { /* */ }
    try { await sb.from('profiles').delete().eq('id', id); } catch (_x) { /* */ }
    try { await sb.auth.admin.deleteUser(id); } catch (_x) { /* */ }
    throw falha('Não consegui terminar o cadastro (nada foi criado): ' + (e && e.message));
  }
  await registrar(sb, adm, 'criar', id, email, { nome, role, areas });
  return { ok: true, id, email };
}

async function atualizar(sb: any, adm: any, c: any) {
  const id = String(c.id || '');
  if (!id) throw falha('Usuário não informado.');
  const alvo = await sb.from('profiles').select('id,nome,role,ativo,admin,area').eq('id', id).maybeSingle();
  if (alvo.error || !alvo.data) throw falha('Usuário não encontrado.');
  const eu = id === adm.id;
  const ant = alvo.data;
  const mud: any = {};
  const det: any = {};

  if (c.nome !== undefined) {
    const nome = String(c.nome).trim();
    if (nome.length < 2 || nome.length > 80) throw falha('Nome inválido (2 a 80 letras).');
    if (nome !== ant.nome) { mud.nome = nome; det.nome = nome; }
  }
  if (c.role !== undefined && c.role !== ant.role) {
    if (!PAPEIS.includes(c.role)) throw falha('Papel inválido.');
    if (eu) throw falha('Você não pode mudar o seu próprio papel.');
    if (ant.admin) throw falha('O papel de outro administrador só muda pelo SQL.');
    mud.role = c.role; det.role = c.role;
  }
  if (c.ativo !== undefined && Boolean(c.ativo) !== (ant.ativo === true)) {
    if (eu) throw falha('Você não pode bloquear a sua própria conta.');
    if (ant.admin) throw falha('Outro administrador só é bloqueado pelo SQL.');
    mud.ativo = Boolean(c.ativo); det.ativo = mud.ativo;
  }

  let novasAreas: string[] | null = null;
  if (c.areas !== undefined) {
    novasAreas = limparAreas(c.areas);
    if (!novasAreas.length) throw falha('Deixe pelo menos uma área.');
    const ativas = await areasAtivas(sb);
    const atuais = await sb.from('usuario_areas').select('area').eq('user_id', id);
    if (atuais.error) throw falha('Erro ao ler as áreas atuais: ' + atuais.error.message);
    const antes = new Set<string>((atuais.data || []).map((r: any) => r.area));
    if (ant.area) antes.add(ant.area);
    // só pode entrar área ativa (área que já tinha e foi desativada pode continuar na lista)
    if (novasAreas.some((a) => !ativas.has(a) && !antes.has(a))) throw falha('Há área inexistente ou desativada na lista.');
    if (eu && [...antes].some((a) => !novasAreas!.includes(a))) throw falha('Você não pode tirar áreas da sua própria conta.');
    det.areas = novasAreas;
  }

  if (!Object.keys(mud).length && !novasAreas) return { ok: true, semMudanca: true };

  if (novasAreas) {
    const ap = novasAreas.includes(ant.area) ? ant.area : novasAreas[0];
    if (ap !== ant.area) mud.area = ap;
    const del = await sb.from('usuario_areas').delete().eq('user_id', id);
    if (del.error) throw falha('Erro ao trocar as áreas: ' + del.error.message);
    const ins = await sb.from('usuario_areas').insert(novasAreas.map((a) => ({ user_id: id, area: a })));
    if (ins.error) {
      // devolve o que existia
      const volta = [...new Set<string>([...(ant.area ? [ant.area] : [])])];
      if (volta.length) await sb.from('usuario_areas').insert(volta.map((a) => ({ user_id: id, area: a })));
      throw falha('Erro ao gravar as áreas: ' + ins.error.message);
    }
  }
  if (Object.keys(mud).length) {
    const up = await sb.from('profiles').update(mud).eq('id', id);
    if (up.error) throw falha('Erro ao gravar o perfil: ' + up.error.message);
  }
  await registrar(sb, adm, mud.ativo === false ? 'bloquear' : mud.ativo === true ? 'reativar' : 'atualizar', id, null, det);
  return { ok: true };
}

async function trocarSenha(sb: any, adm: any, c: any) {
  const id = String(c.id || '');
  const senha = String(c.senha || '');
  if (!id) throw falha('Usuário não informado.');
  if (senha.length < 8 || senha.length > 72) throw falha('A senha precisa ter de 8 a 72 caracteres.');
  const r = await sb.auth.admin.updateUserById(id, { password: senha });
  if (r.error) throw falha('Não consegui trocar a senha: ' + r.error.message);
  await registrar(sb, adm, 'senha', id, null, null);   // a senha nunca é gravada
  return { ok: true };
}

async function tratar(sb: any, jwt: string, corpo: any) {
  try {
    const adm = await quemChama(sb, jwt);
    const acao = String((corpo && corpo.acao) || '');
    if (acao === 'listar') return await listar(sb);
    if (acao === 'criar') return await criar(sb, adm, corpo);
    if (acao === 'atualizar') return await atualizar(sb, adm, corpo);
    if (acao === 'senha') return await trocarSenha(sb, adm, corpo);
    throw falha('Ação desconhecida.');
  } catch (e: any) {
    if (e instanceof ErroNegocio) return { erro: e.message };
    console.error('admin-usuarios', e);
    return { erro: 'Erro inesperado no servidor.' };
  }
}
// ---- ADM-CORE-FIM ----

const sbServico = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  let corpo: any = {};
  try { corpo = await req.json(); } catch (_e) { /* */ }
  const r = await tratar(sbServico, jwt, corpo);
  return new Response(JSON.stringify(r), { status: 200, headers: { ...CORS, 'Content-Type': 'application/json' } });
});
