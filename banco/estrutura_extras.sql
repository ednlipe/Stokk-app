-- ============================================================
-- STOKK — partes da estrutura fora dos schemas public e bi
-- Gerado em 23/11/2026 00:07 (Brasília) por scripts/backup_banco.ps1. Não edite à mão: rode o script de novo.
-- Servidor: PostgreSQL 17.6
-- Ordem para montar um banco novo: docs/banco.md, seção 4.7.
-- ============================================================

-- ---------- Extensões ----------
create extension if not exists "uuid-ossp" with schema extensions;  -- versão 1.1
create extension if not exists pg_cron with schema pg_catalog;  -- versão 1.6.4
create extension if not exists pg_net with schema extensions;  -- versão 0.20.4
create extension if not exists pg_stat_statements with schema extensions;  -- versão 1.11
create extension if not exists pgcrypto with schema extensions;  -- versão 1.3
create extension if not exists supabase_vault with schema vault;  -- versão 0.3.1

-- ---------- Papéis criados pelo projeto (criar à mão, com senha nova, ANTES da estrutura) ----------
-- create role powerbi_leitor login password '<SENHA>';

-- ---------- Tabelas no tempo real (publicação supabase_realtime) ----------
alter publication supabase_realtime add table public.abastecimentos;
alter publication supabase_realtime add table public.cinco_s;
alter publication supabase_realtime add table public.equipamento_locais;
alter publication supabase_realtime add table public.equipamentos;
alter publication supabase_realtime add table public.movimentos;
alter publication supabase_realtime add table public.ocorrencias;
alter publication supabase_realtime add table public.producoes;
alter publication supabase_realtime add table public.produtos;
alter publication supabase_realtime add table public.sessoes;
alter publication supabase_realtime add table public.stokkbook_posts;
alter publication supabase_realtime add table public.stokkbook_reacoes;
alter publication supabase_realtime add table public.tanque_entradas;
alter publication supabase_realtime add table public.tanque_medicoes;
alter publication supabase_realtime add table public.tanques;
alter publication supabase_realtime add table public.volumes;

-- ---------- Gatilhos em auth/storage que chamam funções do public (ex.: criar o perfil ao cadastrar) ----------
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ---------- Storage: buckets ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('cinco-s', 'cinco-s', 'f', 2097152, '{image/jpeg}') on conflict (id) do nothing;

-- ---------- Storage: políticas ----------
create policy cinco_s_fotos_insert on storage.objects as PERMISSIVE for INSERT to authenticated with check (((bucket_id = 'cinco-s'::text) AND ((storage.foldername(name))[1] = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));
create policy cinco_s_fotos_select on storage.objects as PERMISSIVE for SELECT to authenticated using (((bucket_id = 'cinco-s'::text) AND ((storage.foldername(name))[1] = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));

-- ---------- Agendamentos (pg_cron): SÓ REFERÊNCIA, segredos trocados por <SEGREDO>. Recriar pelo docs/deploy.md ----------
-- [job 6] push-conferencia | 0 11,15,19 * * * | ativo: t |  select net.http_post( url := 'https://vjzqzmigifjdxftwmxew.supabase.co/functions/v1/avisar-conferencias', headers := jsonb_build_object('Content-Type','application/json','x-cron-secret','<SEGREDO>'), body := '{"tipo":"conferencia"}'::jsonb); 
-- [job 7] push-inventario | 0 12,16 * * * | ativo: t |  select net.http_post( url := 'https://vjzqzmigifjdxftwmxew.supabase.co/functions/v1/avisar-conferencias', headers := jsonb_build_object('Content-Type','application/json','x-cron-secret','<SEGREDO>'), body := '{"tipo":"inventario"}'::jsonb); 
-- [job 8] push-rendimento | 0 18 * * * | ativo: t |  select net.http_post( url := 'https://vjzqzmigifjdxftwmxew.supabase.co/functions/v1/avisar-conferencias', headers := jsonb_build_object('Content-Type','application/json','x-cron-secret','<SEGREDO>'), body := '{"tipo":"rendimento"}'::jsonb); 
