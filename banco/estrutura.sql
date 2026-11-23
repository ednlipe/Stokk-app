--
-- PostgreSQL database dump
--

\restrict b2f4f5AIB8G8G5zqecRYleehdsSOI02mj6hp1v5Kje4o0Lcw6Mratgq8PJ9Iuzl

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: bi; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA bi;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: area_do_usuario(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.area_do_usuario() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select p.area
  from public.profiles p
  join public.areas a on a.id = p.area
  where p.id = auth.uid() and p.ativo and a.ativa;
$$;


--
-- Name: area_padrao(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.area_padrao() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select p.area from public.profiles p where p.id = auth.uid()), 'trefila');
$$;


--
-- Name: areas_do_usuario(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.areas_do_usuario() RETURNS text[]
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(array_agg(distinct x.area), '{}'::text[])
  from (
    select p.area from public.profiles p where p.id = auth.uid() and p.ativo and p.area is not null
    union
    select ua.area from public.usuario_areas ua
      join public.profiles p on p.id = ua.user_id
      where ua.user_id = auth.uid() and p.ativo
  ) x
  join public.areas a on a.id = x.area and a.ativa;
$$;


--
-- Name: cinco_s_caminhos_ok(text, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cinco_s_caminhos_ok(a text, f text[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select f is not null
     and array_position(f, null) is null
     and coalesce(bool_and(left(x, char_length(a) + 1) = a || '/' and char_length(x) > char_length(a) + 1), true)
  from unnest(f) as x;
$$;


--
-- Name: cinco_s_proteger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cinco_s_proteger() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
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


--
-- Name: diesel_proteger_anulacao(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.diesel_proteger_anulacao() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if old.anulado then
    raise exception 'Este lançamento já foi anulado e não pode mais ser alterado.' using errcode = '42501';
  end if;
  if new.anulado is not true then
    raise exception 'Lançamentos não são editados: para corrigir, anule e lance de novo.' using errcode = '42501';
  end if;
  if coalesce(btrim(new.anulado_motivo), '') = '' then
    raise exception 'Informe o motivo da anulação.' using errcode = '23514';
  end if;
  new.anulado_por := auth.uid();
  new.anulado_em := now();
  return new;
end;
$$;


--
-- Name: diesel_validar_abastecimento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.diesel_validar_abastecimento() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare ant numeric;
begin
  if not new.troca_medidor then
    select a.medidor into ant
    from public.abastecimentos a
    where a.equipamento_id = new.equipamento_id and not a.anulado and a.data_hora <= new.data_hora
    order by a.data_hora desc, a."timestamp" desc
    limit 1;
    if ant is not null and new.medidor < ant then
      raise exception 'O medidor (%) é menor que o do abastecimento anterior (%). Confira, ou marque "troca de medidor".', new.medidor, ant
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;


--
-- Name: eh_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.eh_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.ativo and p.admin);
$$;


--
-- Name: eh_supervisor(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.eh_supervisor() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.ativo and p.role = 'supervisor');
$$;


--
-- Name: eh_usuario_ativo(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.eh_usuario_ativo() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.ativo);
$$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  insert into public.profiles (id, nome, role, ativo)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', split_part(new.email, '@', 1)), 'operador', false);
  return new;
end;
$$;


--
-- Name: impedir_autopromocao_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.impedir_autopromocao_role() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
begin
  if new.role is distinct from old.role and auth.uid() is not null then
    raise exception 'Alterar o próprio nível de acesso (role) não é permitido pelo app. Peça a um administrador para trocar isso pelo SQL Editor do Supabase.';
  end if;
  return new;
end;
$$;


--
-- Name: ocorrencia_proteger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ocorrencia_proteger() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  -- a Edge Function (service_role) só marca "aviso enviado": isso pode acontecer mesmo depois de liberada/anulada
  if (to_jsonb(new) - 'aviso_abertura_em' - 'aviso_liberacao_em') = (to_jsonb(old) - 'aviso_abertura_em' - 'aviso_liberacao_em') then
    return new;
  end if;

  if old.anulado then
    raise exception 'Esta ocorrência já foi anulada e não pode mais ser alterada.' using errcode = '42501';
  end if;

  if new.anulado is true then
    -- anulação: exige motivo, grava quem/quando e não deixa mexer em mais nada
    if coalesce(btrim(new.anulado_motivo), '') = '' then
      raise exception 'Informe o motivo da anulação.' using errcode = '23514';
    end if;
    new.categoria := old.categoria; new.motivo := old.motivo; new.descricao := old.descricao;
    new.editada_em := old.editada_em; new.editada_por := old.editada_por;
    new.liberada_em := old.liberada_em; new.liberada_registro_em := old.liberada_registro_em;
    new.liberada_por := old.liberada_por; new.liberada_por_nome := old.liberada_por_nome;
    new.motivo_liberacao := old.motivo_liberacao; new.servico_realizado := old.servico_realizado; new.recebido_por := old.recebido_por;
    new.anulado_por := auth.uid(); new.anulado_em := now();
    return new;
  end if;

  if old.liberada_em is not null then
    raise exception 'Esta ocorrência já foi liberada e não pode mais ser alterada. Para corrigir, anule e abra de novo.' using errcode = '42501';
  end if;

  if new.liberada_em is null then
    -- correção da ocorrência ainda em aberto: só categoria, motivo e descrição
    if coalesce(btrim(new.motivo), '') = '' then
      raise exception 'Informe o motivo.' using errcode = '23514';
    end if;
    if coalesce(btrim(new.descricao), '') = '' then
      raise exception 'Descreva o que está acontecendo.' using errcode = '23514';
    end if;
    new.liberada_por_nome := old.liberada_por_nome; new.motivo_liberacao := old.motivo_liberacao;
    new.servico_realizado := old.servico_realizado; new.recebido_por := old.recebido_por;
    new.editada_em := now(); new.editada_por := auth.uid();
    return new;
  end if;

  if new.liberada_em > now() + interval '1 hour' then
    raise exception 'A liberação não pode estar no futuro.' using errcode = '23514';
  end if;
  if new.liberada_em < old.aberta_em then
    raise exception 'A liberação não pode ser antes da abertura (%).', to_char(old.aberta_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') using errcode = '23514';
  end if;
  if coalesce(btrim(new.servico_realizado), '') = '' then
    raise exception 'Informe o que foi feito no equipamento.' using errcode = '23514';
  end if;
  if coalesce(btrim(new.recebido_por), '') = '' then
    raise exception 'Informe quem pegou o equipamento.' using errcode = '23514';
  end if;
  if coalesce(btrim(new.motivo_liberacao), '') = '' then
    raise exception 'Informe o motivo da liberação.' using errcode = '23514';
  end if;
  new.liberada_registro_em := now();
  new.liberada_por := auth.uid();
  return new;
end;
$$;


--
-- Name: proteger_area_registro(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.proteger_area_registro() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if auth.uid() is not null and new.area is distinct from old.area then
    raise exception 'Um registro não pode mudar de área (o lote já existe na outra área).' using errcode = '42501';
  end if;
  return new;
end;
$$;


--
-- Name: proteger_profiles(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.proteger_profiles() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
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


--
-- Name: registrar_auditoria(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.registrar_auditoria() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  k text := tg_argv[0];
  old_j jsonb;
  new_j jsonb;
  nome text;
begin
  old_j := to_jsonb(old);
  if tg_op = 'DELETE' then
    new_j := null;
  else
    new_j := to_jsonb(new);
  end if;
  select p.nome into nome from public.profiles p where p.id = auth.uid();
  insert into public.audit_log (usuario_nome, tabela, operacao, chave, antes, depois)
  values (nome, tg_table_name, tg_op, coalesce(new_j, old_j) ->> k, old_j, new_j);
  return null;
end;
$$;


--
-- Name: registrar_push_token(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.registrar_push_token(p_token text, p_plataforma text DEFAULT 'android'::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if auth.uid() is null or not public.eh_usuario_ativo() then
    raise exception 'não autorizado';
  end if;
  insert into public.push_tokens(token, user_id, plataforma, atualizado_em)
  values (p_token, auth.uid(), p_plataforma, now())
  on conflict (token) do update
    set user_id = excluded.user_id, plataforma = excluded.plataforma, atualizado_em = now();
end;
$$;


--
-- Name: stokkbook_de_cinco_s(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stokkbook_de_cinco_s() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if new.anulado and not old.anulado then
    update public.stokkbook_posts
       set oculto = true, oculto_motivo = '5S anulado'
     where tipo = 'cinco_s' and ref_id = new.id and not oculto;
    return new;
  end if;
  if old.concluido_em is null and new.concluido_em is not null and not new.anulado and new.postar_stokkbook then
    insert into public.stokkbook_posts
      (tipo, ref_id, area, autor_id, autor_nome, setor, problema, acao, foto_antes, foto_depois, fotos_antes, fotos_depois, horas, quando)
    values
      ('cinco_s', new.id, new.area, new.concluido_por, new.concluido_por_nome, new.setor, new.problema, new.acao,
       new.foto_antes, new.foto_depois, 1 + cardinality(new.fotos_antes_extra), 1 + cardinality(new.fotos_depois_extra),
       round((extract(epoch from (new.concluido_em - new.aberto_em)) / 3600)::numeric, 2), new.concluido_em)
    on conflict (tipo, ref_id) do nothing;
  end if;
  return new;
end;
$$;


--
-- Name: stokkbook_posts_proteger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stokkbook_posts_proteger() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if new.oculto is distinct from old.oculto then
    if new.oculto and coalesce(btrim(new.oculto_motivo), '') = '' then
      raise exception 'Informe o motivo para ocultar.' using errcode = '23514';
    end if;
    if not new.oculto then new.oculto_motivo := null; end if;
    new.oculto_por := auth.uid();
    new.oculto_em := now();
  end if;
  return new;
end;
$$;


--
-- Name: stokkbook_reacoes_proteger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stokkbook_reacoes_proteger() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if auth.uid() is not null then
    new.user_id := auth.uid();
    new.user_nome := (select p.nome from public.profiles p where p.id = auth.uid());
  end if;
  if tg_op = 'UPDATE' then new.post_id := old.post_id; end if;
  return new;
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: areas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.areas (
    id text NOT NULL,
    nome text NOT NULL,
    ativa boolean DEFAULT true NOT NULL,
    criada_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT areas_id_check CHECK ((id ~ '^[a-z0-9_]+$'::text))
);


--
-- Name: areas; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.areas AS
 SELECT id AS area,
    nome AS area_nome,
    ativa
   FROM public.areas;


--
-- Name: armazens_area; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.armazens_area (
    area text NOT NULL,
    armazem text NOT NULL,
    descricao text
);


--
-- Name: armazens_area; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.armazens_area AS
 SELECT a.area,
    ar.nome AS area_nome,
    a.armazem,
    a.descricao
   FROM (public.armazens_area a
     JOIN public.areas ar ON ((ar.id = a.area)));


--
-- Name: cinco_s; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cinco_s (
    id text NOT NULL,
    setor text NOT NULL,
    problema text NOT NULL,
    foto_antes text NOT NULL,
    aberto_em timestamp with time zone DEFAULT now() NOT NULL,
    aberto_por uuid,
    aberto_por_nome text,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    concluido_em timestamp with time zone,
    concluido_por uuid,
    concluido_por_nome text,
    foto_depois text,
    acao text,
    editado_em timestamp with time zone,
    editado_por uuid,
    anulado boolean DEFAULT false NOT NULL,
    anulado_motivo text,
    anulado_por uuid,
    anulado_em timestamp with time zone,
    area text DEFAULT 'gestao_p1'::text NOT NULL,
    fotos_antes_extra text[] DEFAULT '{}'::text[] NOT NULL,
    fotos_depois_extra text[] DEFAULT '{}'::text[] NOT NULL,
    postar_stokkbook boolean DEFAULT true NOT NULL,
    CONSTRAINT cinco_s_aberto_em_check CHECK ((aberto_em <= (now() + '01:00:00'::interval))),
    CONSTRAINT cinco_s_acao_check CHECK (((acao IS NULL) OR (char_length(acao) <= 500))),
    CONSTRAINT cinco_s_check CHECK (("left"(foto_antes, (char_length(area) + 1)) = (area || '/'::text))),
    CONSTRAINT cinco_s_check1 CHECK (((foto_depois IS NULL) OR ("left"(foto_depois, (char_length(area) + 1)) = (area || '/'::text)))),
    CONSTRAINT cinco_s_check2 CHECK ((((concluido_em IS NULL) = (foto_depois IS NULL)) AND ((concluido_em IS NULL) = (acao IS NULL)))),
    CONSTRAINT cinco_s_extra_antes_ck CHECK (((cardinality(fotos_antes_extra) <= 4) AND public.cinco_s_caminhos_ok(area, fotos_antes_extra))),
    CONSTRAINT cinco_s_extra_depois_ck CHECK (((cardinality(fotos_depois_extra) <= 4) AND public.cinco_s_caminhos_ok(area, fotos_depois_extra) AND ((concluido_em IS NOT NULL) OR (cardinality(fotos_depois_extra) = 0)))),
    CONSTRAINT cinco_s_problema_check CHECK (((btrim(problema) <> ''::text) AND (char_length(problema) <= 300))),
    CONSTRAINT cinco_s_setor_check CHECK (((btrim(setor) <> ''::text) AND (char_length(setor) <= 80)))
);


--
-- Name: cinco_s; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.cinco_s AS
 SELECT id,
    setor,
    problema,
    (aberto_em AT TIME ZONE 'America/Sao_Paulo'::text) AS aberto_em,
    aberto_por_nome,
    (concluido_em AT TIME ZONE 'America/Sao_Paulo'::text) AS concluido_em,
    concluido_por_nome,
    acao,
        CASE
            WHEN (concluido_em IS NULL) THEN NULL::numeric
            ELSE round((EXTRACT(epoch FROM (concluido_em - aberto_em)) / (3600)::numeric), 2)
        END AS horas_ate_concluir,
        CASE
            WHEN (concluido_em IS NULL) THEN 'em aberto'::text
            ELSE 'concluído'::text
        END AS situacao,
    (1 + cardinality(fotos_antes_extra)) AS fotos_antes,
        CASE
            WHEN (foto_depois IS NULL) THEN 0
            ELSE (1 + cardinality(fotos_depois_extra))
        END AS fotos_depois
   FROM public.cinco_s c
  WHERE (NOT anulado);


--
-- Name: sessoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessoes (
    id text NOT NULL,
    iniciado_em timestamp with time zone,
    ativo boolean,
    contados jsonb,
    filtro_produto text,
    finalizado_em timestamp with time zone,
    resultado jsonb,
    usuario_id uuid,
    esperados_snapshot jsonb,
    nome text,
    area text DEFAULT public.area_padrao() NOT NULL,
    tipo text DEFAULT 'normal'::text NOT NULL,
    itens jsonb,
    CONSTRAINT sessoes_tipo_check CHECK ((tipo = ANY (ARRAY['normal'::text, 'cega'::text])))
);


--
-- Name: conferencias; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.conferencias AS
 SELECT s.id,
    COALESCE(NULLIF(TRIM(BOTH FROM s.nome), ''::text), 'Sem nome'::text) AS nome,
    (s.iniciado_em AT TIME ZONE 'America/Sao_Paulo'::text) AS iniciado_em,
    (s.finalizado_em AT TIME ZONE 'America/Sao_Paulo'::text) AS finalizado_em,
        CASE
            WHEN s.ativo THEN 'Em andamento'::text
            ELSE 'Finalizada'::text
        END AS situacao,
    s.filtro_produto,
        CASE
            WHEN (jsonb_typeof(s.contados) = 'array'::text) THEN jsonb_array_length(s.contados)
            ELSE 0
        END AS itens_contados,
        CASE
            WHEN (jsonb_typeof(s.esperados_snapshot) = 'array'::text) THEN jsonb_array_length(s.esperados_snapshot)
            ELSE 0
        END AS itens_esperados,
        CASE
            WHEN (jsonb_typeof((s.resultado -> 'faltando'::text)) = 'array'::text) THEN jsonb_array_length((s.resultado -> 'faltando'::text))
            ELSE 0
        END AS itens_faltando,
    s.area,
    ar.nome AS area_nome
   FROM (public.sessoes s
     LEFT JOIN public.areas ar ON ((ar.id = s.area)));


--
-- Name: abastecimentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.abastecimentos (
    id text NOT NULL,
    equipamento_id text NOT NULL,
    equipamento_codigo text,
    tanque_id text NOT NULL,
    data_hora timestamp with time zone DEFAULT now() NOT NULL,
    medidor numeric NOT NULL,
    litros numeric NOT NULL,
    custo_litro numeric,
    custo_total numeric,
    troca_medidor boolean DEFAULT false NOT NULL,
    obs text,
    usuario_id uuid,
    usuario_nome text,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    anulado boolean DEFAULT false NOT NULL,
    anulado_motivo text,
    anulado_por uuid,
    anulado_em timestamp with time zone,
    area text DEFAULT 'gestao'::text NOT NULL,
    CONSTRAINT abastecimentos_custo_litro_check CHECK (((custo_litro IS NULL) OR (custo_litro >= (0)::numeric))),
    CONSTRAINT abastecimentos_custo_total_check CHECK (((custo_total IS NULL) OR (custo_total >= (0)::numeric))),
    CONSTRAINT abastecimentos_data_hora_check CHECK ((data_hora <= (now() + '01:00:00'::interval))),
    CONSTRAINT abastecimentos_litros_check CHECK ((litros > (0)::numeric)),
    CONSTRAINT abastecimentos_medidor_check CHECK ((medidor >= (0)::numeric))
);


--
-- Name: equipamentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.equipamentos (
    id text NOT NULL,
    codigo text NOT NULL,
    nome text NOT NULL,
    tipo text DEFAULT 'maquina'::text NOT NULL,
    medidor text DEFAULT 'h'::text NOT NULL,
    area_uso text[] DEFAULT '{}'::text[] NOT NULL,
    dias_alerta integer DEFAULT 2 NOT NULL,
    alerta_dias_uteis boolean DEFAULT false NOT NULL,
    alerta_ativo boolean DEFAULT true NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    usuario_id uuid,
    usuario_nome text,
    area text DEFAULT 'gestao'::text NOT NULL,
    setor text,
    CONSTRAINT equipamentos_dias_alerta_check CHECK (((dias_alerta >= 1) AND (dias_alerta <= 60))),
    CONSTRAINT equipamentos_medidor_check CHECK ((medidor = ANY (ARRAY['h'::text, 'km'::text]))),
    CONSTRAINT equipamentos_setor_ck CHECK (((setor IS NULL) OR ((btrim(setor) <> ''::text) AND (char_length(setor) <= 60)))),
    CONSTRAINT equipamentos_tipo_check CHECK ((tipo = ANY (ARRAY['maquina'::text, 'caminhao'::text, 'outro'::text])))
);


--
-- Name: tanques; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tanques (
    id text NOT NULL,
    nome text NOT NULL,
    capacidade_l numeric,
    minimo_l numeric,
    ativo boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    usuario_id uuid,
    usuario_nome text,
    area text DEFAULT 'gestao'::text NOT NULL,
    CONSTRAINT tanques_capacidade_l_check CHECK (((capacidade_l IS NULL) OR (capacidade_l > (0)::numeric))),
    CONSTRAINT tanques_minimo_l_check CHECK (((minimo_l IS NULL) OR (minimo_l >= (0)::numeric)))
);


--
-- Name: diesel_abastecimentos; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.diesel_abastecimentos AS
 SELECT a.id,
    (a.data_hora AT TIME ZONE 'America/Sao_Paulo'::text) AS data_hora,
    e.codigo AS equipamento,
    e.nome AS equipamento_nome,
    e.tipo AS equipamento_tipo,
    e.medidor AS unidade_medidor,
    a.medidor AS leitura_medidor,
    a.litros,
    a.custo_litro,
    a.custo_total,
    a.troca_medidor,
    t.nome AS tanque,
    a.usuario_nome,
    a.obs
   FROM ((public.abastecimentos a
     JOIN public.equipamentos e ON ((e.id = a.equipamento_id)))
     JOIN public.tanques t ON ((t.id = a.tanque_id)))
  WHERE (NOT a.anulado);


--
-- Name: tanque_entradas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tanque_entradas (
    id text NOT NULL,
    tanque_id text NOT NULL,
    data_hora timestamp with time zone DEFAULT now() NOT NULL,
    litros numeric NOT NULL,
    preco_litro numeric NOT NULL,
    valor_total numeric NOT NULL,
    fornecedor text,
    nota text,
    obs text,
    usuario_id uuid,
    usuario_nome text,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    anulado boolean DEFAULT false NOT NULL,
    anulado_motivo text,
    anulado_por uuid,
    anulado_em timestamp with time zone,
    area text DEFAULT 'gestao'::text NOT NULL,
    CONSTRAINT tanque_entradas_data_hora_check CHECK ((data_hora <= (now() + '01:00:00'::interval))),
    CONSTRAINT tanque_entradas_litros_check CHECK ((litros > (0)::numeric)),
    CONSTRAINT tanque_entradas_preco_litro_check CHECK ((preco_litro >= (0)::numeric)),
    CONSTRAINT tanque_entradas_valor_total_check CHECK ((valor_total >= (0)::numeric))
);


--
-- Name: diesel_entradas; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.diesel_entradas AS
 SELECT x.id,
    (x.data_hora AT TIME ZONE 'America/Sao_Paulo'::text) AS data_hora,
    t.nome AS tanque,
    x.litros,
    x.preco_litro,
    x.valor_total,
    x.fornecedor,
    x.nota,
    x.usuario_nome
   FROM (public.tanque_entradas x
     JOIN public.tanques t ON ((t.id = x.tanque_id)))
  WHERE (NOT x.anulado);


--
-- Name: diesel_equipamentos; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.diesel_equipamentos AS
 SELECT codigo AS equipamento,
    nome,
    tipo,
    medidor AS unidade_medidor,
    area_uso,
    ativo
   FROM public.equipamentos;


--
-- Name: equipamento_locais; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.equipamento_locais (
    id text NOT NULL,
    equipamento_id text NOT NULL,
    equipamento_codigo text,
    local text NOT NULL,
    obs text,
    data_hora timestamp with time zone DEFAULT now() NOT NULL,
    usuario_id uuid,
    usuario_nome text,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    anulado boolean DEFAULT false NOT NULL,
    anulado_motivo text,
    anulado_por uuid,
    anulado_em timestamp with time zone,
    area text DEFAULT 'gestao'::text NOT NULL,
    data_fim timestamp with time zone,
    atividade text,
    solicitante text,
    CONSTRAINT equipamento_locais_atividade_ck CHECK (((atividade IS NULL) OR ((btrim(atividade) <> ''::text) AND (char_length(atividade) <= 200)))),
    CONSTRAINT equipamento_locais_data_hora_check CHECK ((data_hora <= (now() + '01:00:00'::interval))),
    CONSTRAINT equipamento_locais_fim_ck CHECK (((data_fim IS NULL) OR (data_fim >= data_hora))),
    CONSTRAINT equipamento_locais_local_check CHECK (((btrim(local) <> ''::text) AND (char_length(local) <= 120))),
    CONSTRAINT equipamento_locais_solicitante_ck CHECK (((solicitante IS NULL) OR ((btrim(solicitante) <> ''::text) AND (char_length(solicitante) <= 120))))
);


--
-- Name: equipamento_locais; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.equipamento_locais AS
 SELECT l.id,
    e.codigo AS equipamento,
    e.nome AS equipamento_nome,
    l.local,
    l.obs,
    (l.data_hora AT TIME ZONE 'America/Sao_Paulo'::text) AS desde,
    l.usuario_nome,
    (l.data_fim AT TIME ZONE 'America/Sao_Paulo'::text) AS fim,
    e.setor,
    l.atividade,
    l.solicitante
   FROM (public.equipamento_locais l
     JOIN public.equipamentos e ON ((e.id = l.equipamento_id)))
  WHERE (NOT l.anulado);


--
-- Name: equipamento_local_atual; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.equipamento_local_atual AS
 SELECT DISTINCT ON (l.equipamento_id) e.codigo AS equipamento,
    e.nome AS equipamento_nome,
    l.local,
    l.obs,
    (l.data_hora AT TIME ZONE 'America/Sao_Paulo'::text) AS desde,
    l.usuario_nome,
    e.setor,
    l.atividade,
    l.solicitante
   FROM (public.equipamento_locais l
     JOIN public.equipamentos e ON ((e.id = l.equipamento_id)))
  WHERE (NOT l.anulado)
  ORDER BY l.equipamento_id, l.data_hora DESC, l."timestamp" DESC;


--
-- Name: produtos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.produtos (
    codigo text NOT NULL,
    descricao text,
    um text,
    tipo text,
    grupo text,
    atualizado_em timestamp with time zone DEFAULT now()
);


--
-- Name: volumes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.volumes (
    lote text NOT NULL,
    produto_codigo text,
    produto_descricao text,
    armazem text,
    quantidade numeric,
    saldo_acumulado numeric,
    categoria text,
    tipo_mov text,
    status text DEFAULT 'estoque'::text,
    origem text,
    status_conferencia text,
    ultima_conferencia_sessao text,
    ultima_conferencia_em timestamp with time zone,
    importado_em timestamp with time zone,
    criado_em timestamp with time zone DEFAULT now(),
    atualizado_em timestamp with time zone DEFAULT now(),
    area text DEFAULT public.area_padrao() NOT NULL
);


--
-- Name: estoque; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.estoque AS
 SELECT v.lote,
    v.produto_codigo,
    COALESCE(p.descricao, v.produto_descricao) AS produto_descricao,
    p.grupo AS produto_grupo,
    v.armazem,
    v.categoria,
    round((v.quantidade / 1000.0), 3) AS quantidade_ton,
    round(v.quantidade, 1) AS quantidade_kg,
    COALESCE(v.status, 'estoque'::text) AS status,
        CASE v.status_conferencia
            WHEN 'contado'::text THEN 'Em estoque (contado)'::text
            WHEN 'nao_conferido'::text THEN 'Não localizado'::text
            ELSE 'Aguardando conferência'::text
        END AS situacao_conferencia,
    v.origem,
    (v.importado_em AT TIME ZONE 'America/Sao_Paulo'::text) AS importado_em,
    (v.ultima_conferencia_em AT TIME ZONE 'America/Sao_Paulo'::text) AS ultima_conferencia_em,
    (v.atualizado_em AT TIME ZONE 'America/Sao_Paulo'::text) AS atualizado_em,
    v.area,
    ar.nome AS area_nome
   FROM ((public.volumes v
     LEFT JOIN public.produtos p ON ((p.codigo = v.produto_codigo)))
     LEFT JOIN public.areas ar ON ((ar.id = v.area)));


--
-- Name: ocorrencias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ocorrencias (
    id text NOT NULL,
    equipamento_id text NOT NULL,
    equipamento_codigo text,
    categoria text NOT NULL,
    motivo text NOT NULL,
    descricao text NOT NULL,
    aberta_em timestamp with time zone DEFAULT now() NOT NULL,
    aberta_por uuid,
    aberta_por_nome text,
    liberada_em timestamp with time zone,
    liberada_registro_em timestamp with time zone,
    liberada_por uuid,
    liberada_por_nome text,
    motivo_liberacao text,
    servico_realizado text,
    recebido_por text,
    aviso_abertura_em timestamp with time zone,
    aviso_liberacao_em timestamp with time zone,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    anulado boolean DEFAULT false NOT NULL,
    anulado_motivo text,
    anulado_por uuid,
    anulado_em timestamp with time zone,
    area text DEFAULT 'gestao'::text NOT NULL,
    editada_em timestamp with time zone,
    editada_por uuid,
    CONSTRAINT ocorrencias_aberta_em_check CHECK ((aberta_em <= (now() + '01:00:00'::interval))),
    CONSTRAINT ocorrencias_categoria_check CHECK ((categoria = ANY (ARRAY['manutencao'::text, 'parada'::text]))),
    CONSTRAINT ocorrencias_check CHECK (((liberada_em IS NULL) OR (liberada_em >= aberta_em))),
    CONSTRAINT ocorrencias_check1 CHECK (((liberada_em IS NULL) OR ((btrim(COALESCE(servico_realizado, ''::text)) <> ''::text) AND (btrim(COALESCE(recebido_por, ''::text)) <> ''::text) AND (btrim(COALESCE(motivo_liberacao, ''::text)) <> ''::text)))),
    CONSTRAINT ocorrencias_descricao_check CHECK ((btrim(descricao) <> ''::text)),
    CONSTRAINT ocorrencias_motivo_check CHECK ((btrim(motivo) <> ''::text))
);


--
-- Name: manutencao_ocorrencias; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.manutencao_ocorrencias AS
 SELECT o.id,
    e.codigo AS equipamento,
    e.nome AS equipamento_nome,
    e.tipo AS equipamento_tipo,
        CASE o.categoria
            WHEN 'manutencao'::text THEN 'Manutenção'::text
            ELSE 'Parada operacional'::text
        END AS categoria,
    o.motivo,
    o.descricao,
    (o.aberta_em AT TIME ZONE 'America/Sao_Paulo'::text) AS aberta_em,
    o.aberta_por_nome,
    (o.liberada_em AT TIME ZONE 'America/Sao_Paulo'::text) AS liberada_em,
    o.motivo_liberacao,
    o.servico_realizado,
    o.recebido_por,
    o.liberada_por_nome,
        CASE
            WHEN (o.liberada_em IS NULL) THEN 'Em aberto'::text
            ELSE 'Liberada'::text
        END AS situacao,
    round((EXTRACT(epoch FROM (COALESCE(o.liberada_em, now()) - o.aberta_em)) / (3600)::numeric), 2) AS horas_parado
   FROM (public.ocorrencias o
     JOIN public.equipamentos e ON ((e.id = o.equipamento_id)))
  WHERE (NOT o.anulado);


--
-- Name: movimentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movimentos (
    id text NOT NULL,
    lote text,
    produto_codigo text,
    produto_descricao text,
    tipo text,
    quantidade numeric,
    "timestamp" timestamp with time zone DEFAULT now(),
    exportado boolean DEFAULT false,
    obs text,
    usuario_id uuid,
    usuario_nome text,
    area text DEFAULT public.area_padrao() NOT NULL
);


--
-- Name: movimentos; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.movimentos AS
 SELECT m.id,
    m.lote,
    m.produto_codigo,
    m.produto_descricao,
    m.tipo,
    m.quantidade,
    (m."timestamp" AT TIME ZONE 'America/Sao_Paulo'::text) AS data_hora,
    ((m."timestamp" AT TIME ZONE 'America/Sao_Paulo'::text))::date AS data,
    m.obs,
    m.usuario_nome,
    m.area,
    ar.nome AS area_nome
   FROM (public.movimentos m
     LEFT JOIN public.areas ar ON ((ar.id = m.area)));


--
-- Name: producoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producoes (
    id text NOT NULL,
    equipamento text NOT NULL,
    etapa text,
    codigo_produto text,
    consumidos jsonb DEFAULT '[]'::jsonb,
    produzidos jsonb DEFAULT '[]'::jsonb,
    iniciado_em timestamp with time zone,
    finalizado_em timestamp with time zone,
    resultado jsonb,
    usuario_id uuid,
    usuario_nome text,
    turno integer,
    data_producao date,
    area text DEFAULT public.area_padrao() NOT NULL
);


--
-- Name: producoes; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.producoes AS
 WITH base AS (
         SELECT p.id,
            p.equipamento,
            p.etapa,
            p.codigo_produto,
            p.consumidos,
            p.produzidos,
            p.iniciado_em,
            p.finalizado_em,
            p.resultado,
            p.usuario_id,
            p.usuario_nome,
            p.turno,
            p.data_producao,
            p.area,
            (COALESCE(p.finalizado_em, p.iniciado_em) AT TIME ZONE 'America/Sao_Paulo'::text) AS ts_local
           FROM public.producoes p
        ), calc AS (
         SELECT b.id,
            b.equipamento,
            b.etapa,
            b.codigo_produto,
            b.consumidos,
            b.produzidos,
            b.iniciado_em,
            b.finalizado_em,
            b.resultado,
            b.usuario_id,
            b.usuario_nome,
            b.turno,
            b.data_producao,
            b.area,
            b.ts_local,
            ((EXTRACT(hour FROM b.ts_local) * (60)::numeric) + EXTRACT(minute FROM b.ts_local)) AS minutos,
            COALESCE(
                CASE
                    WHEN ((b.turno >= 1) AND (b.turno <= 3)) THEN b.turno
                    ELSE NULL::integer
                END,
                CASE
                    WHEN ((((EXTRACT(hour FROM b.ts_local) * (60)::numeric) + EXTRACT(minute FROM b.ts_local)) >= (430)::numeric) AND (((EXTRACT(hour FROM b.ts_local) * (60)::numeric) + EXTRACT(minute FROM b.ts_local)) < (910)::numeric)) THEN 1
                    WHEN ((((EXTRACT(hour FROM b.ts_local) * (60)::numeric) + EXTRACT(minute FROM b.ts_local)) >= (910)::numeric) AND (((EXTRACT(hour FROM b.ts_local) * (60)::numeric) + EXTRACT(minute FROM b.ts_local)) < (1390)::numeric)) THEN 2
                    ELSE 3
                END) AS turno_calc
           FROM base b
        )
 SELECT c.id,
    c.equipamento,
    c.etapa,
    c.codigo_produto,
    c.turno_calc AS turno,
    COALESCE(c.data_producao,
        CASE
            WHEN ((c.turno_calc = 3) AND (c.minutos < (430)::numeric)) THEN ((c.ts_local)::date - 1)
            ELSE (c.ts_local)::date
        END) AS data_producao,
    (c.iniciado_em AT TIME ZONE 'America/Sao_Paulo'::text) AS iniciado_em,
    (c.finalizado_em AT TIME ZONE 'America/Sao_Paulo'::text) AS finalizado_em,
    ((c.resultado ->> 'consumidoKg'::text))::numeric AS consumido_kg,
    ((c.resultado ->> 'produzidoKg'::text))::numeric AS produzido_kg,
    (((c.resultado ->> 'consumidoKg'::text))::numeric - ((c.resultado ->> 'produzidoKg'::text))::numeric) AS perda_kg,
    round(((((c.resultado ->> 'produzidoKg'::text))::numeric / NULLIF(((c.resultado ->> 'consumidoKg'::text))::numeric, (0)::numeric)) * (100)::numeric), 2) AS rendimento_pct,
        CASE
            WHEN (jsonb_typeof(c.consumidos) = 'array'::text) THEN jsonb_array_length(c.consumidos)
            ELSE 0
        END AS qtd_consumidos,
        CASE
            WHEN (jsonb_typeof(c.produzidos) = 'array'::text) THEN jsonb_array_length(c.produzidos)
            ELSE 0
        END AS qtd_produzidos,
    c.usuario_nome,
    c.area,
    ar.nome AS area_nome
   FROM (calc c
     LEFT JOIN public.areas ar ON ((ar.id = c.area)));


--
-- Name: producao_itens; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.producao_itens AS
 SELECT pr.id AS producao_id,
    pr.equipamento,
    pr.turno,
    pr.data_producao,
    pr.etapa,
    x.lado,
    (x.item ->> 'lote'::text) AS lote,
    (x.item ->> 'corrida'::text) AS corrida,
    ((x.item ->> 'pesoKg'::text))::numeric AS peso_kg,
    (x.item ->> 'produtoCodigo'::text) AS produto_codigo,
    (x.item ->> 'produtoDescricao'::text) AS produto_descricao,
    COALESCE(((x.item ->> 'manual'::text))::boolean, false) AS digitado_manual,
    COALESCE(((x.item ->> 'divergente'::text))::boolean, false) AS produto_divergente,
    pr.area,
    pr.area_nome
   FROM ((bi.producoes pr
     JOIN public.producoes raw ON ((raw.id = pr.id)))
     CROSS JOIN LATERAL ( SELECT 'Consumido'::text AS lado,
            i.value AS item
           FROM jsonb_array_elements(
                CASE
                    WHEN (jsonb_typeof(raw.consumidos) = 'array'::text) THEN raw.consumidos
                    ELSE '[]'::jsonb
                END) i(value)
        UNION ALL
         SELECT 'Produzido'::text,
            i.value AS i
           FROM jsonb_array_elements(
                CASE
                    WHEN (jsonb_typeof(raw.produzidos) = 'array'::text) THEN raw.produzidos
                    ELSE '[]'::jsonb
                END) i(value)) x);


--
-- Name: rendimento_turno; Type: VIEW; Schema: bi; Owner: -
--

CREATE VIEW bi.rendimento_turno AS
 SELECT data_producao,
    equipamento,
    turno,
    count(*) AS qtd_producoes,
    sum(consumido_kg) AS consumido_kg,
    sum(produzido_kg) AS produzido_kg,
    (sum(consumido_kg) - sum(produzido_kg)) AS perda_kg,
    round(((sum(produzido_kg) / NULLIF(sum(consumido_kg), (0)::numeric)) * (100)::numeric), 2) AS rendimento_pct,
        CASE
            WHEN (round(((sum(produzido_kg) / NULLIF(sum(consumido_kg), (0)::numeric)) * (100)::numeric), 1) >= (99)::numeric) THEN 'Verde'::text
            WHEN (round(((sum(produzido_kg) / NULLIF(sum(consumido_kg), (0)::numeric)) * (100)::numeric), 1) >= (98)::numeric) THEN 'Amarelo'::text
            ELSE 'Vermelho'::text
        END AS faixa,
    area,
    area_nome
   FROM bi.producoes
  WHERE ((etapa = 'finalizada'::text) AND (consumido_kg > (0)::numeric))
  GROUP BY data_producao, equipamento, turno, area, area_nome;


--
-- Name: _bkp_importados_kg_movimentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public._bkp_importados_kg_movimentos (
    id text,
    quantidade numeric
);


--
-- Name: _bkp_importados_kg_volumes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public._bkp_importados_kg_volumes (
    lote text,
    quantidade numeric
);


--
-- Name: _bkp_unidade_kg_movimentos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public._bkp_unidade_kg_movimentos (
    id text,
    quantidade numeric
);


--
-- Name: _bkp_unidade_kg_volumes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public._bkp_unidade_kg_volumes (
    lote text,
    quantidade numeric
);


--
-- Name: admin_acoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_acoes (
    id bigint NOT NULL,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    admin_id uuid,
    admin_nome text,
    acao text NOT NULL,
    alvo_id uuid,
    alvo_email text,
    detalhe jsonb
);


--
-- Name: admin_acoes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.admin_acoes ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.admin_acoes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    em timestamp with time zone DEFAULT now() NOT NULL,
    usuario_id uuid DEFAULT auth.uid(),
    usuario_nome text,
    tabela text NOT NULL,
    operacao text NOT NULL,
    chave text,
    antes jsonb,
    depois jsonb
);


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    nome text NOT NULL,
    role text DEFAULT 'operador'::text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    ativo boolean DEFAULT false NOT NULL,
    area text,
    admin boolean DEFAULT false NOT NULL,
    CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['operador'::text, 'supervisor'::text])))
);


--
-- Name: push_avisos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_avisos (
    sessao_id text NOT NULL,
    marco_horas integer NOT NULL,
    enviado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: push_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_tokens (
    token text NOT NULL,
    user_id uuid NOT NULL,
    plataforma text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: stokkbook_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stokkbook_posts (
    id bigint NOT NULL,
    tipo text NOT NULL,
    ref_id text NOT NULL,
    area text NOT NULL,
    autor_id uuid,
    autor_nome text,
    setor text,
    problema text,
    acao text,
    foto_antes text,
    foto_depois text,
    fotos_antes integer DEFAULT 1 NOT NULL,
    fotos_depois integer DEFAULT 1 NOT NULL,
    horas numeric,
    quando timestamp with time zone DEFAULT now() NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    oculto boolean DEFAULT false NOT NULL,
    oculto_motivo text,
    oculto_por uuid,
    oculto_em timestamp with time zone,
    CONSTRAINT stokkbook_posts_tipo_check CHECK ((tipo = 'cinco_s'::text))
);


--
-- Name: stokkbook_posts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.stokkbook_posts ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.stokkbook_posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: stokkbook_reacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stokkbook_reacoes (
    post_id bigint NOT NULL,
    user_id uuid DEFAULT auth.uid() NOT NULL,
    user_nome text,
    emoji text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT stokkbook_reacoes_emoji_check CHECK ((emoji = ANY (ARRAY['palmas'::text, 'confete'::text, 'foguete'::text, 'joia'::text])))
);


--
-- Name: tanque_medicoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tanque_medicoes (
    id text NOT NULL,
    tanque_id text NOT NULL,
    data_hora timestamp with time zone DEFAULT now() NOT NULL,
    litros_medidos numeric NOT NULL,
    saldo_app numeric NOT NULL,
    diferenca numeric NOT NULL,
    ajustar boolean DEFAULT false NOT NULL,
    obs text,
    usuario_id uuid,
    usuario_nome text,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    anulado boolean DEFAULT false NOT NULL,
    anulado_motivo text,
    anulado_por uuid,
    anulado_em timestamp with time zone,
    area text DEFAULT 'gestao'::text NOT NULL,
    CONSTRAINT tanque_medicoes_data_hora_check CHECK ((data_hora <= (now() + '01:00:00'::interval))),
    CONSTRAINT tanque_medicoes_litros_medidos_check CHECK ((litros_medidos >= (0)::numeric))
);


--
-- Name: usuario_areas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario_areas (
    user_id uuid NOT NULL,
    area text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: abastecimentos abastecimentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.abastecimentos
    ADD CONSTRAINT abastecimentos_pkey PRIMARY KEY (id);


--
-- Name: admin_acoes admin_acoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_acoes
    ADD CONSTRAINT admin_acoes_pkey PRIMARY KEY (id);


--
-- Name: areas areas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.areas
    ADD CONSTRAINT areas_pkey PRIMARY KEY (id);


--
-- Name: armazens_area armazens_area_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.armazens_area
    ADD CONSTRAINT armazens_area_pkey PRIMARY KEY (area, armazem);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: cinco_s cinco_s_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cinco_s
    ADD CONSTRAINT cinco_s_pkey PRIMARY KEY (id);


--
-- Name: equipamento_locais equipamento_locais_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipamento_locais
    ADD CONSTRAINT equipamento_locais_pkey PRIMARY KEY (id);


--
-- Name: equipamentos equipamentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipamentos
    ADD CONSTRAINT equipamentos_pkey PRIMARY KEY (id);


--
-- Name: movimentos movimentos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimentos
    ADD CONSTRAINT movimentos_pkey PRIMARY KEY (id);


--
-- Name: ocorrencias ocorrencias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocorrencias
    ADD CONSTRAINT ocorrencias_pkey PRIMARY KEY (id);


--
-- Name: producoes producoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producoes
    ADD CONSTRAINT producoes_pkey PRIMARY KEY (id);


--
-- Name: produtos produtos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.produtos
    ADD CONSTRAINT produtos_pkey PRIMARY KEY (codigo);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: push_avisos push_avisos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_avisos
    ADD CONSTRAINT push_avisos_pkey PRIMARY KEY (sessao_id, marco_horas);


--
-- Name: push_tokens push_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tokens
    ADD CONSTRAINT push_tokens_pkey PRIMARY KEY (token);


--
-- Name: sessoes sessoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessoes
    ADD CONSTRAINT sessoes_pkey PRIMARY KEY (id);


--
-- Name: stokkbook_posts stokkbook_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stokkbook_posts
    ADD CONSTRAINT stokkbook_posts_pkey PRIMARY KEY (id);


--
-- Name: stokkbook_posts stokkbook_posts_tipo_ref_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stokkbook_posts
    ADD CONSTRAINT stokkbook_posts_tipo_ref_id_key UNIQUE (tipo, ref_id);


--
-- Name: stokkbook_reacoes stokkbook_reacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stokkbook_reacoes
    ADD CONSTRAINT stokkbook_reacoes_pkey PRIMARY KEY (post_id, user_id);


--
-- Name: tanque_entradas tanque_entradas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanque_entradas
    ADD CONSTRAINT tanque_entradas_pkey PRIMARY KEY (id);


--
-- Name: tanque_medicoes tanque_medicoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanque_medicoes
    ADD CONSTRAINT tanque_medicoes_pkey PRIMARY KEY (id);


--
-- Name: tanques tanques_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanques
    ADD CONSTRAINT tanques_pkey PRIMARY KEY (id);


--
-- Name: usuario_areas usuario_areas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_areas
    ADD CONSTRAINT usuario_areas_pkey PRIMARY KEY (user_id, area);


--
-- Name: volumes volumes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.volumes
    ADD CONSTRAINT volumes_pkey PRIMARY KEY (lote);


--
-- Name: abastecimentos_area_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX abastecimentos_area_idx ON public.abastecimentos USING btree (area);


--
-- Name: abastecimentos_equip_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX abastecimentos_equip_idx ON public.abastecimentos USING btree (equipamento_id, data_hora);


--
-- Name: abastecimentos_tanque_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX abastecimentos_tanque_idx ON public.abastecimentos USING btree (tanque_id, data_hora);


--
-- Name: cinco_s_area_aberta_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cinco_s_area_aberta_idx ON public.cinco_s USING btree (area) WHERE ((concluido_em IS NULL) AND (NOT anulado));


--
-- Name: cinco_s_area_aberto_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cinco_s_area_aberto_idx ON public.cinco_s USING btree (area, aberto_em);


--
-- Name: equipamento_locais_area_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX equipamento_locais_area_idx ON public.equipamento_locais USING btree (area);


--
-- Name: equipamento_locais_equip_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX equipamento_locais_equip_idx ON public.equipamento_locais USING btree (equipamento_id, data_hora);


--
-- Name: equipamentos_area_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX equipamentos_area_idx ON public.equipamentos USING btree (area);


--
-- Name: equipamentos_codigo_uk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX equipamentos_codigo_uk ON public.equipamentos USING btree (area, upper(codigo));


--
-- Name: movimentos_area_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movimentos_area_idx ON public.movimentos USING btree (area);


--
-- Name: ocorrencias_area_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ocorrencias_area_idx ON public.ocorrencias USING btree (area);


--
-- Name: ocorrencias_equip_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ocorrencias_equip_idx ON public.ocorrencias USING btree (equipamento_id, aberta_em);


--
-- Name: ocorrencias_uma_aberta_uk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ocorrencias_uma_aberta_uk ON public.ocorrencias USING btree (equipamento_id) WHERE ((liberada_em IS NULL) AND (NOT anulado));


--
-- Name: producoes_area_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX producoes_area_idx ON public.producoes USING btree (area);


--
-- Name: push_tokens_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX push_tokens_user_idx ON public.push_tokens USING btree (user_id);


--
-- Name: sessoes_area_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sessoes_area_idx ON public.sessoes USING btree (area);


--
-- Name: stokkbook_posts_area_quando_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stokkbook_posts_area_quando_idx ON public.stokkbook_posts USING btree (area, quando DESC);


--
-- Name: tanque_entradas_area_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tanque_entradas_area_idx ON public.tanque_entradas USING btree (area);


--
-- Name: tanque_entradas_tanque_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tanque_entradas_tanque_idx ON public.tanque_entradas USING btree (tanque_id, data_hora);


--
-- Name: tanque_medicoes_area_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tanque_medicoes_area_idx ON public.tanque_medicoes USING btree (area);


--
-- Name: tanque_medicoes_tanque_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tanque_medicoes_tanque_idx ON public.tanque_medicoes USING btree (tanque_id, data_hora);


--
-- Name: tanques_area_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tanques_area_idx ON public.tanques USING btree (area);


--
-- Name: volumes_area_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX volumes_area_idx ON public.volumes USING btree (area);


--
-- Name: producoes trg_audit_producoes_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_producoes_del AFTER DELETE ON public.producoes FOR EACH ROW EXECUTE FUNCTION public.registrar_auditoria('id');


--
-- Name: produtos trg_audit_produtos_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_produtos_del AFTER DELETE ON public.produtos FOR EACH ROW EXECUTE FUNCTION public.registrar_auditoria('codigo');


--
-- Name: produtos trg_audit_produtos_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_produtos_upd AFTER UPDATE ON public.produtos FOR EACH ROW WHEN (((old.descricao IS DISTINCT FROM new.descricao) OR (old.grupo IS DISTINCT FROM new.grupo) OR (old.tipo IS DISTINCT FROM new.tipo) OR (old.um IS DISTINCT FROM new.um))) EXECUTE FUNCTION public.registrar_auditoria('codigo');


--
-- Name: profiles trg_audit_profiles_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_profiles_del AFTER DELETE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.registrar_auditoria('id');


--
-- Name: profiles trg_audit_profiles_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_profiles_upd AFTER UPDATE ON public.profiles FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*)) EXECUTE FUNCTION public.registrar_auditoria('id');


--
-- Name: sessoes trg_audit_sessoes_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_sessoes_del AFTER DELETE ON public.sessoes FOR EACH ROW EXECUTE FUNCTION public.registrar_auditoria('id');


--
-- Name: volumes trg_audit_volumes_del; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_volumes_del AFTER DELETE ON public.volumes FOR EACH ROW EXECUTE FUNCTION public.registrar_auditoria('lote');


--
-- Name: volumes trg_audit_volumes_upd; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_volumes_upd AFTER UPDATE ON public.volumes FOR EACH ROW WHEN (((old.status IS DISTINCT FROM new.status) OR (old.armazem IS DISTINCT FROM new.armazem) OR (old.quantidade IS DISTINCT FROM new.quantidade) OR (old.produto_codigo IS DISTINCT FROM new.produto_codigo))) EXECUTE FUNCTION public.registrar_auditoria('lote');


--
-- Name: cinco_s trg_cinco_s_proteger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cinco_s_proteger BEFORE UPDATE ON public.cinco_s FOR EACH ROW EXECUTE FUNCTION public.cinco_s_proteger();


--
-- Name: abastecimentos trg_diesel_anulacao; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_diesel_anulacao BEFORE UPDATE ON public.abastecimentos FOR EACH ROW EXECUTE FUNCTION public.diesel_proteger_anulacao();


--
-- Name: equipamento_locais trg_diesel_anulacao; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_diesel_anulacao BEFORE UPDATE ON public.equipamento_locais FOR EACH ROW EXECUTE FUNCTION public.diesel_proteger_anulacao();


--
-- Name: tanque_entradas trg_diesel_anulacao; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_diesel_anulacao BEFORE UPDATE ON public.tanque_entradas FOR EACH ROW EXECUTE FUNCTION public.diesel_proteger_anulacao();


--
-- Name: tanque_medicoes trg_diesel_anulacao; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_diesel_anulacao BEFORE UPDATE ON public.tanque_medicoes FOR EACH ROW EXECUTE FUNCTION public.diesel_proteger_anulacao();


--
-- Name: abastecimentos trg_diesel_validar; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_diesel_validar BEFORE INSERT ON public.abastecimentos FOR EACH ROW EXECUTE FUNCTION public.diesel_validar_abastecimento();


--
-- Name: profiles trg_impedir_autopromocao_role; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_impedir_autopromocao_role BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.impedir_autopromocao_role();


--
-- Name: ocorrencias trg_ocorrencia_proteger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ocorrencia_proteger BEFORE UPDATE ON public.ocorrencias FOR EACH ROW EXECUTE FUNCTION public.ocorrencia_proteger();


--
-- Name: abastecimentos trg_proteger_area; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_area BEFORE UPDATE ON public.abastecimentos FOR EACH ROW EXECUTE FUNCTION public.proteger_area_registro();


--
-- Name: cinco_s trg_proteger_area; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_area BEFORE UPDATE ON public.cinco_s FOR EACH ROW EXECUTE FUNCTION public.proteger_area_registro();


--
-- Name: equipamento_locais trg_proteger_area; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_area BEFORE UPDATE ON public.equipamento_locais FOR EACH ROW EXECUTE FUNCTION public.proteger_area_registro();


--
-- Name: equipamentos trg_proteger_area; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_area BEFORE UPDATE ON public.equipamentos FOR EACH ROW EXECUTE FUNCTION public.proteger_area_registro();


--
-- Name: movimentos trg_proteger_area; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_area BEFORE UPDATE ON public.movimentos FOR EACH ROW EXECUTE FUNCTION public.proteger_area_registro();


--
-- Name: ocorrencias trg_proteger_area; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_area BEFORE UPDATE ON public.ocorrencias FOR EACH ROW EXECUTE FUNCTION public.proteger_area_registro();


--
-- Name: producoes trg_proteger_area; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_area BEFORE UPDATE ON public.producoes FOR EACH ROW EXECUTE FUNCTION public.proteger_area_registro();


--
-- Name: sessoes trg_proteger_area; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_area BEFORE UPDATE ON public.sessoes FOR EACH ROW EXECUTE FUNCTION public.proteger_area_registro();


--
-- Name: tanque_entradas trg_proteger_area; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_area BEFORE UPDATE ON public.tanque_entradas FOR EACH ROW EXECUTE FUNCTION public.proteger_area_registro();


--
-- Name: tanque_medicoes trg_proteger_area; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_area BEFORE UPDATE ON public.tanque_medicoes FOR EACH ROW EXECUTE FUNCTION public.proteger_area_registro();


--
-- Name: tanques trg_proteger_area; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_area BEFORE UPDATE ON public.tanques FOR EACH ROW EXECUTE FUNCTION public.proteger_area_registro();


--
-- Name: volumes trg_proteger_area; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_area BEFORE UPDATE ON public.volumes FOR EACH ROW EXECUTE FUNCTION public.proteger_area_registro();


--
-- Name: profiles trg_proteger_profiles; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_proteger_profiles BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.proteger_profiles();


--
-- Name: cinco_s trg_stokkbook_de_cinco_s; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stokkbook_de_cinco_s AFTER UPDATE ON public.cinco_s FOR EACH ROW EXECUTE FUNCTION public.stokkbook_de_cinco_s();


--
-- Name: stokkbook_posts trg_stokkbook_posts_proteger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stokkbook_posts_proteger BEFORE UPDATE ON public.stokkbook_posts FOR EACH ROW EXECUTE FUNCTION public.stokkbook_posts_proteger();


--
-- Name: stokkbook_reacoes trg_stokkbook_reacoes_proteger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stokkbook_reacoes_proteger BEFORE INSERT OR UPDATE ON public.stokkbook_reacoes FOR EACH ROW EXECUTE FUNCTION public.stokkbook_reacoes_proteger();


--
-- Name: abastecimentos abastecimentos_anulado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.abastecimentos
    ADD CONSTRAINT abastecimentos_anulado_por_fkey FOREIGN KEY (anulado_por) REFERENCES auth.users(id);


--
-- Name: abastecimentos abastecimentos_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.abastecimentos
    ADD CONSTRAINT abastecimentos_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: abastecimentos abastecimentos_equipamento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.abastecimentos
    ADD CONSTRAINT abastecimentos_equipamento_id_fkey FOREIGN KEY (equipamento_id) REFERENCES public.equipamentos(id);


--
-- Name: abastecimentos abastecimentos_tanque_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.abastecimentos
    ADD CONSTRAINT abastecimentos_tanque_id_fkey FOREIGN KEY (tanque_id) REFERENCES public.tanques(id);


--
-- Name: abastecimentos abastecimentos_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.abastecimentos
    ADD CONSTRAINT abastecimentos_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id);


--
-- Name: armazens_area armazens_area_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.armazens_area
    ADD CONSTRAINT armazens_area_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: cinco_s cinco_s_aberto_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cinco_s
    ADD CONSTRAINT cinco_s_aberto_por_fkey FOREIGN KEY (aberto_por) REFERENCES auth.users(id);


--
-- Name: cinco_s cinco_s_anulado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cinco_s
    ADD CONSTRAINT cinco_s_anulado_por_fkey FOREIGN KEY (anulado_por) REFERENCES auth.users(id);


--
-- Name: cinco_s cinco_s_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cinco_s
    ADD CONSTRAINT cinco_s_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: cinco_s cinco_s_concluido_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cinco_s
    ADD CONSTRAINT cinco_s_concluido_por_fkey FOREIGN KEY (concluido_por) REFERENCES auth.users(id);


--
-- Name: cinco_s cinco_s_editado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cinco_s
    ADD CONSTRAINT cinco_s_editado_por_fkey FOREIGN KEY (editado_por) REFERENCES auth.users(id);


--
-- Name: equipamento_locais equipamento_locais_anulado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipamento_locais
    ADD CONSTRAINT equipamento_locais_anulado_por_fkey FOREIGN KEY (anulado_por) REFERENCES auth.users(id);


--
-- Name: equipamento_locais equipamento_locais_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipamento_locais
    ADD CONSTRAINT equipamento_locais_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: equipamento_locais equipamento_locais_equipamento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipamento_locais
    ADD CONSTRAINT equipamento_locais_equipamento_id_fkey FOREIGN KEY (equipamento_id) REFERENCES public.equipamentos(id);


--
-- Name: equipamento_locais equipamento_locais_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipamento_locais
    ADD CONSTRAINT equipamento_locais_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id);


--
-- Name: equipamentos equipamentos_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipamentos
    ADD CONSTRAINT equipamentos_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: equipamentos equipamentos_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.equipamentos
    ADD CONSTRAINT equipamentos_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id);


--
-- Name: movimentos movimentos_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimentos
    ADD CONSTRAINT movimentos_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: movimentos movimentos_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movimentos
    ADD CONSTRAINT movimentos_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id);


--
-- Name: ocorrencias ocorrencias_aberta_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocorrencias
    ADD CONSTRAINT ocorrencias_aberta_por_fkey FOREIGN KEY (aberta_por) REFERENCES auth.users(id);


--
-- Name: ocorrencias ocorrencias_anulado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocorrencias
    ADD CONSTRAINT ocorrencias_anulado_por_fkey FOREIGN KEY (anulado_por) REFERENCES auth.users(id);


--
-- Name: ocorrencias ocorrencias_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocorrencias
    ADD CONSTRAINT ocorrencias_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: ocorrencias ocorrencias_editada_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocorrencias
    ADD CONSTRAINT ocorrencias_editada_por_fkey FOREIGN KEY (editada_por) REFERENCES auth.users(id);


--
-- Name: ocorrencias ocorrencias_equipamento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocorrencias
    ADD CONSTRAINT ocorrencias_equipamento_id_fkey FOREIGN KEY (equipamento_id) REFERENCES public.equipamentos(id);


--
-- Name: ocorrencias ocorrencias_liberada_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocorrencias
    ADD CONSTRAINT ocorrencias_liberada_por_fkey FOREIGN KEY (liberada_por) REFERENCES auth.users(id);


--
-- Name: producoes producoes_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producoes
    ADD CONSTRAINT producoes_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: producoes producoes_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producoes
    ADD CONSTRAINT producoes_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id);


--
-- Name: profiles profiles_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: push_tokens push_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tokens
    ADD CONSTRAINT push_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: sessoes sessoes_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessoes
    ADD CONSTRAINT sessoes_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: sessoes sessoes_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessoes
    ADD CONSTRAINT sessoes_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id);


--
-- Name: stokkbook_posts stokkbook_posts_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stokkbook_posts
    ADD CONSTRAINT stokkbook_posts_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: stokkbook_reacoes stokkbook_reacoes_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stokkbook_reacoes
    ADD CONSTRAINT stokkbook_reacoes_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.stokkbook_posts(id) ON DELETE CASCADE;


--
-- Name: tanque_entradas tanque_entradas_anulado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanque_entradas
    ADD CONSTRAINT tanque_entradas_anulado_por_fkey FOREIGN KEY (anulado_por) REFERENCES auth.users(id);


--
-- Name: tanque_entradas tanque_entradas_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanque_entradas
    ADD CONSTRAINT tanque_entradas_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: tanque_entradas tanque_entradas_tanque_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanque_entradas
    ADD CONSTRAINT tanque_entradas_tanque_id_fkey FOREIGN KEY (tanque_id) REFERENCES public.tanques(id);


--
-- Name: tanque_entradas tanque_entradas_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanque_entradas
    ADD CONSTRAINT tanque_entradas_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id);


--
-- Name: tanque_medicoes tanque_medicoes_anulado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanque_medicoes
    ADD CONSTRAINT tanque_medicoes_anulado_por_fkey FOREIGN KEY (anulado_por) REFERENCES auth.users(id);


--
-- Name: tanque_medicoes tanque_medicoes_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanque_medicoes
    ADD CONSTRAINT tanque_medicoes_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: tanque_medicoes tanque_medicoes_tanque_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanque_medicoes
    ADD CONSTRAINT tanque_medicoes_tanque_id_fkey FOREIGN KEY (tanque_id) REFERENCES public.tanques(id);


--
-- Name: tanque_medicoes tanque_medicoes_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanque_medicoes
    ADD CONSTRAINT tanque_medicoes_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id);


--
-- Name: tanques tanques_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanques
    ADD CONSTRAINT tanques_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: tanques tanques_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tanques
    ADD CONSTRAINT tanques_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id);


--
-- Name: usuario_areas usuario_areas_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_areas
    ADD CONSTRAINT usuario_areas_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: usuario_areas usuario_areas_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario_areas
    ADD CONSTRAINT usuario_areas_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: volumes volumes_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.volumes
    ADD CONSTRAINT volumes_area_fkey FOREIGN KEY (area) REFERENCES public.areas(id);


--
-- Name: volumes volumes_produto_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.volumes
    ADD CONSTRAINT volumes_produto_codigo_fkey FOREIGN KEY (produto_codigo) REFERENCES public.produtos(codigo);


--
-- Name: _bkp_importados_kg_movimentos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public._bkp_importados_kg_movimentos ENABLE ROW LEVEL SECURITY;

--
-- Name: _bkp_importados_kg_volumes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public._bkp_importados_kg_volumes ENABLE ROW LEVEL SECURITY;

--
-- Name: _bkp_unidade_kg_movimentos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public._bkp_unidade_kg_movimentos ENABLE ROW LEVEL SECURITY;

--
-- Name: _bkp_unidade_kg_volumes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public._bkp_unidade_kg_volumes ENABLE ROW LEVEL SECURITY;

--
-- Name: abastecimentos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.abastecimentos ENABLE ROW LEVEL SECURITY;

--
-- Name: abastecimentos abastecimentos_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY abastecimentos_insert ON public.abastecimentos FOR INSERT TO authenticated WITH CHECK (((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])) AND ((usuario_id IS NULL) OR (usuario_id = auth.uid()))));


--
-- Name: abastecimentos abastecimentos_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY abastecimentos_select ON public.abastecimentos FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: abastecimentos abastecimentos_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY abastecimentos_update ON public.abastecimentos FOR UPDATE TO authenticated USING ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])))) WITH CHECK ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));


--
-- Name: admin_acoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admin_acoes ENABLE ROW LEVEL SECURITY;

--
-- Name: admin_acoes admin_acoes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_acoes_select ON public.admin_acoes FOR SELECT TO authenticated USING (( SELECT public.eh_admin() AS eh_admin));


--
-- Name: areas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.areas ENABLE ROW LEVEL SECURITY;

--
-- Name: areas areas_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY areas_select ON public.areas FOR SELECT TO authenticated USING (( SELECT public.eh_usuario_ativo() AS eh_usuario_ativo));


--
-- Name: armazens_area; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.armazens_area ENABLE ROW LEVEL SECURITY;

--
-- Name: armazens_area armazens_area_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY armazens_area_select ON public.armazens_area FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log audit_select_supervisor; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_select_supervisor ON public.audit_log FOR SELECT TO authenticated USING (( SELECT public.eh_supervisor() AS eh_supervisor));


--
-- Name: cinco_s; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cinco_s ENABLE ROW LEVEL SECURITY;

--
-- Name: cinco_s cinco_s_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cinco_s_insert ON public.cinco_s FOR INSERT TO authenticated WITH CHECK (((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])) AND ((aberto_por IS NULL) OR (aberto_por = auth.uid())) AND (NOT anulado) AND (concluido_em IS NULL) AND (foto_depois IS NULL) AND (acao IS NULL) AND (cardinality(fotos_depois_extra) = 0)));


--
-- Name: cinco_s cinco_s_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cinco_s_select ON public.cinco_s FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: cinco_s cinco_s_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cinco_s_update ON public.cinco_s FOR UPDATE TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))) WITH CHECK ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: equipamento_locais; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.equipamento_locais ENABLE ROW LEVEL SECURITY;

--
-- Name: equipamento_locais equipamento_locais_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY equipamento_locais_insert ON public.equipamento_locais FOR INSERT TO authenticated WITH CHECK (((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])) AND ((usuario_id IS NULL) OR (usuario_id = auth.uid())) AND (NOT anulado)));


--
-- Name: equipamento_locais equipamento_locais_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY equipamento_locais_select ON public.equipamento_locais FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: equipamento_locais equipamento_locais_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY equipamento_locais_update ON public.equipamento_locais FOR UPDATE TO authenticated USING (((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])) AND (( SELECT public.eh_supervisor() AS eh_supervisor) OR ((usuario_id = auth.uid()) AND ("timestamp" > (now() - '48:00:00'::interval)) AND ("timestamp" <= (now() + '01:00:00'::interval)))))) WITH CHECK (((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])) AND (( SELECT public.eh_supervisor() AS eh_supervisor) OR ((usuario_id = auth.uid()) AND ("timestamp" > (now() - '48:00:00'::interval)) AND ("timestamp" <= (now() + '01:00:00'::interval))))));


--
-- Name: equipamentos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.equipamentos ENABLE ROW LEVEL SECURITY;

--
-- Name: equipamentos equipamentos_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY equipamentos_insert ON public.equipamentos FOR INSERT TO authenticated WITH CHECK ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));


--
-- Name: equipamentos equipamentos_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY equipamentos_select ON public.equipamentos FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: equipamentos equipamentos_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY equipamentos_update ON public.equipamentos FOR UPDATE TO authenticated USING ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])))) WITH CHECK ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));


--
-- Name: movimentos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.movimentos ENABLE ROW LEVEL SECURITY;

--
-- Name: movimentos movimentos_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY movimentos_insert ON public.movimentos FOR INSERT TO authenticated WITH CHECK (((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])) AND ((usuario_id IS NULL) OR (usuario_id = auth.uid()))));


--
-- Name: movimentos movimentos_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY movimentos_select ON public.movimentos FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: ocorrencias; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.ocorrencias ENABLE ROW LEVEL SECURITY;

--
-- Name: ocorrencias ocorrencias_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ocorrencias_insert ON public.ocorrencias FOR INSERT TO authenticated WITH CHECK (((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])) AND ((aberta_por IS NULL) OR (aberta_por = auth.uid())) AND (liberada_em IS NULL) AND (NOT anulado)));


--
-- Name: ocorrencias ocorrencias_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ocorrencias_select ON public.ocorrencias FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: ocorrencias ocorrencias_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY ocorrencias_update ON public.ocorrencias FOR UPDATE TO authenticated USING ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])))) WITH CHECK ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));


--
-- Name: producoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.producoes ENABLE ROW LEVEL SECURITY;

--
-- Name: producoes producoes_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY producoes_delete ON public.producoes FOR DELETE TO authenticated USING ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));


--
-- Name: producoes producoes_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY producoes_insert ON public.producoes FOR INSERT TO authenticated WITH CHECK ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: producoes producoes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY producoes_select ON public.producoes FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: producoes producoes_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY producoes_update ON public.producoes FOR UPDATE TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))) WITH CHECK ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: produtos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.produtos ENABLE ROW LEVEL SECURITY;

--
-- Name: produtos produtos_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY produtos_insert ON public.produtos FOR INSERT TO authenticated WITH CHECK (( SELECT public.eh_supervisor() AS eh_supervisor));


--
-- Name: produtos produtos_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY produtos_select ON public.produtos FOR SELECT TO authenticated USING (( SELECT public.eh_usuario_ativo() AS eh_usuario_ativo));


--
-- Name: produtos produtos_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY produtos_update ON public.produtos FOR UPDATE TO authenticated USING (( SELECT public.eh_supervisor() AS eh_supervisor)) WITH CHECK (( SELECT public.eh_supervisor() AS eh_supervisor));


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_select ON public.profiles FOR SELECT TO authenticated USING (((id = auth.uid()) OR ( SELECT public.eh_usuario_ativo() AS eh_usuario_ativo)));


--
-- Name: profiles profiles_update_proprio; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_update_proprio ON public.profiles FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK ((id = auth.uid()));


--
-- Name: push_avisos; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.push_avisos ENABLE ROW LEVEL SECURITY;

--
-- Name: push_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: sessoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sessoes ENABLE ROW LEVEL SECURITY;

--
-- Name: sessoes sessoes_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sessoes_delete ON public.sessoes FOR DELETE TO authenticated USING ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));


--
-- Name: sessoes sessoes_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sessoes_insert ON public.sessoes FOR INSERT TO authenticated WITH CHECK ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: sessoes sessoes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sessoes_select ON public.sessoes FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: sessoes sessoes_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY sessoes_update ON public.sessoes FOR UPDATE TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))) WITH CHECK ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: stokkbook_posts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stokkbook_posts ENABLE ROW LEVEL SECURITY;

--
-- Name: stokkbook_posts stokkbook_posts_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stokkbook_posts_select ON public.stokkbook_posts FOR SELECT TO authenticated USING (((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])) AND ((NOT oculto) OR ( SELECT public.eh_supervisor() AS eh_supervisor))));


--
-- Name: stokkbook_posts stokkbook_posts_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stokkbook_posts_update ON public.stokkbook_posts FOR UPDATE TO authenticated USING ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])))) WITH CHECK ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));


--
-- Name: stokkbook_reacoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stokkbook_reacoes ENABLE ROW LEVEL SECURITY;

--
-- Name: stokkbook_reacoes stokkbook_reacoes_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stokkbook_reacoes_delete ON public.stokkbook_reacoes FOR DELETE TO authenticated USING ((user_id = auth.uid()));


--
-- Name: stokkbook_reacoes stokkbook_reacoes_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stokkbook_reacoes_insert ON public.stokkbook_reacoes FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM public.stokkbook_posts p
  WHERE (p.id = stokkbook_reacoes.post_id)))));


--
-- Name: stokkbook_reacoes stokkbook_reacoes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stokkbook_reacoes_select ON public.stokkbook_reacoes FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.stokkbook_posts p
  WHERE (p.id = stokkbook_reacoes.post_id))));


--
-- Name: stokkbook_reacoes stokkbook_reacoes_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stokkbook_reacoes_update ON public.stokkbook_reacoes FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK (((user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM public.stokkbook_posts p
  WHERE (p.id = stokkbook_reacoes.post_id)))));


--
-- Name: tanque_entradas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tanque_entradas ENABLE ROW LEVEL SECURITY;

--
-- Name: tanque_entradas tanque_entradas_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tanque_entradas_insert ON public.tanque_entradas FOR INSERT TO authenticated WITH CHECK ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])) AND ((usuario_id IS NULL) OR (usuario_id = auth.uid()))));


--
-- Name: tanque_entradas tanque_entradas_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tanque_entradas_select ON public.tanque_entradas FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: tanque_entradas tanque_entradas_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tanque_entradas_update ON public.tanque_entradas FOR UPDATE TO authenticated USING ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])))) WITH CHECK ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));


--
-- Name: tanque_medicoes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tanque_medicoes ENABLE ROW LEVEL SECURITY;

--
-- Name: tanque_medicoes tanque_medicoes_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tanque_medicoes_insert ON public.tanque_medicoes FOR INSERT TO authenticated WITH CHECK ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])) AND ((usuario_id IS NULL) OR (usuario_id = auth.uid()))));


--
-- Name: tanque_medicoes tanque_medicoes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tanque_medicoes_select ON public.tanque_medicoes FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: tanque_medicoes tanque_medicoes_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tanque_medicoes_update ON public.tanque_medicoes FOR UPDATE TO authenticated USING ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])))) WITH CHECK ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));


--
-- Name: tanques; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tanques ENABLE ROW LEVEL SECURITY;

--
-- Name: tanques tanques_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tanques_insert ON public.tanques FOR INSERT TO authenticated WITH CHECK ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));


--
-- Name: tanques tanques_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tanques_select ON public.tanques FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: tanques tanques_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tanques_update ON public.tanques FOR UPDATE TO authenticated USING ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])))) WITH CHECK ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));


--
-- Name: usuario_areas; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.usuario_areas ENABLE ROW LEVEL SECURITY;

--
-- Name: usuario_areas usuario_areas_select_proprio; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY usuario_areas_select_proprio ON public.usuario_areas FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: volumes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.volumes ENABLE ROW LEVEL SECURITY;

--
-- Name: volumes volumes_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY volumes_delete ON public.volumes FOR DELETE TO authenticated USING ((( SELECT public.eh_supervisor() AS eh_supervisor) AND (area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))));


--
-- Name: volumes volumes_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY volumes_insert ON public.volumes FOR INSERT TO authenticated WITH CHECK ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: volumes volumes_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY volumes_select ON public.volumes FOR SELECT TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: volumes volumes_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY volumes_update ON public.volumes FOR UPDATE TO authenticated USING ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[]))) WITH CHECK ((area = ANY (( SELECT public.areas_do_usuario() AS areas_do_usuario)::text[])));


--
-- Name: SCHEMA bi; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA bi TO powerbi_leitor;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION area_do_usuario(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.area_do_usuario() FROM PUBLIC;
GRANT ALL ON FUNCTION public.area_do_usuario() TO authenticated;
GRANT ALL ON FUNCTION public.area_do_usuario() TO service_role;


--
-- Name: FUNCTION area_padrao(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.area_padrao() FROM PUBLIC;
GRANT ALL ON FUNCTION public.area_padrao() TO authenticated;
GRANT ALL ON FUNCTION public.area_padrao() TO service_role;


--
-- Name: FUNCTION areas_do_usuario(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.areas_do_usuario() FROM PUBLIC;
GRANT ALL ON FUNCTION public.areas_do_usuario() TO authenticated;
GRANT ALL ON FUNCTION public.areas_do_usuario() TO service_role;


--
-- Name: FUNCTION cinco_s_caminhos_ok(a text, f text[]); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.cinco_s_caminhos_ok(a text, f text[]) TO anon;
GRANT ALL ON FUNCTION public.cinco_s_caminhos_ok(a text, f text[]) TO authenticated;
GRANT ALL ON FUNCTION public.cinco_s_caminhos_ok(a text, f text[]) TO service_role;


--
-- Name: FUNCTION cinco_s_proteger(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.cinco_s_proteger() TO anon;
GRANT ALL ON FUNCTION public.cinco_s_proteger() TO authenticated;
GRANT ALL ON FUNCTION public.cinco_s_proteger() TO service_role;


--
-- Name: FUNCTION diesel_proteger_anulacao(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.diesel_proteger_anulacao() TO anon;
GRANT ALL ON FUNCTION public.diesel_proteger_anulacao() TO authenticated;
GRANT ALL ON FUNCTION public.diesel_proteger_anulacao() TO service_role;


--
-- Name: FUNCTION diesel_validar_abastecimento(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.diesel_validar_abastecimento() TO anon;
GRANT ALL ON FUNCTION public.diesel_validar_abastecimento() TO authenticated;
GRANT ALL ON FUNCTION public.diesel_validar_abastecimento() TO service_role;


--
-- Name: FUNCTION eh_admin(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.eh_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.eh_admin() TO authenticated;
GRANT ALL ON FUNCTION public.eh_admin() TO service_role;


--
-- Name: FUNCTION eh_supervisor(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.eh_supervisor() FROM PUBLIC;
GRANT ALL ON FUNCTION public.eh_supervisor() TO authenticated;
GRANT ALL ON FUNCTION public.eh_supervisor() TO service_role;


--
-- Name: FUNCTION eh_usuario_ativo(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.eh_usuario_ativo() FROM PUBLIC;
GRANT ALL ON FUNCTION public.eh_usuario_ativo() TO authenticated;
GRANT ALL ON FUNCTION public.eh_usuario_ativo() TO service_role;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.handle_new_user() TO anon;
GRANT ALL ON FUNCTION public.handle_new_user() TO authenticated;
GRANT ALL ON FUNCTION public.handle_new_user() TO service_role;


--
-- Name: FUNCTION impedir_autopromocao_role(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.impedir_autopromocao_role() TO anon;
GRANT ALL ON FUNCTION public.impedir_autopromocao_role() TO authenticated;
GRANT ALL ON FUNCTION public.impedir_autopromocao_role() TO service_role;


--
-- Name: FUNCTION ocorrencia_proteger(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.ocorrencia_proteger() TO anon;
GRANT ALL ON FUNCTION public.ocorrencia_proteger() TO authenticated;
GRANT ALL ON FUNCTION public.ocorrencia_proteger() TO service_role;


--
-- Name: FUNCTION proteger_area_registro(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.proteger_area_registro() TO anon;
GRANT ALL ON FUNCTION public.proteger_area_registro() TO authenticated;
GRANT ALL ON FUNCTION public.proteger_area_registro() TO service_role;


--
-- Name: FUNCTION proteger_profiles(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.proteger_profiles() TO anon;
GRANT ALL ON FUNCTION public.proteger_profiles() TO authenticated;
GRANT ALL ON FUNCTION public.proteger_profiles() TO service_role;


--
-- Name: FUNCTION registrar_auditoria(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.registrar_auditoria() FROM PUBLIC;
GRANT ALL ON FUNCTION public.registrar_auditoria() TO service_role;


--
-- Name: FUNCTION registrar_push_token(p_token text, p_plataforma text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.registrar_push_token(p_token text, p_plataforma text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.registrar_push_token(p_token text, p_plataforma text) TO authenticated;
GRANT ALL ON FUNCTION public.registrar_push_token(p_token text, p_plataforma text) TO service_role;


--
-- Name: FUNCTION stokkbook_de_cinco_s(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.stokkbook_de_cinco_s() TO anon;
GRANT ALL ON FUNCTION public.stokkbook_de_cinco_s() TO authenticated;
GRANT ALL ON FUNCTION public.stokkbook_de_cinco_s() TO service_role;


--
-- Name: FUNCTION stokkbook_posts_proteger(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.stokkbook_posts_proteger() TO anon;
GRANT ALL ON FUNCTION public.stokkbook_posts_proteger() TO authenticated;
GRANT ALL ON FUNCTION public.stokkbook_posts_proteger() TO service_role;


--
-- Name: FUNCTION stokkbook_reacoes_proteger(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.stokkbook_reacoes_proteger() TO anon;
GRANT ALL ON FUNCTION public.stokkbook_reacoes_proteger() TO authenticated;
GRANT ALL ON FUNCTION public.stokkbook_reacoes_proteger() TO service_role;


--
-- Name: TABLE areas; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.areas TO service_role;
GRANT SELECT ON TABLE public.areas TO authenticated;


--
-- Name: TABLE areas; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.areas TO powerbi_leitor;


--
-- Name: TABLE armazens_area; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.armazens_area TO service_role;
GRANT SELECT ON TABLE public.armazens_area TO authenticated;


--
-- Name: TABLE armazens_area; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.armazens_area TO powerbi_leitor;


--
-- Name: TABLE cinco_s; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cinco_s TO service_role;
GRANT SELECT,INSERT ON TABLE public.cinco_s TO authenticated;


--
-- Name: COLUMN cinco_s.setor; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(setor) ON TABLE public.cinco_s TO authenticated;


--
-- Name: COLUMN cinco_s.problema; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(problema) ON TABLE public.cinco_s TO authenticated;


--
-- Name: COLUMN cinco_s.concluido_em; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(concluido_em) ON TABLE public.cinco_s TO authenticated;


--
-- Name: COLUMN cinco_s.concluido_por_nome; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(concluido_por_nome) ON TABLE public.cinco_s TO authenticated;


--
-- Name: COLUMN cinco_s.foto_depois; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(foto_depois) ON TABLE public.cinco_s TO authenticated;


--
-- Name: COLUMN cinco_s.acao; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(acao) ON TABLE public.cinco_s TO authenticated;


--
-- Name: COLUMN cinco_s.anulado; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(anulado) ON TABLE public.cinco_s TO authenticated;


--
-- Name: COLUMN cinco_s.anulado_motivo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(anulado_motivo) ON TABLE public.cinco_s TO authenticated;


--
-- Name: COLUMN cinco_s.fotos_depois_extra; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(fotos_depois_extra) ON TABLE public.cinco_s TO authenticated;


--
-- Name: COLUMN cinco_s.postar_stokkbook; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(postar_stokkbook) ON TABLE public.cinco_s TO authenticated;


--
-- Name: TABLE cinco_s; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.cinco_s TO powerbi_leitor;


--
-- Name: TABLE sessoes; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,MAINTAIN,UPDATE ON TABLE public.sessoes TO authenticated;
GRANT ALL ON TABLE public.sessoes TO service_role;


--
-- Name: TABLE conferencias; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.conferencias TO powerbi_leitor;


--
-- Name: TABLE abastecimentos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.abastecimentos TO service_role;
GRANT SELECT,INSERT ON TABLE public.abastecimentos TO authenticated;


--
-- Name: COLUMN abastecimentos.anulado; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(anulado) ON TABLE public.abastecimentos TO authenticated;


--
-- Name: COLUMN abastecimentos.anulado_motivo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(anulado_motivo) ON TABLE public.abastecimentos TO authenticated;


--
-- Name: TABLE equipamentos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.equipamentos TO service_role;
GRANT SELECT,INSERT ON TABLE public.equipamentos TO authenticated;


--
-- Name: COLUMN equipamentos.codigo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(codigo) ON TABLE public.equipamentos TO authenticated;


--
-- Name: COLUMN equipamentos.nome; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(nome) ON TABLE public.equipamentos TO authenticated;


--
-- Name: COLUMN equipamentos.tipo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(tipo) ON TABLE public.equipamentos TO authenticated;


--
-- Name: COLUMN equipamentos.medidor; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(medidor) ON TABLE public.equipamentos TO authenticated;


--
-- Name: COLUMN equipamentos.area_uso; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(area_uso) ON TABLE public.equipamentos TO authenticated;


--
-- Name: COLUMN equipamentos.dias_alerta; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(dias_alerta) ON TABLE public.equipamentos TO authenticated;


--
-- Name: COLUMN equipamentos.alerta_dias_uteis; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(alerta_dias_uteis) ON TABLE public.equipamentos TO authenticated;


--
-- Name: COLUMN equipamentos.alerta_ativo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(alerta_ativo) ON TABLE public.equipamentos TO authenticated;


--
-- Name: COLUMN equipamentos.ativo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(ativo) ON TABLE public.equipamentos TO authenticated;


--
-- Name: COLUMN equipamentos.setor; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(setor) ON TABLE public.equipamentos TO authenticated;


--
-- Name: TABLE tanques; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tanques TO service_role;
GRANT SELECT,INSERT ON TABLE public.tanques TO authenticated;


--
-- Name: COLUMN tanques.nome; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(nome) ON TABLE public.tanques TO authenticated;


--
-- Name: COLUMN tanques.capacidade_l; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(capacidade_l) ON TABLE public.tanques TO authenticated;


--
-- Name: COLUMN tanques.minimo_l; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(minimo_l) ON TABLE public.tanques TO authenticated;


--
-- Name: COLUMN tanques.ativo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(ativo) ON TABLE public.tanques TO authenticated;


--
-- Name: TABLE diesel_abastecimentos; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.diesel_abastecimentos TO powerbi_leitor;


--
-- Name: TABLE tanque_entradas; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tanque_entradas TO service_role;
GRANT SELECT,INSERT ON TABLE public.tanque_entradas TO authenticated;


--
-- Name: COLUMN tanque_entradas.anulado; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(anulado) ON TABLE public.tanque_entradas TO authenticated;


--
-- Name: COLUMN tanque_entradas.anulado_motivo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(anulado_motivo) ON TABLE public.tanque_entradas TO authenticated;


--
-- Name: TABLE diesel_entradas; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.diesel_entradas TO powerbi_leitor;


--
-- Name: TABLE diesel_equipamentos; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.diesel_equipamentos TO powerbi_leitor;


--
-- Name: TABLE equipamento_locais; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.equipamento_locais TO service_role;
GRANT SELECT,INSERT ON TABLE public.equipamento_locais TO authenticated;


--
-- Name: COLUMN equipamento_locais.anulado; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(anulado) ON TABLE public.equipamento_locais TO authenticated;


--
-- Name: COLUMN equipamento_locais.anulado_motivo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(anulado_motivo) ON TABLE public.equipamento_locais TO authenticated;


--
-- Name: TABLE equipamento_locais; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.equipamento_locais TO powerbi_leitor;


--
-- Name: TABLE equipamento_local_atual; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.equipamento_local_atual TO powerbi_leitor;


--
-- Name: TABLE produtos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,MAINTAIN,UPDATE ON TABLE public.produtos TO authenticated;
GRANT ALL ON TABLE public.produtos TO service_role;


--
-- Name: TABLE volumes; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,MAINTAIN,UPDATE ON TABLE public.volumes TO authenticated;
GRANT ALL ON TABLE public.volumes TO service_role;


--
-- Name: TABLE estoque; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.estoque TO powerbi_leitor;


--
-- Name: TABLE ocorrencias; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.ocorrencias TO service_role;
GRANT SELECT,INSERT ON TABLE public.ocorrencias TO authenticated;


--
-- Name: COLUMN ocorrencias.categoria; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(categoria) ON TABLE public.ocorrencias TO authenticated;


--
-- Name: COLUMN ocorrencias.motivo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(motivo) ON TABLE public.ocorrencias TO authenticated;


--
-- Name: COLUMN ocorrencias.descricao; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(descricao) ON TABLE public.ocorrencias TO authenticated;


--
-- Name: COLUMN ocorrencias.liberada_em; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(liberada_em) ON TABLE public.ocorrencias TO authenticated;


--
-- Name: COLUMN ocorrencias.liberada_por_nome; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(liberada_por_nome) ON TABLE public.ocorrencias TO authenticated;


--
-- Name: COLUMN ocorrencias.motivo_liberacao; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(motivo_liberacao) ON TABLE public.ocorrencias TO authenticated;


--
-- Name: COLUMN ocorrencias.servico_realizado; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(servico_realizado) ON TABLE public.ocorrencias TO authenticated;


--
-- Name: COLUMN ocorrencias.recebido_por; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(recebido_por) ON TABLE public.ocorrencias TO authenticated;


--
-- Name: COLUMN ocorrencias.anulado; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(anulado) ON TABLE public.ocorrencias TO authenticated;


--
-- Name: COLUMN ocorrencias.anulado_motivo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(anulado_motivo) ON TABLE public.ocorrencias TO authenticated;


--
-- Name: TABLE manutencao_ocorrencias; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.manutencao_ocorrencias TO powerbi_leitor;


--
-- Name: TABLE movimentos; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,MAINTAIN ON TABLE public.movimentos TO authenticated;
GRANT ALL ON TABLE public.movimentos TO service_role;


--
-- Name: TABLE movimentos; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.movimentos TO powerbi_leitor;


--
-- Name: TABLE producoes; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,MAINTAIN,UPDATE ON TABLE public.producoes TO authenticated;
GRANT ALL ON TABLE public.producoes TO service_role;


--
-- Name: TABLE producoes; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.producoes TO powerbi_leitor;


--
-- Name: TABLE producao_itens; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.producao_itens TO powerbi_leitor;


--
-- Name: TABLE rendimento_turno; Type: ACL; Schema: bi; Owner: -
--

GRANT SELECT ON TABLE bi.rendimento_turno TO powerbi_leitor;


--
-- Name: TABLE _bkp_importados_kg_movimentos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public._bkp_importados_kg_movimentos TO authenticated;
GRANT ALL ON TABLE public._bkp_importados_kg_movimentos TO service_role;


--
-- Name: TABLE _bkp_importados_kg_volumes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public._bkp_importados_kg_volumes TO authenticated;
GRANT ALL ON TABLE public._bkp_importados_kg_volumes TO service_role;


--
-- Name: TABLE _bkp_unidade_kg_movimentos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public._bkp_unidade_kg_movimentos TO authenticated;
GRANT ALL ON TABLE public._bkp_unidade_kg_movimentos TO service_role;


--
-- Name: TABLE _bkp_unidade_kg_volumes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public._bkp_unidade_kg_volumes TO authenticated;
GRANT ALL ON TABLE public._bkp_unidade_kg_volumes TO service_role;


--
-- Name: TABLE admin_acoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.admin_acoes TO service_role;
GRANT SELECT ON TABLE public.admin_acoes TO authenticated;


--
-- Name: SEQUENCE admin_acoes_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.admin_acoes_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.admin_acoes_id_seq TO service_role;


--
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.audit_log TO service_role;
GRANT SELECT ON TABLE public.audit_log TO authenticated;


--
-- Name: SEQUENCE audit_log_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.audit_log_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.audit_log_id_seq TO service_role;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.profiles TO service_role;
GRANT SELECT ON TABLE public.profiles TO authenticated;


--
-- Name: COLUMN profiles.nome; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(nome) ON TABLE public.profiles TO authenticated;


--
-- Name: TABLE push_avisos; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.push_avisos TO authenticated;
GRANT ALL ON TABLE public.push_avisos TO service_role;


--
-- Name: TABLE push_tokens; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.push_tokens TO authenticated;
GRANT ALL ON TABLE public.push_tokens TO service_role;


--
-- Name: TABLE stokkbook_posts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.stokkbook_posts TO service_role;
GRANT SELECT ON TABLE public.stokkbook_posts TO authenticated;


--
-- Name: COLUMN stokkbook_posts.oculto; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(oculto) ON TABLE public.stokkbook_posts TO authenticated;


--
-- Name: COLUMN stokkbook_posts.oculto_motivo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(oculto_motivo) ON TABLE public.stokkbook_posts TO authenticated;


--
-- Name: SEQUENCE stokkbook_posts_id_seq; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON SEQUENCE public.stokkbook_posts_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.stokkbook_posts_id_seq TO service_role;


--
-- Name: TABLE stokkbook_reacoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.stokkbook_reacoes TO service_role;
GRANT SELECT,DELETE ON TABLE public.stokkbook_reacoes TO authenticated;


--
-- Name: COLUMN stokkbook_reacoes.post_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(post_id) ON TABLE public.stokkbook_reacoes TO authenticated;


--
-- Name: COLUMN stokkbook_reacoes.emoji; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(emoji),UPDATE(emoji) ON TABLE public.stokkbook_reacoes TO authenticated;


--
-- Name: TABLE tanque_medicoes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tanque_medicoes TO service_role;
GRANT SELECT,INSERT ON TABLE public.tanque_medicoes TO authenticated;


--
-- Name: COLUMN tanque_medicoes.anulado; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(anulado) ON TABLE public.tanque_medicoes TO authenticated;


--
-- Name: COLUMN tanque_medicoes.anulado_motivo; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(anulado_motivo) ON TABLE public.tanque_medicoes TO authenticated;


--
-- Name: TABLE usuario_areas; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.usuario_areas TO service_role;
GRANT SELECT ON TABLE public.usuario_areas TO authenticated;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: bi; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA bi GRANT SELECT ON TABLES TO powerbi_leitor;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict b2f4f5AIB8G8G5zqecRYleehdsSOI02mj6hp1v5Kje4o0Lcw6Mratgq8PJ9Iuzl

