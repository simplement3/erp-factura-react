const jwt = require('jsonwebtoken');

const authMiddleware = (req, res, next) => {
    const token = req.headers.authorization?.split('Bearer ')[1];
    if (!token) {
        return res.status(401).json({ success: false, error: 'No se proporcionó token' });
    }

    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET || 'your_jwt_secret');
        req.user = decoded;
        next();
    } catch (error) {
        console.error('Token inválido:', error);
        return res.status(403).json({ success: false, error: 'Token inválido o expirado' });
    }
};

module.exports = authMiddleware;