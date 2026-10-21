// Edge Function de notificações push. Cada TIPO tem o seu próprio agendamento (pg_cron) e chama
// a função com o corpo {"tipo":"conferencia"|"inventario"|"rendimento"}. O horário vem do cron
// (Brasília = UTC-3). Ver docs/deploy.md.
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

Deno.serve(async (req) => {
  if (req.headers.get('x-cron-secret') !== Deno.env.get('CRON_SECRET')) return new Response('proibido', { status: 403 });

  let tipo = 'conferencia'; // sem corpo = comportamento antigo
  try { const b = await req.json(); if (b?.tipo) tipo = String(b.tipo); } catch { /* corpo vazio */ }
  const montar = { conferencia: montarConferencia, inventario: montarInventario, rendimento: montarRendimento }[tipo];
  if (!montar) return new Response('tipo desconhecido: ' + tipo, { status: 400 });

  let resultado;
  try { resultado = await montar(); } catch (e) { return new Response(String((e as Error).message ?? e), { status: 500 }); }
  if (!resultado.msgs.size) return Response.json({ tipo, itens: resultado.total, enviados: 0 });

  let sa: any;
  try { sa = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT') ?? ''); }
  catch { return new Response('Segredo FCM_SERVICE_ACCOUNT inválido: cole o conteúdo inteiro do .json da chave (começa com { e termina com }).', { status: 500 }); }
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
  return Response.json({ tipo, itens: resultado.total, enviados });
});
