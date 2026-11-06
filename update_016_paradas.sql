-- ============================================================
-- update_016 — GESTÃO / PARADAS E MANUTENÇÃO (ocorrências de equipamento)
-- Rodar no SQL Editor do Supabase DEPOIS do update_015. Pode rodar mais de uma vez.
-- Roda tudo em uma transação: se der erro, nada é alterado.
--
-- O QUE ISTO FAZ
--  1) Cria a tabela ocorrencias: cada linha é uma parada ou manutenção de um equipamento.
--       ABERTURA  (qualquer pessoa ativa da área Gestão): equipamento, categoria (manutenção ou parada operacional),
--                 motivo, descrição, data/hora e quem abriu. Fica "em aberto" enquanto liberada_em for nulo.
--       LIBERAÇÃO (só supervisor, na MESMA linha): data/hora, motivo da liberação, o que foi feito (serviço),
--                 quem pegou o equipamento e quem registrou a liberação.
--  2) Regras travadas no banco (não só na tela):
--       - um equipamento só pode ter UMA ocorrência em aberto por vez;
--       - a liberação não pode ser anterior à abertura nem estar no futuro, e exige o serviço feito e quem pegou;
--       - depois de liberada, a ocorrência não muda mais; ninguém apaga nada: o supervisor ANULA (com motivo),
--         e o original fica guardado.
--  3) RLS por área (mesmo filtro das demais tabelas) e Realtime ligado.
--  4) View bi.manutencao_ocorrencias para o Power BI (duração em horas, só ocorrências válidas).
--  5) Colunas aviso_abertura_em / aviso_liberacao_em: a Edge Function marca quando o aviso push foi enviado
--     (evita aviso repetido); o app não consegue alterá-las.
--
-- NÃO MUDA: update_015 (diesel), estoque, conferências, produção e as outras áreas.
-- ============================================================

begin;

set local lock_timeout = '8s';

create table if not exists public.ocorrencias (
  id text primary key,
  equipamento_id text not null references public.equipamentos(id),
  equipamento_codigo text,                                  -- cópia do código na hora da abertura
  categoria text not null check (categoria in ('manutencao', 'parada')),
  motivo text not null check (btrim(motivo) <> ''),          -- um item da lista do app (ex.: "Quebra / defeito", "Falta de operador")
  descricao text not null check (btrim(descricao) <> ''),    -- o que está acontecendo
  aberta_em timestamptz not null default now(),
  aberta_por uuid references auth.users(id),
  aberta_por_nome text,
  -- liberação (preenchida uma vez, pelo supervisor)
  liberada_em timestamptz,
  liberada_registro_em timestamptz,                         -- quando a liberação foi gravada (o gatilho preenche)
  liberada_por uuid references auth.users(id),              -- quem registrou (o gatilho preenche)
  liberada_por_nome text,
  motivo_liberacao text,                                    -- por que foi liberado (ex.: "Reparo concluído")
  servico_realizado text,                                   -- o que foi feito no equipamento
  recebido_por text,                                        -- quem pegou o equipamento de volta
  -- avisos push (só a Edge Function grava)
  aviso_abertura_em timestamptz,
  aviso_liberacao_em timestamptz,
  criado_em timestamptz not null default now(),
  -- anulação
  anulado boolean not null default false,
  anulado_motivo text,
  anulado_por uuid references auth.users(id),
  anulado_em timestamptz,
  area text not null default 'gestao' references public.areas(id),
  check (aberta_em <= now() + interval '1 hour'),
  check (liberada_em is null or liberada_em >= aberta_em),
  check (liberada_em is null or (btrim(coalesce(servico_realizado, '')) <> '' and btrim(coalesce(recebido_por, '')) <> '' and btrim(coalesce(motivo_liberacao, '')) <> ''))
);
create index if not exists ocorrencias_equip_idx on public.ocorrencias (equipamento_id, aberta_em);
create index if not exists ocorrencias_area_idx on public.ocorrencias (area);
-- só uma ocorrência em aberto por equipamento
create unique index if not exists ocorrencias_uma_aberta_uk on public.ocorrencias (equipamento_id)
  where liberada_em is null and not anulado;

-- ---------- Travas (gatilho de atualização) ----------
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
    raise exception 'Informe a data e a hora da liberação.' using errcode = '23514';
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

do $$
begin
  drop trigger if exists trg_ocorrencia_proteger on public.ocorrencias;
  create trigger trg_ocorrencia_proteger before update on public.ocorrencias
    for each row execute function public.ocorrencia_proteger();
  drop trigger if exists trg_proteger_area on public.ocorrencias;
  create trigger trg_proteger_area before update on public.ocorrencias
    for each row execute function public.proteger_area_registro();
end $$;

-- ---------- Acesso (RLS) e permissões de coluna ----------
alter table public.ocorrencias enable row level security;
do $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname = 'public' and tablename = 'ocorrencias' loop
    execute format('drop policy if exists %I on public.ocorrencias', r.policyname);
  end loop;
end $$;
revoke all on public.ocorrencias from anon, authenticated;

create policy "ocorrencias_select" on public.ocorrencias for select to authenticated
  using (area = any ((select public.areas_do_usuario())::text[]));
-- abrir: qualquer pessoa ativa da área, em nome de si mesma, e já nasce em aberto
create policy "ocorrencias_insert" on public.ocorrencias for insert to authenticated
  with check (area = any ((select public.areas_do_usuario())::text[])
              and (aberta_por is null or aberta_por = auth.uid())
              and liberada_em is null and not anulado);
-- liberar e anular: só supervisor
create policy "ocorrencias_update" on public.ocorrencias for update to authenticated
  using ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]))
  with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));

grant select, insert on public.ocorrencias to authenticated;
grant update (liberada_em, liberada_por_nome, motivo_liberacao, servico_realizado, recebido_por, anulado, anulado_motivo) on public.ocorrencias to authenticated;

-- ---------- Realtime ----------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'ocorrencias') then
    alter publication supabase_realtime add table public.ocorrencias;
  end if;
end $$;

-- ---------- Power BI ----------
create or replace view bi.manutencao_ocorrencias as
select
  o.id,
  e.codigo as equipamento,
  e.nome   as equipamento_nome,
  e.tipo   as equipamento_tipo,
  case o.categoria when 'manutencao' then 'Manutenção' else 'Parada operacional' end as categoria,
  o.motivo,
  o.descricao,
  (o.aberta_em at time zone 'America/Sao_Paulo') as aberta_em,
  o.aberta_por_nome,
  (o.liberada_em at time zone 'America/Sao_Paulo') as liberada_em,
  o.motivo_liberacao,
  o.servico_realizado,
  o.recebido_por,
  o.liberada_por_nome,
  case when o.liberada_em is null then 'Em aberto' else 'Liberada' end as situacao,
  round((extract(epoch from (coalesce(o.liberada_em, now()) - o.aberta_em)) / 3600)::numeric, 2) as horas_parado
from public.ocorrencias o
join public.equipamentos e on e.id = o.equipamento_id
where not o.anulado;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'powerbi_leitor') then
    grant usage on schema bi to powerbi_leitor;
    grant select on all tables in schema bi to powerbi_leitor;
  end if;
end $$;

commit;

-- ============================================================
-- DESFAZER (antes de haver ocorrências): drop view bi.manutencao_ocorrencias; drop table public.ocorrencias cascade;
-- ============================================================
