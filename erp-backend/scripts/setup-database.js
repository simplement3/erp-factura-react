const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
    user: process.env.DB_USER,
    host: process.env.DB_HOST,
    database: process.env.DB_NAME,
    password: process.env.DB_PASSWORD,
    port: process.env.DB_PORT,
});

async function setupDatabase() {
    try {
        // Crear tabla de facturas (existente)
        await pool.query(`
      CREATE TABLE IF NOT EXISTS facturas (
        id SERIAL PRIMARY KEY,
        fecha_factura DATE NOT NULL,
        serie VARCHAR(50),
        numero VARCHAR(50),
        ruc VARCHAR(50),
        proveedor TEXT NOT NULL,
        valor_afecto DECIMAL(15,2) NOT NULL,
        valor_inafecto DECIMAL(15,2) NOT NULL,
        impuestos DECIMAL(15,2) NOT NULL,
        importe DECIMAL(15,2) NOT NULL,
        moneda VARCHAR(10) NOT NULL,
        archivo_original TEXT,
        estado VARCHAR(50),
        dte_folio VARCHAR(50),
        dte_tipo INTEGER,
        dte_estado VARCHAR(50),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

        // Crear tabla de ítems de facturas (existente)
        await pool.query(`
      CREATE TABLE IF NOT EXISTS factura_items (
        id SERIAL PRIMARY KEY,
        factura_id INTEGER REFERENCES facturas(id) ON DELETE CASCADE,
        producto_insumo TEXT NOT NULL,
        categoria VARCHAR(100),
        unidad_medida VARCHAR(50),
        cantidad DECIMAL(10,2) NOT NULL,
        precio_unitario DECIMAL(15,2) NOT NULL,
        valor_afecto DECIMAL(15,2) NOT NULL,
        valor_inafecto DECIMAL(15,2) NOT NULL,
        impuestos DECIMAL(15,2) NOT NULL,
        total DECIMAL(15,2) NOT NULL
      )
    `);

        // Crear tabla de configuración SII (existente)
        await pool.query(`
      CREATE TABLE IF NOT EXISTS sii_config (
        id SERIAL PRIMARY KEY,
        rut_empresa VARCHAR(20) NOT NULL,
        nombre_empresa TEXT NOT NULL,
        giro_empresa TEXT,
        actividad_economica TEXT,
        direccion TEXT,
        comuna TEXT,
        ciudad TEXT,
        telefono VARCHAR(20),
        email VARCHAR(100),
        ambiente VARCHAR(20) NOT NULL
      )
    `);

        // Nueva tabla de usuarios
        await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        email VARCHAR(100) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

        // Insertar usuario de prueba (contraseña: 'password123')
        await pool.query(`
      INSERT INTO users (email, password)
      VALUES ('test@erp.com', '$2b$10$7gX9jK3sZ7Y8vZ5nX9Y0.u9Z2b7p8qK3sZ7Y8vZ5nX9Y0u9Z2b7p')
      ON CONFLICT (email) DO NOTHING
    `);

        console.log('Base de datos configurada correctamente');
    } catch (error) {
        console.error('Error al configurar la base de datos:', error);
    } finally {
        await pool.end();
    }
}

setupDatabase();