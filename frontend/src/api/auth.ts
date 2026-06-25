import client from './client';
import { UserSchema } from './schemas';
import type { User } from './schemas';

interface SignUpParams {
  name: string;
  email: string;
  password: string;
}

interface SignInParams {
  email: string;
  password: string;
}

export async function signUp(params: SignUpParams): Promise<User> {
  const response = await client.post('/auth', { user: params });
  return UserSchema.parse(response.data.user);
}

export async function signIn(params: SignInParams): Promise<User> {
  const response = await client.post('/auth/sign_in', { user: params });
  return UserSchema.parse(response.data.user);
}

export async function signOut(): Promise<void> {
  await client.delete('/auth/sign_out');
}

export async function getMe(): Promise<User> {
  const response = await client.get('/auth/me');
  return UserSchema.parse(response.data.user);
}
