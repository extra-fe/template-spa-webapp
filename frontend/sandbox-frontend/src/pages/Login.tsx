import { useAuth0 } from '@auth0/auth0-react';
import { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';

const Login = () => {
  const { loginWithRedirect, isAuthenticated, isLoading, getAccessTokenSilently } = useAuth0();
  const navigate = useNavigate();

  useEffect(() => {
    // 認証状態が変わったら実行
    const handleAuth = async () => {
      if (isAuthenticated) {
        try {
          // ログイン後にページ遷移
          navigate('/races');
        } catch (err) {
          console.error('トークン取得に失敗しました:', err);
        }
      }
    };
    handleAuth();
  }, [isAuthenticated, getAccessTokenSilently, navigate]);

  if (isLoading) return <div>Loading...</div>;

  const handleLogin = () => {
    loginWithRedirect(); // Auth0 のログインページにリダイレクト
  };

  return (
    <div>
      <h2>ログイン</h2>
      <button onClick={handleLogin}>Auth0でログインする</button>
    </div>
  );
};

export default Login;
