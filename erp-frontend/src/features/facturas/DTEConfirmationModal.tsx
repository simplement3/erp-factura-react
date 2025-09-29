import { XMarkIcon } from '@heroicons/react/24/solid';

interface DTEConfirmationModalProps {
    dteData: { folio: string; tipo_dte: number; estado: string };
    onClose: () => void;
}

function DTEConfirmationModal({ dteData, onClose }: DTEConfirmationModalProps) {
    return (
        <div className="fixed inset-0 bg-gray-600 bg-opacity-50 flex items-center justify-center z-50">
            <div className="bg-white rounded-lg p-6 w-full max-w-md">
                <div className="flex justify-between items-center mb-4">
                    <h3 className="text-lg font-bold">DTE Generado</h3>
                    <button onClick={onClose} className="text-gray-600 hover:text-gray-800">
                        <XMarkIcon className="w-6 h-6" />
                    </button>
                </div>
                <div className="space-y-2">
                    <p>
                        <strong>Tipo DTE:</strong> {dteData.tipo_dte === 33 ? 'Factura Electrónica' : 'Boleta Electrónica'}
                    </p>
                    <p>
                        <strong>Folio:</strong> {dteData.folio}
                    </p>
                    <p>
                        <strong>Estado:</strong> <span className="dte-status-badge success">{dteData.estado}</span>
                    </p>
                </div>
                <div className="flex justify-end mt-6">
                    <button
                        onClick={onClose}
                        className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
                    >
                        Cerrar
                    </button>
                </div>
            </div>
        </div>
    );
}

export default DTEConfirmationModal;