// Type declarations for vendor modules

declare module "../vendor/topbar" {
  interface TopbarConfig {
    barColors?: Record<number, string>;
    shadowColor?: string;
    shadowBlur?: number;
  }

  interface Topbar {
    config(options: TopbarConfig): void;
    show(delay?: number): void;
    hide(): void;
    progress(value: number): void;
  }

  const topbar: Topbar;
  export default topbar;
}

declare module "../vendor/mishka_components.js" {
  import type { Hook } from "phoenix_live_view";
  const MishkaComponents: Hook;
  export default MishkaComponents;
}

declare module "../vendor/floating.js" {
  import type { Hook } from "phoenix_live_view";
  const Floating: Hook;
  export default Floating;
}

// Anime.js module declaration
declare module "animejs" {
  export interface AnimeParams {
    targets?: string | Element | Element[];
    duration?: number;
    delay?: number | ((el: Element, i: number, l: number) => number);
    easing?: string;
    loop?: boolean | number;
    loopDelay?: number;
    autoplay?: boolean | unknown;
    scale?: number | number[] | { to: number; ease?: string; duration?: number }[];
    opacity?: number | number[];
    translateX?: number | number[] | string | string[];
    translateY?: number | number[] | string | string[];
    rotate?: number | string;
    strokeDashoffset?: number | number[];
    [key: string]: unknown;
  }

  export interface Animation {
    pause(): void;
    play(): void;
    restart(): void;
    seek(time: number): void;
    finished: Promise<void>;
  }

  export interface Utils {
    $: (selector: string) => Element[];
  }

  export interface Draggable {
    destroy(): void;
  }

  export function animate(targets: string | Element, params: AnimeParams): Animation;
  export const utils: Utils;
  export function createDraggable(
    targets: string,
    options: {
      container?: number[];
      releaseEase?: unknown;
    }
  ): Draggable;
  export function createSpring(options: { stiffness?: number }): unknown;
  export function onScroll(options: {
    target?: Element;
    container?: Element;
    debug?: boolean;
  }): unknown;
}
