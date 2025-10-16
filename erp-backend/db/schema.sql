--
-- PostgreSQL database dump
--

\restrict zhcef3Eb3u2hM0o4hU57hlvcN6RBf1HFvKS75rRDcKxmkqFggOEBhqdWs9tLu4G

-- Dumped from database version 17.5
-- Dumped by pg_dump version 17.6 (Homebrew)

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
-- Name: actualizar_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.actualizar_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.actualizar_updated_at() OWNER TO postgres;

--
-- Name: crear_asiento_factura(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.crear_asiento_factura() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Crear asiento de compra cuando se confirma una factura
    IF NEW.estado = 'confirmada' AND (OLD.estado IS NULL OR OLD.estado != 'confirmada') THEN
        INSERT INTO factura_asientos (
            factura_id, tipo_asiento, monto, fecha_asiento, descripcion
        ) VALUES (
            NEW.id, 'compra', NEW.importe, NEW.fecha_factura,
            'Asiento automático - ' || NEW.proveedor
        );
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.crear_asiento_factura() OWNER TO postgres;

--
-- Name: generar_numero_asiento(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generar_numero_asiento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    nuevo_numero INT;
    formato_numero VARCHAR(20);
    año_actual INT;
BEGIN
    -- Obtener el año actual
    año_actual := EXTRACT(YEAR FROM NEW.fecha_asiento);
    
    -- Obtener y actualizar el último número de asiento
    UPDATE configuracion_contable 
    SET ultimo_numero_asiento = ultimo_numero_asiento + 1
    WHERE id_negocio = NEW.id_negocio
    RETURNING ultimo_numero_asiento INTO nuevo_numero;
    
    -- Generar el número formateado
    formato_numero := 'ASI-' || año_actual || '-' || LPAD(nuevo_numero::TEXT, 4, '0');
    
    -- Asignar el número generado
    NEW.numero_asiento := formato_numero;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.generar_numero_asiento() OWNER TO postgres;

--
-- Name: obtener_saldo_cuenta(integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.obtener_saldo_cuenta(p_id_cuenta integer, p_fecha_hasta date DEFAULT CURRENT_DATE) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_naturaleza VARCHAR(20);
    v_total_debe DECIMAL(15,2) := 0;
    v_total_haber DECIMAL(15,2) := 0;
    v_saldo DECIMAL(15,2);
BEGIN
    -- Obtener naturaleza de la cuenta
    SELECT naturaleza INTO v_naturaleza
    FROM cuentas_contables
    WHERE id = p_id_cuenta;
    
    -- Calcular totales
    SELECT 
        COALESCE(SUM(da.debe), 0),
        COALESCE(SUM(da.haber), 0)
    INTO v_total_debe, v_total_haber
    FROM detalle_asientos da
    INNER JOIN asientos_contables ac ON da.id_asiento = ac.id
    WHERE da.id_cuenta = p_id_cuenta
      AND ac.estado = 'CONFIRMADO'
      AND ac.fecha_asiento <= p_fecha_hasta;
    
    -- Calcular saldo según naturaleza
    IF v_naturaleza = 'DEUDORA' THEN
        v_saldo := v_total_debe - v_total_haber;
    ELSE
        v_saldo := v_total_haber - v_total_debe;
    END IF;
    
    RETURN v_saldo;
END;
$$;


ALTER FUNCTION public.obtener_saldo_cuenta(p_id_cuenta integer, p_fecha_hasta date) OWNER TO postgres;

--
-- Name: obtener_siguiente_folio(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.obtener_siguiente_folio(p_tipo_dte integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    siguiente_folio INTEGER;
    folio_record RECORD;
BEGIN
    -- Buscar folio activo para el tipo DTE
    SELECT * INTO folio_record 
    FROM dte_folios 
    WHERE tipo_dte = p_tipo_dte 
    AND estado = 'activo' 
    AND folio_actual <= folio_hasta
    ORDER BY id
    LIMIT 1;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No hay folios disponibles para tipo DTE %', p_tipo_dte;
    END IF;
    
    siguiente_folio := folio_record.folio_actual;
    
    -- Actualizar folio actual
    UPDATE dte_folios 
    SET folio_actual = folio_actual + 1,
        estado = CASE 
            WHEN folio_actual + 1 > folio_hasta THEN 'agotado'
            ELSE 'activo'
        END
    WHERE id = folio_record.id;
    
    RETURN siguiente_folio;
END;
$$;


ALTER FUNCTION public.obtener_siguiente_folio(p_tipo_dte integer) OWNER TO postgres;

--
-- Name: registrar_dte_seguimiento(integer, integer, character varying, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.registrar_dte_seguimiento(p_factura_id integer, p_tipo_dte integer, p_folio character varying, p_xml_enviado text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    seguimiento_id INTEGER;
BEGIN
    INSERT INTO dte_seguimiento (
        factura_id, tipo_dte, folio, estado_sii, 
        xml_enviado, fecha_envio, intentos_envio
    ) VALUES (
        p_factura_id, p_tipo_dte, p_folio, 'ENVIADO',
        p_xml_enviado, NOW(), 1
    ) RETURNING id INTO seguimiento_id;
    
    RETURN seguimiento_id;
END;
$$;


ALTER FUNCTION public.registrar_dte_seguimiento(p_factura_id integer, p_tipo_dte integer, p_folio character varying, p_xml_enviado text) OWNER TO postgres;

--
-- Name: validar_asiento_balanceado(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validar_asiento_balanceado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Calcular totales del asiento
    UPDATE asientos_contables 
    SET 
        total_debe = (
            SELECT COALESCE(SUM(debe), 0) 
            FROM detalle_asientos 
            WHERE id_asiento = NEW.id_asiento
        ),
        total_haber = (
            SELECT COALESCE(SUM(haber), 0) 
            FROM detalle_asientos 
            WHERE id_asiento = NEW.id_asiento
        )
    WHERE id = NEW.id_asiento;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validar_asiento_balanceado() OWNER TO postgres;

--
-- Name: validar_asiento_balanceado_completo(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validar_asiento_balanceado_completo(p_id_asiento integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_debe DECIMAL(15,2);
    v_total_haber DECIMAL(15,2);
BEGIN
    SELECT 
        COALESCE(SUM(debe), 0),
        COALESCE(SUM(haber), 0)
    INTO v_total_debe, v_total_haber
    FROM detalle_asientos
    WHERE id_asiento = p_id_asiento;
    
    RETURN v_total_debe = v_total_haber AND v_total_debe > 0;
END;
$$;


ALTER FUNCTION public.validar_asiento_balanceado_completo(p_id_asiento integer) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: alertas_stock; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.alertas_stock (
    id integer NOT NULL,
    id_producto integer NOT NULL,
    id_almacen integer NOT NULL,
    tipo_alerta character varying(50),
    valor numeric(12,2),
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.alertas_stock OWNER TO postgres;

--
-- Name: alertas_stock_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.alertas_stock_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.alertas_stock_id_seq OWNER TO postgres;

--
-- Name: alertas_stock_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.alertas_stock_id_seq OWNED BY public.alertas_stock.id;


--
-- Name: almacenes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.almacenes (
    id integer NOT NULL,
    id_negocio integer NOT NULL,
    nombre character varying(255) NOT NULL,
    direccion text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.almacenes OWNER TO postgres;

--
-- Name: almacenes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.almacenes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.almacenes_id_seq OWNER TO postgres;

--
-- Name: almacenes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.almacenes_id_seq OWNED BY public.almacenes.id;


--
-- Name: asientos_contables; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.asientos_contables (
    id integer NOT NULL,
    numero_asiento character varying(20) NOT NULL,
    fecha_asiento date NOT NULL,
    descripcion text NOT NULL,
    referencia character varying(100),
    tipo_origen character varying(50),
    id_origen integer,
    id_negocio integer NOT NULL,
    id_periodo integer,
    id_centro_costo integer,
    total_debe numeric(15,2) DEFAULT 0 NOT NULL,
    total_haber numeric(15,2) DEFAULT 0 NOT NULL,
    estado character varying(20) DEFAULT 'BORRADOR'::character varying,
    fecha_confirmacion timestamp without time zone,
    usuario_creacion character varying(100),
    usuario_confirmacion character varying(100),
    observaciones text,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT asientos_contables_estado_check CHECK (((estado)::text = ANY ((ARRAY['BORRADOR'::character varying, 'CONFIRMADO'::character varying, 'ANULADO'::character varying])::text[]))),
    CONSTRAINT check_asiento_balanceado CHECK ((((estado)::text <> 'CONFIRMADO'::text) OR ((total_debe = total_haber) AND (total_debe > (0)::numeric))))
);


ALTER TABLE public.asientos_contables OWNER TO postgres;

--
-- Name: TABLE asientos_contables; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.asientos_contables IS 'Asientos contables del sistema';


--
-- Name: asientos_contables_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.asientos_contables_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.asientos_contables_id_seq OWNER TO postgres;

--
-- Name: asientos_contables_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.asientos_contables_id_seq OWNED BY public.asientos_contables.id;


--
-- Name: centros_costo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.centros_costo (
    id integer NOT NULL,
    codigo character varying(20) NOT NULL,
    nombre character varying(255) NOT NULL,
    descripcion text,
    id_negocio integer NOT NULL,
    id_responsable integer,
    activo boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.centros_costo OWNER TO postgres;

--
-- Name: TABLE centros_costo; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.centros_costo IS 'Centros de costo para análisis de gastos';


--
-- Name: centros_costo_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.centros_costo_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.centros_costo_id_seq OWNER TO postgres;

--
-- Name: centros_costo_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.centros_costo_id_seq OWNED BY public.centros_costo.id;


--
-- Name: configuracion_contable; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.configuracion_contable (
    id integer NOT NULL,
    id_negocio integer NOT NULL,
    moneda_base character varying(3) DEFAULT 'CLP'::character varying NOT NULL,
    decimales_moneda integer DEFAULT 2,
    separador_miles character varying(1) DEFAULT '.'::character varying,
    separador_decimales character varying(1) DEFAULT ','::character varying,
    cuenta_ventas_default integer,
    cuenta_compras_default integer,
    cuenta_inventario_default integer,
    cuenta_costo_ventas_default integer,
    cuenta_caja_default integer,
    cuenta_clientes_default integer,
    cuenta_proveedores_default integer,
    "inicio_año_fiscal" date,
    metodo_valoracion_inventario character varying(20) DEFAULT 'PROMEDIO'::character varying,
    formato_asiento character varying(50) DEFAULT 'ASI-{YYYY}-{NNNN}'::character varying,
    ultimo_numero_asiento integer DEFAULT 0,
    mostrar_saldos_cero boolean DEFAULT false,
    niveles_plan_cuentas integer DEFAULT 4,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT configuracion_contable_metodo_valoracion_inventario_check CHECK (((metodo_valoracion_inventario)::text = ANY ((ARRAY['FIFO'::character varying, 'LIFO'::character varying, 'PROMEDIO'::character varying])::text[])))
);


ALTER TABLE public.configuracion_contable OWNER TO postgres;

--
-- Name: TABLE configuracion_contable; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.configuracion_contable IS 'Configuración contable por negocio';


--
-- Name: configuracion_contable_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.configuracion_contable_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.configuracion_contable_id_seq OWNER TO postgres;

--
-- Name: configuracion_contable_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.configuracion_contable_id_seq OWNED BY public.configuracion_contable.id;


--
-- Name: cuentas_contables; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cuentas_contables (
    id integer NOT NULL,
    codigo character varying(20) NOT NULL,
    nombre character varying(255) NOT NULL,
    id_tipo_cuenta integer NOT NULL,
    id_cuenta_padre integer,
    nivel integer DEFAULT 1 NOT NULL,
    naturaleza character varying(20) NOT NULL,
    acepta_movimientos boolean DEFAULT true,
    id_negocio integer NOT NULL,
    descripcion text,
    activa boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT check_nivel_cuenta CHECK ((((id_cuenta_padre IS NULL) AND (nivel = 1)) OR ((id_cuenta_padre IS NOT NULL) AND (nivel > 1)))),
    CONSTRAINT cuentas_contables_naturaleza_check CHECK (((naturaleza)::text = ANY ((ARRAY['DEUDORA'::character varying, 'ACREEDORA'::character varying])::text[])))
);


ALTER TABLE public.cuentas_contables OWNER TO postgres;

--
-- Name: TABLE cuentas_contables; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.cuentas_contables IS 'Plan de cuentas contable jerárquico';


--
-- Name: cuentas_contables_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cuentas_contables_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cuentas_contables_id_seq OWNER TO postgres;

--
-- Name: cuentas_contables_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cuentas_contables_id_seq OWNED BY public.cuentas_contables.id;


--
-- Name: facturas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.facturas (
    id integer NOT NULL,
    fecha_factura date NOT NULL,
    serie character varying(50),
    numero character varying(50),
    ruc character varying(20),
    proveedor character varying(255) NOT NULL,
    valor_afecto numeric(15,2) DEFAULT 0,
    valor_inafecto numeric(15,2) DEFAULT 0,
    impuestos numeric(15,2) DEFAULT 0,
    importe numeric(15,2) NOT NULL,
    moneda character varying(3) NOT NULL,
    archivo_original character varying(255),
    estado character varying(20) DEFAULT 'procesada'::character varying,
    fecha_registro timestamp without time zone DEFAULT now(),
    sucursal_id integer,
    dte_folio character varying(20),
    dte_tipo integer,
    dte_fecha_envio timestamp without time zone,
    dte_estado character varying(50) DEFAULT 'pendiente'::character varying,
    dte_xml text,
    dte_track_id character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.facturas OWNER TO postgres;

--
-- Name: dashboard_facturas; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.dashboard_facturas AS
 SELECT date_trunc('month'::text, (fecha_factura)::timestamp with time zone) AS mes,
    count(*) AS total_facturas,
    sum(importe) AS monto_total,
    sum(
        CASE
            WHEN ((dte_estado)::text = 'enviada_sii'::text) THEN importe
            ELSE (0)::numeric
        END) AS monto_dte_enviado,
    count(
        CASE
            WHEN ((dte_estado)::text = 'enviada_sii'::text) THEN 1
            ELSE NULL::integer
        END) AS facturas_dte,
    avg(importe) AS monto_promedio,
    count(DISTINCT proveedor) AS proveedores_unicos
   FROM public.facturas
  WHERE (fecha_factura >= date_trunc('year'::text, (CURRENT_DATE)::timestamp with time zone))
  GROUP BY (date_trunc('month'::text, (fecha_factura)::timestamp with time zone))
  ORDER BY (date_trunc('month'::text, (fecha_factura)::timestamp with time zone)) DESC;


ALTER VIEW public.dashboard_facturas OWNER TO postgres;

--
-- Name: detalle_asientos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.detalle_asientos (
    id integer NOT NULL,
    id_asiento integer NOT NULL,
    id_cuenta integer NOT NULL,
    orden_linea integer DEFAULT 1 NOT NULL,
    descripcion text,
    debe numeric(15,2) DEFAULT 0 NOT NULL,
    haber numeric(15,2) DEFAULT 0 NOT NULL,
    referencia_detalle character varying(255),
    id_centro_costo integer,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT detalle_asientos_check CHECK (((debe >= (0)::numeric) AND (haber >= (0)::numeric))),
    CONSTRAINT detalle_asientos_check1 CHECK (((debe > (0)::numeric) OR (haber > (0)::numeric))),
    CONSTRAINT detalle_asientos_check2 CHECK ((NOT ((debe > (0)::numeric) AND (haber > (0)::numeric))))
);


ALTER TABLE public.detalle_asientos OWNER TO postgres;

--
-- Name: TABLE detalle_asientos; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.detalle_asientos IS 'Detalle de movimientos contables por cuenta';


--
-- Name: detalle_asientos_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.detalle_asientos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.detalle_asientos_id_seq OWNER TO postgres;

--
-- Name: detalle_asientos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.detalle_asientos_id_seq OWNED BY public.detalle_asientos.id;


--
-- Name: dte_folios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dte_folios (
    id integer NOT NULL,
    tipo_dte integer NOT NULL,
    folio_desde integer NOT NULL,
    folio_hasta integer NOT NULL,
    folio_actual integer NOT NULL,
    fecha_autorizacion date,
    codigo_autorizacion character varying(50),
    xml_caf text,
    estado character varying(20) DEFAULT 'activo'::character varying,
    fecha_creacion timestamp without time zone DEFAULT now()
);


ALTER TABLE public.dte_folios OWNER TO postgres;

--
-- Name: dte_folios_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.dte_folios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dte_folios_id_seq OWNER TO postgres;

--
-- Name: dte_folios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.dte_folios_id_seq OWNED BY public.dte_folios.id;


--
-- Name: dte_seguimiento; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dte_seguimiento (
    id integer NOT NULL,
    factura_id integer,
    tipo_dte integer NOT NULL,
    folio character varying(20) NOT NULL,
    estado_sii character varying(50),
    glosa_sii text,
    track_id character varying(100),
    fecha_envio timestamp without time zone,
    fecha_respuesta_sii timestamp without time zone,
    xml_enviado text,
    xml_respuesta text,
    intentos_envio integer DEFAULT 0,
    fecha_creacion timestamp without time zone DEFAULT now()
);


ALTER TABLE public.dte_seguimiento OWNER TO postgres;

--
-- Name: dte_seguimiento_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.dte_seguimiento_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dte_seguimiento_id_seq OWNER TO postgres;

--
-- Name: dte_seguimiento_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.dte_seguimiento_id_seq OWNED BY public.dte_seguimiento.id;


--
-- Name: factura_asientos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.factura_asientos (
    id integer NOT NULL,
    factura_id integer,
    asiento_id integer,
    tipo_asiento character varying(50),
    monto numeric(12,2) NOT NULL,
    fecha_asiento date NOT NULL,
    descripcion text,
    fecha_creacion timestamp without time zone DEFAULT now()
);


ALTER TABLE public.factura_asientos OWNER TO postgres;

--
-- Name: factura_asientos_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.factura_asientos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.factura_asientos_id_seq OWNER TO postgres;

--
-- Name: factura_asientos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.factura_asientos_id_seq OWNED BY public.factura_asientos.id;


--
-- Name: factura_inventario; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.factura_inventario (
    id integer NOT NULL,
    factura_id integer,
    producto_id integer,
    cantidad numeric(10,2) NOT NULL,
    precio_unitario numeric(10,2) NOT NULL,
    descuento numeric(5,2) DEFAULT 0,
    fecha_creacion timestamp without time zone DEFAULT now()
);


ALTER TABLE public.factura_inventario OWNER TO postgres;

--
-- Name: factura_inventario_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.factura_inventario_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.factura_inventario_id_seq OWNER TO postgres;

--
-- Name: factura_inventario_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.factura_inventario_id_seq OWNED BY public.factura_inventario.id;


--
-- Name: factura_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.factura_items (
    id integer NOT NULL,
    factura_id integer,
    producto_insumo character varying(255) NOT NULL,
    categoria character varying(100) NOT NULL,
    unidad_medida character varying(20) NOT NULL,
    cantidad numeric(10,4) NOT NULL,
    precio_unitario numeric(15,2) NOT NULL,
    valor_afecto numeric(15,2) DEFAULT 0,
    valor_inafecto numeric(15,2) DEFAULT 0,
    impuestos numeric(15,2) DEFAULT 0,
    total numeric(15,2) NOT NULL,
    producto_id integer
);


ALTER TABLE public.factura_items OWNER TO postgres;

--
-- Name: factura_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.factura_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.factura_items_id_seq OWNER TO postgres;

--
-- Name: factura_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.factura_items_id_seq OWNED BY public.factura_items.id;


--
-- Name: facturas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.facturas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.facturas_id_seq OWNER TO postgres;

--
-- Name: facturas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.facturas_id_seq OWNED BY public.facturas.id;


--
-- Name: integraciones_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.integraciones_log (
    id integer NOT NULL,
    modulo_origen character varying(50) NOT NULL,
    tipo_operacion character varying(50) NOT NULL,
    id_registro_origen integer NOT NULL,
    id_asiento_generado integer,
    estado character varying(20) DEFAULT 'PROCESADO'::character varying,
    mensaje text,
    datos_origen jsonb,
    fecha_procesamiento timestamp without time zone DEFAULT now(),
    CONSTRAINT integraciones_log_estado_check CHECK (((estado)::text = ANY ((ARRAY['PROCESADO'::character varying, 'ERROR'::character varying, 'PENDIENTE'::character varying])::text[])))
);


ALTER TABLE public.integraciones_log OWNER TO postgres;

--
-- Name: TABLE integraciones_log; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.integraciones_log IS 'Log de integraciones automáticas con otros módulos';


--
-- Name: integraciones_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.integraciones_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.integraciones_log_id_seq OWNER TO postgres;

--
-- Name: integraciones_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.integraciones_log_id_seq OWNED BY public.integraciones_log.id;


--
-- Name: inventario; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.inventario (
    id integer NOT NULL,
    id_producto integer NOT NULL,
    id_almacen integer NOT NULL,
    cantidad numeric(12,2) DEFAULT 0 NOT NULL,
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.inventario OWNER TO postgres;

--
-- Name: inventario_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.inventario_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.inventario_id_seq OWNER TO postgres;

--
-- Name: inventario_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.inventario_id_seq OWNED BY public.inventario.id;


--
-- Name: movimientos_stock; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.movimientos_stock (
    id integer NOT NULL,
    id_producto integer NOT NULL,
    id_almacen integer NOT NULL,
    tipo character varying(50) NOT NULL,
    cantidad numeric(12,2) NOT NULL,
    referencia character varying(255),
    fecha timestamp without time zone DEFAULT now()
);


ALTER TABLE public.movimientos_stock OWNER TO postgres;

--
-- Name: movimientos_stock_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.movimientos_stock_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.movimientos_stock_id_seq OWNER TO postgres;

--
-- Name: movimientos_stock_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.movimientos_stock_id_seq OWNED BY public.movimientos_stock.id;


--
-- Name: negocios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.negocios (
    id integer NOT NULL,
    nombre character varying(255) NOT NULL,
    direccion text,
    telefono character varying(50),
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.negocios OWNER TO postgres;

--
-- Name: negocios_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.negocios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.negocios_id_seq OWNER TO postgres;

--
-- Name: negocios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.negocios_id_seq OWNED BY public.negocios.id;


--
-- Name: pedidos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pedidos (
    id integer NOT NULL,
    id_negocio integer NOT NULL,
    cliente character varying(255),
    productos jsonb,
    total numeric(10,2),
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    telefono character varying(20),
    direccion text,
    tipo_pedido character varying(20),
    estado_pago character varying(20) DEFAULT 'pendiente'::character varying,
    CONSTRAINT pedidos_estado_pago_check CHECK (((estado_pago)::text = ANY ((ARRAY['pendiente'::character varying, 'pagado'::character varying, 'rechazado'::character varying])::text[]))),
    CONSTRAINT pedidos_tipo_pedido_check CHECK (((tipo_pedido)::text = ANY ((ARRAY['local'::character varying, 'delivery'::character varying])::text[])))
);


ALTER TABLE public.pedidos OWNER TO postgres;

--
-- Name: pedidos_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.pedidos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.pedidos_id_seq OWNER TO postgres;

--
-- Name: pedidos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.pedidos_id_seq OWNED BY public.pedidos.id;


--
-- Name: periodos_contables; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.periodos_contables (
    id integer NOT NULL,
    id_negocio integer NOT NULL,
    "año" integer NOT NULL,
    mes integer NOT NULL,
    fecha_inicio date NOT NULL,
    fecha_fin date NOT NULL,
    estado character varying(20) DEFAULT 'ABIERTO'::character varying,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT periodos_contables_estado_check CHECK (((estado)::text = ANY ((ARRAY['ABIERTO'::character varying, 'CERRADO'::character varying, 'BLOQUEADO'::character varying])::text[]))),
    CONSTRAINT periodos_contables_mes_check CHECK (((mes >= 1) AND (mes <= 12)))
);


ALTER TABLE public.periodos_contables OWNER TO postgres;

--
-- Name: TABLE periodos_contables; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.periodos_contables IS 'Control de períodos contables abiertos/cerrados';


--
-- Name: periodos_contables_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.periodos_contables_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.periodos_contables_id_seq OWNER TO postgres;

--
-- Name: periodos_contables_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.periodos_contables_id_seq OWNED BY public.periodos_contables.id;


--
-- Name: productos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.productos (
    id integer NOT NULL,
    nombre character varying(255) NOT NULL,
    tipo character varying(50) NOT NULL,
    unidad_medida character varying(50),
    created_at timestamp without time zone DEFAULT now(),
    precio integer
);


ALTER TABLE public.productos OWNER TO postgres;

--
-- Name: productos_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.productos_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.productos_id_seq OWNER TO postgres;

--
-- Name: productos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.productos_id_seq OWNED BY public.productos.id;


--
-- Name: recetas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.recetas (
    id integer NOT NULL,
    id_producto_final integer NOT NULL,
    id_producto_insumo integer NOT NULL,
    cantidad numeric(12,2) NOT NULL,
    unidad_medida character varying(50)
);


ALTER TABLE public.recetas OWNER TO postgres;

--
-- Name: recetas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.recetas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.recetas_id_seq OWNER TO postgres;

--
-- Name: recetas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.recetas_id_seq OWNED BY public.recetas.id;


--
-- Name: saldos_contables; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.saldos_contables (
    id integer NOT NULL,
    id_cuenta integer NOT NULL,
    id_negocio integer NOT NULL,
    "año" integer NOT NULL,
    mes integer NOT NULL,
    saldo_inicial_debe numeric(15,2) DEFAULT 0,
    saldo_inicial_haber numeric(15,2) DEFAULT 0,
    movimientos_debe numeric(15,2) DEFAULT 0,
    movimientos_haber numeric(15,2) DEFAULT 0,
    saldo_final_debe numeric(15,2) DEFAULT 0,
    saldo_final_haber numeric(15,2) DEFAULT 0,
    saldo_neto numeric(15,2) DEFAULT 0,
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.saldos_contables OWNER TO postgres;

--
-- Name: TABLE saldos_contables; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.saldos_contables IS 'Saldos contables precalculados para optimización';


--
-- Name: saldos_contables_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.saldos_contables_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.saldos_contables_id_seq OWNER TO postgres;

--
-- Name: saldos_contables_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.saldos_contables_id_seq OWNED BY public.saldos_contables.id;


--
-- Name: sii_configuracion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sii_configuracion (
    id integer NOT NULL,
    rut_empresa character varying(12) NOT NULL,
    nombre_empresa character varying(255) NOT NULL,
    giro_empresa character varying(255),
    actividad_economica character varying(10),
    direccion text,
    comuna character varying(100),
    ciudad character varying(100),
    telefono character varying(20),
    email character varying(100),
    ambiente character varying(20) DEFAULT 'certificacion'::character varying,
    certificado_digital text,
    clave_privada text,
    fecha_creacion timestamp without time zone DEFAULT now(),
    fecha_actualizacion timestamp without time zone DEFAULT now(),
    activo boolean DEFAULT true
);


ALTER TABLE public.sii_configuracion OWNER TO postgres;

--
-- Name: sii_configuracion_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sii_configuracion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sii_configuracion_id_seq OWNER TO postgres;

--
-- Name: sii_configuracion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sii_configuracion_id_seq OWNED BY public.sii_configuracion.id;


--
-- Name: tipos_cuenta; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipos_cuenta (
    id integer NOT NULL,
    codigo character varying(10) NOT NULL,
    nombre character varying(100) NOT NULL,
    naturaleza character varying(20) NOT NULL,
    categoria character varying(50) NOT NULL,
    descripcion text,
    activo boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT tipos_cuenta_categoria_check CHECK (((categoria)::text = ANY ((ARRAY['ACTIVO'::character varying, 'PASIVO'::character varying, 'PATRIMONIO'::character varying, 'INGRESO'::character varying, 'GASTO'::character varying])::text[]))),
    CONSTRAINT tipos_cuenta_naturaleza_check CHECK (((naturaleza)::text = ANY ((ARRAY['DEUDORA'::character varying, 'ACREEDORA'::character varying])::text[])))
);


ALTER TABLE public.tipos_cuenta OWNER TO postgres;

--
-- Name: TABLE tipos_cuenta; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.tipos_cuenta IS 'Catálogo de tipos de cuenta contable';


--
-- Name: tipos_cuenta_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tipos_cuenta_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipos_cuenta_id_seq OWNER TO postgres;

--
-- Name: tipos_cuenta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tipos_cuenta_id_seq OWNED BY public.tipos_cuenta.id;


--
-- Name: transacciones_contables; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.transacciones_contables (
    id integer NOT NULL,
    factura_id integer,
    tipo_transaccion character varying(50) NOT NULL,
    cuenta_contable character varying(100) NOT NULL,
    monto numeric(15,2) NOT NULL,
    moneda character varying(3) NOT NULL,
    fecha_registro timestamp without time zone DEFAULT now(),
    descripcion text,
    estado character varying(20) DEFAULT 'pendiente'::character varying
);


ALTER TABLE public.transacciones_contables OWNER TO postgres;

--
-- Name: transacciones_contables_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.transacciones_contables_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.transacciones_contables_id_seq OWNER TO postgres;

--
-- Name: transacciones_contables_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.transacciones_contables_id_seq OWNED BY public.transacciones_contables.id;


--
-- Name: usuarios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.usuarios (
    id integer NOT NULL,
    id_negocio integer NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    rol character varying(20) NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT usuarios_rol_check CHECK (((rol)::text = ANY ((ARRAY['admin'::character varying, 'cajero'::character varying, 'cliente'::character varying])::text[])))
);


ALTER TABLE public.usuarios OWNER TO postgres;

--
-- Name: usuarios_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.usuarios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.usuarios_id_seq OWNER TO postgres;

--
-- Name: usuarios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.usuarios_id_seq OWNED BY public.usuarios.id;


--
-- Name: vista_balance_comprobacion; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vista_balance_comprobacion AS
 SELECT cc.codigo,
    cc.nombre,
    cc.naturaleza,
    tc.categoria,
    COALESCE(sum(da.debe), (0)::numeric) AS total_debe,
    COALESCE(sum(da.haber), (0)::numeric) AS total_haber,
        CASE
            WHEN ((cc.naturaleza)::text = 'DEUDORA'::text) THEN (COALESCE(sum(da.debe), (0)::numeric) - COALESCE(sum(da.haber), (0)::numeric))
            ELSE (COALESCE(sum(da.haber), (0)::numeric) - COALESCE(sum(da.debe), (0)::numeric))
        END AS saldo_final
   FROM (((public.cuentas_contables cc
     JOIN public.tipos_cuenta tc ON ((cc.id_tipo_cuenta = tc.id)))
     LEFT JOIN public.detalle_asientos da ON ((cc.id = da.id_cuenta)))
     LEFT JOIN public.asientos_contables ac ON (((da.id_asiento = ac.id) AND ((ac.estado)::text = 'CONFIRMADO'::text))))
  WHERE (cc.acepta_movimientos = true)
  GROUP BY cc.id, cc.codigo, cc.nombre, cc.naturaleza, tc.categoria
  ORDER BY cc.codigo;


ALTER VIEW public.vista_balance_comprobacion OWNER TO postgres;

--
-- Name: vista_balance_general; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vista_balance_general AS
 SELECT tc.categoria,
    cc.codigo,
    cc.nombre,
        CASE
            WHEN ((cc.naturaleza)::text = 'DEUDORA'::text) THEN (COALESCE(sum(da.debe), (0)::numeric) - COALESCE(sum(da.haber), (0)::numeric))
            ELSE (COALESCE(sum(da.haber), (0)::numeric) - COALESCE(sum(da.debe), (0)::numeric))
        END AS saldo
   FROM (((public.cuentas_contables cc
     JOIN public.tipos_cuenta tc ON ((cc.id_tipo_cuenta = tc.id)))
     LEFT JOIN public.detalle_asientos da ON ((cc.id = da.id_cuenta)))
     LEFT JOIN public.asientos_contables ac ON (((da.id_asiento = ac.id) AND ((ac.estado)::text = 'CONFIRMADO'::text))))
  WHERE (((tc.categoria)::text = ANY ((ARRAY['ACTIVO'::character varying, 'PASIVO'::character varying, 'PATRIMONIO'::character varying])::text[])) AND (cc.acepta_movimientos = true))
  GROUP BY tc.categoria, cc.id, cc.codigo, cc.nombre, cc.naturaleza
 HAVING (abs(
        CASE
            WHEN ((cc.naturaleza)::text = 'DEUDORA'::text) THEN (COALESCE(sum(da.debe), (0)::numeric) - COALESCE(sum(da.haber), (0)::numeric))
            ELSE (COALESCE(sum(da.haber), (0)::numeric) - COALESCE(sum(da.debe), (0)::numeric))
        END) > (0)::numeric)
  ORDER BY tc.categoria, cc.codigo;


ALTER VIEW public.vista_balance_general OWNER TO postgres;

--
-- Name: vista_estado_resultados; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vista_estado_resultados AS
 SELECT tc.categoria,
    cc.codigo,
    cc.nombre,
        CASE
            WHEN ((tc.categoria)::text = 'INGRESO'::text) THEN (COALESCE(sum(da.haber), (0)::numeric) - COALESCE(sum(da.debe), (0)::numeric))
            WHEN ((tc.categoria)::text = 'GASTO'::text) THEN (COALESCE(sum(da.debe), (0)::numeric) - COALESCE(sum(da.haber), (0)::numeric))
            ELSE (0)::numeric
        END AS monto
   FROM (((public.cuentas_contables cc
     JOIN public.tipos_cuenta tc ON ((cc.id_tipo_cuenta = tc.id)))
     LEFT JOIN public.detalle_asientos da ON ((cc.id = da.id_cuenta)))
     LEFT JOIN public.asientos_contables ac ON (((da.id_asiento = ac.id) AND ((ac.estado)::text = 'CONFIRMADO'::text))))
  WHERE (((tc.categoria)::text = ANY ((ARRAY['INGRESO'::character varying, 'GASTO'::character varying])::text[])) AND (cc.acepta_movimientos = true))
  GROUP BY tc.categoria, cc.id, cc.codigo, cc.nombre
 HAVING ((COALESCE(sum(da.debe), (0)::numeric) + COALESCE(sum(da.haber), (0)::numeric)) > (0)::numeric)
  ORDER BY tc.categoria, cc.codigo;


ALTER VIEW public.vista_estado_resultados OWNER TO postgres;

--
-- Name: vista_facturas_dte; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vista_facturas_dte AS
SELECT
    NULL::integer AS id,
    NULL::date AS fecha_factura,
    NULL::character varying(50) AS serie,
    NULL::character varying(50) AS numero,
    NULL::character varying(20) AS ruc,
    NULL::character varying(255) AS proveedor,
    NULL::numeric(15,2) AS importe,
    NULL::character varying(3) AS moneda,
    NULL::character varying(20) AS estado_factura,
    NULL::character varying(20) AS dte_folio,
    NULL::integer AS dte_tipo,
    NULL::character varying(50) AS dte_estado,
    NULL::timestamp without time zone AS dte_fecha_envio,
    NULL::character varying(50) AS estado_sii,
    NULL::text AS glosa_sii,
    NULL::character varying(100) AS track_id,
    NULL::timestamp without time zone AS fecha_respuesta_sii,
    NULL::text AS tipo_dte_desc,
    NULL::bigint AS total_items;


ALTER VIEW public.vista_facturas_dte OWNER TO postgres;

--
-- Name: alertas_stock id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alertas_stock ALTER COLUMN id SET DEFAULT nextval('public.alertas_stock_id_seq'::regclass);


--
-- Name: almacenes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.almacenes ALTER COLUMN id SET DEFAULT nextval('public.almacenes_id_seq'::regclass);


--
-- Name: asientos_contables id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asientos_contables ALTER COLUMN id SET DEFAULT nextval('public.asientos_contables_id_seq'::regclass);


--
-- Name: centros_costo id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.centros_costo ALTER COLUMN id SET DEFAULT nextval('public.centros_costo_id_seq'::regclass);


--
-- Name: configuracion_contable id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion_contable ALTER COLUMN id SET DEFAULT nextval('public.configuracion_contable_id_seq'::regclass);


--
-- Name: cuentas_contables id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cuentas_contables ALTER COLUMN id SET DEFAULT nextval('public.cuentas_contables_id_seq'::regclass);


--
-- Name: detalle_asientos id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_asientos ALTER COLUMN id SET DEFAULT nextval('public.detalle_asientos_id_seq'::regclass);


--
-- Name: dte_folios id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dte_folios ALTER COLUMN id SET DEFAULT nextval('public.dte_folios_id_seq'::regclass);


--
-- Name: dte_seguimiento id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dte_seguimiento ALTER COLUMN id SET DEFAULT nextval('public.dte_seguimiento_id_seq'::regclass);


--
-- Name: factura_asientos id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura_asientos ALTER COLUMN id SET DEFAULT nextval('public.factura_asientos_id_seq'::regclass);


--
-- Name: factura_inventario id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura_inventario ALTER COLUMN id SET DEFAULT nextval('public.factura_inventario_id_seq'::regclass);


--
-- Name: factura_items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura_items ALTER COLUMN id SET DEFAULT nextval('public.factura_items_id_seq'::regclass);


--
-- Name: facturas id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facturas ALTER COLUMN id SET DEFAULT nextval('public.facturas_id_seq'::regclass);


--
-- Name: integraciones_log id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.integraciones_log ALTER COLUMN id SET DEFAULT nextval('public.integraciones_log_id_seq'::regclass);


--
-- Name: inventario id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventario ALTER COLUMN id SET DEFAULT nextval('public.inventario_id_seq'::regclass);


--
-- Name: movimientos_stock id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movimientos_stock ALTER COLUMN id SET DEFAULT nextval('public.movimientos_stock_id_seq'::regclass);


--
-- Name: negocios id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.negocios ALTER COLUMN id SET DEFAULT nextval('public.negocios_id_seq'::regclass);


--
-- Name: pedidos id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos ALTER COLUMN id SET DEFAULT nextval('public.pedidos_id_seq'::regclass);


--
-- Name: periodos_contables id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.periodos_contables ALTER COLUMN id SET DEFAULT nextval('public.periodos_contables_id_seq'::regclass);


--
-- Name: productos id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.productos ALTER COLUMN id SET DEFAULT nextval('public.productos_id_seq'::regclass);


--
-- Name: recetas id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.recetas ALTER COLUMN id SET DEFAULT nextval('public.recetas_id_seq'::regclass);


--
-- Name: saldos_contables id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.saldos_contables ALTER COLUMN id SET DEFAULT nextval('public.saldos_contables_id_seq'::regclass);


--
-- Name: sii_configuracion id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sii_configuracion ALTER COLUMN id SET DEFAULT nextval('public.sii_configuracion_id_seq'::regclass);


--
-- Name: tipos_cuenta id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipos_cuenta ALTER COLUMN id SET DEFAULT nextval('public.tipos_cuenta_id_seq'::regclass);


--
-- Name: transacciones_contables id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transacciones_contables ALTER COLUMN id SET DEFAULT nextval('public.transacciones_contables_id_seq'::regclass);


--
-- Name: usuarios id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios ALTER COLUMN id SET DEFAULT nextval('public.usuarios_id_seq'::regclass);


--
-- Name: alertas_stock alertas_stock_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alertas_stock
    ADD CONSTRAINT alertas_stock_pkey PRIMARY KEY (id);


--
-- Name: almacenes almacenes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.almacenes
    ADD CONSTRAINT almacenes_pkey PRIMARY KEY (id);


--
-- Name: asientos_contables asientos_contables_id_negocio_numero_asiento_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asientos_contables
    ADD CONSTRAINT asientos_contables_id_negocio_numero_asiento_key UNIQUE (id_negocio, numero_asiento);


--
-- Name: asientos_contables asientos_contables_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asientos_contables
    ADD CONSTRAINT asientos_contables_pkey PRIMARY KEY (id);


--
-- Name: centros_costo centros_costo_codigo_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.centros_costo
    ADD CONSTRAINT centros_costo_codigo_key UNIQUE (codigo);


--
-- Name: centros_costo centros_costo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.centros_costo
    ADD CONSTRAINT centros_costo_pkey PRIMARY KEY (id);


--
-- Name: configuracion_contable configuracion_contable_id_negocio_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion_contable
    ADD CONSTRAINT configuracion_contable_id_negocio_key UNIQUE (id_negocio);


--
-- Name: configuracion_contable configuracion_contable_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion_contable
    ADD CONSTRAINT configuracion_contable_pkey PRIMARY KEY (id);


--
-- Name: cuentas_contables cuentas_contables_codigo_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cuentas_contables
    ADD CONSTRAINT cuentas_contables_codigo_key UNIQUE (codigo);


--
-- Name: cuentas_contables cuentas_contables_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cuentas_contables
    ADD CONSTRAINT cuentas_contables_pkey PRIMARY KEY (id);


--
-- Name: detalle_asientos detalle_asientos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_asientos
    ADD CONSTRAINT detalle_asientos_pkey PRIMARY KEY (id);


--
-- Name: dte_folios dte_folios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dte_folios
    ADD CONSTRAINT dte_folios_pkey PRIMARY KEY (id);


--
-- Name: dte_seguimiento dte_seguimiento_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dte_seguimiento
    ADD CONSTRAINT dte_seguimiento_pkey PRIMARY KEY (id);


--
-- Name: factura_asientos factura_asientos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura_asientos
    ADD CONSTRAINT factura_asientos_pkey PRIMARY KEY (id);


--
-- Name: factura_inventario factura_inventario_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura_inventario
    ADD CONSTRAINT factura_inventario_pkey PRIMARY KEY (id);


--
-- Name: factura_items factura_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura_items
    ADD CONSTRAINT factura_items_pkey PRIMARY KEY (id);


--
-- Name: facturas facturas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.facturas
    ADD CONSTRAINT facturas_pkey PRIMARY KEY (id);


--
-- Name: integraciones_log integraciones_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.integraciones_log
    ADD CONSTRAINT integraciones_log_pkey PRIMARY KEY (id);


--
-- Name: inventario inventario_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventario
    ADD CONSTRAINT inventario_pkey PRIMARY KEY (id);


--
-- Name: movimientos_stock movimientos_stock_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movimientos_stock
    ADD CONSTRAINT movimientos_stock_pkey PRIMARY KEY (id);


--
-- Name: negocios negocios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.negocios
    ADD CONSTRAINT negocios_pkey PRIMARY KEY (id);


--
-- Name: pedidos pedidos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos
    ADD CONSTRAINT pedidos_pkey PRIMARY KEY (id);


--
-- Name: periodos_contables periodos_contables_id_negocio_año_mes_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.periodos_contables
    ADD CONSTRAINT "periodos_contables_id_negocio_año_mes_key" UNIQUE (id_negocio, "año", mes);


--
-- Name: periodos_contables periodos_contables_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.periodos_contables
    ADD CONSTRAINT periodos_contables_pkey PRIMARY KEY (id);


--
-- Name: productos productos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.productos
    ADD CONSTRAINT productos_pkey PRIMARY KEY (id);


--
-- Name: recetas recetas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.recetas
    ADD CONSTRAINT recetas_pkey PRIMARY KEY (id);


--
-- Name: saldos_contables saldos_contables_id_cuenta_id_negocio_año_mes_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.saldos_contables
    ADD CONSTRAINT "saldos_contables_id_cuenta_id_negocio_año_mes_key" UNIQUE (id_cuenta, id_negocio, "año", mes);


--
-- Name: saldos_contables saldos_contables_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.saldos_contables
    ADD CONSTRAINT saldos_contables_pkey PRIMARY KEY (id);


--
-- Name: sii_configuracion sii_configuracion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sii_configuracion
    ADD CONSTRAINT sii_configuracion_pkey PRIMARY KEY (id);


--
-- Name: tipos_cuenta tipos_cuenta_codigo_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipos_cuenta
    ADD CONSTRAINT tipos_cuenta_codigo_key UNIQUE (codigo);


--
-- Name: tipos_cuenta tipos_cuenta_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipos_cuenta
    ADD CONSTRAINT tipos_cuenta_pkey PRIMARY KEY (id);


--
-- Name: transacciones_contables transacciones_contables_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transacciones_contables
    ADD CONSTRAINT transacciones_contables_pkey PRIMARY KEY (id);


--
-- Name: inventario unique_producto_almacen; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventario
    ADD CONSTRAINT unique_producto_almacen UNIQUE (id_producto, id_almacen);


--
-- Name: sii_configuracion unique_rut_empresa; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sii_configuracion
    ADD CONSTRAINT unique_rut_empresa UNIQUE (rut_empresa);


--
-- Name: usuarios usuarios_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_email_key UNIQUE (email);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);


--
-- Name: idx_asientos_estado; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_asientos_estado ON public.asientos_contables USING btree (estado);


--
-- Name: idx_asientos_fecha; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_asientos_fecha ON public.asientos_contables USING btree (fecha_asiento);


--
-- Name: idx_asientos_negocio; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_asientos_negocio ON public.asientos_contables USING btree (id_negocio);


--
-- Name: idx_asientos_numero; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_asientos_numero ON public.asientos_contables USING btree (numero_asiento);


--
-- Name: idx_asientos_tipo_origen; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_asientos_tipo_origen ON public.asientos_contables USING btree (tipo_origen, id_origen);


--
-- Name: idx_cuentas_contables_activa; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cuentas_contables_activa ON public.cuentas_contables USING btree (activa);


--
-- Name: idx_cuentas_contables_codigo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cuentas_contables_codigo ON public.cuentas_contables USING btree (codigo);


--
-- Name: idx_cuentas_contables_negocio; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cuentas_contables_negocio ON public.cuentas_contables USING btree (id_negocio);


--
-- Name: idx_cuentas_contables_padre; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cuentas_contables_padre ON public.cuentas_contables USING btree (id_cuenta_padre);


--
-- Name: idx_detalle_asientos_asiento; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_detalle_asientos_asiento ON public.detalle_asientos USING btree (id_asiento);


--
-- Name: idx_detalle_asientos_cuenta; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_detalle_asientos_cuenta ON public.detalle_asientos USING btree (id_cuenta);


--
-- Name: idx_dte_seguimiento_factura_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_dte_seguimiento_factura_id ON public.dte_seguimiento USING btree (factura_id);


--
-- Name: idx_factura_items_factura_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_factura_items_factura_id ON public.factura_items USING btree (factura_id);


--
-- Name: idx_facturas_dte_estado; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_facturas_dte_estado ON public.facturas USING btree (dte_estado);


--
-- Name: idx_facturas_dte_folio; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_facturas_dte_folio ON public.facturas USING btree (dte_folio);


--
-- Name: idx_facturas_dte_tipo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_facturas_dte_tipo ON public.facturas USING btree (dte_tipo);


--
-- Name: idx_facturas_estado; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_facturas_estado ON public.facturas USING btree (estado);


--
-- Name: idx_facturas_fecha; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_facturas_fecha ON public.facturas USING btree (fecha_factura);


--
-- Name: idx_facturas_proveedor; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_facturas_proveedor ON public.facturas USING btree (proveedor);


--
-- Name: idx_integraciones_fecha; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_integraciones_fecha ON public.integraciones_log USING btree (fecha_procesamiento);


--
-- Name: idx_integraciones_origen; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_integraciones_origen ON public.integraciones_log USING btree (modulo_origen, id_registro_origen);


--
-- Name: idx_saldos_cuenta_periodo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_saldos_cuenta_periodo ON public.saldos_contables USING btree (id_cuenta, "año", mes);


--
-- Name: idx_saldos_negocio_periodo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_saldos_negocio_periodo ON public.saldos_contables USING btree (id_negocio, "año", mes);


--
-- Name: vista_facturas_dte _RETURN; Type: RULE; Schema: public; Owner: postgres
--

CREATE OR REPLACE VIEW public.vista_facturas_dte AS
 SELECT f.id,
    f.fecha_factura,
    f.serie,
    f.numero,
    f.ruc,
    f.proveedor,
    f.importe,
    f.moneda,
    f.estado AS estado_factura,
    f.dte_folio,
    f.dte_tipo,
    f.dte_estado,
    f.dte_fecha_envio,
    ds.estado_sii,
    ds.glosa_sii,
    ds.track_id,
    ds.fecha_respuesta_sii,
        CASE
            WHEN (f.dte_tipo = 33) THEN 'Factura Electrónica'::text
            WHEN (f.dte_tipo = 39) THEN 'Boleta Electrónica'::text
            WHEN (f.dte_tipo = 52) THEN 'Guía de Despacho'::text
            WHEN (f.dte_tipo = 56) THEN 'Nota de Débito'::text
            WHEN (f.dte_tipo = 61) THEN 'Nota de Crédito'::text
            ELSE 'Tipo Desconocido'::text
        END AS tipo_dte_desc,
    count(fi.id) AS total_items
   FROM ((public.facturas f
     LEFT JOIN public.dte_seguimiento ds ON ((f.id = ds.factura_id)))
     LEFT JOIN public.factura_items fi ON ((f.id = fi.factura_id)))
  GROUP BY f.id, ds.id;


--
-- Name: facturas trigger_asiento_factura; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_asiento_factura AFTER UPDATE ON public.facturas FOR EACH ROW EXECUTE FUNCTION public.crear_asiento_factura();


--
-- Name: asientos_contables trigger_asientos_contables_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_asientos_contables_updated_at BEFORE UPDATE ON public.asientos_contables FOR EACH ROW EXECUTE FUNCTION public.actualizar_updated_at();


--
-- Name: configuracion_contable trigger_configuracion_contable_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_configuracion_contable_updated_at BEFORE UPDATE ON public.configuracion_contable FOR EACH ROW EXECUTE FUNCTION public.actualizar_updated_at();


--
-- Name: cuentas_contables trigger_cuentas_contables_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_cuentas_contables_updated_at BEFORE UPDATE ON public.cuentas_contables FOR EACH ROW EXECUTE FUNCTION public.actualizar_updated_at();


--
-- Name: asientos_contables trigger_generar_numero_asiento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_generar_numero_asiento BEFORE INSERT ON public.asientos_contables FOR EACH ROW WHEN (((new.numero_asiento IS NULL) OR ((new.numero_asiento)::text = ''::text))) EXECUTE FUNCTION public.generar_numero_asiento();


--
-- Name: detalle_asientos trigger_validar_asiento_balanceado; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_validar_asiento_balanceado AFTER INSERT OR DELETE OR UPDATE ON public.detalle_asientos FOR EACH ROW EXECUTE FUNCTION public.validar_asiento_balanceado();


--
-- Name: alertas_stock alertas_stock_id_almacen_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alertas_stock
    ADD CONSTRAINT alertas_stock_id_almacen_fkey FOREIGN KEY (id_almacen) REFERENCES public.almacenes(id) ON DELETE CASCADE;


--
-- Name: alertas_stock alertas_stock_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alertas_stock
    ADD CONSTRAINT alertas_stock_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.productos(id) ON DELETE CASCADE;


--
-- Name: almacenes almacenes_id_negocio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.almacenes
    ADD CONSTRAINT almacenes_id_negocio_fkey FOREIGN KEY (id_negocio) REFERENCES public.negocios(id) ON DELETE CASCADE;


--
-- Name: asientos_contables asientos_contables_id_centro_costo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asientos_contables
    ADD CONSTRAINT asientos_contables_id_centro_costo_fkey FOREIGN KEY (id_centro_costo) REFERENCES public.centros_costo(id);


--
-- Name: asientos_contables asientos_contables_id_negocio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asientos_contables
    ADD CONSTRAINT asientos_contables_id_negocio_fkey FOREIGN KEY (id_negocio) REFERENCES public.negocios(id) ON DELETE CASCADE;


--
-- Name: asientos_contables asientos_contables_id_periodo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asientos_contables
    ADD CONSTRAINT asientos_contables_id_periodo_fkey FOREIGN KEY (id_periodo) REFERENCES public.periodos_contables(id);


--
-- Name: centros_costo centros_costo_id_negocio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.centros_costo
    ADD CONSTRAINT centros_costo_id_negocio_fkey FOREIGN KEY (id_negocio) REFERENCES public.negocios(id) ON DELETE CASCADE;


--
-- Name: configuracion_contable configuracion_contable_cuenta_caja_default_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion_contable
    ADD CONSTRAINT configuracion_contable_cuenta_caja_default_fkey FOREIGN KEY (cuenta_caja_default) REFERENCES public.cuentas_contables(id);


--
-- Name: configuracion_contable configuracion_contable_cuenta_clientes_default_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion_contable
    ADD CONSTRAINT configuracion_contable_cuenta_clientes_default_fkey FOREIGN KEY (cuenta_clientes_default) REFERENCES public.cuentas_contables(id);


--
-- Name: configuracion_contable configuracion_contable_cuenta_compras_default_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion_contable
    ADD CONSTRAINT configuracion_contable_cuenta_compras_default_fkey FOREIGN KEY (cuenta_compras_default) REFERENCES public.cuentas_contables(id);


--
-- Name: configuracion_contable configuracion_contable_cuenta_costo_ventas_default_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion_contable
    ADD CONSTRAINT configuracion_contable_cuenta_costo_ventas_default_fkey FOREIGN KEY (cuenta_costo_ventas_default) REFERENCES public.cuentas_contables(id);


--
-- Name: configuracion_contable configuracion_contable_cuenta_inventario_default_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion_contable
    ADD CONSTRAINT configuracion_contable_cuenta_inventario_default_fkey FOREIGN KEY (cuenta_inventario_default) REFERENCES public.cuentas_contables(id);


--
-- Name: configuracion_contable configuracion_contable_cuenta_proveedores_default_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion_contable
    ADD CONSTRAINT configuracion_contable_cuenta_proveedores_default_fkey FOREIGN KEY (cuenta_proveedores_default) REFERENCES public.cuentas_contables(id);


--
-- Name: configuracion_contable configuracion_contable_cuenta_ventas_default_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion_contable
    ADD CONSTRAINT configuracion_contable_cuenta_ventas_default_fkey FOREIGN KEY (cuenta_ventas_default) REFERENCES public.cuentas_contables(id);


--
-- Name: configuracion_contable configuracion_contable_id_negocio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion_contable
    ADD CONSTRAINT configuracion_contable_id_negocio_fkey FOREIGN KEY (id_negocio) REFERENCES public.negocios(id) ON DELETE CASCADE;


--
-- Name: cuentas_contables cuentas_contables_id_cuenta_padre_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cuentas_contables
    ADD CONSTRAINT cuentas_contables_id_cuenta_padre_fkey FOREIGN KEY (id_cuenta_padre) REFERENCES public.cuentas_contables(id);


--
-- Name: cuentas_contables cuentas_contables_id_negocio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cuentas_contables
    ADD CONSTRAINT cuentas_contables_id_negocio_fkey FOREIGN KEY (id_negocio) REFERENCES public.negocios(id) ON DELETE CASCADE;


--
-- Name: cuentas_contables cuentas_contables_id_tipo_cuenta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cuentas_contables
    ADD CONSTRAINT cuentas_contables_id_tipo_cuenta_fkey FOREIGN KEY (id_tipo_cuenta) REFERENCES public.tipos_cuenta(id);


--
-- Name: detalle_asientos detalle_asientos_id_asiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_asientos
    ADD CONSTRAINT detalle_asientos_id_asiento_fkey FOREIGN KEY (id_asiento) REFERENCES public.asientos_contables(id) ON DELETE CASCADE;


--
-- Name: detalle_asientos detalle_asientos_id_centro_costo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_asientos
    ADD CONSTRAINT detalle_asientos_id_centro_costo_fkey FOREIGN KEY (id_centro_costo) REFERENCES public.centros_costo(id);


--
-- Name: detalle_asientos detalle_asientos_id_cuenta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_asientos
    ADD CONSTRAINT detalle_asientos_id_cuenta_fkey FOREIGN KEY (id_cuenta) REFERENCES public.cuentas_contables(id);


--
-- Name: dte_seguimiento dte_seguimiento_factura_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dte_seguimiento
    ADD CONSTRAINT dte_seguimiento_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES public.facturas(id) ON DELETE CASCADE;


--
-- Name: factura_asientos factura_asientos_factura_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura_asientos
    ADD CONSTRAINT factura_asientos_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES public.facturas(id) ON DELETE CASCADE;


--
-- Name: factura_inventario factura_inventario_factura_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura_inventario
    ADD CONSTRAINT factura_inventario_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES public.facturas(id) ON DELETE CASCADE;


--
-- Name: factura_items factura_items_factura_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura_items
    ADD CONSTRAINT factura_items_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES public.facturas(id) ON DELETE CASCADE;


--
-- Name: integraciones_log integraciones_log_id_asiento_generado_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.integraciones_log
    ADD CONSTRAINT integraciones_log_id_asiento_generado_fkey FOREIGN KEY (id_asiento_generado) REFERENCES public.asientos_contables(id);


--
-- Name: inventario inventario_id_almacen_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventario
    ADD CONSTRAINT inventario_id_almacen_fkey FOREIGN KEY (id_almacen) REFERENCES public.almacenes(id) ON DELETE CASCADE;


--
-- Name: inventario inventario_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventario
    ADD CONSTRAINT inventario_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.productos(id) ON DELETE CASCADE;


--
-- Name: movimientos_stock movimientos_stock_id_almacen_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movimientos_stock
    ADD CONSTRAINT movimientos_stock_id_almacen_fkey FOREIGN KEY (id_almacen) REFERENCES public.almacenes(id) ON DELETE CASCADE;


--
-- Name: movimientos_stock movimientos_stock_id_producto_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movimientos_stock
    ADD CONSTRAINT movimientos_stock_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.productos(id) ON DELETE CASCADE;


--
-- Name: pedidos pedidos_id_negocio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos
    ADD CONSTRAINT pedidos_id_negocio_fkey FOREIGN KEY (id_negocio) REFERENCES public.negocios(id) ON DELETE CASCADE;


--
-- Name: periodos_contables periodos_contables_id_negocio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.periodos_contables
    ADD CONSTRAINT periodos_contables_id_negocio_fkey FOREIGN KEY (id_negocio) REFERENCES public.negocios(id) ON DELETE CASCADE;


--
-- Name: recetas recetas_id_producto_final_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.recetas
    ADD CONSTRAINT recetas_id_producto_final_fkey FOREIGN KEY (id_producto_final) REFERENCES public.productos(id) ON DELETE CASCADE;


--
-- Name: recetas recetas_id_producto_insumo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.recetas
    ADD CONSTRAINT recetas_id_producto_insumo_fkey FOREIGN KEY (id_producto_insumo) REFERENCES public.productos(id) ON DELETE CASCADE;


--
-- Name: saldos_contables saldos_contables_id_cuenta_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.saldos_contables
    ADD CONSTRAINT saldos_contables_id_cuenta_fkey FOREIGN KEY (id_cuenta) REFERENCES public.cuentas_contables(id) ON DELETE CASCADE;


--
-- Name: saldos_contables saldos_contables_id_negocio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.saldos_contables
    ADD CONSTRAINT saldos_contables_id_negocio_fkey FOREIGN KEY (id_negocio) REFERENCES public.negocios(id) ON DELETE CASCADE;


--
-- Name: transacciones_contables transacciones_contables_factura_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transacciones_contables
    ADD CONSTRAINT transacciones_contables_factura_id_fkey FOREIGN KEY (factura_id) REFERENCES public.facturas(id) ON DELETE CASCADE;


--
-- Name: usuarios usuarios_id_negocio_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_id_negocio_fkey FOREIGN KEY (id_negocio) REFERENCES public.negocios(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict zhcef3Eb3u2hM0o4hU57hlvcN6RBf1HFvKS75rRDcKxmkqFggOEBhqdWs9tLu4G

