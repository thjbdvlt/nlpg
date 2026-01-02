--
-- PostgreSQL database dump
--

-- Dumped from database version 16.8 (Debian 16.8-1.pgdg120+1)
-- Dumped by pg_dump version 16.8 (Debian 16.8-1.pgdg120+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgrespacy; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA postgrespacy;


--
-- Name: _get_config(text); Type: FUNCTION; Schema: postgrespacy; Owner: -
--

CREATE FUNCTION postgrespacy._get_config(key text) RETURNS text
    LANGUAGE sql
    AS $_$
    SELECT value FROM postgrespacy._config WHERE key = $1;
$_$;


--
-- Name: _set_config(text, text); Type: FUNCTION; Schema: postgrespacy; Owner: -
--

CREATE FUNCTION postgrespacy._set_config(key text, value text) RETURNS void
    LANGUAGE sql
    AS $_$
    DELETE FROM postgrespacy._config
    WHERE key = $1;
    INSERT INTO postgrespacy._config (key, value)
    SELECT
        $1,
        $2;
$_$;


--
-- Name: feats_to_json(); Type: FUNCTION; Schema: postgrespacy; Owner: -
--

CREATE FUNCTION postgrespacy.feats_to_json() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE
        morph
    SET
        j = CASE WHEN feats != '' THEN
            jsonb_object(regexp_split_to_array(feats, '\||='))
        ELSE
            '{}'::jsonb
        END
    WHERE
        id = new.id;

RETURN new;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: token; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.token (
    sent integer NOT NULL,
    i integer NOT NULL,
    idx integer NOT NULL,
    len smallint NOT NULL,
    s text NOT NULL,
    tspace smallint NOT NULL
);


--
-- Name: word; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.word (
    dep smallint NOT NULL,
    lexeme integer NOT NULL,
    head integer NOT NULL
)
INHERITS (postgrespacy.token);


--
-- Name: has_aux(postgrespacy.word, integer); Type: FUNCTION; Schema: postgrespacy; Owner: -
--

CREATE FUNCTION postgrespacy.has_aux(postgrespacy.word, n integer) RETURNS postgrespacy.word
    LANGUAGE sql
    AS $_$
select
    m2
from word m2
join lexeme x2 on m2.lexeme = x2.id
join pos n on n.id = x2.pos
join dep f on f.id = m2.dep
where $1.string = m2.string and $1.i = m2.head
and (n.name in ('aux', 'verb') or f.name like 'aux:%')
limit $2
$_$;


--
-- Name: has_head(postgrespacy.word); Type: FUNCTION; Schema: postgrespacy; Owner: -
--

CREATE FUNCTION postgrespacy.has_head(postgrespacy.word) RETURNS postgrespacy.word
    LANGUAGE sql
    AS $_$
select
    m2
from word m2
join lexeme x2 on m2.lexeme = x2.id
join lexeme x1 on $1.lexeme = x1.id
where $1.string = m2.string and $1.head = m2.i
$_$;


--
-- Name: insert_annotations(integer); Type: FUNCTION; Schema: postgrespacy; Owner: -
--

CREATE FUNCTION postgrespacy.insert_annotations(integer DEFAULT 1) RETURNS void
    LANGUAGE plpgsql
    AS $_$
BEGIN

    /* lemmas */
    RAISE info 'Inserting lemmas.';
    INSERT INTO lemma (str)
    SELECT DISTINCT
        lemma
    FROM
        _textobj
    WHERE
        type = 1
    EXCEPT
    SELECT DISTINCT
        str
    FROM
        lemma;

    /* Lexemes */
    RAISE info 'Inserting lexemes.';
    INSERT INTO lexeme (norm, pos, lemma, morph)
    SELECT DISTINCT
        i.norm,
        i.pos,
        l.id,
        i.morph
    FROM
        _textobj i
        JOIN lemma l ON l.str = i.lemma
    WHERE
        i.type = 1
    EXCEPT
    SELECT DISTINCT
        x.norm,
        x.pos,
        x.lemma,
        x.morph
    FROM
        lexeme x;

    /* Paragraphs */
    RAISE info 'Inserting paragraphs.';
    INSERT INTO par (string, i, idx, len)
    SELECT
        i.text_id,
        i.par_i,
        i.idx,
        i.len
    FROM
        _textobj i
    WHERE
        i.type = - 2;

    /* Sentences */
    RAISE info 'Inserting sentences.';
    INSERT INTO sent (string, par, i, idx, len)
    SELECT
        i.text_id,
        p.id,
        i.sent_i,
        i.idx,
        i.len
    FROM
        _textobj i
        JOIN par p ON p.string = i.text_id
            AND p.i = i.par_i
    WHERE
        i.type = - 1;

    /* Update indexes */
    RAISE info 'Updating indexes.';
    analyze sent;
    analyze lemma;
    analyze lexeme;
    analyze _textobj;

    /* Words */
    RAISE info 'Inserting words.';
    INSERT INTO word (sent, i, idx, len, s, tspace, dep, lexeme, head)
    SELECT
        s.id,
        i.i,
        i.idx,
        i.len,
        i.s,
        i.tspace,
        i.dep,
        x.id,
        i.head
    FROM
        _textobj i
        JOIN lemma l ON l.str = i.lemma
        JOIN lexeme x ON x.pos = i.pos
            AND x.norm = i.norm
            AND l.id = x.lemma
            AND i.morph = x.morph

        -- TODO: par_i
        -- FIXME
        JOIN par p ON p.i = i.par_i
            AND p.string = i.text_id
        JOIN sent s ON s.string = i.text_id
            AND s.i = i.sent_i
            AND p.id = s.par
    WHERE
        i.type = 1;

    /* Non-word tokens */
    RAISE info 'Inserting non-words tokens...';
    INSERT INTO token (sent, i, idx, len, s, tspace)
    SELECT
        s.id,
        i.i,
        i.idx,
        i.len,
        i.s,
        i.tspace
    FROM
        _textobj i
        -- TODO: par_i
        -- FIXME
        JOIN par p ON p.i = i.par_i
            AND p.string = i.text_id
        JOIN sent s ON s.string = i.text_id
            AND s.i = i.sent_i
            AND p.id = s.par
    WHERE
        i.type = 0;

    RAISE info 'Annotations successfully inserted!';

    /* Truncate table if parameter is 1. */
    IF $1 = 1 THEN
        TRUNCATE _textobj;
    END IF;
END;
$_$;


--
-- Name: _config; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy._config (
    key text,
    value text
);


--
-- Name: _textobj; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy._textobj (
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
    morph smallint,
    lemma text,
    dep smallint,
    head integer,
    userdata jsonb
);


--
-- Name: dep; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.dep (
    id smallint NOT NULL,
    name text NOT NULL,
    definition text
);


--
-- Name: dep_id_seq; Type: SEQUENCE; Schema: postgrespacy; Owner: -
--

ALTER TABLE postgrespacy.dep ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME postgrespacy.dep_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: lemma; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.lemma (
    id integer NOT NULL,
    str text NOT NULL
);


--
-- Name: lexeme; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.lexeme (
    id integer NOT NULL,
    lemma integer NOT NULL,
    pos smallint NOT NULL,
    morph smallint NOT NULL,
    norm text NOT NULL
);


--
-- Name: morph; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.morph (
    id smallint NOT NULL,
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
-- Name: pos; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.pos (
    id smallint NOT NULL,
    name text NOT NULL,
    definition text
);


--
-- Name: seg; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.seg (
    string integer NOT NULL,
    idx integer NOT NULL,
    len integer NOT NULL
);


--
-- Name: sent; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.sent (
    id integer NOT NULL,
    par integer NOT NULL,
    i integer NOT NULL
)
INHERITS (postgrespacy.seg);


--
-- Name: lemma_id_seq; Type: SEQUENCE; Schema: postgrespacy; Owner: -
--

ALTER TABLE postgrespacy.lemma ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME postgrespacy.lemma_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: lexeme_id_seq; Type: SEQUENCE; Schema: postgrespacy; Owner: -
--

ALTER TABLE postgrespacy.lexeme ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME postgrespacy.lexeme_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: markup; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.markup (
    id integer,
    text text
);


--
-- Name: morph_id_seq; Type: SEQUENCE; Schema: postgrespacy; Owner: -
--

ALTER TABLE postgrespacy.morph ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME postgrespacy.morph_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: par; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.par (
    id integer NOT NULL,
    i integer NOT NULL
)
INHERITS (postgrespacy.seg);


--
-- Name: par_id_seq; Type: SEQUENCE; Schema: postgrespacy; Owner: -
--

ALTER TABLE postgrespacy.par ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME postgrespacy.par_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: pos_id_seq; Type: SEQUENCE; Schema: postgrespacy; Owner: -
--

ALTER TABLE postgrespacy.pos ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME postgrespacy.pos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: sent_id_seq; Type: SEQUENCE; Schema: postgrespacy; Owner: -
--

ALTER TABLE postgrespacy.sent ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME postgrespacy.sent_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: span; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.span (
    attrs jsonb
)
INHERITS (postgrespacy.seg);


--
-- Name: stopword; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.stopword (
    norm text NOT NULL
);


--
-- Name: xspan; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.xspan (
    tag text
)
INHERITS (postgrespacy.span);


--
-- Name: xtag; Type: TABLE; Schema: postgrespacy; Owner: -
--

CREATE TABLE postgrespacy.xtag (
    sid integer,
    idxtext integer,
    idxxml integer,
    len integer,
    s text
);


--
-- Name: dep dep_name_key; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.dep
    ADD CONSTRAINT dep_name_key UNIQUE (name);


--
-- Name: dep dep_pkey; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.dep
    ADD CONSTRAINT dep_pkey PRIMARY KEY (id);


--
-- Name: lemma lemma_pkey; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.lemma
    ADD CONSTRAINT lemma_pkey PRIMARY KEY (id);


--
-- Name: lemma lemma_str_key; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.lemma
    ADD CONSTRAINT lemma_str_key UNIQUE (str);


--
-- Name: lexeme lexeme_pkey; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.lexeme
    ADD CONSTRAINT lexeme_pkey PRIMARY KEY (id);


--
-- Name: lexeme lexeme_uniq; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.lexeme
    ADD CONSTRAINT lexeme_uniq UNIQUE (lemma, norm, pos, morph);


--
-- Name: morph morph_feats_key; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.morph
    ADD CONSTRAINT morph_feats_key UNIQUE (feats);


--
-- Name: morph morph_pkey; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.morph
    ADD CONSTRAINT morph_pkey PRIMARY KEY (id);


--
-- Name: par par_pkey; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.par
    ADD CONSTRAINT par_pkey PRIMARY KEY (id);


--
-- Name: pos pos_name_key; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.pos
    ADD CONSTRAINT pos_name_key UNIQUE (name);


--
-- Name: pos pos_pkey; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.pos
    ADD CONSTRAINT pos_pkey PRIMARY KEY (id);


--
-- Name: sent sent_pkey; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.sent
    ADD CONSTRAINT sent_pkey PRIMARY KEY (id);


--
-- Name: stopword stopword_pkey; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.stopword
    ADD CONSTRAINT stopword_pkey PRIMARY KEY (norm);


--
-- Name: token token_sent_i_key; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.token
    ADD CONSTRAINT token_sent_i_key UNIQUE (sent, i);


--
-- Name: word word_sent_i_key; Type: CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.word
    ADD CONSTRAINT word_sent_i_key UNIQUE (sent, i);


--
-- Name: dep_name_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX dep_name_idx ON postgrespacy.dep USING btree (name);


--
-- Name: lexeme_lemma_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX lexeme_lemma_idx ON postgrespacy.lexeme USING btree (lemma);


--
-- Name: lexeme_morph_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX lexeme_morph_idx ON postgrespacy.lexeme USING btree (morph);


--
-- Name: lexeme_norm_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX lexeme_norm_idx ON postgrespacy.lexeme USING btree (norm);


--
-- Name: lexeme_pos_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX lexeme_pos_idx ON postgrespacy.lexeme USING btree (pos);


--
-- Name: morph_feats_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX morph_feats_idx ON postgrespacy.morph USING btree (feats);


--
-- Name: morph_j_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX morph_j_idx ON postgrespacy.morph USING btree (j);


--
-- Name: par_i_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX par_i_idx ON postgrespacy.par USING btree (i);


--
-- Name: pos_name_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX pos_name_idx ON postgrespacy.pos USING btree (name);


--
-- Name: seg_string_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX seg_string_idx ON postgrespacy.seg USING btree (string);


--
-- Name: sent_i_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX sent_i_idx ON postgrespacy.sent USING btree (i);


--
-- Name: sent_par_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX sent_par_idx ON postgrespacy.sent USING btree (par);


--
-- Name: sent_string_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX sent_string_idx ON postgrespacy.sent USING btree (string);


--
-- Name: word_dep_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX word_dep_idx ON postgrespacy.word USING btree (dep);


--
-- Name: word_head_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX word_head_idx ON postgrespacy.word USING btree (head);


--
-- Name: word_i_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX word_i_idx ON postgrespacy.word USING btree (i);


--
-- Name: word_lexeme_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX word_lexeme_idx ON postgrespacy.word USING btree (lexeme);


--
-- Name: word_sent_idx; Type: INDEX; Schema: postgrespacy; Owner: -
--

CREATE INDEX word_sent_idx ON postgrespacy.word USING btree (sent);


--
-- Name: morph jsonize_feats; Type: TRIGGER; Schema: postgrespacy; Owner: -
--

CREATE TRIGGER jsonize_feats AFTER INSERT OR UPDATE OF feats ON postgrespacy.morph FOR EACH ROW EXECUTE FUNCTION postgrespacy.feats_to_json();


--
-- Name: lexeme lexeme_lemma_fkey; Type: FK CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.lexeme
    ADD CONSTRAINT lexeme_lemma_fkey FOREIGN KEY (lemma) REFERENCES postgrespacy.lemma(id);


--
-- Name: lexeme lexeme_morph_fkey; Type: FK CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.lexeme
    ADD CONSTRAINT lexeme_morph_fkey FOREIGN KEY (morph) REFERENCES postgrespacy.morph(id);


--
-- Name: lexeme lexeme_pos_fkey; Type: FK CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.lexeme
    ADD CONSTRAINT lexeme_pos_fkey FOREIGN KEY (pos) REFERENCES postgrespacy.pos(id);


--
-- Name: sent sent_par_fkey; Type: FK CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.sent
    ADD CONSTRAINT sent_par_fkey FOREIGN KEY (par) REFERENCES postgrespacy.par(id);


--
-- Name: token token_sent_fkey; Type: FK CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.token
    ADD CONSTRAINT token_sent_fkey FOREIGN KEY (sent) REFERENCES postgrespacy.sent(id);


--
-- Name: word word_dep_fkey; Type: FK CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.word
    ADD CONSTRAINT word_dep_fkey FOREIGN KEY (dep) REFERENCES postgrespacy.dep(id);


--
-- Name: word word_lexeme_fkey; Type: FK CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.word
    ADD CONSTRAINT word_lexeme_fkey FOREIGN KEY (lexeme) REFERENCES postgrespacy.lexeme(id);


--
-- Name: word word_sent_fkey; Type: FK CONSTRAINT; Schema: postgrespacy; Owner: -
--

ALTER TABLE ONLY postgrespacy.word
    ADD CONSTRAINT word_sent_fkey FOREIGN KEY (sent) REFERENCES postgrespacy.sent(id);


-- 2025-04-21
CREATE OR REPLACE VIEW postgrespacy.word_ AS
 SELECT sent.string,
    sent.id AS sent,
    sent.par,
    word.i,
    word.s,
    word.tspace,
    word.idx,
    word.len,
    lexeme.norm,
    lemma.str AS lemma,
    pos.name AS pos,
    word.head,
    dep.name AS dep,
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
   FROM postgrespacy.word
     JOIN postgrespacy.sent ON sent.id = word.sent
     JOIN postgrespacy.lexeme ON lexeme.id = word.lexeme
     JOIN postgrespacy.lemma ON lemma.id = lexeme.lemma
     JOIN postgrespacy.pos ON pos.id = lexeme.pos
     JOIN postgrespacy.morph ON morph.id = lexeme.morph
     JOIN postgrespacy.dep ON dep.id = word.dep;


-- 2025-04-21
create or replace view postgrespacy.token_ as
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
    postgrespacy.word
    join postgrespacy.sent on sent.id = word.sent
    join postgrespacy.lexeme on lexeme.id = word.lexeme
    join postgrespacy.lemma on lemma.id = lexeme.lemma
    join postgrespacy.pos on pos.id = lexeme.pos
    join postgrespacy.dep on dep.id = word.dep
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
    only postgrespacy.token
    join postgrespacy.sent on sent.id = token.sent;


-- 2025-04-21
create or replace function postgrespacy.tokenandtag (
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
            only postgrespacy.token
            join postgrespacy.sent on sent.id = token.sent
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
            postgrespacy.word
            join postgrespacy.sent on sent.id = word.sent
            join postgrespacy.lexeme on lexeme.id = word.lexeme
            join postgrespacy.pos on pos.id = lexeme.pos
            join postgrespacy.lemma on lemma.id = lexeme.lemma
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
            postgrespacy.xtag
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

