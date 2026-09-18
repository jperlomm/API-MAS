--
-- PostgreSQL database dump
--

\restrict OSNH67ATfqQrteL06fnXZl2Fb2eqgHGih3lqi6WdnEuV8dM0bBZTzcjg1gFKfgz

-- Dumped from database version 15.15 (Debian 15.15-1.pgdg13+1)
-- Dumped by pg_dump version 15.15 (Debian 15.15-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'LATIN1';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: auditoria; Type: SCHEMA; Schema: -; Owner: spi40
--

CREATE SCHEMA auditoria;


ALTER SCHEMA auditoria OWNER TO spi40;

--
-- Name: auditoria_historico; Type: SCHEMA; Schema: -; Owner: spi40
--

CREATE SCHEMA auditoria_historico;


ALTER SCHEMA auditoria_historico OWNER TO spi40;

--
-- Name: permisos; Type: TYPE; Schema: public; Owner: spi40
--

CREATE TYPE public.permisos AS (
	permitidos smallint,
	negados smallint,
	efectivos smallint
);


ALTER TYPE public.permisos OWNER TO spi40;

--
-- Name: tablefunc_crosstab_2; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.tablefunc_crosstab_2 AS (
	row_name text,
	category_1 text,
	category_2 text
);


ALTER TYPE public.tablefunc_crosstab_2 OWNER TO postgres;

--
-- Name: tablefunc_crosstab_3; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.tablefunc_crosstab_3 AS (
	row_name text,
	category_1 text,
	category_2 text,
	category_3 text
);


ALTER TYPE public.tablefunc_crosstab_3 OWNER TO postgres;

--
-- Name: tablefunc_crosstab_4; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.tablefunc_crosstab_4 AS (
	row_name text,
	category_1 text,
	category_2 text,
	category_3 text,
	category_4 text
);


ALTER TYPE public.tablefunc_crosstab_4 OWNER TO postgres;

--
-- Name: tipo_permisos; Type: TYPE; Schema: public; Owner: spi40
--

CREATE TYPE public.tipo_permisos AS (
	permitido smallint,
	negado smallint
);


ALTER TYPE public.tipo_permisos OWNER TO spi40;

--
-- Name: activar_auditoria(text); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.activar_auditoria(tabla_auditada text) RETURNS void
    LANGUAGE plpgsql
    AS $$
                DECLARE
                    val_consulta text;
                BEGIN
                    --si no existe el trigger de la auditoria lo creo
                    IF NOT EXISTS(SELECT * FROM information_schema.triggers where event_object_table = tabla_auditada  and 'auditar_' || tabla_auditada ~ trigger_name) THEN
                        -- creo el trigger que audita la tabla
                        val_consulta := 'CREATE TRIGGER auditar_' || tabla_auditada || '
                                        AFTER INSERT OR UPDATE OR DELETE ON ' || tabla_auditada || '
                                        FOR EACH ROW EXECUTE PROCEDURE auditar_tabla();';
                        EXECUTE val_consulta;
                    ELSE
                        RAISE NOTICE 'La tabla % ya esta siendo auditada!', tabla_auditada;
                    END IF;

                    execute auditoria.regenerar_funciones_auditoria();                    

                END;
                $$;


ALTER FUNCTION auditoria.activar_auditoria(tabla_auditada text) OWNER TO spi40;

--
-- Name: desactivar_auditoria(text); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.desactivar_auditoria(tabla_auditada text) RETURNS void
    LANGUAGE plpgsql
    AS $$
                DECLARE

                BEGIN
                    IF EXISTS(SELECT * FROM information_schema.triggers where event_object_table = tabla_auditada  and 'auditar_' || tabla_auditada ~ trigger_name) THEN
                        -- ELIMINO el trigger que audita la tabla
                        EXECUTE 'DROP TRIGGER auditar_' || tabla_auditada || ' ON ' || tabla_auditada || ';';
                    ELSE
                        RAISE NOTICE 'La tabla % NO esta siendo auditada!', tabla_auditada;
                    END IF;

                    execute auditoria.regenerar_funciones_auditoria();

                END;
                $$;


ALTER FUNCTION auditoria.desactivar_auditoria(tabla_auditada text) OWNER TO spi40;

--
-- Name: regenerar_funciones_auditoria(); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.regenerar_funciones_auditoria() RETURNS void
    LANGUAGE plpgsql
    AS $_$
       DECLARE         
               val_tablas record;
               val_consulta_funcion_nombres text;
               val_consulta_funcion_valores text;
               val_consulta_funcion_pkeys text;
               val_consulta_funcion_orden_pkeys text;
               val_cont integer;
               val_campos record;
               val_separador text;
               val_separador_pkeys text;              
       BEGIN

               FOR val_tablas IN (select tabla,
                                         'agregar' as accion
                                    from sys_tablas_auditoria 
                                   where tabla != '' and 
                                         activo)  

                                 union                                                               

                                (select table_name,
                                        'quitar' as accion
                                   from information_schema.tables
                                  where table_schema = 'public' and
                                        table_type   = 'BASE TABLE' and
                                        table_name in (SELECT split_part(pg_catalog.oidvectortypes(proargtypes), ',', 1)
							FROM pg_proc
							WHERE proname ilike '%row_to_array%') and 
                                        table_name not in (select tabla
                                                             from sys_tablas_auditoria 
                                                            where tabla != '' and 
                                                                  activo)

                                  ) order by accion

               LOOP  
                       if (val_tablas.accion = 'agregar') then	

                           -- creo la funcion para convertir el registro a arreglo
                           val_consulta_funcion_valores     := 'CREATE OR REPLACE FUNCTION auditoria.row_to_array(' || val_tablas.tabla  || ',tipo integer) RETURNS text[] AS $BODY1$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[';
                           val_consulta_funcion_nombres     := '  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY[';
                           val_consulta_funcion_pkeys       := '  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY[';
                           val_consulta_funcion_orden_pkeys := '  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY[';
                           val_separador := '';
                           val_separador_pkeys := '';
                           val_cont := 1;
                           FOR val_campos IN                               	  
                                SELECT col.column_name,  
				       col.data_type,
				       col.ordinal_position,
				       (select true as es_pkey --tc.table_schema, tc.table_name, kc.column_name 
					  from information_schema.table_constraints tc,
					       information_schema.key_column_usage kc  
					 where tc.constraint_type = 'PRIMARY KEY' and
					       kc.table_name = tc.table_name and kc.table_schema = tc.table_schema and
					       kc.constraint_name = tc.constraint_name and 
					       tc.table_name = col.table_name and
					       tc.table_schema = col.table_schema and
					       kc.column_name =col.column_name) as es_pkey					  
					  FROM information_schema.columns as col
				         WHERE col.table_schema = 'public' AND 
					       col.table_name = quote_ident(val_tablas.tabla)
				      ORDER BY col.ordinal_position    
                           LOOP
                       
                               if (val_campos.data_type = 'boolean') then
                                   val_consulta_funcion_valores := val_consulta_funcion_valores || val_separador || 'bool_to_text($1.' || val_campos.column_name || ')';
                               else
                                   val_consulta_funcion_valores := val_consulta_funcion_valores || val_separador || 'COALESCE(replace($1.' || val_campos.column_name || '::text,' || '''''''''' || ',' || '''''''''''''' ||'),' || '''Valor_Del_Campo_Es_NULL'')';
                               end if;
                               val_consulta_funcion_nombres := val_consulta_funcion_nombres || val_separador || '''' || val_campos.column_name || '''';
                               if (val_campos.es_pkey) then
                                   val_consulta_funcion_pkeys  := val_consulta_funcion_pkeys || val_separador_pkeys || '''' || val_campos.column_name || '''';
                                   val_consulta_funcion_orden_pkeys  := val_consulta_funcion_orden_pkeys || val_separador_pkeys || '''' || val_campos.ordinal_position || '''';
                                   val_separador_pkeys := ', ';
                               end if;                              

                               val_separador := ', ';

                               val_cont := val_cont + 1;
                           end loop;                      
                                    
                           val_consulta_funcion_valores := val_consulta_funcion_valores || ']' || val_consulta_funcion_nombres || ']' || val_consulta_funcion_pkeys ||  ']' || val_consulta_funcion_orden_pkeys || ']  ELSE NULL END; $BODY1$ LANGUAGE SQL;';

                           execute val_consulta_funcion_valores;	
                           execute 'ALTER FUNCTION auditoria.row_to_array(' || val_tablas.tabla || ',tipo integer)  OWNER TO spi40;';		 
                           --raise notice '   +++++++++++++ agrego %',val_tablas.tabla;			    
                       else		
                           begin	
                              execute 'drop function auditoria.row_to_array(' || val_tablas.tabla || ',tipo integer)';
                              --raise notice '   ------------- quito %',val_tablas.tabla;			
                           EXCEPTION WHEN others THEN 
				raise notice 'No existe la funcion auditoria.row_to_array(%,tipo integer)', val_tablas.tabla ;
			   end;
                       end if;
               end loop;

       END;

       $_$;


ALTER FUNCTION auditoria.regenerar_funciones_auditoria() OWNER TO spi40;

--
-- Name: com_clientes_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.com_clientes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.com_clientes_id_seq OWNER TO spi40;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: com_clientes; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.com_clientes (
    id integer DEFAULT nextval('public.com_clientes_id_seq'::regclass) NOT NULL,
    denominacion character varying(100),
    tipo_documento smallint,
    nro_documento character varying(20),
    responsable character varying(100),
    telefono character varying(50) DEFAULT ''::character varying NOT NULL,
    telefono_movil character varying(50) DEFAULT ''::character varying NOT NULL,
    email_contacto character varying(50) DEFAULT ''::character varying NOT NULL,
    id_locacion_principal integer
);


ALTER TABLE public.com_clientes OWNER TO spi40;

--
-- Name: row_to_array(public.com_clientes, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.com_clientes, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.denominacion::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.tipo_documento::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.nro_documento::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.responsable::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.telefono::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.telefono_movil::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.email_contacto::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_locacion_principal::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'denominacion', 'tipo_documento', 'nro_documento', 'responsable', 'telefono', 'telefono_movil', 'email_contacto', 'id_locacion_principal']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.com_clientes, tipo integer) OWNER TO spi40;

--
-- Name: com_locaciones_clientes_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.com_locaciones_clientes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.com_locaciones_clientes_id_seq OWNER TO spi40;

--
-- Name: com_locaciones_clientes; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.com_locaciones_clientes (
    id integer DEFAULT nextval('public.com_locaciones_clientes_id_seq'::regclass) NOT NULL,
    id_cliente integer NOT NULL,
    descripcion character varying(100) DEFAULT ''::character varying NOT NULL,
    piso character varying(10) DEFAULT ''::character varying NOT NULL,
    departamento character varying(10) DEFAULT ''::character varying NOT NULL,
    id_pais smallint,
    id_localidad smallint NOT NULL,
    id_provincia smallint,
    telefono character varying(50) DEFAULT ''::character varying NOT NULL,
    telefono_movil character varying(50) DEFAULT ''::character varying NOT NULL,
    responsable character varying(100) DEFAULT ''::character varying NOT NULL,
    id_zona integer NOT NULL,
    calle character varying(100) DEFAULT ''::character varying NOT NULL,
    numero character varying(10) DEFAULT ''::character varying NOT NULL,
    entre_calle character varying(100) DEFAULT ''::character varying,
    y_calle character varying(100) DEFAULT ''::character varying,
    barrio character varying(100) DEFAULT ''::character varying,
    km character varying(10) DEFAULT ''::character varying,
    manzana character varying(10) DEFAULT ''::character varying,
    sector character varying(10) DEFAULT ''::character varying,
    monoblock_torre character varying(10) DEFAULT ''::character varying,
    acceso_entrada character varying(10) DEFAULT ''::character varying,
    comentarios character varying(300) DEFAULT ''::character varying,
    latitud numeric DEFAULT 0 NOT NULL,
    longitud numeric DEFAULT 0 NOT NULL,
    geocoding_status numeric DEFAULT 0 NOT NULL
);


ALTER TABLE public.com_locaciones_clientes OWNER TO spi40;

--
-- Name: row_to_array(public.com_locaciones_clientes, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.com_locaciones_clientes, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_cliente::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.descripcion::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.piso::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.departamento::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_pais::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_localidad::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_provincia::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.telefono::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.telefono_movil::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.responsable::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_zona::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.calle::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.numero::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.entre_calle::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.y_calle::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.barrio::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.km::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.manzana::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.sector::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.monoblock_torre::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.acceso_entrada::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.comentarios::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.latitud::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.longitud::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.geocoding_status::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'id_cliente', 'descripcion', 'piso', 'departamento', 'id_pais', 'id_localidad', 'id_provincia', 'telefono', 'telefono_movil', 'responsable', 'id_zona', 'calle', 'numero', 'entre_calle', 'y_calle', 'barrio', 'km', 'manzana', 'sector', 'monoblock_torre', 'acceso_entrada', 'comentarios', 'latitud', 'longitud', 'geocoding_status']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.com_locaciones_clientes, tipo integer) OWNER TO spi40;

--
-- Name: com_locaciones_clientes_packs_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.com_locaciones_clientes_packs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.com_locaciones_clientes_packs_id_seq OWNER TO spi40;

--
-- Name: com_locaciones_clientes_packs; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.com_locaciones_clientes_packs (
    id integer DEFAULT nextval('public.com_locaciones_clientes_packs_id_seq'::regclass) NOT NULL,
    id_locacion_cliente integer NOT NULL,
    id_pack integer,
    estado smallint DEFAULT 0 NOT NULL,
    marcado_cambiar_estado smallint DEFAULT 0 NOT NULL
);


ALTER TABLE public.com_locaciones_clientes_packs OWNER TO spi40;

--
-- Name: row_to_array(public.com_locaciones_clientes_packs, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.com_locaciones_clientes_packs, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_locacion_cliente::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_pack::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.estado::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.marcado_cambiar_estado::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'id_locacion_cliente', 'id_pack', 'estado', 'marcado_cambiar_estado']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.com_locaciones_clientes_packs, tipo integer) OWNER TO spi40;

--
-- Name: com_locaciones_clientes_packs_servicios_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.com_locaciones_clientes_packs_servicios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.com_locaciones_clientes_packs_servicios_id_seq OWNER TO spi40;

--
-- Name: com_locaciones_clientes_packs_servicios; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.com_locaciones_clientes_packs_servicios (
    id integer DEFAULT nextval('public.com_locaciones_clientes_packs_servicios_id_seq'::regclass) NOT NULL,
    id_locacion_cliente_pack integer NOT NULL,
    id_servicio integer NOT NULL,
    estado smallint DEFAULT 0 NOT NULL,
    requisitos_ok smallint DEFAULT 0 NOT NULL,
    fecha_cambio_estado timestamp without time zone DEFAULT now()
);


ALTER TABLE public.com_locaciones_clientes_packs_servicios OWNER TO spi40;

--
-- Name: row_to_array(public.com_locaciones_clientes_packs_servicios, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.com_locaciones_clientes_packs_servicios, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_locacion_cliente_pack::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_servicio::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.estado::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.requisitos_ok::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.fecha_cambio_estado::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'id_locacion_cliente_pack', 'id_servicio', 'estado', 'requisitos_ok', 'fecha_cambio_estado']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.com_locaciones_clientes_packs_servicios, tipo integer) OWNER TO spi40;

--
-- Name: com_localidades_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.com_localidades_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 32767
    CACHE 1;


ALTER TABLE public.com_localidades_id_seq OWNER TO spi40;

--
-- Name: com_localidades; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.com_localidades (
    id integer DEFAULT nextval('public.com_localidades_id_seq'::regclass) NOT NULL,
    nombre character varying(50) NOT NULL,
    id_provincia integer NOT NULL
);


ALTER TABLE public.com_localidades OWNER TO spi40;

--
-- Name: row_to_array(public.com_localidades, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.com_localidades, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.nombre::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_provincia::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'nombre', 'id_provincia']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.com_localidades, tipo integer) OWNER TO spi40;

--
-- Name: com_packs_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.com_packs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.com_packs_id_seq OWNER TO spi40;

--
-- Name: com_packs; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.com_packs (
    id integer DEFAULT nextval('public.com_packs_id_seq'::regclass) NOT NULL,
    descripcion character varying(50) NOT NULL,
    estado smallint DEFAULT 1 NOT NULL,
    de_servicios smallint NOT NULL
);


ALTER TABLE public.com_packs OWNER TO spi40;

--
-- Name: row_to_array(public.com_packs, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.com_packs, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.descripcion::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.estado::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.de_servicios::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'descripcion', 'estado', 'de_servicios']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.com_packs, tipo integer) OWNER TO spi40;

--
-- Name: com_packs_contenido; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.com_packs_contenido (
    id_pack integer NOT NULL,
    id_hijo integer NOT NULL,
    cantidad integer DEFAULT 1 NOT NULL
);


ALTER TABLE public.com_packs_contenido OWNER TO spi40;

--
-- Name: row_to_array(public.com_packs_contenido, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.com_packs_contenido, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id_pack::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_hijo::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.cantidad::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id_pack', 'id_hijo', 'cantidad']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id_pack', 'id_hijo']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1', '2']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.com_packs_contenido, tipo integer) OWNER TO spi40;

--
-- Name: com_paises_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.com_paises_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 32767
    CACHE 1;


ALTER TABLE public.com_paises_id_seq OWNER TO spi40;

--
-- Name: com_paises; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.com_paises (
    id smallint DEFAULT nextval('public.com_paises_id_seq'::regclass) NOT NULL,
    nombre character varying(50) NOT NULL
);


ALTER TABLE public.com_paises OWNER TO spi40;

--
-- Name: row_to_array(public.com_paises, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.com_paises, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.nombre::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'nombre']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.com_paises, tipo integer) OWNER TO spi40;

--
-- Name: com_provincias_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.com_provincias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    MAXVALUE 32767
    CACHE 1;


ALTER TABLE public.com_provincias_id_seq OWNER TO spi40;

--
-- Name: com_provincias; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.com_provincias (
    id smallint DEFAULT nextval('public.com_provincias_id_seq'::regclass) NOT NULL,
    nombre character varying(50) NOT NULL,
    id_pais integer NOT NULL
);


ALTER TABLE public.com_provincias OWNER TO spi40;

--
-- Name: row_to_array(public.com_provincias, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.com_provincias, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.nombre::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_pais::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'nombre', 'id_pais']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.com_provincias, tipo integer) OWNER TO spi40;

--
-- Name: svc_servicios_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.svc_servicios_id_seq
    START WITH 34
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.svc_servicios_id_seq OWNER TO spi40;

--
-- Name: svc_servicios; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_servicios (
    id integer DEFAULT nextval('public.svc_servicios_id_seq'::regclass) NOT NULL,
    nombre character varying(50) NOT NULL,
    descripcion text DEFAULT ''::text,
    id_tipo_servicio integer NOT NULL,
    id_tipo_tecnologia integer NOT NULL,
    esencial smallint DEFAULT 0 NOT NULL,
    id_grupo integer
);


ALTER TABLE public.svc_servicios OWNER TO spi40;

--
-- Name: row_to_array(public.svc_servicios, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.svc_servicios, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.nombre::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.descripcion::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_tipo_servicio::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_tipo_tecnologia::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.esencial::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_grupo::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'nombre', 'descripcion', 'id_tipo_servicio', 'id_tipo_tecnologia', 'esencial', 'id_grupo']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.svc_servicios, tipo integer) OWNER TO spi40;

--
-- Name: svc_servicios_grupos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.svc_servicios_grupos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.svc_servicios_grupos_id_seq OWNER TO spi40;

--
-- Name: svc_servicios_grupos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_servicios_grupos (
    id integer DEFAULT nextval('public.svc_servicios_grupos_id_seq'::regclass) NOT NULL,
    nombre character varying(50) NOT NULL,
    descripcion character varying(50) NOT NULL,
    id_tipo_servicio integer NOT NULL,
    id_tipo_tecnologia integer NOT NULL
);


ALTER TABLE public.svc_servicios_grupos OWNER TO spi40;

--
-- Name: row_to_array(public.svc_servicios_grupos, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.svc_servicios_grupos, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.nombre::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.descripcion::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_tipo_servicio::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_tipo_tecnologia::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'nombre', 'descripcion', 'id_tipo_servicio', 'id_tipo_tecnologia']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.svc_servicios_grupos, tipo integer) OWNER TO spi40;

--
-- Name: svc_servicios_propiedades; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_servicios_propiedades (
    id_locacion_cliente_pack_servicio integer NOT NULL,
    id_propiedad integer NOT NULL,
    valor text DEFAULT ''::text NOT NULL,
    valor_modificado integer
);


ALTER TABLE public.svc_servicios_propiedades OWNER TO spi40;

--
-- Name: row_to_array(public.svc_servicios_propiedades, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.svc_servicios_propiedades, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id_locacion_cliente_pack_servicio::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_propiedad::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.valor::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.valor_modificado::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id_locacion_cliente_pack_servicio', 'id_propiedad', 'valor', 'valor_modificado']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id_locacion_cliente_pack_servicio', 'id_propiedad']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1', '2']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.svc_servicios_propiedades, tipo integer) OWNER TO spi40;

--
-- Name: svc_servicios_propiedades_internas; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_servicios_propiedades_internas (
    id_servicio integer NOT NULL,
    id_propiedad integer NOT NULL,
    valor text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.svc_servicios_propiedades_internas OWNER TO spi40;

--
-- Name: row_to_array(public.svc_servicios_propiedades_internas, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.svc_servicios_propiedades_internas, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id_servicio::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_propiedad::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.valor::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id_servicio', 'id_propiedad', 'valor']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id_servicio', 'id_propiedad']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1', '2']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.svc_servicios_propiedades_internas, tipo integer) OWNER TO spi40;

--
-- Name: tec_dispositivos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_dispositivos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_dispositivos_id_seq OWNER TO spi40;

--
-- Name: tec_dispositivos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_dispositivos (
    id integer DEFAULT nextval('public.tec_dispositivos_id_seq'::regclass) NOT NULL,
    descripcion character varying(50) NOT NULL,
    id_modelo integer NOT NULL,
    es_multiusuario smallint DEFAULT 0 NOT NULL,
    estado smallint DEFAULT 1 NOT NULL,
    fecha_alta timestamp without time zone DEFAULT now()
);


ALTER TABLE public.tec_dispositivos OWNER TO spi40;

--
-- Name: row_to_array(public.tec_dispositivos, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.tec_dispositivos, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.descripcion::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_modelo::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.es_multiusuario::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.estado::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.fecha_alta::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'descripcion', 'id_modelo', 'es_multiusuario', 'estado', 'fecha_alta']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.tec_dispositivos, tipo integer) OWNER TO spi40;

--
-- Name: tec_dispositivos_etiquetas_dispositivos_unico_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_dispositivos_etiquetas_dispositivos_unico_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_dispositivos_etiquetas_dispositivos_unico_seq OWNER TO spi40;

--
-- Name: tec_dispositivos_etiquetas_dispositivos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_dispositivos_etiquetas_dispositivos (
    id_dispositivo integer NOT NULL,
    id_etiqueta integer NOT NULL,
    valor character varying(100),
    unico integer DEFAULT nextval('public.tec_dispositivos_etiquetas_dispositivos_unico_seq'::regclass) NOT NULL
);


ALTER TABLE public.tec_dispositivos_etiquetas_dispositivos OWNER TO spi40;

--
-- Name: row_to_array(public.tec_dispositivos_etiquetas_dispositivos, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.tec_dispositivos_etiquetas_dispositivos, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id_dispositivo::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_etiqueta::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.valor::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.unico::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id_dispositivo', 'id_etiqueta', 'valor', 'unico']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id_dispositivo', 'id_etiqueta']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1', '2']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.tec_dispositivos_etiquetas_dispositivos, tipo integer) OWNER TO spi40;

--
-- Name: tec_dispositivos_interfaces_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_dispositivos_interfaces_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_dispositivos_interfaces_id_seq OWNER TO spi40;

--
-- Name: tec_dispositivos_interfaces; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_dispositivos_interfaces (
    id_dispositivo integer NOT NULL,
    descripcion character varying(80) DEFAULT ''::character varying NOT NULL,
    id integer DEFAULT nextval('public.tec_dispositivos_interfaces_id_seq'::regclass) NOT NULL,
    ifindex bigint NOT NULL,
    estado smallint DEFAULT 0 NOT NULL,
    ifrelated integer,
    ifalias character varying(100) DEFAULT ''::character varying NOT NULL,
    ifadminstatus integer,
    iftype character varying(30) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE public.tec_dispositivos_interfaces OWNER TO spi40;

--
-- Name: row_to_array(public.tec_dispositivos_interfaces, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.tec_dispositivos_interfaces, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id_dispositivo::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.descripcion::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.ifindex::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.estado::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.ifrelated::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.ifalias::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.ifadminstatus::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.iftype::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id_dispositivo', 'descripcion', 'id', 'ifindex', 'estado', 'ifrelated', 'ifalias', 'ifadminstatus', 'iftype']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['3']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.tec_dispositivos_interfaces, tipo integer) OWNER TO spi40;

--
-- Name: tec_dispositivos_interfaces_propiedades; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_dispositivos_interfaces_propiedades (
    id_interface integer NOT NULL,
    id_propiedad_interface integer NOT NULL,
    valor text
);


ALTER TABLE public.tec_dispositivos_interfaces_propiedades OWNER TO spi40;

--
-- Name: row_to_array(public.tec_dispositivos_interfaces_propiedades, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.tec_dispositivos_interfaces_propiedades, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id_interface::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_propiedad_interface::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.valor::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id_interface', 'id_propiedad_interface', 'valor']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id_interface', 'id_propiedad_interface']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1', '2']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.tec_dispositivos_interfaces_propiedades, tipo integer) OWNER TO spi40;

--
-- Name: tec_marcas_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_marcas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_marcas_id_seq OWNER TO spi40;

--
-- Name: tec_marcas; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_marcas (
    id integer DEFAULT nextval('public.tec_marcas_id_seq'::regclass) NOT NULL,
    nombre character varying(50) NOT NULL
);


ALTER TABLE public.tec_marcas OWNER TO spi40;

--
-- Name: row_to_array(public.tec_marcas, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.tec_marcas, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.nombre::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'nombre']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.tec_marcas, tipo integer) OWNER TO spi40;

--
-- Name: tec_modelos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_modelos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_modelos_id_seq OWNER TO spi40;

--
-- Name: tec_modelos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_modelos (
    id integer DEFAULT nextval('public.tec_modelos_id_seq'::regclass) NOT NULL,
    id_marca integer NOT NULL,
    descripcion character varying(100) NOT NULL,
    id_tipo_dispositivo integer NOT NULL
);


ALTER TABLE public.tec_modelos OWNER TO spi40;

--
-- Name: row_to_array(public.tec_modelos, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.tec_modelos, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_marca::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.descripcion::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_tipo_dispositivo::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'id_marca', 'descripcion', 'id_tipo_dispositivo']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.tec_modelos, tipo integer) OWNER TO spi40;

--
-- Name: tec_modelos_etiquetas_dispositivos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_modelos_etiquetas_dispositivos (
    id_modelo integer NOT NULL,
    id_etiqueta integer NOT NULL,
    orden integer NOT NULL
);


ALTER TABLE public.tec_modelos_etiquetas_dispositivos OWNER TO spi40;

--
-- Name: row_to_array(public.tec_modelos_etiquetas_dispositivos, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.tec_modelos_etiquetas_dispositivos, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id_modelo::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_etiqueta::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.orden::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id_modelo', 'id_etiqueta', 'orden']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id_modelo', 'id_etiqueta', 'orden']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1', '2', '3']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.tec_modelos_etiquetas_dispositivos, tipo integer) OWNER TO spi40;

--
-- Name: tec_modelos_propiedades_interfaces; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_modelos_propiedades_interfaces (
    id_modelo integer NOT NULL,
    id_propiedad_interface integer NOT NULL
);


ALTER TABLE public.tec_modelos_propiedades_interfaces OWNER TO spi40;

--
-- Name: row_to_array(public.tec_modelos_propiedades_interfaces, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.tec_modelos_propiedades_interfaces, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id_modelo::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_propiedad_interface::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id_modelo', 'id_propiedad_interface']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id_modelo', 'id_propiedad_interface']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1', '2']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.tec_modelos_propiedades_interfaces, tipo integer) OWNER TO spi40;

--
-- Name: tec_modelos_puertos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_modelos_puertos (
    id_modelo integer NOT NULL,
    id_tipo_puerto integer NOT NULL,
    cantidad smallint DEFAULT 1 NOT NULL
);


ALTER TABLE public.tec_modelos_puertos OWNER TO spi40;

--
-- Name: row_to_array(public.tec_modelos_puertos, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.tec_modelos_puertos, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id_modelo::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_tipo_puerto::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.cantidad::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id_modelo', 'id_tipo_puerto', 'cantidad']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id_modelo', 'id_tipo_puerto']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1', '2']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.tec_modelos_puertos, tipo integer) OWNER TO spi40;

--
-- Name: tec_zonas_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_zonas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_zonas_id_seq OWNER TO spi40;

--
-- Name: tec_zonas; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_zonas (
    id integer DEFAULT nextval('public.tec_zonas_id_seq'::regclass) NOT NULL,
    descripcion character varying(50) NOT NULL,
    id_dispositivo integer
);


ALTER TABLE public.tec_zonas OWNER TO spi40;

--
-- Name: row_to_array(public.tec_zonas, integer); Type: FUNCTION; Schema: auditoria; Owner: spi40
--

CREATE FUNCTION auditoria.row_to_array(public.tec_zonas, tipo integer) RETURNS text[]
    LANGUAGE sql
    AS $_$ SELECT CASE WHEN $2 = 1 /*valores*/ THEN  ARRAY[COALESCE(replace($1.id::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.descripcion::text,'''',''''''),'Valor_Del_Campo_Es_NULL'), COALESCE(replace($1.id_dispositivo::text,'''',''''''),'Valor_Del_Campo_Es_NULL')]  WHEN $2 = 2 /*nombres campos*/ THEN ARRAY['id', 'descripcion', 'id_dispositivo']  WHEN $2 = 3 /*nombre pkeys*/ THEN ARRAY['id']  WHEN $2 = 4 /*orden pkeys*/ THEN ARRAY['1']  ELSE NULL END; $_$;


ALTER FUNCTION auditoria.row_to_array(public.tec_zonas, tipo integer) OWNER TO spi40;

--
-- Name: actualizar_fecha_servicio(); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.actualizar_fecha_servicio() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	IF NEW.estado != OLD.estado THEN
		NEW.fecha_cambio_estado = now();
	END IF;
RETURN new;
END

$$;


ALTER FUNCTION public.actualizar_fecha_servicio() OWNER TO spi40;

--
-- Name: all_words_included(text, text); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.all_words_included(text, text) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
DECLARE
    agujas varchar;
    pajar varchar;
    partes_agujas varchar Array[6];
    cont integer;
BEGIN
/*
  FUNCION QUE RECIBE DOS STRINGS Y CHEQUEA QUE LAS PALABRAS DE 'AGUJAS' ESTEN
  INCLUIDAS EN LAS PALABRAS DE 'PAJAR'.
  FUNCION CASE INSENSITIVE

   EJEMPLOS:
   ---------------------------------------------
   | AGUJAS       | PAJAR          | RESULTADO |
   ---------------------------------------------
   | 'JUAN PEDRO' | 'JUAN PEDRO'   | TRUE      |
   | 'JUAN'       | 'JUANA PEDROS' | TRUE      |
   | 'JUANCITO'   | 'JUAN PEDRO'   | FALSE     |
   | ' '          | null           | FALSE     |
   | null         | ''             | TRUE      |
   ---------------------------------------------
*/
    -- PASA LAS ENTRADAS A MINUSCULAS PARA QUE SEA CASE-INSENSITIVE
    agujas = lower_latin1($1);
    pajar =  lower_latin1($2);

    IF (agujas IS NULL) THEN
        agujas = '';
    END IF;

    IF (pajar IS NULL) THEN
        pajar = '';
    END IF;

    -- SI EL 'PAJAR' ESTA VACIO Y 'AGUJAS' TAMBIEN RETORNA TRUE
    IF (pajar = '' AND agujas = '') THEN
        RETURN true;
    END IF;

    -- SI EL 'PAJAR' ESTA VACIO Y HAY 'AGUJAS' RETORNA FALSE
    IF (pajar = '' AND agujas != '') THEN
        RETURN false;
    END IF;

    -- DIVIDE EN PARTES 'AGUJAS'
    SELECT string_to_array(agujas,' ') INTO partes_agujas;

    cont = 1;
    LOOP -- PARA CADA 'AGUJA' LA BUSCA EN 'PAJAR'
		EXIT WHEN partes_agujas[cont] IS NULL; -- SI YA NO QUEDAN 'AGUJAS' POR BUSCAR EN 'PAJAR', TERMINO.
		IF (POSITION(partes_agujas[cont] IN pajar) = 0) THEN
		    --RAISE NOTICE ' No existe "%" en "%" .', partes_agujas[cont],pajar;
		    RETURN false;
		END IF;
	        cont = cont + 1;
    END LOOP;

    RETURN true;
END
$_$;


ALTER FUNCTION public.all_words_included(text, text) OWNER TO spi40;

--
-- Name: ancestros_operador(integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.ancestros_operador(integer) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $_$
DECLARE
	id_operador ALIAS FOR $1;
	id_padre_operador integer;
	ancestros record;
BEGIN
	-- busco el padre del operador (y si existe el operador!)
	SELECT INTO id_padre_operador
	            id_padre
	       FROM sys_operadores
	      WHERE id = id_operador and
                    id != id_padre;
	IF FOUND THEN
		-- agrego el operador actual
		FOR ancestros IN (SELECT id_operador)  LOOP
			RETURN NEXT ancestros;
		END LOOP;
		-- agrego recursivamente los operadores padres
        -- IF (VERSION DE POSTRGRES > 8.3) THEN
            --return query select id from ancestros_operador(id_padre_operador) AS tabla("id" integer) ;
        -- ELSE
            FOR ancestros IN (select id from ancestros_operador(id_padre_operador) AS tabla("id" integer))  LOOP
                RETURN NEXT ancestros;
            END LOOP;
        -- END IF

	ELSE
		-- agrego el operador actual
		FOR ancestros IN (SELECT id_operador)  LOOP
			RETURN NEXT ancestros;
		END LOOP;
	END IF;

	return;
END;
$_$;


ALTER FUNCTION public.ancestros_operador(integer) OWNER TO spi40;

--
-- Name: array_contains(text[], text[]); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.array_contains(text[], text[]) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
                DECLARE        
                        val_arreglo1 ALIAS FOR $1;
                        val_arreglo2 ALIAS FOR $2;       
                        val_pos1 int;
                        val_pos2 int;

                        val_existe boolean;
                BEGIN



                --raise notice '%  %',val_arreglo1,val_arreglo2;

                        FOR val_pos2 IN 1 .. array_length(val_arreglo2, 1) LOOP
                                val_existe := false;
                                FOR val_pos1 IN 1 .. array_length(val_arreglo1, 1) LOOP				
                                        --raise notice 'a1[%]=%  a2[%]=%',val_pos1,val_arreglo1[val_pos1],val_pos2,val_arreglo2[val_pos2];

                                        IF (val_arreglo2[val_pos2] = val_arreglo1[val_pos1]) THEN				    
                                             val_existe := true;										
                                        END IF;
                                END LOOP;

                                if (not val_existe) THEN                             
                                         --raise notice '**** NO EXISTE!  %=%',val_arreglo1[val_pos1],val_arreglo2[val_pos2];
                                         return false;

                                END IF;
                        END LOOP;

                       -- raise notice ' ***   % - % = %',val_arreglo1,val_arreglo2,val_resultado;               
                        RETURN true;

                END
                $_$;


ALTER FUNCTION public.array_contains(text[], text[]) OWNER TO spi40;

--
-- Name: array_diff(text[], text[]); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.array_diff(text[], text[]) RETURNS text[]
    LANGUAGE plpgsql
    AS $_$
        DECLARE        
                val_arreglo1 ALIAS FOR $1;
                val_arreglo2 ALIAS FOR $2;       
                val_pos1 int;
                val_pos2 int;
                val_resultado text[]; 
                val_existe boolean;
        BEGIN
        
                /* A PARTIR DE LA VERSION 8.2 DE POSTGRES SE PODRIA RESUMIR EL CODIGO DE LA FUNCION DE ESTA FORMA.  
                FOR val_pos IN 1 .. array_length(val_arreglo1, 1) LOOP
                        IF not (val_arreglo2 @> ARRAY[val_arreglo1[val_pos]]) THEN
                                val_resultado := val_resultado || ARRAY[val_arreglo1[val_pos]];
                        END IF;
                END LOOP;
                */

                FOR val_pos1 IN 1 .. array_length(val_arreglo1, 1) LOOP
			val_existe := false;
			FOR val_pos2 IN 1 .. array_length(val_arreglo2, 1) LOOP				
				--raise notice 'a1[%]=%  a2[%]=%',val_pos1,val_arreglo1[val_pos1],val_pos2,val_arreglo2[val_pos2];
				IF (val_arreglo2[val_pos2] = val_arreglo1[val_pos1]) THEN
				     --raise notice '**** EXISTE!  %=%',val_arreglo1[val_pos1],val_arreglo2[val_pos2];
				     val_existe := true;
										
				END IF;
                        END LOOP;
                        if (not val_existe) THEN
                                --raise notice '++++ AGREGO % en (%)',val_arreglo1[val_pos1], val_resultado;
                                if (val_resultado is null) then
                                    val_resultado := array[val_arreglo1[val_pos1]];
                                else
				    val_resultado := val_resultado || val_arreglo1[val_pos1];
				end if;
                        END IF;
                END LOOP;

               -- raise notice ' ***   % - % = %',val_arreglo1,val_arreglo2,val_resultado;               
                RETURN val_resultado;

        END
        $_$;


ALTER FUNCTION public.array_diff(text[], text[]) OWNER TO spi40;

--
-- Name: array_length(anyarray, integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.array_length(anyarray, integer) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
        DECLARE        
                val_arreglo1 ALIAS FOR $1;
                val_dim     ALIAS FOR $2;     
        BEGIN
                -- ATENCION!! ESTA FUNCION ESTA DISPONIBLE NATIVAMENTE DESDE LA VERSION 8.4 DE POSTGRES
                return   array_upper(val_arreglo1, val_dim) - array_lower(val_arreglo1, val_dim) + 1;
        END
        $_$;


ALTER FUNCTION public.array_length(anyarray, integer) OWNER TO spi40;

--
-- Name: auditar_tabla(); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.auditar_tabla() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
        DECLARE          
            val_arreglo_parametros_acceso  text[0];
            val_llave_elemento  text[0];         
            val_valores_campos_NEW text[0];
            val_valores_campos_OLD text[0];
            val_nombres_campos text[0];
            val_orden_pkeys text[0];
            val_cont integer;    
            val_campos record;  
            val_eventos record;
            val_registro record;
            val_id_operador integer;    
            val_operador_ws text;    
            val_ip_origen inet;    
            val_id_entidad integer;    
            val_parametros_acceso text;
            val_tipo_operacion integer;
            val_retorno record;               
            val_id_evento_nuevo integer;   
            val_id_llaves_primarias integer;   
            valor_campo_NEW text;
            valor_campo_OLD text;            
            val_id_registro integer;
            val_llaves_primarias integer[];
        BEGIN
        
            -- Check that the trigger for the logger should be AFTER and FOR EACH ROW
            IF TG_WHEN = 'BEFORE' THEN
                RAISE EXCEPTION 'Trigger for logger should be AFTER';
            END IF;

            IF TG_LEVEL = 'STATEMENT' AND TG_OP <> 'TRUNCATE' THEN
                RAISE EXCEPTION 'Trigger for logger should be FOR EACH ROW';
            END IF;    

            -- leo las variables de sesion
            val_id_operador := valor_variable_de_session('session.id_operador','0');           
            val_ip_origen := valor_variable_de_session('session.ip_origen','127.0.0.1')::inet;
            val_id_entidad := valor_variable_de_session('session.id_entidad','1');
            val_operador_ws := valor_variable_de_session('session.operador_ws','');
            val_parametros_acceso := valor_variable_de_session('session.parametros_acceso','');
          
            -- defino los valores por defecto
            val_tipo_operacion := 0;
            


            -- esta logueando un acceso de operador, no un movimento en tablas
            if (val_parametros_acceso != '') then
                val_retorno := NEW;
                val_tipo_operacion := 999;
            ELSIF (TG_OP = 'INSERT') THEN
                val_tipo_operacion := 1;
                val_retorno := NEW;
                val_valores_campos_NEW := auditoria.row_to_array(NEW,1);
            ELSIF (TG_OP = 'UPDATE') THEN 
                val_valores_campos_NEW := auditoria.row_to_array(NEW,1);
                val_valores_campos_OLD := auditoria.row_to_array(OLD,1);
                -- si cambiaron los campos guardo log    
                IF (val_valores_campos_NEW is distinct from val_valores_campos_OLD) THEN
                    val_tipo_operacion := 2;
                END IF;
                val_retorno := NEW; 
            ELSIF (TG_OP = 'DELETE') THEN
                val_tipo_operacion := 3;      
                val_retorno := OLD;
                val_valores_campos_OLD := auditoria.row_to_array(OLD,1);
            ELSE
                -- NO DEBERIA ENTRAR NUNCA ACA!!!               
                raise exception 'Llamado a trigger con TG_OP no valido!!!';
            END IF;

            
--raise notice 'TG_OP:% ',TG_OP;
--raise notice 'val_retorno:%',val_retorno;
--raise notice 'val_tipo_operacion:%',val_tipo_operacion;


            if (not val_retorno is null and val_tipo_operacion > 0) then
               
                val_nombres_campos :=  auditoria.row_to_array(val_retorno, 2);
                val_orden_pkeys :=  auditoria.row_to_array(val_retorno, 4);

                --raise notice 'val_tipo_operacion %', val_tipo_operacion;
		--raise notice 'NEW %', val_valores_campos_NEW;
                --raise notice 'OLD %', val_valores_campos_OLD;
		--raise notice 'val_nombres_campos:%', val_nombres_campos;
		--raise notice 'val_orden_pkeys:%', val_orden_pkeys;
		--raise notice 'val_parametros_acceso:%', val_parametros_acceso;
            
                SELECT INTO val_eventos
	                    id	                    
	               FROM auditoria.eventos
	              WHERE id_operador = val_id_operador and
                            ip_origen   = val_ip_origen and
                            timestamp   = now() and
                            id_entidad  = val_id_entidad;
	        IF FOUND THEN 
	            val_id_evento_nuevo := val_eventos.id;
                else
                    SELECT INTO val_id_evento_nuevo nextval('auditoria.eventos_id_seq');    
                    insert into auditoria.eventos                
                       values (val_id_evento_nuevo, val_id_operador, val_ip_origen, now(), val_id_entidad );

                    -- si hay operador_ws lo guardo en los parametros de acceso
		    if (val_operador_ws != '') then
			insert into auditoria.parametros_acceso (id_evento, nombre_campo, valor)                
			     values (val_id_evento_nuevo, 'operador_ws', val_operador_ws);
		    end if;
                end if;

                --raise notice 'val_id_evento_nuevo %',val_id_evento_nuevo;
              

                -- si estoy logueando un acceso no tengo que guardar cambios en tablas, solo datos de acceso
                if (val_parametros_acceso != '') then
                    -- guardo los parametros de acceso
                    -- val_parametros_acceso := regexp_replace(val_parametros_acceso, E'\\n+', '');
                    --raise notice 'param acceso (%)', val_parametros_acceso;

                    -- formato del string de parametros   llave1/*separador_llaves*/valor1/*separador_registros*/llave2/*separador_llaves*/valor2
                    -- separo los elemntos del string
                    SELECT string_to_array(val_parametros_acceso,'/*separador_registros*/') INTO val_arreglo_parametros_acceso;

                   --raise notice 'param acceso (%)', val_arreglo_parametros_acceso;

                    val_cont := 1;
                    LOOP EXIT WHEN val_arreglo_parametros_acceso[val_cont] IS NULL; 
                        -- separo la llave del valor
                        SELECT string_to_array(val_arreglo_parametros_acceso[val_cont],'/*separador_llaves*/') INTO val_llave_elemento;
                       --RAISE NOTICE 'evento:%, linea "% => %" .',val_id_evento_nuevo, val_llave_elemento[1], val_llave_elemento[2];
                        -- agrego el parametro de acceso   
                        insert into auditoria.parametros_acceso (id_evento, nombre_campo, valor)                
                             values (val_id_evento_nuevo,  substring(val_llave_elemento[1] from 1 for 60), substring(val_llave_elemento[2] from 1 for 100));                    

                        val_cont = val_cont + 1;
                    END LOOP;
                else

	            -- busco los keys del registro
                    val_cont := 1;
                    LOOP EXIT WHEN val_orden_pkeys[val_cont] IS NULL;
                        val_llaves_primarias[val_cont] := coalesce(val_valores_campos_OLD[val_orden_pkeys[val_cont]::integer], val_valores_campos_NEW[val_orden_pkeys[val_cont]::integer]);                            
                        val_cont := val_cont + 1;
                    end loop;        


		    SELECT INTO val_registro
				    id	                    
			       FROM auditoria.registros_modificados
			      WHERE id_evento = val_id_evento_nuevo and
				    id_tipo_operacion   = val_tipo_operacion and
				    tabla   = TG_RELNAME and
				    llaves_primarias  = val_llaves_primarias;
		    IF FOUND THEN 
			    val_id_registro := val_registro.id;
		    else
			-- creo el registro de cambios
			SELECT INTO  val_id_registro nextval('auditoria.registros_modificados_id_seq');    
			insert into auditoria.registros_modificados                
		             values (val_id_registro, val_id_evento_nuevo, val_tipo_operacion, TG_RELNAME, val_llaves_primarias);
		    end if;
                    
                       
                    -- guardo los campos que cambiaron en la tabla auditada    
                    val_cont := 1;             

                    LOOP EXIT WHEN val_nombres_campos[val_cont] IS NULL;
                        valor_campo_NEW := val_valores_campos_NEW[val_cont];
                        valor_campo_OLD := val_valores_campos_OLD[val_cont];
--raise notice ' ant:%  new:%',valor_campo_OLD,valor_campo_NEW;
/*
			 -- guardo las pkeys                    
                        IF (array_contains(val_nombres_pkeys, array[val_nombres_campos[val_cont]])) THEN
                            insert into auditoria.llaves_primarias  (id_registro, nombre_campo,valor)
                                values (val_id_registro, val_nombres_campos[val_cont], coalesce(valor_campo_OLD, coalesce(valor_campo_NEW,'')) );
                        END IF;
  */                      
                        -- si el campo cambio guardo el cambio    
                        if (valor_campo_NEW is distinct from valor_campo_OLD) then
                            if (valor_campo_OLD IS NULL or valor_campo_OLD = 'Valor_Del_Campo_Es_NULL') then 
                                valor_campo_OLD := NULL;
                            end if;
                            if (valor_campo_NEW IS NULL or valor_campo_NEW = 'Valor_Del_Campo_Es_NULL') then 
                                valor_campo_NEW := NULL;
                            end if;                           

                           -- SELECT INTO val_id_campos_modificados nextval('auditoria.campos_modificados_id_seq');    
                            insert into auditoria.campos_modificados  (id_registro, nombre_campo, valor_anterior, valor_nuevo)       
                                values (val_id_registro, val_nombres_campos[val_cont], valor_campo_OLD, valor_campo_NEW);
                        end if;                           
                        
                        val_cont := val_cont + 1;                 
                    END LOOP;
                end if;     
            end if;
            RETURN val_retorno; -- result is ignored since this is an AFTER trigger
        END;

        $$;


ALTER FUNCTION public.auditar_tabla() OWNER TO spi40;

--
-- Name: bool_to_text(boolean); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.bool_to_text(boolean) RETURNS text
    LANGUAGE sql STRICT
    AS $_$
            select case
                    when $1 then 'true'
                    else 'false'
            end;$_$;


ALTER FUNCTION public.bool_to_text(boolean) OWNER TO spi40;

--
-- Name: calcular_permisos_efectivos(integer, integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.calcular_permisos_efectivos(integer, integer) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_operador ALIAS FOR $1;
        val_id_entidad ALIAS FOR $2;
        permisos_operador RECORD;
        efectivo integer;
        negado integer;
BEGIN
        SELECT INTO permisos_operador * FROM get_permisos_operador(val_id_operador, val_id_entidad);
        negado   := 3 - permisos_operador.negado;
        efectivo := permisos_operador.permitido & negado;
        RETURN efectivo;
END
$_$;


ALTER FUNCTION public.calcular_permisos_efectivos(integer, integer) OWNER TO spi40;

--
-- Name: cantidad_max_pack(integer, integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.cantidad_max_pack(integer, integer) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_pack ALIAS FOR $1;
        val_id_pack_en_creacion ALIAS FOR $2;
	registro RECORD;
        registros_hijos RECORD;
        resultado integer;
        resultado_hijos integer;
BEGIN
	-- cantidades retornadas:  -1=referencia circular, 0=excluyente, 1=unico

	-- busco dentro del pack si hay algun servicio excluyente,
	-- si lo hay el pack es excluyente, si no la cant maxima es 1
	-- si algun descendiente del pack es el pack en creacion hay una referencia circular,
	-- la indico con el resultado -1

	SELECT INTO registro de_servicios FROM com_packs WHERE id = val_id_pack;
        resultado := 1;
	FOR registros_hijos IN (SELECT id_hijo
				  FROM com_packs_contenido
				 WHERE id_pack = val_id_pack
				) LOOP
    	    IF registro.de_servicios = 0 THEN
		-- es un pack de packs
		IF registros_hijos.id_hijo = val_id_pack_en_creacion  THEN
		    resultado := -1;
		ELSE
	    	    resultado_hijos := cantidad_max_pack(registros_hijos.id_hijo,val_id_pack_en_creacion);
		    IF resultado_hijos = 0 and resultado != -1  THEN
	    		resultado := 0;
		    END IF;
		END IF;
	    ELSE
		-- es un pack de servicios
	        resultado_hijos := cantidad_max_servicio(registros_hijos.id_hijo);
		IF resultado_hijos = 0  THEN
	    	    resultado := 0;
		END IF;
    	    END IF;
	END LOOP;

        RETURN resultado;
END
$_$;


ALTER FUNCTION public.cantidad_max_pack(integer, integer) OWNER TO spi40;

--
-- Name: cantidad_max_servicio(integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.cantidad_max_servicio(integer) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_servicio ALIAS FOR $1;
	registro RECORD;
BEGIN
	-- cantidades retornadas:  0=excluyente, 1=unico, 2..99=multiple

	-- asigno la cantidad maxima de servicios asignables al pack
	SELECT INTO registro ts.cantidad_maxima
	                FROM svc_servicios AS ser
			     JOIN svc_tipos_servicios AS ts ON ts.id = ser.id_tipo_servicio
	               WHERE ser.id = val_id_servicio;
        RETURN registro.cantidad_maxima;
END
$_$;


ALTER FUNCTION public.cantidad_max_servicio(integer) OWNER TO spi40;

--
-- Name: cantidad_servicios_de_pack(integer, integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.cantidad_servicios_de_pack(integer, integer) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_pack ALIAS FOR $1;
        val_id_servicio ALIAS FOR $2;
        cantidad integer;
        pack RECORD;
        packs_hijos RECORD;
        servicios_hijos RECORD;

BEGIN
        cantidad := 0;
        --raise notice 'entre pack: % serv: %',val_id_pack,val_id_servicio;
	SELECT INTO pack de_servicios FROM com_packs WHERE id = val_id_pack;
	--raise notice ' servicio de servicios: %', pack.de_servicios;
	FOR packs_hijos IN (SELECT *
			      FROM com_packs_contenido
			     WHERE id_pack = val_id_pack) LOOP
		--raise notice '   packs hijos: % cant: % ', packs_hijos.id_hijo, packs_hijos.cantidad;
		IF (pack.de_servicios = 0) THEN
			cantidad = cantidad + cantidad_servicios_de_pack(packs_hijos.id_hijo, val_id_servicio);
		ELSE
			IF val_id_servicio = packs_hijos.id_hijo THEN
				cantidad = cantidad + packs_hijos.cantidad;
			END IF;
		END IF;
	END LOOP;

        RETURN cantidad;
END
$_$;


ALTER FUNCTION public.cantidad_servicios_de_pack(integer, integer) OWNER TO spi40;

--
-- Name: check_valor_etiqueta(); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.check_valor_etiqueta() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	grupo RECORD;
	tmp RECORD;
BEGIN

	select ted.id_grupo_etiqueta as id, tge.descripcion as descripcion into grupo from tec_etiquetas_dispositivos ted, tec_grupos_etiquetas tge where ted.id = NEW.id_etiqueta and ted.id_grupo_etiqueta = tge.id;

	if (grupo.id <> 0) then

		select into tmp
				id_etiqueta
			 from
				tec_dispositivos_etiquetas_dispositivos
			 where
				valor = NEW.valor and unico = grupo.id;

		if found then

			RAISE EXCEPTION 'Etiqueta de valor unico (grupo: %)', grupo.descripcion;

		end if;

	end if;

	NEW.unico := grupo.id;

	return NEW;

END
$$;


ALTER FUNCTION public.check_valor_etiqueta() OWNER TO spi40;

--
-- Name: chequear_servidor_grupo(); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.chequear_servidor_grupo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
        DECLARE
                tmp RECORD;
        BEGIN

            SELECT id,
                   descripcion,
                   es_grupo
              INTO tmp 
              FROM cfg_servidores_spi 
             WHERE id = NEW.id_servidor;

            IF (tmp.es_grupo) THEN		
                RAISE EXCEPTION 'El objeto "%" con id % es un grupo, no un servidor!', tmp.descripcion, tmp.id;
            ELSE	
                SELECT id,
                       descripcion,
                       es_grupo
                  INTO tmp 
                  FROM cfg_servidores_spi 
                 WHERE id = NEW.id_grupo;
                 IF (not tmp.es_grupo) THEN		
                    RAISE EXCEPTION 'El objeto "%" con id % es un servidor, no un grupo!', tmp.descripcion, tmp.id;
                 end IF;
            end IF;

            return NEW;

        END
        $$;


ALTER FUNCTION public.chequear_servidor_grupo() OWNER TO spi40;

--
-- Name: crear_dependencias_idioma(); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.crear_dependencias_idioma() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	registro_tmp record;
BEGIN

   -- regenero el idioma de las entidades (lang_cfg_configuraciones)
	FOR registro_tmp IN (SELECT id_configuracion,
	                            descripcion
			       FROM lang_cfg_configuraciones
			      WHERE id_idioma = 1 AND
			            id_configuracion NOT IN (SELECT id_configuracion
			                                       FROM lang_cfg_configuraciones
			                                      WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_cfg_configuraciones (id_configuracion,id_idioma,descripcion)
		     VALUES (registro_tmp.id_configuracion, NEW.id, registro_tmp.descripcion || '_' || NEW.abreviatura);
	END LOOP;

   -- regenero el idioma de las entidades (lang_cfg_grupos_configuraciones)
	FOR registro_tmp IN (SELECT id_grupo,
	                            descripcion
			       FROM lang_cfg_grupos_configuraciones
			      WHERE id_idioma = 1 AND
			            id_grupo NOT IN (SELECT id_grupo
			                               FROM lang_cfg_grupos_configuraciones
			                              WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_cfg_grupos_configuraciones (id_grupo,id_idioma,descripcion)
		     VALUES (registro_tmp.id_grupo, NEW.id, registro_tmp.descripcion || '_' || NEW.abreviatura);
	END LOOP;

    -- regenero el idioma de las dependencias (lang_svc_dependencias)
	FOR registro_tmp IN (SELECT id_dependencia,
	                            descripcion,
	                            descripcion_larga
			       FROM lang_svc_dependencias
			      WHERE id_idioma = 1 AND
			            id_dependencia NOT IN (SELECT id_dependencia
			                                     FROM lang_svc_dependencias
			                                    WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_svc_dependencias (id_dependencia,id_idioma,descripcion,descripcion_larga)
		     VALUES (registro_tmp.id_dependencia, NEW.id, registro_tmp.descripcion || '_' || NEW.abreviatura, registro_tmp.descripcion_larga || '_' || NEW.abreviatura);
	END LOOP;

    -- regenero el idioma de las propiedades (lang_svc_propiedades)
	FOR registro_tmp IN (SELECT id_propiedad,
	                            descripcion
			       FROM lang_svc_propiedades
			      WHERE id_idioma = 1 AND
			            id_propiedad NOT IN (SELECT id_propiedad
			                                   FROM lang_svc_propiedades
			                                  WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_svc_propiedades (id_propiedad,id_idioma,descripcion)
		     VALUES (registro_tmp.id_propiedad, NEW.id, registro_tmp.descripcion || '_' || NEW.abreviatura);
	END LOOP;

    -- regenero el idioma de los requisitos (lang_svc_requisitos)
	FOR registro_tmp IN (SELECT id_requisito,
	                            descripcion,
	                            descripcion_larga
			       FROM lang_svc_requisitos
			      WHERE id_idioma = 1 AND
			            id_requisito NOT IN (SELECT id_requisito
			                                   FROM lang_svc_requisitos
			                                  WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_svc_requisitos (id_requisito,id_idioma,descripcion,descripcion_larga)
		     VALUES (registro_tmp.id_requisito, NEW.id, registro_tmp.descripcion || '_' || NEW.abreviatura, registro_tmp.descripcion_larga || '_' || NEW.abreviatura);
	END LOOP;

    -- regenero el idioma de los tipos de servicios (lang_svc_tipos_servicios)
	FOR registro_tmp IN (SELECT id_tipo_servicio,
	                            descripcion
			       FROM lang_svc_tipos_servicios
			      WHERE id_idioma = 1 AND
			            id_tipo_servicio NOT IN (SELECT id_tipo_servicio
			                                       FROM lang_svc_tipos_servicios
			                                      WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_svc_tipos_servicios (id_tipo_servicio,id_idioma,descripcion)
		     VALUES (registro_tmp.id_tipo_servicio, NEW.id, registro_tmp.descripcion || '_' || NEW.abreviatura);
	END LOOP;

    -- regenero el idioma de los abns (lang_sys_abns)
	FOR registro_tmp IN (SELECT id_abn,
				    nombre,
	                            descripcion
			       FROM lang_sys_abns
			      WHERE id_idioma = 1 AND
			            id_abn NOT IN (SELECT id_abn
			                                FROM lang_sys_abns
			                               WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_sys_abns (id_abn,id_idioma,nombre,descripcion)
		     VALUES (registro_tmp.id_abn, NEW.id, registro_tmp.nombre || '_' || NEW.abreviatura, registro_tmp.descripcion || '_' || NEW.abreviatura);
	END LOOP;

     -- regenero el idioma de las entidades (lang_sys_entidades)
	FOR registro_tmp IN (SELECT id_entidad,
	                            descripcion
			       FROM lang_sys_entidades
			      WHERE id_idioma = 1 AND
			            id_entidad NOT IN (SELECT id_entidad
			                                 FROM lang_sys_entidades
			                                WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_sys_entidades (id_entidad,id_idioma,descripcion)
		     VALUES (registro_tmp.id_entidad, NEW.id, registro_tmp.descripcion || '_' || NEW.abreviatura);
	END LOOP;

   -- regenero el idioma de los estados (lang_sys_estados)
	FOR registro_tmp IN (SELECT id_tipo_estado,
				    id_estado,
	                            descripcion
			       FROM lang_sys_estados
			      WHERE id_idioma = 1 AND
			            id_tipo_estado NOT IN (SELECT id_tipo_estado
			                                     FROM lang_sys_estados
			                                    WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_sys_estados (id_tipo_estado, id_estado, id_idioma, descripcion)
		     VALUES (registro_tmp.id_tipo_estado, registro_tmp.id_estado, NEW.id, registro_tmp.descripcion || '_' || NEW.abreviatura);
	END LOOP;


    -- regenero el idioma de los listados (lang_sys_listados)
	FOR registro_tmp IN (SELECT id_listado,
				    columnas,
	                            descripcion,
	                            orientacion_papel
			       FROM lang_sys_listados
			      WHERE id_idioma = 1 AND
			            id_listado NOT IN (SELECT id_listado
			                                 FROM lang_sys_listados
			                                WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_sys_listados (id_listado, id_idioma, columnas, descripcion, orientacion_papel)
		     VALUES (registro_tmp.id_listado, NEW.id, registro_tmp.columnas, registro_tmp.descripcion || '_' || NEW.abreviatura, registro_tmp.orientacion_papel);
	END LOOP;

    -- regenero el idioma de los plugins (lang_sys_plugins)
	FOR registro_tmp IN (SELECT id_plugin,
	                            nombre,
	                            descripcion
			       FROM lang_sys_plugins
			      WHERE id_idioma = 1 AND
			            id_plugin NOT IN (SELECT id_plugin
			                                FROM lang_sys_plugins
			                               WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_sys_plugins (id_plugin, id_idioma, nombre, descripcion)
		     VALUES (registro_tmp.id_plugin, NEW.id, registro_tmp.nombre, registro_tmp.descripcion || '_' || NEW.abreviatura);
	END LOOP;


    -- regenero el idioma de los tipos de eventos (lang_sys_tipos_eventos)
	FOR registro_tmp IN (SELECT id_tipo_evento,
	                            descripcion
			       FROM lang_sys_tipos_eventos
			      WHERE id_idioma = 1 AND
			            id_tipo_evento NOT IN (SELECT id_tipo_evento
			                                     FROM lang_sys_tipos_eventos
			                                    WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_sys_tipos_eventos (id_tipo_evento, id_idioma, descripcion)
		     VALUES (registro_tmp.id_tipo_evento, NEW.id, registro_tmp.descripcion || '_' || NEW.abreviatura);
	END LOOP;

    -- regenero el idioma de las propiedades de dispositivos (lang_tec_propiedades_dispositivos)
	FOR registro_tmp IN (SELECT id_propiedad_dispositivo,
	                            descripcion
			       FROM lang_tec_propiedades_dispositivos
			      WHERE id_idioma = 1 AND
			            id_propiedad_dispositivo NOT IN (SELECT id_propiedad_dispositivo
			                                         FROM lang_tec_propiedades_dispositivos
			                                        WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_tec_propiedades_dispositivos (id_propiedad_dispositivo,id_idioma,descripcion)
		     VALUES (registro_tmp.id_propiedad_dispositivo, NEW.id, registro_tmp.descripcion || '_' || NEW.abreviatura);
	END LOOP;

    -- regenero el idioma de las propiedades de interfaces (lang_tec_propiedades_interfaces)

	FOR registro_tmp IN (SELECT id_propiedad_interface,
	                            descripcion,
	                            descripcion_larga
			       FROM lang_tec_propiedades_interfaces
			      WHERE id_idioma = 1 AND
			            id_propiedad_interface NOT IN (SELECT id_propiedad_interface
			                                             FROM lang_tec_propiedades_interfaces
			                                            WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_tec_propiedades_interfaces (id_propiedad_interface,id_idioma,descripcion,descripcion_larga)
		     VALUES (registro_tmp.id_propiedad_interface, NEW.id, registro_tmp.descripcion || '_' || NEW.abreviatura, registro_tmp.descripcion_larga || '_' || NEW.abreviatura);
	END LOOP;

    -- regenero el idioma de los tipos de tecnologias (lang_tec_tipos_tecnologias)
	FOR registro_tmp IN (SELECT id_tipo_tecnologia,
	                            descripcion
			       FROM lang_tec_tipos_tecnologias
			      WHERE id_idioma = 1 AND
			            id_tipo_tecnologia NOT IN (SELECT id_tipo_tecnologia
			                                         FROM lang_tec_tipos_tecnologias
			                                        WHERE id_idioma = NEW.id)
		  	   ORDER BY id_idioma) LOOP
		INSERT INTO lang_tec_tipos_tecnologias (id_tipo_tecnologia,id_idioma,descripcion)
		     VALUES (registro_tmp.id_tipo_tecnologia, NEW.id, registro_tmp.descripcion || '_' || NEW.abreviatura);
	END LOOP;



	RETURN NEW;
END
$$;


ALTER FUNCTION public.crear_dependencias_idioma() OWNER TO spi40;

--
-- Name: descendientes_operadores(integer[], integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.descendientes_operadores(integer[], integer) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $_$
DECLARE
	operadores ALIAS FOR $1;
	nivel_indentacion ALIAS FOR $2;
	nivel_indentacion_siguiente integer;
	indentacion text;
	hijos_operador record;
	operador_actual record;
	hijos record;
	cont integer;
BEGIN
	-- si mando indentacion = -1 es que no quiere indentar
	IF (nivel_indentacion != -1)THEN
		indentacion := repeat('&nbsp;', nivel_indentacion*5);
		nivel_indentacion_siguiente := nivel_indentacion + 1;
	ELSE
		indentacion := '';
		nivel_indentacion_siguiente := nivel_indentacion;
	END IF;
	cont = 1;
	LOOP -- para cada operador busco sus hijos
		EXIT WHEN operadores[cont] IS NULL; -- SI YA NO QUEDAN 'operadores' POR BUSCAR, TERMINO.

		SELECT INTO operador_actual
		            nombre
		       FROM sys_operadores
	              WHERE id = operadores[cont];
		IF FOUND THEN
			-- agrego el operador actual
			FOR hijos IN (SELECT operadores[cont] as id, (indentacion || operador_actual.nombre)::text as nombre)  LOOP
				RETURN NEXT hijos;
			END LOOP;
			FOR hijos_operador IN (SELECT id
                                     FROM sys_operadores
                                    WHERE id_padre = operadores[cont] and
                                          id != id_padre
                                 ORDER BY nombre) LOOP
				-- agrego recursivamente los operadores hijos
                -- IF (VERSION DE POSTRGRES > 8.3) THEN
                    --return query select id,nombre from descendientes_operadores(ARRAY[hijos_operador.id], nivel_indentacion_siguiente) AS tabla("id" integer, "nombre" text);
                -- ELSE
                    FOR hijos IN (select id,nombre from descendientes_operadores(ARRAY[hijos_operador.id], nivel_indentacion_siguiente) AS tabla("id" integer, "nombre" text))  LOOP
                        RETURN NEXT hijos;
                    END LOOP;
                -- END IF

			END LOOP;
			cont = cont + 1;

		END IF;

	END LOOP;

	return;
END;
$_$;


ALTER FUNCTION public.descendientes_operadores(integer[], integer) OWNER TO spi40;

--
-- Name: domicilio_locacion(integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.domicilio_locacion(integer) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
    id_locacion ALIAS FOR $1;
    registro record;
    id_idioma_default integer;
BEGIN
	SELECT INTO id_idioma_default id
	       FROM sys_idiomas
	 WHERE abreviatura = (SELECT valor
				            FROM cfg_configuraciones
				           WHERE id = 5);

	SELECT INTO registro  calle || ' ' || numero ||
		CASE WHEN piso != '' THEN
			(SELECT descripcion
			   FROM lang_sys_estados
			  WHERE id_tipo_estado=5 AND id_estado = 1 AND id_idioma=id_idioma_default) || piso ELSE ''
		END ||
		CASE WHEN departamento != '' THEN
			(SELECT descripcion
			   FROM lang_sys_estados
			  WHERE id_tipo_estado=5 AND id_estado = 0 AND id_idioma=id_idioma_default) || departamento ELSE ''
		END ||
		CASE WHEN acceso_entrada != '' THEN
			(SELECT descripcion
			   FROM lang_sys_estados
			  WHERE id_tipo_estado=5 AND id_estado = 2 AND id_idioma=id_idioma_default) || acceso_entrada ELSE ''
		END ||
		CASE WHEN monoblock_torre != '' THEN
			(SELECT descripcion
			   FROM lang_sys_estados
			  WHERE id_tipo_estado=5 AND id_estado = 3 AND id_idioma=id_idioma_default) || monoblock_torre ELSE ''
		END ||
		CASE WHEN manzana != '' THEN
			(SELECT descripcion
			   FROM lang_sys_estados
			  WHERE id_tipo_estado=5 AND id_estado = 4 AND id_idioma=id_idioma_default) || manzana ELSE ''
		END ||
		CASE WHEN sector != '' THEN
			(SELECT descripcion
			   FROM lang_sys_estados
			  WHERE id_tipo_estado=5 AND id_estado = 5 AND id_idioma=id_idioma_default) || sector ELSE ''
		END ||
		CASE WHEN entre_calle != '' THEN
			(SELECT descripcion
			   FROM lang_sys_estados
			  WHERE id_tipo_estado=5 AND id_estado = 6 AND id_idioma=id_idioma_default) || entre_calle ELSE ''
		END ||
		CASE WHEN y_calle != '' THEN
			(SELECT descripcion
			   FROM lang_sys_estados
			  WHERE id_tipo_estado=5 AND id_estado = 7 AND id_idioma=id_idioma_default) || y_calle ELSE ''
		END ||
		CASE WHEN barrio != '' THEN
			(SELECT descripcion
			   FROM lang_sys_estados
			  WHERE id_tipo_estado=5 AND id_estado = 8 AND id_idioma=id_idioma_default) || barrio ELSE ''
		END ||
		CASE WHEN km != '' THEN
			(SELECT descripcion
			   FROM lang_sys_estados
			  WHERE id_tipo_estado=5 AND id_estado = 9 AND id_idioma=id_idioma_default) || km  ELSE ''
		END ||
		CASE WHEN comentarios != '' THEN
			(SELECT descripcion
			   FROM lang_sys_estados
			  WHERE id_tipo_estado=5 AND id_estado = 10 AND id_idioma=id_idioma_default) || comentarios ELSE ''
		END as domicilio_completo
	FROM com_locaciones_clientes
   WHERE id = id_locacion;

    IF FOUND THEN
        RETURN registro.domicilio_completo;
    ELSE
        RETURN '';
    END IF;
END
$_$;


ALTER FUNCTION public.domicilio_locacion(integer) OWNER TO spi40;

--
-- Name: espacio(); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.espacio() RETURNS text
    LANGUAGE plpgsql
    AS $$                
        BEGIN	
                return ' ';--retorna un espacio, se usa cuando las comillas simples me dan error
        END
        $$;


ALTER FUNCTION public.espacio() OWNER TO spi40;

--
-- Name: estado_servicio(integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.estado_servicio(integer) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_loc_cli_pack_sev ALIAS FOR $1;
        estados RECORD;
        resultado integer;
BEGIN
/* Funcion que retorna el estado real de un servicio dado (dependiente tambien del estado del pack).

pack  serv  res |    pack      servicio   resultado
----------------|------------------------------------------
 0     0     1  | En Proceso  Automatico   Activo
 0     1     1  | En Proceso  Activo       Activo
 0     2     2  | En Proceso  Suspendido   Suspendido
 0     3     3  | En Proceso  Bajado       Bajado
 1     0     1  | Activo      Automatico   Activo
 1     1     1  | Activo      Activo       Activo
 1     2     2  | Activo      Suspendido   Suspendido
 1     3     3  | Activo      Bajado       Bajado
 2     0     2  | Suspendido  Automatico   Suspendido
 2     1     1  | Suspendido  Activo       Activo
 2     2     2  | Suspendido  Suspendido   Suspendido
 2     3     3  | Suspendido  Bajado       Bajado


NOTA: si el id de servicio no existe se retornara el estado ACTIVO (1),
----  esto es por si hay algun servicio definido fuera de las tablas normales de servicios

*/
    SELECT INTO estados lcps.estado as estado_servicio,
                        lcp.estado as estado_pack
      FROM com_locaciones_clientes_packs_servicios as lcps
           JOIN com_locaciones_clientes_packs as lcp on lcp.id = lcps.id_locacion_cliente_pack
     WHERE lcps.id = val_id_loc_cli_pack_sev;

     IF NOT FOUND THEN
         resultado := 1;
     ELSE
         IF (estados.estado_pack < 2) THEN -- en proceso o activo
             IF (estados.estado_servicio < 2) THEN
                 resultado := 1;
             ELSE
                 resultado := estados.estado_servicio;
             END IF;
         ELSIF (estados.estado_pack > 1) THEN -- suspendido o bajado
             IF (estados.estado_servicio = 0 ) THEN
                 resultado := 2;
             ELSE
                 resultado := estados.estado_servicio;
             END IF;

         END IF;
     END IF;
--raise notice 'id % estado_pack:%  estado_servicio:%  resultado:%',val_id_loc_cli_pack_sev,estados.estado_pack ,estados.estado_servicio,resultado;
     RETURN resultado;
END
$_$;


ALTER FUNCTION public.estado_servicio(integer) OWNER TO spi40;

--
-- Name: geo_distance(double precision, double precision, double precision, double precision); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.geo_distance(_lat1 double precision, _lng1 double precision, _lat2 double precision, _lng2 double precision) RETURNS double precision
    LANGUAGE plpgsql
    AS $$
        DECLARE
            theta float8;
            dist float8;
            pi80 float8;
            dlat float8;
            dlng float8;
            lat1 float8;
            lng1 float8;
            lat2 float8;
            lng2 float8;
            r float8;
            a float8;
            c float8;
        BEGIN

            pi80 := pi() / 180;
            lat1 := _lat1 * pi80;
            lng1 := _lng1 * pi80;
            lat2 := _lat2 * pi80;
            lng2 := _lng2 * pi80;

            r = 6372.797; -- mean radius of Earth in km
            dlat = lat2 - lat1;
            dlng = lng2 - lng1;
            a = sin(dlat / 2) * sin(dlat / 2) + cos(lat1) * cos(lat2) * sin(dlng / 2) * sin(dlng / 2);
            c = 2 * atan2(sqrt(a), sqrt(1 - a));

            -- Distance in metros
            return r * c * 1000;

        END;

        $$;


ALTER FUNCTION public.geo_distance(_lat1 double precision, _lng1 double precision, _lat2 double precision, _lng2 double precision) OWNER TO spi40;

--
-- Name: get_permisos_entidad(integer, integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.get_permisos_entidad(integer, integer) RETURNS public.tipo_permisos
    LANGUAGE plpgsql
    AS $_$
                DECLARE
                        var_id_operador ALIAS FOR $1;
                        var_id_entidad ALIAS FOR $2;
                        var_id_padre_entidad_permisos RECORD;
                        var_permisos_entidad tipo_permisos;
                        var_permisos_operador_entidad_padre tipo_permisos;
                        var_tmp_permisos_entidad tipo_permisos;
                BEGIN

                        var_permisos_entidad := (0,0);

                        -- busco los permisos y el padre de la entidad (y si existe la entidad!)
                        SELECT INTO var_id_padre_entidad_permisos
                                    ent.id_padre,
                                    COALESCE(per.permitido,0) AS permitido,
                                    COALESCE(per.negado,0) AS negado
                               FROM sys_entidades AS ent
                                    LEFT JOIN sys_permisos AS per ON per.id_entidad = ent.id AND
                                         per.id_operador=var_id_operador
                              WHERE id = var_id_entidad;
                        IF FOUND THEN

                                var_permisos_operador_entidad_padre := (0,0);
                                -- si tiene padre calculo sus permisos (los del padre) con el operador
                                IF var_id_padre_entidad_permisos.id_padre != var_id_entidad THEN
                                        SELECT INTO var_permisos_operador_entidad_padre
                                                    permitido, negado
                                               FROM get_permisos_entidad(var_id_operador, var_id_padre_entidad_permisos.id_padre);
                                END IF;

                                -- resto permitidos actuales a los negados heredados
                                var_tmp_permisos_entidad=(var_id_padre_entidad_permisos.permitido,var_id_padre_entidad_permisos.negado);
                                var_permisos_entidad := restar_permisos_permitidos_a_negados_padres(var_tmp_permisos_entidad, var_permisos_operador_entidad_padre);

                        END IF;

                        RETURN var_permisos_entidad;
                END;
                $_$;


ALTER FUNCTION public.get_permisos_entidad(integer, integer) OWNER TO spi40;

--
-- Name: get_permisos_operador(integer, integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.get_permisos_operador(integer, integer) RETURNS public.tipo_permisos
    LANGUAGE plpgsql
    AS $_$
                DECLARE
                        var_id_operador ALIAS FOR $1;
                        var_id_entidad ALIAS FOR $2;
                        var_id_padre_operador integer;
                        var_permisos_operador tipo_permisos;
                        var_permisos_operador_padre_entidad tipo_permisos;
                BEGIN
                        var_permisos_operador := (0,0);

                        -- busco el padre del operador (y si existe el operador!)
                        SELECT INTO var_id_padre_operador
                                    id_padre
                               FROM sys_operadores
                              WHERE id = var_id_operador AND 
                                    estado = 0;
                        IF FOUND THEN

                                var_permisos_operador_padre_entidad := (0,0);
                                -- si tiene padre calculo sus permisos (los del padre) con la entidad
                                IF var_id_padre_operador != var_id_operador THEN
                                        SELECT INTO var_permisos_operador_padre_entidad
                                                    permitido, negado
                                               FROM get_permisos_operador(var_id_padre_operador, var_id_entidad);
                                END IF;
                                -- calculo los permisos del operador con la entidad
                                var_permisos_operador := get_permisos_entidad(var_id_operador, var_id_entidad);

                                -- resto permitidos actuales a los negados heredados
                                var_permisos_operador := restar_permisos_permitidos_a_negados_padres(var_permisos_operador, var_permisos_operador_padre_entidad);
                        END IF;
                        RETURN var_permisos_operador;
                END;
                $_$;


ALTER FUNCTION public.get_permisos_operador(integer, integer) OWNER TO spi40;

--
-- Name: ids_packs_padres(integer, integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.ids_packs_padres(integer, integer) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_pack ALIAS FOR $1;
        val_es_servicio ALIAS FOR $2;
        registros_padres RECORD;
        resultado text;
        resultado_padres text;
BEGIN
	-- retorna los packs que contienen al pack (o servicio) pasado como parametro

	resultado := '';

	FOR registros_padres IN (SELECT con.id_pack
				   FROM com_packs_contenido AS con
				        JOIN com_packs AS pck ON pck.id = con.id_pack
				  WHERE con.id_hijo = val_id_pack AND
				        pck.de_servicios = val_es_servicio
				) LOOP


		IF resultado != '' THEN
			resultado := resultado || ',' || registros_padres.id_pack;
		ELSE
			resultado := registros_padres.id_pack;
		END IF;

		resultado_padres := ids_packs_padres( registros_padres.id_pack,0);
		IF resultado_padres != '' THEN
			resultado := resultado || ',' || resultado_padres;
		END IF;

	END LOOP;

        RETURN resultado;
END
$_$;


ALTER FUNCTION public.ids_packs_padres(integer, integer) OWNER TO spi40;

--
-- Name: ids_servicios_pack(integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.ids_servicios_pack(integer) RETURNS text
    LANGUAGE plpgsql
    AS $_$
        DECLARE
                val_id_pack ALIAS FOR $1;
                registro RECORD;
                registros_hijos RECORD;
                resultado text;
                resultado_hijos text;
        BEGIN

                resultado := '';
                SELECT INTO registro de_servicios FROM com_packs WHERE id = val_id_pack;
                FOR registros_hijos IN (SELECT id_hijo
                                          FROM com_packs_contenido
                                         WHERE id_pack = val_id_pack
                                        ) LOOP
                    IF registro.de_servicios = 0 THEN
                        -- es un pack de packs, busco dentro
                        resultado_hijos := ids_servicios_pack(registros_hijos.id_hijo);	  
                        if resultado_hijos != '' then -- tiene servicios hijos, los agrego
                                if resultado != '' then
                                    resultado := resultado || ',' || resultado_hijos;
                                ELSE
                                    resultado := resultado_hijos;
                                end if;                      
                        end if;
                    ELSE
                        -- es un pack de servicios
                        if resultado != '' then
                            resultado := resultado || ',' || registros_hijos.id_hijo;
                        ELSE
                            resultado := registros_hijos.id_hijo;
                        end if;
                    END IF;
                END LOOP;

                RETURN resultado;
        END
        $_$;


ALTER FUNCTION public.ids_servicios_pack(integer) OWNER TO spi40;

--
-- Name: ids_servicios_pack(text); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.ids_servicios_pack(text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_ids_packs ALIAS FOR $1;
        resultado text;
        resultado_pack text;
        arreglo_ids_packs integer Array[6];
        pos int;
BEGIN
        resultado := '';
        --RAISE NOTICE 'packs = %', val_ids_packs;

	SELECT string_to_array(val_ids_packs,',') INTO arreglo_ids_packs ;

	pos = 1;
	LOOP EXIT WHEN arreglo_ids_packs[pos] IS NULL;
		--RAISE NOTICE 'id=%', arreglo_ids_packs[pos];
		resultado_pack := ids_servicios_pack(arreglo_ids_packs[pos]);
		IF (resultado != '' AND resultado_pack != '') THEN
	    	    resultado := resultado || ',' || resultado_pack;
		ELSE
	    	    resultado :=  resultado || resultado_pack;
		END IF;
		pos = pos + 1;
	END LOOP;

        RETURN resultado;
END
$_$;


ALTER FUNCTION public.ids_servicios_pack(text) OWNER TO spi40;

--
-- Name: ip2long(text); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.ip2long(text) RETURNS bigint
    LANGUAGE plpgsql
    AS $_$
        DECLARE	
                val_ip ALIAS FOR $1;
                val_resultado bigint;
                val_ip1 bigint;
                val_ip2 bigint;
                val_ip3 bigint;
                val_ip4 bigint;
        BEGIN	


                -- el nombre deberia ser ip2bigint pero se llama ip2long para que sea consistente con la funcion equivalente de php

                val_resultado := 0;

                if (length(replace(val_ip, '.', '')) + 3) =  length(val_ip) and -- tiene tres puntos
                   is_numeric(replace(val_ip, '.', ''))  then                   -- solo numeros

                        val_ip1 := split_part(val_ip,'.', 1);	
                        val_ip2 := split_part(val_ip,'.', 2);
                        val_ip3 := split_part(val_ip,'.', 3);
                        val_ip4 := split_part(val_ip,'.', 4);

                        if val_ip1 >= 0 and val_ip2 >= 0 and val_ip3 >= 0 and val_ip4 >= 0  and      --numero mayores o iguales a cero
                           val_ip1 < 256 and val_ip2 < 256 and val_ip3 < 256 and val_ip4 < 256  then -- numeros menores a 256
                                val_resultado := ((((val_ip1*256) + val_ip2) *256 + val_ip3)*256 + val_ip4);			
                        end if; 	
                end if;

                return val_resultado;
        END
        $_$;


ALTER FUNCTION public.ip2long(text) OWNER TO spi40;

--
-- Name: is_numeric(text); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.is_numeric(text) RETURNS boolean
    LANGUAGE sql
    AS $_$
    SELECT $1 ~ '^[0-9]+$'
$_$;


ALTER FUNCTION public.is_numeric(text) OWNER TO spi40;

--
-- Name: long2ip(bigint); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.long2ip(bigint) RETURNS text
    LANGUAGE plpgsql
    AS $_$
        DECLARE
                val_numero ALIAS FOR $1;	
                val_numero_tmp bigint;	
                val_resultado text;
                val_posicion bigint;
        BEGIN	

                -- el nombre deberia ser bigint2ip pero se llama long2ip para que sea consistente con la funcion equivalente de php

                val_resultado := '';

                if (val_numero >= 0 and val_numero <= 4294967295) then

                        val_posicion := 3;

                        val_numero_tmp := val_numero;

                        WHILE val_posicion >= 0  LOOP
                            val_resultado := val_resultado || floor(val_numero_tmp / (256 ^ val_posicion))::text;
                            val_numero_tmp := val_numero_tmp - floor(val_numero_tmp / (256 ^ val_posicion)) * (256 ^ val_posicion);
                            val_posicion := val_posicion - 1;	

                            if val_posicion >= 0 then
                                val_resultado := val_resultado || '.';
                            end if;	
                        END LOOP;
                end if;

                return val_resultado;
        END
        $_$;


ALTER FUNCTION public.long2ip(bigint) OWNER TO spi40;

--
-- Name: lower_latin1(text); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.lower_latin1(text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
        texto ALIAS FOR $1;
BEGIN
    RETURN lower(translate(texto, 'ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝ', 'àáâãäåæçèéêëìíîïðñòóôõöøùúûüý'));
END
$_$;


ALTER FUNCTION public.lower_latin1(text) OWNER TO spi40;

--
-- Name: normalizar_mac(text); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.normalizar_mac(text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
        mac ALIAS FOR $1;
BEGIN
    RETURN upper(substring(mac from 0 for 3) || ':' ||substring(mac from 3 for 2) || ':' ||substring(mac from 5 for 2) || ':' ||substring(mac from 7 for 2) || ':' ||substring(mac from 9 for 2) || ':' ||substring(mac from 11 for 2) );
END
$_$;


ALTER FUNCTION public.normalizar_mac(text) OWNER TO spi40;

--
-- Name: pack_en_uso(integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.pack_en_uso(integer) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_pack ALIAS FOR $1;
        packs_padres text;
	registro RECORD;
        resultado integer;
BEGIN

	resultado := 0;
	packs_padres := ids_packs_padres(val_id_pack,0);
	--raise notice 'padres %',packs_padres;

	IF packs_padres != '' THEN
		packs_padres := val_id_pack || ',' || packs_padres ;
		resultado := 1;
	ELSE
		packs_padres := val_id_pack;
	END IF;

	FOR registro IN EXECUTE 'SELECT count(*) as cantidad
			FROM com_locaciones_clientes_packs
			 WHERE id_pack IN (' || packs_padres || ')
			LIMIT 1' LOOP
	   --raise notice 'registro %',registro.cantidad;
	   IF registro.cantidad != 0 THEN
		resultado := 1;
	   END IF;
	END LOOP;

        RETURN resultado;
END
$_$;


ALTER FUNCTION public.pack_en_uso(integer) OWNER TO spi40;

--
-- Name: pack_es_facturable(integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.pack_es_facturable(integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_pack ALIAS FOR $1;
	registro RECORD;
        registros_hijos RECORD;
        resultado boolean;
BEGIN
	resultado := false;

	SELECT INTO registro de_servicios
	                FROM com_packs
	               WHERE id = val_id_pack;

	FOR registros_hijos IN (SELECT id_hijo,
	                               ts.facturable
				  FROM com_packs_contenido as cpc
				       left join com_packs as cp on cp.id=cpc.id_pack and cp.de_servicios=1
				       left join svc_servicios as ser on ser.id=cpc.id_hijo
				       left join svc_tipos_servicios as ts on ts.id=ser.id_tipo_servicio
				 WHERE id_pack = val_id_pack
				) LOOP

    	    IF registro.de_servicios = 0 THEN
		-- es un pack de packs, busco dentro
		if pack_es_facturable(registros_hijos.id_hijo) then
		    resultado = true;
		end if;
	    ELSIF registros_hijos.facturable THEN
		-- es un pack de servicios facturables
		resultado = true;
    	    END IF;
	END LOOP;

	return resultado;

END
$_$;


ALTER FUNCTION public.pack_es_facturable(integer) OWNER TO spi40;

--
-- Name: plg_1000_cm_cambio_servicio_setear_flag(); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.plg_1000_cm_cambio_servicio_setear_flag() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
            DECLARE
                actualizar boolean;
            begin
                actualizar = false;	 

                IF (TG_OP = 'INSERT') then
                    IF ( new.id_tipo_tecnologia =1000 and (new.id_tipo_servicio = 1000 or new.id_tipo_servicio = 1002)) then		             
                        actualizar = true;
                    END IF; 
                elsif (TG_OP = 'UPDATE') then 
                    IF ( new.id_tipo_tecnologia =1000 and (new.id_tipo_servicio = 1000 or new.id_tipo_servicio = 1002)) then		    
                        IF (old.nombre != new.nombre or old.descripcion != new.descripcion ) then 
                            actualizar = true;
                        END IF;
                    END IF; 
                else -- delete 
                    IF ( old.id_tipo_tecnologia =1000 and (old.id_tipo_servicio = 1000 or old.id_tipo_servicio = 1002)) then		         
                        actualizar = true;	
                    END IF;  
                END if;

                IF (actualizar) THEN
                    update cfg_configuraciones
                       set valor=1
                     where id=1036;
                END IF;		

                IF (TG_OP = 'DELETE') then
                    RETURN old;
                else
                    RETURN NEW;
                END if;
            END
        $$;


ALTER FUNCTION public.plg_1000_cm_cambio_servicio_setear_flag() OWNER TO spi40;

--
-- Name: plg_1000_cm_chequear_cm_duplicado_en_servicios(); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.plg_1000_cm_chequear_cm_duplicado_en_servicios() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	registro record;
BEGIN
	-- FUNCION QUE CHEQUEA QUE CUANDO AGREGO UNA MAC NO ESTE REPETIDA
	-- SI EXISTE EL TRIGGER GENERA UN EXCEPCION QUE IMPIDE EL INSERT/UPDATE

	-- miro que el id_propiedad se corresponda con una mac
	IF (NEW.id_propiedad = 1003) THEN
		IF (TG_OP = 'INSERT') THEN
			SELECT INTO registro count(*) AS cantidad
			  FROM svc_servicios_propiedades
			 WHERE id_propiedad = NEW.id_propiedad AND
			       valor = NEW.valor;
				raise notice 'insertado id_mac:%', NEW.valor;
			IF (registro.cantidad > 0) THEN
				raise exception 'insert on table "svc_servicios_propiedades" violates virtual relation " plg_1000_cm_impedir_cm_duplicado_en_servicios"
	DETAIL: Key (id_mac)=(%) is still referenced from table "svc_servicios_propiedades". ',NEW.valor ;
				RETURN NULL;
			END IF;
		ELSEIF (TG_OP = 'UPDATE') THEN
			SELECT INTO registro count(*) AS cantidad
			  FROM svc_servicios_propiedades
			 WHERE id_propiedad = NEW.id_propiedad AND
			       valor = NEW.valor AND
			       id_locacion_cliente_pack_servicio != NEW.id_locacion_cliente_pack_servicio;
				raise notice 'insertado id_mac:%', NEW.valor;
			IF (registro.cantidad > 0) THEN
				raise exception 'update on table "svc_servicios_propiedades" violates virtual relation " plg_1000_cm_impedir_cm_duplicado_en_servicios"
	DETAIL: Key (id_mac)=(%) is still referenced from table "svc_servicios_propiedades". ',NEW.valor;
				RETURN NULL;
			END IF;
		END IF;
	END IF;

        RETURN NEW;
END
$$;


ALTER FUNCTION public.plg_1000_cm_chequear_cm_duplicado_en_servicios() OWNER TO spi40;

--
-- Name: plg_1000_cm_chequear_dependencias_modelos_explog_especifica(); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.plg_1000_cm_chequear_dependencias_modelos_explog_especifica() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	registro record;
BEGIN
	-- FUNCION QUE CHEQUEA QUE CUANDO BORRO EL id DE plg_1000_cm_modelos_explog_especifica NO ESTE ESTE EN plg_1000_cm_servicios_explog,
	-- SI ESTA DEFINIDO EL TRIGGER GENERA UN EXCEPCION QUE IMPIDE EL DELETE
        IF (TG_OP = 'DELETE') THEN

		SELECT INTO registro count(*) AS cantidad
		  FROM plg_1000_cm_servicios_explog
		 WHERE id_explog_especifica = OLD.id;
raise notice 'borrando id:%',OLD.id;
		IF (registro.cantidad > 0) THEN
			raise exception 'update or delete on table "plg_1000_cm_modelos_explog_especifica" violates virtual relation "plg_1000_cm_chequear_dependencias_explog_especifica"
DETAIL: Key (id)=(%) is still referenced from table "plg_1000_cm_servicios_explog". ',OLD.id;
			RETURN NULL;
		END IF;

	END IF;

        RETURN OLD;
END
$$;


ALTER FUNCTION public.plg_1000_cm_chequear_dependencias_modelos_explog_especifica() OWNER TO spi40;

--
-- Name: plg_1000_cm_chequear_dependencias_rangos_ip(); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.plg_1000_cm_chequear_dependencias_rangos_ip() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
                DECLARE
                    val_registro RECORD;
                    val_id_idioma TEXT;
                    val_desde_ip bigint;
                    val_hasta_ip bigint;    
                BEGIN

                    val_id_idioma := valor_variable_de_session('session.id_idioma','1');

                    IF TG_OP = 'UPDATE' THEN

                        IF (OLD.desde_ip != NEW.desde_ip or OLD.hasta_ip != NEW.hasta_ip) THEN

                            IF ip2long(NEW.desde_ip) > ip2long(OLD.desde_ip) THEN -- reduce rango al principio
                                val_desde_ip := ip2long(OLD.desde_ip);
                                val_hasta_ip := ip2long(NEW.desde_ip) - 1;  		
                            END IF; 

                            IF ip2long(OLD.hasta_ip) > ip2long(NEW.hasta_ip) THEN -- reduce rango al final
                                val_desde_ip := ip2long(NEW.hasta_ip) + 1;
                                val_hasta_ip := ip2long(OLD.hasta_ip); 
                            END IF; 

                            -- chequeo si hay ips asignadas en el subrango eliminado
                            SELECT INTO val_registro
                                   lc.id_cliente,
                                   err.descripcion as descripcion_error,
                                   pro.valor as ip
                              FROM svc_servicios_propiedades as pro
                                   join com_locaciones_clientes_packs_servicios as lcps on lcps.id=pro.id_locacion_cliente_pack_servicio
                                   join com_locaciones_clientes_packs as lcp on lcp.id=lcps.id_locacion_cliente_pack
                                   join com_locaciones_clientes as lc on lc.id=lcp.id_locacion_cliente
                                   join lang_mensajes_varios as err on err.id = 2 and 
                                                                       err.id_idioma::text = val_id_idioma
                             WHERE not is_numeric(pro.valor) and
                                   ip2long(pro.valor) >= val_desde_ip  and 
                                   ip2long(pro.valor) <= val_hasta_ip and
                                   pro.id_propiedad = 1004;

                             IF FOUND THEN
                                 RAISE EXCEPTION '% %',replace(val_registro.descripcion_error, '%ip%',val_registro.ip) , val_registro.id_cliente;
                             END IF;			

                        END IF;

                        RETURN NEW;  

                    ELSIF TG_OP = 'DELETE' THEN      
                        -- busco si el rango de ip esta en uso en la tabla svc_servicios_propiedades, si esta es por que esta asignado a un usuario
                        SELECT INTO val_registro
                               lc.id_cliente,
                               err.descripcion as descripcion_error,
                               pro.valor as ip
                          FROM svc_servicios_propiedades as pro
                               join com_locaciones_clientes_packs_servicios as lcps on lcps.id=pro.id_locacion_cliente_pack_servicio
                               join com_locaciones_clientes_packs as lcp on lcp.id=lcps.id_locacion_cliente_pack
                               join com_locaciones_clientes as lc on lc.id=lcp.id_locacion_cliente
                               join lang_mensajes_varios as err on err.id = 2 and 
                                                                   err.id_idioma::text = val_id_idioma
                         WHERE not is_numeric(pro.valor) and
                               ip2long(pro.valor) >= ip2long(OLD.desde_ip) and 
                               ip2long(pro.valor) <= ip2long(OLD.hasta_ip) and
                               pro.id_propiedad = 1004;
                        IF FOUND THEN
                            RAISE EXCEPTION '% %',replace(val_registro.descripcion_error, '%ip%',val_registro.ip) , val_registro.id_cliente;
                        END IF;   

                        RETURN OLD;  
                    END IF;    

                END
                $$;


ALTER FUNCTION public.plg_1000_cm_chequear_dependencias_rangos_ip() OWNER TO spi40;

--
-- Name: plg_1000_cm_chequear_dependencias_servicios_explog(); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.plg_1000_cm_chequear_dependencias_servicios_explog() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	registro record;
BEGIN

	-- FUNCION QUE CHEQUEA QUE EL id_modelo Y EL id_explog_especifica ESTEN DEFINIDOS ANTES DE INSERTAR UN REGISTRO EN plg_1000_cm_servicios_explog,
	-- SI ALGUNO DE ESTOS DOS NO ESTAN DEFINIDOS EL TRIGGER GENERA UN EXCEPCION QUE IMPIDE EL INSERT O EL UPDATE
	-- TAMBIEN CHEQUEO QUE ESTE DEFINIDO EL id_servicio O EL id_grupo, PERO NO LOS DOS A LA VEZ
        IF (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
		--si esta definido el id_modelo chequeo que este exista en la tabla tec_modelos
		IF (NEW.id_modelo IS NOT NULL) THEN

			SELECT INTO registro count(*) AS cantidad
			  FROM tec_modelos
			 WHERE id = NEW.id_modelo;

			IF (registro.cantidad = 0) THEN
				raise exception 'insert or update on table "plg_1000_cm_servicios_explog" violates virtual relation "plg_1000_cm_chequear_dependencias_explog"
DETAIL: Key (id_modelo)=(%) is not present in table "tec_modelos". ', NEW.id_modelo;
				RETURN NULL;
			END IF;

		END IF;

		--si esta definida la id_explog_especifica chequeo que esta exista en la tabla plg_1000_cm_modelos_explog_especifica
		IF (NEW.id_modelo IS NOT NULL AND NEW.id_explog_especifica IS NOT NULL) THEN

			SELECT INTO registro count(*) AS cantidad
			  FROM plg_1000_cm_modelos_explog_especifica
			 WHERE id = NEW.id_explog_especifica;

			IF (registro.cantidad = 0) THEN
				raise exception 'insert or update on table "plg_1000_cm_servicios_explog" violates virtual relation "plg_1000_cm_chequear_dependencias_explog"
DETAIL: Key (id_explog_especifica)=(%) is not present in table "plg_1000_cm_modelos_explog_especifica". ', NEW.id_explog_especifica;
				RETURN NULL;
			END IF;

		END IF;
	END IF;
	
	-- chequeo que este definido el id_modelo o el id_grupo, solo uno
	IF ((NEW.id_servicio IS NOT NULL AND NEW.id_grupo IS NOT NULL) OR
	    (NEW.id_servicio IS NULL AND NEW.id_grupo IS NULL))THEN
		raise exception 'insert or update on table "plg_1000_cm_servicios_explog" violates virtual relation "plg_1000_cm_chequear_dependencias_explog"
DETAIL: Key (id_servicio)=(%) XOR (id_grupo)=(%) must be defined in table "plg_1000_cm_modelos_explog_especifica". ', NEW.id_servicio, NEW.id_grupo;
		RETURN NULL;
	END IF;

        RETURN NEW;
END
$$;


ALTER FUNCTION public.plg_1000_cm_chequear_dependencias_servicios_explog() OWNER TO spi40;

--
-- Name: plg_1000_cm_expresiones_modelos(integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.plg_1000_cm_expresiones_modelos(integer) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_modelo ALIAS FOR $1;
        expresiones RECORD;
        resultado text;
BEGIN
	resultado := '';
	FOR expresiones IN (SELECT explog
	                      FROM plg_1000_cm_modelos_explog
			     WHERE id_modelo = val_id_modelo) LOOP
		IF resultado != '' THEN
			resultado := resultado || ' OR (' || expresiones.explog || ')';
		ELSE
			resultado := '(' || expresiones.explog || ')';
		END IF;
	END LOOP;

        RETURN resultado;
 END
$_$;


ALTER FUNCTION public.plg_1000_cm_expresiones_modelos(integer) OWNER TO spi40;

--
-- Name: plg_1000_cm_id_servicio_conectividad_en_pack(integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.plg_1000_cm_id_servicio_conectividad_en_pack(integer) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
val_id_pack ALIAS FOR $1;
registro RECORD;
registros_hijos RECORD;
resultado integer;           
BEGIN
resultado := -1; 
SELECT INTO registro de_servicios FROM com_packs WHERE id = val_id_pack;

FOR registros_hijos IN (SELECT id_hijo,
id_tipo_servicio,
id_tipo_tecnologia
FROM com_packs_contenido as cpc
left join svc_servicios as ss on ss.id=cpc.id_hijo
WHERE cpc.id_pack = val_id_pack
) LOOP

IF registro.de_servicios = 0 THEN
-- es un pack de packs, busco dentro                        
return plg_1000_cm_id_servicio_conectividad_en_pack(registros_hijos.id_hijo);                    
ELSE
-- es un pack de servicios, miro si es de cm
if (registros_hijos.id_tipo_servicio = 1000 or registros_hijos.id_tipo_servicio = 1002) and  registros_hijos.id_tipo_tecnologia = 1000 then                            
return registros_hijos.id_hijo;                            
end if;
END IF;
END LOOP;

RETURN resultado;-- no encontro, retorno -1
END
$_$;


ALTER FUNCTION public.plg_1000_cm_id_servicio_conectividad_en_pack(integer) OWNER TO spi40;

--
-- Name: propiedades_servicios(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.propiedades_servicios(integer, integer, integer) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $_$
                DECLARE
                        val_id_locacion_cliente_pack ALIAS FOR $1;
                        val_id_servicio ALIAS FOR $2;
                        val_id_idioma ALIAS FOR $3;

                        registro  record;
                        propiedad record;
                        consulta text;
                        nombre_tabla text;
                        id_tipo_servicio int;

                BEGIN
                        nombre_tabla='tabla_temporal_rnd_' || (random()*99999999)::integer;
                        raise notice 'tabla = %', nombre_tabla;
                        EXECUTE 'create TEMPORARY table ' || nombre_tabla || ' (id_locacion_cliente_pack_servicio integer)ON COMMIT DROP';

                        consulta := -1;
                        FOR registro  IN ((SELECT pro.id,
                                                lang.descripcion,
                                                pro.orden_mostrado
                                            FROM svc_tipos_servicios_propiedades AS tsp
                                                JOIN svc_propiedades AS pro ON pro.id = tsp.id_propiedad
                                                JOIN lang_svc_propiedades AS lang ON lang.id_propiedad = pro.id AND lang.id_idioma = val_id_idioma
                                                JOIN svc_servicios AS ser ON ser.id_tipo_servicio=tsp.id_tipo_servicio
                                            WHERE ser.id = val_id_servicio)
                                        UNION
                                        (SELECT pro.id,
                                                lang.descripcion,
                                                pro.orden_mostrado
                                            FROM svc_tipos_tecnologias_propiedades AS ttp
                                                JOIN svc_propiedades AS pro ON pro.id = ttp.id_propiedad
                                                JOIN lang_svc_propiedades AS lang ON lang.id_propiedad = pro.id AND lang.id_idioma = val_id_idioma
                                                JOIN svc_servicios AS ser ON ser.id_tipo_tecnologia=ttp.id_tipo_tecnologia
                                        WHERE  ser.id = val_id_servicio)
                                    ORDER BY
                                                orden_mostrado, id ) LOOP
                                consulta := consulta || ',''' || registro.id || '''' ;
                                EXECUTE 'ALTER TABLE ' || nombre_tabla || ' ADD COLUMN "' || registro.descripcion || '" text;';
                                raise notice 'insertando id % desc  %', registro.id, registro.descripcion;
                          
                        END LOOP;

                        -- agrego la columna de estado
                        EXECUTE 'ALTER TABLE ' || nombre_tabla || ' ADD COLUMN estado integer;';

                        raise notice 'consulta';
                        EXECUTE  'INSERT INTO ' || nombre_tabla || ' VALUES ('|| consulta || ',-1);';

                        FOR registro  IN (SELECT id,
                                                estado
                                            FROM com_locaciones_clientes_packs_servicios
                                        WHERE id_locacion_cliente_pack = val_id_locacion_cliente_pack AND
                                                id_servicio=val_id_servicio
                                        ORDER BY id) LOOP
                                consulta := registro.id;
                                FOR propiedad  IN (                      
												select pro.id as id_propiedad,
												       coalesce(valor,'') as valor
												from svc_propiedades pro     
												     JOIN lang_svc_propiedades AS lang ON lang.id_propiedad = pro.id AND lang.id_idioma = val_id_idioma
											       	join svc_tipos_servicios_propiedades stsp on stsp.id_propiedad = pro.id 
												    left join svc_servicios_propiedades as sp on sp.id_locacion_cliente_pack_servicio =registro.id and sp.id_propiedad =pro.id
												      JOIN svc_servicios AS ser ON ser.id_tipo_servicio=stsp.id_tipo_servicio and ser.id=val_id_servicio
												  ORDER BY  pro.orden_mostrado,sp.id_propiedad
                                                ) loop
	                                       raise notice 'propiedad % valor %',propiedad.id_propiedad, propiedad.valor ;
                                        consulta :=  consulta || ',''' || propiedad.valor || '''';
                                END LOOP;
                                raise notice 'registro %',consulta;
                                EXECUTE  'INSERT INTO ' || nombre_tabla || ' VALUES ('|| consulta || ',' || registro.estado || ');';
                        END LOOP;

                        FOR registro IN EXECUTE 'SELECT * FROM ' || nombre_tabla   LOOP
                        raise notice 'registro %',registro;
                        RETURN NEXT registro;
                        END LOOP;

                        RETURN;
                END
                $_$;


ALTER FUNCTION public.propiedades_servicios(integer, integer, integer) OWNER TO spi40;

--
-- Name: propiedades_servicios_columnas(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.propiedades_servicios_columnas(integer, integer, integer) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_servicio ALIAS FOR $2;
        val_id_idioma ALIAS FOR $3;

        registro  record;
        consulta text;
        resultado text;

BEGIN
	resultado := 'tabla(id integer';
	FOR registro  IN ((SELECT pro.id,
	                          lang.descripcion
                             FROM svc_tipos_servicios_propiedades AS tsp
                    	          JOIN svc_propiedades AS pro ON pro.id = tsp.id_propiedad
                  	          JOIN lang_svc_propiedades AS lang ON lang.id_propiedad = pro.id AND lang.id_idioma = val_id_idioma
                  	          JOIN svc_servicios AS ser ON ser.id_tipo_servicio=tsp.id_tipo_servicio
                            WHERE ser.id = val_id_servicio)
                        UNION
                          (SELECT pro.id,
	                          lang.descripcion
                             FROM svc_tipos_tecnologias_propiedades AS ttp
                   	          JOIN svc_propiedades AS pro ON pro.id = ttp.id_propiedad
                  	          JOIN lang_svc_propiedades AS lang ON lang.id_propiedad = pro.id AND lang.id_idioma = val_id_idioma
                  	          JOIN svc_servicios AS ser ON ser.id_tipo_tecnologia=ttp.id_tipo_tecnologia
                           WHERE  ser.id = val_id_servicio)
	               ORDER BY id ) LOOP
	        resultado := resultado || ',''' || registro.descripcion || '''' || ' text' ;
		--raise notice 'insertando id % desc  %', registro.id, registro.descripcion;
	END LOOP;
	resultado := resultado || ',estado integer)' ;


        RETURN resultado;
END
$_$;


ALTER FUNCTION public.propiedades_servicios_columnas(integer, integer, integer) OWNER TO spi40;

--
-- Name: propiedades_servicios_columnas(integer, integer, text); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.propiedades_servicios_columnas(integer, integer, text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_servicio ALIAS FOR $1;
        val_id_idioma ALIAS FOR $2;
        val_etiqueta_estado ALIAS FOR $3;

        registro  record;
        consulta text;
        resultado text;

BEGIN
	resultado := 'tabla(id integer';
	FOR registro  IN ((SELECT pro.id,
	                          lang.descripcion
                             FROM svc_tipos_servicios_propiedades AS tsp
                    	          JOIN svc_propiedades AS pro ON pro.id = tsp.id_propiedad
                  	          JOIN lang_svc_propiedades AS lang ON lang.id_propiedad = pro.id AND lang.id_idioma = val_id_idioma
                  	          JOIN svc_servicios AS ser ON ser.id_tipo_servicio=tsp.id_tipo_servicio
                            WHERE ser.id = val_id_servicio)
                        UNION
                          (SELECT pro.id,
	                          lang.descripcion
                             FROM svc_tipos_tecnologias_propiedades AS ttp
                   	          JOIN svc_propiedades AS pro ON pro.id = ttp.id_propiedad
                  	          JOIN lang_svc_propiedades AS lang ON lang.id_propiedad = pro.id AND lang.id_idioma = val_id_idioma
                  	          JOIN svc_servicios AS ser ON ser.id_tipo_tecnologia=ttp.id_tipo_tecnologia
                           WHERE  ser.id = val_id_servicio)
	               ORDER BY id ) LOOP
	        resultado := resultado || ',"' || registro.descripcion || '" text' ;
		--raise notice 'insertando id % desc  %', registro.id, registro.descripcion;
	END LOOP;
	resultado := resultado || ',"' || val_etiqueta_estado  || '" integer)' ;


        RETURN resultado;
END
$_$;


ALTER FUNCTION public.propiedades_servicios_columnas(integer, integer, text) OWNER TO spi40;

--
-- Name: restar_permisos_permitidos_a_negados_padres(public.tipo_permisos, public.tipo_permisos); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.restar_permisos_permitidos_a_negados_padres(public.tipo_permisos, public.tipo_permisos) RETURNS public.tipo_permisos
    LANGUAGE plpgsql
    AS $_$
DECLARE
	permisos_actual ALIAS FOR $1;
	permisos_padre  ALIAS FOR $2;
	permisos_entidad tipo_permisos;
	permitido integer;
	negado integer;
	negado_padre_menos_permitido_actual integer;
BEGIN
	permitido 		            := permisos_actual.permitido | permisos_padre.permitido;
	negado_padre_menos_permitido_actual := permisos_padre.negado - (permisos_padre.negado & permisos_actual.permitido);
	negado    		            := negado_padre_menos_permitido_actual | permisos_actual.negado;
	permisos_entidad := (permitido, negado);
	return permisos_entidad;
END;
$_$;


ALTER FUNCTION public.restar_permisos_permitidos_a_negados_padres(public.tipo_permisos, public.tipo_permisos) OWNER TO spi40;

--
-- Name: setear_flags_abns(); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.setear_flags_abns() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
        DECLARE
                var_registro_tmp record;
                var_id_propiedad integer;
        BEGIN
            var_id_propiedad = -1;
            IF (TG_RELNAME = 'com_locaciones_clientes_packs_servicios') THEN
                        -- si cambio el estado del servicio seteo el abn, el var_id_propiedad = 3 es el estado del servicio
                        IF (TG_OP = 'UPDATE') THEN
                                IF (OLD.estado != NEW.estado) THEN
                                        --raise notice 'update  ant: %  nuevo: %',OLD.estado,NEW.estado;
                                        var_id_propiedad = 3;
                                END IF;
                        ELSE
                                var_id_propiedad = 3;
                        END IF;
                ELSIF (TG_RELNAME = 'com_locaciones_clientes_packs') THEN
                        -- si cambio el estado del pack seteo el abn, el var_id_propiedad = 4 es el estado del pack
                        IF (TG_OP = 'UPDATE') THEN
                                IF (OLD.estado != NEW.estado) THEN
                                        --raise notice 'update  ant: %  nuevo: %',OLD.estado,NEW.estado;
                                        var_id_propiedad = 4;
                                END IF;
                        ELSE
                                var_id_propiedad = 4;
                        END IF;
                ELSE
                        IF (TG_OP = 'UPDATE') THEN
                                IF (OLD.valor != NEW.valor) THEN
                                        --raise notice 'update  ant: %  nuevo: %',OLD.valor,NEW.valor;
                                        var_id_propiedad = NEW.id_propiedad;
                                END IF;
                        ELSIF (TG_OP = 'INSERT') THEN
                                --raise notice 'insert nuevo: %',NEW.valor;
                                var_id_propiedad = NEW.id_propiedad;
                        ELSIF (TG_OP = 'DELETE') THEN
                                --raise notice 'delete  ant: %',OLD.valor;
                                var_id_propiedad = OLD.id_propiedad;
                        END IF;
                END IF;

                IF (var_id_propiedad != -1) THEN
                        FOR var_registro_tmp IN (SELECT pa.id_abn
                              FROM sys_propiedades_abns AS pa
                             WHERE pa.id_propiedad = var_id_propiedad ) LOOP
                                --raise notice 'id: %',var_registro_tmp.id_abn;
                                UPDATE sys_abns
                                   SET flag = 1
                                 WHERE id = var_registro_tmp.id_abn;
                        END LOOP;
                END IF;

            RETURN NEW;
        END
        $$;


ALTER FUNCTION public.setear_flags_abns() OWNER TO spi40;

--
-- Name: tipos_servicios_asociados(integer, integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.tipos_servicios_asociados(integer, integer) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_tipo_tecnologia ALIAS FOR $1;
        val_id_idioma ALIAS FOR $2;
        servicios RECORD;
        resultado text;
BEGIN
	resultado := '';
	FOR servicios IN (SELECT tstt.id_tipo_servicio,
	                         lts.descripcion
			    FROM svc_tipos_servicios_tipos_tecnologias AS tstt
			         JOIN lang_svc_tipos_servicios AS lts ON lts.id_tipo_servicio=tstt.id_tipo_servicio AND lts.id_idioma = val_id_idioma
			  WHERE id_tipo_tecnologia = val_id_tipo_tecnologia) LOOP
		IF resultado != '' THEN
			resultado := resultado || ',[' || servicios.id_tipo_servicio || ',''' || servicios.descripcion || ''']';
		ELSE
			resultado := '[' || servicios.id_tipo_servicio || ',''' || servicios.descripcion || ''']';
		END IF;
	END LOOP;

        RETURN '[' || resultado || ']';
 END
$_$;


ALTER FUNCTION public.tipos_servicios_asociados(integer, integer) OWNER TO spi40;

--
-- Name: tipos_tecnologias_asociadas(integer, integer); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.tipos_tecnologias_asociadas(integer, integer) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
        val_id_tipo_servicio ALIAS FOR $1;
        val_id_idioma ALIAS FOR $2;
        tecnologias RECORD;
        resultado text;
BEGIN
	resultado := '';
	FOR tecnologias IN (SELECT tstt.id_tipo_tecnologia,
	                           ltt.descripcion
			      FROM svc_tipos_servicios_tipos_tecnologias AS tstt
			           JOIN lang_tec_tipos_tecnologias AS ltt ON ltt.id_tipo_tecnologia=tstt.id_tipo_tecnologia AND ltt.id_idioma = val_id_idioma
			     WHERE id_tipo_servicio = val_id_tipo_servicio) LOOP
		IF resultado != '' THEN
			resultado := resultado || ',[' || tecnologias.id_tipo_tecnologia || ',''' || tecnologias.descripcion || ''']';
		ELSE
			resultado := '[' || tecnologias.id_tipo_tecnologia || ',''' || tecnologias.descripcion || ''']';
		END IF;
	END LOOP;

        RETURN '[' || resultado || ']';
 END
$_$;


ALTER FUNCTION public.tipos_tecnologias_asociadas(integer, integer) OWNER TO spi40;

--
-- Name: upper_latin1(text); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.upper_latin1(text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
        texto ALIAS FOR $1;
BEGIN
    RETURN upper(translate(texto, 'àáâãäåæçèéêëìíîïðñòóôõöøùúûüý', 'ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝ'));
END
$_$;


ALTER FUNCTION public.upper_latin1(text) OWNER TO spi40;

--
-- Name: valor_variable_de_session(text, text); Type: FUNCTION; Schema: public; Owner: spi40
--

CREATE FUNCTION public.valor_variable_de_session(text, text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
        DECLARE
                val_nombre_variable  ALIAS FOR $1;
                val_valor_default  ALIAS FOR $2;
                val_resultado text;
        BEGIN
                BEGIN
                    val_resultado := current_setting(val_nombre_variable);
                    IF (val_resultado = 'unset' OR val_resultado = '') THEN
                        val_resultado := val_valor_default;
                    END IF;
                EXCEPTION WHEN others THEN
                    val_resultado := val_valor_default;
                END;

                RETURN val_resultado; 
        END
        $_$;


ALTER FUNCTION public.valor_variable_de_session(text, text) OWNER TO spi40;

--
-- Name: campos_modificados_id_seq; Type: SEQUENCE; Schema: auditoria; Owner: spi40
--

CREATE SEQUENCE auditoria.campos_modificados_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE auditoria.campos_modificados_id_seq OWNER TO spi40;

--
-- Name: campos_modificados; Type: TABLE; Schema: auditoria; Owner: spi40
--

CREATE TABLE auditoria.campos_modificados (
    id integer DEFAULT nextval('auditoria.campos_modificados_id_seq'::regclass) NOT NULL,
    id_registro integer NOT NULL,
    nombre_campo character varying(60),
    valor_anterior text,
    valor_nuevo text
);


ALTER TABLE auditoria.campos_modificados OWNER TO spi40;

--
-- Name: eventos_id_seq; Type: SEQUENCE; Schema: auditoria; Owner: spi40
--

CREATE SEQUENCE auditoria.eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE auditoria.eventos_id_seq OWNER TO spi40;

--
-- Name: eventos; Type: TABLE; Schema: auditoria; Owner: spi40
--

CREATE TABLE auditoria.eventos (
    id integer DEFAULT nextval('auditoria.eventos_id_seq'::regclass) NOT NULL,
    id_operador integer NOT NULL,
    ip_origen inet NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    id_entidad integer NOT NULL
);


ALTER TABLE auditoria.eventos OWNER TO spi40;

--
-- Name: lang_tipos_operaciones; Type: TABLE; Schema: auditoria; Owner: spi40
--

CREATE TABLE auditoria.lang_tipos_operaciones (
    id integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion character varying(50)
);


ALTER TABLE auditoria.lang_tipos_operaciones OWNER TO spi40;

--
-- Name: parametros_acceso_id_seq; Type: SEQUENCE; Schema: auditoria; Owner: spi40
--

CREATE SEQUENCE auditoria.parametros_acceso_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE auditoria.parametros_acceso_id_seq OWNER TO spi40;

--
-- Name: parametros_acceso; Type: TABLE; Schema: auditoria; Owner: spi40
--

CREATE TABLE auditoria.parametros_acceso (
    id integer DEFAULT nextval('auditoria.parametros_acceso_id_seq'::regclass) NOT NULL,
    id_evento integer NOT NULL,
    nombre_campo character varying(60) NOT NULL,
    valor character varying(100) NOT NULL
);


ALTER TABLE auditoria.parametros_acceso OWNER TO spi40;

--
-- Name: registros_modificados_id_seq; Type: SEQUENCE; Schema: auditoria; Owner: spi40
--

CREATE SEQUENCE auditoria.registros_modificados_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE auditoria.registros_modificados_id_seq OWNER TO spi40;

--
-- Name: registros_modificados; Type: TABLE; Schema: auditoria; Owner: spi40
--

CREATE TABLE auditoria.registros_modificados (
    id integer DEFAULT nextval('auditoria.registros_modificados_id_seq'::regclass) NOT NULL,
    id_evento integer NOT NULL,
    id_tipo_operacion integer NOT NULL,
    tabla character varying(60) NOT NULL,
    llaves_primarias integer[] NOT NULL
);


ALTER TABLE auditoria.registros_modificados OWNER TO spi40;

--
-- Name: secuencia_global; Type: SEQUENCE; Schema: auditoria; Owner: spi40
--

CREATE SEQUENCE auditoria.secuencia_global
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE auditoria.secuencia_global OWNER TO spi40;

--
-- Name: lang_sys_entidades; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_sys_entidades (
    id_entidad integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion character varying(110) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE public.lang_sys_entidades OWNER TO spi40;

--
-- Name: sys_operadores_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.sys_operadores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sys_operadores_id_seq OWNER TO spi40;

--
-- Name: sys_operadores; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_operadores (
    id integer DEFAULT nextval('public.sys_operadores_id_seq'::regclass) NOT NULL,
    id_padre integer DEFAULT 1 NOT NULL,
    nombre character varying(50) DEFAULT ''::character varying NOT NULL,
    login character varying(50) DEFAULT ''::character varying NOT NULL,
    password character varying(50) DEFAULT ''::character varying NOT NULL,
    id_idioma integer DEFAULT 1 NOT NULL,
    imagen character varying(100) DEFAULT 'default.jpg'::character varying NOT NULL,
    estado integer DEFAULT 0 NOT NULL,
    duracion_sesion character varying DEFAULT '30m'::character varying NOT NULL,
    es_grupo smallint DEFAULT 0 NOT NULL,
    parametros_acceso text DEFAULT ''::text
);


ALTER TABLE public.sys_operadores OWNER TO spi40;

--
-- Name: vista_general; Type: VIEW; Schema: auditoria; Owner: spi40
--

CREATE VIEW auditoria.vista_general AS
 SELECT ev.id,
    op.nombre AS operador,
    ev.ip_origen,
    ev."timestamp",
    en.descripcion AS entidad,
    reg.tabla,
    COALESCE(top.descripcion, acc.descripcion) AS operacion,
    reg.llaves_primarias AS llaves,
    array_to_string(ARRAY( SELECT (((parametros_acceso.nombre_campo)::text || ':'::text) || (parametros_acceso.valor)::text)
           FROM auditoria.parametros_acceso
          WHERE (parametros_acceso.id_evento = ev.id)
        UNION
         SELECT (((((campos_modificados.nombre_campo)::text || ':'::text) || COALESCE(campos_modificados.valor_anterior, ''::text)) || '->'::text) || COALESCE(campos_modificados.valor_nuevo, ''::text))
           FROM auditoria.campos_modificados
          WHERE (campos_modificados.id_registro = reg.id)), '<br>'::text) AS campos
   FROM (((((auditoria.eventos ev
     LEFT JOIN auditoria.registros_modificados reg ON ((reg.id_evento = ev.id)))
     JOIN public.lang_sys_entidades en ON (((en.id_entidad = ev.id_entidad) AND (en.id_idioma = (public.valor_variable_de_session('session.id_idioma'::text, '1'::text))::integer))))
     LEFT JOIN auditoria.lang_tipos_operaciones acc ON (((acc.id = 4) AND (acc.id_idioma = en.id_idioma))))
     LEFT JOIN auditoria.lang_tipos_operaciones top ON (((top.id = reg.id_tipo_operacion) AND (top.id_idioma = en.id_idioma))))
     LEFT JOIN public.sys_operadores op ON ((op.id = ev.id_operador)));


ALTER TABLE auditoria.vista_general OWNER TO spi40;

--
-- Name: campos_modificados; Type: TABLE; Schema: auditoria_historico; Owner: spi40
--

CREATE TABLE auditoria_historico.campos_modificados (
    id integer NOT NULL,
    id_registro integer NOT NULL,
    nombre_campo character varying(60),
    valor_anterior text,
    valor_nuevo text
);


ALTER TABLE auditoria_historico.campos_modificados OWNER TO spi40;

--
-- Name: eventos; Type: TABLE; Schema: auditoria_historico; Owner: spi40
--

CREATE TABLE auditoria_historico.eventos (
    id integer NOT NULL,
    id_operador integer NOT NULL,
    ip_origen inet NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    id_entidad integer NOT NULL
);


ALTER TABLE auditoria_historico.eventos OWNER TO spi40;

--
-- Name: parametros_acceso; Type: TABLE; Schema: auditoria_historico; Owner: spi40
--

CREATE TABLE auditoria_historico.parametros_acceso (
    id integer NOT NULL,
    id_evento integer NOT NULL,
    nombre_campo character varying(60) NOT NULL,
    valor character varying(100) NOT NULL
);


ALTER TABLE auditoria_historico.parametros_acceso OWNER TO spi40;

--
-- Name: registros_modificados; Type: TABLE; Schema: auditoria_historico; Owner: spi40
--

CREATE TABLE auditoria_historico.registros_modificados (
    id integer NOT NULL,
    id_evento integer NOT NULL,
    id_tipo_operacion integer NOT NULL,
    tabla character varying(60) NOT NULL,
    llaves_primarias integer[] NOT NULL
);


ALTER TABLE auditoria_historico.registros_modificados OWNER TO spi40;

--
-- Name: vista_general; Type: VIEW; Schema: auditoria_historico; Owner: spi40
--

CREATE VIEW auditoria_historico.vista_general AS
 SELECT ev.id,
    op.nombre AS operador,
    ev.ip_origen,
    ev."timestamp",
    en.descripcion AS entidad,
    reg.tabla,
    COALESCE(top.descripcion, acc.descripcion) AS operacion,
    reg.llaves_primarias AS llaves,
    array_to_string(ARRAY( SELECT (((parametros_acceso.nombre_campo)::text || ':'::text) || (parametros_acceso.valor)::text)
           FROM auditoria_historico.parametros_acceso
          WHERE (parametros_acceso.id_evento = ev.id)
        UNION
         SELECT (((((campos_modificados.nombre_campo)::text || ':'::text) || COALESCE(campos_modificados.valor_anterior, ''::text)) || '->'::text) || COALESCE(campos_modificados.valor_nuevo, ''::text))
           FROM auditoria_historico.campos_modificados
          WHERE (campos_modificados.id_registro = reg.id)), '<br>'::text) AS campos
   FROM (((((auditoria_historico.eventos ev
     LEFT JOIN auditoria_historico.registros_modificados reg ON ((reg.id_evento = ev.id)))
     JOIN public.lang_sys_entidades en ON (((en.id_entidad = ev.id_entidad) AND (en.id_idioma = (public.valor_variable_de_session('session.id_idioma'::text, '1'::text))::integer))))
     LEFT JOIN auditoria.lang_tipos_operaciones acc ON (((acc.id = 4) AND (acc.id_idioma = en.id_idioma))))
     LEFT JOIN auditoria.lang_tipos_operaciones top ON (((top.id = reg.id_tipo_operacion) AND (top.id_idioma = en.id_idioma))))
     LEFT JOIN public.sys_operadores op ON ((op.id = ev.id_operador)));


ALTER TABLE auditoria_historico.vista_general OWNER TO spi40;

--
-- Name: cfg_configuraciones_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.cfg_configuraciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.cfg_configuraciones_id_seq OWNER TO spi40;

--
-- Name: cfg_configuraciones; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.cfg_configuraciones (
    id integer DEFAULT nextval('public.cfg_configuraciones_id_seq'::regclass) NOT NULL,
    constante character varying(100) NOT NULL,
    valor text,
    funcion_cargar character varying(50) DEFAULT ''::character varying,
    funcion_validar character varying(50) DEFAULT ''::character varying,
    funcion_guardar character varying(50) DEFAULT ''::character varying,
    id_grupo integer NOT NULL,
    oculto smallint DEFAULT 0 NOT NULL,
    orden integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.cfg_configuraciones OWNER TO spi40;

--
-- Name: cfg_grupos_configuraciones; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.cfg_grupos_configuraciones (
    id integer NOT NULL
);


ALTER TABLE public.cfg_grupos_configuraciones OWNER TO spi40;

--
-- Name: cfg_servidores_grupos_servidores; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.cfg_servidores_grupos_servidores (
    id_servidor integer NOT NULL,
    id_grupo integer NOT NULL
);


ALTER TABLE public.cfg_servidores_grupos_servidores OWNER TO spi40;

--
-- Name: cfg_servidores_spi; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.cfg_servidores_spi (
    id integer NOT NULL,
    descripcion character varying(10) NOT NULL,
    url_webservice character varying(150) DEFAULT ''::character varying NOT NULL,
    es_grupo boolean DEFAULT false NOT NULL
);


ALTER TABLE public.cfg_servidores_spi OWNER TO spi40;

--
-- Name: cfg_servidores_spi_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.cfg_servidores_spi_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.cfg_servidores_spi_id_seq OWNER TO spi40;

--
-- Name: cfg_servidores_spi_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.cfg_servidores_spi_id_seq OWNED BY public.cfg_servidores_spi.id;


--
-- Name: dhcp_campos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.dhcp_campos (
    id_tipo_objeto integer NOT NULL,
    orden integer NOT NULL,
    descripcion character varying(50),
    por_defecto character varying(50),
    extendido boolean DEFAULT false NOT NULL,
    id_tipo_dato integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.dhcp_campos OWNER TO spi40;

--
-- Name: dhcp_campos_objetos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.dhcp_campos_objetos (
    id_objeto integer NOT NULL,
    id_tipo_objeto integer NOT NULL,
    orden integer NOT NULL,
    dato text NOT NULL
);


ALTER TABLE public.dhcp_campos_objetos OWNER TO spi40;

--
-- Name: dhcp_mapa_tipos_objetos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.dhcp_mapa_tipos_objetos (
    id_padre integer NOT NULL,
    id_hijo integer NOT NULL
);


ALTER TABLE public.dhcp_mapa_tipos_objetos OWNER TO spi40;

--
-- Name: dhcp_objetos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.dhcp_objetos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.dhcp_objetos_id_seq OWNER TO spi40;

--
-- Name: dhcp_objetos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.dhcp_objetos (
    id integer DEFAULT nextval('public.dhcp_objetos_id_seq'::regclass) NOT NULL,
    id_tipo_objeto integer NOT NULL,
    id_padre integer NOT NULL,
    estado smallint DEFAULT 1 NOT NULL,
    id_servidor_grupo integer,
    orden double precision DEFAULT 0 NOT NULL,
    ipv smallint DEFAULT 4 NOT NULL
);


ALTER TABLE public.dhcp_objetos OWNER TO spi40;

--
-- Name: dhcp_opciones_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.dhcp_opciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.dhcp_opciones_id_seq OWNER TO spi40;

--
-- Name: dhcp_opciones; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.dhcp_opciones (
    id integer DEFAULT nextval('public.dhcp_opciones_id_seq'::regclass) NOT NULL,
    nombre character varying(50) NOT NULL,
    descripcion text,
    tipo character(1) DEFAULT 'O'::bpchar NOT NULL,
    repetible boolean DEFAULT false,
    id_especial integer DEFAULT 0,
    code_especial integer DEFAULT 0,
    tipo_especial text DEFAULT ''::text,
    extendido boolean DEFAULT false,
    id_tipo_dato integer DEFAULT 0 NOT NULL,
    ipv smallint DEFAULT 4 NOT NULL
);


ALTER TABLE public.dhcp_opciones OWNER TO spi40;

--
-- Name: dhcp_opciones_especiales; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.dhcp_opciones_especiales (
    id integer NOT NULL,
    space text DEFAULT ''::text NOT NULL,
    code integer NOT NULL,
    ipv smallint DEFAULT 4 NOT NULL,
    parametros character varying(100) DEFAULT ''::character varying
);


ALTER TABLE public.dhcp_opciones_especiales OWNER TO spi40;

--
-- Name: dhcp_opciones_objetos_contador_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.dhcp_opciones_objetos_contador_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.dhcp_opciones_objetos_contador_seq OWNER TO spi40;

--
-- Name: dhcp_opciones_objetos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.dhcp_opciones_objetos (
    id_objeto integer NOT NULL,
    id_opcion integer NOT NULL,
    dato text NOT NULL,
    contador integer DEFAULT nextval('public.dhcp_opciones_objetos_contador_seq'::regclass) NOT NULL,
    estado smallint DEFAULT 1 NOT NULL,
    id_servidor_grupo integer,
    orden double precision DEFAULT 0 NOT NULL,
    ipv smallint DEFAULT 4 NOT NULL
);


ALTER TABLE public.dhcp_opciones_objetos OWNER TO spi40;

--
-- Name: dhcp_tipos_datos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.dhcp_tipos_datos (
    id integer NOT NULL,
    descripcion text DEFAULT ''::text NOT NULL,
    regexp text DEFAULT '.*'::text NOT NULL
);


ALTER TABLE public.dhcp_tipos_datos OWNER TO spi40;

--
-- Name: dhcp_tipos_objetos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.dhcp_tipos_objetos (
    id integer NOT NULL,
    clausula_declarativa character varying(30) NOT NULL,
    no_cerrar boolean DEFAULT false NOT NULL,
    orden integer DEFAULT 0 NOT NULL,
    ipv smallint DEFAULT 4 NOT NULL
);


ALTER TABLE public.dhcp_tipos_objetos OWNER TO spi40;

--
-- Name: lang_cfg_configuraciones; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_cfg_configuraciones (
    id_configuracion integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.lang_cfg_configuraciones OWNER TO spi40;

--
-- Name: lang_cfg_grupos_configuraciones; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_cfg_grupos_configuraciones (
    id_grupo integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.lang_cfg_grupos_configuraciones OWNER TO spi40;

--
-- Name: lang_mensajes_varios; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_mensajes_varios (
    id integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.lang_mensajes_varios OWNER TO spi40;

--
-- Name: lang_mensajes_varios_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.lang_mensajes_varios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.lang_mensajes_varios_id_seq OWNER TO spi40;

--
-- Name: lang_mensajes_varios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.lang_mensajes_varios_id_seq OWNED BY public.lang_mensajes_varios.id;


--
-- Name: lang_svc_dependencias; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_svc_dependencias (
    id_dependencia integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion character varying(50),
    descripcion_larga text
);


ALTER TABLE public.lang_svc_dependencias OWNER TO spi40;

--
-- Name: lang_svc_propiedades; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_svc_propiedades (
    id_propiedad integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion character varying(100)
);


ALTER TABLE public.lang_svc_propiedades OWNER TO spi40;

--
-- Name: lang_svc_requisitos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_svc_requisitos (
    id_requisito integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion character varying(50),
    descripcion_larga text
);


ALTER TABLE public.lang_svc_requisitos OWNER TO spi40;

--
-- Name: lang_svc_tipos_servicios; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_svc_tipos_servicios (
    id_tipo_servicio integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion character varying(50)
);


ALTER TABLE public.lang_svc_tipos_servicios OWNER TO spi40;

--
-- Name: lang_sys_abns; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_sys_abns (
    id_abn integer NOT NULL,
    id_idioma integer NOT NULL,
    nombre character varying(50) DEFAULT ''::character varying NOT NULL,
    descripcion text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.lang_sys_abns OWNER TO spi40;

--
-- Name: lang_sys_estados; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_sys_estados (
    id_tipo_estado integer NOT NULL,
    id_estado integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion character varying(50) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE public.lang_sys_estados OWNER TO spi40;

--
-- Name: COLUMN lang_sys_estados.id_tipo_estado; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.lang_sys_estados.id_tipo_estado IS '0=packs_clientes, 1=servicios_clientes, 2=tipos_packs, 3=dispositivos, 4=eventos, 5=columnas_domicilio';


--
-- Name: lang_sys_listados; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_sys_listados (
    id_listado integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion character varying(50) DEFAULT ''::character varying NOT NULL,
    columnas text NOT NULL,
    orientacion_papel character varying(10) DEFAULT 'portrait'::character varying NOT NULL
);


ALTER TABLE public.lang_sys_listados OWNER TO spi40;

--
-- Name: COLUMN lang_sys_listados.orientacion_papel; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.lang_sys_listados.orientacion_papel IS 'debe ser portrait o landscape';


--
-- Name: lang_sys_plugins; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_sys_plugins (
    id_plugin integer NOT NULL,
    id_idioma integer NOT NULL,
    nombre character varying(50) DEFAULT ''::character varying NOT NULL,
    descripcion text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.lang_sys_plugins OWNER TO spi40;

--
-- Name: lang_sys_tipos_eventos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_sys_tipos_eventos (
    id_tipo_evento integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion character varying(100) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE public.lang_sys_tipos_eventos OWNER TO spi40;

--
-- Name: lang_tablas_auditoria; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_tablas_auditoria (
    id_tabla_auditoria integer NOT NULL,
    id_idioma integer NOT NULL,
    nombre character varying(50)
);


ALTER TABLE public.lang_tablas_auditoria OWNER TO spi40;

--
-- Name: lang_tablas_auditoria_id_idioma_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.lang_tablas_auditoria_id_idioma_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.lang_tablas_auditoria_id_idioma_seq OWNER TO spi40;

--
-- Name: lang_tablas_auditoria_id_idioma_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.lang_tablas_auditoria_id_idioma_seq OWNED BY public.lang_tablas_auditoria.id_idioma;


--
-- Name: lang_tablas_auditoria_id_tabla_auditoria_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.lang_tablas_auditoria_id_tabla_auditoria_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.lang_tablas_auditoria_id_tabla_auditoria_seq OWNER TO spi40;

--
-- Name: lang_tablas_auditoria_id_tabla_auditoria_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.lang_tablas_auditoria_id_tabla_auditoria_seq OWNED BY public.lang_tablas_auditoria.id_tabla_auditoria;


--
-- Name: lang_tec_objetos_monitoreo_columnas_extras; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_tec_objetos_monitoreo_columnas_extras (
    id_columna integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion_columna character varying(50) DEFAULT ''::character varying NOT NULL,
    consulta_columna text NOT NULL,
    alineacion_columna character varying(10) DEFAULT 'center'::character varying NOT NULL,
    filtro_columna text NOT NULL,
    boton_extra text NOT NULL
);


ALTER TABLE public.lang_tec_objetos_monitoreo_columnas_extras OWNER TO spi40;

--
-- Name: lang_tec_propiedades_dispositivos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_tec_propiedades_dispositivos (
    id_propiedad_dispositivo integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion character varying(50)
);


ALTER TABLE public.lang_tec_propiedades_dispositivos OWNER TO spi40;

--
-- Name: lang_tec_propiedades_interfaces; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_tec_propiedades_interfaces (
    id_propiedad_interface integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion character varying(50),
    descripcion_larga text
);


ALTER TABLE public.lang_tec_propiedades_interfaces OWNER TO spi40;

--
-- Name: lang_tec_tipos_tecnologias; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.lang_tec_tipos_tecnologias (
    id_tipo_tecnologia integer NOT NULL,
    id_idioma integer NOT NULL,
    descripcion character varying(50)
);


ALTER TABLE public.lang_tec_tipos_tecnologias OWNER TO spi40;

--
-- Name: newsletter_destinatarios; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.newsletter_destinatarios (
    id integer NOT NULL,
    id_tarea integer NOT NULL,
    id_cliente integer NOT NULL,
    estado integer NOT NULL
);


ALTER TABLE public.newsletter_destinatarios OWNER TO spi40;

--
-- Name: newsletter_destinatarios_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.newsletter_destinatarios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.newsletter_destinatarios_id_seq OWNER TO spi40;

--
-- Name: newsletter_destinatarios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.newsletter_destinatarios_id_seq OWNED BY public.newsletter_destinatarios.id;


--
-- Name: newsletter_filtros_plugins; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.newsletter_filtros_plugins (
    id integer NOT NULL,
    id_plugin integer NOT NULL,
    descripcion character varying(50),
    funcion_carga character varying(50),
    funcion_mostrar character varying(50),
    funcion_buscar character varying(50),
    estado text
);


ALTER TABLE public.newsletter_filtros_plugins OWNER TO spi40;

--
-- Name: newsletter_filtros_plugins_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.newsletter_filtros_plugins_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.newsletter_filtros_plugins_id_seq OWNER TO spi40;

--
-- Name: newsletter_filtros_plugins_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.newsletter_filtros_plugins_id_seq OWNED BY public.newsletter_filtros_plugins.id;


--
-- Name: newsletter_plantillas; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.newsletter_plantillas (
    id integer NOT NULL,
    name character varying(50),
    body text,
    type integer DEFAULT 0
);


ALTER TABLE public.newsletter_plantillas OWNER TO spi40;

--
-- Name: newsletter_plantillas_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.newsletter_plantillas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.newsletter_plantillas_id_seq OWNER TO spi40;

--
-- Name: newsletter_plantillas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.newsletter_plantillas_id_seq OWNED BY public.newsletter_plantillas.id;


--
-- Name: newsletter_tareas; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.newsletter_tareas (
    id integer NOT NULL,
    fecha_ini timestamp without time zone DEFAULT now(),
    fecha_fin timestamp without time zone,
    fecha_modificacion timestamp without time zone,
    de character varying(50) NOT NULL,
    cc character varying(100),
    cco character varying(100),
    subject character varying(100) NOT NULL,
    priority integer NOT NULL,
    body text,
    estado integer NOT NULL
);


ALTER TABLE public.newsletter_tareas OWNER TO spi40;

--
-- Name: newsletter_tareas_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.newsletter_tareas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.newsletter_tareas_id_seq OWNER TO spi40;

--
-- Name: newsletter_tareas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.newsletter_tareas_id_seq OWNED BY public.newsletter_tareas.id;


--
-- Name: plg_1000_cm_dispositivos_interfaces_pools_ip; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_1000_cm_dispositivos_interfaces_pools_ip (
    id_dispositivo integer NOT NULL,
    id integer NOT NULL,
    id_pool integer NOT NULL
);


ALTER TABLE public.plg_1000_cm_dispositivos_interfaces_pools_ip OWNER TO spi40;

--
-- Name: plg_1000_cm_listado_cms_clientes; Type: VIEW; Schema: public; Owner: spi40
--

CREATE VIEW public.plg_1000_cm_listado_cms_clientes AS
 SELECT dis.id AS id_cm,
    (((mar.nombre)::text || ' '::text) || (mod.descripcion)::text) AS modelo_cm,
    dis.estado AS estado_cm,
    est.descripcion AS descripcion_estado_cm,
    ded.valor AS hfc_cm,
    ( SELECT tec_dispositivos_etiquetas_dispositivos.valor
           FROM public.tec_dispositivos_etiquetas_dispositivos
          WHERE ((tec_dispositivos_etiquetas_dispositivos.id_dispositivo = dis.id) AND (tec_dispositivos_etiquetas_dispositivos.id_etiqueta = 1003))) AS usb_cm,
    ( SELECT tec_dispositivos_etiquetas_dispositivos.valor
           FROM public.tec_dispositivos_etiquetas_dispositivos
          WHERE ((tec_dispositivos_etiquetas_dispositivos.id_dispositivo = dis.id) AND (tec_dispositivos_etiquetas_dispositivos.id_etiqueta = 1004))) AS mta_cm,
    ( SELECT tec_dispositivos_etiquetas_dispositivos.valor
           FROM public.tec_dispositivos_etiquetas_dispositivos
          WHERE ((tec_dispositivos_etiquetas_dispositivos.id_dispositivo = dis.id) AND (tec_dispositivos_etiquetas_dispositivos.id_etiqueta = 1005))) AS eth_cm,
    ( SELECT tec_dispositivos_etiquetas_dispositivos.valor
           FROM public.tec_dispositivos_etiquetas_dispositivos
          WHERE ((tec_dispositivos_etiquetas_dispositivos.id_dispositivo = dis.id) AND (tec_dispositivos_etiquetas_dispositivos.id_etiqueta = 1001))) AS serial_cm,
    cli.id AS id_cli,
    cli.denominacion AS denominacion_cli,
    cli.responsable AS responsable_cli,
    lc.calle AS calle_cli,
    lc.numero AS numero_cli,
    public.domicilio_locacion(lc.id) AS direccion_cli,
    lcp.estado AS estado_pack,
    lcps.estado AS estado_ser,
    public.estado_servicio(lcps.id) AS estado_efectivo_ser,
    est1.descripcion AS descripcion_estado_efectivo_ser
   FROM ((((((((((public.tec_modelos mod
     JOIN public.tec_marcas mar ON ((mar.id = mod.id_marca)))
     JOIN public.tec_dispositivos dis ON ((dis.id_modelo = mod.id)))
     JOIN public.lang_sys_estados est ON (((est.id_tipo_estado = 3) AND (est.id_estado = dis.estado) AND (est.id_idioma = (public.valor_variable_de_session('id_idioma'::text, '1'::text))::integer))))
     JOIN public.tec_dispositivos_etiquetas_dispositivos ded ON (((ded.id_dispositivo = dis.id) AND (ded.id_etiqueta = 1002))))
     LEFT JOIN public.svc_servicios_propiedades sp ON (((sp.valor = (dis.id)::text) AND (sp.id_propiedad = 1003))))
     LEFT JOIN public.com_locaciones_clientes_packs_servicios lcps ON ((lcps.id = sp.id_locacion_cliente_pack_servicio)))
     LEFT JOIN public.com_locaciones_clientes_packs lcp ON ((lcp.id = lcps.id_locacion_cliente_pack)))
     JOIN public.lang_sys_estados est1 ON (((est1.id_tipo_estado = 1) AND (est1.id_estado = public.estado_servicio(lcps.id)) AND (est1.id_idioma = (public.valor_variable_de_session('id_idioma'::text, '1'::text))::integer))))
     LEFT JOIN public.com_locaciones_clientes lc ON ((lc.id = lcp.id_locacion_cliente)))
     LEFT JOIN public.com_clientes cli ON ((cli.id = lc.id_cliente)))
  WHERE (mod.id_tipo_dispositivo = 1000);


ALTER TABLE public.plg_1000_cm_listado_cms_clientes OWNER TO spi40;

--
-- Name: tec_dispositivos_propiedades_dispositivos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_dispositivos_propiedades_dispositivos (
    id_dispositivo integer NOT NULL,
    id_propiedad integer NOT NULL,
    valor text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.tec_dispositivos_propiedades_dispositivos OWNER TO spi40;

--
-- Name: plg_1000_cm_listado_ip_fijas; Type: VIEW; Schema: public; Owner: spi40
--

CREATE VIEW public.plg_1000_cm_listado_ip_fijas AS
 SELECT cli.id AS id_cli,
    cli.denominacion AS denominacion_cli,
    public.domicilio_locacion(lc.id) AS direccion_loc,
    lc.id AS id_locacion,
    lcp.id AS id_pack,
    lcps.id AS id_servicio,
    sp.valor AS ip_fija,
    sp1.valor AS mac_cpe,
    zon.descripcion AS zona,
    lcps.id AS id_estado,
    public.estado_servicio(lcps.id) AS id_estado_efectivo,
    est.descripcion AS estado,
    ( SELECT dis1.descripcion
           FROM (((((public.com_locaciones_clientes_packs_servicios lcps_1
             JOIN public.svc_servicios_propiedades sp_1 ON (((sp_1.id_locacion_cliente_pack_servicio = lcps_1.id) AND (sp_1.id_propiedad = 1003))))
             JOIN public.tec_dispositivos dis ON (((dis.id)::text = sp_1.valor)))
             JOIN public.tec_dispositivos_etiquetas_dispositivos et ON (((et.id_dispositivo = dis.id) AND (et.id_etiqueta = 1002))))
             JOIN public.tec_dispositivos_propiedades_dispositivos pd ON (((pd.id_dispositivo = dis.id) AND (pd.id_propiedad = 1009))))
             JOIN public.tec_dispositivos dis1 ON (((dis1.id)::text = pd.valor)))
          WHERE (lcps_1.id_locacion_cliente_pack = lcp.id)) AS cmts
   FROM (((((((public.com_clientes cli
     JOIN public.com_locaciones_clientes lc ON ((lc.id_cliente = cli.id)))
     JOIN public.com_locaciones_clientes_packs lcp ON ((lcp.id_locacion_cliente = lc.id)))
     JOIN public.com_locaciones_clientes_packs_servicios lcps ON ((lcps.id_locacion_cliente_pack = lcp.id)))
     JOIN public.tec_zonas zon ON ((zon.id = lc.id_zona)))
     JOIN public.svc_servicios_propiedades sp ON (((sp.id_locacion_cliente_pack_servicio = lcps.id) AND (sp.id_propiedad = 1004))))
     JOIN public.svc_servicios_propiedades sp1 ON (((sp1.id_locacion_cliente_pack_servicio = lcps.id) AND (sp1.id_propiedad = 1005))))
     JOIN public.lang_sys_estados est ON (((est.id_tipo_estado = 1) AND (est.id_estado = public.estado_servicio(lcps.id)) AND (est.id_idioma = (public.valor_variable_de_session('id_idioma'::text, '1'::text))::integer))));


ALTER TABLE public.plg_1000_cm_listado_ip_fijas OWNER TO spi40;

--
-- Name: plg_1000_cm_modelos_explog; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_1000_cm_modelos_explog (
    id integer NOT NULL,
    id_modelo integer NOT NULL,
    explog text NOT NULL
);


ALTER TABLE public.plg_1000_cm_modelos_explog OWNER TO spi40;

--
-- Name: plg_1000_cm_modelos_explog_especifica; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_1000_cm_modelos_explog_especifica (
    id integer NOT NULL,
    id_modelo integer NOT NULL,
    explog text NOT NULL,
    descripcion character varying(50) NOT NULL
);


ALTER TABLE public.plg_1000_cm_modelos_explog_especifica OWNER TO spi40;

--
-- Name: plg_1000_cm_modelos_explog_especifica_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.plg_1000_cm_modelos_explog_especifica_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.plg_1000_cm_modelos_explog_especifica_id_seq OWNER TO spi40;

--
-- Name: plg_1000_cm_modelos_explog_especifica_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.plg_1000_cm_modelos_explog_especifica_id_seq OWNED BY public.plg_1000_cm_modelos_explog_especifica.id;


--
-- Name: plg_1000_cm_modelos_explog_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.plg_1000_cm_modelos_explog_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.plg_1000_cm_modelos_explog_id_seq OWNER TO spi40;

--
-- Name: plg_1000_cm_modelos_explog_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.plg_1000_cm_modelos_explog_id_seq OWNED BY public.plg_1000_cm_modelos_explog.id;


--
-- Name: plg_1000_cm_modelos_ipv6; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_1000_cm_modelos_ipv6 (
    id integer NOT NULL,
    id_modelo integer NOT NULL,
    ipv6 smallint DEFAULT 0 NOT NULL
);


ALTER TABLE public.plg_1000_cm_modelos_ipv6 OWNER TO spi40;

--
-- Name: plg_1000_cm_modelos_ipv6_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.plg_1000_cm_modelos_ipv6_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.plg_1000_cm_modelos_ipv6_id_seq OWNER TO spi40;

--
-- Name: plg_1000_cm_modelos_ipv6_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.plg_1000_cm_modelos_ipv6_id_seq OWNED BY public.plg_1000_cm_modelos_ipv6.id;


--
-- Name: plg_1000_cm_servicios_explog; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_1000_cm_servicios_explog (
    id integer NOT NULL,
    id_modelo integer,
    id_explog_especifica integer,
    id_servicio integer,
    id_grupo integer,
    nombre_archivo character varying(50) NOT NULL
);


ALTER TABLE public.plg_1000_cm_servicios_explog OWNER TO spi40;

--
-- Name: plg_1000_cm_servicios_explog_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.plg_1000_cm_servicios_explog_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.plg_1000_cm_servicios_explog_id_seq OWNER TO spi40;

--
-- Name: plg_1000_cm_servicios_explog_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.plg_1000_cm_servicios_explog_id_seq OWNED BY public.plg_1000_cm_servicios_explog.id;


--
-- Name: plg_1000_cm_templates_cm; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_1000_cm_templates_cm (
    id integer NOT NULL,
    descripcion character varying(50),
    template text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.plg_1000_cm_templates_cm OWNER TO spi40;

--
-- Name: plg_1000_cm_templates_cm_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.plg_1000_cm_templates_cm_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.plg_1000_cm_templates_cm_id_seq OWNER TO spi40;

--
-- Name: plg_1000_cm_templates_cm_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.plg_1000_cm_templates_cm_id_seq OWNED BY public.plg_1000_cm_templates_cm.id;


--
-- Name: plg_13000_neutralidad_listado_servicios_archivo_especial; Type: VIEW; Schema: public; Owner: spi40
--

CREATE VIEW public.plg_13000_neutralidad_listado_servicios_archivo_especial AS
 SELECT cli.id AS id_cli,
    cli.denominacion AS denominacion_cli,
    public.domicilio_locacion(lc.id) AS direccion_cli,
    (((mar.nombre)::text || ' '::text) || (mod.descripcion)::text) AS modelo_cm,
    dis.estado AS estado_cm,
    ded.valor AS hfc_cm,
    sp1.valor AS archivo_especial
   FROM (((((((((public.tec_modelos mod
     JOIN public.tec_marcas mar ON (((mar.id = mod.id_marca) AND (mod.id_tipo_dispositivo = 1000))))
     JOIN public.tec_dispositivos dis ON ((dis.id_modelo = mod.id)))
     JOIN public.tec_dispositivos_etiquetas_dispositivos ded ON (((ded.id_dispositivo = dis.id) AND (ded.id_etiqueta = 1002))))
     JOIN public.svc_servicios_propiedades sp ON (((sp.valor = (dis.id)::text) AND (sp.id_propiedad = 1003))))
     JOIN public.svc_servicios_propiedades sp1 ON (((sp.id_locacion_cliente_pack_servicio = sp1.id_locacion_cliente_pack_servicio) AND (sp1.id_propiedad = 1002) AND (sp1.valor <> ''::text))))
     JOIN public.com_locaciones_clientes_packs_servicios lcps ON ((lcps.id = sp1.id_locacion_cliente_pack_servicio)))
     JOIN public.com_locaciones_clientes_packs lcp ON ((lcp.id = lcps.id_locacion_cliente_pack)))
     JOIN public.com_locaciones_clientes lc ON ((lc.id = lcp.id_locacion_cliente)))
     JOIN public.com_clientes cli ON ((cli.id = lc.id_cliente)));


ALTER TABLE public.plg_13000_neutralidad_listado_servicios_archivo_especial OWNER TO spi40;

--
-- Name: plg_14000_alertas; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_14000_alertas (
    id integer NOT NULL,
    descripcion character varying(70) NOT NULL,
    id_objeto_monitoreo integer,
    columna_objeto_monitoreo smallint DEFAULT 1,
    tipo_alerta smallint DEFAULT 0 NOT NULL,
    modo_desactivacion smallint DEFAULT 0 NOT NULL,
    valor1 character varying(20) NOT NULL,
    valor2 character varying(20),
    estado smallint DEFAULT 1 NOT NULL,
    activada smallint DEFAULT 0 NOT NULL,
    script character varying(150),
    mensaje character varying(500) DEFAULT ''::character varying NOT NULL,
    id_alerta_padre integer,
    modo_evaluacion smallint DEFAULT 0 NOT NULL,
    timestamp_ultimo_mensaje timestamp without time zone DEFAULT now() NOT NULL,
    texto_ultimo_mensaje character varying(500) DEFAULT ''::character varying NOT NULL,
    cant_fallas_para_activar integer DEFAULT 1 NOT NULL,
    cant_nan_para_activar integer DEFAULT 1 NOT NULL,
    contador_fallas integer DEFAULT 0 NOT NULL,
    contador_nan integer DEFAULT 0 NOT NULL,
    informar_auto_desactivacion smallint DEFAULT 0 NOT NULL,
    id_categoria integer DEFAULT 0 NOT NULL,
    timestamp_ultima_muestra integer DEFAULT 0 NOT NULL,
    id_dispositivo integer,
    json_fms text DEFAULT ''::text NOT NULL,
    json_script text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.plg_14000_alertas OWNER TO spi40;

--
-- Name: COLUMN plg_14000_alertas.tipo_alerta; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.plg_14000_alertas.tipo_alerta IS '0: Val Absoluto -> obj >= valor1
        1: Val Absoluto -> obj <= valor1
        2: 0: Val Absoluto -> valor1 >= obj >= valor2
        3: Val Relativo -> valor1% mas que promedio de <valor2> ?ltimos objs
        4: Val Relativo -> valor1% menos que promedio de <valor2> ?ltimos objs';


--
-- Name: COLUMN plg_14000_alertas.modo_desactivacion; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.plg_14000_alertas.modo_desactivacion IS '0: Automatica -> se desactiva sola cuando el obj vuelve a los valores normales.
        1: Manual -> Si o si hay que desactivarla manualmente
        ';


--
-- Name: plg_14000_alertas_alertas_notificaciones; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_14000_alertas_alertas_notificaciones (
    id_alerta integer NOT NULL,
    id_alerta_notificacion integer NOT NULL,
    modo_notificacion smallint DEFAULT 0 NOT NULL,
    agenda text,
    cuenta_notificacion integer DEFAULT 0 NOT NULL,
    tiempo_entre_notificaciones integer DEFAULT 1 NOT NULL,
    timestamp_ultima_notificacion bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.plg_14000_alertas_alertas_notificaciones OWNER TO spi40;

--
-- Name: COLUMN plg_14000_alertas_alertas_notificaciones.modo_notificacion; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.plg_14000_alertas_alertas_notificaciones.modo_notificacion IS '0: Permanente -> Sigue notificando hasta que la alarma se desactive
n: Notifica por n veces';


--
-- Name: COLUMN plg_14000_alertas_alertas_notificaciones.cuenta_notificacion; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.plg_14000_alertas_alertas_notificaciones.cuenta_notificacion IS 'El ABN suma 1 cada vez que se notifica, y lo pone a 0 cuando la alerta está desactivada.';


--
-- Name: plg_14000_alertas_categorias; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_14000_alertas_categorias (
    id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    color_bg character varying(7) NOT NULL,
    color_fg character varying(7) NOT NULL
);


ALTER TABLE public.plg_14000_alertas_categorias OWNER TO spi40;

--
-- Name: plg_14000_alertas_categorias_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.plg_14000_alertas_categorias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.plg_14000_alertas_categorias_id_seq OWNER TO spi40;

--
-- Name: plg_14000_alertas_categorias_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.plg_14000_alertas_categorias_id_seq OWNED BY public.plg_14000_alertas_categorias.id;


--
-- Name: plg_14000_alertas_contactos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_14000_alertas_contactos (
    id integer NOT NULL,
    nombre character varying(100) NOT NULL,
    es_grupo smallint DEFAULT 0 NOT NULL,
    telefono_fijo character varying(50),
    telefono_movil character varying(50),
    email_sms character varying(100),
    email character varying(100),
    beeper character varying(50)
);


ALTER TABLE public.plg_14000_alertas_contactos OWNER TO spi40;

--
-- Name: plg_14000_alertas_contactos_alertas_contactos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_14000_alertas_contactos_alertas_contactos (
    id_alerta_contacto_grupo integer NOT NULL,
    alerta_contacto_nodo integer NOT NULL
);


ALTER TABLE public.plg_14000_alertas_contactos_alertas_contactos OWNER TO spi40;

--
-- Name: plg_14000_alertas_contactos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.plg_14000_alertas_contactos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.plg_14000_alertas_contactos_id_seq OWNER TO spi40;

--
-- Name: plg_14000_alertas_contactos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.plg_14000_alertas_contactos_id_seq OWNED BY public.plg_14000_alertas_contactos.id;


--
-- Name: plg_14000_alertas_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.plg_14000_alertas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.plg_14000_alertas_id_seq OWNER TO spi40;

--
-- Name: plg_14000_alertas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.plg_14000_alertas_id_seq OWNED BY public.plg_14000_alertas.id;


--
-- Name: plg_14000_alertas_logs; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_14000_alertas_logs (
    id integer NOT NULL,
    "timestamp" timestamp without time zone DEFAULT now(),
    id_alerta integer NOT NULL,
    id_notificacion integer,
    id_contacto integer,
    id_operador_desactivo integer,
    mensaje character varying(500) DEFAULT ''::character varying NOT NULL,
    id_tipo_mensaje smallint
);


ALTER TABLE public.plg_14000_alertas_logs OWNER TO spi40;

--
-- Name: COLUMN plg_14000_alertas_logs.id_tipo_mensaje; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.plg_14000_alertas_logs.id_tipo_mensaje IS '1=activacion de alerta
                             2=desactivacion automatica
                             3=desactivacion manual
                             4=envio de notificacion
                             5=Parametro fuera de rango o NAN
                             6=Error en envio de notificacion';


--
-- Name: tec_objetos_monitoreo_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_objetos_monitoreo_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_objetos_monitoreo_id_seq OWNER TO spi40;

--
-- Name: tec_objetos_monitoreo; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_objetos_monitoreo (
    id integer DEFAULT nextval('public.tec_objetos_monitoreo_id_seq'::regclass) NOT NULL,
    id_interface integer NOT NULL,
    descripcion character varying(100),
    estado smallint DEFAULT 0 NOT NULL,
    archivo_datos character varying(100) NOT NULL,
    ancho_grafico integer DEFAULT 500 NOT NULL,
    alto_grafico integer DEFAULT 125 NOT NULL,
    id_plantilla_objetos_monitoreo integer NOT NULL,
    periodo integer DEFAULT 300 NOT NULL,
    ultimo_registro bigint,
    titulo character varying(100) DEFAULT ''::character varying NOT NULL,
    titulo_vertical character varying(50) DEFAULT ''::character varying NOT NULL,
    color_fondo character varying(7) DEFAULT '#eeeeee'::character varying NOT NULL,
    color_fondo_grafico character varying(7) DEFAULT '#ffffff'::character varying NOT NULL,
    parametro_extra character varying(100) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE public.tec_objetos_monitoreo OWNER TO spi40;

--
-- Name: plg_14000_alertas_listado_logs_alertas; Type: VIEW; Schema: public; Owner: spi40
--

CREATE VIEW public.plg_14000_alertas_listado_logs_alertas AS
 SELECT al.id,
    al.id_alerta,
    ta.descripcion,
    (((((td.descripcion)::text || ' - '::text) || (tdi.ifalias)::text) || ' - '::text) || (tom.descripcion)::text) AS dispositivo,
    al."timestamp",
        CASE
            WHEN (ta.activada = 1) THEN ((('<label class="error">'::text || (lse.descripcion)::text) || '</label>'::text))::character varying
            ELSE lse.descripcion
        END AS estado,
    al.mensaje,
    op.nombre AS operador,
    lse1.descripcion AS tipo_mensaje
   FROM (((((((public.plg_14000_alertas_logs al
     JOIN public.plg_14000_alertas ta ON ((ta.id = al.id_alerta)))
     LEFT JOIN public.sys_operadores op ON ((op.id = al.id_operador_desactivo)))
     JOIN public.lang_sys_estados lse ON (((lse.id_tipo_estado = 14000) AND (lse.id_idioma = 1) AND (lse.id_estado = ta.activada))))
     LEFT JOIN public.tec_objetos_monitoreo tom ON ((tom.id = ta.id_objeto_monitoreo)))
     LEFT JOIN public.tec_dispositivos_interfaces tdi ON ((tdi.id = tom.id_interface)))
     LEFT JOIN public.tec_dispositivos td ON ((td.id = tdi.id_dispositivo)))
     LEFT JOIN public.lang_sys_estados lse1 ON (((lse1.id_estado = al.id_tipo_mensaje) AND (lse1.id_tipo_estado = 14001) AND (lse1.id_idioma = 1))));


ALTER TABLE public.plg_14000_alertas_listado_logs_alertas OWNER TO spi40;

--
-- Name: plg_14000_alertas_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.plg_14000_alertas_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.plg_14000_alertas_logs_id_seq OWNER TO spi40;

--
-- Name: plg_14000_alertas_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.plg_14000_alertas_logs_id_seq OWNED BY public.plg_14000_alertas_logs.id;


--
-- Name: plg_14000_alertas_notificaciones; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_14000_alertas_notificaciones (
    id integer NOT NULL,
    nombre character varying(100) NOT NULL
);


ALTER TABLE public.plg_14000_alertas_notificaciones OWNER TO spi40;

--
-- Name: plg_14000_alertas_notificaciones_alertas_contactos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_14000_alertas_notificaciones_alertas_contactos (
    id_alerta_notificacion integer NOT NULL,
    id_alerta_contacto integer NOT NULL
);


ALTER TABLE public.plg_14000_alertas_notificaciones_alertas_contactos OWNER TO spi40;

--
-- Name: plg_14000_alertas_notificaciones_alertas_tipo_notificaciones; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_14000_alertas_notificaciones_alertas_tipo_notificaciones (
    id_alerta_notificacion integer NOT NULL,
    id_alerta_tipo_notificacion integer NOT NULL
);


ALTER TABLE public.plg_14000_alertas_notificaciones_alertas_tipo_notificaciones OWNER TO spi40;

--
-- Name: plg_14000_alertas_notificaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.plg_14000_alertas_notificaciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.plg_14000_alertas_notificaciones_id_seq OWNER TO spi40;

--
-- Name: plg_14000_alertas_notificaciones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.plg_14000_alertas_notificaciones_id_seq OWNED BY public.plg_14000_alertas_notificaciones.id;


--
-- Name: plg_14000_alertas_tipo_notificaciones; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.plg_14000_alertas_tipo_notificaciones (
    id integer NOT NULL,
    nombre character varying(50) NOT NULL,
    funcion_notificacion character varying(100) NOT NULL
);


ALTER TABLE public.plg_14000_alertas_tipo_notificaciones OWNER TO spi40;

--
-- Name: plg_14000_alertas_tipo_notificaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.plg_14000_alertas_tipo_notificaciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.plg_14000_alertas_tipo_notificaciones_id_seq OWNER TO spi40;

--
-- Name: plg_14000_alertas_tipo_notificaciones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.plg_14000_alertas_tipo_notificaciones_id_seq OWNED BY public.plg_14000_alertas_tipo_notificaciones.id;


--
-- Name: svc_dependencias_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.svc_dependencias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.svc_dependencias_id_seq OWNER TO spi40;

--
-- Name: svc_dependencias; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_dependencias (
    id integer DEFAULT nextval('public.svc_dependencias_id_seq'::regclass) NOT NULL,
    funcion character varying(50) NOT NULL,
    id_tipo_servicio integer NOT NULL,
    id_tipo_tecnologia integer NOT NULL
);


ALTER TABLE public.svc_dependencias OWNER TO spi40;

--
-- Name: svc_elegidos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_elegidos (
    id_seleccion integer NOT NULL,
    id_cliente integer,
    id_locacion_cliente integer,
    id_locacion_cliente_pack integer,
    id_locacion_cliente_pack_servicio integer,
    datos_extra text DEFAULT ''::text NOT NULL
);


ALTER TABLE public.svc_elegidos OWNER TO spi40;

--
-- Name: svc_propiedades_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.svc_propiedades_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.svc_propiedades_id_seq OWNER TO spi40;

--
-- Name: svc_propiedades; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_propiedades (
    id integer DEFAULT nextval('public.svc_propiedades_id_seq'::regclass) NOT NULL,
    heredable smallint DEFAULT 1 NOT NULL,
    funcion_carga character varying(50) DEFAULT 'cargar_texto'::character varying NOT NULL,
    funcion_validacion character varying(50) DEFAULT 'validar_texto'::character varying NOT NULL,
    funcion_guardado character varying(50) DEFAULT 'guardar_texto'::character varying NOT NULL,
    funcion_mostrar character varying(50) DEFAULT 'mostrar_texto'::character varying NOT NULL,
    funcion_valida_guarda_herencia character varying(50) DEFAULT 'validar_guardar_herencia'::character varying NOT NULL,
    orden_mostrado integer DEFAULT 0 NOT NULL,
    funcion_buscar character varying(50) DEFAULT ''::character varying NOT NULL,
    propiedad_secundaria smallint DEFAULT 0
);


ALTER TABLE public.svc_propiedades OWNER TO spi40;

--
-- Name: svc_requisitos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.svc_requisitos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.svc_requisitos_id_seq OWNER TO spi40;

--
-- Name: svc_requisitos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_requisitos (
    id integer DEFAULT nextval('public.svc_requisitos_id_seq'::regclass) NOT NULL,
    funcion character varying(50) NOT NULL,
    id_tipo_servicio integer NOT NULL,
    id_tipo_tecnologia integer NOT NULL
);


ALTER TABLE public.svc_requisitos OWNER TO spi40;

--
-- Name: svc_servicios_dependencias; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_servicios_dependencias (
    id_servicio integer NOT NULL,
    id_dependencia integer NOT NULL
);


ALTER TABLE public.svc_servicios_dependencias OWNER TO spi40;

--
-- Name: svc_servicios_requisitos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_servicios_requisitos (
    id_servicio integer NOT NULL,
    id_requisito integer NOT NULL
);


ALTER TABLE public.svc_servicios_requisitos OWNER TO spi40;

--
-- Name: svc_tipos_servicios_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.svc_tipos_servicios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.svc_tipos_servicios_id_seq OWNER TO spi40;

--
-- Name: svc_tipos_servicios; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_tipos_servicios (
    id integer DEFAULT nextval('public.svc_tipos_servicios_id_seq'::regclass) NOT NULL,
    cantidad_maxima smallint DEFAULT 0 NOT NULL,
    bloquear_carga boolean DEFAULT true NOT NULL,
    funcion_registro_eventos character varying(50) DEFAULT 'registrar_evento_servicio'::character varying NOT NULL,
    funcion_validar_estado character varying(50) DEFAULT 'validar_estado'::character varying NOT NULL,
    facturable boolean DEFAULT false NOT NULL
);


ALTER TABLE public.svc_tipos_servicios OWNER TO spi40;

--
-- Name: COLUMN svc_tipos_servicios.cantidad_maxima; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.svc_tipos_servicios.cantidad_maxima IS '0=excluyente, 1=unico, 2..99=multiple';


--
-- Name: svc_tipos_servicios_propiedades; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_tipos_servicios_propiedades (
    id_tipo_servicio integer NOT NULL,
    id_propiedad integer NOT NULL
);


ALTER TABLE public.svc_tipos_servicios_propiedades OWNER TO spi40;

--
-- Name: svc_tipos_servicios_propiedades_internas; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_tipos_servicios_propiedades_internas (
    id_tipo_servicio integer NOT NULL,
    id_propiedad integer NOT NULL
);


ALTER TABLE public.svc_tipos_servicios_propiedades_internas OWNER TO spi40;

--
-- Name: svc_tipos_servicios_tipos_tecnologias; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_tipos_servicios_tipos_tecnologias (
    id_tipo_servicio integer NOT NULL,
    id_tipo_tecnologia integer NOT NULL
);


ALTER TABLE public.svc_tipos_servicios_tipos_tecnologias OWNER TO spi40;

--
-- Name: svc_tipos_tecnologias_propiedades; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_tipos_tecnologias_propiedades (
    id_tipo_tecnologia integer NOT NULL,
    id_propiedad integer NOT NULL
);


ALTER TABLE public.svc_tipos_tecnologias_propiedades OWNER TO spi40;

--
-- Name: svc_tipos_tecnologias_propiedades_internas; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.svc_tipos_tecnologias_propiedades_internas (
    id_tipo_tecnologia integer NOT NULL,
    id_propiedad integer NOT NULL
);


ALTER TABLE public.svc_tipos_tecnologias_propiedades_internas OWNER TO spi40;

--
-- Name: sys_abns_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.sys_abns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sys_abns_id_seq OWNER TO spi40;

--
-- Name: sys_abns; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_abns (
    id integer DEFAULT nextval('public.sys_abns_id_seq'::regclass) NOT NULL,
    flag integer DEFAULT 0 NOT NULL,
    id_cfg_configuraciones integer NOT NULL,
    id_proceso integer DEFAULT 0 NOT NULL,
    contador_proceso integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.sys_abns OWNER TO spi40;

--
-- Name: TABLE sys_abns; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON TABLE public.sys_abns IS '0=notificacion, 1=alerta, 2=error';


--
-- Name: sys_abns_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.sys_abns_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sys_abns_logs_id_seq OWNER TO spi40;

--
-- Name: sys_abns_logs; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_abns_logs (
    id integer DEFAULT nextval('public.sys_abns_logs_id_seq'::regclass) NOT NULL,
    id_abn integer DEFAULT 0 NOT NULL,
    tipo_mensaje smallint DEFAULT 0,
    hora timestamp without time zone DEFAULT now(),
    mensaje text DEFAULT ''::text
);


ALTER TABLE public.sys_abns_logs OWNER TO spi40;

--
-- Name: sys_abns_tareas_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.sys_abns_tareas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sys_abns_tareas_id_seq OWNER TO spi40;

--
-- Name: sys_abns_tareas; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_abns_tareas (
    id integer DEFAULT nextval('public.sys_abns_tareas_id_seq'::regclass) NOT NULL,
    id_abn integer NOT NULL,
    prioridad double precision DEFAULT 0 NOT NULL,
    tarea text DEFAULT ''::text NOT NULL,
    "timestamp" bigint DEFAULT (date_part('epoch'::text, now()))::bigint NOT NULL,
    timestamp_ultimo_acceso bigint,
    descripcion character varying(200) DEFAULT ''::character varying NOT NULL,
    intentos_desencolar integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.sys_abns_tareas OWNER TO spi40;

--
-- Name: sys_entidades_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.sys_entidades_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sys_entidades_id_seq OWNER TO spi40;

--
-- Name: sys_entidades; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_entidades (
    id integer DEFAULT nextval('public.sys_entidades_id_seq'::regclass) NOT NULL,
    id_padre integer DEFAULT 1 NOT NULL,
    id_tipo integer NOT NULL,
    dato_adicional character varying(50) DEFAULT ''::character varying NOT NULL,
    orden smallint DEFAULT 0
);


ALTER TABLE public.sys_entidades OWNER TO spi40;

--
-- Name: sys_eventos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.sys_eventos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sys_eventos_id_seq OWNER TO spi40;

--
-- Name: sys_eventos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_eventos (
    id integer DEFAULT nextval('public.sys_eventos_id_seq'::regclass) NOT NULL,
    id_padre integer NOT NULL,
    id_cliente integer NOT NULL,
    id_locacion integer,
    id_pack integer,
    id_servicio integer,
    id_tipo_evento integer NOT NULL,
    "timestamp" bigint NOT NULL,
    estado smallint DEFAULT 0 NOT NULL,
    id_operador_origen integer NOT NULL,
    id_operador_destino integer NOT NULL,
    mensaje text
);


ALTER TABLE public.sys_eventos OWNER TO spi40;

--
-- Name: sys_idiomas_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.sys_idiomas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sys_idiomas_id_seq OWNER TO spi40;

--
-- Name: sys_idiomas; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_idiomas (
    id integer DEFAULT nextval('public.sys_idiomas_id_seq'::regclass) NOT NULL,
    nombre character varying(20) NOT NULL,
    archivo character varying(20) NOT NULL,
    abreviatura character varying(2) NOT NULL
);


ALTER TABLE public.sys_idiomas OWNER TO spi40;

--
-- Name: sys_listados_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.sys_listados_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sys_listados_id_seq OWNER TO spi40;

--
-- Name: sys_listados; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_listados (
    id integer DEFAULT nextval('public.sys_listados_id_seq'::regclass) NOT NULL,
    campos text NOT NULL,
    origen text NOT NULL,
    condiciones text,
    orden_inicial text,
    origen_count character varying(50) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE public.sys_listados OWNER TO spi40;

--
-- Name: sys_permisos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_permisos (
    id_entidad integer NOT NULL,
    id_operador integer NOT NULL,
    permitido smallint NOT NULL,
    negado smallint NOT NULL
);


ALTER TABLE public.sys_permisos OWNER TO spi40;

--
-- Name: sys_plugins; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_plugins (
    id integer NOT NULL,
    version character varying(10),
    dependencias character varying(120),
    instalacion bigint DEFAULT 0 NOT NULL,
    revision_git integer DEFAULT 0 NOT NULL,
    sha_git character varying(40)
);


ALTER TABLE public.sys_plugins OWNER TO spi40;

--
-- Name: sys_propiedades_abns; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_propiedades_abns (
    id_propiedad integer NOT NULL,
    id_abn integer NOT NULL
);


ALTER TABLE public.sys_propiedades_abns OWNER TO spi40;

--
-- Name: sys_tablas_auditoria; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_tablas_auditoria (
    id integer NOT NULL,
    id_padre integer NOT NULL,
    tabla text,
    activo boolean DEFAULT false
);


ALTER TABLE public.sys_tablas_auditoria OWNER TO spi40;

--
-- Name: sys_tablas_auditoria_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.sys_tablas_auditoria_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sys_tablas_auditoria_id_seq OWNER TO spi40;

--
-- Name: sys_tablas_auditoria_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.sys_tablas_auditoria_id_seq OWNED BY public.sys_tablas_auditoria.id;


--
-- Name: sys_tipos_eventos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.sys_tipos_eventos_id_seq
    START WITH 10000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sys_tipos_eventos_id_seq OWNER TO spi40;

--
-- Name: sys_tipos_eventos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_tipos_eventos (
    id integer DEFAULT nextval('public.sys_tipos_eventos_id_seq'::regclass) NOT NULL,
    id_padre integer NOT NULL,
    id_operador_origen_default integer NOT NULL,
    id_operador_destino_default integer NOT NULL,
    estado_tipo smallint DEFAULT 1 NOT NULL,
    estado_default smallint NOT NULL,
    imprimible boolean DEFAULT false NOT NULL,
    alcance smallint DEFAULT 0 NOT NULL
);


ALTER TABLE public.sys_tipos_eventos OWNER TO spi40;

--
-- Name: COLUMN sys_tipos_eventos.estado_tipo; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.sys_tipos_eventos.estado_tipo IS '0: inactivo, 1: activo, 2: sistema (r/o)';


--
-- Name: COLUMN sys_tipos_eventos.estado_default; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.sys_tipos_eventos.estado_default IS '0: cerrada, 1: abierta';


--
-- Name: COLUMN sys_tipos_eventos.imprimible; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.sys_tipos_eventos.imprimible IS '0: no imnprimible, 1: imprimible';


--
-- Name: COLUMN sys_tipos_eventos.alcance; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.sys_tipos_eventos.alcance IS '0: Cliente, 1: Locacion, 2: Pack, 3: Servicio';


--
-- Name: sys_tipos_eventos_operadores; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.sys_tipos_eventos_operadores (
    id_tipo_evento integer NOT NULL,
    id_operador integer NOT NULL,
    tipo smallint NOT NULL
);


ALTER TABLE public.sys_tipos_eventos_operadores OWNER TO spi40;

--
-- Name: COLUMN sys_tipos_eventos_operadores.tipo; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.sys_tipos_eventos_operadores.tipo IS '0: operador origen, 1: operador destino';


--
-- Name: sys_webservice_pedidos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.sys_webservice_pedidos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sys_webservice_pedidos_id_seq OWNER TO spi40;

--
-- Name: sys_webservice_transacciones_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.sys_webservice_transacciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sys_webservice_transacciones_id_seq OWNER TO spi40;

--
-- Name: tec_etiquetas_dispositivos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_etiquetas_dispositivos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_etiquetas_dispositivos_id_seq OWNER TO spi40;

--
-- Name: tec_etiquetas_dispositivos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_etiquetas_dispositivos (
    id integer DEFAULT nextval('public.tec_etiquetas_dispositivos_id_seq'::regclass) NOT NULL,
    nombre character varying(50) NOT NULL,
    id_grupo_etiqueta integer DEFAULT 0 NOT NULL,
    funcion_carga character varying(50) DEFAULT 'cargar_etiqueta_dispositivo'::character varying,
    funcion_validacion character varying(50) DEFAULT 'validar_etiqueta_dispositivo'::character varying,
    funcion_guardado character varying(50) DEFAULT 'guardar_etiqueta_dispositivo'::character varying,
    funcion_mostrar character varying(50) DEFAULT 'mostrar_etiqueta_dispositivo'::character varying
);


ALTER TABLE public.tec_etiquetas_dispositivos OWNER TO spi40;

--
-- Name: tec_grupos_etiquetas_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_grupos_etiquetas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_grupos_etiquetas_id_seq OWNER TO spi40;

--
-- Name: tec_grupos_etiquetas; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_grupos_etiquetas (
    id integer DEFAULT nextval('public.tec_grupos_etiquetas_id_seq'::regclass) NOT NULL,
    descripcion character varying(50) NOT NULL
);


ALTER TABLE public.tec_grupos_etiquetas OWNER TO spi40;

--
-- Name: tec_plantillas_objetos_monitoreo_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_plantillas_objetos_monitoreo_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_plantillas_objetos_monitoreo_id_seq OWNER TO spi40;

--
-- Name: tec_plantillas_objetos_monitoreo; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_plantillas_objetos_monitoreo (
    id integer DEFAULT nextval('public.tec_plantillas_objetos_monitoreo_id_seq'::regclass) NOT NULL,
    descripcion character varying(50) NOT NULL,
    ancho_grafico integer,
    alto_grafico integer,
    etiqueta_vertical character varying(50) NOT NULL,
    tipo_grafico character varying(15) DEFAULT ''::character varying NOT NULL,
    color_fondo character varying(7) DEFAULT '#eeeeee'::character varying NOT NULL,
    color_fondo_grafico character varying(7) DEFAULT '#ffffff'::character varying NOT NULL
);


ALTER TABLE public.tec_plantillas_objetos_monitoreo OWNER TO spi40;

--
-- Name: tec_plantillas_objetos_monitoreo_items_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_plantillas_objetos_monitoreo_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_plantillas_objetos_monitoreo_items_id_seq OWNER TO spi40;

--
-- Name: tec_plantillas_objetos_monitoreo_items; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_plantillas_objetos_monitoreo_items (
    id integer DEFAULT nextval('public.tec_plantillas_objetos_monitoreo_items_id_seq'::regclass) NOT NULL,
    id_plantilla_objetos_monitoreo integer NOT NULL,
    tipo smallint DEFAULT 0 NOT NULL,
    oid_script character varying(200) NOT NULL,
    etiqueta character varying(50) NOT NULL,
    snmpversion character varying(2) DEFAULT '1'::character varying NOT NULL,
    valor_min bigint DEFAULT 0 NOT NULL,
    valor_max bigint DEFAULT 0 NOT NULL,
    color character varying(7) DEFAULT ''::character varying NOT NULL,
    unidad character varying(6) DEFAULT ''::character varying NOT NULL,
    multiplo character varying(10) DEFAULT 1 NOT NULL,
    grafico character varying(6) DEFAULT 'LINE1'::character varying NOT NULL
);


ALTER TABLE public.tec_plantillas_objetos_monitoreo_items OWNER TO spi40;

--
-- Name: tec_pools_ips_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_pools_ips_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_pools_ips_id_seq OWNER TO spi40;

--
-- Name: tec_pools_ips; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_pools_ips (
    id integer DEFAULT nextval('public.tec_pools_ips_id_seq'::regclass) NOT NULL,
    descripcion character varying(50) DEFAULT ''::character varying
);


ALTER TABLE public.tec_pools_ips OWNER TO spi40;

--
-- Name: tec_propiedades_dispositivos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_propiedades_dispositivos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_propiedades_dispositivos_id_seq OWNER TO spi40;

--
-- Name: tec_propiedades_dispositivos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_propiedades_dispositivos (
    id integer DEFAULT nextval('public.tec_propiedades_dispositivos_id_seq'::regclass) NOT NULL,
    funcion_carga character varying(50) DEFAULT 'cargar_texto_dispositivo'::character varying NOT NULL,
    funcion_validacion character varying(50) DEFAULT 'validar_texto_dispositivo'::character varying NOT NULL,
    funcion_guardado character varying(50) DEFAULT 'guardar_texto_dispositivo'::character varying NOT NULL,
    funcion_busqueda character varying(50) DEFAULT 'cargar_texto_dispositivo'::character varying
);


ALTER TABLE public.tec_propiedades_dispositivos OWNER TO spi40;

--
-- Name: tec_propiedades_interfaces_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_propiedades_interfaces_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_propiedades_interfaces_id_seq OWNER TO spi40;

--
-- Name: tec_propiedades_interfaces; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_propiedades_interfaces (
    id integer DEFAULT nextval('public.tec_propiedades_interfaces_id_seq'::regclass) NOT NULL,
    funcion_carga character varying(50) DEFAULT 'cargar_texto_interface'::character varying NOT NULL,
    funcion_validacion character varying(50) DEFAULT 'validar_texto_interface'::character varying NOT NULL,
    funcion_guardado character varying(50) DEFAULT 'guardar_texto_interface'::character varying NOT NULL
);


ALTER TABLE public.tec_propiedades_interfaces OWNER TO spi40;

--
-- Name: tec_rangos_ips_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_rangos_ips_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_rangos_ips_id_seq OWNER TO spi40;

--
-- Name: tec_rangos_ips; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_rangos_ips (
    id integer DEFAULT nextval('public.tec_rangos_ips_id_seq'::regclass) NOT NULL,
    desde_ip character varying(50) NOT NULL,
    hasta_ip character varying(50) NOT NULL,
    id_pool integer NOT NULL
);


ALTER TABLE public.tec_rangos_ips OWNER TO spi40;

--
-- Name: tec_tipos_dispositivos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_tipos_dispositivos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_tipos_dispositivos_id_seq OWNER TO spi40;

--
-- Name: tec_tipos_dispositivos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_tipos_dispositivos (
    id integer DEFAULT nextval('public.tec_tipos_dispositivos_id_seq'::regclass) NOT NULL,
    descripcion character varying(100) NOT NULL,
    multiusuario boolean DEFAULT false,
    funcion_validar_borrado text
);


ALTER TABLE public.tec_tipos_dispositivos OWNER TO spi40;

--
-- Name: COLUMN tec_tipos_dispositivos.funcion_validar_borrado; Type: COMMENT; Schema: public; Owner: spi40
--

COMMENT ON COLUMN public.tec_tipos_dispositivos.funcion_validar_borrado IS 'pueden ser varias funciones separadas por punto y coma';


--
-- Name: tec_tipos_dispositivos_propiedades_dispositivos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_tipos_dispositivos_propiedades_dispositivos (
    id_propiedad integer NOT NULL,
    id_tipo_dispositivo integer NOT NULL
);


ALTER TABLE public.tec_tipos_dispositivos_propiedades_dispositivos OWNER TO spi40;

--
-- Name: tec_tipos_dispositivos_solapas; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_tipos_dispositivos_solapas (
    id integer NOT NULL,
    id_tipo_dispositivo integer NOT NULL,
    titulo character varying(30) NOT NULL,
    programa character varying(50) NOT NULL,
    json_parametros character varying(100) NOT NULL
);


ALTER TABLE public.tec_tipos_dispositivos_solapas OWNER TO spi40;

--
-- Name: tec_tipos_dispositivos_solapas_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_tipos_dispositivos_solapas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_tipos_dispositivos_solapas_id_seq OWNER TO spi40;

--
-- Name: tec_tipos_dispositivos_solapas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: spi40
--

ALTER SEQUENCE public.tec_tipos_dispositivos_solapas_id_seq OWNED BY public.tec_tipos_dispositivos_solapas.id;


--
-- Name: tec_tipos_puertos_dispositivos_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_tipos_puertos_dispositivos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_tipos_puertos_dispositivos_id_seq OWNER TO spi40;

--
-- Name: tec_tipos_puertos_dispositivos; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_tipos_puertos_dispositivos (
    id integer DEFAULT nextval('public.tec_tipos_puertos_dispositivos_id_seq'::regclass) NOT NULL,
    descripcion character varying(50) NOT NULL,
    cantidad_fija smallint
);


ALTER TABLE public.tec_tipos_puertos_dispositivos OWNER TO spi40;

--
-- Name: tec_tipos_tecnologias_id_seq; Type: SEQUENCE; Schema: public; Owner: spi40
--

CREATE SEQUENCE public.tec_tipos_tecnologias_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.tec_tipos_tecnologias_id_seq OWNER TO spi40;

--
-- Name: tec_tipos_tecnologias; Type: TABLE; Schema: public; Owner: spi40
--

CREATE TABLE public.tec_tipos_tecnologias (
    id integer DEFAULT nextval('public.tec_tipos_tecnologias_id_seq'::regclass) NOT NULL
);


ALTER TABLE public.tec_tipos_tecnologias OWNER TO spi40;

--
-- Name: cfg_servidores_spi id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.cfg_servidores_spi ALTER COLUMN id SET DEFAULT nextval('public.cfg_servidores_spi_id_seq'::regclass);


--
-- Name: lang_mensajes_varios id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_mensajes_varios ALTER COLUMN id SET DEFAULT nextval('public.lang_mensajes_varios_id_seq'::regclass);


--
-- Name: lang_tablas_auditoria id_tabla_auditoria; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tablas_auditoria ALTER COLUMN id_tabla_auditoria SET DEFAULT nextval('public.lang_tablas_auditoria_id_tabla_auditoria_seq'::regclass);


--
-- Name: lang_tablas_auditoria id_idioma; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tablas_auditoria ALTER COLUMN id_idioma SET DEFAULT nextval('public.lang_tablas_auditoria_id_idioma_seq'::regclass);


--
-- Name: newsletter_destinatarios id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.newsletter_destinatarios ALTER COLUMN id SET DEFAULT nextval('public.newsletter_destinatarios_id_seq'::regclass);


--
-- Name: newsletter_filtros_plugins id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.newsletter_filtros_plugins ALTER COLUMN id SET DEFAULT nextval('public.newsletter_filtros_plugins_id_seq'::regclass);


--
-- Name: newsletter_plantillas id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.newsletter_plantillas ALTER COLUMN id SET DEFAULT nextval('public.newsletter_plantillas_id_seq'::regclass);


--
-- Name: newsletter_tareas id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.newsletter_tareas ALTER COLUMN id SET DEFAULT nextval('public.newsletter_tareas_id_seq'::regclass);


--
-- Name: plg_1000_cm_modelos_explog id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_modelos_explog ALTER COLUMN id SET DEFAULT nextval('public.plg_1000_cm_modelos_explog_id_seq'::regclass);


--
-- Name: plg_1000_cm_modelos_explog_especifica id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_modelos_explog_especifica ALTER COLUMN id SET DEFAULT nextval('public.plg_1000_cm_modelos_explog_especifica_id_seq'::regclass);


--
-- Name: plg_1000_cm_modelos_ipv6 id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_modelos_ipv6 ALTER COLUMN id SET DEFAULT nextval('public.plg_1000_cm_modelos_ipv6_id_seq'::regclass);


--
-- Name: plg_1000_cm_servicios_explog id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_servicios_explog ALTER COLUMN id SET DEFAULT nextval('public.plg_1000_cm_servicios_explog_id_seq'::regclass);


--
-- Name: plg_1000_cm_templates_cm id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_templates_cm ALTER COLUMN id SET DEFAULT nextval('public.plg_1000_cm_templates_cm_id_seq'::regclass);


--
-- Name: plg_14000_alertas id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas ALTER COLUMN id SET DEFAULT nextval('public.plg_14000_alertas_id_seq'::regclass);


--
-- Name: plg_14000_alertas_categorias id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_categorias ALTER COLUMN id SET DEFAULT nextval('public.plg_14000_alertas_categorias_id_seq'::regclass);


--
-- Name: plg_14000_alertas_contactos id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_contactos ALTER COLUMN id SET DEFAULT nextval('public.plg_14000_alertas_contactos_id_seq'::regclass);


--
-- Name: plg_14000_alertas_logs id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_logs ALTER COLUMN id SET DEFAULT nextval('public.plg_14000_alertas_logs_id_seq'::regclass);


--
-- Name: plg_14000_alertas_notificaciones id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_notificaciones ALTER COLUMN id SET DEFAULT nextval('public.plg_14000_alertas_notificaciones_id_seq'::regclass);


--
-- Name: plg_14000_alertas_tipo_notificaciones id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_tipo_notificaciones ALTER COLUMN id SET DEFAULT nextval('public.plg_14000_alertas_tipo_notificaciones_id_seq'::regclass);


--
-- Name: sys_tablas_auditoria id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_tablas_auditoria ALTER COLUMN id SET DEFAULT nextval('public.sys_tablas_auditoria_id_seq'::regclass);


--
-- Name: tec_tipos_dispositivos_solapas id; Type: DEFAULT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_tipos_dispositivos_solapas ALTER COLUMN id SET DEFAULT nextval('public.tec_tipos_dispositivos_solapas_id_seq'::regclass);


--
-- Name: campos_modificados campos_modificados_pkey; Type: CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.campos_modificados
    ADD CONSTRAINT campos_modificados_pkey PRIMARY KEY (id);


--
-- Name: eventos eventos_pkey; Type: CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.eventos
    ADD CONSTRAINT eventos_pkey PRIMARY KEY (id);


--
-- Name: eventos eventos_unique; Type: CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.eventos
    ADD CONSTRAINT eventos_unique UNIQUE (id_operador, ip_origen, "timestamp", id_entidad);


--
-- Name: lang_tipos_operaciones lang_tipos_operaciones_pkey; Type: CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.lang_tipos_operaciones
    ADD CONSTRAINT lang_tipos_operaciones_pkey PRIMARY KEY (id, id_idioma);


--
-- Name: parametros_acceso parametros_acceso_pkey; Type: CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.parametros_acceso
    ADD CONSTRAINT parametros_acceso_pkey PRIMARY KEY (id);


--
-- Name: parametros_acceso parametros_acceso_unique; Type: CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.parametros_acceso
    ADD CONSTRAINT parametros_acceso_unique UNIQUE (id_evento, nombre_campo, valor);


--
-- Name: registros_modificados registros_modificados_pkey; Type: CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.registros_modificados
    ADD CONSTRAINT registros_modificados_pkey PRIMARY KEY (id);


--
-- Name: registros_modificados registros_modificados_unique; Type: CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.registros_modificados
    ADD CONSTRAINT registros_modificados_unique UNIQUE (id_evento, id_tipo_operacion, tabla, llaves_primarias);


--
-- Name: campos_modificados campos_modificados_pkey; Type: CONSTRAINT; Schema: auditoria_historico; Owner: spi40
--

ALTER TABLE ONLY auditoria_historico.campos_modificados
    ADD CONSTRAINT campos_modificados_pkey PRIMARY KEY (id);


--
-- Name: eventos eventos_pkey; Type: CONSTRAINT; Schema: auditoria_historico; Owner: spi40
--

ALTER TABLE ONLY auditoria_historico.eventos
    ADD CONSTRAINT eventos_pkey PRIMARY KEY (id);


--
-- Name: eventos eventos_unique; Type: CONSTRAINT; Schema: auditoria_historico; Owner: spi40
--

ALTER TABLE ONLY auditoria_historico.eventos
    ADD CONSTRAINT eventos_unique UNIQUE (id_operador, ip_origen, "timestamp", id_entidad);


--
-- Name: parametros_acceso parametros_acceso_pkey; Type: CONSTRAINT; Schema: auditoria_historico; Owner: spi40
--

ALTER TABLE ONLY auditoria_historico.parametros_acceso
    ADD CONSTRAINT parametros_acceso_pkey PRIMARY KEY (id);


--
-- Name: parametros_acceso parametros_acceso_unique; Type: CONSTRAINT; Schema: auditoria_historico; Owner: spi40
--

ALTER TABLE ONLY auditoria_historico.parametros_acceso
    ADD CONSTRAINT parametros_acceso_unique UNIQUE (id_evento, nombre_campo, valor);


--
-- Name: registros_modificados registros_modificados_pkey; Type: CONSTRAINT; Schema: auditoria_historico; Owner: spi40
--

ALTER TABLE ONLY auditoria_historico.registros_modificados
    ADD CONSTRAINT registros_modificados_pkey PRIMARY KEY (id);


--
-- Name: registros_modificados registros_modificados_unique; Type: CONSTRAINT; Schema: auditoria_historico; Owner: spi40
--

ALTER TABLE ONLY auditoria_historico.registros_modificados
    ADD CONSTRAINT registros_modificados_unique UNIQUE (id_evento, id_tipo_operacion, tabla, llaves_primarias);


--
-- Name: cfg_configuraciones cfg_configuraciones_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.cfg_configuraciones
    ADD CONSTRAINT cfg_configuraciones_pkey PRIMARY KEY (id);


--
-- Name: cfg_grupos_configuraciones cfg_grupos_configuraciones_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.cfg_grupos_configuraciones
    ADD CONSTRAINT cfg_grupos_configuraciones_pkey PRIMARY KEY (id);


--
-- Name: cfg_servidores_grupos_servidores cfg_servidores_grupos_servidores_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.cfg_servidores_grupos_servidores
    ADD CONSTRAINT cfg_servidores_grupos_servidores_pkey PRIMARY KEY (id_servidor, id_grupo);


--
-- Name: cfg_servidores_spi cfg_servidores_spi_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.cfg_servidores_spi
    ADD CONSTRAINT cfg_servidores_spi_pkey PRIMARY KEY (id);


--
-- Name: cfg_servidores_spi cfg_servidores_spi_unique; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.cfg_servidores_spi
    ADD CONSTRAINT cfg_servidores_spi_unique UNIQUE (descripcion, es_grupo);


--
-- Name: com_clientes com_clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_clientes
    ADD CONSTRAINT com_clientes_pkey PRIMARY KEY (id);


--
-- Name: com_locaciones_clientes_packs com_locaciones_clientes_packs_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_locaciones_clientes_packs
    ADD CONSTRAINT com_locaciones_clientes_packs_pkey PRIMARY KEY (id);


--
-- Name: com_locaciones_clientes_packs_servicios com_locaciones_clientes_packs_servicios_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_locaciones_clientes_packs_servicios
    ADD CONSTRAINT com_locaciones_clientes_packs_servicios_pkey PRIMARY KEY (id);


--
-- Name: com_locaciones_clientes com_locaciones_clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_locaciones_clientes
    ADD CONSTRAINT com_locaciones_clientes_pkey PRIMARY KEY (id);


--
-- Name: com_localidades com_localidades_nombre_unique; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_localidades
    ADD CONSTRAINT com_localidades_nombre_unique UNIQUE (nombre);


--
-- Name: com_localidades com_localidades_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_localidades
    ADD CONSTRAINT com_localidades_pkey PRIMARY KEY (id);


--
-- Name: com_packs_contenido com_packs_contenido_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_packs_contenido
    ADD CONSTRAINT com_packs_contenido_pkey PRIMARY KEY (id_pack, id_hijo);


--
-- Name: com_packs com_packs_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_packs
    ADD CONSTRAINT com_packs_pkey PRIMARY KEY (id);


--
-- Name: com_paises com_paises_nombre_unique; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_paises
    ADD CONSTRAINT com_paises_nombre_unique UNIQUE (nombre);


--
-- Name: com_paises com_paises_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_paises
    ADD CONSTRAINT com_paises_pkey PRIMARY KEY (id);


--
-- Name: com_provincias com_provincias_nombre_unique; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_provincias
    ADD CONSTRAINT com_provincias_nombre_unique UNIQUE (nombre);


--
-- Name: com_provincias com_provincias_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_provincias
    ADD CONSTRAINT com_provincias_pkey PRIMARY KEY (id);


--
-- Name: dhcp_campos_objetos dhcp_campos_objetos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_campos_objetos
    ADD CONSTRAINT dhcp_campos_objetos_pkey PRIMARY KEY (id_objeto, id_tipo_objeto, orden);


--
-- Name: dhcp_campos dhcp_campos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_campos
    ADD CONSTRAINT dhcp_campos_pkey PRIMARY KEY (id_tipo_objeto, orden);


--
-- Name: dhcp_mapa_tipos_objetos dhcp_mapa_tipos_objetos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_mapa_tipos_objetos
    ADD CONSTRAINT dhcp_mapa_tipos_objetos_pkey PRIMARY KEY (id_padre, id_hijo);


--
-- Name: dhcp_objetos dhcp_objetos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_objetos
    ADD CONSTRAINT dhcp_objetos_pkey PRIMARY KEY (id);


--
-- Name: dhcp_opciones_especiales dhcp_opciones_especiales_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_opciones_especiales
    ADD CONSTRAINT dhcp_opciones_especiales_pkey PRIMARY KEY (id);


--
-- Name: dhcp_opciones dhcp_opciones_nombre_key; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_opciones
    ADD CONSTRAINT dhcp_opciones_nombre_key UNIQUE (nombre);


--
-- Name: dhcp_opciones_objetos dhcp_opciones_objetos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_opciones_objetos
    ADD CONSTRAINT dhcp_opciones_objetos_pkey PRIMARY KEY (id_objeto, id_opcion, contador);


--
-- Name: dhcp_opciones dhcp_opciones_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_opciones
    ADD CONSTRAINT dhcp_opciones_pkey PRIMARY KEY (id);


--
-- Name: dhcp_tipos_datos dhcp_tipos_datos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_tipos_datos
    ADD CONSTRAINT dhcp_tipos_datos_pkey PRIMARY KEY (id);


--
-- Name: dhcp_tipos_objetos dhcp_tipos_objetos_clausula_declarativa_key; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_tipos_objetos
    ADD CONSTRAINT dhcp_tipos_objetos_clausula_declarativa_key UNIQUE (clausula_declarativa);


--
-- Name: dhcp_tipos_objetos dhcp_tipos_objetos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_tipos_objetos
    ADD CONSTRAINT dhcp_tipos_objetos_pkey PRIMARY KEY (id);


--
-- Name: lang_cfg_configuraciones lang_cfg_configuraciones_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_cfg_configuraciones
    ADD CONSTRAINT lang_cfg_configuraciones_pkey PRIMARY KEY (id_idioma, id_configuracion);


--
-- Name: lang_cfg_grupos_configuraciones lang_cfg_grupos_configuraciones_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_cfg_grupos_configuraciones
    ADD CONSTRAINT lang_cfg_grupos_configuraciones_pkey PRIMARY KEY (id_idioma, id_grupo);


--
-- Name: lang_mensajes_varios lang_mensajes_varios_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_mensajes_varios
    ADD CONSTRAINT lang_mensajes_varios_pkey PRIMARY KEY (id, id_idioma);


--
-- Name: lang_svc_dependencias lang_svc_dependencias_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_svc_dependencias
    ADD CONSTRAINT lang_svc_dependencias_pkey PRIMARY KEY (id_dependencia, id_idioma);


--
-- Name: lang_svc_propiedades lang_svc_propiedades_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_svc_propiedades
    ADD CONSTRAINT lang_svc_propiedades_pkey PRIMARY KEY (id_propiedad, id_idioma);


--
-- Name: lang_svc_requisitos lang_svc_requisitos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_svc_requisitos
    ADD CONSTRAINT lang_svc_requisitos_pkey PRIMARY KEY (id_requisito, id_idioma);


--
-- Name: lang_svc_tipos_servicios lang_svc_tipos_servicios_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_svc_tipos_servicios
    ADD CONSTRAINT lang_svc_tipos_servicios_pkey PRIMARY KEY (id_tipo_servicio, id_idioma);


--
-- Name: lang_sys_abns lang_sys_abns_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_abns
    ADD CONSTRAINT lang_sys_abns_pkey PRIMARY KEY (id_abn, id_idioma);


--
-- Name: lang_sys_entidades lang_sys_entidades_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_entidades
    ADD CONSTRAINT lang_sys_entidades_pkey PRIMARY KEY (id_entidad, id_idioma);


--
-- Name: lang_sys_estados lang_sys_estados_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_estados
    ADD CONSTRAINT lang_sys_estados_pkey PRIMARY KEY (id_tipo_estado, id_estado, id_idioma);


--
-- Name: lang_sys_listados lang_sys_listados_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_listados
    ADD CONSTRAINT lang_sys_listados_pkey PRIMARY KEY (id_listado, id_idioma);


--
-- Name: lang_sys_plugins lang_sys_plugins_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_plugins
    ADD CONSTRAINT lang_sys_plugins_pkey PRIMARY KEY (id_plugin, id_idioma);


--
-- Name: lang_sys_tipos_eventos lang_sys_tipos_eventos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_tipos_eventos
    ADD CONSTRAINT lang_sys_tipos_eventos_pkey PRIMARY KEY (id_tipo_evento, id_idioma);


--
-- Name: lang_tablas_auditoria lang_tablas_auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tablas_auditoria
    ADD CONSTRAINT lang_tablas_auditoria_pkey PRIMARY KEY (id_tabla_auditoria, id_idioma);


--
-- Name: lang_tec_objetos_monitoreo_columnas_extras lang_tec_objetos_monitoreo_columnas_extras_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tec_objetos_monitoreo_columnas_extras
    ADD CONSTRAINT lang_tec_objetos_monitoreo_columnas_extras_pkey PRIMARY KEY (id_columna, id_idioma);


--
-- Name: lang_tec_propiedades_dispositivos lang_tec_propiedades_dispositivos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tec_propiedades_dispositivos
    ADD CONSTRAINT lang_tec_propiedades_dispositivos_pkey PRIMARY KEY (id_propiedad_dispositivo, id_idioma);


--
-- Name: lang_tec_propiedades_interfaces lang_tec_propiedades_interfaces_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tec_propiedades_interfaces
    ADD CONSTRAINT lang_tec_propiedades_interfaces_pkey PRIMARY KEY (id_propiedad_interface, id_idioma);


--
-- Name: lang_tec_tipos_tecnologias lang_tec_tipos_tecnologias_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tec_tipos_tecnologias
    ADD CONSTRAINT lang_tec_tipos_tecnologias_pkey PRIMARY KEY (id_tipo_tecnologia, id_idioma);


--
-- Name: newsletter_destinatarios newsletter_destinatarios_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.newsletter_destinatarios
    ADD CONSTRAINT newsletter_destinatarios_pkey PRIMARY KEY (id);


--
-- Name: newsletter_tareas newsletter_tareas_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.newsletter_tareas
    ADD CONSTRAINT newsletter_tareas_pkey PRIMARY KEY (id);


--
-- Name: plg_1000_cm_dispositivos_interfaces_pools_ip plg_1000_cm_dispositivos_interfaces_pools_ip_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_dispositivos_interfaces_pools_ip
    ADD CONSTRAINT plg_1000_cm_dispositivos_interfaces_pools_ip_pkey PRIMARY KEY (id_dispositivo, id, id_pool);


--
-- Name: plg_1000_cm_modelos_explog_especifica plg_1000_cm_modelos_explog_especifica_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_modelos_explog_especifica
    ADD CONSTRAINT plg_1000_cm_modelos_explog_especifica_pkey PRIMARY KEY (id);


--
-- Name: plg_1000_cm_modelos_explog plg_1000_cm_modelos_explog_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_modelos_explog
    ADD CONSTRAINT plg_1000_cm_modelos_explog_pkey PRIMARY KEY (id);


--
-- Name: plg_1000_cm_modelos_ipv6 plg_1000_cm_modelos_ipv6_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_modelos_ipv6
    ADD CONSTRAINT plg_1000_cm_modelos_ipv6_pkey PRIMARY KEY (id);


--
-- Name: plg_1000_cm_templates_cm plg_1000_cm_templates_cm_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_templates_cm
    ADD CONSTRAINT plg_1000_cm_templates_cm_pkey PRIMARY KEY (id);


--
-- Name: plg_1000_cm_servicios_explog plg_1000_servicios_exlog_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_servicios_explog
    ADD CONSTRAINT plg_1000_servicios_exlog_pkey PRIMARY KEY (id);


--
-- Name: plg_14000_alertas_alertas_notificaciones plg_14000_alertas_alertas_notificaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_alertas_notificaciones
    ADD CONSTRAINT plg_14000_alertas_alertas_notificaciones_pkey PRIMARY KEY (id_alerta, id_alerta_notificacion);


--
-- Name: plg_14000_alertas_categorias plg_14000_alertas_categorias_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_categorias
    ADD CONSTRAINT plg_14000_alertas_categorias_pkey PRIMARY KEY (id);


--
-- Name: plg_14000_alertas_contactos_alertas_contactos plg_14000_alertas_contactos_alertas_contactos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_contactos_alertas_contactos
    ADD CONSTRAINT plg_14000_alertas_contactos_alertas_contactos_pkey PRIMARY KEY (id_alerta_contacto_grupo, alerta_contacto_nodo);


--
-- Name: plg_14000_alertas_contactos plg_14000_alertas_contactos_nombre_unique; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_contactos
    ADD CONSTRAINT plg_14000_alertas_contactos_nombre_unique UNIQUE (nombre);


--
-- Name: plg_14000_alertas_contactos plg_14000_alertas_contactos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_contactos
    ADD CONSTRAINT plg_14000_alertas_contactos_pkey PRIMARY KEY (id);


--
-- Name: plg_14000_alertas_logs plg_14000_alertas_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_logs
    ADD CONSTRAINT plg_14000_alertas_logs_pkey PRIMARY KEY (id);


--
-- Name: plg_14000_alertas_notificaciones_alertas_tipo_notificaciones plg_14000_alertas_notif_alertas_tipo_notif_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_notificaciones_alertas_tipo_notificaciones
    ADD CONSTRAINT plg_14000_alertas_notif_alertas_tipo_notif_pkey PRIMARY KEY (id_alerta_notificacion, id_alerta_tipo_notificacion);


--
-- Name: plg_14000_alertas_notificaciones_alertas_contactos plg_14000_alertas_notificaciones_alertas_contactos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_notificaciones_alertas_contactos
    ADD CONSTRAINT plg_14000_alertas_notificaciones_alertas_contactos_pkey PRIMARY KEY (id_alerta_notificacion, id_alerta_contacto);


--
-- Name: plg_14000_alertas_notificaciones plg_14000_alertas_notificaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_notificaciones
    ADD CONSTRAINT plg_14000_alertas_notificaciones_pkey PRIMARY KEY (id);


--
-- Name: plg_14000_alertas plg_14000_alertas_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas
    ADD CONSTRAINT plg_14000_alertas_pkey PRIMARY KEY (id);


--
-- Name: plg_14000_alertas_tipo_notificaciones plg_14000_alertas_tipo_notificaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_tipo_notificaciones
    ADD CONSTRAINT plg_14000_alertas_tipo_notificaciones_pkey PRIMARY KEY (id);


--
-- Name: svc_dependencias svc_dependencias_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_dependencias
    ADD CONSTRAINT svc_dependencias_pkey PRIMARY KEY (id);


--
-- Name: svc_elegidos svc_elegidos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_elegidos
    ADD CONSTRAINT svc_elegidos_pkey UNIQUE (id_seleccion, id_cliente, id_locacion_cliente, id_locacion_cliente_pack, id_locacion_cliente_pack_servicio);


--
-- Name: svc_propiedades svc_propiedades_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_propiedades
    ADD CONSTRAINT svc_propiedades_pkey PRIMARY KEY (id);


--
-- Name: svc_requisitos svc_requisitos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_requisitos
    ADD CONSTRAINT svc_requisitos_pkey PRIMARY KEY (id);


--
-- Name: svc_servicios_dependencias svc_servicios_dependencias_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_dependencias
    ADD CONSTRAINT svc_servicios_dependencias_pkey PRIMARY KEY (id_servicio, id_dependencia);


--
-- Name: svc_servicios_grupos svc_servicios_grupos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_grupos
    ADD CONSTRAINT svc_servicios_grupos_pkey PRIMARY KEY (id);


--
-- Name: svc_servicios svc_servicios_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios
    ADD CONSTRAINT svc_servicios_pkey PRIMARY KEY (id);


--
-- Name: svc_servicios_propiedades_internas svc_servicios_propiedades_internas_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_propiedades_internas
    ADD CONSTRAINT svc_servicios_propiedades_internas_pkey PRIMARY KEY (id_servicio, id_propiedad);


--
-- Name: svc_servicios_propiedades svc_servicios_propiedades_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_propiedades
    ADD CONSTRAINT svc_servicios_propiedades_pkey PRIMARY KEY (id_locacion_cliente_pack_servicio, id_propiedad);


--
-- Name: svc_servicios_requisitos svc_servicios_requisitos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_requisitos
    ADD CONSTRAINT svc_servicios_requisitos_pkey PRIMARY KEY (id_servicio, id_requisito);


--
-- Name: svc_tipos_servicios svc_tipos_servicios_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_servicios
    ADD CONSTRAINT svc_tipos_servicios_pkey PRIMARY KEY (id);


--
-- Name: svc_tipos_servicios_propiedades_internas svc_tipos_servicios_propiedades_internas_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_servicios_propiedades_internas
    ADD CONSTRAINT svc_tipos_servicios_propiedades_internas_pkey PRIMARY KEY (id_tipo_servicio, id_propiedad);


--
-- Name: svc_tipos_servicios_propiedades svc_tipos_servicios_propiedades_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_servicios_propiedades
    ADD CONSTRAINT svc_tipos_servicios_propiedades_pkey PRIMARY KEY (id_tipo_servicio, id_propiedad);


--
-- Name: svc_tipos_servicios_tipos_tecnologias svc_tipos_servicios_tipos_tecnologias_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_servicios_tipos_tecnologias
    ADD CONSTRAINT svc_tipos_servicios_tipos_tecnologias_pkey PRIMARY KEY (id_tipo_servicio, id_tipo_tecnologia);


--
-- Name: svc_tipos_tecnologias_propiedades_internas svc_tipos_tecnologias_propiedades_internas_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_tecnologias_propiedades_internas
    ADD CONSTRAINT svc_tipos_tecnologias_propiedades_internas_pkey PRIMARY KEY (id_tipo_tecnologia, id_propiedad);


--
-- Name: svc_tipos_tecnologias_propiedades svc_tipos_tecnologias_propiedades_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_tecnologias_propiedades
    ADD CONSTRAINT svc_tipos_tecnologias_propiedades_pkey PRIMARY KEY (id_tipo_tecnologia, id_propiedad);


--
-- Name: sys_abns_logs sys_abns_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_abns_logs
    ADD CONSTRAINT sys_abns_logs_pkey PRIMARY KEY (id);


--
-- Name: sys_abns sys_abns_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_abns
    ADD CONSTRAINT sys_abns_pkey PRIMARY KEY (id);


--
-- Name: sys_abns_tareas sys_abns_tareas_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_abns_tareas
    ADD CONSTRAINT sys_abns_tareas_pkey PRIMARY KEY (id);


--
-- Name: sys_entidades sys_entidades_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_entidades
    ADD CONSTRAINT sys_entidades_pkey PRIMARY KEY (id);


--
-- Name: sys_eventos sys_eventos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_eventos
    ADD CONSTRAINT sys_eventos_pkey PRIMARY KEY (id);


--
-- Name: sys_idiomas sys_idiomas_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_idiomas
    ADD CONSTRAINT sys_idiomas_pkey PRIMARY KEY (id);


--
-- Name: sys_listados sys_listados_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_listados
    ADD CONSTRAINT sys_listados_pkey PRIMARY KEY (id);


--
-- Name: sys_operadores sys_operadores_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_operadores
    ADD CONSTRAINT sys_operadores_pkey PRIMARY KEY (id);


--
-- Name: sys_permisos sys_permisos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_permisos
    ADD CONSTRAINT sys_permisos_pkey PRIMARY KEY (id_operador, id_entidad);


--
-- Name: sys_plugins sys_plugins_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_plugins
    ADD CONSTRAINT sys_plugins_pkey PRIMARY KEY (id);


--
-- Name: sys_propiedades_abns sys_propiedades_abns_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_propiedades_abns
    ADD CONSTRAINT sys_propiedades_abns_pkey PRIMARY KEY (id_propiedad, id_abn);


--
-- Name: sys_tablas_auditoria sys_tablas_auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_tablas_auditoria
    ADD CONSTRAINT sys_tablas_auditoria_pkey PRIMARY KEY (id);


--
-- Name: sys_tipos_eventos_operadores sys_tipos_eventos_operadores_tipo_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_tipos_eventos_operadores
    ADD CONSTRAINT sys_tipos_eventos_operadores_tipo_pkey PRIMARY KEY (id_tipo_evento, id_operador, tipo);


--
-- Name: sys_tipos_eventos sys_tipos_eventos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_tipos_eventos
    ADD CONSTRAINT sys_tipos_eventos_pkey PRIMARY KEY (id);


--
-- Name: tec_dispositivos_etiquetas_dispositivos tec_dispositivos_etiquetas_dispositivos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos_etiquetas_dispositivos
    ADD CONSTRAINT tec_dispositivos_etiquetas_dispositivos_pkey PRIMARY KEY (id_dispositivo, id_etiqueta);


--
-- Name: tec_dispositivos_etiquetas_dispositivos tec_dispositivos_etiquetas_dispositivos_valor_key; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos_etiquetas_dispositivos
    ADD CONSTRAINT tec_dispositivos_etiquetas_dispositivos_valor_key UNIQUE (valor, unico);


--
-- Name: tec_dispositivos_interfaces tec_dispositivos_interfaces_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos_interfaces
    ADD CONSTRAINT tec_dispositivos_interfaces_pkey PRIMARY KEY (id);


--
-- Name: tec_dispositivos tec_dispositivos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos
    ADD CONSTRAINT tec_dispositivos_pkey PRIMARY KEY (id);


--
-- Name: tec_dispositivos_propiedades_dispositivos tec_dispositivos_propiedades_dispositivos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos_propiedades_dispositivos
    ADD CONSTRAINT tec_dispositivos_propiedades_dispositivos_pkey PRIMARY KEY (id_dispositivo, id_propiedad);


--
-- Name: tec_etiquetas_dispositivos tec_etiquetas_dispositivos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_etiquetas_dispositivos
    ADD CONSTRAINT tec_etiquetas_dispositivos_pkey PRIMARY KEY (id);


--
-- Name: tec_grupos_etiquetas tec_grupos_etiquetas_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_grupos_etiquetas
    ADD CONSTRAINT tec_grupos_etiquetas_pkey PRIMARY KEY (id);


--
-- Name: tec_dispositivos_interfaces_propiedades tec_interfaces_propiedades_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos_interfaces_propiedades
    ADD CONSTRAINT tec_interfaces_propiedades_pkey PRIMARY KEY (id_interface, id_propiedad_interface);


--
-- Name: tec_marcas tec_marcas_nombre_unique; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_marcas
    ADD CONSTRAINT tec_marcas_nombre_unique UNIQUE (nombre);


--
-- Name: tec_marcas tec_marcas_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_marcas
    ADD CONSTRAINT tec_marcas_pkey PRIMARY KEY (id);


--
-- Name: tec_modelos tec_modelos_descripcion_marca_key; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos
    ADD CONSTRAINT tec_modelos_descripcion_marca_key UNIQUE (descripcion, id_marca);


--
-- Name: tec_modelos_etiquetas_dispositivos tec_modelos_etiquetas_dispositivos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos_etiquetas_dispositivos
    ADD CONSTRAINT tec_modelos_etiquetas_dispositivos_pkey PRIMARY KEY (id_modelo, id_etiqueta, orden);


--
-- Name: tec_modelos tec_modelos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos
    ADD CONSTRAINT tec_modelos_pkey PRIMARY KEY (id);


--
-- Name: tec_modelos_propiedades_interfaces tec_modelos_propiedades_interfaces_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos_propiedades_interfaces
    ADD CONSTRAINT tec_modelos_propiedades_interfaces_pkey PRIMARY KEY (id_modelo, id_propiedad_interface);


--
-- Name: tec_modelos_puertos tec_modelos_puertos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos_puertos
    ADD CONSTRAINT tec_modelos_puertos_pkey PRIMARY KEY (id_modelo, id_tipo_puerto);


--
-- Name: tec_objetos_monitoreo tec_objetos_monitoreo_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_objetos_monitoreo
    ADD CONSTRAINT tec_objetos_monitoreo_pkey PRIMARY KEY (id);


--
-- Name: tec_plantillas_objetos_monitoreo_items tec_plantillas_objetos_monitoreo_items_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_plantillas_objetos_monitoreo_items
    ADD CONSTRAINT tec_plantillas_objetos_monitoreo_items_pkey PRIMARY KEY (id);


--
-- Name: tec_plantillas_objetos_monitoreo tec_plantillas_objetos_monitoreo_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_plantillas_objetos_monitoreo
    ADD CONSTRAINT tec_plantillas_objetos_monitoreo_pkey PRIMARY KEY (id);


--
-- Name: tec_pools_ips tec_pools_ips_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_pools_ips
    ADD CONSTRAINT tec_pools_ips_pkey PRIMARY KEY (id);


--
-- Name: tec_propiedades_dispositivos tec_propiedades_dispositivos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_propiedades_dispositivos
    ADD CONSTRAINT tec_propiedades_dispositivos_pkey PRIMARY KEY (id);


--
-- Name: tec_propiedades_interfaces tec_propiedades_interfaes_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_propiedades_interfaces
    ADD CONSTRAINT tec_propiedades_interfaes_pkey PRIMARY KEY (id);


--
-- Name: tec_rangos_ips tec_rangos_ips_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_rangos_ips
    ADD CONSTRAINT tec_rangos_ips_pkey PRIMARY KEY (id);


--
-- Name: tec_tipos_dispositivos tec_tipos_dispositivos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_tipos_dispositivos
    ADD CONSTRAINT tec_tipos_dispositivos_pkey PRIMARY KEY (id);


--
-- Name: tec_tipos_dispositivos_propiedades_dispositivos tec_tipos_dispositivos_propiedades_dispositivos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_tipos_dispositivos_propiedades_dispositivos
    ADD CONSTRAINT tec_tipos_dispositivos_propiedades_dispositivos_pkey PRIMARY KEY (id_propiedad, id_tipo_dispositivo);


--
-- Name: tec_tipos_dispositivos_solapas tec_tipos_dispositivos_solapas_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_tipos_dispositivos_solapas
    ADD CONSTRAINT tec_tipos_dispositivos_solapas_pkey PRIMARY KEY (id);


--
-- Name: tec_tipos_puertos_dispositivos tec_tipos_puertos_dispositivos_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_tipos_puertos_dispositivos
    ADD CONSTRAINT tec_tipos_puertos_dispositivos_pkey PRIMARY KEY (id);


--
-- Name: tec_tipos_tecnologias tec_tipos_tecnologias_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_tipos_tecnologias
    ADD CONSTRAINT tec_tipos_tecnologias_pkey PRIMARY KEY (id);


--
-- Name: tec_zonas tec_zonas_descripcion_key; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_zonas
    ADD CONSTRAINT tec_zonas_descripcion_key UNIQUE (descripcion);


--
-- Name: tec_zonas tec_zonas_pkey; Type: CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_zonas
    ADD CONSTRAINT tec_zonas_pkey PRIMARY KEY (id);


--
-- Name: campos_modificados_skey_id_evento; Type: INDEX; Schema: auditoria; Owner: spi40
--

CREATE INDEX campos_modificados_skey_id_evento ON auditoria.campos_modificados USING btree (id_registro);


--
-- Name: eventos_skey_timestamp; Type: INDEX; Schema: auditoria; Owner: spi40
--

CREATE INDEX eventos_skey_timestamp ON auditoria.eventos USING btree ("timestamp");


--
-- Name: lang_tipos_operaciones_skey_id_id_idioma; Type: INDEX; Schema: auditoria; Owner: spi40
--

CREATE INDEX lang_tipos_operaciones_skey_id_id_idioma ON auditoria.lang_tipos_operaciones USING btree (id, id_idioma);


--
-- Name: parametros_acceso_skey_id_evento; Type: INDEX; Schema: auditoria; Owner: spi40
--

CREATE INDEX parametros_acceso_skey_id_evento ON auditoria.parametros_acceso USING btree (id_evento);


--
-- Name: registros_modificados_skey_id_evento; Type: INDEX; Schema: auditoria; Owner: spi40
--

CREATE INDEX registros_modificados_skey_id_evento ON auditoria.registros_modificados USING btree (id_evento);


--
-- Name: campos_modificados_skey_id_evento; Type: INDEX; Schema: auditoria_historico; Owner: spi40
--

CREATE INDEX campos_modificados_skey_id_evento ON auditoria_historico.campos_modificados USING btree (id_registro);


--
-- Name: eventos_skey_timestamp; Type: INDEX; Schema: auditoria_historico; Owner: spi40
--

CREATE INDEX eventos_skey_timestamp ON auditoria_historico.eventos USING btree ("timestamp");


--
-- Name: parametros_acceso_skey_id_evento; Type: INDEX; Schema: auditoria_historico; Owner: spi40
--

CREATE INDEX parametros_acceso_skey_id_evento ON auditoria_historico.parametros_acceso USING btree (id_evento);


--
-- Name: registros_modificados_skey_id_evento; Type: INDEX; Schema: auditoria_historico; Owner: spi40
--

CREATE INDEX registros_modificados_skey_id_evento ON auditoria_historico.registros_modificados USING btree (id_evento);


--
-- Name: IX_Relationship10; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX "IX_Relationship10" ON public.dhcp_opciones_objetos USING btree (id_opcion);


--
-- Name: IX_Relationship11; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX "IX_Relationship11" ON public.dhcp_campos_objetos USING btree (id_objeto);


--
-- Name: IX_Relationship12; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX "IX_Relationship12" ON public.dhcp_campos_objetos USING btree (id_tipo_objeto, orden);


--
-- Name: IX_Relationship5; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX "IX_Relationship5" ON public.dhcp_mapa_tipos_objetos USING btree (id_padre);


--
-- Name: IX_Relationship6; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX "IX_Relationship6" ON public.dhcp_mapa_tipos_objetos USING btree (id_hijo);


--
-- Name: IX_Relationship8; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX "IX_Relationship8" ON public.dhcp_opciones_objetos USING btree (id_objeto);


--
-- Name: IX_Relationship9; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX "IX_Relationship9" ON public.dhcp_objetos USING btree (id_tipo_objeto);


--
-- Name: IX_dato; Type: INDEX; Schema: public; Owner: spi40
--

CREATE UNIQUE INDEX "IX_dato" ON public.dhcp_campos_objetos USING btree (id_objeto, dato);


--
-- Name: IX_dato1; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX "IX_dato1" ON public.dhcp_campos_objetos USING btree (dato);


--
-- Name: IX_dato_tipo; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX "IX_dato_tipo" ON public.dhcp_campos_objetos USING btree (id_tipo_objeto, dato);


--
-- Name: com_clientes_skey_denominacion; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX com_clientes_skey_denominacion ON public.com_clientes USING btree (denominacion);


--
-- Name: com_clientes_skey_email_contacto; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX com_clientes_skey_email_contacto ON public.com_clientes USING btree (email_contacto);


--
-- Name: com_clientes_skey_responsable; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX com_clientes_skey_responsable ON public.com_clientes USING btree (responsable);


--
-- Name: com_clientes_skey_telefono; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX com_clientes_skey_telefono ON public.com_clientes USING btree (telefono);


--
-- Name: com_clientes_skey_telefono_movil; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX com_clientes_skey_telefono_movil ON public.com_clientes USING btree (telefono_movil);


--
-- Name: com_locaciones_clientes_skey_calle; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX com_locaciones_clientes_skey_calle ON public.com_locaciones_clientes USING btree (calle);


--
-- Name: com_locaciones_clientes_skey_descripcion; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX com_locaciones_clientes_skey_descripcion ON public.com_locaciones_clientes USING btree (descripcion);


--
-- Name: com_locaciones_clientes_skey_id_cliente; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX com_locaciones_clientes_skey_id_cliente ON public.com_locaciones_clientes USING btree (id_cliente);


--
-- Name: com_locaciones_clientes_skey_responsable; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX com_locaciones_clientes_skey_responsable ON public.com_locaciones_clientes USING btree (responsable);


--
-- Name: idx_dhcp_objetos_orden; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX idx_dhcp_objetos_orden ON public.dhcp_objetos USING btree (orden);


--
-- Name: idx_dhcp_oopciones_objetos_orden; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX idx_dhcp_oopciones_objetos_orden ON public.dhcp_opciones_objetos USING btree (orden);


--
-- Name: lang_sys_estados_todo; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX lang_sys_estados_todo ON public.lang_sys_estados USING btree (id_tipo_estado, id_estado, id_idioma);


--
-- Name: svc_servicios_propiedades_skey_id_propiedad_valor; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX svc_servicios_propiedades_skey_id_propiedad_valor ON public.svc_servicios_propiedades USING btree (id_propiedad, valor);


--
-- Name: svc_servicios_propiedades_skey_valor; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX svc_servicios_propiedades_skey_valor ON public.svc_servicios_propiedades USING btree (valor);


--
-- Name: sys_eventos_index_id_padre_id_estado; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX sys_eventos_index_id_padre_id_estado ON public.sys_eventos USING btree (id, id_padre, estado);


--
-- Name: sys_eventos_index_id_tipo_evento; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX sys_eventos_index_id_tipo_evento ON public.sys_eventos USING btree (id_tipo_evento);


--
-- Name: sys_operadores_login_key; Type: INDEX; Schema: public; Owner: spi40
--

CREATE UNIQUE INDEX sys_operadores_login_key ON public.sys_operadores USING btree (login);


--
-- Name: tec_dispositivos_etiquetas_dispositivos_skey_valor; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX tec_dispositivos_etiquetas_dispositivos_skey_valor ON public.tec_dispositivos_etiquetas_dispositivos USING btree (valor);


--
-- Name: tec_dispositivos_id_dispositivo_id_propiedad_key; Type: INDEX; Schema: public; Owner: spi40
--

CREATE UNIQUE INDEX tec_dispositivos_id_dispositivo_id_propiedad_key ON public.tec_dispositivos_propiedades_dispositivos USING btree (id_dispositivo, id_propiedad, valor);


--
-- Name: tec_dispositivos_interfaces_idx1; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX tec_dispositivos_interfaces_idx1 ON public.tec_dispositivos_interfaces USING btree (id_dispositivo, id);


--
-- Name: tec_dispositivos_interfaces_idx2; Type: INDEX; Schema: public; Owner: spi40
--

CREATE UNIQUE INDEX tec_dispositivos_interfaces_idx2 ON public.tec_dispositivos_interfaces USING btree (id_dispositivo, ifindex);


--
-- Name: tec_dispositivos_skey_valor; Type: INDEX; Schema: public; Owner: spi40
--

CREATE INDEX tec_dispositivos_skey_valor ON public.tec_dispositivos USING btree (descripcion);


--
-- Name: com_locaciones_clientes_packs_servicios actualiza_fecha_cambio_estado; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER actualiza_fecha_cambio_estado BEFORE UPDATE ON public.com_locaciones_clientes_packs_servicios FOR EACH ROW EXECUTE FUNCTION public.actualizar_fecha_servicio();


--
-- Name: com_clientes auditar_com_clientes; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_com_clientes AFTER INSERT OR DELETE OR UPDATE ON public.com_clientes FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: com_locaciones_clientes auditar_com_locaciones_clientes; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_com_locaciones_clientes AFTER INSERT OR DELETE OR UPDATE ON public.com_locaciones_clientes FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: com_locaciones_clientes_packs auditar_com_locaciones_clientes_packs; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_com_locaciones_clientes_packs AFTER INSERT OR DELETE OR UPDATE ON public.com_locaciones_clientes_packs FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: com_locaciones_clientes_packs_servicios auditar_com_locaciones_clientes_packs_servicios; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_com_locaciones_clientes_packs_servicios AFTER INSERT OR DELETE OR UPDATE ON public.com_locaciones_clientes_packs_servicios FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: com_localidades auditar_com_localidades; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_com_localidades AFTER INSERT OR DELETE OR UPDATE ON public.com_localidades FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: com_packs auditar_com_packs; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_com_packs AFTER INSERT OR DELETE OR UPDATE ON public.com_packs FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: com_packs_contenido auditar_com_packs_contenido; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_com_packs_contenido AFTER INSERT OR DELETE OR UPDATE ON public.com_packs_contenido FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: com_paises auditar_com_paises; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_com_paises AFTER INSERT OR DELETE OR UPDATE ON public.com_paises FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: com_provincias auditar_com_provincias; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_com_provincias AFTER INSERT OR DELETE OR UPDATE ON public.com_provincias FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: svc_servicios auditar_svc_servicios; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_svc_servicios AFTER INSERT OR DELETE OR UPDATE ON public.svc_servicios FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: svc_servicios_grupos auditar_svc_servicios_grupos; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_svc_servicios_grupos AFTER INSERT OR DELETE OR UPDATE ON public.svc_servicios_grupos FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: svc_servicios_propiedades auditar_svc_servicios_propiedades; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_svc_servicios_propiedades AFTER INSERT OR DELETE OR UPDATE ON public.svc_servicios_propiedades FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: svc_servicios_propiedades_internas auditar_svc_servicios_propiedades_internas; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_svc_servicios_propiedades_internas AFTER INSERT OR DELETE OR UPDATE ON public.svc_servicios_propiedades_internas FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: tec_dispositivos auditar_tec_dispositivos; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_tec_dispositivos AFTER INSERT OR DELETE OR UPDATE ON public.tec_dispositivos FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: tec_dispositivos_etiquetas_dispositivos auditar_tec_dispositivos_etiquetas_dispositivos; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_tec_dispositivos_etiquetas_dispositivos AFTER INSERT OR DELETE OR UPDATE ON public.tec_dispositivos_etiquetas_dispositivos FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: tec_dispositivos_interfaces auditar_tec_dispositivos_interfaces; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_tec_dispositivos_interfaces AFTER INSERT OR DELETE OR UPDATE ON public.tec_dispositivos_interfaces FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: tec_dispositivos_interfaces_propiedades auditar_tec_dispositivos_interfaces_propiedades; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_tec_dispositivos_interfaces_propiedades AFTER INSERT OR DELETE OR UPDATE ON public.tec_dispositivos_interfaces_propiedades FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: tec_marcas auditar_tec_marcas; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_tec_marcas AFTER INSERT OR DELETE OR UPDATE ON public.tec_marcas FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: tec_modelos auditar_tec_modelos; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_tec_modelos AFTER INSERT OR DELETE OR UPDATE ON public.tec_modelos FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: tec_modelos_etiquetas_dispositivos auditar_tec_modelos_etiquetas_dispositivos; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_tec_modelos_etiquetas_dispositivos AFTER INSERT OR DELETE OR UPDATE ON public.tec_modelos_etiquetas_dispositivos FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: tec_modelos_propiedades_interfaces auditar_tec_modelos_propiedades_interfaces; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_tec_modelos_propiedades_interfaces AFTER INSERT OR DELETE OR UPDATE ON public.tec_modelos_propiedades_interfaces FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: tec_modelos_puertos auditar_tec_modelos_puertos; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_tec_modelos_puertos AFTER INSERT OR DELETE OR UPDATE ON public.tec_modelos_puertos FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: tec_zonas auditar_tec_zonas; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER auditar_tec_zonas AFTER INSERT OR DELETE OR UPDATE ON public.tec_zonas FOR EACH ROW EXECUTE FUNCTION public.auditar_tabla();


--
-- Name: com_locaciones_clientes_packs cambio_estado_com_locaciones_clientes_packs; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER cambio_estado_com_locaciones_clientes_packs AFTER INSERT OR DELETE OR UPDATE ON public.com_locaciones_clientes_packs FOR EACH ROW EXECUTE FUNCTION public.setear_flags_abns();


--
-- Name: com_locaciones_clientes_packs_servicios cambio_estado_com_locaciones_clientes_packs_servicios; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER cambio_estado_com_locaciones_clientes_packs_servicios AFTER INSERT OR DELETE OR UPDATE ON public.com_locaciones_clientes_packs_servicios FOR EACH ROW EXECUTE FUNCTION public.setear_flags_abns();


--
-- Name: svc_servicios_propiedades cambio_valor_servicios_propiedades; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER cambio_valor_servicios_propiedades AFTER INSERT OR DELETE OR UPDATE ON public.svc_servicios_propiedades FOR EACH ROW EXECUTE FUNCTION public.setear_flags_abns();


--
-- Name: svc_servicios_propiedades_internas cambio_valor_servicios_propiedades_internas; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER cambio_valor_servicios_propiedades_internas AFTER INSERT OR DELETE OR UPDATE ON public.svc_servicios_propiedades_internas FOR EACH ROW EXECUTE FUNCTION public.setear_flags_abns();


--
-- Name: cfg_servidores_grupos_servidores chequear_relacion_servidor_grupo; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER chequear_relacion_servidor_grupo AFTER INSERT OR UPDATE ON public.cfg_servidores_grupos_servidores FOR EACH ROW EXECUTE FUNCTION public.chequear_servidor_grupo();


--
-- Name: sys_idiomas crear_dependencias_idiomas; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER crear_dependencias_idiomas AFTER INSERT OR UPDATE ON public.sys_idiomas FOR EACH ROW EXECUTE FUNCTION public.crear_dependencias_idioma();


--
-- Name: svc_servicios plg_1000_cm_cambio_servicio; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER plg_1000_cm_cambio_servicio AFTER INSERT OR DELETE OR UPDATE ON public.svc_servicios FOR EACH ROW EXECUTE FUNCTION public.plg_1000_cm_cambio_servicio_setear_flag();


--
-- Name: plg_1000_cm_servicios_explog plg_1000_cm_chequear_dependencias_explog; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER plg_1000_cm_chequear_dependencias_explog BEFORE INSERT OR UPDATE ON public.plg_1000_cm_servicios_explog FOR EACH ROW EXECUTE FUNCTION public.plg_1000_cm_chequear_dependencias_servicios_explog();


--
-- Name: plg_1000_cm_modelos_explog_especifica plg_1000_cm_chequear_dependencias_explog_especifica; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER plg_1000_cm_chequear_dependencias_explog_especifica AFTER DELETE ON public.plg_1000_cm_modelos_explog_especifica FOR EACH ROW EXECUTE FUNCTION public.plg_1000_cm_chequear_dependencias_modelos_explog_especifica();


--
-- Name: svc_servicios_propiedades plg_1000_cm_impedir_cm_duplicado_en_servicios; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER plg_1000_cm_impedir_cm_duplicado_en_servicios BEFORE INSERT OR UPDATE ON public.svc_servicios_propiedades FOR EACH ROW EXECUTE FUNCTION public.plg_1000_cm_chequear_cm_duplicado_en_servicios();


--
-- Name: tec_rangos_ips plg_1000_cm_tec_rangos_ips; Type: TRIGGER; Schema: public; Owner: spi40
--

CREATE TRIGGER plg_1000_cm_tec_rangos_ips AFTER DELETE OR UPDATE ON public.tec_rangos_ips FOR EACH ROW EXECUTE FUNCTION public.plg_1000_cm_chequear_dependencias_rangos_ip();


--
-- Name: campos_modificados campos_modificados_id_registro_fkey; Type: FK CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.campos_modificados
    ADD CONSTRAINT campos_modificados_id_registro_fkey FOREIGN KEY (id_registro) REFERENCES auditoria.registros_modificados(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: eventos eventos_id_entidad_fkey; Type: FK CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.eventos
    ADD CONSTRAINT eventos_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES public.sys_entidades(id) ON UPDATE CASCADE;


--
-- Name: eventos eventos_id_operador_fkey; Type: FK CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.eventos
    ADD CONSTRAINT eventos_id_operador_fkey FOREIGN KEY (id_operador) REFERENCES public.sys_operadores(id) ON UPDATE CASCADE;


--
-- Name: lang_tipos_operaciones lang_tipos_operaciones_idioma_fkey; Type: FK CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.lang_tipos_operaciones
    ADD CONSTRAINT lang_tipos_operaciones_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE;


--
-- Name: parametros_acceso parametros_acceso_id_evento_fkey; Type: FK CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.parametros_acceso
    ADD CONSTRAINT parametros_acceso_id_evento_fkey FOREIGN KEY (id_evento) REFERENCES auditoria.eventos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: registros_modificados registros_modificados_id_evento_fkey; Type: FK CONSTRAINT; Schema: auditoria; Owner: spi40
--

ALTER TABLE ONLY auditoria.registros_modificados
    ADD CONSTRAINT registros_modificados_id_evento_fkey FOREIGN KEY (id_evento) REFERENCES auditoria.eventos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: campos_modificados campos_modificados_id_registro_fkey; Type: FK CONSTRAINT; Schema: auditoria_historico; Owner: spi40
--

ALTER TABLE ONLY auditoria_historico.campos_modificados
    ADD CONSTRAINT campos_modificados_id_registro_fkey FOREIGN KEY (id_registro) REFERENCES auditoria_historico.registros_modificados(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: eventos eventos_id_entidad_fkey; Type: FK CONSTRAINT; Schema: auditoria_historico; Owner: spi40
--

ALTER TABLE ONLY auditoria_historico.eventos
    ADD CONSTRAINT eventos_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES public.sys_entidades(id) ON UPDATE CASCADE;


--
-- Name: eventos eventos_id_operador_fkey; Type: FK CONSTRAINT; Schema: auditoria_historico; Owner: spi40
--

ALTER TABLE ONLY auditoria_historico.eventos
    ADD CONSTRAINT eventos_id_operador_fkey FOREIGN KEY (id_operador) REFERENCES public.sys_operadores(id) ON UPDATE CASCADE;


--
-- Name: parametros_acceso parametros_acceso_id_evento_fkey; Type: FK CONSTRAINT; Schema: auditoria_historico; Owner: spi40
--

ALTER TABLE ONLY auditoria_historico.parametros_acceso
    ADD CONSTRAINT parametros_acceso_id_evento_fkey FOREIGN KEY (id_evento) REFERENCES auditoria_historico.eventos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: registros_modificados registros_modificados_id_evento_fkey; Type: FK CONSTRAINT; Schema: auditoria_historico; Owner: spi40
--

ALTER TABLE ONLY auditoria_historico.registros_modificados
    ADD CONSTRAINT registros_modificados_id_evento_fkey FOREIGN KEY (id_evento) REFERENCES auditoria_historico.eventos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cfg_configuraciones cfg_configuraciones_id_grupo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.cfg_configuraciones
    ADD CONSTRAINT cfg_configuraciones_id_grupo_fkey FOREIGN KEY (id_grupo) REFERENCES public.cfg_grupos_configuraciones(id) ON DELETE CASCADE;


--
-- Name: cfg_servidores_grupos_servidores cfg_servidores_grupos_servidores_id_grupo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.cfg_servidores_grupos_servidores
    ADD CONSTRAINT cfg_servidores_grupos_servidores_id_grupo_fkey FOREIGN KEY (id_grupo) REFERENCES public.cfg_servidores_spi(id) ON DELETE CASCADE;


--
-- Name: cfg_servidores_grupos_servidores cfg_servidores_grupos_servidores_id_servidor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.cfg_servidores_grupos_servidores
    ADD CONSTRAINT cfg_servidores_grupos_servidores_id_servidor_fkey FOREIGN KEY (id_servidor) REFERENCES public.cfg_servidores_spi(id) ON DELETE CASCADE;


--
-- Name: com_clientes com_clientes_id_locacion_principal_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_clientes
    ADD CONSTRAINT com_clientes_id_locacion_principal_fkey FOREIGN KEY (id_locacion_principal) REFERENCES public.com_locaciones_clientes(id) ON DELETE RESTRICT;


--
-- Name: com_locaciones_clientes com_locaciones_clientes_id_cliente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_locaciones_clientes
    ADD CONSTRAINT com_locaciones_clientes_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.com_clientes(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: com_locaciones_clientes com_locaciones_clientes_id_localidad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_locaciones_clientes
    ADD CONSTRAINT com_locaciones_clientes_id_localidad_fkey FOREIGN KEY (id_localidad) REFERENCES public.com_localidades(id) ON DELETE RESTRICT;


--
-- Name: com_locaciones_clientes com_locaciones_clientes_id_pais_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_locaciones_clientes
    ADD CONSTRAINT com_locaciones_clientes_id_pais_fkey FOREIGN KEY (id_pais) REFERENCES public.com_paises(id) ON DELETE RESTRICT;


--
-- Name: com_locaciones_clientes com_locaciones_clientes_id_provincia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_locaciones_clientes
    ADD CONSTRAINT com_locaciones_clientes_id_provincia_fkey FOREIGN KEY (id_provincia) REFERENCES public.com_provincias(id) ON DELETE RESTRICT;


--
-- Name: com_locaciones_clientes com_locaciones_clientes_id_zona_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_locaciones_clientes
    ADD CONSTRAINT com_locaciones_clientes_id_zona_fkey FOREIGN KEY (id_zona) REFERENCES public.tec_zonas(id) ON DELETE RESTRICT;


--
-- Name: com_locaciones_clientes_packs com_locaciones_clientes_packs_id_locacion_cliente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_locaciones_clientes_packs
    ADD CONSTRAINT com_locaciones_clientes_packs_id_locacion_cliente_fkey FOREIGN KEY (id_locacion_cliente) REFERENCES public.com_locaciones_clientes(id) ON DELETE RESTRICT;


--
-- Name: com_locaciones_clientes_packs com_locaciones_clientes_packs_id_pack_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_locaciones_clientes_packs
    ADD CONSTRAINT com_locaciones_clientes_packs_id_pack_fkey FOREIGN KEY (id_pack) REFERENCES public.com_packs(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: com_locaciones_clientes_packs_servicios com_locaciones_clientes_packs_ser_id_locacion_cliente_pack_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_locaciones_clientes_packs_servicios
    ADD CONSTRAINT com_locaciones_clientes_packs_ser_id_locacion_cliente_pack_fkey FOREIGN KEY (id_locacion_cliente_pack) REFERENCES public.com_locaciones_clientes_packs(id) ON DELETE CASCADE;


--
-- Name: com_locaciones_clientes_packs_servicios com_locaciones_clientes_packs_servicios_id_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_locaciones_clientes_packs_servicios
    ADD CONSTRAINT com_locaciones_clientes_packs_servicios_id_servicio_fkey FOREIGN KEY (id_servicio) REFERENCES public.svc_servicios(id) ON DELETE RESTRICT;


--
-- Name: com_localidades com_localidades_id_provincia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_localidades
    ADD CONSTRAINT com_localidades_id_provincia_fkey FOREIGN KEY (id_provincia) REFERENCES public.com_provincias(id);


--
-- Name: com_packs_contenido com_packs_contenido_id_pack_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_packs_contenido
    ADD CONSTRAINT com_packs_contenido_id_pack_fkey FOREIGN KEY (id_pack) REFERENCES public.com_packs(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: com_provincias com_provincias_id_pais_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.com_provincias
    ADD CONSTRAINT com_provincias_id_pais_fkey FOREIGN KEY (id_pais) REFERENCES public.com_paises(id);


--
-- Name: dhcp_campos_objetos dhcp_campos_objetos_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_campos_objetos
    ADD CONSTRAINT dhcp_campos_objetos_id_fkey FOREIGN KEY (id_objeto) REFERENCES public.dhcp_objetos(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: dhcp_campos_objetos dhcp_campos_objetos_id_tipo_objeto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_campos_objetos
    ADD CONSTRAINT dhcp_campos_objetos_id_tipo_objeto_fkey FOREIGN KEY (id_tipo_objeto, orden) REFERENCES public.dhcp_campos(id_tipo_objeto, orden) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: dhcp_campos dhcp_campos_tipo_datos_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_campos
    ADD CONSTRAINT dhcp_campos_tipo_datos_fkey FOREIGN KEY (id_tipo_dato) REFERENCES public.dhcp_tipos_datos(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: dhcp_mapa_tipos_objetos dhcp_mapa_tipos_objetos_id_hijo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_mapa_tipos_objetos
    ADD CONSTRAINT dhcp_mapa_tipos_objetos_id_hijo_fkey FOREIGN KEY (id_hijo) REFERENCES public.dhcp_tipos_objetos(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: dhcp_mapa_tipos_objetos dhcp_mapa_tipos_objetos_id_padre_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_mapa_tipos_objetos
    ADD CONSTRAINT dhcp_mapa_tipos_objetos_id_padre_fkey FOREIGN KEY (id_padre) REFERENCES public.dhcp_tipos_objetos(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: dhcp_objetos dhcp_objetos_id_padre_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_objetos
    ADD CONSTRAINT dhcp_objetos_id_padre_fkey FOREIGN KEY (id_padre) REFERENCES public.dhcp_objetos(id) ON DELETE CASCADE;


--
-- Name: dhcp_objetos dhcp_objetos_id_servidor_grupo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_objetos
    ADD CONSTRAINT dhcp_objetos_id_servidor_grupo_fkey FOREIGN KEY (id_servidor_grupo) REFERENCES public.cfg_servidores_spi(id);


--
-- Name: dhcp_objetos dhcp_objetos_id_tipo_objeto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_objetos
    ADD CONSTRAINT dhcp_objetos_id_tipo_objeto_fkey FOREIGN KEY (id_tipo_objeto) REFERENCES public.dhcp_tipos_objetos(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: dhcp_opciones dhcp_opciones_id_especial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_opciones
    ADD CONSTRAINT dhcp_opciones_id_especial_fkey FOREIGN KEY (id_especial) REFERENCES public.dhcp_opciones_especiales(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: dhcp_opciones_objetos dhcp_opciones_objetos_id_objeto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_opciones_objetos
    ADD CONSTRAINT dhcp_opciones_objetos_id_objeto_fkey FOREIGN KEY (id_objeto) REFERENCES public.dhcp_objetos(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: dhcp_opciones_objetos dhcp_opciones_objetos_id_opcion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_opciones_objetos
    ADD CONSTRAINT dhcp_opciones_objetos_id_opcion_fkey FOREIGN KEY (id_opcion) REFERENCES public.dhcp_opciones(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: dhcp_opciones_objetos dhcp_opciones_objetos_id_servidor_grupo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_opciones_objetos
    ADD CONSTRAINT dhcp_opciones_objetos_id_servidor_grupo_fkey FOREIGN KEY (id_servidor_grupo) REFERENCES public.cfg_servidores_spi(id);


--
-- Name: dhcp_opciones dhcp_opciones_tipo_dato_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.dhcp_opciones
    ADD CONSTRAINT dhcp_opciones_tipo_dato_fkey FOREIGN KEY (id_tipo_dato) REFERENCES public.dhcp_tipos_datos(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: sys_propiedades_abns id_abn_id_abn_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_propiedades_abns
    ADD CONSTRAINT id_abn_id_abn_fkey FOREIGN KEY (id_abn) REFERENCES public.sys_abns(id) ON DELETE CASCADE;


--
-- Name: lang_cfg_configuraciones lang_cfg_configuraciones_id_configuracion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_cfg_configuraciones
    ADD CONSTRAINT lang_cfg_configuraciones_id_configuracion_fkey FOREIGN KEY (id_configuracion) REFERENCES public.cfg_configuraciones(id) ON DELETE CASCADE;


--
-- Name: lang_cfg_configuraciones lang_cfg_configuraciones_id_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_cfg_configuraciones
    ADD CONSTRAINT lang_cfg_configuraciones_id_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON DELETE CASCADE;


--
-- Name: lang_cfg_grupos_configuraciones lang_cfg_grupos_configuraciones_id_grupo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_cfg_grupos_configuraciones
    ADD CONSTRAINT lang_cfg_grupos_configuraciones_id_grupo_fkey FOREIGN KEY (id_grupo) REFERENCES public.cfg_grupos_configuraciones(id) ON DELETE CASCADE;


--
-- Name: lang_cfg_grupos_configuraciones lang_cfg_grupos_configuraciones_id_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_cfg_grupos_configuraciones
    ADD CONSTRAINT lang_cfg_grupos_configuraciones_id_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON DELETE CASCADE;


--
-- Name: lang_svc_dependencias lang_svc_dependencias_id_dependencia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_svc_dependencias
    ADD CONSTRAINT lang_svc_dependencias_id_dependencia_fkey FOREIGN KEY (id_dependencia) REFERENCES public.svc_dependencias(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_svc_dependencias lang_svc_dependencias_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_svc_dependencias
    ADD CONSTRAINT lang_svc_dependencias_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_svc_propiedades lang_svc_dependencias_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_svc_propiedades
    ADD CONSTRAINT lang_svc_dependencias_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_tec_propiedades_interfaces lang_svc_dependencias_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tec_propiedades_interfaces
    ADD CONSTRAINT lang_svc_dependencias_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_svc_propiedades lang_svc_propiedades_id_propiedad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_svc_propiedades
    ADD CONSTRAINT lang_svc_propiedades_id_propiedad_fkey FOREIGN KEY (id_propiedad) REFERENCES public.svc_propiedades(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_svc_requisitos lang_svc_requisitos_id_requisito_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_svc_requisitos
    ADD CONSTRAINT lang_svc_requisitos_id_requisito_fkey FOREIGN KEY (id_requisito) REFERENCES public.svc_requisitos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_svc_requisitos lang_svc_requisitos_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_svc_requisitos
    ADD CONSTRAINT lang_svc_requisitos_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_svc_tipos_servicios lang_svc_tipos_servicios_id_tipo_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_svc_tipos_servicios
    ADD CONSTRAINT lang_svc_tipos_servicios_id_tipo_servicio_fkey FOREIGN KEY (id_tipo_servicio) REFERENCES public.svc_tipos_servicios(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_svc_tipos_servicios lang_svc_tipos_servicios_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_svc_tipos_servicios
    ADD CONSTRAINT lang_svc_tipos_servicios_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_sys_abns lang_sys_abns_id_abn_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_abns
    ADD CONSTRAINT lang_sys_abns_id_abn_fkey FOREIGN KEY (id_abn) REFERENCES public.sys_abns(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_sys_entidades lang_sys_entidades_entidad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_entidades
    ADD CONSTRAINT lang_sys_entidades_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES public.sys_entidades(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_sys_entidades lang_sys_entidades_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_entidades
    ADD CONSTRAINT lang_sys_entidades_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_sys_estados lang_sys_estados_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_estados
    ADD CONSTRAINT lang_sys_estados_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_sys_listados lang_sys_listados_id_listado_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_listados
    ADD CONSTRAINT lang_sys_listados_id_listado_fkey FOREIGN KEY (id_listado) REFERENCES public.sys_listados(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_sys_listados lang_sys_listados_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_listados
    ADD CONSTRAINT lang_sys_listados_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_tec_objetos_monitoreo_columnas_extras lang_sys_listados_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tec_objetos_monitoreo_columnas_extras
    ADD CONSTRAINT lang_sys_listados_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_sys_abns lang_sys_plugins_id_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_abns
    ADD CONSTRAINT lang_sys_plugins_id_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_sys_plugins lang_sys_plugins_id_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_plugins
    ADD CONSTRAINT lang_sys_plugins_id_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_sys_plugins lang_sys_plugins_id_plugin_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_plugins
    ADD CONSTRAINT lang_sys_plugins_id_plugin_fkey FOREIGN KEY (id_plugin) REFERENCES public.sys_plugins(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_sys_tipos_eventos lang_sys_tipos_eventos_id_tipo_evento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_tipos_eventos
    ADD CONSTRAINT lang_sys_tipos_eventos_id_tipo_evento_fkey FOREIGN KEY (id_tipo_evento) REFERENCES public.sys_tipos_eventos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_sys_tipos_eventos lang_sys_tipos_eventos_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_sys_tipos_eventos
    ADD CONSTRAINT lang_sys_tipos_eventos_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_tablas_auditoria lang_tablas_auditoria_id_tabla_auditoria_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tablas_auditoria
    ADD CONSTRAINT lang_tablas_auditoria_id_tabla_auditoria_fkey FOREIGN KEY (id_tabla_auditoria) REFERENCES public.sys_tablas_auditoria(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_tablas_auditoria lang_tablas_auditoria_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tablas_auditoria
    ADD CONSTRAINT lang_tablas_auditoria_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_tec_propiedades_dispositivos lang_tec_propiedades_dispositivos_id_propiedad_dispositivo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tec_propiedades_dispositivos
    ADD CONSTRAINT lang_tec_propiedades_dispositivos_id_propiedad_dispositivo_fkey FOREIGN KEY (id_propiedad_dispositivo) REFERENCES public.tec_propiedades_dispositivos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_tec_propiedades_dispositivos lang_tec_propiedades_dispositivos_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tec_propiedades_dispositivos
    ADD CONSTRAINT lang_tec_propiedades_dispositivos_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_tec_propiedades_interfaces lang_tec_propiedades_interfaces_id_propiedad_interface_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tec_propiedades_interfaces
    ADD CONSTRAINT lang_tec_propiedades_interfaces_id_propiedad_interface_fkey FOREIGN KEY (id_propiedad_interface) REFERENCES public.tec_propiedades_interfaces(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_tec_tipos_tecnologias lang_tec_tipos_tecnologias_id_tipo_tecnologia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tec_tipos_tecnologias
    ADD CONSTRAINT lang_tec_tipos_tecnologias_id_tipo_tecnologia_fkey FOREIGN KEY (id_tipo_tecnologia) REFERENCES public.tec_tipos_tecnologias(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: lang_tec_tipos_tecnologias lang_tec_tipos_tecnologias_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.lang_tec_tipos_tecnologias
    ADD CONSTRAINT lang_tec_tipos_tecnologias_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: newsletter_destinatarios newsletter_destinatarios_id_tarea_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.newsletter_destinatarios
    ADD CONSTRAINT newsletter_destinatarios_id_tarea_fkey FOREIGN KEY (id_tarea) REFERENCES public.newsletter_tareas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_1000_cm_dispositivos_interfaces_pools_ip plg_1000_cm_interfaces_pools_id_dispositivo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_dispositivos_interfaces_pools_ip
    ADD CONSTRAINT plg_1000_cm_interfaces_pools_id_dispositivo_fkey FOREIGN KEY (id_dispositivo) REFERENCES public.tec_dispositivos(id) ON DELETE CASCADE;


--
-- Name: plg_1000_cm_dispositivos_interfaces_pools_ip plg_1000_cm_interfaces_pools_id_interface_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_dispositivos_interfaces_pools_ip
    ADD CONSTRAINT plg_1000_cm_interfaces_pools_id_interface_fkey FOREIGN KEY (id) REFERENCES public.tec_dispositivos_interfaces(id) ON DELETE CASCADE;


--
-- Name: plg_1000_cm_dispositivos_interfaces_pools_ip plg_1000_cm_interfaces_pools_id_pool_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_dispositivos_interfaces_pools_ip
    ADD CONSTRAINT plg_1000_cm_interfaces_pools_id_pool_fkey FOREIGN KEY (id_pool) REFERENCES public.tec_pools_ips(id) ON DELETE CASCADE;


--
-- Name: plg_1000_cm_modelos_explog_especifica plg_1000_cm_modelos_explog_especifica_id_modelo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_modelos_explog_especifica
    ADD CONSTRAINT plg_1000_cm_modelos_explog_especifica_id_modelo_fkey FOREIGN KEY (id_modelo) REFERENCES public.tec_modelos(id) ON DELETE CASCADE;


--
-- Name: plg_1000_cm_modelos_explog plg_1000_cm_modelos_explog_id_modelo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_modelos_explog
    ADD CONSTRAINT plg_1000_cm_modelos_explog_id_modelo_fkey FOREIGN KEY (id_modelo) REFERENCES public.tec_modelos(id) ON DELETE CASCADE;


--
-- Name: plg_1000_cm_modelos_ipv6 plg_1000_cm_modelos_ipv6_id_modelo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_modelos_ipv6
    ADD CONSTRAINT plg_1000_cm_modelos_ipv6_id_modelo_fkey FOREIGN KEY (id_modelo) REFERENCES public.tec_modelos(id) ON DELETE CASCADE;


--
-- Name: plg_1000_cm_servicios_explog plg_1000_cm_servicios_explog_id_grupo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_servicios_explog
    ADD CONSTRAINT plg_1000_cm_servicios_explog_id_grupo_fkey FOREIGN KEY (id_grupo) REFERENCES public.svc_servicios_grupos(id) ON DELETE RESTRICT;


--
-- Name: plg_1000_cm_servicios_explog plg_1000_servicios_exlog_id_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_1000_cm_servicios_explog
    ADD CONSTRAINT plg_1000_servicios_exlog_id_servicio_fkey FOREIGN KEY (id_servicio) REFERENCES public.svc_servicios(id) ON DELETE CASCADE;


--
-- Name: plg_14000_alertas_notificaciones_alertas_tipo_notificaciones plg_14000_alert_notif_alert_tipo_notif_id_alert_tipo_notif_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_notificaciones_alertas_tipo_notificaciones
    ADD CONSTRAINT plg_14000_alert_notif_alert_tipo_notif_id_alert_tipo_notif_fkey FOREIGN KEY (id_alerta_tipo_notificacion) REFERENCES public.plg_14000_alertas_tipo_notificaciones(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_14000_alertas_alertas_notificaciones plg_14000_alertas_alertas_notificaciones_id_alerta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_alertas_notificaciones
    ADD CONSTRAINT plg_14000_alertas_alertas_notificaciones_id_alerta_fkey FOREIGN KEY (id_alerta) REFERENCES public.plg_14000_alertas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_14000_alertas_alertas_notificaciones plg_14000_alertas_alertas_notificaciones_id_alerta_notificacion; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_alertas_notificaciones
    ADD CONSTRAINT plg_14000_alertas_alertas_notificaciones_id_alerta_notificacion FOREIGN KEY (id_alerta_notificacion) REFERENCES public.plg_14000_alertas_notificaciones(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_14000_alertas_contactos_alertas_contactos plg_14000_alertas_contactos_ale_alerta_contacto_nodo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_contactos_alertas_contactos
    ADD CONSTRAINT plg_14000_alertas_contactos_ale_alerta_contacto_nodo_fkey FOREIGN KEY (alerta_contacto_nodo) REFERENCES public.plg_14000_alertas_contactos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_14000_alertas_contactos_alertas_contactos plg_14000_alertas_contactos_ale_id_alerta_contacto_grupo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_contactos_alertas_contactos
    ADD CONSTRAINT plg_14000_alertas_contactos_ale_id_alerta_contacto_grupo_fkey FOREIGN KEY (id_alerta_contacto_grupo) REFERENCES public.plg_14000_alertas_contactos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_14000_alertas plg_14000_alertas_id_alerta_padre_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas
    ADD CONSTRAINT plg_14000_alertas_id_alerta_padre_fkey FOREIGN KEY (id_alerta_padre) REFERENCES public.plg_14000_alertas(id) ON UPDATE CASCADE;


--
-- Name: plg_14000_alertas plg_14000_alertas_id_categoria_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas
    ADD CONSTRAINT plg_14000_alertas_id_categoria_fkey FOREIGN KEY (id_categoria) REFERENCES public.plg_14000_alertas_categorias(id) ON UPDATE CASCADE;


--
-- Name: plg_14000_alertas plg_14000_alertas_id_dispositivo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas
    ADD CONSTRAINT plg_14000_alertas_id_dispositivo_fkey FOREIGN KEY (id_dispositivo) REFERENCES public.tec_dispositivos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_14000_alertas plg_14000_alertas_id_objeto_monitoreo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas
    ADD CONSTRAINT plg_14000_alertas_id_objeto_monitoreo_fkey FOREIGN KEY (id_objeto_monitoreo) REFERENCES public.tec_objetos_monitoreo(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_14000_alertas_logs plg_14000_alertas_logs_id_alerta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_logs
    ADD CONSTRAINT plg_14000_alertas_logs_id_alerta_fkey FOREIGN KEY (id_alerta) REFERENCES public.plg_14000_alertas(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_14000_alertas_logs plg_14000_alertas_logs_id_contacto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_logs
    ADD CONSTRAINT plg_14000_alertas_logs_id_contacto_fkey FOREIGN KEY (id_contacto) REFERENCES public.plg_14000_alertas_contactos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_14000_alertas_logs plg_14000_alertas_logs_id_notificacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_logs
    ADD CONSTRAINT plg_14000_alertas_logs_id_notificacion_fkey FOREIGN KEY (id_notificacion) REFERENCES public.plg_14000_alertas_notificaciones(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_14000_alertas_logs plg_14000_alertas_logs_id_operador_desactivo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_logs
    ADD CONSTRAINT plg_14000_alertas_logs_id_operador_desactivo_fkey FOREIGN KEY (id_operador_desactivo) REFERENCES public.sys_operadores(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: plg_14000_alertas_notificaciones_alertas_tipo_notificaciones plg_14000_alertas_notif_alertas_tipo_notif_id_alerta_notif_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_notificaciones_alertas_tipo_notificaciones
    ADD CONSTRAINT plg_14000_alertas_notif_alertas_tipo_notif_id_alerta_notif_fkey FOREIGN KEY (id_alerta_notificacion) REFERENCES public.plg_14000_alertas_notificaciones(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_14000_alertas_notificaciones_alertas_contactos plg_14000_alertas_notificaciones_alertas_cont_id_alerta_contact; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_notificaciones_alertas_contactos
    ADD CONSTRAINT plg_14000_alertas_notificaciones_alertas_cont_id_alerta_contact FOREIGN KEY (id_alerta_contacto) REFERENCES public.plg_14000_alertas_contactos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: plg_14000_alertas_notificaciones_alertas_contactos plg_14000_alertas_notificaciones_alertas_id_alerta_notificacion; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.plg_14000_alertas_notificaciones_alertas_contactos
    ADD CONSTRAINT plg_14000_alertas_notificaciones_alertas_id_alerta_notificacion FOREIGN KEY (id_alerta_notificacion) REFERENCES public.plg_14000_alertas_notificaciones(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: svc_dependencias svc_dependencias_id_tipo_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_dependencias
    ADD CONSTRAINT svc_dependencias_id_tipo_servicio_fkey FOREIGN KEY (id_tipo_servicio) REFERENCES public.svc_tipos_servicios(id) ON DELETE CASCADE;


--
-- Name: svc_dependencias svc_dependencias_id_tipo_tecnologia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_dependencias
    ADD CONSTRAINT svc_dependencias_id_tipo_tecnologia_fkey FOREIGN KEY (id_tipo_tecnologia) REFERENCES public.tec_tipos_tecnologias(id) ON DELETE CASCADE;


--
-- Name: svc_elegidos svc_elegidos_id_cliente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_elegidos
    ADD CONSTRAINT svc_elegidos_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.com_clientes(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: svc_elegidos svc_elegidos_id_locacion_cliente_pack_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_elegidos
    ADD CONSTRAINT svc_elegidos_id_locacion_cliente_pack_fkey FOREIGN KEY (id_locacion_cliente_pack_servicio) REFERENCES public.com_locaciones_clientes_packs_servicios(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: svc_elegidos svc_elegidos_id_locacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_elegidos
    ADD CONSTRAINT svc_elegidos_id_locacion_fkey FOREIGN KEY (id_locacion_cliente) REFERENCES public.com_locaciones_clientes(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: svc_elegidos svc_elegidos_id_pack_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_elegidos
    ADD CONSTRAINT svc_elegidos_id_pack_fkey FOREIGN KEY (id_locacion_cliente_pack) REFERENCES public.com_locaciones_clientes_packs(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: svc_requisitos svc_requisitos_id_tipo_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_requisitos
    ADD CONSTRAINT svc_requisitos_id_tipo_servicio_fkey FOREIGN KEY (id_tipo_servicio) REFERENCES public.svc_tipos_servicios(id) ON DELETE CASCADE;


--
-- Name: svc_requisitos svc_requisitos_id_tipo_tecnologia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_requisitos
    ADD CONSTRAINT svc_requisitos_id_tipo_tecnologia_fkey FOREIGN KEY (id_tipo_tecnologia) REFERENCES public.tec_tipos_tecnologias(id) ON DELETE CASCADE;


--
-- Name: svc_servicios_dependencias svc_servicios_dependencias_id_dependencia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_dependencias
    ADD CONSTRAINT svc_servicios_dependencias_id_dependencia_fkey FOREIGN KEY (id_dependencia) REFERENCES public.svc_dependencias(id) ON DELETE CASCADE;


--
-- Name: svc_servicios_dependencias svc_servicios_dependencias_id_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_dependencias
    ADD CONSTRAINT svc_servicios_dependencias_id_servicio_fkey FOREIGN KEY (id_servicio) REFERENCES public.svc_servicios(id) ON DELETE CASCADE;


--
-- Name: svc_servicios_grupos svc_servicios_grupos_id_tipo_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_grupos
    ADD CONSTRAINT svc_servicios_grupos_id_tipo_servicio_fkey FOREIGN KEY (id_tipo_servicio) REFERENCES public.svc_tipos_servicios(id) ON DELETE RESTRICT;


--
-- Name: svc_servicios_grupos svc_servicios_grupos_id_tipo_tecnologia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_grupos
    ADD CONSTRAINT svc_servicios_grupos_id_tipo_tecnologia_fkey FOREIGN KEY (id_tipo_tecnologia) REFERENCES public.tec_tipos_tecnologias(id) ON DELETE RESTRICT;


--
-- Name: svc_servicios svc_servicios_id_grupo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios
    ADD CONSTRAINT svc_servicios_id_grupo_fkey FOREIGN KEY (id_grupo) REFERENCES public.svc_servicios_grupos(id) ON DELETE RESTRICT;


--
-- Name: svc_servicios svc_servicios_id_tipo_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios
    ADD CONSTRAINT svc_servicios_id_tipo_servicio_fkey FOREIGN KEY (id_tipo_servicio) REFERENCES public.svc_tipos_servicios(id) ON DELETE RESTRICT;


--
-- Name: svc_servicios svc_servicios_id_tipo_tecnologia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios
    ADD CONSTRAINT svc_servicios_id_tipo_tecnologia_fkey FOREIGN KEY (id_tipo_tecnologia) REFERENCES public.tec_tipos_tecnologias(id) ON DELETE RESTRICT;


--
-- Name: svc_servicios_propiedades svc_servicios_propiedades_id_locacion_cliente_pack_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_propiedades
    ADD CONSTRAINT svc_servicios_propiedades_id_locacion_cliente_pack_fkey FOREIGN KEY (id_locacion_cliente_pack_servicio) REFERENCES public.com_locaciones_clientes_packs_servicios(id) ON DELETE CASCADE;


--
-- Name: svc_servicios_propiedades svc_servicios_propiedades_id_propiedad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_propiedades
    ADD CONSTRAINT svc_servicios_propiedades_id_propiedad_fkey FOREIGN KEY (id_propiedad) REFERENCES public.svc_propiedades(id) ON DELETE CASCADE;


--
-- Name: svc_servicios_propiedades_internas svc_servicios_propiedades_id_propiedad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_propiedades_internas
    ADD CONSTRAINT svc_servicios_propiedades_id_propiedad_fkey FOREIGN KEY (id_propiedad) REFERENCES public.svc_propiedades(id) ON DELETE CASCADE;


--
-- Name: svc_servicios_propiedades_internas svc_servicios_propiedades_internas_id_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_propiedades_internas
    ADD CONSTRAINT svc_servicios_propiedades_internas_id_servicio_fkey FOREIGN KEY (id_servicio) REFERENCES public.svc_servicios(id) ON DELETE CASCADE;


--
-- Name: svc_servicios_requisitos svc_servicios_requisitos_id_requisito_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_requisitos
    ADD CONSTRAINT svc_servicios_requisitos_id_requisito_fkey FOREIGN KEY (id_requisito) REFERENCES public.svc_requisitos(id) ON DELETE CASCADE;


--
-- Name: svc_servicios_requisitos svc_servicios_requisitos_id_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_servicios_requisitos
    ADD CONSTRAINT svc_servicios_requisitos_id_servicio_fkey FOREIGN KEY (id_servicio) REFERENCES public.svc_servicios(id) ON DELETE CASCADE;


--
-- Name: svc_tipos_servicios_propiedades svc_tipos_servicios_propiedades_id_propiedad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_servicios_propiedades
    ADD CONSTRAINT svc_tipos_servicios_propiedades_id_propiedad_fkey FOREIGN KEY (id_propiedad) REFERENCES public.svc_propiedades(id) ON DELETE CASCADE;


--
-- Name: svc_tipos_servicios_propiedades svc_tipos_servicios_propiedades_id_tipo_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_servicios_propiedades
    ADD CONSTRAINT svc_tipos_servicios_propiedades_id_tipo_servicio_fkey FOREIGN KEY (id_tipo_servicio) REFERENCES public.svc_tipos_servicios(id) ON DELETE CASCADE;


--
-- Name: svc_tipos_servicios_propiedades_internas svc_tipos_servicios_propiedades_internas_id_propiedad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_servicios_propiedades_internas
    ADD CONSTRAINT svc_tipos_servicios_propiedades_internas_id_propiedad_fkey FOREIGN KEY (id_propiedad) REFERENCES public.svc_propiedades(id) ON DELETE CASCADE;


--
-- Name: svc_tipos_servicios_propiedades_internas svc_tipos_servicios_propiedades_internas_id_tipo_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_servicios_propiedades_internas
    ADD CONSTRAINT svc_tipos_servicios_propiedades_internas_id_tipo_servicio_fkey FOREIGN KEY (id_tipo_servicio) REFERENCES public.svc_tipos_servicios(id) ON DELETE CASCADE;


--
-- Name: svc_tipos_servicios_tipos_tecnologias svc_tipos_servicios_tipos_tecnologias_id_tipo_servicio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_servicios_tipos_tecnologias
    ADD CONSTRAINT svc_tipos_servicios_tipos_tecnologias_id_tipo_servicio_fkey FOREIGN KEY (id_tipo_servicio) REFERENCES public.svc_tipos_servicios(id) ON DELETE CASCADE;


--
-- Name: svc_tipos_servicios_tipos_tecnologias svc_tipos_servicios_tipos_tecnologias_id_tipo_tecnologia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_servicios_tipos_tecnologias
    ADD CONSTRAINT svc_tipos_servicios_tipos_tecnologias_id_tipo_tecnologia_fkey FOREIGN KEY (id_tipo_tecnologia) REFERENCES public.tec_tipos_tecnologias(id) ON DELETE CASCADE;


--
-- Name: svc_tipos_tecnologias_propiedades svc_tipos_tecnologias_propiedades_id_propiedad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_tecnologias_propiedades
    ADD CONSTRAINT svc_tipos_tecnologias_propiedades_id_propiedad_fkey FOREIGN KEY (id_propiedad) REFERENCES public.svc_propiedades(id) ON DELETE CASCADE;


--
-- Name: svc_tipos_tecnologias_propiedades svc_tipos_tecnologias_propiedades_id_tipo_tecnologia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_tecnologias_propiedades
    ADD CONSTRAINT svc_tipos_tecnologias_propiedades_id_tipo_tecnologia_fkey FOREIGN KEY (id_tipo_tecnologia) REFERENCES public.tec_tipos_tecnologias(id) ON DELETE CASCADE;


--
-- Name: svc_tipos_tecnologias_propiedades_internas svc_tipos_tecnologias_propiedades_internas_id_propiedad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_tecnologias_propiedades_internas
    ADD CONSTRAINT svc_tipos_tecnologias_propiedades_internas_id_propiedad_fkey FOREIGN KEY (id_propiedad) REFERENCES public.svc_propiedades(id) ON DELETE CASCADE;


--
-- Name: svc_tipos_tecnologias_propiedades_internas svc_tipos_tecnologias_propiedades_internas_id_tipo_tec_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.svc_tipos_tecnologias_propiedades_internas
    ADD CONSTRAINT svc_tipos_tecnologias_propiedades_internas_id_tipo_tec_fkey FOREIGN KEY (id_tipo_tecnologia) REFERENCES public.tec_tipos_tecnologias(id) ON DELETE CASCADE;


--
-- Name: sys_abns sys_abns_id_cfg_configuraciones_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_abns
    ADD CONSTRAINT sys_abns_id_cfg_configuraciones_fkey FOREIGN KEY (id_cfg_configuraciones) REFERENCES public.cfg_configuraciones(id) ON DELETE CASCADE;


--
-- Name: sys_abns_logs sys_abns_logs_id_abn_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_abns_logs
    ADD CONSTRAINT sys_abns_logs_id_abn_fkey FOREIGN KEY (id_abn) REFERENCES public.sys_abns(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: sys_abns_tareas sys_abns_tareas_id_abn_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_abns_tareas
    ADD CONSTRAINT sys_abns_tareas_id_abn_fkey FOREIGN KEY (id_abn) REFERENCES public.sys_abns(id) ON DELETE CASCADE;


--
-- Name: sys_entidades sys_entidades_padre_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_entidades
    ADD CONSTRAINT sys_entidades_padre_fkey FOREIGN KEY (id_padre) REFERENCES public.sys_entidades(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: sys_eventos sys_eventos_id_cliente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_eventos
    ADD CONSTRAINT sys_eventos_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.com_clientes(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: sys_eventos sys_eventos_id_operador_destino_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_eventos
    ADD CONSTRAINT sys_eventos_id_operador_destino_fkey FOREIGN KEY (id_operador_destino) REFERENCES public.sys_operadores(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: sys_eventos sys_eventos_id_operador_origen_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_eventos
    ADD CONSTRAINT sys_eventos_id_operador_origen_fkey FOREIGN KEY (id_operador_origen) REFERENCES public.sys_operadores(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: sys_eventos sys_eventos_id_padre_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_eventos
    ADD CONSTRAINT sys_eventos_id_padre_fkey FOREIGN KEY (id_padre) REFERENCES public.sys_eventos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: sys_eventos sys_eventos_id_tipo_evento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_eventos
    ADD CONSTRAINT sys_eventos_id_tipo_evento_fkey FOREIGN KEY (id_tipo_evento) REFERENCES public.sys_tipos_eventos(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: sys_operadores sys_operadores_idioma_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_operadores
    ADD CONSTRAINT sys_operadores_idioma_fkey FOREIGN KEY (id_idioma) REFERENCES public.sys_idiomas(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: sys_operadores sys_operadores_padre_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_operadores
    ADD CONSTRAINT sys_operadores_padre_fkey FOREIGN KEY (id_padre) REFERENCES public.sys_operadores(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: sys_permisos sys_permisos_entidad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_permisos
    ADD CONSTRAINT sys_permisos_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES public.sys_entidades(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: sys_permisos sys_permisos_operador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_permisos
    ADD CONSTRAINT sys_permisos_operador_fkey FOREIGN KEY (id_operador) REFERENCES public.sys_operadores(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: sys_propiedades_abns sys_propiedades_abns_id_propiedad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_propiedades_abns
    ADD CONSTRAINT sys_propiedades_abns_id_propiedad_fkey FOREIGN KEY (id_propiedad) REFERENCES public.svc_propiedades(id) ON DELETE CASCADE;


--
-- Name: sys_tablas_auditoria sys_tablas_auditoria_id_padre_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_tablas_auditoria
    ADD CONSTRAINT sys_tablas_auditoria_id_padre_fkey FOREIGN KEY (id_padre) REFERENCES public.sys_tablas_auditoria(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: sys_tipos_eventos sys_tipos_eventos_id_operador_destino_default_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_tipos_eventos
    ADD CONSTRAINT sys_tipos_eventos_id_operador_destino_default_fkey FOREIGN KEY (id_operador_destino_default) REFERENCES public.sys_operadores(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: sys_tipos_eventos sys_tipos_eventos_id_operador_origen_default_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_tipos_eventos
    ADD CONSTRAINT sys_tipos_eventos_id_operador_origen_default_fkey FOREIGN KEY (id_operador_origen_default) REFERENCES public.sys_operadores(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: sys_tipos_eventos sys_tipos_eventos_id_padre_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_tipos_eventos
    ADD CONSTRAINT sys_tipos_eventos_id_padre_fkey FOREIGN KEY (id_padre) REFERENCES public.sys_tipos_eventos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: sys_tipos_eventos_operadores sys_tipos_eventos_operadores_id_operador_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_tipos_eventos_operadores
    ADD CONSTRAINT sys_tipos_eventos_operadores_id_operador_fkey FOREIGN KEY (id_operador) REFERENCES public.sys_operadores(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: sys_tipos_eventos_operadores sys_tipos_eventos_operadores_id_tipo_evento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.sys_tipos_eventos_operadores
    ADD CONSTRAINT sys_tipos_eventos_operadores_id_tipo_evento_fkey FOREIGN KEY (id_tipo_evento) REFERENCES public.sys_tipos_eventos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tec_dispositivos_propiedades_dispositivos tec_disp_propiedades_disp_id_dispositivo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos_propiedades_dispositivos
    ADD CONSTRAINT tec_disp_propiedades_disp_id_dispositivo_fkey FOREIGN KEY (id_dispositivo) REFERENCES public.tec_dispositivos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tec_dispositivos_propiedades_dispositivos tec_disp_propiedades_disp_id_propiedad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos_propiedades_dispositivos
    ADD CONSTRAINT tec_disp_propiedades_disp_id_propiedad_fkey FOREIGN KEY (id_propiedad) REFERENCES public.tec_propiedades_dispositivos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tec_dispositivos_etiquetas_dispositivos tec_dispositivos_etiquetas_dispositivos_id_dispositivo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos_etiquetas_dispositivos
    ADD CONSTRAINT tec_dispositivos_etiquetas_dispositivos_id_dispositivo_fkey FOREIGN KEY (id_dispositivo) REFERENCES public.tec_dispositivos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tec_dispositivos_etiquetas_dispositivos tec_dispositivos_etiquetas_dispositivos_id_etiqueta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos_etiquetas_dispositivos
    ADD CONSTRAINT tec_dispositivos_etiquetas_dispositivos_id_etiqueta_fkey FOREIGN KEY (id_etiqueta) REFERENCES public.tec_etiquetas_dispositivos(id) ON DELETE CASCADE;


--
-- Name: tec_dispositivos tec_dispositivos_id_modelo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos
    ADD CONSTRAINT tec_dispositivos_id_modelo_fkey FOREIGN KEY (id_modelo) REFERENCES public.tec_modelos(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: tec_dispositivos_interfaces tec_dispositivos_interfaces_id_dispositivo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos_interfaces
    ADD CONSTRAINT tec_dispositivos_interfaces_id_dispositivo_fkey FOREIGN KEY (id_dispositivo) REFERENCES public.tec_dispositivos(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tec_dispositivos_interfaces_propiedades tec_dispositivos_interfaces_propied_id_propiedad_interface_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos_interfaces_propiedades
    ADD CONSTRAINT tec_dispositivos_interfaces_propied_id_propiedad_interface_fkey FOREIGN KEY (id_propiedad_interface) REFERENCES public.tec_propiedades_interfaces(id) ON DELETE CASCADE;


--
-- Name: tec_dispositivos_interfaces_propiedades tec_dispositivos_interfaces_propiedades_id_interface_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_dispositivos_interfaces_propiedades
    ADD CONSTRAINT tec_dispositivos_interfaces_propiedades_id_interface_fkey FOREIGN KEY (id_interface) REFERENCES public.tec_dispositivos_interfaces(id) ON DELETE CASCADE;


--
-- Name: tec_etiquetas_dispositivos tec_etiquetas_dispositivos_id_grupo_etiqueta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_etiquetas_dispositivos
    ADD CONSTRAINT tec_etiquetas_dispositivos_id_grupo_etiqueta_fkey FOREIGN KEY (id_grupo_etiqueta) REFERENCES public.tec_grupos_etiquetas(id) ON DELETE RESTRICT;


--
-- Name: tec_modelos_etiquetas_dispositivos tec_modelos_etiquetas_dispositivos_id_etiqueta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos_etiquetas_dispositivos
    ADD CONSTRAINT tec_modelos_etiquetas_dispositivos_id_etiqueta_fkey FOREIGN KEY (id_etiqueta) REFERENCES public.tec_etiquetas_dispositivos(id) ON DELETE CASCADE;


--
-- Name: tec_modelos_etiquetas_dispositivos tec_modelos_etiquetas_dispositivos_id_modelo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos_etiquetas_dispositivos
    ADD CONSTRAINT tec_modelos_etiquetas_dispositivos_id_modelo_fkey FOREIGN KEY (id_modelo) REFERENCES public.tec_modelos(id) ON DELETE CASCADE;


--
-- Name: tec_modelos tec_modelos_id_marca_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos
    ADD CONSTRAINT tec_modelos_id_marca_fkey FOREIGN KEY (id_marca) REFERENCES public.tec_marcas(id) ON DELETE RESTRICT;


--
-- Name: tec_modelos tec_modelos_id_tipo_dispositivo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos
    ADD CONSTRAINT tec_modelos_id_tipo_dispositivo_fkey FOREIGN KEY (id_tipo_dispositivo) REFERENCES public.tec_tipos_dispositivos(id) ON DELETE RESTRICT;


--
-- Name: tec_modelos_propiedades_interfaces tec_modelos_propiedades_interfaces_id_modelo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos_propiedades_interfaces
    ADD CONSTRAINT tec_modelos_propiedades_interfaces_id_modelo_fkey FOREIGN KEY (id_modelo) REFERENCES public.tec_modelos(id) ON DELETE CASCADE;


--
-- Name: tec_modelos_propiedades_interfaces tec_modelos_propiedades_interfaces_id_propiedad_interface_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos_propiedades_interfaces
    ADD CONSTRAINT tec_modelos_propiedades_interfaces_id_propiedad_interface_fkey FOREIGN KEY (id_propiedad_interface) REFERENCES public.tec_propiedades_interfaces(id) ON DELETE CASCADE;


--
-- Name: tec_modelos_puertos tec_modelos_puertos_id_modelo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos_puertos
    ADD CONSTRAINT tec_modelos_puertos_id_modelo_fkey FOREIGN KEY (id_modelo) REFERENCES public.tec_modelos(id) ON DELETE CASCADE;


--
-- Name: tec_modelos_puertos tec_modelos_puertos_id_tipo_puerto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_modelos_puertos
    ADD CONSTRAINT tec_modelos_puertos_id_tipo_puerto_fkey FOREIGN KEY (id_tipo_puerto) REFERENCES public.tec_tipos_puertos_dispositivos(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: tec_objetos_monitoreo tec_objetos_monitoreo_id_interface_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_objetos_monitoreo
    ADD CONSTRAINT tec_objetos_monitoreo_id_interface_fkey FOREIGN KEY (id_interface) REFERENCES public.tec_dispositivos_interfaces(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tec_objetos_monitoreo tec_objetos_monitoreo_id_plantilla_objetos_monitoreo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_objetos_monitoreo
    ADD CONSTRAINT tec_objetos_monitoreo_id_plantilla_objetos_monitoreo_fkey FOREIGN KEY (id_plantilla_objetos_monitoreo) REFERENCES public.tec_plantillas_objetos_monitoreo(id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: tec_plantillas_objetos_monitoreo_items tec_plantillas_objetos_monito_id_plantilla_objetos_monitor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_plantillas_objetos_monitoreo_items
    ADD CONSTRAINT tec_plantillas_objetos_monito_id_plantilla_objetos_monitor_fkey FOREIGN KEY (id_plantilla_objetos_monitoreo) REFERENCES public.tec_plantillas_objetos_monitoreo(id) ON DELETE CASCADE;


--
-- Name: tec_rangos_ips tec_rangos_ips_id_pool_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_rangos_ips
    ADD CONSTRAINT tec_rangos_ips_id_pool_fkey FOREIGN KEY (id_pool) REFERENCES public.tec_pools_ips(id) ON DELETE CASCADE;


--
-- Name: tec_tipos_dispositivos_propiedades_dispositivos tec_tipos_disp_propiedades_disp_id_propiedad_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_tipos_dispositivos_propiedades_dispositivos
    ADD CONSTRAINT tec_tipos_disp_propiedades_disp_id_propiedad_fkey FOREIGN KEY (id_propiedad) REFERENCES public.tec_propiedades_dispositivos(id) ON DELETE CASCADE;


--
-- Name: tec_tipos_dispositivos_propiedades_dispositivos tec_tipos_disp_propiedades_disp_id_tipo_dispositivo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_tipos_dispositivos_propiedades_dispositivos
    ADD CONSTRAINT tec_tipos_disp_propiedades_disp_id_tipo_dispositivo_fkey FOREIGN KEY (id_tipo_dispositivo) REFERENCES public.tec_tipos_dispositivos(id) ON DELETE CASCADE;


--
-- Name: tec_tipos_dispositivos_solapas tec_tipos_dispositivos_solapas_id_tipo_dispositivo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_tipos_dispositivos_solapas
    ADD CONSTRAINT tec_tipos_dispositivos_solapas_id_tipo_dispositivo_fkey FOREIGN KEY (id_tipo_dispositivo) REFERENCES public.tec_tipos_dispositivos(id) ON DELETE CASCADE;


--
-- Name: tec_zonas tec_zonas_id_dispositivo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: spi40
--

ALTER TABLE ONLY public.tec_zonas
    ADD CONSTRAINT tec_zonas_id_dispositivo_fkey FOREIGN KEY (id_dispositivo) REFERENCES public.tec_dispositivos(id) ON DELETE SET NULL;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO spi40;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

\unrestrict OSNH67ATfqQrteL06fnXZl2Fb2eqgHGih3lqi6WdnEuV8dM0bBZTzcjg1gFKfgz

