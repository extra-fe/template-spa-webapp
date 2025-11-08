import { useAuth0 } from '@auth0/auth0-react';
import type { JSX } from 'react';

const ProtectedRoute = ({ children }: { children: JSX.Element }) => {
  const { isAuthenticated, isLoading, loginWithRedirect } = useAuth0();

  if (isLoading) return <div>Loading...</div>;

  if (!isAuthenticated) {
    loginWithRedirect(); // 認証してないならリダイレクト
    return null;
  }

  return children;
};

export default ProtectedRoute;
