-- ============================================================
-- update_019 — 5S COM VÁRIAS FOTOS (até 5 no antes e até 5 no depois)
-- Rodar no SQL Editor do Supabase DEPOIS do update_018. Pode rodar mais de uma vez.
-- Roda tudo em uma transação: se der erro, nada é alterado.
--
-- O QUE ISTO FAZ
--  A foto principal continua em cinco_s.foto_antes / foto_depois (o que já existe não muda).
--  Ficam de lado as fotos EXTRAS, até 4 em cada lado (total de 5 + 5):
--    cinco_s.fotos_antes_extra  — nascem junto com o registro e nunca mudam;
--    cinco_s.fotos_depois_extra — só entram na hora de concluir.
--  Todas ficam na pasta da própria área do bucket 'cinco-s' (mesma regra de acesso do update_018).
--  O gatilho cinco_s_proteger é recriado para tratar as fotos extras; a view bi.cinco_s ganha
--  as colunas fotos_antes e fotos_depois (quantidade).
--
-- NÃO MUDA: regras de quem abre, conclui, corrige e anula (as mesmas do update_018).
-- ============================================================

begin;

set local lock_timeout = '8s';

-- ---------- 1) Colunas ----------
alter table public.cinco_s add column if not exists fotos_antes_extra text[] not null default '{}';
alter table public.cinco_s add column if not exists fotos_depois_extra text[] not null default '{}';

-- todos os caminhos precisam estar na pasta da própria área (e nenhum pode ser vazio)
create or replace function public.cinco_s_caminhos_ok(a text, f text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select f is not null
     and array_position(f, null) is null
     and coalesce(bool_and(left(x, char_length(a) + 1) = a || '/' and char_length(x) > char_length(a) + 1), true)
  from unnest(f) as x;
$$;

alter table public.cinco_s drop constraint if exists cinco_s_extra_antes_ck;
alter table public.cinco_s add constraint cinco_s_extra_antes_ck
  check (cardinality(fotos_antes_extra) <= 4 and public.cinco_s_caminhos_ok(area, fotos_antes_extra));
alter table public.cinco_s drop constraint if exists cinco_s_extra_depois_ck;
alter table public.cinco_s add constraint cinco_s_extra_depois_ck
  check (cardinality(fotos_depois_extra) <= 4 and public.cinco_s_caminhos_ok(area, fotos_depois_extra)
         and (concluido_em is not null or cardinality(fotos_depois_extra) = 0));

-- ---------- 2) Gatilho (igual ao do update_018, tratando as fotos extras) ----------
create or replace function public.cinco_s_proteger()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if to_jsonb(new) = to_jsonb(old) then
    return new;
  end if;

  if old.anulado then
    raise exception 'Este 5S já foi anulado e não pode mais ser alterado.' using errcode = '42501';
  end if;

  if new.anulado is true then
    if not (select public.eh_supervisor()) then
      raise exception 'Só o supervisor anula um 5S.' using errcode = '42501';
    end if;
    if coalesce(btrim(new.anulado_motivo), '') = '' then
      raise exception 'Informe o motivo da anulação.' using errcode = '23514';
    end if;
    new.setor := old.setor; new.problema := old.problema; new.foto_antes := old.foto_antes;
    new.fotos_antes_extra := old.fotos_antes_extra;
    new.aberto_em := old.aberto_em; new.aberto_por := old.aberto_por; new.aberto_por_nome := old.aberto_por_nome;
    new.concluido_em := old.concluido_em; new.concluido_por := old.concluido_por; new.concluido_por_nome := old.concluido_por_nome;
    new.foto_depois := old.foto_depois; new.fotos_depois_extra := old.fotos_depois_extra; new.acao := old.acao;
    new.editado_em := old.editado_em; new.editado_por := old.editado_por;
    new.anulado_por := auth.uid(); new.anulado_em := now();
    return new;
  end if;

  if old.concluido_em is not null then
    raise exception 'Este 5S já foi concluído e não pode mais ser alterado. Para corrigir, anule e abra de novo.' using errcode = '42501';
  end if;

  -- daqui para baixo: o registro está em aberto
  new.foto_antes := old.foto_antes; new.fotos_antes_extra := old.fotos_antes_extra;
  new.aberto_em := old.aberto_em; new.aberto_por := old.aberto_por; new.aberto_por_nome := old.aberto_por_nome;
  new.anulado_motivo := old.anulado_motivo; new.anulado_por := old.anulado_por; new.anulado_em := old.anulado_em;

  if new.concluido_em is null then
    -- correção do que está em aberto: só setor e descrição, só o supervisor
    if not (select public.eh_supervisor()) then
      raise exception 'Só o supervisor corrige um 5S em aberto.' using errcode = '42501';
    end if;
    new.foto_depois := null; new.fotos_depois_extra := '{}'; new.acao := null; new.concluido_por := null; new.concluido_por_nome := null;
    new.editado_em := now(); new.editado_por := auth.uid();
    return new;
  end if;

  -- conclusão (qualquer pessoa da área): setor e descrição não mudam
  new.setor := old.setor; new.problema := old.problema;
  new.editado_em := old.editado_em; new.editado_por := old.editado_por;
  if coalesce(btrim(new.foto_depois), '') = '' then
    raise exception 'Tire a foto do depois.' using errcode = '23514';
  end if;
  if coalesce(btrim(new.acao), '') = '' then
    raise exception 'Informe o que foi feito.' using errcode = '23514';
  end if;
  if new.concluido_em > now() + interval '1 hour' then
    raise exception 'A conclusão não pode estar no futuro.' using errcode = '23514';
  end if;
  if new.concluido_em < old.aberto_em then
    raise exception 'A conclusão não pode ser antes da abertura (%).', to_char(old.aberto_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') using errcode = '23514';
  end if;
  new.concluido_por := auth.uid();
  return new;
end;
$$;

-- ---------- 3) Quem pode gravar o quê ----------
-- abrir: as fotos extras do depois só entram na conclusão
drop policy if exists "cinco_s_insert" on public.cinco_s;
create policy "cinco_s_insert" on public.cinco_s for insert to authenticated
  with check (area = any ((select public.areas_do_usuario())::text[])
    and (aberto_por is null or aberto_por = auth.uid())
    and not anulado and concluido_em is null and foto_depois is null and acao is null
    and cardinality(fotos_depois_extra) = 0);
-- concluir pode gravar as fotos extras do depois (as do antes não são editáveis)
grant update (fotos_depois_extra) on public.cinco_s to authenticated;

-- ---------- 4) Power BI ----------
-- (colunas novas só no fim da view, para não quebrar o que já está no Power BI)
create or replace view bi.cinco_s as
select
  c.id,
  c.setor,
  c.problema,
  (c.aberto_em at time zone 'America/Sao_Paulo') as aberto_em,
  c.aberto_por_nome,
  (c.concluido_em at time zone 'America/Sao_Paulo') as concluido_em,
  c.concluido_por_nome,
  c.acao,
  case when c.concluido_em is null then null
       else round((extract(epoch from (c.concluido_em - c.aberto_em)) / 3600)::numeric, 2) end as horas_ate_concluir,
  case when c.concluido_em is null then 'em aberto' else 'concluído' end as situacao,
  1 + cardinality(c.fotos_antes_extra) as fotos_antes,
  case when c.foto_depois is null then 0 else 1 + cardinality(c.fotos_depois_extra) end as fotos_depois
from public.cinco_s c
where not c.anulado;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'powerbi_leitor') then
    grant usage on schema bi to powerbi_leitor;
    grant select on all tables in schema bi to powerbi_leitor;
  end if;
end $$;

commit;

-- ============================================================
-- DESFAZER (antes de haver fotos extras): rode de novo o update_018 (recria o gatilho antigo) e depois
--   alter table public.cinco_s drop column fotos_antes_extra, drop column fotos_depois_extra;
-- ============================================================
