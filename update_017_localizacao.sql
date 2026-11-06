-- ============================================================
-- update_017 — GESTÃO / LOCALIZAÇÃO DOS EQUIPAMENTOS + CORREÇÃO DE OCORRÊNCIA EM ABERTO
-- Rodar no SQL Editor do Supabase DEPOIS do update_016. Pode rodar mais de uma vez.
-- Roda tudo em uma transação: se der erro, nada é alterado.
--
-- O QUE ISTO FAZ
--  1) Cria a tabela equipamento_locais: cada linha é "o equipamento X está em tal lugar, a partir de tal data e hora".
--       - qualquer pessoa ativa da área Gestão registra (texto livre + observação opcional);
--       - o local atual de um equipamento é o último registro válido; os anteriores formam o histórico;
--       - ninguém apaga nem edita: o supervisor ANULA (com motivo), igual ao diesel.
--  2) Ocorrência em ABERTO pode ser corrigida pelo supervisor (categoria, motivo, descrição): o gatilho grava
--     editada_em / editada_por. Depois de liberada ou anulada continua sem mudar.
--  3) RLS por área, Realtime ligado e views para o Power BI:
--       bi.equipamento_locais (histórico) e bi.equipamento_local_atual (onde cada equipamento está agora).
--
-- NÃO MUDA: update_015 (diesel) e a regra de liberação do update_016.
-- ============================================================

begin;

set local lock_timeout = '8s';

-- ---------- 1) Localização ----------
create table if not exists public.equipamento_locais (
  id text primary key,
  equipamento_id text not null references public.equipamentos(id),
  equipamento_codigo text,                                   -- cópia do código na hora do lançamento
  local text not null check (btrim(local) <> '' and char_length(local) <= 120),
  obs text,
  data_hora timestamptz not null default now(),              -- desde quando está nesse local
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
create index if not exists equipamento_locais_equip_idx on public.equipamento_locais (equipamento_id, data_hora);
create index if not exists equipamento_locais_area_idx on public.equipamento_locais (area);

-- mesma trava de anulação do diesel (update_015): só muda anulado/motivo, exige motivo, grava quem e quando
do $$
begin
  drop trigger if exists trg_diesel_anulacao on public.equipamento_locais;
  create trigger trg_diesel_anulacao before update on public.equipamento_locais
    for each row execute function public.diesel_proteger_anulacao();
  drop trigger if exists trg_proteger_area on public.equipamento_locais;
  create trigger trg_proteger_area before update on public.equipamento_locais
    for each row execute function public.proteger_area_registro();
end $$;

alter table public.equipamento_locais enable row level security;
do $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname = 'public' and tablename = 'equipamento_locais' loop
    execute format('drop policy if exists %I on public.equipamento_locais', r.policyname);
  end loop;
end $$;
revoke all on public.equipamento_locais from anon, authenticated;

create policy "equipamento_locais_select" on public.equipamento_locais for select to authenticated
  using (area = any ((select public.areas_do_usuario())::text[]));
create policy "equipamento_locais_insert" on public.equipamento_locais for insert to authenticated
  with check (area = any ((select public.areas_do_usuario())::text[]) and (usuario_id is null or usuario_id = auth.uid()) and not anulado);
create policy "equipamento_locais_update" on public.equipamento_locais for update to authenticated
  using ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]))
  with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));

grant select, insert on public.equipamento_locais to authenticated;
grant update (anulado, anulado_motivo) on public.equipamento_locais to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'equipamento_locais') then
    alter publication supabase_realtime add table public.equipamento_locais;
  end if;
end $$;

-- ---------- 2) Corrigir ocorrência em aberto (supervisor) ----------
alter table public.ocorrencias add column if not exists editada_em timestamptz;
alter table public.ocorrencias add column if not exists editada_por uuid references auth.users(id);

create or replace function public.ocorrencia_proteger()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- a Edge Function (service_role) só marca "aviso enviado": isso pode acontecer mesmo depois de liberada/anulada
  if (to_jsonb(new) - 'aviso_abertura_em' - 'aviso_liberacao_em') = (to_jsonb(old) - 'aviso_abertura_em' - 'aviso_liberacao_em') then
    return new;
  end if;

  if old.anulado then
    raise exception 'Esta ocorrência já foi anulada e não pode mais ser alterada.' using errcode = '42501';
  end if;

  if new.anulado is true then
    -- anulação: exige motivo, grava quem/quando e não deixa mexer em mais nada
    if coalesce(btrim(new.anulado_motivo), '') = '' then
      raise exception 'Informe o motivo da anulação.' using errcode = '23514';
    end if;
    new.categoria := old.categoria; new.motivo := old.motivo; new.descricao := old.descricao;
    new.editada_em := old.editada_em; new.editada_por := old.editada_por;
    new.liberada_em := old.liberada_em; new.liberada_registro_em := old.liberada_registro_em;
    new.liberada_por := old.liberada_por; new.liberada_por_nome := old.liberada_por_nome;
    new.motivo_liberacao := old.motivo_liberacao; new.servico_realizado := old.servico_realizado; new.recebido_por := old.recebido_por;
    new.anulado_por := auth.uid(); new.anulado_em := now();
    return new;
  end if;

  if old.liberada_em is not null then
    raise exception 'Esta ocorrência já foi liberada e não pode mais ser alterada. Para corrigir, anule e abra de novo.' using errcode = '42501';
  end if;

  if new.liberada_em is null then
    -- correção da ocorrência ainda em aberto: só categoria, motivo e descrição
    if coalesce(btrim(new.motivo), '') = '' then
      raise exception 'Informe o motivo.' using errcode = '23514';
    end if;
    if coalesce(btrim(new.descricao), '') = '' then
      raise exception 'Descreva o que está acontecendo.' using errcode = '23514';
    end if;
    new.liberada_por_nome := old.liberada_por_nome; new.motivo_liberacao := old.motivo_liberacao;
    new.servico_realizado := old.servico_realizado; new.recebido_por := old.recebido_por;
    new.editada_em := now(); new.editada_por := auth.uid();
    return new;
  end if;

  if new.liberada_em > now() + interval '1 hour' then
    raise exception 'A liberação não pode estar no futuro.' using errcode = '23514';
  end if;
  if new.liberada_em < old.aberta_em then
    raise exception 'A liberação não pode ser antes da abertura (%).', to_char(old.aberta_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') using errcode = '23514';
  end if;
  if coalesce(btrim(new.servico_realizado), '') = '' then
    raise exception 'Informe o que foi feito no equipamento.' using errcode = '23514';
  end if;
  if coalesce(btrim(new.recebido_por), '') = '' then
    raise exception 'Informe quem pegou o equipamento.' using errcode = '23514';
  end if;
  if coalesce(btrim(new.motivo_liberacao), '') = '' then
    raise exception 'Informe o motivo da liberação.' using errcode = '23514';
  end if;
  new.liberada_registro_em := now();
  new.liberada_por := auth.uid();
  return new;
end;
$$;

grant update (categoria, motivo, descricao) on public.ocorrencias to authenticated;

-- ---------- 3) Power BI ----------
create or replace view bi.equipamento_locais as
select
  l.id,
  e.codigo as equipamento,
  e.nome   as equipamento_nome,
  l.local,
  l.obs,
  (l.data_hora at time zone 'America/Sao_Paulo') as desde,
  l.usuario_nome
from public.equipamento_locais l
join public.equipamentos e on e.id = l.equipamento_id
where not l.anulado;

create or replace view bi.equipamento_local_atual as
select distinct on (l.equipamento_id)
  e.codigo as equipamento,
  e.nome   as equipamento_nome,
  l.local,
  l.obs,
  (l.data_hora at time zone 'America/Sao_Paulo') as desde,
  l.usuario_nome
from public.equipamento_locais l
join public.equipamentos e on e.id = l.equipamento_id
where not l.anulado
order by l.equipamento_id, l.data_hora desc, l."timestamp" desc;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'powerbi_leitor') then
    grant usage on schema bi to powerbi_leitor;
    grant select on all tables in schema bi to powerbi_leitor;
  end if;
end $$;

commit;

-- ============================================================
-- DESFAZER (antes de haver registros): drop view bi.equipamento_local_atual, bi.equipamento_locais;
--   drop table public.equipamento_locais cascade;
-- (a correção de ocorrência em aberto some ao rodar de novo o update_016, que recria o gatilho antigo)
-- ============================================================
