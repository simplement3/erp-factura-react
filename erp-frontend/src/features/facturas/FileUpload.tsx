import { useState, useCallback } from 'react';
import { useDropzone } from 'react-dropzone';
import { toast } from 'react-toastify';
import { postOCR, saveInvoice, Invoice } from '../../api/apiClient';
import InvoicePreviewModal from './InvoicePreviewModal';
import { ArrowUpTrayIcon } from '@heroicons/react/24/solid';  // Reemplazado UploadIcon por ArrowUpTrayIcon

function FileUpload() {
    const [invoices, setInvoices] = useState<Invoice[]>([]);
    const [isModalOpen, setIsModalOpen] = useState(false);

    const onDrop = useCallback(async (acceptedFiles: File[]) => {
        try {
            const response = await postOCR(acceptedFiles);
            if (response.success) {
                setInvoices(response.data);
                setIsModalOpen(true);
                toast.success('Archivos procesados correctamente');
            } else {
                toast.error(response.error || 'Error al procesar archivos');
            }
        } catch (error) {
            console.error('Error en onDrop:', error);  // Usar error para evitar ESLint no-unused-vars
            toast.error('Error al procesar archivos');
        }
    }, []);

    const { getRootProps, getInputProps, isDragActive } = useDropzone({
        onDrop,
        accept: { 'application/pdf': ['.pdf'], 'image/*': ['.png', '.jpg', '.jpeg'] },
        multiple: true,
    });

    const handleSave = async (invoice: Invoice) => {
        try {
            await saveInvoice(invoice);
            toast.success('Factura guardada correctamente');
            setIsModalOpen(false);
        } catch (error) {
            console.error('Error en handleSave:', error);  // Usar error para evitar ESLint no-unused-vars
            toast.error('Error al guardar factura');
        }
    };

    return (
        <div className="mt-6">
            <div
                {...getRootProps()}
                className={`border-2 border-dashed rounded-lg p-6 text-center ${isDragActive ? 'border-blue-500 bg-blue-50' : 'border-gray-300 bg-white'
                    }`}
            >
                <input {...getInputProps()} />
                <ArrowUpTrayIcon className="mx-auto h-12 w-12 text-gray-400" />
                <p className="mt-2 text-sm text-gray-600">
                    {isDragActive
                        ? 'Suelta los archivos aquí'
                        : 'Arrastra y suelta facturas (PDF o imágenes) o haz clic para seleccionar'}
                </p>
            </div>
            {isModalOpen && (
                <InvoicePreviewModal
                    invoices={invoices}
                    onSave={handleSave}
                    onClose={() => setIsModalOpen(false)}
                />
            )}
        </div>
    );
}

export default FileUpload;