-- ============================================================
-- update_020 — ADMINISTRADOR DE USUÁRIOS (criar login, escolher áreas, papel e bloqueio, pelo app)
-- Rodar no SQL Editor do Supabase. Pode rodar mais de uma vez.
-- Roda tudo em uma transação: se der erro, nada é alterado.
--
-- O QUE ISTO FAZ
--  1) Cria profiles.admin (padrão false). Quem é administrador vê a tela "Usuários" no app e pode, por ela,
--     criar contas, ativar/bloquear, trocar o papel (operador/supervisor), escolher as áreas e redefinir senhas.
--     O campo admin só muda pelo SQL Editor / painel (o gatilho proteger_profiles agora também o protege).
--  2) Cria admin_acoes: registro (só inserção) de tudo o que o administrador faz pela tela. Nunca guarda senha.
--  3) Cria eh_admin() (conta ativa com admin = true).
--
-- A tela fala com a Edge Function supabase/functions/admin-usuarios, que usa a chave de serviço do Supabase
-- (guardada só no servidor) e antes de qualquer coisa confere se quem chamou é administrador.
--
-- DEPOIS DE RODAR, torne a sua conta administradora (troque o e-mail):
--   update public.profiles set admin = true, role = 'supervisor', ativo = true
--   where id = (select id from auth.users where email = 'SEU_EMAIL');
-- ============================================================

begin;

set local lock_timeout = '8s';

-- ---------- 1) Campo admin ----------
alter table public.profiles add column if not exists admin boolean not null default false;

-- ninguém muda role / ativo / id / área / admin pelo app (a Edge Function usa a chave de serviço: auth.uid() é nulo)
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
       or new.area is distinct from old.area
       or new.admin is distinct from old.admin then
      raise exception 'Perfil, ativação, área e administração só podem ser alterados pelo painel do Supabase.' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

-- ---------- 2) eh_admin() ----------
create or replace function public.eh_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.ativo and p.admin);
$$;
revoke all on function public.eh_admin() from public, anon;
grant execute on function public.eh_admin() to authenticated;

-- ---------- 3) Registro das ações do administrador ----------
create table if not exists public.admin_acoes (
  id bigint generated always as identity primary key,
  quando timestamptz not null default now(),
  admin_id uuid,
  admin_nome text,
  acao text not null,
  alvo_id uuid,
  alvo_email text,
  detalhe jsonb
);
alter table public.admin_acoes enable row level security;
do $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname = 'public' and tablename = 'admin_acoes' loop
    execute format('drop policy if exists %I on public.admin_acoes', r.policyname);
  end loop;
end $$;
revoke all on public.admin_acoes from anon, authenticated;
-- quem grava é a Edge Function (chave de serviço); administrador pode ler
create policy "admin_acoes_select" on public.admin_acoes for select to authenticated using ((select public.eh_admin()));
grant select on public.admin_acoes to authenticated;

commit;

-- ============================================================
-- DESFAZER: drop table public.admin_acoes; drop function public.eh_admin();
--   alter table public.profiles drop column admin;
--   (e rode de novo o update_012 para recriar proteger_profiles sem o campo admin)
-- ============================================================
