import { createContext, ReactNode, useState } from 'react';

export interface AuthContextType {
    user: { id: number; email: string; rol: string; id_negocio: number } | null;
    login: (token: string, user: { id: number; email: string; rol: string; id_negocio: number }) => void;
    logout: () => void;
}

// @refresh reset
export const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
    const [user, setUser] = useState<{ id: number; email: string; rol: string; id_negocio: number } | null>(() => {
        const userData = localStorage.getItem('user');
        if (userData) {
            try {
                return JSON.parse(userData);
            } catch (error) {
                console.error('Error parsing user from localStorage:', error);
                localStorage.removeItem('user');
                return null;
            }
        }
        return null;
    });

    const login = (token: string, user: { id: number; email: string; rol: string; id_negocio: number }) => {
        localStorage.setItem('token', token);
        localStorage.setItem('user', JSON.stringify(user));
        setUser(user);
    };

    const logout = () => {
        localStorage.removeItem('token');
        localStorage.removeItem('user');
        setUser(null);
        window.location.href = '/login';
    };

    return (
        <AuthContext.Provider value={{ user, login, logout }}>
            {children}
        </AuthContext.Provider>
    );
}