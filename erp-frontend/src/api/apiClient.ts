import axios from 'axios';

const apiClient = axios.create({
    baseURL: 'http://localhost:5002/api',
    headers: {
        'Content-Type': 'application/json',
    },
});

apiClient.interceptors.request.use(
    (config) => {
        const token = localStorage.getItem('token');
        if (token) {
            config.headers.Authorization = `Bearer ${token}`;
        }
        return config;
    },
    (error) => Promise.reject(error)
);

apiClient.interceptors.response.use(
    (response) => response,
    (error) => {
        if (error.response?.status === 401) {
            localStorage.removeItem('token');
            localStorage.removeItem('user');
            window.location.href = '/login';
        }
        return Promise.reject(error);
    }
);

export interface InvoiceItem {
    id?: number;
    producto_insumo: string;
    categoria: string;
    unidad_medida: string;
    cantidad: number;
    precio_unitario: number;
    valor_afecto: number;
    valor_inafecto: number;
    impuestos: number;
    total: number;
}

export interface Invoice {
    id?: number;
    fecha_factura: string;
    serie?: string;
    numero?: string;
    ruc?: string;
    proveedor: string;
    valor_afecto: number;
    valor_inafecto: number;
    impuestos: number;
    importe: number;
    moneda: string;
    archivo_original?: string;
    estado?: string;
    dte_folio?: string;
    dte_tipo?: number;
    dte_estado?: string;
    items: InvoiceItem[];
}

export interface SIIConfig {
    id?: number;
    rut_empresa: string;
    nombre_empresa: string;
    giro_empresa: string;
    actividad_economica: string;
    direccion: string;
    comuna: string;
    ciudad: string;
    telefono: string;
    email: string;
    ambiente: 'certificacion' | 'produccion';
}

export const login = async (data: { email: string; password: string }) => {
    const response = await apiClient.post('/auth/login', data);
    return response.data;
};

export const getFacturas = async (
    page: number = 1,
    limit: number = 50,
    filters: { estado?: string; tipo_dte?: string; fecha_inicio?: string; fecha_fin?: string } = {}
) => {
    const response = await apiClient.get('/facturas/listar', {
        params: { page, limit, ...filters },
    });
    return response.data;
};

export const postOCR = async (files: File[]) => {
    const formData = new FormData();
    files.forEach((file) => formData.append('files', file));
    const response = await apiClient.post('/facturas/ocr', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
    });
    return response.data;
};

export const saveInvoice = async (invoice: Invoice) => {
    const response = await apiClient.post('/facturas/guardar', invoice);
    return response.data;
};

export const deleteInvoice = async (id: number) => {
    const response = await apiClient.delete(`/facturas/${id}`);
    return response.data;
};

export const generateDTE = async (factura_id: number, tipo_dte: number) => {
    const response = await apiClient.post('/sii/generar-dte', { factura_id, tipo_dte });
    return response.data;
};

export const getSIIConfig = async () => {
    const response = await apiClient.get('/sii/configuracion-empresa');
    return response.data;
};

export const updateSIIConfig = async (config: SIIConfig) => {
    const response = await apiClient.put('/sii/configuracion-empresa', config);
    return response.data;
};

export const getDashboardStats = async () => {
    const response = await apiClient.get('/sii/dashboard-stats');
    return response.data;
};

export default apiClient;