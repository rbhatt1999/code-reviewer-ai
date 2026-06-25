import ActionCable from 'actioncable';
import type { Consumer } from 'actioncable';
import { useAuthStore } from '@stores/authStore';

let consumer: Consumer | null = null;
let lastToken: string | null = null;

export function teardown(): void {
  consumer?.disconnect();
  consumer = null;
  lastToken = null;
}

export function getConsumer(): Consumer | null {
  const token = useAuthStore.getState().token;
  if (!token) {
    teardown();
    return null;
  }
  if (consumer && token === lastToken) return consumer;
  teardown();
  const url = `${import.meta.env.VITE_WS_BASE_URL}?token=${encodeURIComponent(token)}`;
  consumer = ActionCable.createConsumer(url);
  lastToken = token;
  return consumer;
}

// Tear down and recreate the consumer when the token changes (logout / token rotation).
useAuthStore.subscribe((state, prev) => {
  if (state.token !== prev.token) teardown();
});
