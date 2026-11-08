-- ============================================================
-- update_018 — GESTÃO PLANTA 1 / 5S (antes e depois, com foto)
-- Rodar no SQL Editor do Supabase. Pode rodar mais de uma vez (não depende do 015/016/017).
-- Roda tudo em uma transação: se der erro, nada é alterado.
--
-- O QUE ISTO FAZ
--  1) Cria a área 'gestao_p1' ("Gestão Planta 1"). Quem não tiver essa área em usuario_areas não a vê.
--  2) Cria a tabela cinco_s: cada linha é uma melhoria de 5S.
--       - abre com a foto do ANTES (setor, o que está errado) e fica "em aberto";
--       - qualquer pessoa da área conclui depois, com a foto do DEPOIS e o que foi feito;
--       - ninguém apaga: o supervisor ANULA (com motivo) ou corrige setor/descrição enquanto está em aberto;
--       - depois de concluída não muda mais.
--  3) Cria o bucket privado 'cinco-s' no Storage (fotos JPEG de até 2 MB; o app já reduz cada foto
--     para ~150–300 KB antes de enviar) com regras por área: o arquivo fica em <area>/<aaaa-mm>/<id>_antes.jpg
--     e só quem tem aquela área lê ou envia. Ninguém sobrescreve nem apaga foto pelo app.
--  4) RLS por área, Realtime ligado e a view bi.cinco_s para o Power BI (sem as fotos).
--
-- NÃO MUDA: nada do estoque, do diesel, das paradas nem da localização.
-- Depois de rodar, libere a Gestão Planta 1 para quem for usar, por exemplo:
--   insert into public.usuario_areas (user_id, area)
--   select id, 'gestao_p1' from public.profiles where nome = 'NOME DA PESSOA' and ativo
--   on conflict do nothing;
-- ============================================================

begin;

set local lock_timeout = '8s';

-- ---------- 1) Área ----------
insert into public.areas (id, nome) values ('gestao_p1', 'Gestão Planta 1')
on conflict (id) do nothing;

-- ---------- 2) Tabela ----------
create table if not exists public.cinco_s (
  id text primary key,
  setor text not null check (btrim(setor) <> '' and char_length(setor) <= 80),
  problema text not null check (btrim(problema) <> '' and char_length(problema) <= 300),
  foto_antes text not null,                                   -- caminho no bucket 'cinco-s'
  aberto_em timestamptz not null default now(),               -- quando foi visto / começou
  aberto_por uuid references auth.users(id),
  aberto_por_nome text,
  "timestamp" timestamptz not null default now(),             -- quando o registro foi gravado
  concluido_em timestamptz,
  concluido_por uuid references auth.users(id),
  concluido_por_nome text,
  foto_depois text,
  acao text check (acao is null or char_length(acao) <= 500),
  editado_em timestamptz,
  editado_por uuid references auth.users(id),
  anulado boolean not null default false,
  anulado_motivo text,
  anulado_por uuid references auth.users(id),
  anulado_em timestamptz,
  area text not null default 'gestao_p1' references public.areas(id),
  check (aberto_em <= now() + interval '1 hour'),
  -- a foto tem que estar na pasta da própria área (ninguém aponta para a foto de outra área)
  check (left(foto_antes, char_length(area) + 1) = area || '/'),
  check (foto_depois is null or left(foto_depois, char_length(area) + 1) = area || '/'),
  -- concluir é tudo ou nada: data, foto do depois e o que foi feito
  check ((concluido_em is null) = (foto_depois is null) and (concluido_em is null) = (acao is null))
);
create index if not exists cinco_s_area_aberto_idx on public.cinco_s (area, aberto_em);
create index if not exists cinco_s_area_aberta_idx on public.cinco_s (area) where concluido_em is null and not anulado;

-- Regras de alteração (valem mesmo que alguém tente por fora do app):
--  * anulada não muda mais; concluída só pode ser anulada;
--  * anular = só o supervisor, com motivo; nada mais muda junto;
--  * em aberto: o supervisor corrige setor/descrição; qualquer pessoa da área conclui.
create or replace function public.cinco_s_proteger()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if to_jsonb(new) = to_jsonb(old) then
    return new;
  end if;

  if old.anulado then
    raise exception 'Este 5S já foi anulado e não pode mais ser alterado.' using errcode = '42501';
  end if;

  if new.anulado is true then
    if not (select public.eh_supervisor()) then
      raise exception 'Só o supervisor anula um 5S.' using errcode = '42501';
    end if;
    if coalesce(btrim(new.anulado_motivo), '') = '' then
      raise exception 'Informe o motivo da anulação.' using errcode = '23514';
    end if;
    new.setor := old.setor; new.problema := old.problema; new.foto_antes := old.foto_antes;
    new.aberto_em := old.aberto_em; new.aberto_por := old.aberto_por; new.aberto_por_nome := old.aberto_por_nome;
    new.concluido_em := old.concluido_em; new.concluido_por := old.concluido_por; new.concluido_por_nome := old.concluido_por_nome;
    new.foto_depois := old.foto_depois; new.acao := old.acao;
    new.editado_em := old.editado_em; new.editado_por := old.editado_por;
    new.anulado_por := auth.uid(); new.anulado_em := now();
    return new;
  end if;

  if old.concluido_em is not null then
    raise exception 'Este 5S já foi concluído e não pode mais ser alterado. Para corrigir, anule e abra de novo.' using errcode = '42501';
  end if;

  -- daqui para baixo: o registro está em aberto
  new.foto_antes := old.foto_antes;
  new.aberto_em := old.aberto_em; new.aberto_por := old.aberto_por; new.aberto_por_nome := old.aberto_por_nome;
  new.anulado_motivo := old.anulado_motivo; new.anulado_por := old.anulado_por; new.anulado_em := old.anulado_em;

  if new.concluido_em is null then
    -- correção do que está em aberto: só setor e descrição, só o supervisor
    if not (select public.eh_supervisor()) then
      raise exception 'Só o supervisor corrige um 5S em aberto.' using errcode = '42501';
    end if;
    new.foto_depois := null; new.acao := null; new.concluido_por := null; new.concluido_por_nome := null;
    new.editado_em := now(); new.editado_por := auth.uid();
    return new;
  end if;

  -- conclusão (qualquer pessoa da área): setor e descrição não mudam
  new.setor := old.setor; new.problema := old.problema;
  new.editado_em := old.editado_em; new.editado_por := old.editado_por;
  if coalesce(btrim(new.foto_depois), '') = '' then
    raise exception 'Tire a foto do depois.' using errcode = '23514';
  end if;
  if coalesce(btrim(new.acao), '') = '' then
    raise exception 'Informe o que foi feito.' using errcode = '23514';
  end if;
  if new.concluido_em > now() + interval '1 hour' then
    raise exception 'A conclusão não pode estar no futuro.' using errcode = '23514';
  end if;
  if new.concluido_em < old.aberto_em then
    raise exception 'A conclusão não pode ser antes da abertura (%).', to_char(old.aberto_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') using errcode = '23514';
  end if;
  new.concluido_por := auth.uid();
  return new;
end;
$$;

do $$
begin
  drop trigger if exists trg_cinco_s_proteger on public.cinco_s;
  create trigger trg_cinco_s_proteger before update on public.cinco_s
    for each row execute function public.cinco_s_proteger();
  drop trigger if exists trg_proteger_area on public.cinco_s;
  create trigger trg_proteger_area before update on public.cinco_s
    for each row execute function public.proteger_area_registro();
end $$;

alter table public.cinco_s enable row level security;
do $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname = 'public' and tablename = 'cinco_s' loop
    execute format('drop policy if exists %I on public.cinco_s', r.policyname);
  end loop;
end $$;
revoke all on public.cinco_s from anon, authenticated;

create policy "cinco_s_select" on public.cinco_s for select to authenticated
  using (area = any ((select public.areas_do_usuario())::text[]));
-- abrir: qualquer pessoa da área, em seu próprio nome, ainda sem conclusão
create policy "cinco_s_insert" on public.cinco_s for insert to authenticated
  with check (area = any ((select public.areas_do_usuario())::text[])
    and (aberto_por is null or aberto_por = auth.uid())
    and not anulado and concluido_em is null and foto_depois is null and acao is null);
-- concluir / corrigir / anular: a linha tem que ser da área da pessoa; quem pode o quê é decidido no gatilho
create policy "cinco_s_update" on public.cinco_s for update to authenticated
  using (area = any ((select public.areas_do_usuario())::text[]))
  with check (area = any ((select public.areas_do_usuario())::text[]));

grant select, insert on public.cinco_s to authenticated;
grant update (setor, problema, concluido_em, concluido_por_nome, foto_depois, acao, anulado, anulado_motivo) on public.cinco_s to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'cinco_s') then
    alter publication supabase_realtime add table public.cinco_s;
  end if;
end $$;

-- ---------- 3) Fotos (Storage) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('cinco-s', 'cinco-s', false, 2097152, array['image/jpeg'])
on conflict (id) do update
  set public = false, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg'];

drop policy if exists "cinco_s_fotos_select" on storage.objects;
drop policy if exists "cinco_s_fotos_insert" on storage.objects;
create policy "cinco_s_fotos_select" on storage.objects for select to authenticated
  using (bucket_id = 'cinco-s' and (storage.foldername(name))[1] = any ((select public.areas_do_usuario())::text[]));
create policy "cinco_s_fotos_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'cinco-s' and (storage.foldername(name))[1] = any ((select public.areas_do_usuario())::text[]));
-- (de propósito não há política de update nem de delete: foto enviada não é trocada nem apagada pelo app)

-- ---------- 4) Power BI ----------
create or replace view bi.cinco_s as
select
  c.id,
  c.setor,
  c.problema,
  (c.aberto_em at time zone 'America/Sao_Paulo') as aberto_em,
  c.aberto_por_nome,
  (c.concluido_em at time zone 'America/Sao_Paulo') as concluido_em,
  c.concluido_por_nome,
  c.acao,
  case when c.concluido_em is null then null
       else round((extract(epoch from (c.concluido_em - c.aberto_em)) / 3600)::numeric, 2) end as horas_ate_concluir,
  case when c.concluido_em is null then 'em aberto' else 'concluído' end as situacao
from public.cinco_s c
where not c.anulado;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'powerbi_leitor') then
    grant usage on schema bi to powerbi_leitor;
    grant select on all tables in schema bi to powerbi_leitor;
  end if;
end $$;

commit;

-- ============================================================
-- DESFAZER (antes de haver registros): drop view bi.cinco_s; drop table public.cinco_s cascade;
--   drop policy "cinco_s_fotos_select" on storage.objects; drop policy "cinco_s_fotos_insert" on storage.objects;
--   (o bucket só pode ser apagado pelo painel do Supabase, depois de esvaziado); delete from public.areas where id = 'gestao_p1';
-- ============================================================
