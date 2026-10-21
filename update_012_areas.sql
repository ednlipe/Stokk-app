-- ============================================================
-- update_012 — ÁREAS (ambientes separados dentro do mesmo app)
-- Rodar no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Roda tudo em uma transação: se der erro, nada é alterado.
-- Se der "lock timeout": nada foi alterado; rode de novo (de preferência fora do horário de uso).
--
-- O QUE ISTO FAZ
--  1) Cria a tabela "areas" com 2 áreas: Trefila (id 'trefila') e Planta 1 (laminação) (id 'planta1').
--  2) Cada usuário passa a ter UMA área (profiles.area). Quem já está ATIVO hoje fica na Trefilaria.
--     Conta nova nasce SEM área: só vê dados depois que um supervisor define a área.
--  3) volumes, movimentos, sessoes (conferências) e producoes ganham a coluna "area".
--     Tudo que existe hoje fica marcado como Trefilaria. Registro novo recebe a área de quem o criou.
--  4) As regras de acesso (RLS) passam a filtrar por área: cada usuário lê/grava só a SUA área.
--  5) Ninguém muda a própria área pelo app (só pelo painel do Supabase / SQL Editor).
--  6) Cria a tabela "armazens_area" (armazéns de cada área, cadastráveis sem mexer no código).
--  7) As views do Power BI ganham as colunas "area" e "area_nome" (no FIM de cada view).
--     O Power BI continua enxergando TODAS as áreas (usuário powerbi_leitor não passa pela RLS).
--
-- NÃO MUDA: produtos (cadastro compartilhado entre as áreas), a trilha de auditoria e as notificações push
-- (a Edge Function nova separa por área: publique-a DEPOIS de rodar este script).
--
-- LIMITES DESTA VERSÃO (ver docs/banco.md):
--  - O número do lote (volumes.lote) continua único no banco inteiro, mesmo entre áreas.
--  - Nenhum usuário enxerga duas áreas pelo app. Quem precisa ver tudo usa o Power BI.
--
-- DEPOIS DE RODAR: definir a área de cada pessoa da Planta 1 (exemplo no fim deste arquivo).
-- ============================================================

begin;

set local lock_timeout = '8s';
lock table public.profiles, public.volumes, public.movimentos, public.sessoes, public.producoes
  in access exclusive mode;

-- ---------- 1) Áreas ----------
create table if not exists public.areas (
  id text primary key check (id ~ '^[a-z0-9_]+$'),
  nome text not null,
  ativa boolean not null default true,
  criada_em timestamptz not null default now()
);
insert into public.areas (id, nome) values
  ('trefila', 'Trefila'),
  ('planta1', 'Planta 1 (laminação)')
on conflict (id) do nothing;
alter table public.areas enable row level security;

-- ---------- 2) Área do usuário (só na 1ª vez: quem já está ativo vai para a Trefilaria) ----------
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'area'
  ) then
    alter table public.profiles add column area text references public.areas(id);
    update public.profiles set area = 'trefila' where ativo;
  end if;
end $$;

-- ---------- 3) Funções de apoio ----------
-- Área do usuário logado (nula se a conta está bloqueada, sem área ou com a área desativada)
create or replace function public.area_do_usuario()
returns text
language sql stable security definer
set search_path = ''
as $$
  select p.area
  from public.profiles p
  join public.areas a on a.id = p.area
  where p.id = auth.uid() and p.ativo and a.ativa;
$$;

-- Valor padrão da coluna "area" nos registros novos (painel/SQL Editor, sem usuário logado, usam 'trefila')
create or replace function public.area_padrao()
returns text
language sql stable security definer
set search_path = ''
as $$
  select coalesce((select p.area from public.profiles p where p.id = auth.uid()), 'trefila');
$$;

revoke all on function public.area_do_usuario() from public, anon;
revoke all on function public.area_padrao() from public, anon;
grant execute on function public.area_do_usuario() to authenticated;
grant execute on function public.area_padrao() to authenticated;

-- ---------- 4) Coluna "area" nas tabelas de dados ----------
-- (adicionar com valor fixo 'trefila' marca todo o histórico sem reescrever linhas nem disparar gatilhos;
--  depois o padrão passa a ser a área de quem cria o registro)
do $$
declare t text;
begin
  foreach t in array array['volumes', 'movimentos', 'sessoes', 'producoes'] loop
    execute format('alter table public.%I add column if not exists area text not null default %L references public.areas(id)', t, 'trefila');
    execute format('alter table public.%I alter column area set default public.area_padrao()', t);
    execute format('create index if not exists %I on public.%I (area)', t || '_area_idx', t);
  end loop;
end $$;

-- ---------- 5) Ninguém muda role/ativo/id/área pelo app ----------
create or replace function public.proteger_profiles()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is not null then
    if new.role is distinct from old.role
       or new.ativo is distinct from old.ativo
       or new.id is distinct from old.id
       or new.area is distinct from old.area then
      raise exception 'Perfil, ativação e área só podem ser alterados pelo painel do Supabase.' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

-- ---------- 6) Regras de acesso (RLS) por área ----------
do $$
declare r record;
begin
  for r in
    select policyname, tablename from pg_policies
    where schemaname = 'public'
      and tablename in ('volumes', 'movimentos', 'sessoes', 'producoes', 'areas')
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- áreas: contas ativas leem a lista (o app mostra o nome da própria área)
create policy "areas_select" on public.areas for select to authenticated
  using ((select public.eh_usuario_ativo()));

-- volumes
create policy "volumes_select" on public.volumes for select to authenticated using (area = (select public.area_do_usuario()));
create policy "volumes_insert" on public.volumes for insert to authenticated with check (area = (select public.area_do_usuario()));
create policy "volumes_update" on public.volumes for update to authenticated
  using (area = (select public.area_do_usuario())) with check (area = (select public.area_do_usuario()));
create policy "volumes_delete" on public.volumes for delete to authenticated
  using ((select public.eh_supervisor()) and area = (select public.area_do_usuario()));

-- movimentos: histórico só lê e insere; não aceita registro em nome de outra pessoa
create policy "movimentos_select" on public.movimentos for select to authenticated using (area = (select public.area_do_usuario()));
create policy "movimentos_insert" on public.movimentos for insert to authenticated
  with check (area = (select public.area_do_usuario()) and (usuario_id is null or usuario_id = auth.uid()));

-- sessoes (conferências)
create policy "sessoes_select" on public.sessoes for select to authenticated using (area = (select public.area_do_usuario()));
create policy "sessoes_insert" on public.sessoes for insert to authenticated with check (area = (select public.area_do_usuario()));
create policy "sessoes_update" on public.sessoes for update to authenticated
  using (area = (select public.area_do_usuario())) with check (area = (select public.area_do_usuario()));
create policy "sessoes_delete" on public.sessoes for delete to authenticated
  using ((select public.eh_supervisor()) and area = (select public.area_do_usuario()));

-- producoes
create policy "producoes_select" on public.producoes for select to authenticated using (area = (select public.area_do_usuario()));
create policy "producoes_insert" on public.producoes for insert to authenticated with check (area = (select public.area_do_usuario()));
create policy "producoes_update" on public.producoes for update to authenticated
  using (area = (select public.area_do_usuario())) with check (area = (select public.area_do_usuario()));
create policy "producoes_delete" on public.producoes for delete to authenticated
  using ((select public.eh_supervisor()) and area = (select public.area_do_usuario()));

-- permissões de tabela (segunda camada, além da RLS)
revoke all on public.areas from anon, authenticated;
grant select on public.areas to authenticated;

-- ---------- 7) Armazéns de cada área (cadastráveis; o app ainda não usa, serve ao Power BI e à futura integração) ----------
create table if not exists public.armazens_area (
  area text not null references public.areas(id),
  armazem text not null,
  descricao text,
  primary key (area, armazem)
);
alter table public.armazens_area enable row level security;
drop policy if exists "armazens_area_select" on public.armazens_area;
create policy "armazens_area_select" on public.armazens_area for select to authenticated
  using (area = (select public.area_do_usuario()));
revoke all on public.armazens_area from anon, authenticated;
grant select on public.armazens_area to authenticated;
-- armazéns que já aparecem no estoque da Trefilaria (os da Planta 1 serão cadastrados quando forem definidos)
insert into public.armazens_area (area, armazem) values
  ('trefila', '44'), ('trefila', '61'), ('trefila', '02'), ('trefila', '55'), ('trefila', '93'), ('trefila', '03')
on conflict (area, armazem) do nothing;

-- ---------- 8) Views do Power BI: colunas novas "area" e "area_nome" no FIM ----------
create or replace view bi.estoque as
select
  v.lote,
  v.produto_codigo,
  coalesce(p.descricao, v.produto_descricao) as produto_descricao,
  p.grupo                                   as produto_grupo,
  v.armazem,
  v.categoria,
  round(v.quantidade / 1000.0, 3)           as quantidade_ton,
  round(v.quantidade, 1)                    as quantidade_kg,
  coalesce(v.status, 'estoque')             as status,
  case v.status_conferencia
    when 'contado'       then 'Em estoque (contado)'
    when 'nao_conferido' then 'Não localizado'
    else 'Aguardando conferência'
  end                                       as situacao_conferencia,
  v.origem,
  (v.importado_em        at time zone 'America/Sao_Paulo') as importado_em,
  (v.ultima_conferencia_em at time zone 'America/Sao_Paulo') as ultima_conferencia_em,
  (v.atualizado_em       at time zone 'America/Sao_Paulo') as atualizado_em,
  v.area,
  ar.nome                                   as area_nome
from public.volumes v
left join public.produtos p on p.codigo = v.produto_codigo
left join public.areas ar on ar.id = v.area;

create or replace view bi.movimentos as
select
  m.id,
  m.lote,
  m.produto_codigo,
  m.produto_descricao,
  m.tipo,
  m.quantidade,
  (m.timestamp at time zone 'America/Sao_Paulo')       as data_hora,
  (m.timestamp at time zone 'America/Sao_Paulo')::date as data,
  m.obs,
  m.usuario_nome,
  m.area,
  ar.nome                                              as area_nome
from public.movimentos m
left join public.areas ar on ar.id = m.area;

create or replace view bi.conferencias as
select
  s.id,
  coalesce(nullif(trim(s.nome), ''), 'Sem nome')       as nome,
  (s.iniciado_em  at time zone 'America/Sao_Paulo')    as iniciado_em,
  (s.finalizado_em at time zone 'America/Sao_Paulo')   as finalizado_em,
  case when s.ativo then 'Em andamento' else 'Finalizada' end as situacao,
  s.filtro_produto,
  case when jsonb_typeof(s.contados) = 'array'
       then jsonb_array_length(s.contados) else 0 end as itens_contados,
  case when jsonb_typeof(s.esperados_snapshot) = 'array'
       then jsonb_array_length(s.esperados_snapshot) else 0 end as itens_esperados,
  case when jsonb_typeof(s.resultado -> 'faltando') = 'array'
       then jsonb_array_length(s.resultado -> 'faltando') else 0 end as itens_faltando,
  s.area,
  ar.nome                                              as area_nome
from public.sessoes s
left join public.areas ar on ar.id = s.area;

create or replace view bi.producoes as
with base as (
  select
    p.*,
    (coalesce(p.finalizado_em, p.iniciado_em) at time zone 'America/Sao_Paulo') as ts_local
  from public.producoes p
), calc as (
  select
    b.*,
    extract(hour from b.ts_local) * 60 + extract(minute from b.ts_local) as minutos,
    coalesce(
      case when b.turno between 1 and 3 then b.turno end,
      case
        when extract(hour from b.ts_local) * 60 + extract(minute from b.ts_local) >= 430
         and extract(hour from b.ts_local) * 60 + extract(minute from b.ts_local) <  910 then 1
        when extract(hour from b.ts_local) * 60 + extract(minute from b.ts_local) >= 910
         and extract(hour from b.ts_local) * 60 + extract(minute from b.ts_local) < 1390 then 2
        else 3
      end
    ) as turno_calc
  from base b
)
select
  c.id,
  c.equipamento,
  c.etapa,
  c.codigo_produto,
  c.turno_calc                                         as turno,
  coalesce(
    c.data_producao,
    case when c.turno_calc = 3 and c.minutos < 430
         then (c.ts_local::date - 1) else c.ts_local::date end
  )                                                    as data_producao,
  (c.iniciado_em  at time zone 'America/Sao_Paulo')    as iniciado_em,
  (c.finalizado_em at time zone 'America/Sao_Paulo')   as finalizado_em,
  (c.resultado ->> 'consumidoKg')::numeric             as consumido_kg,
  (c.resultado ->> 'produzidoKg')::numeric             as produzido_kg,
  (c.resultado ->> 'consumidoKg')::numeric
    - (c.resultado ->> 'produzidoKg')::numeric         as perda_kg,
  round( (c.resultado ->> 'produzidoKg')::numeric
         / nullif((c.resultado ->> 'consumidoKg')::numeric, 0) * 100, 2 ) as rendimento_pct,
  case when jsonb_typeof(c.consumidos) = 'array' then jsonb_array_length(c.consumidos) else 0 end as qtd_consumidos,
  case when jsonb_typeof(c.produzidos) = 'array' then jsonb_array_length(c.produzidos) else 0 end as qtd_produzidos,
  c.usuario_nome,
  c.area,
  ar.nome                                              as area_nome
from calc c
left join public.areas ar on ar.id = c.area;

create or replace view bi.producao_itens as
select
  pr.id                                  as producao_id,
  pr.equipamento,
  pr.turno,
  pr.data_producao,
  pr.etapa,
  x.lado,
  x.item ->> 'lote'                      as lote,
  x.item ->> 'corrida'                   as corrida,
  (x.item ->> 'pesoKg')::numeric         as peso_kg,
  x.item ->> 'produtoCodigo'             as produto_codigo,
  x.item ->> 'produtoDescricao'          as produto_descricao,
  coalesce((x.item ->> 'manual')::boolean, false)     as digitado_manual,
  coalesce((x.item ->> 'divergente')::boolean, false) as produto_divergente,
  pr.area,
  pr.area_nome
from bi.producoes pr
join public.producoes raw on raw.id = pr.id
cross join lateral (
  select 'Consumido' as lado, i as item
    from jsonb_array_elements(case when jsonb_typeof(raw.consumidos) = 'array' then raw.consumidos else '[]'::jsonb end) i
  union all
  select 'Produzido', i
    from jsonb_array_elements(case when jsonb_typeof(raw.produzidos) = 'array' then raw.produzidos else '[]'::jsonb end) i
) x;

-- O rendimento é SEMPRE soma produzida ÷ soma consumida (nunca média de %). Agora também por área.
create or replace view bi.rendimento_turno as
select
  data_producao,
  equipamento,
  turno,
  count(*)                                   as qtd_producoes,
  sum(consumido_kg)                          as consumido_kg,
  sum(produzido_kg)                          as produzido_kg,
  sum(consumido_kg) - sum(produzido_kg)      as perda_kg,
  round(sum(produzido_kg) / nullif(sum(consumido_kg), 0) * 100, 2) as rendimento_pct,
  case
    when round(sum(produzido_kg) / nullif(sum(consumido_kg), 0) * 100, 1) >= 99 then 'Verde'
    when round(sum(produzido_kg) / nullif(sum(consumido_kg), 0) * 100, 1) >= 98 then 'Amarelo'
    else 'Vermelho'
  end                                        as faixa,
  area,
  area_nome
from bi.producoes
where etapa = 'finalizada' and consumido_kg > 0
group by data_producao, equipamento, turno, area, area_nome;

-- listas de apoio para o Power BI
create or replace view bi.areas as
select id as area, nome as area_nome, ativa from public.areas;

create or replace view bi.armazens_area as
select a.area, ar.nome as area_nome, a.armazem, a.descricao
from public.armazens_area a
join public.areas ar on ar.id = a.area;

-- garante leitura das views novas pelo usuário do Power BI (se ele já existe)
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'powerbi_leitor') then
    grant usage on schema bi to powerbi_leitor;
    grant select on all tables in schema bi to powerbi_leitor;
  end if;
end $$;

commit;

-- ============================================================
-- COMO DEFINIR A ÁREA DE UMA PESSOA (SQL Editor, depois de criar/ativar a conta):
--   update public.profiles set area = 'planta1' where id = '<ID DO USUÁRIO>';
--   (ou Table Editor › profiles › coluna "area" = trefila / planta1)
-- Para listar quem está em cada área:
--   select p.nome, p.role, p.ativo, p.area from public.profiles p order by p.area, p.nome;
-- Para criar uma nova área no futuro:
--   insert into public.areas (id, nome) values ('nova_area', 'Nome da área');
--
-- DESFAZER (se precisar, antes de a Planta 1 ter dados): as colunas "area" podem ficar; para voltar às regras
-- antigas rode de novo o bloco 5) do update_008_seguranca.sql (regras de acesso sem filtro de área) e
-- recrie as views do update_007/update_009 sem as colunas area/area_nome.
-- ============================================================
