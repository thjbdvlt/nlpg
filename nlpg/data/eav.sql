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
-- Name: eav; Type: SCHEMA; Schema: -; Owner: -
--
create schema eav;

--
-- Name: importer(); Type: PROCEDURE; Schema: eav; Owner: -
--
create procedure eav.importer ()
language plpgsql
as $$
declare
begin
    -- Create a temporary table to prepare insertion of entities, properties and relations. This first table separate fields "id", "class", "relations" and "attributes" (i.e. everything else). All these fields require different processing.
    create temp table _ent as
    select
        nextval('eav.entity_id_seq') as id,
        j ->> 'id' as import_id,
        j ->> 'class' as class_name,
        j -> 'relations' as relations,
        j - 'id' - 'class' - 'relations' as attributes
    from
        eav._entity;
    -- Add new classes.
    insert into eav.class (
        name)
    select distinct
        class_name
    from
        _ent
    except
    select
        name
    from
        eav.class;
    -- Add entities in the lookup table.
    insert into eav._lookup_ent (
        id,
        import_id)
    select
        id,
        import_id
    from
        _ent;
    -- Insert entities.
    insert into eav.entity (
        id,
        class)
    select
        e.id as id,
        c.id as class
    from
        _ent e
        join eav.class c on c.name = e.class_name;
    -- Unfold relations.
    -- TODO: ensure there's ALWAYS an "obj" and "type" fields.
    create temp table _relation_text as
    select
        id as sub,
        r.*
    from
        _ent e,
        jsonb_to_recordset(e.relations) as r (type text,
        obj text);
    -- Add relation types.
    insert into eav.relation_type (
        name)
    select distinct
        type
    from
        _relation_text
    except
    select
        name
    from
        eav.relation_type;
    -- Add relations.
    insert into eav.relation (
        sub,
        type,
        obj)
    select
        r.sub,
        y.id as type,
        l2.id as obj
    from
        _relation_text r
        join eav._lookup_ent l2 on l2.import_id = r.obj
        join eav.relation_type y on y.name = r.type;
    -- Unfold properties in key/value format (2 columns). Add 'datatype' from jsonb, so that we know in which table we must put each property.
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
    -- Add property types.
    insert into eav.attr_type (
        name)
    select distinct
        regexp_replace(type_name, '^xml_', '')
    from
        _attribute
    except
    select
        name
    from
        eav.attr_type;
    -- Add XML-encoded attributes.
    insert into eav.xml(
        entity, type, val)
    select
        p.entity,
        y.id as type,
        p.val ->> 0 as val
    from
        _attribute p
        join eav.attr_type y on y.name = p.type_name
    where
        p.datatype = 'xml';
    -- Add strings (i.e. attribute for datatype 'text').
    insert into eav.string (
        entity,
        type,
        val)
    select
        p.entity,
        y.id as type,
        p.val ->> 0 as val
    from
        _attribute p
        join eav.attr_type y on y.name = p.type_name
    where
        p.datatype = 'string';
    -- Add JSONB properties (array or objects).
    insert into eav.attr_jsonb (
        entity,
        type,
        val)
    select
        p.entity,
        y.id as type,
        p.val -> 0 as val
    from
        _attribute p
        join eav.attr_type y on y.name = p.type_name
    where
        p.datatype in ('array', 'object');
    -- Add integers numeric attributes.
    insert into eav.attr_int (
        entity,
        type,
        val)
    select
        p.entity,
        y.id as type,
        (p.val -> 0)::integer as val
    from
        _attribute p
        join eav.attr_type y on y.name = p.type_name
    where
        p.datatype = 'number'
        and not regexp_like (p.val ->> 0, '\.');
    -- Add float numeric attributes.
    insert into eav.attr_float (
        entity,
        type,
        val)
    select
        p.entity,
        y.id as type,
        (p.val -> 0)::float as val
    from
        _attribute p
        join eav.attr_type y on y.name = p.type_name
    where
        p.datatype = 'number'
        and regexp_like (p.val ->> 0, '\.');
    -- Add attributes without values.
    insert into eav.attribute (
        entity,
        type)
    select
        p.entity,
        y.id as type
    from
        _attribute p
        join eav.attr_type y on y.name = p.type_name
    where
        p.datatype = 'null';
    -- Drop temporary tables.
    drop table _attribute;
    drop table _relation_text;
    drop table _ent;
    -- Empty the import table.
    truncate eav._entity;
end;
$$;

set default_tablespace = '';

set default_table_access_method = heap;

--
-- Name: _entity; Type: TABLE; Schema: eav; Owner: -
--
create table eav._entity (
    j jsonb
);

--
-- Name: _lookup_ent; Type: TABLE; Schema: eav; Owner: -
--
create table eav._lookup_ent (
    import_id text,
    id integer
);

--
-- Name: attribute; Type: TABLE; Schema: eav; Owner: -
--
create table eav.attribute (
    type smallint not null,
    entity integer not null
);

--
-- Name: attr_date; Type: TABLE; Schema: eav; Owner: -
--
create table eav.attr_date (
    val timestamp without time zone
)
inherits (
    eav.attribute
);

--
-- Name: attr_float; Type: TABLE; Schema: eav; Owner: -
--
create table eav.attr_float (
    val double precision
)
inherits (
    eav.attribute
);

--
-- Name: attr_int; Type: TABLE; Schema: eav; Owner: -
--
create table eav.attr_int (
    val integer
)
inherits (
    eav.attribute
);

--
-- Name: attr_jsonb; Type: TABLE; Schema: eav; Owner: -
--
create table eav.attr_jsonb (
    val jsonb
)
inherits (
    eav.attribute
);

--
-- Name: concept; Type: TABLE; Schema: eav; Owner: -
--
create table eav.concept (
    name text not null,
    definition text
);

--
-- Name: attr_type; Type: TABLE; Schema: eav; Owner: -
--
create table eav.attr_type (
    id smallint not null
)
inherits (
    eav.concept
);

--
-- Name: attr_type_id_seq; Type: SEQUENCE; Schema: eav; Owner: -
--
alter table eav.attr_type
    alter column id
    add generated by default as identity (sequence NAME
        eav.attr_type_id_seq start with 1 increment by 1
        no minvalue
        no maxvalue
        cache 1);

--
-- Name: class; Type: TABLE; Schema: eav; Owner: -
--
create table eav.class (
    id smallint not null
)
inherits (
    eav.concept
);

--
-- Name: class_id_seq; Type: SEQUENCE; Schema: eav; Owner: -
--
alter table eav.class
    alter column id
    add generated by default as identity (sequence NAME
        eav.class_id_seq start with 1 increment by 1
        no minvalue
        no maxvalue
        cache 1);

--
-- Name: entity; Type: TABLE; Schema: eav; Owner: -
--
create table eav.entity (
    id integer not null,
    class smallint not null
);

--
-- Name: entity_id_seq; Type: SEQUENCE; Schema: eav; Owner: -
--
alter table eav.entity
    alter column id
    add generated by default as identity (sequence NAME
        eav.entity_id_seq start with 1 increment by 1
        no minvalue
        no maxvalue
        cache 1);

--
-- Name: relation; Type: TABLE; Schema: eav; Owner: -
--
create table eav.relation (
    type smallint not null,
    sub integer not null,
    obj integer not null
);

--
-- Name: relation_type; Type: TABLE; Schema: eav; Owner: -
--
create table eav.relation_type (
    id smallint not null
)
inherits (
    eav.concept
);

--
-- Name: relation_type_id_seq; Type: SEQUENCE; Schema: eav; Owner: -
--
alter table eav.relation_type
    alter column id
    add generated by default as identity (sequence NAME
        eav.relation_type_id_seq start with 1 increment by 1
        no minvalue
        no maxvalue
        cache 1);

--
-- Name: string; Type: TABLE; Schema: eav; Owner: -
--
create table eav.string (
    id bigint not null,
    val text
)
inherits (
    eav.attribute
);

--
-- Name: string_id_seq; Type: SEQUENCE; Schema: eav; Owner: -
--
alter table eav.string
    alter column id
    add generated by default as identity (sequence NAME
        eav.string_id_seq start with 1 increment by 1
        no minvalue
        no maxvalue
        cache 1);

--
-- Name: xml; Type: TABLE; Schema: eav; Owner: -
--
create table eav.xml (
    val text
)
inherits (
    eav.attribute
);

--
-- Name: attr_date attr_date_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_date
    add constraint attr_date_uniq_fkey unique (entity, type);

--
-- Name: attr_float attr_float_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_float
    add constraint attr_float_uniq_fkey unique (entity, type);

--
-- Name: attr_int attr_int_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_int
    add constraint attr_int_uniq_fkey unique (entity, type);

--
-- Name: attr_jsonb attr_jsonb_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_jsonb
    add constraint attr_jsonb_uniq_fkey unique (entity, type);

--
-- Name: attr_type attr_type_name_key; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_type
    add constraint attr_type_name_key unique (name);

--
-- Name: attr_type attr_type_pkey; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_type
    add constraint attr_type_pkey primary key (id);

--
-- Name: attribute attribute_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attribute
    add constraint attribute_uniq_fkey unique (entity, type);

--
-- Name: class class_name_key; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.class
    add constraint class_name_key unique (name);

--
-- Name: class class_pkey; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.class
    add constraint class_pkey primary key (id);

--
-- Name: entity entity_pkey; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.entity
    add constraint entity_pkey primary key (id);

--
-- Name: relation_type relation_type_name_key; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.relation_type
    add constraint relation_type_name_key unique (name);

--
-- Name: relation_type relation_type_pkey; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.relation_type
    add constraint relation_type_pkey primary key (id);

--
-- Name: string string_pkey; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.string
    add constraint string_pkey primary key (id);

--
-- Name: string string_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.string
    add constraint string_uniq_fkey unique (entity, type);

--
-- Name: xml xml_uniq_fkey; Type: CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.xml
    add constraint xml_uniq_fkey unique (entity, type);

--
-- Name: attr_float_entity_idx; Type: INDEX; Schema: eav; Owner: -
--
create index attr_float_entity_idx on eav.attr_float using btree (entity);

--
-- Name: attr_float_type_idx; Type: INDEX; Schema: eav; Owner: -
--
create index attr_float_type_idx on eav.attr_float using btree (type);

--
-- Name: attr_int_entity_idx; Type: INDEX; Schema: eav; Owner: -
--
create index attr_int_entity_idx on eav.attr_int using btree (entity);

--
-- Name: attr_int_type_idx; Type: INDEX; Schema: eav; Owner: -
--
create index attr_int_type_idx on eav.attr_int using btree (type);

--
-- Name: attr_jsonb_entity_idx; Type: INDEX; Schema: eav; Owner: -
--
create index attr_jsonb_entity_idx on eav.attr_jsonb using btree (entity);

--
-- Name: attr_jsonb_type_idx; Type: INDEX; Schema: eav; Owner: -
--
create index attr_jsonb_type_idx on eav.attr_jsonb using btree (type);

--
-- Name: attr_type_name_idx; Type: INDEX; Schema: eav; Owner: -
--
create index attr_type_name_idx on eav.attr_type using btree (name);

--
-- Name: attribute_entity_idx; Type: INDEX; Schema: eav; Owner: -
--
create index attribute_entity_idx on eav.attribute using btree (entity);

--
-- Name: attribute_type_idx; Type: INDEX; Schema: eav; Owner: -
--
create index attribute_type_idx on eav.attribute using btree (type);

--
-- Name: class_name_idx; Type: INDEX; Schema: eav; Owner: -
--
create index class_name_idx on eav.class using btree (name);

--
-- Name: entity_class_idx; Type: INDEX; Schema: eav; Owner: -
--
create index entity_class_idx on eav.entity using btree (class);

--
-- Name: relation_obj_idx; Type: INDEX; Schema: eav; Owner: -
--
create index relation_obj_idx on eav.relation using btree (obj);

--
-- Name: relation_sub_idx; Type: INDEX; Schema: eav; Owner: -
--
create index relation_sub_idx on eav.relation using btree (sub);

--
-- Name: relation_type_idx; Type: INDEX; Schema: eav; Owner: -
--
create index relation_type_idx on eav.relation using btree (type);

--
-- Name: relation_type_name_idx; Type: INDEX; Schema: eav; Owner: -
--
create index relation_type_name_idx on eav.relation_type using btree (name);

--
-- Name: string_entity_idx; Type: INDEX; Schema: eav; Owner: -
--
create index string_entity_idx on eav.string using btree (entity);

--
-- Name: string_type_idx; Type: INDEX; Schema: eav; Owner: -
--
create index string_type_idx on eav.string using btree (type);

--
-- Name: xml_entity_idx; Type: INDEX; Schema: eav; Owner: -
--
create index xml_entity_idx on eav.xml using btree (entity);

--
-- Name: xml_type_idx; Type: INDEX; Schema: eav; Owner: -
--
create index xml_type_idx on eav.xml using btree (type);

--
-- Name: attr_date attr_date_entity_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_date
    add constraint attr_date_entity_fk foreign key (entity) references eav.entity (id);

--
-- Name: attr_date attr_date_type_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_date
    add constraint attr_date_type_fk foreign key (type) references eav.attr_type (id);

--
-- Name: attr_float attr_float_entity_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_float
    add constraint attr_float_entity_fk foreign key (entity) references eav.entity (id);

--
-- Name: attr_float attr_float_type_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_float
    add constraint attr_float_type_fk foreign key (type) references eav.attr_type (id);

--
-- Name: attr_int attr_int_entity_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_int
    add constraint attr_int_entity_fk foreign key (entity) references eav.entity (id);

--
-- Name: attr_int attr_int_type_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_int
    add constraint attr_int_type_fk foreign key (type) references eav.attr_type (id);

--
-- Name: attr_jsonb attr_jsonb_entity_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_jsonb
    add constraint attr_jsonb_entity_fk foreign key (entity) references eav.entity (id);

--
-- Name: attr_jsonb attr_jsonb_type_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attr_jsonb
    add constraint attr_jsonb_type_fk foreign key (type) references eav.attr_type (id);

--
-- Name: attribute attribute_entity_fkey; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attribute
    add constraint attribute_entity_fkey foreign key (entity) references eav.entity (id);

--
-- Name: attribute attribute_type_fkey; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.attribute
    add constraint attribute_type_fkey foreign key (type) references eav.attr_type (id);

--
-- Name: entity entity_class_fkey; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.entity
    add constraint entity_class_fkey foreign key (class) references eav.class (id);

--
-- Name: relation relation_obj_fkey; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.relation
    add constraint relation_obj_fkey foreign key (obj) references eav.entity (id);

--
-- Name: relation relation_sub_fkey; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.relation
    add constraint relation_sub_fkey foreign key (sub) references eav.entity (id);

--
-- Name: relation relation_type_fkey; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.relation
    add constraint relation_type_fkey foreign key (type) references eav.relation_type (id);

--
-- Name: string string_entity_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.string
    add constraint string_entity_fk foreign key (entity) references eav.entity (id);

--
-- Name: string string_type_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.string
    add constraint string_type_fk foreign key (type) references eav.attr_type (id);

--
-- Name: xml xml_entity_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.xml
    add constraint xml_entity_fk foreign key (entity) references eav.entity (id);

--
-- Name: xml xml_type_fk; Type: FK CONSTRAINT; Schema: eav; Owner: -
--
alter table only eav.xml
    add constraint xml_type_fk foreign key (type) references eav.attr_type (id);

--
-- PostgreSQL database dump complete
--
