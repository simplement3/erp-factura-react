const express = require('express');
const router = express.Router();
const { Pool } = require('pg');
const authMiddleware = require('../middleware/authMiddleware');

const pool = new Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'erp_facturas',
  password: process.env.DB_PASSWORD || 'admin',
  port: process.env.DB_PORT || 5432,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

// ===== CONFIGURACIÓN Y VALIDACIONES =====

const TIPOS_DTE = {
  33: { nombre: 'Factura Electrónica', codigo: 'FE' },
  39: { nombre: 'Boleta Electrónica', codigo: 'BE' },
  52: { nombre: 'Guía de Despacho Electrónica', codigo: 'GDE' },
  56: { nombre: 'Nota de Débito Electrónica', codigo: 'NDE' },
  61: { nombre: 'Nota de Crédito Electrónica', codigo: 'NCE' }
};

// ===== ENDPOINT PRINCIPAL GENERAR DTE =====

router.post('/generar-dte', authMiddleware, async (req, res) => {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const { factura_id, tipo_dte } = req.body;

    // Validaciones mejoradas
    const validationResult = await validateDTERequest(client, factura_id, tipo_dte);
    if (!validationResult.valid) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        error: validationResult.error
      });
    }

    const factura = validationResult.factura;

    // Obtener configuración de empresa
    const empresaConfig = await obtenerConfiguracionEmpresa(client);

    // Generar folio único
    const folio = await obtenerSiguienteFolio(client, tipo_dte);

    // Generar XML DTE completo
    const xmlDTE = await generarXMLDTECompleto(factura, tipo_dte, folio, empresaConfig);

    // Simular envío al SII
    const resultadoSII = await simularEnvioSII(factura, tipo_dte, folio, xmlDTE);

    // Actualizar factura con información DTE
    await actualizarFacturaDTE(client, factura_id, tipo_dte, folio, xmlDTE);

    // Registrar seguimiento
    const seguimientoId = await registrarSeguimientoDTE(
      client, factura_id, tipo_dte, folio, xmlDTE, resultadoSII
    );

    // Crear asiento contable automático si corresponde
    await crearAsientoContable(client, factura, 'dte_generado');

    await client.query('COMMIT');

    console.log(`✓ DTE generado exitosamente - Factura: ${factura_id}, Tipo: ${tipo_dte}, Folio: ${folio}`);

    res.json({
      success: true,
      message: `${TIPOS_DTE[tipo_dte].nombre} generada correctamente`,
      data: {
        ...resultadoSII,
        seguimiento_id: seguimientoId,
        xml_disponible: true
      }
    });

  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error generando DTE:', error);
    res.status(500).json({
      success: false,
      error: 'Error interno al generar DTE',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  } finally {
    client.release();
  }
});

// ===== FUNCIONES AUXILIARES =====

async function validateDTERequest(client, factura_id, tipo_dte) {
  // Validar parámetros básicos
  if (!factura_id || isNaN(parseInt(factura_id))) {
    return { valid: false, error: 'ID de factura no válido' };
  }

  if (!tipo_dte || !TIPOS_DTE[parseInt(tipo_dte)]) {
    return {
      valid: false,
      error: `Tipo de DTE no válido. Tipos permitidos: ${Object.keys(TIPOS_DTE).join(', ')}`
    };
  }

  // Obtener y validar factura
  const facturaQuery = `
        SELECT f.*, 
               array_agg(
                 CASE WHEN fi.id IS NOT NULL THEN
                   json_build_object(
                     'id', fi.id,
                     'producto_insumo', fi.producto_insumo,
                     'categoria', fi.categoria,
                     'unidad_medida', fi.unidad_medida,
                     'cantidad', fi.cantidad,
                     'precio_unitario', fi.precio_unitario,
                     'valor_afecto', fi.valor_afecto,
                     'valor_inafecto', fi.valor_inafecto,
                     'impuestos', fi.impuestos,
                     'total', fi.total
                   )
                 END
               ) FILTER (WHERE fi.id IS NOT NULL) as items
        FROM facturas f
        LEFT JOIN factura_items fi ON f.id = fi.factura_id
        WHERE f.id = $1
        GROUP BY f.id
    `;

  const result = await client.query(facturaQuery, [parseInt(factura_id)]);

  if (result.rows.length === 0) {
    return { valid: false, error: 'Factura no encontrada' };
  }

  const factura = result.rows[0];

  // Validaciones de negocio
  if (!factura.proveedor || factura.proveedor.trim().length === 0) {
    return { valid: false, error: 'Factura debe tener un proveedor válido' };
  }

  if (!factura.importe || parseFloat(factura.importe) <= 0) {
    return { valid: false, error: 'Factura debe tener un importe válido mayor a 0' };
  }

  if (!factura.items || factura.items.length === 0) {
    return { valid: false, error: 'Factura debe tener al menos un ítem' };
  }

  // Verificar si ya tiene DTE generado
  if (factura.dte_folio && factura.dte_estado === 'enviada_sii') {
    return {
      valid: false,
      error: `Factura ya tiene DTE generado - Folio: ${factura.dte_folio}`
    };
  }

  return { valid: true, factura };
}

async function obtenerConfiguracionEmpresa(client) {
  const query = 'SELECT * FROM sii_configuracion WHERE activo = true ORDER BY id DESC LIMIT 1';
  const result = await client.query(query);

  if (result.rows.length === 0) {
    // Configuración por defecto si no existe
    return {
      rut_empresa: process.env.EMPRESA_RUT || '76162804-6',
      nombre_empresa: process.env.EMPRESA_NOMBRE || 'Empresa Demo Ltda',
      giro_empresa: process.env.EMPRESA_GIRO || 'Servicios Tecnológicos',
      actividad_economica: process.env.EMPRESA_ACTECO || '620200',
      direccion: process.env.EMPRESA_DIRECCION || 'Av. Las Condes 123',
      comuna: process.env.EMPRESA_COMUNA || 'Las Condes',
      ciudad: process.env.EMPRESA_CIUDAD || 'Santiago',
      telefono: process.env.EMPRESA_TELEFONO || '+56 2 2345 6789',
      email: process.env.EMPRESA_EMAIL || 'contacto@empresa.cl'
    };
  }

  return result.rows[0];
}

async function obtenerSiguienteFolio(client, tipoDte) {
  try {
    const result = await client.query('SELECT obtener_siguiente_folio($1)', [tipoDte]);
    return result.rows[0].obtener_siguiente_folio;
  } catch (error) {
    console.warn('Error obteniendo folio de BD, usando timestamp:', error.message);
    // Fallback: usar timestamp
    return Date.now().toString().slice(-8);
  }
}

async function generarXMLDTECompleto(factura, tipoDte, folio, empresa) {
  const fechaEmision = factura.fecha_factura || new Date().toISOString().split('T')[0];
  const rutReceptor = factura.ruc || '66666666-6';

  // Calcular montos (IVA 19% para Chile)
  const tasaIVA = 0.19;
  const montoNeto = Math.round(parseFloat(factura.importe) / (1 + tasaIVA));
  const montoIVA = Math.round(parseFloat(factura.importe) - montoNeto);
  const montoTotal = montoNeto + montoIVA;

  // Generar detalle de items
  const detalleItems = factura.items.map((item, index) => {
    const cantidad = parseFloat(item.cantidad) || 1;
    const precioUnitario = parseFloat(item.precio_unitario) || 0;
    const total = parseFloat(item.total) || (cantidad * precioUnitario);

    return `
        <Detalle>
            <NroLinDet>${index + 1}</NroLinDet>
            <IndExe>0</IndExe>
            <NmbItem><![CDATA[${item.producto_insumo || 'Producto/Servicio'}]]></NmbItem>
            <DscItem><![CDATA[${item.categoria || ''}]]></DscItem>
            <QtyItem>${cantidad}</QtyItem>
            <UnmdItem>${item.unidad_medida || 'UN'}</UnmdItem>
            <PrcItem>${precioUnitario}</PrcItem>
            <MontoItem>${Math.round(total)}</MontoItem>
        </Detalle>`;
  }).join('');

  const xmlDTE = `<?xml version="1.0" encoding="UTF-8"?>
<DTE version="1.0" xmlns="http://www.sii.cl/SiiDte">
    <Documento ID="MiPE${folio}">
        <Encabezado>
            <IdDoc>
                <TipoDTE>${tipoDte}</TipoDTE>
                <Folio>${folio}</Folio>
                <FchEmis>${fechaEmision}</FchEmis>
                <IndNoRebaja>0</IndNoRebaja>
                <TipoDespacho>1</TipoDespacho>
                <IndTraslado>1</IndTraslado>
                <TpoImpresion>N</TpoImpresion>
                <IndServicio>3</IndServicio>
                <MntBruto>1</MntBruto>
                <FmaPago>1</FmaPago>
                <FchCancel>${fechaEmision}</FchCancel>
            </IdDoc>
            <Emisor>
                <RUTEmisor>${empresa.rut_empresa}</RUTEmisor>
                <RznSoc><![CDATA[${empresa.nombre_empresa}]]></RznSoc>
                <GiroEmis><![CDATA[${empresa.giro_empresa}]]></GiroEmis>
                <Acteco>${empresa.actividad_economica}</Acteco>
                <CdgSIISucur>81208400</CdgSIISucur>
                <DirOrigen><![CDATA[${empresa.direccion}]]></DirOrigen>
                <CmnaOrigen>${empresa.comuna}</CmnaOrigen>
                <CiudadOrigen>${empresa.ciudad}</CiudadOrigen>
                <Telefono>${empresa.telefono}</Telefono>
                <CorreoEmisor>${empresa.email}</CorreoEmisor>
            </Emisor>
            <Receptor>
                <RUTRecep>${rutReceptor}</RUTRecep>
                <RznSocRecep><![CDATA[${factura.proveedor}]]></RznSocRecep>
                <GiroRecep>Giro Comercial</GiroRecep>
                <DirRecep>Dirección Cliente</DirRecep>
                <CmnaRecep>Comuna Cliente</CmnaRecep>
                <CiudadRecep>Santiago</CiudadRecep>
                <CorreoRecep>cliente@email.com</CorreoRecep>
            </Receptor>
            <Totales>
                <MntNeto>${montoNeto}</MntNeto>
                <MntExe>0</MntExe>
                <TasaIVA>${Math.round(tasaIVA * 100)}</TasaIVA>
                <IVA>${montoIVA}</IVA>
                <MntTotal>${montoTotal}</MntTotal>
            </Totales>
        </Encabezado>
        ${detalleItems}
        <TED version="1.0">
            <DD>
                <RE>${empresa.rut_empresa}</RE>
                <TD>${tipoDte}</TD>
                <F>${folio}</F>
                <FE>${fechaEmision}</FE>
                <RR>${rutReceptor}</RR>
                <RSR><![CDATA[${factura.proveedor}]]></RSR>
                <MNT>${montoTotal}</MNT>
                <IT1>${factura.items[0]?.producto_insumo || 'Servicios'}</IT1>
                <CAF version="1.0">
                    <DA>
                        <RE>${empresa.rut_empresa}</RE>
                        <RS><![CDATA[${empresa.nombre_empresa}]]></RS>
                        <TD>${tipoDte}</TD>
                        <RNG><D>${folio}</D><H>${folio + 999}</H></RNG>
                        <FA>${fechaEmision}</FA>
                        <RSAPK><M><!-- RSA Key Mock --></M><E><!-- RSA Exponent Mock --></E></RSAPK>
                        <IDK>300</IDK>
                    </DA>
                    <FRMA algoritmo="SHA1withRSA"><!-- Firma Mock --></FRMA>
                </CAF>
                <TSTED>${new Date().toISOString()}</TSTED>
            </DD>
            <FRMT algoritmo="SHA1withRSA"><!-- Firma Electrónica Mock --></FRMT>
        </TED>
    </Documento>
</DTE>`;

  return xmlDTE;
}

async function simularEnvioSII(factura, tipoDte, folio, xmlDTE) {
  // Simular tiempo de procesamiento
  await new Promise(resolve => setTimeout(resolve, 1000));

  const trackId = `TRACK_${Date.now()}_${folio}`;

  return {
    success: true,
    status: 'ACEPTADO',
    message: `${TIPOS_DTE[tipoDte].nombre} enviado y aceptado por SII (simulación)`,
    tipo_dte: parseInt(tipoDte),
    folio: folio.toString(),
    fecha: new Date().toISOString(),
    track_id: trackId,
    rut_emisor: process.env.EMPRESA_RUT || '76162804-6',
    rut_receptor: factura.ruc || '66666666-6',
    monto_total: parseFloat(factura.importe),
    xml: xmlDTE,
    estado_sii: 'ACEPTADO_SIMULACION',
    codigo_sii: '0',
    glosa_sii: 'DTE Aceptado en Simulación'
  };
}

async function actualizarFacturaDTE(client, facturaId, tipoDte, folio, xmlDTE) {
  const updateQuery = `
        UPDATE facturas 
        SET estado = $1,
            dte_folio = $2,
            dte_tipo = $3,
            dte_fecha_envio = NOW(),
            dte_estado = $4,
            dte_xml = $5
        WHERE id = $6
    `;

  await client.query(updateQuery, [
    'enviada_sii', folio, tipoDte, 'enviada_sii', xmlDTE, facturaId
  ]);
}

async function registrarSeguimientoDTE(client, facturaId, tipoDte, folio, xmlDTE, resultadoSII) {
  const insertQuery = `
        INSERT INTO dte_seguimiento (
            factura_id, tipo_dte, folio, estado_sii, glosa_sii,
            track_id, fecha_envio, fecha_respuesta_sii,
            xml_enviado, xml_respuesta, intentos_envio
        ) VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW(), $7, $8, 1)
        RETURNING id
    `;

  const result = await client.query(insertQuery, [
    facturaId, tipoDte, folio, resultadoSII.estado_sii, resultadoSII.glosa_sii,
    resultadoSII.track_id, xmlDTE, JSON.stringify(resultadoSII)
  ]);

  return result.rows[0].id;
}

async function crearAsientoContable(client, factura, tipoOperacion) {
  try {
    // Crear asiento contable automático
    const insertAsiento = `
            INSERT INTO factura_asientos (
                factura_id, tipo_asiento, monto, fecha_asiento, descripcion
            ) VALUES ($1, $2, $3, $4, $5)
        `;

    await client.query(insertAsiento, [
      factura.id,
      tipoOperacion,
      factura.importe,
      factura.fecha_factura,
      `Asiento automático - DTE generado para ${factura.proveedor}`
    ]);

    console.log(`✓ Asiento contable creado para factura ${factura.id}`);

  } catch (error) {
    console.warn('Error creando asiento contable:', error.message);
    // No detener el proceso si falla el asiento
  }
}

// ===== ENDPOINTS ADICIONALES PARA GESTIÓN DTE =====

// Consultar estado DTE en SII (simulado)
router.get('/consultar-estado/:factura_id', authMiddleware, async (req, res) => {
  try {
    const { factura_id } = req.params;

    const query = `
            SELECT f.*, ds.* 
            FROM facturas f
            LEFT JOIN dte_seguimiento ds ON f.id = ds.factura_id
            WHERE f.id = $1
        `;

    const result = await pool.query(query, [factura_id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Factura no encontrada'
      });
    }

    const data = result.rows[0];

    if (!data.dte_folio) {
      return res.json({
        success: true,
        estado: 'sin_dte',
        message: 'Factura no tiene DTE generado'
      });
    }

    // Simular consulta al SII
    const estadoSII = await simularConsultaEstadoSII(data.track_id);

    res.json({
      success: true,
      data: {
        factura_id: data.id,
        folio: data.dte_folio,
        tipo_dte: data.dte_tipo,
        estado_sii: estadoSII.estado,
        glosa_sii: estadoSII.glosa,
        fecha_envio: data.dte_fecha_envio,
        track_id: data.track_id
      }
    });

  } catch (error) {
    console.error('Error consultando estado DTE:', error);
    res.status(500).json({
      success: false,
      error: 'Error consultando estado en SII'
    });
  }
});

// Descargar XML DTE
router.get('/descargar-xml/:factura_id', authMiddleware, async (req, res) => {
  try {
    const { factura_id } = req.params;

    const query = 'SELECT dte_xml, dte_folio, proveedor FROM facturas WHERE id = $1';
    const result = await pool.query(query, [factura_id]);

    if (result.rows.length === 0 || !result.rows[0].dte_xml) {
      return res.status(404).json({
        success: false,
        error: 'XML DTE no encontrado'
      });
    }

    const { dte_xml, dte_folio, proveedor } = result.rows[0];
    const filename = `DTE_${dte_folio}_${proveedor.replace(/[^a-zA-Z0-9]/g, '_')}.xml`;

    res.setHeader('Content-Type', 'application/xml');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.send(dte_xml);

  } catch (error) {
    console.error('Error descargando XML:', error);
    res.status(500).json({
      success: false,
      error: 'Error descargando XML'
    });
  }
});

// Listar DTEs generados con filtros
router.get('/listar-dtes', authMiddleware, async (req, res) => {
  try {
    const {
      page = 1,
      limit = 50,
      tipo_dte,
      estado_sii,
      fecha_desde,
      fecha_hasta
    } = req.query;

    const offset = (page - 1) * limit;
    let whereConditions = ['f.dte_folio IS NOT NULL'];
    let queryParams = [];
    let paramIndex = 1;

    // Filtros opcionales
    if (tipo_dte) {
      whereConditions.push(`f.dte_tipo = $${paramIndex++}`);
      queryParams.push(tipo_dte);
    }

    if (estado_sii) {
      whereConditions.push(`ds.estado_sii = $${paramIndex++}`);
      queryParams.push(estado_sii);
    }

    if (fecha_desde) {
      whereConditions.push(`f.fecha_factura >= $${paramIndex++}`);
      queryParams.push(fecha_desde);
    }

    if (fecha_hasta) {
      whereConditions.push(`f.fecha_factura <= $${paramIndex++}`);
      queryParams.push(fecha_hasta);
    }

    const whereClause = whereConditions.join(' AND ');

    // Query para contar total
    const countQuery = `
            SELECT COUNT(DISTINCT f.id)
            FROM facturas f
            LEFT JOIN dte_seguimiento ds ON f.id = ds.factura_id
            WHERE ${whereClause}
        `;

    // Query principal
    const dataQuery = `
            SELECT DISTINCT ON (f.id)
                f.id, f.fecha_factura, f.proveedor, f.importe, f.moneda,
                f.dte_folio, f.dte_tipo, f.dte_fecha_envio, f.dte_estado,
                ds.estado_sii, ds.glosa_sii, ds.track_id,
                CASE 
                    WHEN f.dte_tipo = 33 THEN 'Factura Electrónica'
                    WHEN f.dte_tipo = 39 THEN 'Boleta Electrónica'
                    WHEN f.dte_tipo = 52 THEN 'Guía de Despacho'
                    WHEN f.dte_tipo = 56 THEN 'Nota de Débito'
                    WHEN f.dte_tipo = 61 THEN 'Nota de Crédito'
                    ELSE 'Tipo Desconocido'
                END as tipo_dte_nombre
            FROM facturas f
            LEFT JOIN dte_seguimiento ds ON f.id = ds.factura_id
            WHERE ${whereClause}
            ORDER BY f.id DESC, ds.fecha_creacion DESC
            LIMIT $${paramIndex++} OFFSET $${paramIndex++}
        `;

    queryParams.push(limit, offset);

    const [countResult, dataResult] = await Promise.all([
      pool.query(countQuery, queryParams.slice(0, -2)),
      pool.query(dataQuery, queryParams)
    ]);

    const totalRegistros = parseInt(countResult.rows[0].count);
    const totalPaginas = Math.ceil(totalRegistros / limit);

    res.json({
      success: true,
      data: dataResult.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalRegistros,
        pages: totalPaginas
      }
    });

  } catch (error) {
    console.error('Error listando DTEs:', error);
    res.status(500).json({
      success: false,
      error: 'Error obteniendo lista de DTEs'
    });
  }
});

// Reenviar DTE al SII
router.post('/reenviar-dte/:factura_id', authMiddleware, async (req, res) => {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const { factura_id } = req.params;

    // Obtener datos del DTE
    const query = `
            SELECT f.*, ds.intentos_envio
            FROM facturas f
            LEFT JOIN dte_seguimiento ds ON f.id = ds.factura_id
            WHERE f.id = $1 AND f.dte_folio IS NOT NULL
        `;

    const result = await client.query(query, [factura_id]);

    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        success: false,
        error: 'DTE no encontrado o no generado'
      });
    }

    const factura = result.rows[0];
    const intentosActuales = factura.intentos_envio || 0;

    if (intentosActuales >= 3) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        error: 'Máximo número de intentos alcanzado (3)'
      });
    }

    // Simular reenvío
    const resultadoReenvio = await simularReenvioSII(factura);

    // Actualizar seguimiento
    await client.query(`
            UPDATE dte_seguimiento 
            SET intentos_envio = intentos_envio + 1,
                estado_sii = $1,
                glosa_sii = $2,
                fecha_respuesta_sii = NOW()
            WHERE factura_id = $3
        `, [resultadoReenvio.estado_sii, resultadoReenvio.glosa_sii, factura_id]);

    await client.query('COMMIT');

    res.json({
      success: true,
      message: 'DTE reenviado correctamente',
      data: resultadoReenvio
    });

  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error reenviando DTE:', error);
    res.status(500).json({
      success: false,
      error: 'Error reenviando DTE'
    });
  } finally {
    client.release();
  }
});

// Dashboard de estadísticas DTE
router.get('/dashboard-stats', authMiddleware, async (req, res) => {
  try {
    const statsQuery = `
            WITH estadisticas_dte AS (
                SELECT 
                    COUNT(*) as total_dtes,
                    COUNT(CASE WHEN ds.estado_sii = 'ACEPTADO_SIMULACION' THEN 1 END) as aceptados,
                    COUNT(CASE WHEN ds.estado_sii = 'RECHAZADO' THEN 1 END) as rechazados,
                    COUNT(CASE WHEN ds.estado_sii IS NULL THEN 1 END) as pendientes,
                    SUM(f.importe) as monto_total_dtes,
                    COUNT(CASE WHEN f.dte_tipo = 33 THEN 1 END) as facturas_electronicas,
                    COUNT(CASE WHEN f.dte_tipo = 39 THEN 1 END) as boletas_electronicas
                FROM facturas f
                LEFT JOIN dte_seguimiento ds ON f.id = ds.factura_id
                WHERE f.dte_folio IS NOT NULL
                AND f.fecha_factura >= DATE_TRUNC('month', CURRENT_DATE)
            ),
            stats_mensuales AS (
                SELECT 
                    DATE_TRUNC('day', f.fecha_factura) as fecha,
                    COUNT(*) as dtes_dia,
                    SUM(f.importe) as monto_dia
                FROM facturas f
                WHERE f.dte_folio IS NOT NULL
                AND f.fecha_factura >= DATE_TRUNC('month', CURRENT_DATE)
                GROUP BY DATE_TRUNC('day', f.fecha_factura)
                ORDER BY fecha
            )
            SELECT 
                ed.*,
                json_agg(
                    json_build_object(
                        'fecha', sm.fecha,
                        'dtes', sm.dtes_dia,
                        'monto', sm.monto_dia
                    ) ORDER BY sm.fecha
                ) as estadisticas_diarias
            FROM estadisticas_dte ed
            CROSS JOIN stats_mensuales sm
            GROUP BY ed.total_dtes, ed.aceptados, ed.rechazados, ed.pendientes, 
                     ed.monto_total_dtes, ed.facturas_electronicas, ed.boletas_electronicas
        `;

    const result = await pool.query(statsQuery);

    res.json({
      success: true,
      data: result.rows[0] || {
        total_dtes: 0,
        aceptados: 0,
        rechazados: 0,
        pendientes: 0,
        monto_total_dtes: 0,
        facturas_electronicas: 0,
        boletas_electronicas: 0,
        estadisticas_diarias: []
      }
    });

  } catch (error) {
    console.error('Error obteniendo estadísticas:', error);
    res.status(500).json({
      success: false,
      error: 'Error obteniendo estadísticas'
    });
  }
});

// ===== FUNCIONES DE SIMULACIÓN SII =====

async function simularConsultaEstadoSII(trackId) {
  // Simular consulta al SII
  await new Promise(resolve => setTimeout(resolve, 500));

  const estados = ['ACEPTADO', 'RECHAZADO', 'PENDIENTE', 'EN_PROCESO'];
  const estado = estados[Math.floor(Math.random() * estados.length)];

  const glosas = {
    'ACEPTADO': 'DTE Aceptado por SII',
    'RECHAZADO': 'DTE Rechazado - Error en datos',
    'PENDIENTE': 'DTE en cola de procesamiento',
    'EN_PROCESO': 'DTE siendo procesado por SII'
  };

  return {
    estado: estado,
    glosa: glosas[estado],
    fecha_consulta: new Date().toISOString()
  };
}

async function simularReenvioSII(factura) {
  await new Promise(resolve => setTimeout(resolve, 1000));

  return {
    success: true,
    estado_sii: 'ACEPTADO_REENVIO',
    glosa_sii: 'DTE reenviado y aceptado (simulación)',
    track_id: `REENVIO_${Date.now()}_${factura.dte_folio}`,
    fecha_reenvio: new Date().toISOString()
  };
}

// ===== CONFIGURACIÓN DE EMPRESA =====

// Obtener configuración actual
router.get('/configuracion-empresa', authMiddleware, async (req, res) => {
  try {
    const query = 'SELECT * FROM sii_configuracion WHERE activo = true ORDER BY id DESC LIMIT 1';
    const result = await pool.query(query);

    res.json({
      success: true,
      data: result.rows[0] || null
    });

  } catch (error) {
    console.error('Error obteniendo configuración:', error);
    res.status(500).json({
      success: false,
      error: 'Error obteniendo configuración'
    });
  }
});

// Actualizar configuración de empresa
router.put('/configuracion-empresa', authMiddleware, async (req, res) => {
  try {
    const {
      rut_empresa, nombre_empresa, giro_empresa, actividad_economica,
      direccion, comuna, ciudad, telefono, email, ambiente
    } = req.body;

    // Validaciones básicas
    if (!rut_empresa || !nombre_empresa || !giro_empresa) {
      return res.status(400).json({
        success: false,
        error: 'RUT, nombre y giro de empresa son obligatorios'
      });
    }

    const query = `
      INSERT INTO sii_configuracion (
        rut_empresa, nombre_empresa, giro_empresa, actividad_economica,
        direccion, comuna, ciudad, telefono, email, ambiente, fecha_actualizacion, activo
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), true)
      ON CONFLICT (rut_empresa)
      DO UPDATE SET
        nombre_empresa = EXCLUDED.nombre_empresa,
        giro_empresa = EXCLUDED.giro_empresa,
        actividad_economica = EXCLUDED.actividad_economica,
        direccion = EXCLUDED.direccion,
        comuna = EXCLUDED.comuna,
        ciudad = EXCLUDED.ciudad,
        telefono = EXCLUDED.telefono,
        email = EXCLUDED.email,
        ambiente = EXCLUDED.ambiente,
        fecha_actualizacion = NOW(),
        activo = true
      RETURNING *
    `;

    const result = await pool.query(query, [
      rut_empresa, nombre_empresa, giro_empresa, actividad_economica || null,
      direccion || null, comuna || null, ciudad || null, telefono || null,
      email || null, ambiente || 'certificacion'
    ]);

    res.json({
      success: true,
      message: 'Configuración actualizada correctamente',
      data: result.rows[0]
    });

  } catch (error) {
    console.error('Error actualizando configuración:', error);
    res.status(500).json({
      success: false,
      error: 'Error actualizando configuración'
    });
  }
});

module.exports = router;