import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { toast } from 'react-toastify';
import { getSIIConfig, updateSIIConfig } from '../api/apiClient';
import { SIIConfig } from '../api/apiClient';

const siiConfigSchema = z.object({
    rut_empresa: z.string().min(1, 'RUT es obligatorio'),
    nombre_empresa: z.string().min(1, 'Nombre es obligatorio'),
    giro_empresa: z.string().optional(),
    actividad_economica: z.string().optional(),
    direccion: z.string().optional(),
    comuna: z.string().optional(),
    ciudad: z.string().optional(),
    telefono: z.string().optional(),
    email: z.string().email('Correo no válido').optional().or(z.literal('')),
    ambiente: z.enum(['certificacion', 'produccion']),
});

type SIIConfigFormData = z.infer<typeof siiConfigSchema>;

function ConfiguracionSIIPage() {
    const queryClient = useQueryClient();
    const { data, isLoading } = useQuery({
        queryKey: ['siiConfig'],
        queryFn: getSIIConfig,
    });

    const mutation = useMutation({
        mutationFn: updateSIIConfig,
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['siiConfig'] });
            toast.success('Configuración guardada correctamente');
        },
        onError: () => toast.error('Error al guardar configuración'),
    });

    const { register, handleSubmit, reset, formState: { errors, isSubmitting } } = useForm<SIIConfigFormData>({
        resolver: zodResolver(siiConfigSchema),
        defaultValues: data?.data || { ambiente: 'certificacion' },
    });

    const onSubmit = (formData: SIIConfigFormData) => {
        mutation.mutate(formData);
    };

    if (isLoading) return <div className="custom-spinner mx-auto mt-10"></div>;

    return (
        <div className="max-w-2xl mx-auto">
            <h2 className="text-2xl font-bold mb-6">Configuración SII</h2>
            <form onSubmit={handleSubmit(onSubmit)} className="space-y-4 bg-white p-6 rounded-lg shadow-md">
                <div>
                    <label className="block text-sm font-medium text-gray-700">RUT Empresa</label>
                    <input
                        {...register('rut_empresa')}
                        className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.rut_empresa ? 'border-red-500' : ''}`}
                    />
                    {errors.rut_empresa && <p className="mt-1 text-sm text-red-600">{errors.rut_empresa.message}</p>}
                </div>
                <div>
                    <label className="block text-sm font-medium text-gray-700">Nombre Empresa</label>
                    <input
                        {...register('nombre_empresa')}
                        className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.nombre_empresa ? 'border-red-500' : ''}`}
                    />
                    {errors.nombre_empresa && <p className="mt-1 text-sm text-red-600">{errors.nombre_empresa.message}</p>}
                </div>
                <div>
                    <label className="block text-sm font-medium text-gray-700">Giro Comercial</label>
                    <input
                        {...register('giro_empresa')}
                        className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                    />
                </div>
                <div>
                    <label className="block text-sm font-medium text-gray-700">Actividad Económica</label>
                    <input
                        {...register('actividad_economica')}
                        className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                    />
                </div>
                <div>
                    <label className="block text-sm font-medium text-gray-700">Dirección</label>
                    <input
                        {...register('direccion')}
                        className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                    />
                </div>
                <div>
                    <label className="block text-sm font-medium text-gray-700">Comuna</label>
                    <input
                        {...register('comuna')}
                        className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                    />
                </div>
                <div>
                    <label className="block text-sm font-medium text-gray-700">Teléfono</label>
                    <input
                        {...register('telefono')}
                        className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                    />
                </div>
                <div>
                    <label className="block text-sm font-medium text-gray-700">Email</label>
                    <input
                        {...register('email')}
                        className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.email ? 'border-red-500' : ''}`}
                    />
                    {errors.email && <p className="mt-1 text-sm text-red-600">{errors.email.message}</p>}
                </div>
                <div>
                    <label className="block text-sm font-medium text-gray-700">Ambiente</label>
                    <select
                        {...register('ambiente')}
                        className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                    >
                        <option value="certificacion">Certificación</option>
                        <option value="produccion">Producción</option>
                    </select>
                </div>
                <div className="flex justify-end space-x-4">
                    <button
                        type="button"
                        onClick={() => reset()}
                        className="px-4 py-2 bg-gray-300 text-gray-700 rounded hover:bg-gray-400"
                    >
                        Cancelar
                    </button>
                    <button
                        type="submit"
                        disabled={isSubmitting}
                        className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:bg-blue-400"
                    >
                        {isSubmitting ? 'Guardando...' : 'Guardar Configuración'}
                    </button>
                </div>
            </form>
        </div>
    );
}

export default ConfiguracionSIIPage;