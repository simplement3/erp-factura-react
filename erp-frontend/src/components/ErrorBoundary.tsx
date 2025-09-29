import { Component, ReactNode } from 'react';
import { toast } from 'react-toastify';

interface Props {
    children: ReactNode;
}

interface State {
    hasError: boolean;
}

class ErrorBoundary extends Component<Props, State> {
    state: State = { hasError: false };

    static getDerivedStateFromError(): State {
        return { hasError: true };
    }

    componentDidCatch(error: Error) {
        console.error('ErrorBoundary caught:', error);
        toast.error('Ocurrió un error inesperado. Por favor, intenta de nuevo.');
    }

    render() {
        if (this.state.hasError) {
            return (
                <div className="p-4 text-center">
                    <h2 className="text-xl font-bold text-red-600">Algo salió mal</h2>
                    <p className="mt-2">Por favor, recarga la página o contacta al soporte.</p>
                </div>
            );
        }
        return this.props.children;
    }
}

export default ErrorBoundary;