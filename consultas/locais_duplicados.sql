-- ============================================================
-- STOKK — CONSULTA (só leitura, não altera nada): possíveis registros de Locais duplicados
-- por "corrigir" do operador antes do update_024 (ver docs/pendencias.md §13.4).
--
-- O que acontecia: o operador corrigia um local; o app salvava o registro novo, mas o banco
-- (sem o update_024) não deixava anular o antigo e não avisava. Os dois ficaram válidos.
--
-- Lista PARES de registros válidos do mesmo equipamento, lançados pela mesma pessoa (não supervisor)
-- a partir de 13/11/2026 (v1.10.4), com o 2º lançado até 48 h depois do 1º e com início a até
-- 30 min do outro ou trechos que se sobrepõem. É uma ESTIMATIVA: confira cada par no app
-- (histórico do equipamento) e, se for duplicado, o supervisor anula o ANTIGO com motivo.
-- Rodar no SQL Editor do Supabase. Horários em Brasília.
-- ============================================================
with l as (
  select el.*, coalesce(el.data_fim, el.data_hora) as fim_ef
    from public.equipamento_locais el
    join public.profiles p on p.id = el.usuario_id
   where not el.anulado
     and el."timestamp" >= timestamptz '2026-11-13 00:00 -03'
     and p.role <> 'supervisor'
)
select a.equipamento_codigo                                   as equipamento,
       a.usuario_nome                                         as quem_lancou,
       to_char(a.data_hora   at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as inicio_antigo,
       a.local || coalesce(' · ' || a.atividade, '')          as antigo,
       to_char(a."timestamp" at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as lancado_antigo,
       to_char(b.data_hora   at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as inicio_novo,
       b.local || coalesce(' · ' || b.atividade, '')          as novo,
       to_char(b."timestamp" at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as lancado_novo,
       a.id                                                   as id_antigo,
       b.id                                                   as id_novo
  from l a
  join l b
    on b.equipamento_id = a.equipamento_id
   and b.usuario_id     = a.usuario_id
   and b."timestamp"    > a."timestamp"
   and b."timestamp"   <= a."timestamp" + interval '48 hours'
   and (abs(extract(epoch from (b.data_hora - a.data_hora))) <= 1800
        or (b.data_hora < a.fim_ef and a.data_hora < b.fim_ef))
 order by a.equipamento_codigo, a.data_hora;
