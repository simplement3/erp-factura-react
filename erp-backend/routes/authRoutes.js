const express = require('express');
const bcryptjs = require('bcryptjs');
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

    console.log('Intento de login:', { email, receivedAt: new Date().toISOString() });

    try {
        if (!email || !password) {
            console.log('Faltan datos:', { email });
            return res.status(400).json({ success: false, error: 'Correo y contraseña requeridos' });
        }

        const result = await pool.query('SELECT * FROM usuarios WHERE email = $1', [email]);
        const user = result.rows[0];

        if (!user) {
            console.log('Usuario no encontrado:', email);
            return res.status(401).json({ success: false, error: 'Correo o contraseña incorrectos' });
        }

        const isPasswordValid = await bcryptjs.compare(password, user.password_hash);
        if (!isPasswordValid) {
            console.log('Contraseña no válida para:', email);
            return res.status(401).json({ success: false, error: 'Correo o contraseña incorrectos' });
        }

        if (!process.env.JWT_SECRET) {
            console.error('JWT_SECRET no configurado');
            return res.status(500).json({ success: false, error: 'Error de configuración' });
        }

        const token = jwt.sign(
            { userId: user.id, email: user.email, rol: user.rol, id_negocio: user.id_negocio },
            process.env.JWT_SECRET,
            { expiresIn: '1h' }
        );

        console.log('Login exitoso:', { email, userId: user.id });
        return res.status(200).json({
            success: true,
            token,
            user: { id: user.id, email: user.email, rol: user.rol, id_negocio: user.id_negocio },
        });
    } catch (error) {
        console.error('Error en login:', error);
        return res.status(500).json({ success: false, error: 'Error interno del servidor' });
    }
});

router.post('/register', async (req, res) => {
    const { email, password, rol, id_negocio } = req.body;

    try {
        if (!email || !password) {
            return res.status(400).json({ success: false, error: 'Correo y contraseña requeridos' });
        }

        const hashedPassword = await bcryptjs.hash(password, 10);

        await pool.query(
            'INSERT INTO usuarios (email, password_hash, rol, id_negocio, created_at) VALUES ($1, $2, $3, $4, NOW()) ON CONFLICT (email) DO UPDATE SET password_hash = $2, rol = $3',
            [email, hashedPassword, rol || 'admin', id_negocio || 1]
        );

        res.status(201).json({ success: true, message: 'Usuario registrado' });
    } catch (error) {
        console.error('Error en register:', error);
        res.status(500).json({ success: false, error: 'Error interno del servidor' });
    }
});

module.exports = router;