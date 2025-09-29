import { Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ToastContainer } from 'react-toastify';
import 'react-toastify/dist/ReactToastify.css';
import { AuthProvider } from './features/auth/AuthContext';
import ErrorBoundary from './components/ErrorBoundary';
import LoginPage from './pages/LoginPage';
import FacturasPage from './pages/FacturasPage';
import ConfiguracionSIIPage from './pages/ConfiguracionSIIPage';
import Layout from './components/Layout';

const queryClient = new QueryClient();

function App() {
  const isAuthenticated = !!localStorage.getItem('token');

  return (
    <ErrorBoundary>
      <AuthProvider>
        <QueryClientProvider client={queryClient}>
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route
              element={isAuthenticated ? <Layout /> : <Navigate to="/login" replace />}
            >
              <Route path="/facturas" element={<FacturasPage />} />
              <Route path="/configuracion-sii" element={<ConfiguracionSIIPage />} />
            </Route>
            <Route path="*" element={<Navigate to={isAuthenticated ? "/facturas" : "/login"} replace />} />
          </Routes>
          <ToastContainer position="top-right" autoClose={3000} />
        </QueryClientProvider>
      </AuthProvider>
    </ErrorBoundary>
  );
}

export default App;