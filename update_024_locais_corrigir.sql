-- ============================================================
-- update_024 — LOCAIS: QUEM LANÇOU PODE CORRIGIR (ANULAR) O PRÓPRIO REGISTRO POR 48 H
-- Rodar no SQL Editor do Supabase DEPOIS do update_017 (e do 022/023). Pode rodar mais de uma vez.
-- Roda tudo em uma transação: se der erro, nada é alterado.
--
-- O QUE ISTO FAZ
--  Hoje só o supervisor consegue anular um registro de local. O app agora tem "corrigir": salva o registro novo e anula o antigo
--  (motivo "Corrigido por ..."). Para o operador poder corrigir o que ele mesmo lançou (ex.: depois do turno), a regra de UPDATE passa a ser:
--    - supervisor: qualquer registro da(s) área(s) dele (como antes);
--    - quem lançou (usuario_id = ele): só o próprio registro, e só até 48 h depois de lançado ("timestamp").
--  Continua valendo a trava do update_015/017: o UPDATE só pode marcar anulado, exige motivo e grava quem/quando. Nada é apagado nem editado.
--  O "timestamp" vem do app; para ninguém estender o prazo com data no futuro, só conta até 1 h à frente.
-- NÃO MUDA: leitura, inserção, permissões de coluna, anulação já feita.
-- ============================================================

begin;

set local lock_timeout = '8s';

drop policy if exists "equipamento_locais_update" on public.equipamento_locais;
create policy "equipamento_locais_update" on public.equipamento_locais for update to authenticated
  using (
    area = any ((select public.areas_do_usuario())::text[])
    and ((select public.eh_supervisor())
         or (usuario_id = auth.uid() and "timestamp" > now() - interval '48 hours' and "timestamp" <= now() + interval '1 hour'))
  )
  with check (
    area = any ((select public.areas_do_usuario())::text[])
    and ((select public.eh_supervisor())
         or (usuario_id = auth.uid() and "timestamp" > now() - interval '48 hours' and "timestamp" <= now() + interval '1 hour'))
  );

commit;

-- ============================================================
-- DESFAZER (volta a só supervisor):
--   drop policy "equipamento_locais_update" on public.equipamento_locais;
--   create policy "equipamento_locais_update" on public.equipamento_locais for update to authenticated
--     using ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]))
--     with check ((select public.eh_supervisor()) and area = any ((select public.areas_do_usuario())::text[]));
-- ============================================================
