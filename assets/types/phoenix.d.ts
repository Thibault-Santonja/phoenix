// Type declarations for Phoenix dependencies

declare module "phoenix" {
  export class Socket {
    constructor(endPoint: string, opts?: object);
    connect(): void;
    disconnect(): void;
    channel(topic: string, params?: object): Channel;
    onOpen(callback: () => void): void;
    onClose(callback: () => void): void;
    onError(callback: (error: Error) => void): void;
  }

  export class Channel {
    join(): Push;
    leave(): Push;
    push(event: string, payload?: object): Push;
    on(event: string, callback: (response: unknown) => void): void;
    off(event: string): void;
  }

  export class Push {
    receive(status: string, callback: (response: unknown) => void): Push;
  }
}

declare module "phoenix_html" {
  // Phoenix HTML is imported for side effects
}

declare module "phoenix_live_view" {
  import { Socket } from "phoenix";

  export interface ViewHook {
    el: HTMLElement;
    pushEvent(event: string, payload?: object, callback?: (reply: unknown) => void): void;
    pushEventTo(
      selector: string | HTMLElement,
      event: string,
      payload?: object,
      callback?: (reply: unknown) => void
    ): void;
    handleEvent(event: string, callback: (payload: unknown) => void): void;
    upload(name: string, files: FileList): void;
    uploadTo(
      selector: string | HTMLElement,
      name: string,
      files: FileList
    ): void;
  }

  export interface HookCallbacks {
    mounted?(): void;
    beforeUpdate?(): void;
    updated?(): void;
    destroyed?(): void;
    disconnected?(): void;
    reconnected?(): void;
  }

  export type Hook = HookCallbacks & Partial<ViewHook>;

  export interface LiveSocketOptions {
    params?: object | (() => object);
    hooks?: Record<string, Hook>;
    longPollFallbackMs?: number;
    timeout?: number;
    uploaders?: Record<string, unknown>;
    dom?: {
      onBeforeElUpdated?: (from: HTMLElement, to: HTMLElement) => boolean;
    };
  }

  export class LiveSocket {
    constructor(url: string, socket: typeof Socket, opts?: LiveSocketOptions);
    connect(): void;
    disconnect(): void;
    enableDebug(): void;
    enableLatencySim(latencyMs: number): void;
    disableLatencySim(): void;
  }
}
