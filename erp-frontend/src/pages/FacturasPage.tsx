import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { toast } from 'react-toastify';
import { getFacturas, deleteInvoice, generateDTE } from '../api/apiClient';
import { Invoice } from '../api/apiClient';
import FileUpload from '../features/facturas/FileUpload';
import DTEConfirmationModal from '../features/facturas/DTEConfirmationModal';
import { TrashIcon, DocumentTextIcon, ReceiptPercentIcon, ArrowDownTrayIcon } from '@heroicons/react/24/solid';
import { format } from 'date-fns';

interface DTEData {
    folio: string;
    tipo_dte: number;
    estado: string;
}

function FacturasPage() {
    const queryClient = useQueryClient();
    const [page, setPage] = useState(1);
    const [filters, setFilters] = useState({
        estado: '',
        tipoDTE: '',
        fechaInicio: '',
        fechaFin: '',
    });
    const [isDTEModalOpen, setIsDTEModalOpen] = useState(false);
    const [dteData, setDTEData] = useState<DTEData | null>(null);

    const { data, isLoading, error } = useQuery({
        queryKey: ['facturas', page, filters],
        queryFn: () =>
            getFacturas(page, 50, {
                estado: filters.estado,
                tipo_dte: filters.tipoDTE,
                fecha_inicio: filters.fechaInicio,
                fecha_fin: filters.fechaFin,
            }),
    });

    const deleteMutation = useMutation({
        mutationFn: deleteInvoice,
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['facturas'] });
            toast.success('Factura eliminada correctamente');
        },
        onError: () => toast.error('Error al eliminar factura'),
    });

    const generateDTEMutation = useMutation({
        mutationFn: ({ factura_id, tipo_dte }: { factura_id: number; tipo_dte: number }) =>
            generateDTE(factura_id, tipo_dte),
        onSuccess: (response) => {
            queryClient.invalidateQueries({ queryKey: ['facturas'] });
            toast.success('DTE generado correctamente');
            setDTEData(response.data);
            setIsDTEModalOpen(true);
        },
        onError: () => toast.error('Error al generar DTE'),
    });

    const handleFilterChange = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
        setFilters({ ...filters, [e.target.name]: e.target.value });
        setPage(1);
    };

    const handleExport = () => {
        const facturas = data?.data || [];
        const csvContent = [
            ['ID', 'Fecha Factura', 'Serie', 'Número', 'RUT', 'Proveedor', 'Importe', 'Moneda', 'Estado DTE', 'Folio DTE'],
            ...facturas.map((invoice: Invoice) => [
                invoice.id,
                invoice.fecha_factura,
                invoice.serie || '-',
                invoice.numero || '-',
                invoice.ruc || '-',
                invoice.proveedor,
                invoice.importe,
                invoice.moneda,
                invoice.dte_estado || '-',
                invoice.dte_folio || '-',
            ]),
        ]
            .map(row => row.map((cell: string | number | undefined) => `"${cell ?? '-'}"`).join(','))
            .join('\n');

        const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
        const link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = `facturas_${format(new Date(), 'yyyy-MM-dd')}.csv`;
        link.click();
    };

    const renderContent = () => {
        if (isLoading) {
            return (
                <div className="flex justify-center items-center h-screen">
                    <div className="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500"></div>
                </div>
            );
        }
        if (error) {
            toast.error('Error al cargar facturas');
            return <div className="text-red-600 text-center">Error al cargar facturas</div>;
        }

        const facturas = data?.data || [];
        const { page: currentPage, total, pages } = data?.pagination || {};

        return (
            <>
                <div className="table-container mt-6">
                    <div className="overflow-x-auto">
                        <table className="min-w-full bg-white shadow-md rounded-lg">
                            <thead>
                                <tr className="bg-gray-200 text-gray-600 uppercase text-sm">
                                    <th className="py-3 px-6 text-left">Fecha Factura</th>
                                    <th className="py-3 px-6 text-left">Serie</th>
                                    <th className="py-3 px-6 text-left">Número</th>
                                    <th className="py-3 px-6 text-left">RUT</th>
                                    <th className="py-3 px-6 text-left">Proveedor</th>
                                    <th className="py-3 px-6 text-left">Importe</th>
                                    <th className="py-3 px-6 text-left">Moneda</th>
                                    <th className="py-3 px-6 text-left">Acciones / DTE</th>
                                </tr>
                            </thead>
                            <tbody>
                                {facturas.length === 0 ? (
                                    <tr>
                                        <td colSpan={8} className="py-4 text-center text-gray-500">
                                            No hay facturas procesadas. Sube archivos para comenzar.
                                        </td>
                                    </tr>
                                ) : (
                                    facturas.map((invoice: Invoice) => {
                                        const hasDTE = invoice.dte_folio && invoice.dte_estado === 'enviada_sii';
                                        return (
                                            <tr key={invoice.id} className="border-b">
                                                <td className="py-3 px-6">{invoice.fecha_factura}</td>
                                                <td className="py-3 px-6">{invoice.serie || '-'}</td>
                                                <td className="py-3 px-6">{invoice.numero || '-'}</td>
                                                <td className="py-3 px-6">{invoice.ruc || '-'}</td>
                                                <td className="py-3 px-6">
                                                    <div className="flex flex-col">
                                                        {invoice.proveedor}
                                                        {hasDTE && (
                                                            <span className="dte-status-badge success mt-1">
                                                                <i className="fas fa-check-circle"></i> DTE: {invoice.dte_folio}
                                                            </span>
                                                        )}
                                                    </div>
                                                </td>
                                                <td className="py-3 px-6">{invoice.importe}</td>
                                                <td className="py-3 px-6">{invoice.moneda}</td>
                                                <td className="py-3 px-6">
                                                    <div className="flex space-x-2">
                                                        {!hasDTE && (
                                                            <>
                                                                <button
                                                                    className="dte-btn factura"
                                                                    onClick={() =>
                                                                        generateDTEMutation.mutate({ factura_id: invoice.id!, tipo_dte: 33 })
                                                                    }
                                                                    disabled={generateDTEMutation.isPending}
                                                                >
                                                                    <DocumentTextIcon className="w-4 h-4 mr-1" /> Factura
                                                                </button>
                                                                <button
                                                                    className="dte-btn boleta"
                                                                    onClick={() =>
                                                                        generateDTEMutation.mutate({ factura_id: invoice.id!, tipo_dte: 39 })
                                                                    }
                                                                    disabled={generateDTEMutation.isPending}
                                                                >
                                                                    <ReceiptPercentIcon className="w-4 h-4 mr-1" /> Boleta
                                                                </button>
                                                            </>
                                                        )}
                                                        <button
                                                            className="text-red-600 hover:text-red-800"
                                                            onClick={() => deleteMutation.mutate(invoice.id!)}
                                                            disabled={deleteMutation.isPending}
                                                        >
                                                            <TrashIcon className="w-5 h-5" />
                                                        </button>
                                                    </div>
                                                </td>
                                            </tr>
                                        );
                                    })
                                )}
                            </tbody>
                        </table>
                    </div>
                    {facturas.length > 0 && (
                        <div className="mt-4 flex justify-between">
                            <button
                                className="px-4 py-2 bg-blue-600 text-white rounded disabled:bg-gray-400"
                                disabled={page === 1}
                                onClick={() => setPage(page - 1)}
                            >
                                Anterior
                            </button>
                            <span>
                                Página {currentPage} de {pages} (Total: {total})
                            </span>
                            <button
                                className="px-4 py-2 bg-blue-600 text-white rounded disabled:bg-gray-400"
                                disabled={page === pages}
                                onClick={() => setPage(page + 1)}
                            >
                                Siguiente
                            </button>
                        </div>
                    )}
                </div>
                {isDTEModalOpen && dteData && (
                    <DTEConfirmationModal dteData={dteData} onClose={() => setIsDTEModalOpen(false)} />
                )}
            </>
        );
    };

    return (
        <div>
            <h2 className="text-2xl font-bold mb-4">Facturas Procesadas</h2>
            <FileUpload />
            <div className="mt-6 bg-white p-4 rounded-lg shadow-md">
                <h3 className="text-lg font-semibold mb-4">Filtros</h3>
                <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
                    <div>
                        <label className="block text-sm font-medium text-gray-700">Estado DTE</label>
                        <select
                            name="estado"
                            value={filters.estado}
                            onChange={handleFilterChange}
                            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                        >
                            <option value="">Todos</option>
                            <option value="enviada_sii">Enviada SII</option>
                            <option value="pendiente">Pendiente</option>
                            <option value="error">Error</option>
                        </select>
                    </div>
                    <div>
                        <label className="block text-sm font-medium text-gray-700">Tipo DTE</label>
                        <select
                            name="tipoDTE"
                            value={filters.tipoDTE}
                            onChange={handleFilterChange}
                            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                        >
                            <option value="">Todos</option>
                            <option value="33">Factura Electrónica</option>
                            <option value="39">Boleta Electrónica</option>
                        </select>
                    </div>
                    <div>
                        <label className="block text-sm font-medium text-gray-700">Fecha Inicio</label>
                        <input
                            type="date"
                            name="fechaInicio"
                            value={filters.fechaInicio}
                            onChange={handleFilterChange}
                            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                        />
                    </div>
                    <div>
                        <label className="block text-sm font-medium text-gray-700">Fecha Fin</label>
                        <input
                            type="date"
                            name="fechaFin"
                            value={filters.fechaFin}
                            onChange={handleFilterChange}
                            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                        />
                    </div>
                </div>
                <button
                    onClick={handleExport}
                    className="mt-4 px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 flex items-center"
                >
                    <ArrowDownTrayIcon className="w-5 h-5 mr-2" /> Exportar CSV
                </button>
            </div>
            {renderContent()}
        </div>
    );
}

export default FacturasPage;