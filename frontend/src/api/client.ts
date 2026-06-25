import axios from 'axios';
import { useAuthStore } from '@stores/authStore';

const client = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL as string,
  headers: { 'Content-Type': 'application/json' },
});

client.interceptors.request.use((config) => {
  // Read token directly from store state — not the hook (interceptor runs outside React)
  const token = useAuthStore.getState().token;
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

client.interceptors.response.use(
  (response) => {
    // Devise emits JWT in the Authorization response header on sign-in / register
    const authHeader = response.headers['authorization'] as string | undefined;
    if (authHeader?.startsWith('Bearer ')) {
      const token = authHeader.slice(7);
      useAuthStore.getState().setToken(token);
    }
    return response;
  },
  (error) => {
    if (error.response?.status === 401) {
      useAuthStore.getState().clear();
    }
    return Promise.reject(error);
  }
);

export default client;
