import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderWithProviders } from '@/tests/testUtils';
import { LoginPage } from './LoginPage';
import { useAuthStore } from '@stores/authStore';
import * as authApi from '@api/auth';

// Mock the auth API so no network calls are made
jest.mock('@api/auth');
const mockedSignIn = authApi.signIn as jest.MockedFunction<typeof authApi.signIn>;

describe('LoginPage', () => {
  beforeEach(() => {
    useAuthStore.getState().clear();
    localStorage.clear();
    mockedSignIn.mockResolvedValue({
      id: 1,
      email: 'test@example.com',
      name: 'Test User',
      role: 'reviewer',
    });
  });

  it('renders the login form', () => {
    renderWithProviders(<LoginPage />);

    expect(screen.getByTestId('login-form')).toBeInTheDocument();
    expect(screen.getByTestId('login-email')).toBeInTheDocument();
    expect(screen.getByTestId('login-password')).toBeInTheDocument();
    expect(screen.getByTestId('login-submit')).toBeInTheDocument();
  });

  it('renders the app title', () => {
    renderWithProviders(<LoginPage />);
    expect(screen.getByText('CodeReviewer.AI')).toBeInTheDocument();
  });

  it('shows a validation error when email is empty', async () => {
    const user = userEvent.setup();
    renderWithProviders(<LoginPage />);

    await user.click(screen.getByTestId('login-submit'));

    await waitFor(() => {
      expect(screen.getByText('Email is required')).toBeInTheDocument();
    });
  });

  it('calls signIn and stores the user on successful submission', async () => {
    const user = userEvent.setup();
    renderWithProviders(<LoginPage />, { initialEntries: ['/login'] });

    await user.type(screen.getByTestId('login-email'), 'test@example.com');
    await user.type(screen.getByTestId('login-password'), 'password123');
    await user.click(screen.getByTestId('login-submit'));

    await waitFor(() => {
      expect(mockedSignIn).toHaveBeenCalledWith({
        email: 'test@example.com',
        password: 'password123',
      });
    });

    await waitFor(() => {
      expect(useAuthStore.getState().user?.email).toBe('test@example.com');
    });
  });

  it('shows an error message on failed login', async () => {
    mockedSignIn.mockRejectedValueOnce(new Error('Unauthorized'));
    const user = userEvent.setup();
    renderWithProviders(<LoginPage />);

    await user.type(screen.getByTestId('login-email'), 'bad@example.com');
    await user.type(screen.getByTestId('login-password'), 'wrongpassword');
    await user.click(screen.getByTestId('login-submit'));

    await waitFor(() => {
      expect(screen.getByTestId('login-error')).toBeInTheDocument();
    });
  });

  it('has a link to the register page', () => {
    renderWithProviders(<LoginPage />);
    expect(screen.getByRole('link', { name: /register/i })).toBeInTheDocument();
  });
});
