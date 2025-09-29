import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { Invoice } from '../../api/apiClient';
import { XMarkIcon } from '@heroicons/react/24/solid';

const invoiceSchema = z.object({
    fecha_factura: z.string().min(1, 'Fecha es obligatoria'),
    serie: z.string().optional(),
    numero: z.string().optional(),
    ruc: z.string().optional(),
    proveedor: z.string().min(1, 'Proveedor es obligatorio'),
    valor_afecto: z.number().min(0, 'Valor afecto no válido'),
    valor_inafecto: z.number().min(0, 'Valor inafecto no válido'),
    impuestos: z.number().min(0, 'Impuestos no válidos'),
    importe: z.number().min(0, 'Importe no válido'),
    moneda: z.string().min(1, 'Moneda es obligatoria'),
    items: z.array(
        z.object({
            producto_insumo: z.string().min(1, 'Producto es obligatorio'),
            categoria: z.string().optional(),
            unidad_medida: z.string().optional(),
            cantidad: z.number().min(0, 'Cantidad no válida'),
            precio_unitario: z.number().min(0, 'Precio unitario no válido'),
            valor_afecto: z.number().min(0, 'Valor afecto no válido'),
            valor_inafecto: z.number().min(0, 'Valor inafecto no válido'),
            impuestos: z.number().min(0, 'Impuestos no válidos'),
            total: z.number().min(0, 'Total no válido'),
        })
    ),
});

type InvoiceFormData = z.infer<typeof invoiceSchema>;

interface InvoicePreviewModalProps {
    invoices: Invoice[];
    onSave: (invoice: Invoice) => void;
    onClose: () => void;
}

function InvoicePreviewModal({ invoices, onSave, onClose }: InvoicePreviewModalProps) {
    const [currentInvoiceIndex, setCurrentInvoiceIndex] = useState(0);
    const currentInvoice = invoices[currentInvoiceIndex];

    const { register, handleSubmit, formState: { errors } } = useForm<InvoiceFormData>({
        resolver: zodResolver(invoiceSchema),
        defaultValues: currentInvoice,
    });

    const onSubmit = (data: InvoiceFormData) => {
        onSave(data);
        if (currentInvoiceIndex < invoices.length - 1) {
            setCurrentInvoiceIndex(currentInvoiceIndex + 1);
        } else {
            onClose();
        }
    };

    return (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center z-50">
            <div className="bg-white rounded-lg p-6 w-full max-w-3xl max-h-[80vh] overflow-y-auto">
                <div className="flex justify-between items-center mb-4">
                    <h3 className="text-lg font-bold">Revisar Factura {currentInvoiceIndex + 1} de {invoices.length}</h3>
                    <button onClick={onClose} className="text-gray-600 hover:text-gray-800">
                        <XMarkIcon className="w-6 h-6" />
                    </button>
                </div>
                <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div>
                            <label className="block text-sm font-medium text-gray-700">Fecha Factura</label>
                            <input
                                type="date"
                                {...register('fecha_factura')}
                                className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.fecha_factura ? 'border-red-500' : ''}`}
                            />
                            {errors.fecha_factura && <p className="mt-1 text-sm text-red-600">{errors.fecha_factura.message}</p>}
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-700">Serie</label>
                            <input
                                {...register('serie')}
                                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                            />
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-700">Número</label>
                            <input
                                {...register('numero')}
                                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                            />
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-700">RUT Proveedor</label>
                            <input
                                {...register('ruc')}
                                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                            />
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-700">Proveedor</label>
                            <input
                                {...register('proveedor')}
                                className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.proveedor ? 'border-red-500' : ''}`}
                            />
                            {errors.proveedor && <p className="mt-1 text-sm text-red-600">{errors.proveedor.message}</p>}
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-700">Moneda</label>
                            <input
                                {...register('moneda')}
                                className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.moneda ? 'border-red-500' : ''}`}
                            />
                            {errors.moneda && <p className="mt-1 text-sm text-red-600">{errors.moneda.message}</p>}
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-700">Valor Afecto</label>
                            <input
                                type="number"
                                step="0.01"
                                {...register('valor_afecto', { valueAsNumber: true })}
                                className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.valor_afecto ? 'border-red-500' : ''}`}
                            />
                            {errors.valor_afecto && <p className="mt-1 text-sm text-red-600">{errors.valor_afecto.message}</p>}
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-700">Valor Inafecto</label>
                            <input
                                type="number"
                                step="0.01"
                                {...register('valor_inafecto', { valueAsNumber: true })}
                                className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.valor_inafecto ? 'border-red-500' : ''}`}
                            />
                            {errors.valor_inafecto && <p className="mt-1 text-sm text-red-600">{errors.valor_inafecto.message}</p>}
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-700">Impuestos</label>
                            <input
                                type="number"
                                step="0.01"
                                {...register('impuestos', { valueAsNumber: true })}
                                className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.impuestos ? 'border-red-500' : ''}`}
                            />
                            {errors.impuestos && <p className="mt-1 text-sm text-red-600">{errors.impuestos.message}</p>}
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-700">Importe</label>
                            <input
                                type="number"
                                step="0.01"
                                {...register('importe', { valueAsNumber: true })}
                                className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.importe ? 'border-red-500' : ''}`}
                            />
                            {errors.importe && <p className="mt-1 text-sm text-red-600">{errors.importe.message}</p>}
                        </div>
                    </div>
                    <h4 className="text-md font-semibold mt-4">Ítems</h4>
                    {currentInvoice.items.map((item, index) => (
                        <div key={index} className="border-t pt-4">
                            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                                <div>
                                    <label className="block text-sm font-medium text-gray-700">Producto</label>
                                    <input
                                        {...register(`items.${index}.producto_insumo`)}
                                        className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.items?.[index]?.producto_insumo ? 'border-red-500' : ''}`}
                                    />
                                    {errors.items?.[index]?.producto_insumo && <p className="mt-1 text-sm text-red-600">{errors.items[index].producto_insumo?.message}</p>}
                                </div>
                                <div>
                                    <label className="block text-sm font-medium text-gray-700">Cantidad</label>
                                    <input
                                        type="number"
                                        step="0.01"
                                        {...register(`items.${index}.cantidad`, { valueAsNumber: true })}
                                        className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.items?.[index]?.cantidad ? 'border-red-500' : ''}`}
                                    />
                                    {errors.items?.[index]?.cantidad && <p className="mt-1 text-sm text-red-600">{errors.items[index].cantidad?.message}</p>}
                                </div>
                                <div>
                                    <label className="block text-sm font-medium text-gray-700">Precio Unitario</label>
                                    <input
                                        type="number"
                                        step="0.01"
                                        {...register(`items.${index}.precio_unitario`, { valueAsNumber: true })}
                                        className={`mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 ${errors.items?.[index]?.precio_unitario ? 'border-red-500' : ''}`}
                                    />
                                    {errors.items?.[index]?.precio_unitario && <p className="mt-1 text-sm text-red-600">{errors.items[index].precio_unitario?.message}</p>}
                                </div>
                            </div>
                        </div>
                    ))}
                    <div className="flex justify-end space-x-4 mt-6">
                        <button
                            type="button"
                            onClick={onClose}
                            className="px-4 py-2 bg-gray-300 text-gray-700 rounded hover:bg-gray-400"
                        >
                            Cancelar
                        </button>
                        <button
                            type="submit"
                            className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
                        >
                            Guardar Factura
                        </button>
                    </div>
                </form>
            </div>
        </div>
    );
}

export default InvoicePreviewModal;