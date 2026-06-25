import { useAuthStore } from './authStore';
import type { User } from '@api/schemas';

const mockUser: User = {
  id: 1,
  email: 'test@example.com',
  name: 'Test User',
  role: 'reviewer',
};

describe('authStore', () => {
  beforeEach(() => {
    // Reset the store to initial state before each test
    useAuthStore.getState().clear();
    // Clear localStorage so persist middleware starts fresh
    localStorage.clear();
  });

  it('initialises with null token and user', () => {
    const { token, user } = useAuthStore.getState();
    expect(token).toBeNull();
    expect(user).toBeNull();
  });

  it('setToken stores a JWT token', () => {
    useAuthStore.getState().setToken('abc.def.ghi');
    expect(useAuthStore.getState().token).toBe('abc.def.ghi');
  });

  it('setUser stores a user object', () => {
    useAuthStore.getState().setUser(mockUser);
    expect(useAuthStore.getState().user).toEqual(mockUser);
  });

  it('clear resets token and user to null', () => {
    useAuthStore.getState().setToken('some-token');
    useAuthStore.getState().setUser(mockUser);

    useAuthStore.getState().clear();

    expect(useAuthStore.getState().token).toBeNull();
    expect(useAuthStore.getState().user).toBeNull();
  });
});
