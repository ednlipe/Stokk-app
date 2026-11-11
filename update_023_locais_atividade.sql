-- ============================================================
-- update_023 — LOCAIS: ATIVIDADE E SOLICITANTE
-- Rodar no SQL Editor do Supabase DEPOIS do update_022. Pode rodar mais de uma vez.
-- Roda tudo em uma transação: se der erro, nada é alterado.
--
-- O QUE ISTO FAZ
--  1) equipamento_locais.atividade  — o que o equipamento está fazendo ("carregando tarugo"...). Texto, até 200.
--  2) equipamento_locais.solicitante — quem pediu o serviço. Texto, até 120. Opcional.
--  3) Views do Power BI ganham as duas colunas (no fim, para não quebrar relatórios existentes).
--
-- O LOCAL (Planta 1, Planta 2, Trefila) passou a ser uma lista escolhida no app; o banco continua aceitando
-- texto livre no campo local, então os registros antigos ("Pátio 2"...) continuam válidos e visíveis.
-- Registros antigos ficam com atividade e solicitante vazios. NÃO muda RLS, anulação nem permissões.
-- ============================================================

begin;

set local lock_timeout = '8s';

alter table public.equipamento_locais add column if not exists atividade text;
alter table public.equipamento_locais add column if not exists solicitante text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'equipamento_locais_atividade_ck' and conrelid = 'public.equipamento_locais'::regclass) then
    alter table public.equipamento_locais
      add constraint equipamento_locais_atividade_ck check (atividade is null or (btrim(atividade) <> '' and char_length(atividade) <= 200));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'equipamento_locais_solicitante_ck' and conrelid = 'public.equipamento_locais'::regclass) then
    alter table public.equipamento_locais
      add constraint equipamento_locais_solicitante_ck check (solicitante is null or (btrim(solicitante) <> '' and char_length(solicitante) <= 120));
  end if;
end $$;

-- ---------- Power BI (colunas novas sempre no fim) ----------
create or replace view bi.equipamento_locais as
select
  l.id,
  e.codigo as equipamento,
  e.nome   as equipamento_nome,
  l.local,
  l.obs,
  (l.data_hora at time zone 'America/Sao_Paulo') as desde,
  l.usuario_nome,
  (l.data_fim at time zone 'America/Sao_Paulo') as fim,
  e.setor,
  l.atividade,
  l.solicitante
from public.equipamento_locais l
join public.equipamentos e on e.id = l.equipamento_id
where not l.anulado;

create or replace view bi.equipamento_local_atual as
select distinct on (l.equipamento_id)
  e.codigo as equipamento,
  e.nome   as equipamento_nome,
  l.local,
  l.obs,
  (l.data_hora at time zone 'America/Sao_Paulo') as desde,
  l.usuario_nome,
  e.setor,
  l.atividade,
  l.solicitante
from public.equipamento_locais l
join public.equipamentos e on e.id = l.equipamento_id
where not l.anulado
order by l.equipamento_id, l.data_hora desc, l."timestamp" desc;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'powerbi_leitor') then
    grant usage on schema bi to powerbi_leitor;
    grant select on all tables in schema bi to powerbi_leitor;
  end if;
end $$;

commit;

-- ============================================================
-- DESFAZER: drop view bi.equipamento_locais, bi.equipamento_local_atual; (recrie com a seção 3 do update_022)
--   alter table public.equipamento_locais drop constraint equipamento_locais_atividade_ck, drop constraint equipamento_locais_solicitante_ck,
--     drop column atividade, drop column solicitante;
-- ============================================================
