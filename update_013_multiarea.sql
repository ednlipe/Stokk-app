-- ============================================================
-- update_013 — VÁRIAS ÁREAS POR USUÁRIO (troca de área dentro do app)
-- Rodar no SQL Editor do Supabase DEPOIS do update_012. Pode rodar mais de uma vez.
-- Roda tudo em uma transação: se der erro, nada é alterado.
-- Se der "lock timeout": nada foi alterado; rode de novo (de preferência fora do horário de uso).
--
-- O QUE ISTO FAZ
--  1) Cria "usuario_areas": a lista de áreas que cada pessoa pode acessar.
--     A área de profiles.area continua valendo como área principal (padrão), e quem já tem uma
--     só área não muda nada. Pessoa com mais de uma área escolhe a área ao entrar e pode trocar
--     no app (botão no topo).
--  2) As regras de acesso (RLS) passam a aceitar QUALQUER área da lista da pessoa. O app filtra pela
--     área escolhida e grava os registros nela. (Quem não é do app, como o Power BI, não muda.)
--  3) Trava: nenhum registro muda de área pelo app (um lote que já existe em outra área não é movido).
--  4) A pessoa NÃO altera a própria lista de áreas pelo app: só pelo painel do Supabase / SQL Editor.
--
-- LIMITE: o nível (operador/supervisor) vale para todas as áreas da pessoa.
-- ============================================================

begin;

set local lock_timeout = '8s';
lock table public.volumes, public.movimentos, public.sessoes, public.producoes
  in access exclusive mode;

-- ---------- 1) Lista de áreas por usuário ----------
create table if not exists public.usuario_areas (
  user_id uuid not null references public.profiles(id) on delete cascade,
  area text not null references public.areas(id),
  criado_em timestamptz not null default now(),
  primary key (user_id, area)
);
alter table public.usuario_areas enable row level security;

-- quem já tem área principal entra na lista (não duplica se rodar de novo)
insert into public.usuario_areas (user_id, area)
select p.id, p.area from public.profiles p where p.area is not null
on conflict do nothing;

drop policy if exists "usuario_areas_select_proprio" on public.usuario_areas;
create policy "usuario_areas_select_proprio" on public.usuario_areas for select to authenticated
  using (user_id = auth.uid());
revoke all on public.usuario_areas from anon, authenticated;
grant select on public.usuario_areas to authenticated;

-- ---------- 2) Funções ----------
-- Áreas que a pessoa logada pode acessar (vazio se a conta está bloqueada ou sem área)
create or replace function public.areas_do_usuario()
returns text[]
language sql stable security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct x.area), '{}'::text[])
  from (
    select p.area from public.profiles p where p.id = auth.uid() and p.ativo and p.area is not null
    union
    select ua.area from public.usuario_areas ua
      join public.profiles p on p.id = ua.user_id
      where ua.user_id = auth.uid() and p.ativo
  ) x
  join public.areas a on a.id = x.area and a.ativa;
$$;
revoke all on function public.areas_do_usuario() from public, anon;
grant execute on function public.areas_do_usuario() to authenticated;

-- ---------- 3) Regras de acesso (RLS): qualquer área da lista da pessoa ----------
do $$
declare r record;
begin
  for r in
    select policyname, tablename from pg_policies
    where schemaname = 'public'
      and tablename in ('volumes', 'movimentos', 'sessoes', 'producoes', 'armazens_area')
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- volumes
create policy "volumes_select" on public.volumes for select to authenticated using (area = any ((select public.areas_do_usuario())::text[]));
create policy "volumes_insert" on public.volumes for insert to authenticated with check (area = any ((select public.areas_do_usuario())::text[]));
create policy "volumes_update" on public.volumes for update to authenticated
  using (area = any ((select public.areas_do_usuario())::text[])) with check (area = any ((select public.areas_do_usuario())::text[]));
create policy "volumes_delete" on public.volumes for delete to authenticated
  using ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));

-- movimentos: histórico só lê e insere; não aceita registro em nome de outra pessoa
create policy "movimentos_select" on public.movimentos for select to authenticated using (area = any ((select public.areas_do_usuario())::text[]));
create policy "movimentos_insert" on public.movimentos for insert to authenticated
  with check (area = any ((select public.areas_do_usuario())::text[]) and (usuario_id is null or usuario_id = auth.uid()));

-- sessoes (conferências)
create policy "sessoes_select" on public.sessoes for select to authenticated using (area = any ((select public.areas_do_usuario())::text[]));
create policy "sessoes_insert" on public.sessoes for insert to authenticated with check (area = any ((select public.areas_do_usuario())::text[]));
create policy "sessoes_update" on public.sessoes for update to authenticated
  using (area = any ((select public.areas_do_usuario())::text[])) with check (area = any ((select public.areas_do_usuario())::text[]));
create policy "sessoes_delete" on public.sessoes for delete to authenticated
  using ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));

-- producoes
create policy "producoes_select" on public.producoes for select to authenticated using (area = any ((select public.areas_do_usuario())::text[]));
create policy "producoes_insert" on public.producoes for insert to authenticated with check (area = any ((select public.areas_do_usuario())::text[]));
create policy "producoes_update" on public.producoes for update to authenticated
  using (area = any ((select public.areas_do_usuario())::text[])) with check (area = any ((select public.areas_do_usuario())::text[]));
create policy "producoes_delete" on public.producoes for delete to authenticated
  using ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));

-- armazéns das áreas da pessoa
create policy "armazens_area_select" on public.armazens_area for select to authenticated
  using (area = any ((select public.areas_do_usuario())::text[]));

-- ---------- 4) Nenhum registro muda de área pelo app ----------
-- (sem isso, quem tem duas áreas poderia "mover" um volume de uma área para outra ao salvar um lote que já existe)
create or replace function public.proteger_area_registro()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is not null and new.area is distinct from old.area then
    raise exception 'Um registro não pode mudar de área (o lote já existe na outra área).' using errcode = '42501';
  end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['volumes', 'movimentos', 'sessoes', 'producoes'] loop
    execute format('drop trigger if exists trg_proteger_area on public.%I', t);
    execute format('create trigger trg_proteger_area before update on public.%I for each row execute function public.proteger_area_registro()', t);
  end loop;
end $$;

commit;

-- ============================================================
-- COMO DAR MAIS UMA ÁREA A UMA PESSOA (SQL Editor):
--   insert into public.usuario_areas (user_id, area) values ('<ID DO USUÁRIO>', 'planta1') on conflict do nothing;
-- Para tirar uma área:
--   delete from public.usuario_areas where user_id = '<ID DO USUÁRIO>' and area = 'planta1';
--   (se for a área principal, troque também profiles.area)
-- Quem tem uma área só continua entrando direto, sem tela de escolha.
-- Para listar quem tem acesso a quê:
--   select p.nome, p.role, p.area as principal, array_agg(ua.area order by ua.area) as areas
--   from public.profiles p left join public.usuario_areas ua on ua.user_id = p.id group by 1,2,3 order by 1;
--
-- DESFAZER: rode de novo o bloco 6) do update_012_areas.sql (regras com "area = area_do_usuario()")
-- e apague os gatilhos: drop trigger trg_proteger_area on public.<tabela>;
-- ============================================================
