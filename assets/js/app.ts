// Phoenix HTML to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";

// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import type { Hook } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import MishkaComponents from "../vendor/mishka_components.js";
import Floating from "../vendor/floating.js";

import {
  AnimateThis,
  AnimateGallery,
  AnimatePath,
  AnimateTimelineScroll,
  GalleryModal,
  YearTrigger,
  HorizontalScrollFadeIn,
  AnimatePhotographyGallery,
  DarkModeSwitch,
  PhotoSortable,
  ParallaxHero,
  SmoothScroll,
  RateLimitCountdown,
  MagicLinkExpiration,
  InfiniteScroll,
} from "./hooks";

// =============================================================================
// Theme Management
// =============================================================================

function getSystemTheme(): "dark" | "light" {
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function setTheme(): void {
  const html = document.documentElement;
  const stored = localStorage.getItem("theme");
  const theme = stored || getSystemTheme();
  html.classList.toggle("dark", theme === "dark");
}

setTheme();

// =============================================================================
// LiveView Hooks Registration
// =============================================================================

const Hooks: Record<string, Hook> = {
  MishkaComponents: MishkaComponents as Hook,
  Floating: Floating as Hook,
  AnimateThis,
  AnimateGallery,
  AnimatePath,
  AnimateTimelineScroll,
  GalleryModal,
  YearTrigger,
  HorizontalScrollFadeIn,
  AnimatePhotographyGallery,
  DarkModeSwitch,
  PhotoSortable,
  ParallaxHero,
  SmoothScroll,
  RateLimitCountdown,
  MagicLinkExpiration,
  InfiniteScroll,
};

// =============================================================================
// LiveSocket Configuration
// =============================================================================

const csrfTokenMeta = document.querySelector("meta[name='csrf-token']");
const csrfToken = csrfTokenMeta ? csrfTokenMeta.getAttribute("content") : "";

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {
    _csrf_token: csrfToken,
  },
  hooks: Hooks,
});

// =============================================================================
// Progress Bar Configuration
// =============================================================================

topbar.config({
  barColors: {
    0: "#29d",
  },
  shadowColor: "rgba(0, 0, 0, .3)",
});

window.addEventListener("phx:page-loading-start", (_info: Event) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info: Event) => topbar.hide());

// Connect to LiveView
liveSocket.connect();

// Expose liveSocket on window for debugging
(window as any).liveSocket = liveSocket;

// =============================================================================
// Locale Management
// =============================================================================

// Normalize locale value to prevent injection (BCP-47 format)
const normalizeLocale = (value: unknown): string =>
  typeof value === "string" ? value.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 20) : "";

const SetLocale = (): void => {
  if (document.cookie.match(/(?:^|;\s*)locale=/) === null) {
    const locale = normalizeLocale(navigator.language);
    if (!locale) {
      return;
    }
    document.cookie = `locale=${locale};path=/;SameSite=Lax`;
    // Only reload if cookie was successfully set (avoid infinite loop if cookies blocked)
    if (document.cookie.match(/(?:^|;\s*)locale=/)) {
      location.reload();
    }
  }
};

SetLocale();

// Handle locale change events from LiveView
interface LocaleChangeEvent extends CustomEvent {
  detail: {
    locale: string;
  };
}

window.addEventListener("phx:change_locale", ((e: LocaleChangeEvent) => {
  const locale = normalizeLocale(e.detail.locale);
  if (!locale) {
    return;
  }
  document.cookie = `locale=${locale};path=/;SameSite=Lax`;
  location.reload();
}) as EventListener);
