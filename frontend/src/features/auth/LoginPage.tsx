import { useForm } from 'react-hook-form';
import { Link, useNavigate } from 'react-router-dom';
import { useMutation } from '@tanstack/react-query';
import { signIn } from '@api/auth';
import { useAuthStore } from '@stores/authStore';

interface LoginForm {
  email: string;
  password: string;
}

export function LoginPage() {
  const navigate = useNavigate();
  const setUser = useAuthStore((state) => state.setUser);

  const {
    register,
    handleSubmit,
    formState: { errors },
    setError,
  } = useForm<LoginForm>();

  const mutation = useMutation({
    mutationFn: (data: LoginForm) => signIn({ email: data.email, password: data.password }),
    onSuccess: (user) => {
      setUser(user);
      navigate('/projects');
    },
    onError: () => {
      setError('root', { message: 'Invalid email or password.' });
    },
  });

  const onSubmit = (data: LoginForm) => {
    mutation.mutate(data);
  };

  return (
    <div className="min-h-screen bg-[#f6f7fb] px-4 py-12 sm:grid sm:place-items-center">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center"><span className="inline-grid h-9 w-9 place-items-center rounded-lg bg-zinc-950 text-sm font-bold text-white">CR</span><h1 className="mt-3 text-xl font-semibold tracking-tight text-zinc-950">CodeReviewer.AI</h1><p className="mt-1 text-sm text-zinc-500">Focused code review, without noise.</p></div>
        <div className="app-panel p-6 sm:p-8">
          <h2 className="text-xl font-semibold tracking-tight text-zinc-950">Sign in</h2>
          <p className="mt-1 text-sm text-zinc-500">Continue to your review workspace.</p>
          <form onSubmit={handleSubmit(onSubmit)} noValidate data-testid="login-form">
            {errors.root && (
              <p className="text-red-600 text-sm mb-4" data-testid="login-error">
                {errors.root.message}
              </p>
            )}
            <div className="mb-4 mt-6">
              <label htmlFor="email" className="field-label">
                Email
              </label>
              <input
                id="email"
                type="email"
                autoComplete="email"
                className="field-input"
                data-testid="login-email"
                {...register('email', {
                  required: 'Email is required',
                  pattern: { value: /^\S+@\S+\.\S+$/, message: 'Invalid email address' },
                })}
              />
              {errors.email && (
                <p className="text-red-500 text-xs mt-1">{errors.email.message}</p>
              )}
            </div>
            <div className="mb-6">
              <label htmlFor="password" className="field-label">
                Password
              </label>
              <input
                id="password"
                type="password"
                autoComplete="current-password"
                className="field-input"
                data-testid="login-password"
                {...register('password', { required: 'Password is required' })}
              />
              {errors.password && (
                <p className="text-red-500 text-xs mt-1">{errors.password.message}</p>
              )}
            </div>
            <button
              type="submit"
              disabled={mutation.isPending}
              className="btn-primary w-full"
              data-testid="login-submit"
            >
              {mutation.isPending ? 'Signing in...' : 'Sign in'}
            </button>
          </form>
          <p className="text-center text-sm text-zinc-500 mt-5">
            Don&apos;t have an account?{' '}
            <Link to="/register" className="font-medium text-blue-600 hover:text-blue-700">
              Register
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}
