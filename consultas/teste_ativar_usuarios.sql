-- ============================================================
-- STOKK — SÓ NO BANCO DE TESTE: ativa uma conta de teste com todas as áreas.
-- Usado por scripts/montar_banco_teste.ps1 (psql -v email=... -v papel=supervisor|operador).
-- Pelo terminal (fora do script): psql -v email=x@teste.stokk -v papel=operador -f consultas/teste_ativar_usuarios.sql
-- (os :'email' e :'papel' são variáveis do psql; o SQL Editor do Supabase não entende essa sintaxe).
-- A conta precisa já existir (Authentication > Users > Add user): o gatilho cria o perfil bloqueado.
-- ============================================================
select set_config('stokk.email', :'email', false) as _email, set_config('stokk.papel', :'papel', false) as _papel \gset

do $$
declare
  v_id uuid;
  v_papel text := current_setting('stokk.papel');
begin
  if v_papel not in ('supervisor', 'operador') then raise exception 'papel inválido: %', v_papel; end if;
  select id into v_id from auth.users where lower(email) = lower(current_setting('stokk.email'));
  if v_id is null then
    raise exception 'Não existe conta com o e-mail % neste projeto. Crie em Authentication > Users > Add user.', current_setting('stokk.email');
  end if;
  insert into public.profiles (id, nome, role, ativo)
    values (v_id, split_part(current_setting('stokk.email'), '@', 1), 'operador', false)
    on conflict (id) do nothing;   -- caso a conta tenha sido criada antes do gatilho existir
  update public.profiles
     set ativo = true, role = v_papel,
         area = coalesce((select id from public.areas where id = 'trefila'),
                         (select id from public.areas where ativa order by id limit 1))
   where id = v_id;
  insert into public.usuario_areas (user_id, area)
    select v_id, a.id from public.areas a where a.ativa
    on conflict do nothing;
end $$;
