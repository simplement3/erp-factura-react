const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
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

router.post('/login', async (req, res) => {
    const { email, password } = req.body;

    try {
        // Validar entrada
        if (!email || !password) {
            return res.status(400).json({ success: false, error: 'Correo y contraseña son obligatorios' });
        }

        // Buscar usuario
        const result = await pool.query('SELECT * FROM usuarios WHERE email = $1', [email]);
        const user = result.rows[0];

        if (!user) {
            return res.status(401).json({ success: false, error: 'Correo o contraseña incorrectos' });
        }

        // Comparar contraseña
        const isPasswordValid = await bcrypt.compare(password, user.password_hash);
        if (!isPasswordValid) {
            return res.status(401).json({ success: false, error: 'Correo o contraseña incorrectos' });
        }

        // Generar token JWT
        const token = jwt.sign(
            { userId: user.id, email: user.email, rol: user.rol, id_negocio: user.id_negocio },
            process.env.JWT_SECRET,
            { expiresIn: '1h' }
        );

        res.json({
            success: true,
            token,
            user: { id: user.id, email: user.email, rol: user.rol, id_negocio: user.id_negocio },
        });
    } catch (error) {
        console.error('Error en login:', error);
        res.status(500).json({ success: false, error: 'Error interno del servidor' });
    }
});

module.exports = router;