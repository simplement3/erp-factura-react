import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../features/auth/useAuth';
import { toast } from 'react-toastify';
import { login } from '../api/apiClient';

const loginSchema = z.object({
    email: z.string().email('Correo electrónico no válido'),
    password: z.string().min(6, 'La contraseña debe tener al menos 6 caracteres'),
});

type LoginFormData = z.infer<typeof loginSchema>;

function LoginPage() {
    const navigate = useNavigate();
    const { login: authLogin } = useAuth();
    const {
        register,
        handleSubmit,
        formState: { errors, isSubmitting },
    } = useForm<LoginFormData>({
        resolver: zodResolver(loginSchema),
    });

    const onSubmit = async (data: LoginFormData) => {
        try {
            const response = await login(data);
            if (response.success) {
                // Verificar que response.user tenga la estructura correcta
                const user = {
                    id: response.user.id,
                    email: response.user.email,
                    rol: response.user.rol,
                    id_negocio: response.user.id_negocio,
                };
                authLogin(response.token, user);
                toast.success('Inicio de sesión exitoso');
                navigate('/facturas');
            } else {
                toast.error(response.error || 'Error al iniciar sesión');
            }
        } catch (error) {
            console.error('Error en login:', error);
            toast.error('Error al iniciar sesión');
        }
    };

    return (
        <div className="max-w-md mx-auto mt-10 p-6 bg-white rounded-lg shadow-xl">
            <h2 className="text-2xl font-bold text-center mb-6">Iniciar Sesión</h2>
            <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
                <div>
                    <label htmlFor="email" className="block text-sm font-medium text-gray-700">
                        Correo Electrónico
                    </label>
                    <input
                        id="email"
                        type="email"
                        {...register('email')}
                        className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.email ? 'border-red-500' : ''}`}
                    />
                    {errors.email && (
                        <p className="mt-1 text-sm text-red-600">{errors.email.message}</p>
                    )}
                </div>
                <div>
                    <label htmlFor="password" className="block text-sm font-medium text-gray-700">
                        Contraseña
                    </label>
                    <input
                        id="password"
                        type="password"
                        {...register('password')}
                        className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.password ? 'border-red-500' : ''}`}
                    />
                    {errors.password && (
                        <p className="mt-1 text-sm text-red-600">{errors.password.message}</p>
                    )}
                </div>
                <button
                    type="submit"
                    disabled={isSubmitting}
                    className="w-full bg-blue-600 text-white py-2 px-4 rounded-md hover:bg-blue-700 disabled:bg-blue-400 transition-colors"
                >
                    {isSubmitting ? 'Iniciando...' : 'Iniciar Sesión'}
                </button>
            </form>
        </div>
    );
}

export default LoginPage;