-- ============================================================
-- update_014 — CONTAGEM CEGA (conferência sem lista prévia)
-- Rodar no SQL Editor do Supabase DEPOIS do update_013. Pode rodar mais de uma vez.
-- Roda tudo em uma transação: se der erro, nada é alterado.
--
-- O QUE ISTO FAZ
--  1) sessoes.tipo   : 'normal' (a conferência de sempre) ou 'cega' (bipa tudo primeiro e compara
--                      depois com a planilha do Protheus). Conferências que já existem ficam 'normal'.
--  2) sessoes.itens  : os itens lidos da etiqueta numa contagem cega (lote, corrida, peso, produto,
--                      quantidade de peças). Fica vazio nas conferências normais.
--  Nada muda no estoque (volumes): a contagem cega só guarda o que foi bipado e o resultado da comparação.
--  As regras de acesso (RLS) por área continuam valendo, pois a tabela sessoes é a mesma.
-- ============================================================

begin;

set local lock_timeout = '8s';

alter table public.sessoes add column if not exists tipo text not null default 'normal';
alter table public.sessoes add column if not exists itens jsonb;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.sessoes'::regclass and conname = 'sessoes_tipo_check'
  ) then
    alter table public.sessoes
      add constraint sessoes_tipo_check check (tipo in ('normal', 'cega'));
  end if;
end $$;

commit;

-- ============================================================
-- DESFAZER (só se precisar; apaga os dados das contagens cegas):
--   alter table public.sessoes drop constraint if exists sessoes_tipo_check;
--   alter table public.sessoes drop column if exists itens;
--   alter table public.sessoes drop column if exists tipo;
-- ============================================================
