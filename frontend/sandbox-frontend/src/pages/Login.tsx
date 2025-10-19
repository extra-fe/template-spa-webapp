import { useNavigate } from 'react-router-dom';

const Login = () => {
  const navigate = useNavigate();

  const handleLogin = () => {
    // 通常はAPIでトークンを取得して保存
    localStorage.setItem('access_token', 'dummy-token');
    navigate('/races');
  };

  return (
    <div>
      <h2>ログイン</h2>
      <button onClick={handleLogin}>ログインする</button>
    </div>
  );
};

export default Login;
