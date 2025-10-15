Módulo Facturas - ERP
El Módulo Facturas es un sistema ERP minimalista para gestionar facturas electrónicas, integrado con un backend simulado para el Servicio de Impuestos Internos (SII). Este proyecto es un Producto Mínimo Viable (MVP) que incluye autenticación, listado de facturas, carga de facturas con OCR, y configuración SII. Está construido con tecnologías modernas para frontend y backend, asegurando escalabilidad y mantenibilidad.
Características
Frontend

Tecnologías: React, TypeScript, Vite, TailwindCSS, React Query, React Hook Form, Zod, React Toastify.
Autenticación: Formulario de login/logout con validación (email, contraseña) y protección de rutas.
Listado de facturas: Tabla dinámica con filtros (estado, tipo DTE, fechas), paginación, y exportación a CSV.
Carga de facturas: Componente drag-and-drop para subir PDF/JPG con OCR simulado y vista previa.
Configuración SII: Formulario para gestionar datos de la empresa (RUT, nombre, ambiente).
Generación DTE: Botones para generar DTEs simulados con confirmación vía modal.
UX: Layout responsivo con navbar (escritorio) y sidebar (móvil), notificaciones, y estados de carga.

Backend

Tecnologías: Node.js, Express, PostgreSQL, JWT, Bcryptjs.
Endpoints:
POST /api/auth/login: Autenticación con JWT.
GET /api/facturas/listar: Lista facturas con filtros y paginación.
POST /api/facturas/ocr: Procesa archivos con OCR simulado.
DELETE /api/facturas/:id: Elimina facturas.
POST /api/sii/generar-dte: Simula generación de DTE.
GET/PUT /api/sii/configuracion-empresa: Gestiona configuración SII.
Otros: /consultar-estado, /descargar-xml, /listar-dtes, /reenviar-dte.


Seguridad: Contraseñas hasheadas, autenticación con JWT.

Requisitos previos

Node.js: v18 o superior.
PostgreSQL: v13 o superior.
NPM: v8 o superior.
Puertos libres: 6000 (frontend), 5002 (backend).

Instalación
1. Clonar el repositorio
git clone https://github.com/<tu-usuario>/modulo-facturas.git
cd modulo-facturas

2. Configurar el backend

Navega al directorio del backend:cd erp-backend


Instala dependencias:npm install


Configura la base de datos PostgreSQL:
Crea una base de datos erp_db.
Ejecuta el esquema SQL (erp-backend/db/schema.sql):CREATE TABLE usuarios (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,
  rol VARCHAR(50) NOT NULL,
  id_negocio INTEGER NOT NULL
);
CREATE TABLE facturas (
  id SERIAL PRIMARY KEY,
  proveedor VARCHAR(255),
  fecha DATE,
  importe DECIMAL(10,2),
  estado VARCHAR(50),
  id_negocio INTEGER
);
CREATE TABLE sii_config (
  id SERIAL PRIMARY KEY,
  rut_empresa VARCHAR(20),
  nombre_empresa VARCHAR(255),
  ambiente VARCHAR(20),
  id_negocio INTEGER
);




Crea un archivo .env en erp-backend:PORT=5002
JWT_SECRET=your-secret-key
PGHOST=localhost
PGUSER=postgres
PGDATABASE=erp_db
PGPASSWORD=your_password
PGPORT=5432


Inicia el backend:node server.js



3. Configurar el frontend

Navega al directorio del frontend:cd erp-frontend


Instala dependencias:npm install


Inicia el frontend:npm run dev


Accede en http://localhost:6000.



4. Configuración adicional

Asegúrate de que no haya procesos usando los puertos 6000 o 5002:lsof -i :6000
lsof -i :5002
kill -9 <PID>


Limpia localStorage en el navegador para evitar conflictos con otros proyectos.

Uso

Abre http://localhost:6000/login.
Inicia sesión con las credenciales de prueba:
Email: test@erp.com
Contraseña: password123


Navega por las secciones:
Facturas: /facturas (listado, filtros, carga de archivos, generación DTE).
Configuración SII: /configuracion-sii (gestionar datos de la empresa).



Estructura del proyecto
modulo-facturas/
├── erp-backend/
│   ├── db/
│   │   └── schema.sql
│   ├── routes/
│   │   ├── authRoutes.js
│   │   ├── facturasRoutes.js
│   │   └── siiRoutes.js
│   ├── .env
│   └── server.js
├── erp-frontend/
│   ├── src/
│   │   ├── api/
│   │   │   └── apiClient.ts
│   │   ├── components/
│   │   │   ├── Layout.tsx
│   │   │   └── FileUpload.tsx
│   │   ├── features/
│   │   │   └── auth/
│   │   │       ├── AuthContext.tsx
│   │   │       └── useAuth.ts
│   │   ├── pages/
│   │   │   ├── LoginPage.tsx
│   │   │   ├── FacturasPage.tsx
│   │   │   └── ConfiguracionSIIPage.tsx
│   │   ├── hooks/
│   │   ├── routes/
│   │   ├── App.tsx
│   │   └── main.tsx
│   ├── vite.config.ts
│   └── package.json
└── README.md

Limitaciones

Integración SII: Simulada, no conectada con la API oficial de SII.
Seguridad: Tokens almacenados en localStorage (vulnerable a XSS).
Tests: No implementados (pendiente Etapa 6).
Despliegue: Sin configuración para producción (pendiente Etapa 7).
Módulo "menu": Puede causar conflictos si usa localhost:3000 o claves similares en localStorage.

Mejoras futuras

Configurar ESLint, Prettier, y tests con Vitest (Etapa 6).
Implementar HttpOnly cookies para tokens.
Integrar API real de SII.
Añadir animaciones con framer-motion y error boundaries.
Desplegar con Docker (frontend en Vercel/S3, backend en Heroku/AWS).

Contribuir

Haz un fork del repositorio.
Crea una rama (git checkout -b feature/nueva-funcionalidad).
Realiza tus cambios y haz commit (git commit -m "Añadir nueva funcionalidad").
Sube los cambios (git push origin feature/nueva-funcionalidad).
Abre un Pull Request.

Licencia
MIT License




=======================================================================================


Etapa 1 – Preparación del proyecto:

Completado: Proyecto creado con Vite + React + TypeScript, TailwindCSS configurado, dependencias clave instaladas (react-router-dom, @tanstack/react-query, react-hook-form, zod, react-toastify), y estructura de carpetas implementada (src/api, src/components, src/features, etc.).
Estado: Listo, asumiendo que la estructura de carpetas coincide con la guía.


Etapa 2 – Base de la aplicación:

Completado: Rutas configuradas (/login, /facturas, /configuracion-sii), layout principal con Sidebar y Navbar, y protección de rutas (redirige a /login si no hay token).
Estado: Funcional, ya que el login redirige a /facturas y la navegación entre pestañas trabaja.


Etapa 3 – API y manejo de estado:

Completado: React Query configurado, funciones en src/api/apiClient.ts para login, facturas, y configuración SII. Autenticación con token en localStorage.
Estado: Operativo, con respuestas HTTP 304 (caché) indicando que las solicitudes al backend funcionan.


Etapa 4 – Features principales:

4.1 Autenticación: Login funcional con formulario (react-hook-form) y redirección a /facturas.
4.2 Facturas: Tabla de facturas con columnas (ID, proveedor, fecha, importe, estado) y paginación (asumiendo que /facturas muestra datos o un mensaje si está vacío).
4.3 Configuración SII: Formulario para guardar configuración vía PUT /api/sii/configuracion-empresa, con notificaciones.
4.4 Upload Facturas: Componente FileUpload para subir archivos (PDF/JPG) a /api/facturas/ocr, con vista previa (asumiendo que está implementado, ya que no reportaste errores).
Estado: Completo para un MVP, aunque falta confirmar si FileUpload y la tabla de facturas muestran datos correctamente.


Etapa 5 – UX y feedback:

Parcialmente completado: react-toastify implementado para notificaciones en LoginPage.tsx. Probablemente también en FacturasPage.tsx y ConfiguracionSIIPage.tsx, pero falta confirmar si los estados de carga (isLoading) y errores centralizados (e.g., logout automático si el token expira) están implementados.
Pendiente: Asegurar spinners de carga en FacturasPage.tsx y ConfiguracionSIIPage.tsx, y manejo de errores como token expirado.


Etapa 6 – Calidad y mantenibilidad:

Pendiente: Error de ESLint (react-refresh/only-export-components) en AuthContext.tsx indica que useAuth no está completamente separado en useAuth.ts. Configuración de ESLint, Prettier, alias de imports, y tests con Vitest no están implementados.
Estado: No crítico para un MVP, pero necesario para un producto más robusto.


Etapa 7 – Deploy inicial:

Pendiente: No hay evidencia de un Dockerfile o deploy en staging (e.g., S3+CloudFront o backend Express).
Estado: No necesario para un MVP, pero importante para producción.
