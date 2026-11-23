-- STOKK — usado por scripts/backup_banco.ps1 (psql -X -q -A -t). Só LEITURA: não altera nada no banco.
-- Gera, como texto SQL, o que o pg_dump de public/bi não traz: extensões, papéis extras, tempo real,
-- gatilhos em auth/storage, bucket e políticas do Storage e os agendamentos do pg_cron.
-- Segredos dos agendamentos (x-cron-secret, Authorization, apikey, JWTs) saem trocados por <SEGREDO>.
\pset footer off
-- search_path vazio de schemas do projeto: assim gatilhos e políticas saem com o schema escrito
-- (public.handle_new_user(), public.areas_do_usuario()) e funcionam num banco novo.
select set_config('search_path', 'pg_catalog', false) as _caminho \gset

select '-- ============================================================';
select '-- STOKK — partes da estrutura fora dos schemas public e bi';
select '-- Gerado em ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
       || ' (Brasília) por scripts/backup_banco.ps1. Não edite à mão: rode o script de novo.';
select '-- Servidor: PostgreSQL ' || current_setting('server_version');
select '-- Ordem para montar um banco novo: docs/banco.md, seção 4.7.';
select '-- ============================================================';

select '';
select '-- ---------- Extensões ----------';
select format('create extension if not exists %I with schema %I;  -- versão %s', e.extname, n.nspname, e.extversion)
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
 where e.extname <> 'plpgsql'
 order by 1;

select '';
select '-- ---------- Papéis criados pelo projeto (criar à mão, com senha nova, ANTES da estrutura) ----------';
select format('-- create role %I %s password ''<SENHA>'';', r.rolname, case when r.rolcanlogin then 'login' else 'nologin' end)
  from pg_roles r
 where r.rolname !~ '^(pg_|supabase|pgsodium)'
   and r.rolname not in ('postgres', 'anon', 'authenticated', 'service_role', 'authenticator',
                         'dashboard_user', 'pgbouncer', 'cli_login_postgres')
 order by 1;

select '';
select '-- ---------- Tabelas no tempo real (publicação supabase_realtime) ----------';
select format('alter publication supabase_realtime add table %I.%I;', schemaname, tablename)
  from pg_publication_tables
 where pubname = 'supabase_realtime'
 order by 1;

select '';
select '-- ---------- Gatilhos em auth/storage que chamam funções do public (ex.: criar o perfil ao cadastrar) ----------';
select pg_get_triggerdef(t.oid) || ';'
  from pg_trigger t
  join pg_class c       on c.oid = t.tgrelid
  join pg_namespace n   on n.oid = c.relnamespace
  join pg_proc p        on p.oid = t.tgfoid
  join pg_namespace pn  on pn.oid = p.pronamespace
 where n.nspname in ('auth', 'storage')
   and not t.tgisinternal
   and pn.nspname = 'public'
 order by 1;

select '';
select '-- ---------- Storage: buckets ----------';
select format('insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values (%L, %L, %L, %s, %L) on conflict (id) do nothing;',
              id, name, public, coalesce(file_size_limit::text, 'null'), allowed_mime_types)
  from storage.buckets
 order by id;

select '';
select '-- ---------- Storage: políticas ----------';
select format('create policy %I on %I.%I as %s for %s to %s%s%s;',
              policyname, schemaname, tablename, permissive, cmd,
              array_to_string(roles, ', '),
              coalesce(' using (' || qual || ')', ''),
              coalesce(' with check (' || with_check || ')', ''))
  from pg_policies
 where schemaname = 'storage'
 order by tablename, policyname;

select exists (select 1 from pg_namespace where nspname = 'cron') as tem_cron \gset
\if :tem_cron
select '';
select '-- ---------- Agendamentos (pg_cron): SÓ REFERÊNCIA, segredos trocados por <SEGREDO>. Recriar pelo docs/deploy.md ----------';
select format('-- [job %s] %s | %s | ativo: %s | %s', jobid, jobname, schedule, active,
         regexp_replace(
           regexp_replace(
             regexp_replace(
               regexp_replace(command,
                 '("(x-cron-secret|authorization|apikey)"\s*:\s*")[^"]*', '\1<SEGREDO>', 'gi'),
               '(''(x-cron-secret|authorization|apikey)''\s*,\s*'')[^'']*', '\1<SEGREDO>', 'gi'),
             'eyJ[A-Za-z0-9_.-]{10,}', '<SEGREDO>', 'g'),
           '\s+', ' ', 'g'))
  from cron.job
 order by jobid;
\endif
