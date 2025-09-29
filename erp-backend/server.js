const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const facturaRoutes = require('./routes/facturaRoutes');
const siiRoutes = require('./routes/siiRoutes');
const authRoutes = require('./routes/authRoutes');
require('dotenv').config({ debug: true }); // Habilitar debug para dotenv

const app = express();

app.use(cors());
app.use(express.json());
app.use('/uploads', express.static('uploads'));

// Middleware para verificar JWT
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return res.status(401).json({ error: 'Token requerido' });
    }

    jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
        if (err) {
            return res.status(403).json({ error: 'Token inválido o expirado' });
        }
        req.user = user;
        next();
    });
};

// Rutas
app.use('/api/auth', authRoutes);
app.use('/api/facturas', authenticateToken, facturaRoutes);
app.use('/api/sii', authenticateToken, siiRoutes);

// Manejo de errores global
app.use((err, req, res, next) => {
    console.error('Error en el servidor:', err.stack);
    res.status(500).json({ success: false, error: 'Error interno del servidor' });
});

const PORT = process.env.PORT || 5002;
app.listen(PORT, () => {
    console.log(`Servidor corriendo en puerto ${PORT}`);
    // Verificar variables de entorno
    console.log('JWT_SECRET:', process.env.JWT_SECRET ? 'Configurado' : 'No configurado');
    console.log('GOOGLE_APPLICATION_CREDENTIALS:', process.env.GOOGLE_APPLICATION_CREDENTIALS || 'No configurado');
});