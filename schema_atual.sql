-- ============================================================
-- STOKK — FOTO DO BANCO (schema "public") em 23/10/2026
-- Reconstruído a partir de consultas ao Supabase em produção (colunas, políticas RLS,
-- chaves, índices e restrições — todos conferidos)
-- porque o schema.sql original e os update_001…006, 009 e 010 foram perdidos.
--
-- ATENÇÃO
--  * É DOCUMENTAÇÃO DE REFERÊNCIA. Não rode em cima do banco que já existe.
--  * Chaves primárias, chaves estrangeiras, checks e índices foram CONFERIDOS no banco em produção.
--    Só os gatilhos não foram listados aqui (estão nos update_008, 012 e 013).
--  * Funções, gatilhos, views do Power BI e permissões NÃO estão aqui: estão nos arquivos
--      update_007_powerbi.sql   (schema bi, usuário powerbi_leitor, views)
--      update_008_seguranca.sql (eh_usuario_ativo, eh_supervisor, proteger_profiles, audit_log)
--      update_011_push.sql      (push_tokens, push_avisos, pg_cron/pg_net)
--      update_012_areas.sql     (areas, area_padrao, area_do_usuario, coluna area)
--      update_013_multiarea.sql (usuario_areas, areas_do_usuario, proteger_area_registro)
--  * Tabelas "_bkp_*" são cópias de segurança feitas pelos update_009 e update_010
--    (conversão de unidade para kg). Podem ser apagadas quando você não precisar mais delas.
-- ============================================================

-- ---------- Base (criadas primeiro: outras tabelas dependem delas) ----------
create table public.areas (
  id text not null check (id ~ '^[a-z0-9_]+$'),   -- 'trefila', 'planta1'
  nome text not null,
  ativa boolean not null default true,
  criada_em timestamptz not null default now(),
  primary key (id)
);

create table public.produtos (                -- compartilhado entre áreas
  codigo text not null,                       -- PK
  descricao text,
  um text,
  tipo text,
  grupo text,
  atualizado_em timestamptz default now(),
  primary key (codigo)
);

-- ---------- Estoque ----------
create table public.volumes (
  lote text not null,                         -- PK; único entre áreas
  produto_codigo text references public.produtos(codigo),
  produto_descricao text,
  armazem text,
  quantidade numeric,                         -- sempre em kg
  saldo_acumulado numeric,
  categoria text,
  tipo_mov text,
  status text default 'estoque',
  origem text,
  status_conferencia text,
  ultima_conferencia_sessao text,
  ultima_conferencia_em timestamptz,
  importado_em timestamptz,
  criado_em timestamptz default now(),
  atualizado_em timestamptz default now(),
  area text not null default public.area_padrao() references public.areas(id),
  primary key (lote)
);
create index volumes_area_idx on public.volumes (area);

create table public.movimentos (
  id text not null,                           -- PK
  lote text,
  produto_codigo text,
  produto_descricao text,
  tipo text,
  quantidade numeric,                         -- kg
  "timestamp" timestamptz default now(),
  exportado boolean default false,
  obs text,
  usuario_id uuid references auth.users(id),
  usuario_nome text,
  area text not null default public.area_padrao() references public.areas(id),
  primary key (id)
);
create index movimentos_area_idx on public.movimentos (area);

-- ---------- Conferência (inventário) ----------
create table public.sessoes (
  id text not null,                           -- PK
  iniciado_em timestamptz,
  ativo boolean,
  contados jsonb,
  filtro_produto text,
  finalizado_em timestamptz,
  resultado jsonb,
  usuario_id uuid references auth.users(id),
  esperados_snapshot jsonb,
  nome text,
  area text not null default public.area_padrao() references public.areas(id),
  primary key (id)
);
create index sessoes_area_idx on public.sessoes (area);

-- ---------- Produção / rendimento metálico ----------
create table public.producoes (
  id text not null,                           -- PK
  equipamento text not null,
  etapa text,
  codigo_produto text,
  consumidos jsonb default '[]'::jsonb,
  produzidos jsonb default '[]'::jsonb,
  iniciado_em timestamptz,
  finalizado_em timestamptz,
  resultado jsonb,
  usuario_id uuid references auth.users(id),
  usuario_nome text,
  turno integer,
  data_producao date,
  area text not null default public.area_padrao() references public.areas(id),
  primary key (id)
);
create index producoes_area_idx on public.producoes (area);

-- ---------- Usuários e áreas ----------
create table public.profiles (
  id uuid not null references auth.users(id) on delete cascade,   -- PK
  nome text not null,
  role text not null default 'operador' check (role in ('operador','supervisor')),
  criado_em timestamptz not null default now(),
  ativo boolean not null default false,       -- conta nova nasce bloqueada
  area text references public.areas(id),     -- área principal
  primary key (id)
);

create table public.usuario_areas (
  user_id uuid not null references public.profiles(id) on delete cascade,
  area text not null references public.areas(id),
  criado_em timestamptz not null default now(),
  primary key (user_id, area)
);

create table public.armazens_area (
  area text not null references public.areas(id),
  armazem text not null,
  descricao text,
  primary key (area, armazem)
);

-- ---------- Auditoria e notificações ----------
create table public.audit_log (
  id bigint generated always as identity,
  em timestamptz not null default now(),
  usuario_id uuid default auth.uid(),
  usuario_nome text,
  tabela text not null,
  operacao text not null,
  chave text,
  antes jsonb,
  depois jsonb,
  primary key (id)
);

create table public.push_tokens (
  token text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  plataforma text,
  atualizado_em timestamptz not null default now(),
  primary key (token)
);
create index push_tokens_user_idx on public.push_tokens (user_id);

create table public.push_avisos (             -- não é mais usada pela função de aviso (v2/v3)
  sessao_id text not null,
  marco_horas integer not null,
  enviado_em timestamptz not null default now(),
  primary key (sessao_id, marco_horas)
);

-- ============================================================
-- POLÍTICAS RLS EM PRODUÇÃO (conferidas em 23/10/2026)
-- Todas para o papel "authenticated". A = areas_do_usuario()
-- ============================================================
-- areas:          select  → eh_usuario_ativo()
-- armazens_area:  select  → area = any(A)
-- audit_log:      select  → eh_supervisor()
-- profiles:       select  → id = auth.uid() OR eh_usuario_ativo()
--                 update  → id = auth.uid()   (role/ativo/area/id protegidos pelo gatilho proteger_profiles)
-- produtos:       select  → eh_usuario_ativo();  insert/update → eh_supervisor()
-- usuario_areas:  select  → user_id = auth.uid()   (sem escrita pelo app)
-- volumes:        select/insert/update → area = any(A);  delete → eh_supervisor() AND area = any(A)
-- sessoes:        select/insert/update → area = any(A);  delete → eh_supervisor() AND area = any(A)
-- producoes:      select/insert/update → area = any(A);  delete → eh_supervisor() AND area = any(A)
-- movimentos:     select → area = any(A);  insert → area = any(A) AND (usuario_id is null OR usuario_id = auth.uid())
--                 (sem update nem delete: o histórico só cresce)
-- Forma obrigatória do filtro:  area = any ((select public.areas_do_usuario())::text[])
-- ============================================================

-- ============================================================
-- PARA LISTAR OS GATILHOS (não conferidos neste arquivo):
--   select tgrelid::regclass as tabela, tgname, pg_get_triggerdef(oid)
--   from pg_trigger where not tgisinternal order by 1, 2;
-- ============================================================
