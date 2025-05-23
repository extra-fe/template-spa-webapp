import { useAuth0 } from '@auth0/auth0-react';
export const useApiCaller = () => {
  const { getAccessTokenSilently, isAuthenticated } = useAuth0();

  const callApi = async (
    path: string,
    requiresAuth: boolean = true,
    method: string = 'GET',
    body?: any,
  ): Promise<any> => {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };

    if (requiresAuth && isAuthenticated) {
      const token = await getAccessTokenSilently();
      headers['Authorization'] = `Bearer ${token}`;
    }

    const res = await fetch(`${import.meta.env.VITE_API_BASE_URL}${path}`, {
      method,
      headers,
      credentials: 'include',
      body: body ? JSON.stringify(body) : undefined,
    });

    if (!res.ok) {
      throw new Error(`API call failed with status ${res.status}`);
    }

    return res.json();
  };

  return { callApi };
};  
