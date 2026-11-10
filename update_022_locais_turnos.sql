-- ============================================================
-- update_022 — LOCAIS POR SETOR E TURNO (fim do período + setor responsável do equipamento)
-- Rodar no SQL Editor do Supabase DEPOIS do update_017. Pode rodar mais de uma vez.
-- Roda tudo em uma transação: se der erro, nada é alterado.
--
-- O QUE ISTO FAZ
--  1) equipamento_locais.data_fim (opcional): até quando o equipamento ficou naquele local.
--       Vazio = em andamento. O fim efetivo é calculado no app/BI: o menor entre data_fim e o início do
--       próximo registro do mesmo equipamento. Nenhum registro antigo é alterado (continua só inserção).
--  2) equipamentos.setor (texto): setor responsável ("Pátio de Tarugo", "Expedição"...). O supervisor
--       edita pela tela Equipamentos. Equipamentos ainda sem setor são preenchidos pelo nome (só os vazios).
--  3) Views do Power BI atualizadas (bi.equipamento_locais ganha fim e setor; bi.equipamento_local_atual ganha setor).
--
-- O relatório de turno é montado pelo app a partir do histórico (1º 07:10–15:10, 2º 15:10–23:10, 3º 23:10–07:10).
-- NÃO MUDA: RLS, anulação e permissões de quem lança local.
-- ============================================================

begin;

set local lock_timeout = '8s';

-- ---------- 1) Fim do período no local ----------
alter table public.equipamento_locais add column if not exists data_fim timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'equipamento_locais_fim_ck' and conrelid = 'public.equipamento_locais'::regclass) then
    alter table public.equipamento_locais
      add constraint equipamento_locais_fim_ck check (data_fim is null or data_fim >= data_hora);
  end if;
end $$;

-- ---------- 2) Setor responsável ----------
alter table public.equipamentos add column if not exists setor text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'equipamentos_setor_ck' and conrelid = 'public.equipamentos'::regclass) then
    alter table public.equipamentos
      add constraint equipamentos_setor_ck check (setor is null or (btrim(setor) <> '' and char_length(setor) <= 60));
  end if;
end $$;

-- o supervisor já altera equipamentos (policy do update_015); só falta liberar a coluna nova
grant update (setor) on public.equipamentos to authenticated;

-- preenche só quem ainda está sem setor, pelo nome (corrija pela tela Equipamentos se algum não bater)
update public.equipamentos
   set setor = 'Expedição'
 where setor is null and nome ilike '%empilhadeira%';
update public.equipamentos
   set setor = 'Pátio de Tarugo'
 where setor is null
   and (nome ilike '%carregadeira%' or nome ilike '%caminh%' or nome ilike '%cavalo%' or nome ilike '%meteor%');

-- ---------- 3) Power BI ----------
-- (create or replace view só aceita ACRESCENTAR colunas no fim; por isso as colunas novas vão por último)
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
  e.setor
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
  e.setor
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
-- DESFAZER: alter table public.equipamento_locais drop constraint equipamento_locais_fim_ck, drop column data_fim;
--   alter table public.equipamentos drop constraint equipamentos_setor_ck, drop column setor;
--   (as views: drop view bi.equipamento_locais, bi.equipamento_local_atual; e rode de novo as seções 3 do update_017)
-- ============================================================
