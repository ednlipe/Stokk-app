// Edge Function de notificações push. Cada TIPO tem o seu próprio agendamento (pg_cron) e chama
// a função com o corpo {"tipo":"conferencia"|"inventario"|"rendimento"|"diesel"}. O horário vem do cron
// (Brasília = UTC-3). O tipo "ocorrencia" é diferente: quem chama é o próprio app (login do usuário, sem cron),
// logo depois de abrir ou liberar uma parada/manutenção. Ver docs/deploy.md.
// Segredos necessários (Edge Functions › Secrets):
//   FCM_SERVICE_ACCOUNT  = conteúdo do JSON da conta de serviço do Firebase
//   CRON_SECRET          = texto qualquer, igual ao usado no agendamento
// (SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já existem automaticamente.)
import { createClient } from 'npm:@supabase/supabase-js@2';

const MIN_IDADE_H = 2;  // só avisa conferência aberta há pelo menos 2 h (evita avisar uma que acabou de começar)
const MAX_IDADE_H = 72; // depois de 3 dias para de avisar (conferência abandonada)

const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

function b64url(input: ArrayBuffer | string) {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : new Uint8Array(input);
  let s = ''; bytes.forEach((b) => (s += String.fromCharCode(b)));
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function tokenGoogle(sa: any): Promise<string> {
  const agora = Math.floor(Date.now() / 1000);
  const cab = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const corpo = b64url(JSON.stringify({
    iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token', iat: agora, exp: agora + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const chave = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const assinatura = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', chave, new TextEncoder().encode(`${cab}.${corpo}`));
  const jwt = `${cab}.${corpo}.${b64url(assinatura)}`;
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error('Falha ao obter token do Google: ' + JSON.stringify(j));
  return j.access_token;
}

async function enviar(sa: any, acesso: string, token: string, titulo: string, texto: string) {
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${acesso}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: { token, notification: { title: titulo, body: texto },
      android: { priority: 'HIGH', notification: { channel_id: 'conferencias', icon: 'ic_stat_stokk', color: '#F28C28' } } } }),
  });
  if (r.ok) return 'ok';
  const t = await r.text();
  if (r.status === 404 || t.includes('UNREGISTERED') || t.includes('INVALID_ARGUMENT')) return 'invalido';
  console.error('FCM erro', r.status, t);
  return 'erro';
}

type Msg = { titulo: string; texto: string };

const nomeSP = new Intl.DateTimeFormat('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', year: 'numeric' });
const fmtPct = (n: number) => n.toFixed(1).replace('.', ',') + '%';

// Áreas (update_012/013): cada supervisor recebe só os avisos das áreas a que tem acesso
// (área principal em profiles.area + lista em usuario_areas).
async function areasEsupervisores(): Promise<{ nomes: Map<string, string>; sups: Map<string, string[]> }> {
  const { data: ars } = await sb.from('areas').select('id, nome').eq('ativa', true);
  const nomes = new Map<string, string>((ars ?? []).map((a: any) => [a.id, a.nome]));
  const { data: ps } = await sb.from('profiles').select('id, area').eq('role', 'supervisor').eq('ativo', true);
  const ids = (ps ?? []).map((p: any) => p.id);
  const { data: uas } = ids.length ? await sb.from('usuario_areas').select('user_id, area').in('user_id', ids) : { data: [] };
  const pares = new Set<string>();
  for (const p of ps ?? []) if (p.area) pares.add(`${p.id}|${p.area}`);
  for (const u of uas ?? []) pares.add(`${u.user_id}|${u.area}`);
  const sups = new Map<string, string[]>();
  for (const par of pares) {
    const [uid, area] = par.split('|');
    if (nomes.has(area)) sups.set(area, [...(sups.get(area) ?? []), uid]);
  }
  return { nomes, sups };
}

// ---- tipo 1: conferências em aberto (supervisores da área + quem iniciou) ----
async function montarConferencia(): Promise<{ msgs: Map<string, Msg>; total: number }> {
  const { data: sessoes, error } = await sb.from('sessoes')
    .select('id, nome, iniciado_em, usuario_id, contados, filtro_produto, area').eq('ativo', true);
  if (error) throw new Error(error.message);
  const agora = Date.now();
  const abertas = (sessoes ?? []).map((s: any) => ({ s, horas: s.iniciado_em ? (agora - new Date(s.iniciado_em).getTime()) / 3600000 : 0 }))
    .filter((x) => x.horas >= MIN_IDADE_H && x.horas <= MAX_IDADE_H);
  const { nomes, sups } = await areasEsupervisores();
  const nomeDe = (s: any) => s.nome || (s.filtro_produto ? `Conferência (${s.filtro_produto})` : 'Conferência sem nome');
  const tempoDe = (h: number) => (h >= 48 ? `${Math.floor(h / 24)} dias` : `${Math.floor(h)} h`);
  const porUsuario = new Map<string, typeof abertas>();
  for (const x of abertas) {
    const dest = new Set<string>([...(sups.get(x.s.area) ?? []), ...(x.s.usuario_id ? [x.s.usuario_id] : [])]);
    for (const u of dest) porUsuario.set(u, [...(porUsuario.get(u) ?? []), x]);
  }
  const msgs = new Map<string, Msg>();
  for (const [u, lista] of porUsuario) {
    const varias = new Set(lista.map((x) => x.s.area)).size > 1; // pessoa com mais de uma área: mostra a área
    const rot = (x: any) => nomeDe(x.s) + (varias ? ` [${nomes.get(x.s.area) ?? x.s.area}]` : '');
    msgs.set(u, {
      titulo: lista.length === 1 ? '⚠ Conferência em aberto' : `⚠ ${lista.length} conferências em aberto`,
      texto: lista.length === 1
        ? `${rot(lista[0])} está aberta há ${tempoDe(lista[0].horas)} (${Array.isArray(lista[0].s.contados) ? lista[0].s.contados.length : 0} contado(s)). Finalize ou exclua.`
        : lista.slice(0, 3).map((x) => `${rot(x)} (${tempoDe(x.horas)})`).join(', ') + (lista.length > 3 ? ` e mais ${lista.length - 3}` : '') + '. Finalize ou exclua.',
    });
  }
  return { msgs, total: abertas.length };
}

// ---- tipo 2: há quanto tempo foi o último inventário de cada área (supervisores da área) ----
async function montarInventario(): Promise<{ msgs: Map<string, Msg>; total: number }> {
  const { nomes, sups } = await areasEsupervisores();
  const partes = new Map<string, { area: string; texto: string }[]>();
  for (const [area, ids] of sups) {
    const { data, error } = await sb.from('sessoes').select('finalizado_em').eq('ativo', false).eq('area', area)
      .not('finalizado_em', 'is', null).order('finalizado_em', { ascending: false }).limit(1);
    if (error) throw new Error(error.message);
    const ult = data?.[0]?.finalizado_em;
    let texto = 'Nenhum inventário finalizado até agora.';
    if (ult) {
      const dias = Math.floor((Date.now() - new Date(ult).getTime()) / 86400000);
      texto = dias <= 0 ? `Foi finalizado hoje (${nomeSP.format(new Date(ult))}).` : `Foi há ${dias} dia${dias > 1 ? 's' : ''} (${nomeSP.format(new Date(ult))}).`;
    }
    for (const u of ids) partes.set(u, [...(partes.get(u) ?? []), { area, texto }]);
  }
  const msgs = new Map<string, Msg>();
  for (const [u, ps] of partes) {
    msgs.set(u, ps.length === 1
      ? { titulo: `📋 Último inventário · ${nomes.get(ps[0].area)}`, texto: ps[0].texto }
      : { titulo: '📋 Último inventário', texto: ps.map((p) => `${nomes.get(p.area)}: ${p.texto}`).join(' ') });
  }
  return { msgs, total: partes.size ? 1 : 0 };
}

// ---- tipo 3: produções finalizadas hoje com rendimento abaixo de 98% (supervisores da área) ----
async function montarRendimento(): Promise<{ msgs: Map<string, Msg>; total: number }> {
  const hojeSP = new Date(Date.now() - 3 * 3600000).toISOString().slice(0, 10); // data de hoje em Brasília
  const { data, error } = await sb.from('producoes').select('equipamento, turno, resultado, finalizado_em, area')
    .eq('etapa', 'finalizada').gte('finalizado_em', `${hojeSP}T00:00:00-03:00`);
  if (error) throw new Error(error.message);
  const baixas = (data ?? []).filter((p: any) => {
    const pct = Number(p.resultado?.rendimentoPct);
    return Number.isFinite(pct) && Math.round(pct * 10) / 10 < 98;
  });
  const msgs = new Map<string, Msg>();
  if (!baixas.length) return { msgs, total: 0 };
  const { nomes, sups } = await areasEsupervisores();
  const porUsuario = new Map<string, any[]>();
  for (const p of baixas) for (const u of sups.get(p.area) ?? []) porUsuario.set(u, [...(porUsuario.get(u) ?? []), p]);
  for (const [u, lista] of porUsuario) {
    const varias = new Set(lista.map((p) => p.area)).size > 1;
    const itens = lista.slice(0, 3).map((p: any) =>
      `${p.equipamento}${p.turno ? ` (${p.turno}º turno)` : ''} ${fmtPct(Number(p.resultado.rendimentoPct))}${varias ? ` [${nomes.get(p.area) ?? p.area}]` : ''}`);
    msgs.set(u, {
      titulo: lista.length === 1 ? '🔻 Rendimento abaixo de 98%' : `🔻 ${lista.length} produções abaixo de 98%`,
      texto: 'Hoje: ' + itens.join(', ') + (lista.length > 3 ? ` e mais ${lista.length - 3}` : '') + '.',
    });
  }
  return { msgs, total: baixas.length };
}

// ---- tipo 4: equipamentos sem abastecer há mais dias que o prazo (supervisores da área Gestão) ----
// Mesma regra do app (dslSemAbastecer em src/App.jsx): conta dias de Brasília entre o último abastecimento válido
// (ou o cadastro, se nunca abasteceu) e hoje; avisa quando passa do prazo do equipamento (dias_alerta);
// com alerta_dias_uteis só conta segunda a sexta. Equipamento inativo ou com alerta desligado não entra.
const MS_DIA = 86400000;
const diaSP = (t: number) => new Date(t - 3 * 3600000).toISOString().slice(0, 10);
function diasEntre(deT: number, ateT: number, uteis: boolean): number {
  const a = Date.parse(diaSP(deT) + 'T00:00:00Z'), b = Date.parse(diaSP(ateT) + 'T00:00:00Z');
  if (b <= a) return 0;
  if (!uteis) return Math.round((b - a) / MS_DIA);
  let n = 0;
  for (let t = a + MS_DIA; t <= b; t += MS_DIA) { const w = new Date(t).getUTCDay(); if (w !== 0 && w !== 6) n++; }
  return n;
}
async function montarDiesel(): Promise<{ msgs: Map<string, Msg>; total: number }> {
  const { data: eqs, error } = await sb.from('equipamentos')
    .select('id, codigo, nome, dias_alerta, alerta_dias_uteis, criado_em, area').eq('ativo', true).eq('alerta_ativo', true);
  if (error) throw new Error(error.message);
  const msgs = new Map<string, Msg>();
  if (!(eqs ?? []).length) return { msgs, total: 0 };
  const desde = new Date(Date.now() - 70 * MS_DIA).toISOString(); // o prazo máximo é 60 dias
  const { data: abs, error: e2 } = await sb.from('abastecimentos').select('equipamento_id, data_hora')
    .eq('anulado', false).gte('data_hora', desde).order('data_hora', { ascending: false }).limit(20000);
  if (e2) throw new Error(e2.message);
  const ult = new Map<string, number>();
  for (const a of abs ?? []) if (!ult.has(a.equipamento_id)) ult.set(a.equipamento_id, new Date(a.data_hora).getTime());
  const agora = Date.now();
  // equipamento parado/em manutenção (ocorrência em aberto) não é "falta de abastecimento". Se o update_016 ainda não
  // foi rodado, a consulta dá erro e nada é ignorado.
  const { data: abertas } = await sb.from('ocorrencias').select('equipamento_id').is('liberada_em', null).eq('anulado', false);
  const emOcorrencia = new Set<string>((abertas ?? []).map((o: any) => o.equipamento_id));
  const paradas: { e: any; dias: number }[] = [];
  for (const e of eqs ?? []) {
    if (emOcorrencia.has(e.id)) continue;
    const base = ult.get(e.id) ?? new Date(e.criado_em).getTime();
    const dias = diasEntre(base, agora, !!e.alerta_dias_uteis);
    if (dias > (Number(e.dias_alerta) || 2)) paradas.push({ e, dias });
  }
  if (!paradas.length) return { msgs, total: 0 };
  paradas.sort((a, b) => b.dias - a.dias);
  const { sups } = await areasEsupervisores();
  const porUsuario = new Map<string, typeof paradas>();
  for (const p of paradas) for (const u of sups.get(p.e.area) ?? []) porUsuario.set(u, [...(porUsuario.get(u) ?? []), p]);
  for (const [u, lista] of porUsuario) {
    msgs.set(u, {
      titulo: lista.length === 1 ? '⛽ Equipamento sem abastecer' : `⛽ ${lista.length} equipamentos sem abastecer`,
      texto: lista.slice(0, 4).map((x) => `${x.e.codigo} (${x.dias} dias)`).join(', ') + (lista.length > 4 ? ` e mais ${lista.length - 4}` : '') + '.',
    });
  }
  return { msgs, total: paradas.length };
}

// ---- tipo 5: parada/manutenção aberta ou liberada (aviso na hora, chamado pelo app) ----
// A mensagem sai do banco, não do que o app mandar. Só quem abriu (ou quem liberou) dispara o aviso, até 15 min depois;
// cada aviso sai uma vez só (a coluna aviso_*_em é "reservada" antes do envio, de forma atômica).
const fmtHoras = (h: number) => h < 1 ? `${Math.max(1, Math.round(h * 60))} min`
  : h < 48 ? `${Math.floor(h)} h${Math.round((h - Math.floor(h)) * 60) ? ' ' + Math.round((h - Math.floor(h)) * 60) + ' min' : ''}`
  : `${Math.floor(h / 24)} dias`;
const corta = (t: any, n: number) => { const x = String(t ?? '').trim(); return x.length > n ? x.slice(0, n - 1) + '…' : x; };
async function areasDoUsuario(uid: string): Promise<Set<string>> {
  const { data: p } = await sb.from('profiles').select('area, ativo').eq('id', uid).maybeSingle();
  if (!p || !p.ativo) return new Set();
  const { data: uas } = await sb.from('usuario_areas').select('area').eq('user_id', uid);
  return new Set<string>([...(p.area ? [p.area] : []), ...(uas ?? []).map((u: any) => u.area)]);
}
async function montarOcorrencia(uid: string, id: string, evento: string): Promise<{ msgs: Map<string, Msg>; total: number }> {
  const vazio = { msgs: new Map<string, Msg>(), total: 0 };
  if (evento !== 'abertura' && evento !== 'liberacao') throw { status: 400, msg: 'evento desconhecido' };
  const { data: o, error } = await sb.from('ocorrencias').select('*').eq('id', id).maybeSingle();
  if (error) throw { status: 500, msg: error.message };
  if (!o || o.anulado) throw { status: 404, msg: 'ocorrência não encontrada' };
  if (!(await areasDoUsuario(uid)).has(o.area)) throw { status: 403, msg: 'proibido' };
  const agora = Date.now(), JANELA = 15 * 60000;
  const campo = evento === 'abertura' ? 'aviso_abertura_em' : 'aviso_liberacao_em';
  if (evento === 'abertura') {
    if (o.aberta_por !== uid) throw { status: 403, msg: 'só quem abriu avisa' };
    if (agora - new Date(o.criado_em).getTime() > JANELA) throw { status: 409, msg: 'tarde demais para avisar' };
  } else {
    if (!o.liberada_em || o.liberada_por !== uid) throw { status: 403, msg: 'só quem liberou avisa' };
    if (!o.liberada_registro_em || agora - new Date(o.liberada_registro_em).getTime() > JANELA) throw { status: 409, msg: 'tarde demais para avisar' };
  }
  if (o[campo]) return vazio;   // já avisado
  const { data: reservou, error: e2 } = await sb.from('ocorrencias').update({ [campo]: new Date().toISOString() }).eq('id', id).is(campo, null).select('id');
  if (e2) throw { status: 500, msg: e2.message };
  if (!reservou?.length) return vazio;   // outra chamada reservou primeiro
  const { data: eq } = await sb.from('equipamentos').select('codigo, nome').eq('id', o.equipamento_id).maybeSingle();
  const cod = eq?.codigo ?? o.equipamento_codigo ?? 'Equipamento';
  const { sups } = await areasEsupervisores();
  const dest = new Set<string>(sups.get(o.area) ?? []);
  let m: Msg;
  if (evento === 'abertura') {
    m = { titulo: o.categoria === 'manutencao' ? `🔧 ${cod} em manutenção` : `⏸ ${cod} parado`,
          texto: `${o.motivo}: ${corta(o.descricao, 120)}${o.aberta_por_nome ? ` (aberto por ${o.aberta_por_nome})` : ''}.` };
  } else {
    if (o.aberta_por) dest.add(o.aberta_por);   // quem abriu também sabe que voltou
    const h = (new Date(o.liberada_em).getTime() - new Date(o.aberta_em).getTime()) / 3600000;
    m = { titulo: `✅ ${cod} liberado`,
          texto: `${o.motivo_liberacao} — ${corta(o.servico_realizado, 100)}. Pegou: ${corta(o.recebido_por, 40)}. Ficou parado ${fmtHoras(Math.max(h, 0))}.` };
  }
  dest.delete(uid);   // quem fez a ação não precisa do aviso
  const msgs = new Map<string, Msg>();
  for (const u of dest) msgs.set(u, m);
  return { msgs, total: 1 };
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const resp = (corpo: string | null, status = 200) => new Response(corpo, { status, headers: CORS });

async function disparar(tipo: string, resultado: { msgs: Map<string, Msg>; total: number }): Promise<Response> {
  if (!resultado.msgs.size) return Response.json({ tipo, itens: resultado.total, enviados: 0 }, { headers: CORS });
  let sa: any;
  try { sa = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT') ?? ''); }
  catch { return resp('Segredo FCM_SERVICE_ACCOUNT inválido: cole o conteúdo inteiro do .json da chave (começa com { e termina com }).', 500); }
  const acesso = await tokenGoogle(sa);

  let enviados = 0;
  for (const [userId, m] of resultado.msgs) {
    const { data: tokens } = await sb.from('push_tokens').select('token').eq('user_id', userId);
    for (const { token } of tokens ?? []) {
      const res = await enviar(sa, acesso, token, m.titulo, m.texto);
      if (res === 'ok') enviados++;
      if (res === 'invalido') await sb.from('push_tokens').delete().eq('token', token);
    }
  }
  return Response.json({ tipo, itens: resultado.total, enviados }, { headers: CORS });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

  let corpo: any = {};
  try { corpo = await req.json(); } catch { /* corpo vazio */ }
  const tipo = corpo?.tipo ? String(corpo.tipo) : 'conferencia'; // sem corpo = comportamento antigo

  // Aviso de ocorrência: chamado pelo app, com o login do usuário (não usa o segredo do cron)
  if (tipo === 'ocorrencia') {
    const jwt = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    const { data: u, error: eu } = jwt ? await sb.auth.getUser(jwt) : { data: null, error: new Error('sem login') };
    if (eu || !u?.user) return resp('proibido', 403);
    let resultado;
    try { resultado = await montarOcorrencia(u.user.id, String(corpo.id ?? ''), String(corpo.evento ?? '')); }
    catch (e: any) { return resp(e?.msg ?? String(e?.message ?? e), e?.status ?? 500); }
    return disparar(tipo, resultado);
  }

  if (req.headers.get('x-cron-secret') !== Deno.env.get('CRON_SECRET')) return resp('proibido', 403);
  const montar = { conferencia: montarConferencia, inventario: montarInventario, rendimento: montarRendimento, diesel: montarDiesel }[tipo];
  if (!montar) return resp('tipo desconhecido: ' + tipo, 400);

  let resultado;
  try { resultado = await montar(); } catch (e) { return resp(String((e as Error).message ?? e), 500); }
  return disparar(tipo, resultado);
});
