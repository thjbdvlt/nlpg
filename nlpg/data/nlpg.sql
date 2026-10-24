--
-- PostgreSQL database dump
--
-- Dumped from database version 16.8 (Debian 16.8-1.pgdg120+1)
-- Dumped by pg_dump version 16.8 (Debian 16.8-1.pgdg120+1)
set statement_timeout = 0;

set lock_timeout = 0;

set idle_in_transaction_session_timeout = 0;

set client_encoding = 'UTF8';

set standard_conforming_strings = on;

select
    pg_catalog.set_config('search_path', '', false);

set check_function_bodies = false;

set xmloption = content;

set client_min_messages = warning;

set row_security = off;

--
-- Name: nlpg; Type: SCHEMA; Schema: -; Owner: -
--
create schema nlpg;

--
-- Name: _get_config(text); Type: FUNCTION; Schema: nlpg; Owner: -
--
create function nlpg._get_config (
    key text
)
    returns text
    language sql
    as $_$
    select
        value
    from
        nlpg._config
    where
        key = $1;
$_$;

--
-- Name: _set_config(text, text); Type: FUNCTION; Schema: nlpg; Owner: -
--
create function nlpg._set_config (
    key text,
    value text
)
    returns void
    language sql
    as $_$
    delete from nlpg._config
    where key = $1;
    insert into nlpg._config (key, value)
    select
        $1,
        $2;
$_$;

--
-- Name: feats_to_json(); Type: FUNCTION; Schema: nlpg; Owner: -
--
create function nlpg.feats_to_json ()
    returns trigger
    language plpgsql
    as $$
begin
    update
        morph
    set
        j = case when feats != '' then
            jsonb_object(regexp_split_to_array(feats, '\||='))
        else
            '{}'::jsonb
        end
    where
        id = new.id;
    return new;
end;
$$;

set default_tablespace = '';

set default_table_access_method = heap;

--
-- Name: token; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.token (
    sent integer not null,
    i integer not null,
    idx integer not null,
    len smallint not null,
    s text not null,
    tspace smallint not null
);

--
-- Name: word; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.word (
    dep smallint not null,
    lexeme integer not null,
    head integer not null
)
inherits (
    nlpg.token
);

--
-- Name: has_head(nlpg.word); Type: FUNCTION; Schema: nlpg; Owner: -
--
create function nlpg.has_head (
    nlpg.word
)
    returns nlpg.word
    language sql
    as $_$
    select
        m2
    from
        word m2
        join lexeme x2 on m2.lexeme = x2.id
        join lexeme x1 on $1.lexeme = x1.id
    where
        $1.string = m2.string
        and $1.head = m2.i
$_$;

--
-- Name: insert_annotations(integer); Type: FUNCTION; Schema: nlpg; Owner: -
--
create function nlpg.insert_annotations (
    integer default 1
)
    returns void
    language plpgsql
    as $_$
begin
    /* lemmas */
    raise info 'Inserting lemmas.';
    insert into lemma (str, pos)
    select distinct
        lemma,
        pos
    from
        _textobj
    where
        type = 1
    except
    select distinct
        str,
        pos
    from
        lemma;

    /* Morphologies */
    raise info 'Inserting morphologies.';
    insert into morph (feats)
    select distinct
        i.morph
    from
        _textobj i
    where
        type = 1
    except
    select distinct
        feats
    from
        nlpg.morph;

    /* Lexemes */
    raise info 'Inserting lexemes.';
    insert into lexeme (norm, lemma, morph)
    select distinct
        i.norm,
        l.id,
        m.id
    from
        _textobj i
        join lemma l on l.str = i.lemma
        join morph m on m.feats = i.morph
    where
        i.type = 1
    except
    select distinct
        x.norm,
        x.lemma,
        x.morph
    from
        lexeme x;

    /* Paragraphs */
    raise info 'Inserting paragraphs.';
    insert into par (string, i, idx, len)
    select
        i.text_id,
        i.par_i,
        i.idx,
        i.len
    from
        _textobj i
    where
        i.type = -2;

    /* Sentences */
    raise info 'Inserting sentences.';
    insert into sent (string, par, i, idx, len)
    select
        i.text_id,
        p.id,
        i.sent_i,
        i.idx,
        i.len
    from
        _textobj i
        join par p on p.string = i.text_id
            and p.i = i.par_i
    where
        i.type = -1;

    /* Update indexes */
    raise info 'Updating indexes.';
    analyze sent;
    analyze lemma;
    analyze lexeme;
    analyze _textobj;

    /* Words */
    raise info 'Inserting words.';
    insert into word (sent, i, idx, len, s, tspace, dep, lexeme, head)
    select
        s.id,
        i.i,
        i.idx,
        i.len,
        i.s,
        i.tspace,
        i.dep,
        x.id,
        i.head
    from
        _textobj i
        join lemma l on l.str = i.lemma
            and l.pos = i.pos
        join morph m on m.feats = i.morph
        join lexeme x on x.norm = i.norm
            and l.id = x.lemma
            and x.morph = m.id
        join par p on p.i = i.par_i
            and p.string = i.text_id
        join sent s on s.string = i.text_id
            and s.i = i.sent_i
            and p.id = s.par
    where
        i.type = 1;

    /* Non-word tokens */
    raise info 'Inserting non-words tokens...';
    insert into token (sent, i, idx, len, s, tspace)
    select
        s.id,
        i.i,
        i.idx,
        i.len,
        i.s,
        i.tspace
    from
        _textobj i
        -- TODO: par_i
        -- FIXME
        join par p on p.i = i.par_i
            and p.string = i.text_id
        join sent s on s.string = i.text_id
            and s.i = i.sent_i
            and p.id = s.par
    where
        i.type = 0;
    raise info 'Annotations successfully inserted!';

    /* Truncate table if parameter is 1. */
    if $1 = 1 then
        truncate _textobj;
    end if;
end;
$_$;

--
-- Name: _config; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg._config (
    key text,
    value text
);

--
-- Name: _textobj; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg._textobj (
    text_id integer,
    par_i integer,
    sent_i integer,
    type smallint,
    i integer,
    idx integer,
    len integer,
    s text,
    tspace smallint,
    norm text,
    pos smallint,
    morph text,
    lemma text,
    dep smallint,
    head integer,
    userdata jsonb
);

--
-- Name: dep; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.dep (
    id smallint not null,
    name text not null,
    definition text
);

--
-- Name: dep_id_seq; Type: SEQUENCE; Schema: nlpg; Owner: -
--
alter table nlpg.dep
    alter column id
    add generated by default as identity (sequence NAME
        nlpg.dep_id_seq start with 1 increment by 1
        no minvalue
        no maxvalue
        cache 1);

--
-- Name: lemma; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.lemma (
    id integer not null,
    pos smallint not null,
    str text not null
);

--
-- Name: lexeme; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.lexeme (
    id integer not null,
    lemma integer not null,
    morph smallint not null,
    norm text not null
);

--
-- Name: morph; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.morph (
    id smallint not null,
    feats text,
    j jsonb,
    numtype text,
    number text,
    person text,
    prontype text,
    mood text,
    tense text,
    definite text,
    verbform text,
    voice text,
    reflex text,
    polarity text,
    number_psor text,
    poss text
);

--
-- Name: pos; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.pos (
    id smallint not null,
    name text not null,
    definition text
);

--
-- Name: seg; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.seg (
    string integer not null,
    idx integer not null,
    len integer not null
);

--
-- Name: sent; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.sent (
    id integer not null,
    par integer not null,
    i integer not null
)
inherits (
    nlpg.seg
);

--
-- Name: lemma_id_seq; Type: SEQUENCE; Schema: nlpg; Owner: -
--
alter table nlpg.lemma
    alter column id
    add generated by default as identity (sequence NAME
        nlpg.lemma_id_seq start with 1 increment by 1
        no minvalue
        no maxvalue
        cache 1);

--
-- Name: lexeme_id_seq; Type: SEQUENCE; Schema: nlpg; Owner: -
--
alter table nlpg.lexeme
    alter column id
    add generated by default as identity (sequence NAME
        nlpg.lexeme_id_seq start with 1 increment by 1
        no minvalue
        no maxvalue
        cache 1);

--
-- Name: markup; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.markup (
    id integer,
    text text
);

--
-- Name: morph_id_seq; Type: SEQUENCE; Schema: nlpg; Owner: -
--
alter table nlpg.morph
    alter column id
    add generated by default as identity (sequence NAME
        nlpg.morph_id_seq start with 1 increment by 1
        no minvalue
        no maxvalue
        cache 1);

--
-- Name: par; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.par (
    id integer not null,
    i integer not null
)
inherits (
    nlpg.seg
);

--
-- Name: par_id_seq; Type: SEQUENCE; Schema: nlpg; Owner: -
--
alter table nlpg.par
    alter column id
    add generated by default as identity (sequence NAME
        nlpg.par_id_seq start with 1 increment by 1
        no minvalue
        no maxvalue
        cache 1);

--
-- Name: pos_id_seq; Type: SEQUENCE; Schema: nlpg; Owner: -
--
alter table nlpg.pos
    alter column id
    add generated by default as identity (sequence NAME
        nlpg.pos_id_seq start with 1 increment by 1
        no minvalue
        no maxvalue
        cache 1);

--
-- Name: sent_id_seq; Type: SEQUENCE; Schema: nlpg; Owner: -
--
alter table nlpg.sent
    alter column id
    add generated by default as identity (sequence NAME
        nlpg.sent_id_seq start with 1 increment by 1
        no minvalue
        no maxvalue
        cache 1);

--
-- Name: span; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.span (
    attrs jsonb
)
inherits (
    nlpg.seg
);

--
-- Name: stopword; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.stopword (
    norm text not null
);

--
-- Name: xspan; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.xspan (
    tag text
)
inherits (
    nlpg.span
);

--
-- Name: xtag; Type: TABLE; Schema: nlpg; Owner: -
--
create table nlpg.xtag (
    sid integer,
    idxtext integer,
    idxxml integer,
    len integer,
    s text
);

--
-- Name: dep dep_name_key; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.dep
    add constraint dep_name_key unique (name);

--
-- Name: dep dep_pkey; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.dep
    add constraint dep_pkey primary key (id);

--
-- Name: lemma lemma_pkey; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.lemma
    add constraint lemma_pkey primary key (id);

--
-- Name: lemma lemma_str_key; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.lemma
    add constraint lemma_str_pos_key unique (str, pos);

--
-- Name: lexeme lexeme_pkey; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.lexeme
    add constraint lexeme_pkey primary key (id);

--
-- Name: lexeme lexeme_uniq; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.lexeme
    add constraint lexeme_uniq unique (lemma, norm, morph);

--
-- Name: morph morph_feats_key; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.morph
    add constraint morph_feats_key unique (feats);

--
-- Name: morph morph_pkey; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.morph
    add constraint morph_pkey primary key (id);

--
-- Name: par par_pkey; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.par
    add constraint par_pkey primary key (id);

--
-- Name: pos pos_name_key; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.pos
    add constraint pos_name_key unique (name);

--
-- Name: pos pos_pkey; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.pos
    add constraint pos_pkey primary key (id);

--
-- Name: sent sent_pkey; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.sent
    add constraint sent_pkey primary key (id);

--
-- Name: stopword stopword_pkey; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.stopword
    add constraint stopword_pkey primary key (norm);

--
-- Name: token token_sent_i_key; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.token
    add constraint token_sent_i_key unique (sent, i);

--
-- Name: word word_sent_i_key; Type: CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.word
    add constraint word_sent_i_key unique (sent, i);

--
-- Name: dep_name_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index dep_name_idx on nlpg.dep using btree (name);

--
-- Name: lexeme_lemma_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index lexeme_lemma_idx on nlpg.lexeme using btree (lemma);

--
-- Name: lexeme_morph_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index lexeme_morph_idx on nlpg.lexeme using btree (morph);

--
-- Name: lexeme_norm_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index lexeme_norm_idx on nlpg.lexeme using btree (norm);

--
-- Name: lemma_pos_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index lemma_pos_idx on nlpg.lemma using btree (pos);

--
-- Name: morph_feats_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index morph_feats_idx on nlpg.morph using btree (feats);

--
-- Name: morph_j_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index morph_j_idx on nlpg.morph using btree (j);

--
-- Name: par_i_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index par_i_idx on nlpg.par using btree (i);

--
-- Name: pos_name_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index pos_name_idx on nlpg.pos using btree (name);

--
-- Name: seg_string_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index seg_string_idx on nlpg.seg using btree (string);

--
-- Name: sent_i_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index sent_i_idx on nlpg.sent using btree (i);

--
-- Name: sent_par_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index sent_par_idx on nlpg.sent using btree (par);

--
-- Name: sent_string_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index sent_string_idx on nlpg.sent using btree (string);

--
-- Name: word_dep_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index word_dep_idx on nlpg.word using btree (dep);

--
-- Name: word_head_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index word_head_idx on nlpg.word using btree (head);

--
-- Name: word_i_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index word_i_idx on nlpg.word using btree (i);

--
-- Name: word_lexeme_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index word_lexeme_idx on nlpg.word using btree (lexeme);

--
-- Name: word_sent_idx; Type: INDEX; Schema: nlpg; Owner: -
--
create index word_sent_idx on nlpg.word using btree (sent);

--
-- Name: morph jsonize_feats; Type: TRIGGER; Schema: nlpg; Owner: -
--
create trigger jsonize_feats
    after insert or update of feats on nlpg.morph for each row
    execute function nlpg.feats_to_json ();

--
-- Name: lexeme lexeme_lemma_fkey; Type: FK CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.lexeme
    add constraint lexeme_lemma_fkey foreign key (lemma) references nlpg.lemma (id);

--
-- Name: lexeme lexeme_morph_fkey; Type: FK CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.lexeme
    add constraint lexeme_morph_fkey foreign key (morph) references nlpg.morph (id);

--
-- Name: lexeme lemma_pos_fkey; Type: FK CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.lemma
    add constraint lemma_pos_fkey foreign key (pos) references nlpg.pos (id);

--
-- Name: sent sent_par_fkey; Type: FK CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.sent
    add constraint sent_par_fkey foreign key (par) references nlpg.par (id);

--
-- Name: token token_sent_fkey; Type: FK CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.token
    add constraint token_sent_fkey foreign key (sent) references nlpg.sent (id);

--
-- Name: word word_dep_fkey; Type: FK CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.word
    add constraint word_dep_fkey foreign key (dep) references nlpg.dep (id);

--
-- Name: word word_lexeme_fkey; Type: FK CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.word
    add constraint word_lexeme_fkey foreign key (lexeme) references nlpg.lexeme (id);

--
-- Name: word word_sent_fkey; Type: FK CONSTRAINT; Schema: nlpg; Owner: -
--
alter table only nlpg.word
    add constraint word_sent_fkey foreign key (sent) references nlpg.sent (id);

-- 2025-04-21
create or replace view nlpg.word_ as
select
    sent.string,
    sent.id as sent,
    sent.par,
    word.i,
    word.s,
    word.tspace,
    word.idx,
    word.len,
    lexeme.norm,
    lemma.str as lemma,
    pos.name as pos,
    word.head,
    dep.name as dep,
    morph.number,
    morph.mood,
    morph.verbform,
    morph.polarity,
    morph.prontype,
    morph.voice,
    morph.number_psor,
    morph.poss,
    morph.numtype,
    morph.person,
    morph.definite,
    morph.tense,
    morph.reflex
from
    nlpg.word
    join nlpg.sent on sent.id = word.sent
    join nlpg.lexeme on lexeme.id = word.lexeme
    join nlpg.lemma on lemma.id = lexeme.lemma
    join nlpg.pos on pos.id = lemma.pos
    join nlpg.morph on morph.id = lexeme.morph
    join nlpg.dep on dep.id = word.dep;

-- 2025-04-21
create or replace view nlpg.token_ as
select
    sent.string,
    sent.id as sent,
    sent.par,
    word.i,
    word.s,
    word.tspace,
    word.idx,
    word.len,
    lexeme.norm,
    lemma.str as lemma,
    pos.name as pos,
    word.head,
    dep.name as dep
from
    nlpg.word
    join nlpg.sent on sent.id = word.sent
    join nlpg.lexeme on lexeme.id = word.lexeme
    join nlpg.lemma on lemma.id = lexeme.lemma
    join nlpg.pos on pos.id = lemma.pos
    join nlpg.dep on dep.id = word.dep
union
select
    sent.string,
    sent.id as sent,
    sent.par,
    token.i,
    token.s,
    token.tspace,
    token.idx,
    token.len,
    ''::text as norm,
    ''::text as lemma,
    ''::text as pos,
    '-1'::integer as head,
    ''::text as dep
from
    only nlpg.token
    join nlpg.sent on sent.id = token.sent;

-- 2025-04-21
create or replace function nlpg.tokenandtag (
    sid int
)
    returns table (
            s text,
            tspace int,
            lemma text,
            pos text,
            idxtext int,
            idxxml int
)
    language sql
    as $$
    with x as (
        select
            token.s,
            token.tspace,
            '' as lemma,
            '' as pos,
            token.idx as idxtext,
            token.idx as idxxml
        from
            only nlpg.token
            join nlpg.sent on sent.id = token.sent
        where
            sent.string = $1
        union
        select
            word.s,
            word.tspace,
            lemma.str,
            pos.name as pos,
            word.idx as idxtext,
            word.idx as idxxml
        from
            nlpg.word
            join nlpg.sent on sent.id = word.sent
            join nlpg.lexeme on lexeme.id = word.lexeme
            join nlpg.lemma on lemma.id = lexeme.lemma
            join nlpg.pos on pos.id = lemma.pos
        where
            sent.string = $1
        union
        select
            s,
            0 as tspace,
            '' as lemma,
            '' as pos,
            idxtext,
            idxxml
        from
            nlpg.xtag
        where
            sid = $1
)
    select
        *
    from
        x
    order by
        idxtext,
        idxxml
$$;

--
-- PostgreSQL database dump complete
--
