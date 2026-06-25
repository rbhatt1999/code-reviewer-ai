// Type declarations for actioncable 5.2.8-1 (no @types/actioncable available).
// The package exports the ActionCable namespace object as module.exports.

declare module 'actioncable' {
  export interface Subscription {
    unsubscribe(): void;
  }

  export interface ChannelParams {
    channel: string;
    [key: string]: unknown;
  }

  export interface SubscriptionCallbacks<T = unknown> {
    connected?(): void;
    disconnected?(): void;
    received?(data: T): void;
    rejected?(): void;
  }

  export interface Subscriptions {
    create<T = unknown>(
      channelOrParams: string | ChannelParams,
      callbacks: SubscriptionCallbacks<T>
    ): Subscription;
  }

  export interface Consumer {
    subscriptions: Subscriptions;
    disconnect(): void;
    connect(): void;
  }

  interface ActionCableInterface {
    createConsumer(url?: string): Consumer;
  }

  const ActionCable: ActionCableInterface;
  export default ActionCable;
}
