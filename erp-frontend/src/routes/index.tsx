import { createBrowserRouter } from 'react-router-dom';
import Layout from '../components/Layout';
import LoginPage from '../pages/LoginPage';
import FacturasPage from '../pages/FacturasPage';
import ConfiguracionSIIPage from '../pages/ConfiguracionSIIPage';
import PrivateRoute from '../components/PrivateRoute';

const router = createBrowserRouter([
    {
        path: '/',
        element: <Layout />,
        children: [
            {
                path: 'login',
                element: <LoginPage />,
            },
            {
                path: 'facturas',
                element: (
                    <PrivateRoute>
                        <FacturasPage />
                    </PrivateRoute>
                ),
            },
            {
                path: 'configuracion-sii',
                element: (
                    <PrivateRoute>
                        <ConfiguracionSIIPage />
                    </PrivateRoute>
                ),
            },
        ],
    },
]);

export default router;