-- ============================================================
-- update_015 — GESTÃO / DIESEL (ambiente "Gestão": equipamentos, tanque, compras e abastecimentos)
-- Rodar no SQL Editor do Supabase DEPOIS do update_014. Pode rodar mais de uma vez.
-- Roda tudo em uma transação: se der erro, nada é alterado.
--
-- O QUE ISTO FAZ
--  1) Cria a área 'gestao' (nome "Gestão") na tabela areas. Ela aparece para a pessoa só depois que o
--     supervisor a incluir em usuario_areas (exemplo no fim deste arquivo).
--  2) Cria 5 tabelas, todas com a coluna "area" e RLS por área (mesmo filtro das demais):
--       equipamentos     máquinas e caminhão (medem em horas "h" ou quilômetros "km")
--       tanques          tanque de diesel da empresa (capacidade e saldo mínimo)
--       tanque_entradas  compras / descargas de diesel no tanque (litros, preço, fornecedor, nota)
--       abastecimentos   saídas: diesel colocado em cada equipamento (horímetro/km, litros, custo do dia)
--       tanque_medicoes  conferência com a régua do tanque (litros medidos x saldo do app; ajuste opcional)
--  3) Quem pode o quê (tudo também protegido no banco, não só na tela):
--       abastecimentos   qualquer pessoa ATIVA da área Gestão lê e registra
--       demais tabelas   todos da área leem; só SUPERVISOR cadastra/registra
--       ninguém apaga nada: um lançamento errado é ANULADO (supervisor, com motivo), e o original fica guardado
--  4) Trava no banco: o horímetro/km de um equipamento não pode diminuir (a não ser que seja marcada
--     "troca de medidor"). Litros e valores não aceitam número negativo.
--  5) Entra na publicação do Realtime (a tela atualiza sozinha) e ganha views para o Power BI (schema bi).
--
-- NÃO MUDA: estoque, conferências, produção, movimentos e as áreas Trefila / Planta 1.
-- O saldo do tanque e o custo médio NÃO ficam gravados: são calculados pelo app a partir das entradas,
-- abastecimentos e ajustes (docs/regras-de-negocio.md, seção Diesel). Cada abastecimento guarda o
-- "custo_litro" do momento, para o histórico de gasto não mudar quando o preço do diesel mudar.
-- ============================================================

begin;

set local lock_timeout = '8s';

-- ---------- 1) Área Gestão ----------
insert into public.areas (id, nome) values ('gestao', 'Gestão')
on conflict (id) do nothing;

-- ---------- 2) Tabelas ----------
create table if not exists public.equipamentos (
  id text primary key,
  codigo text not null,                                   -- ex.: PC01, EMP02, CAM01
  nome text not null,
  tipo text not null default 'maquina' check (tipo in ('maquina', 'caminhao', 'outro')),
  medidor text not null default 'h' check (medidor in ('h', 'km')),   -- h = horímetro, km = odômetro
  area_uso text[] not null default '{}',                  -- áreas atendidas: trefila, planta1 (vazio = não informado)
  dias_alerta integer not null default 2 check (dias_alerta between 1 and 60),   -- avisa se passar disto sem abastecer
  alerta_dias_uteis boolean not null default false,       -- true = conta só segunda a sexta
  alerta_ativo boolean not null default true,             -- false = equipamento parado de propósito (sem aviso)
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  usuario_id uuid references auth.users(id),
  usuario_nome text,
  area text not null default 'gestao' references public.areas(id)
);
create unique index if not exists equipamentos_codigo_uk on public.equipamentos (area, upper(codigo));
create index if not exists equipamentos_area_idx on public.equipamentos (area);

create table if not exists public.tanques (
  id text primary key,
  nome text not null,
  capacidade_l numeric check (capacidade_l is null or capacidade_l > 0),
  minimo_l numeric check (minimo_l is null or minimo_l >= 0),   -- avisa/destaca quando o saldo ficar abaixo
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  usuario_id uuid references auth.users(id),
  usuario_nome text,
  area text not null default 'gestao' references public.areas(id)
);
create index if not exists tanques_area_idx on public.tanques (area);

create table if not exists public.tanque_entradas (
  id text primary key,
  tanque_id text not null references public.tanques(id),
  data_hora timestamptz not null default now(),
  litros numeric not null check (litros > 0),
  preco_litro numeric not null check (preco_litro >= 0),
  valor_total numeric not null check (valor_total >= 0),
  fornecedor text,
  nota text,
  obs text,
  usuario_id uuid references auth.users(id),
  usuario_nome text,
  "timestamp" timestamptz not null default now(),
  anulado boolean not null default false,
  anulado_motivo text,
  anulado_por uuid references auth.users(id),
  anulado_em timestamptz,
  area text not null default 'gestao' references public.areas(id),
  check (data_hora <= now() + interval '1 hour')
);
create index if not exists tanque_entradas_tanque_idx on public.tanque_entradas (tanque_id, data_hora);
create index if not exists tanque_entradas_area_idx on public.tanque_entradas (area);

create table if not exists public.abastecimentos (
  id text primary key,
  equipamento_id text not null references public.equipamentos(id),
  equipamento_codigo text,                                 -- cópia do código na hora do lançamento
  tanque_id text not null references public.tanques(id),
  data_hora timestamptz not null default now(),
  medidor numeric not null check (medidor >= 0),           -- horímetro (h) ou odômetro (km) lido no equipamento
  litros numeric not null check (litros > 0),
  custo_litro numeric check (custo_litro is null or custo_litro >= 0),   -- custo médio do tanque no momento (nulo = sem compra registrada)
  custo_total numeric check (custo_total is null or custo_total >= 0),
  troca_medidor boolean not null default false,            -- true = medidor foi trocado/zerado: não gera consumo nem erro
  obs text,
  usuario_id uuid references auth.users(id),
  usuario_nome text,
  "timestamp" timestamptz not null default now(),
  anulado boolean not null default false,
  anulado_motivo text,
  anulado_por uuid references auth.users(id),
  anulado_em timestamptz,
  area text not null default 'gestao' references public.areas(id),
  check (data_hora <= now() + interval '1 hour')
);
create index if not exists abastecimentos_equip_idx on public.abastecimentos (equipamento_id, data_hora);
create index if not exists abastecimentos_tanque_idx on public.abastecimentos (tanque_id, data_hora);
create index if not exists abastecimentos_area_idx on public.abastecimentos (area);

create table if not exists public.tanque_medicoes (
  id text primary key,
  tanque_id text not null references public.tanques(id),
  data_hora timestamptz not null default now(),
  litros_medidos numeric not null check (litros_medidos >= 0),   -- o que a régua / medidor mostrou
  saldo_app numeric not null,                                    -- saldo que o app calculava na hora
  diferenca numeric not null,                                    -- medido - saldo do app (negativo = faltou diesel)
  ajustar boolean not null default false,                        -- true = a diferença passa a valer no saldo
  obs text,
  usuario_id uuid references auth.users(id),
  usuario_nome text,
  "timestamp" timestamptz not null default now(),
  anulado boolean not null default false,
  anulado_motivo text,
  anulado_por uuid references auth.users(id),
  anulado_em timestamptz,
  area text not null default 'gestao' references public.areas(id),
  check (data_hora <= now() + interval '1 hour')
);
create index if not exists tanque_medicoes_tanque_idx on public.tanque_medicoes (tanque_id, data_hora);
create index if not exists tanque_medicoes_area_idx on public.tanque_medicoes (area);

-- ---------- 3) Travas (gatilhos) ----------
-- 3a) Anulação: só muda anulado/motivo; não volta atrás; grava quem e quando; exige motivo
create or replace function public.diesel_proteger_anulacao()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.anulado then
    raise exception 'Este lançamento já foi anulado e não pode mais ser alterado.' using errcode = '42501';
  end if;
  if new.anulado is not true then
    raise exception 'Lançamentos não são editados: para corrigir, anule e lance de novo.' using errcode = '42501';
  end if;
  if coalesce(btrim(new.anulado_motivo), '') = '' then
    raise exception 'Informe o motivo da anulação.' using errcode = '23514';
  end if;
  new.anulado_por := auth.uid();
  new.anulado_em := now();
  return new;
end;
$$;

-- 3b) Abastecimento: horímetro/km não pode diminuir (salvo troca de medidor)
create or replace function public.diesel_validar_abastecimento()
returns trigger
language plpgsql
set search_path = ''
as $$
declare ant numeric;
begin
  if not new.troca_medidor then
    select a.medidor into ant
    from public.abastecimentos a
    where a.equipamento_id = new.equipamento_id and not a.anulado and a.data_hora <= new.data_hora
    order by a.data_hora desc, a."timestamp" desc
    limit 1;
    if ant is not null and new.medidor < ant then
      raise exception 'O medidor (%) é menor que o do abastecimento anterior (%). Confira, ou marque "troca de medidor".', new.medidor, ant
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

-- 3c) Registro não muda de área (mesma regra do estoque)
do $$
declare t text;
begin
  foreach t in array array['equipamentos', 'tanques', 'tanque_entradas', 'abastecimentos', 'tanque_medicoes'] loop
    execute format('drop trigger if exists trg_proteger_area on public.%I', t);
    execute format('create trigger trg_proteger_area before update on public.%I for each row execute function public.proteger_area_registro()', t);
  end loop;
  foreach t in array array['tanque_entradas', 'abastecimentos', 'tanque_medicoes'] loop
    execute format('drop trigger if exists trg_diesel_anulacao on public.%I', t);
    execute format('create trigger trg_diesel_anulacao before update on public.%I for each row execute function public.diesel_proteger_anulacao()', t);
  end loop;
end $$;

drop trigger if exists trg_diesel_validar on public.abastecimentos;
create trigger trg_diesel_validar before insert on public.abastecimentos
  for each row execute function public.diesel_validar_abastecimento();

-- ---------- 4) Acesso (RLS) e permissões de coluna ----------
do $$
declare t text; r record;
begin
  foreach t in array array['equipamentos', 'tanques', 'tanque_entradas', 'abastecimentos', 'tanque_medicoes'] loop
    execute format('alter table public.%I enable row level security', t);
    for r in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy if exists %I on public.%I', r.policyname, t);
    end loop;
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('create policy %I on public.%I for select to authenticated using (area = any ((select public.areas_do_usuario())::text[]))', t || '_select', t);
  end loop;
end $$;

-- cadastros: supervisor cria e altera (nunca apaga; desativa com ativo = false)
create policy "equipamentos_insert" on public.equipamentos for insert to authenticated
  with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));
create policy "equipamentos_update" on public.equipamentos for update to authenticated
  using ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]))
  with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));
create policy "tanques_insert" on public.tanques for insert to authenticated
  with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));
create policy "tanques_update" on public.tanques for update to authenticated
  using ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]))
  with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));
grant select, insert on public.equipamentos, public.tanques to authenticated;
grant update (codigo, nome, tipo, medidor, area_uso, dias_alerta, alerta_dias_uteis, alerta_ativo, ativo) on public.equipamentos to authenticated;
grant update (nome, capacidade_l, minimo_l, ativo) on public.tanques to authenticated;

-- compras e medições: só supervisor registra; anulação só supervisor
create policy "tanque_entradas_insert" on public.tanque_entradas for insert to authenticated
  with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[])
              and (usuario_id is null or usuario_id = auth.uid()));
create policy "tanque_entradas_update" on public.tanque_entradas for update to authenticated
  using ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]))
  with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));
create policy "tanque_medicoes_insert" on public.tanque_medicoes for insert to authenticated
  with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[])
              and (usuario_id is null or usuario_id = auth.uid()));
create policy "tanque_medicoes_update" on public.tanque_medicoes for update to authenticated
  using ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]))
  with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));

-- abastecimentos: qualquer pessoa ativa da área registra; anulação só supervisor
create policy "abastecimentos_insert" on public.abastecimentos for insert to authenticated
  with check (area = any ((select public.areas_do_usuario())::text[]) and (usuario_id is null or usuario_id = auth.uid()));
create policy "abastecimentos_update" on public.abastecimentos for update to authenticated
  using ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]))
  with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));

grant select, insert on public.tanque_entradas, public.abastecimentos, public.tanque_medicoes to authenticated;
grant update (anulado, anulado_motivo) on public.tanque_entradas, public.abastecimentos, public.tanque_medicoes to authenticated;

-- ---------- 5) Realtime ----------
do $$
declare t text;
begin
  foreach t in array array['equipamentos', 'tanques', 'tanque_entradas', 'abastecimentos', 'tanque_medicoes'] loop
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------- 6) Power BI (só lançamentos válidos; horário de Brasília) ----------
create or replace view bi.diesel_abastecimentos as
select
  a.id,
  (a.data_hora at time zone 'America/Sao_Paulo') as data_hora,
  e.codigo as equipamento,
  e.nome   as equipamento_nome,
  e.tipo   as equipamento_tipo,
  e.medidor as unidade_medidor,
  a.medidor as leitura_medidor,
  a.litros,
  a.custo_litro,
  a.custo_total,
  a.troca_medidor,
  t.nome as tanque,
  a.usuario_nome,
  a.obs
from public.abastecimentos a
join public.equipamentos e on e.id = a.equipamento_id
join public.tanques t on t.id = a.tanque_id
where not a.anulado;

create or replace view bi.diesel_entradas as
select
  x.id,
  (x.data_hora at time zone 'America/Sao_Paulo') as data_hora,
  t.nome as tanque,
  x.litros,
  x.preco_litro,
  x.valor_total,
  x.fornecedor,
  x.nota,
  x.usuario_nome
from public.tanque_entradas x
join public.tanques t on t.id = x.tanque_id
where not x.anulado;

create or replace view bi.diesel_equipamentos as
select codigo as equipamento, nome, tipo, medidor as unidade_medidor, area_uso, ativo from public.equipamentos;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'powerbi_leitor') then
    grant usage on schema bi to powerbi_leitor;
    grant select on all tables in schema bi to powerbi_leitor;
  end if;
end $$;

commit;

-- ============================================================
-- DEPOIS DE RODAR — liberar a área Gestão para as pessoas (SQL Editor):
--   insert into public.usuario_areas (user_id, area)
--   select id, 'gestao' from public.profiles where nome = '<NOME DA PESSOA>' and ativo
--   on conflict do nothing;
-- (a pessoa passa a escolher entre as áreas dela ao entrar; o perfil supervisor/operador vale para todas as áreas)
-- Para ver quem está na Gestão:
--   select p.nome, p.role from public.usuario_areas ua join public.profiles p on p.id = ua.user_id where ua.area = 'gestao';
--
-- DESFAZER (antes de haver lançamentos): drop table public.abastecimentos, public.tanque_medicoes,
--   public.tanque_entradas, public.tanques, public.equipamentos cascade;  e as 3 views bi.diesel_*.
-- ============================================================
