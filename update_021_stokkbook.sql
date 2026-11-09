-- ============================================================
-- update_021 — STOKKBOOK (feed de reconhecimento: 5S concluídos + reações)
-- Rodar no SQL Editor do Supabase DEPOIS do update_018/019 (5S). Pode rodar mais de uma vez.
-- Roda tudo em uma transação: se der erro, nada é alterado.
--
-- O QUE ISTO FAZ
--  1) cinco_s.postar_stokkbook (padrão true): a caixinha "Postar no Stokkbook" da tela de concluir 5S.
--  2) stokkbook_posts: um post por evento. Hoje só tipo 'cinco_s'; nasce SOZINHO (gatilho) quando um 5S é concluído
--     com a caixinha marcada. Guarda uma cópia dos textos e os caminhos da foto antes/depois (as fotos continuam no
--     bucket privado 'cinco-s', mesma regra de área). Se o 5S for anulado, o post fica oculto.
--     O tipo é texto livre com check: para novos eventos (ex.: máquina) basta ampliar o check e criar outro gatilho.
--  3) Quem vê: só os posts das áreas da própria pessoa. Supervisor pode OCULTAR (com motivo) e reexibir; nada se apaga.
--  4) stokkbook_reacoes: uma reação por pessoa por post (palmas, confete, foguete, joia), pode trocar ou tirar.
--  5) Realtime ligado nas duas tabelas. Posts dos 5S já concluídos entram no feed (uma vez).
-- NÃO MUDA: regras de quem abre/conclui/corrige/anula o 5S.
-- ============================================================

begin;

set local lock_timeout = '8s';

-- ---------- 1) Caixinha na tela de concluir ----------
alter table public.cinco_s add column if not exists postar_stokkbook boolean not null default true;
grant update (postar_stokkbook) on public.cinco_s to authenticated;

-- ---------- 2) Posts ----------
create table if not exists public.stokkbook_posts (
  id bigint generated always as identity primary key,
  tipo text not null check (tipo in ('cinco_s')),
  ref_id text not null,
  area text not null references public.areas(id),
  autor_id uuid,
  autor_nome text,
  setor text,
  problema text,
  acao text,
  foto_antes text,
  foto_depois text,
  fotos_antes int not null default 1,
  fotos_depois int not null default 1,
  horas numeric,
  quando timestamptz not null default now(),         -- quando aconteceu (conclusão do 5S)
  criado_em timestamptz not null default now(),
  oculto boolean not null default false,
  oculto_motivo text,
  oculto_por uuid,
  oculto_em timestamptz,
  unique (tipo, ref_id)
);
create index if not exists stokkbook_posts_area_quando_idx on public.stokkbook_posts (area, quando desc);

-- só o supervisor mexe em oculto; registra quem e quando
create or replace function public.stokkbook_posts_proteger()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.oculto is distinct from old.oculto then
    if new.oculto and coalesce(btrim(new.oculto_motivo), '') = '' then
      raise exception 'Informe o motivo para ocultar.' using errcode = '23514';
    end if;
    if not new.oculto then new.oculto_motivo := null; end if;
    new.oculto_por := auth.uid();
    new.oculto_em := now();
  end if;
  return new;
end;
$$;
drop trigger if exists trg_stokkbook_posts_proteger on public.stokkbook_posts;
create trigger trg_stokkbook_posts_proteger before update on public.stokkbook_posts
  for each row execute function public.stokkbook_posts_proteger();

alter table public.stokkbook_posts enable row level security;
do $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname = 'public' and tablename = 'stokkbook_posts' loop
    execute format('drop policy if exists %I on public.stokkbook_posts', r.policyname);
  end loop;
end $$;
revoke all on public.stokkbook_posts from anon, authenticated;
create policy "stokkbook_posts_select" on public.stokkbook_posts for select to authenticated
  using (area = any ((select public.areas_do_usuario())::text[]) and (not oculto or (select public.eh_supervisor())));
create policy "stokkbook_posts_update" on public.stokkbook_posts for update to authenticated
  using ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]))
  with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));
grant select on public.stokkbook_posts to authenticated;
grant update (oculto, oculto_motivo) on public.stokkbook_posts to authenticated;
-- (de propósito: ninguém insere nem apaga post pelo app; quem cria é o gatilho do 5S)

-- ---------- 3) Gatilho: 5S concluído -> post; 5S anulado -> post oculto ----------
create or replace function public.stokkbook_de_cinco_s()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.anulado and not old.anulado then
    update public.stokkbook_posts
       set oculto = true, oculto_motivo = '5S anulado'
     where tipo = 'cinco_s' and ref_id = new.id and not oculto;
    return new;
  end if;
  if old.concluido_em is null and new.concluido_em is not null and not new.anulado and new.postar_stokkbook then
    insert into public.stokkbook_posts
      (tipo, ref_id, area, autor_id, autor_nome, setor, problema, acao, foto_antes, foto_depois, fotos_antes, fotos_depois, horas, quando)
    values
      ('cinco_s', new.id, new.area, new.concluido_por, new.concluido_por_nome, new.setor, new.problema, new.acao,
       new.foto_antes, new.foto_depois, 1 + cardinality(new.fotos_antes_extra), 1 + cardinality(new.fotos_depois_extra),
       round((extract(epoch from (new.concluido_em - new.aberto_em)) / 3600)::numeric, 2), new.concluido_em)
    on conflict (tipo, ref_id) do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_stokkbook_de_cinco_s on public.cinco_s;
create trigger trg_stokkbook_de_cinco_s after update on public.cinco_s
  for each row execute function public.stokkbook_de_cinco_s();

-- posts dos 5S que já estavam concluídos (uma vez; não repete)
insert into public.stokkbook_posts
  (tipo, ref_id, area, autor_id, autor_nome, setor, problema, acao, foto_antes, foto_depois, fotos_antes, fotos_depois, horas, quando)
select 'cinco_s', c.id, c.area, c.concluido_por, c.concluido_por_nome, c.setor, c.problema, c.acao, c.foto_antes, c.foto_depois,
       1 + cardinality(c.fotos_antes_extra), 1 + cardinality(c.fotos_depois_extra),
       round((extract(epoch from (c.concluido_em - c.aberto_em)) / 3600)::numeric, 2), c.concluido_em
from public.cinco_s c
where c.concluido_em is not null and not c.anulado and c.postar_stokkbook
on conflict (tipo, ref_id) do nothing;

-- ---------- 4) Reações ----------
create table if not exists public.stokkbook_reacoes (
  post_id bigint not null references public.stokkbook_posts(id) on delete cascade,
  user_id uuid not null default auth.uid(),
  user_nome text,
  emoji text not null check (emoji in ('palmas', 'confete', 'foguete', 'joia')),
  criado_em timestamptz not null default now(),
  primary key (post_id, user_id)
);

-- a pessoa é sempre quem está logada, e o nome vem do perfil (não do que o app mandar)
create or replace function public.stokkbook_reacoes_proteger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null then
    new.user_id := auth.uid();
    new.user_nome := (select p.nome from public.profiles p where p.id = auth.uid());
  end if;
  if tg_op = 'UPDATE' then new.post_id := old.post_id; end if;
  return new;
end;
$$;
drop trigger if exists trg_stokkbook_reacoes_proteger on public.stokkbook_reacoes;
create trigger trg_stokkbook_reacoes_proteger before insert or update on public.stokkbook_reacoes
  for each row execute function public.stokkbook_reacoes_proteger();

alter table public.stokkbook_reacoes enable row level security;
do $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname = 'public' and tablename = 'stokkbook_reacoes' loop
    execute format('drop policy if exists %I on public.stokkbook_reacoes', r.policyname);
  end loop;
end $$;
revoke all on public.stokkbook_reacoes from anon, authenticated;
-- só vê/reage quem vê o post (a regra de área e de oculto do post vale aqui dentro)
create policy "stokkbook_reacoes_select" on public.stokkbook_reacoes for select to authenticated
  using (exists (select 1 from public.stokkbook_posts p where p.id = post_id));
create policy "stokkbook_reacoes_insert" on public.stokkbook_reacoes for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.stokkbook_posts p where p.id = post_id));
create policy "stokkbook_reacoes_update" on public.stokkbook_reacoes for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and exists (select 1 from public.stokkbook_posts p where p.id = post_id));
create policy "stokkbook_reacoes_delete" on public.stokkbook_reacoes for delete to authenticated
  using (user_id = auth.uid());
grant select, delete on public.stokkbook_reacoes to authenticated;
grant insert (post_id, emoji) on public.stokkbook_reacoes to authenticated;
grant update (emoji) on public.stokkbook_reacoes to authenticated;

-- ---------- 5) Realtime ----------
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['stokkbook_posts', 'stokkbook_reacoes'] loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

commit;

-- ============================================================
-- DESFAZER: drop table public.stokkbook_reacoes; drop table public.stokkbook_posts;
--   drop trigger trg_stokkbook_de_cinco_s on public.cinco_s; drop function public.stokkbook_de_cinco_s();
--   alter table public.cinco_s drop column postar_stokkbook;
-- ============================================================
