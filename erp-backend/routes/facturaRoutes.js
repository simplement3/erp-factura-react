const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { processInvoice } = require('../deepseekServices');
const { Pool } = require('pg');
require('dotenv').config();

const router = express.Router();
const pool = new Pool({
    user: process.env.DB_USER,
    host: process.env.DB_HOST,
    database: process.env.DB_NAME,
    password: process.env.DB_PASSWORD,
    port: process.env.DB_PORT,
});

const upload = multer({ dest: 'uploads/' });

router.post('/ocr', upload.array('files'), async (req, res) => {
    try {
        const files = req.files;
        if (!files || files.length === 0) {
            return res.status(400).json({ success: false, error: 'No se subieron archivos' });
        }

        const invoices = [];
        for (const file of files) {
            const filePath = path.join(__dirname, '..', file.path);
            const invoiceData = await processInvoice(filePath);
            invoices.push({
                ...invoiceData,
                archivo_original: file.filename,
            });
            // Opcional: eliminar archivo temporal
            // fs.unlinkSync(filePath);
        }
        res.json({ success: true, data: invoices });
    } catch (error) {
        console.error('Error en /api/facturas/ocr:', error);
        res.status(500).json({ success: false, error: 'Error al procesar archivos' });
    }
});

router.post('/guardar', async (req, res) => {
    const {
        fecha_factura, serie, numero, ruc, proveedor, valor_afecto,
        valor_inafecto, impuestos, importe, moneda, archivo_original, items
    } = req.body;

    try {
        const result = await pool.query(
            `INSERT INTO facturas (fecha_factura, serie, numero, ruc, proveedor, valor_afecto,
        valor_inafecto, impuestos, importe, moneda, archivo_original, estado)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
       RETURNING id`,
            [
                fecha_factura, serie || null, numero || null, ruc || null, proveedor,
                valor_afecto, valor_inafecto, impuestos, importe, moneda,
                archivo_original || null, 'pendiente'
            ]
        );

        const facturaId = result.rows[0].id;

        for (const item of items) {
            await pool.query(
                `INSERT INTO factura_items (factura_id, producto_insumo, categoria, unidad_medida,
          cantidad, precio_unitario, valor_afecto, valor_inafecto, impuestos, total)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
                [
                    facturaId, item.producto_insumo, item.categoria || null, item.unidad_medida || null,
                    item.cantidad, item.precio_unitario, item.valor_afecto, item.valor_inafecto,
                    item.impuestos, item.total
                ]
            );
        }

        res.json({ success: true, factura_id: facturaId });
    } catch (error) {
        console.error('Error en /api/facturas/guardar:', error);
        res.status(500).json({ success: false, error: 'Error al guardar factura' });
    }
});

router.get('/listar', async (req, res) => {
    const { page = 1, limit = 50, estado, tipo_dte, fecha_inicio, fecha_fin } = req.query;
    const offset = (page - 1) * limit;

    try {
        let whereClause = 'WHERE 1=1';
        const params = [];
        let paramIndex = 1;

        if (estado) {
            whereClause += ` AND f.dte_estado = $${paramIndex++}`;
            params.push(estado);
        }
        if (tipo_dte) {
            whereClause += ` AND f.dte_tipo = $${paramIndex++}`;
            params.push(tipo_dte);
        }
        if (fecha_inicio) {
            whereClause += ` AND f.fecha_factura >= $${paramIndex++}`;
            params.push(fecha_inicio);
        }
        if (fecha_fin) {
            whereClause += ` AND f.fecha_factura <= $${paramIndex++}`;
            params.push(fecha_fin);
        }

        const countQuery = `SELECT COUNT(*) as total FROM facturas f ${whereClause}`;
        const filterParams = [...params]; // Copia de parámetros para la consulta de conteo

        const query = `
            SELECT f.*, 
                   (SELECT json_agg(
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
                   ) FROM factura_items fi WHERE fi.factura_id = f.id) as items
            FROM facturas f
            ${whereClause}
            ORDER BY f.created_at DESC 
            LIMIT $${paramIndex++} OFFSET $${paramIndex++}
        `;
        params.push(limit, offset); // Agrega parámetros de paginación solo a la consulta principal

        const [facturasResult, countResult] = await Promise.all([
            pool.query(query, params),
            pool.query(countQuery, filterParams),
        ]);

        const facturas = facturasResult.rows;
        const total = parseInt(countResult.rows[0].total, 10);
        const pages = Math.ceil(total / limit);

        res.json({
            success: true,
            data: facturas,
            pagination: { page: parseInt(page, 10), limit: parseInt(limit, 10), total, pages },
        });
    } catch (error) {
        console.error('Error en /api/facturas/listar:', error);
        res.status(500).json({ success: false, error: 'Error al listar facturas' });
    }
});

router.delete('/:id', async (req, res) => {
    const { id } = req.params;
    try {
        await pool.query('DELETE FROM facturas WHERE id = $1', [id]);
        res.json({ success: true });
    } catch (error) {
        console.error('Error en /api/facturas/:id:', error);
        res.status(500).json({ success: false, error: 'Error al eliminar factura' });
    }
});

module.exports = router;