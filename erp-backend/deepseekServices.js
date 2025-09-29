const vision = require('@google-cloud/vision');
const pdfParse = require('pdf-parse');
const fs = require('fs').promises;

async function processInvoice(filePath) {
    try {
        const client = new vision.ImageAnnotatorClient();
        let text;

        if (filePath.endsWith('.pdf')) {
            const data = await fs.readFile(filePath);
            const pdf = await pdfParse(data);
            text = pdf.text;
        } else {
            const [result] = await client.textDetection(filePath);
            text = result.fullTextAnnotation?.text || '';
        }

        // Simulación de extracción de datos (reemplazar con lógica real)
        const invoiceData = {
            fecha_factura: '2025-09-28',
            proveedor: text.match(/proveedor:\s*([^\n]+)/i)?.[1] || 'Proveedor Desconocido',
            valor_afecto: 100000,
            valor_inafecto: 0,
            impuestos: 19000,
            importe: 119000,
            moneda: 'CLP',
            items: [
                {
                    producto_insumo: 'Producto 1',
                    categoria: 'General',
                    unidad_medida: 'Unidad',
                    cantidad: 1,
                    precio_unitario: 100000,
                    valor_afecto: 100000,
                    valor_inafecto: 0,
                    impuestos: 19000,
                    total: 119000,
                },
            ],
        };

        return invoiceData;
    } catch (error) {
        console.error('Error en processInvoice:', error);
        throw error;
    }
}

module.exports = { processInvoice };