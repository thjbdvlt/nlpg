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
-- Name: eav; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA eav;


--
-- Name: importer(); Type: PROCEDURE; Schema: eav; Owner: -
--

CREATE PROCEDURE eav.importer()
    LANGUAGE plpgsql
    AS $$
    declare

    begin

        -- crée une table temporaire pour préparer l'insertion des entités, de leurs propriétés et de leurs relations. cette première table sépare les champs "id", "class", "relations" et "attributes", qui requierent tous des traitements différents.
        create temp table _ent as 
        select 
            nextval('eav.entity_id_seq') as id,
            j ->> 'id' as import_id,
            j ->> 'class' as class_name,
            j -> 'relations' as relations,
            j - 'id' - 'class' - 'relations' as attributes
        from eav._entity;

        -- ajoute les classs manquantes.
        insert into eav.class (name)
        select distinct class_name from _ent
        except select name from eav.class;

        -- ajoute les entités dans la lookup table.
        insert into eav._lookup_ent
        (id, import_id)
        select id, import_id from _ent;

        -- ajoute les entités
        insert into eav.entity (id, class)
        select
            e.id as id,
            c.id as class
        from _ent e
        join eav.class c
        on c.name = e.class_name;

        -- déplie les relations
        create temp table _relation_text as
        select
            id as sub,
            r.*
        from _ent e,
        jsonb_to_recordset(e.relations) as r (type text, obj text);

        -- ajoute les types de relations
        insert into eav.relation_type (name)
        select distinct type from _relation_text
        except
        select name from eav.relation_type;

        -- ajoute les relations
        insert into eav.relation (sub, type, obj)
        select
            r.sub,
            y.id as type,
            l2.id as obj
        from _relation_text r
        join eav._lookup_ent l2 on l2.import_id = r.obj
        join eav.relation_type y on y.name = r.type;

        -- déplie les propriétés dans un format key/value (deux colonnes), ajoute le 'datatype' jsonb (string, array, object, number), duquel va dépendre la sous-tablede propriété dans laquelle chaque propriété va aller.
        create temp table _attribute as
        select
            e.id as entity,
            regexp_replace(key, '^xml_', '') as type_name,
            jsonb_build_array(value) as val,
            case when key like 'xml_%' then
                'xml'
            else
                jsonb_typeof(value)
            end as datatype
        from
            _ent e,
            jsonb_each(e.attributes);

        -- ajoute les types de propriétés
        insert into eav.attr_type (name)
        select distinct regexp_replace(type_name, '^xml_', '')
        from _attribute
        except
        select name from eav.attr_type;

        -- ajoute les strings (les propriétés de datatype string).
        insert into eav.xml (entity, type, val)
        select
            p.entity,
            y.id as type,
            p.val ->> 0 as val
        from _attribute p
        join eav.attr_type y on y.name = p.type_name
        where p.datatype = 'xml';

        -- ajoute les strings (les propriétés de datatype string).
        insert into eav.string (entity, type, val)
        select
            p.entity,
            y.id as type,
            p.val ->> 0 as val
        from _attribute p
        join eav.attr_type y on y.name = p.type_name
        where p.datatype = 'string';

        -- ajoute les propriétés à valeur jsonb (array/object).
        insert into eav.attr_jsonb (entity, type, val)
        select
            p.entity,
            y.id as type,
            p.val -> 0 as val
        from _attribute p
        join eav.attr_type y on y.name = p.type_name
        where p.datatype in ('array', 'object');

        -- ajoute les propriétés numériques entières.
        insert into eav.attr_int (entity, type, val)
        select
            p.entity,
            y.id as type,
            (p.val -> 0)::integer as val
        from _attribute p
        join eav.attr_type y on y.name = p.type_name
        where p.datatype = 'number' and not regexp_like(p.val ->> 0, '\.');

        -- ajoute les propriétés numériques décimales.
        insert into eav.attr_float (entity, type, val)
        select
            p.entity,
            y.id as type,
            (p.val -> 0)::float as val
        from _attribute p
        join eav.attr_type y on y.name = p.type_name
        where p.datatype = 'number' and regexp_like(p.val ->> 0, '\.');

        -- ajoute les propriétés numériques décimales.
        insert into eav.attribute (entity, type)
        select
            p.entity,
            y.id as type
        from _attribute p
        join eav.attr_type y on y.name = p.type_name
        where p.datatype = 'null' ;

        -- drop les tables temporaires, 
        drop table _attribute;
        drop table _relation_text;
        drop table _ent;

        -- vider la table d'importation.
        truncate eav._entity;

    end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: _entity; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav._entity (
    j jsonb
);


--
-- Name: _lookup_ent; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav._lookup_ent (
    import_id text,
    id integer
);


--
-- Name: attribute; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.attribute (
    type smallint NOT NULL,
    entity integer NOT NULL
);


--
-- Name: attr_date; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.attr_date (
    val timestamp without time zone
)
INHERITS (eav.attribute);


--
-- Name: attr_float; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.attr_float (
    val double precision
)
INHERITS (eav.attribute);


--
-- Name: attr_int; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.attr_int (
    val integer
)
INHERITS (eav.attribute);


--
-- Name: attr_jsonb; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.attr_jsonb (
    val jsonb
)
INHERITS (eav.attribute);


--
-- Name: concept; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.concept (
    name text NOT NULL,
    definition text
);


--
-- Name: attr_type; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.attr_type (
    id smallint NOT NULL
)
INHERITS (eav.concept);


--
-- Name: attr_type_id_seq; Type: SEQUENCE; Schema: eav; Owner: -
--

ALTER TABLE eav.attr_type ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME eav.attr_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: class; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.class (
    id smallint NOT NULL
)
INHERITS (eav.concept);


--
-- Name: class_id_seq; Type: SEQUENCE; Schema: eav; Owner: -
--

ALTER TABLE eav.class ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME eav.class_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: entity; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.entity (
    id integer NOT NULL,
    class smallint NOT NULL
);


--
-- Name: entity_id_seq; Type: SEQUENCE; Schema: eav; Owner: -
--

ALTER TABLE eav.entity ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME eav.entity_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: relation; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.relation (
    type smallint NOT NULL,
    sub integer NOT NULL,
    obj integer NOT NULL
);


--
-- Name: relation_type; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.relation_type (
    id smallint NOT NULL
)
INHERITS (eav.concept);


--
-- Name: relation_type_id_seq; Type: SEQUENCE; Schema: eav; Owner: -
--

ALTER TABLE eav.relation_type ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME eav.relation_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: string; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.string (
    id integer NOT NULL,
    val text
)
INHERITS (eav.attribute);


--
-- Name: string_id_seq; Type: SEQUENCE; Schema: eav; Owner: -
--

ALTER TABLE eav.string ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME eav.string_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: xml; Type: TABLE; Schema: eav; Owner: -
--

CREATE TABLE eav.xml (
    val text
)
INHERITS (eav.attribute);


--
-- Name: attr_date attr_date_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_date
    ADD CONSTRAINT attr_date_uniq_fkey UNIQUE (entity, type);


--
-- Name: attr_float attr_float_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_float
    ADD CONSTRAINT attr_float_uniq_fkey UNIQUE (entity, type);


--
-- Name: attr_int attr_int_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_int
    ADD CONSTRAINT attr_int_uniq_fkey UNIQUE (entity, type);


--
-- Name: attr_jsonb attr_jsonb_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_jsonb
    ADD CONSTRAINT attr_jsonb_uniq_fkey UNIQUE (entity, type);


--
-- Name: attr_type attr_type_name_key; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_type
    ADD CONSTRAINT attr_type_name_key UNIQUE (name);


--
-- Name: attr_type attr_type_pkey; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_type
    ADD CONSTRAINT attr_type_pkey PRIMARY KEY (id);


--
-- Name: attribute attribute_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attribute
    ADD CONSTRAINT attribute_uniq_fkey UNIQUE (entity, type);


--
-- Name: class class_name_key; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.class
    ADD CONSTRAINT class_name_key UNIQUE (name);


--
-- Name: class class_pkey; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.class
    ADD CONSTRAINT class_pkey PRIMARY KEY (id);


--
-- Name: entity entity_pkey; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.entity
    ADD CONSTRAINT entity_pkey PRIMARY KEY (id);


--
-- Name: relation_type relation_type_name_key; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.relation_type
    ADD CONSTRAINT relation_type_name_key UNIQUE (name);


--
-- Name: relation_type relation_type_pkey; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.relation_type
    ADD CONSTRAINT relation_type_pkey PRIMARY KEY (id);


--
-- Name: string string_pkey; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.string
    ADD CONSTRAINT string_pkey PRIMARY KEY (id);


--
-- Name: string string_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.string
    ADD CONSTRAINT string_uniq_fkey UNIQUE (entity, type);


--
-- Name: xml xml_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.xml
    ADD CONSTRAINT xml_uniq_fkey UNIQUE (entity, type);


--
-- Name: attr_float_entity_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX attr_float_entity_idx ON eav.attr_float USING btree (entity);


--
-- Name: attr_float_type_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX attr_float_type_idx ON eav.attr_float USING btree (type);


--
-- Name: attr_int_entity_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX attr_int_entity_idx ON eav.attr_int USING btree (entity);


--
-- Name: attr_int_type_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX attr_int_type_idx ON eav.attr_int USING btree (type);


--
-- Name: attr_jsonb_entity_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX attr_jsonb_entity_idx ON eav.attr_jsonb USING btree (entity);


--
-- Name: attr_jsonb_type_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX attr_jsonb_type_idx ON eav.attr_jsonb USING btree (type);


--
-- Name: attr_type_name_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX attr_type_name_idx ON eav.attr_type USING btree (name);


--
-- Name: attribute_entity_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX attribute_entity_idx ON eav.attribute USING btree (entity);


--
-- Name: attribute_type_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX attribute_type_idx ON eav.attribute USING btree (type);


--
-- Name: class_name_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX class_name_idx ON eav.class USING btree (name);


--
-- Name: entity_class_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX entity_class_idx ON eav.entity USING btree (class);


--
-- Name: relation_obj_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX relation_obj_idx ON eav.relation USING btree (obj);


--
-- Name: relation_sub_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX relation_sub_idx ON eav.relation USING btree (sub);


--
-- Name: relation_type_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX relation_type_idx ON eav.relation USING btree (type);


--
-- Name: relation_type_name_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX relation_type_name_idx ON eav.relation_type USING btree (name);


--
-- Name: string_entity_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX string_entity_idx ON eav.string USING btree (entity);


--
-- Name: string_type_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX string_type_idx ON eav.string USING btree (type);


--
-- Name: xml_entity_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX xml_entity_idx ON eav.xml USING btree (entity);


--
-- Name: xml_type_idx; Type: INDEX; Schema: eav; Owner: -
--

CREATE INDEX xml_type_idx ON eav.xml USING btree (type);


--
-- Name: attr_date attr_date_entity_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_date
    ADD CONSTRAINT attr_date_entity_fk FOREIGN KEY (entity) REFERENCES eav.entity(id);


--
-- Name: attr_date attr_date_type_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_date
    ADD CONSTRAINT attr_date_type_fk FOREIGN KEY (type) REFERENCES eav.attr_type(id);


--
-- Name: attr_float attr_float_entity_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_float
    ADD CONSTRAINT attr_float_entity_fk FOREIGN KEY (entity) REFERENCES eav.entity(id);


--
-- Name: attr_float attr_float_type_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_float
    ADD CONSTRAINT attr_float_type_fk FOREIGN KEY (type) REFERENCES eav.attr_type(id);


--
-- Name: attr_int attr_int_entity_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_int
    ADD CONSTRAINT attr_int_entity_fk FOREIGN KEY (entity) REFERENCES eav.entity(id);


--
-- Name: attr_int attr_int_type_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_int
    ADD CONSTRAINT attr_int_type_fk FOREIGN KEY (type) REFERENCES eav.attr_type(id);


--
-- Name: attr_jsonb attr_jsonb_entity_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_jsonb
    ADD CONSTRAINT attr_jsonb_entity_fk FOREIGN KEY (entity) REFERENCES eav.entity(id);


--
-- Name: attr_jsonb attr_jsonb_type_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attr_jsonb
    ADD CONSTRAINT attr_jsonb_type_fk FOREIGN KEY (type) REFERENCES eav.attr_type(id);


--
-- Name: attribute attribute_entity_fkey; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attribute
    ADD CONSTRAINT attribute_entity_fkey FOREIGN KEY (entity) REFERENCES eav.entity(id);


--
-- Name: attribute attribute_type_fkey; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.attribute
    ADD CONSTRAINT attribute_type_fkey FOREIGN KEY (type) REFERENCES eav.attr_type(id);


--
-- Name: entity entity_class_fkey; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.entity
    ADD CONSTRAINT entity_class_fkey FOREIGN KEY (class) REFERENCES eav.class(id);


--
-- Name: relation relation_obj_fkey; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.relation
    ADD CONSTRAINT relation_obj_fkey FOREIGN KEY (obj) REFERENCES eav.entity(id);


--
-- Name: relation relation_sub_fkey; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.relation
    ADD CONSTRAINT relation_sub_fkey FOREIGN KEY (sub) REFERENCES eav.entity(id);


--
-- Name: relation relation_type_fkey; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.relation
    ADD CONSTRAINT relation_type_fkey FOREIGN KEY (type) REFERENCES eav.relation_type(id);


--
-- Name: string string_entity_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.string
    ADD CONSTRAINT string_entity_fk FOREIGN KEY (entity) REFERENCES eav.entity(id);


--
-- Name: string string_type_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.string
    ADD CONSTRAINT string_type_fk FOREIGN KEY (type) REFERENCES eav.attr_type(id);


--
-- Name: xml xml_entity_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.xml
    ADD CONSTRAINT xml_entity_fk FOREIGN KEY (entity) REFERENCES eav.entity(id);


--
-- Name: xml xml_type_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--

ALTER TABLE ONLY eav.xml
    ADD CONSTRAINT xml_type_fk FOREIGN KEY (type) REFERENCES eav.attr_type(id);


--
-- PostgreSQL database dump complete
--

