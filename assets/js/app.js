// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"
// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
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
} from "./hooks";

function getSystemTheme() {
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

function setTheme() {
  const html = document.documentElement;
  const stored = localStorage.getItem("theme");
  const theme = stored || getSystemTheme();
  html.classList.toggle("dark", theme === "dark");
}

setTheme();

// Hook animate this
const Hooks = {};

Hooks.MishkaComponents = MishkaComponents;
Hooks.Floating = Floating;
Hooks.AnimateThis = AnimateThis;
Hooks.AnimateGallery = AnimateGallery;
Hooks.AnimatePath = AnimatePath;
Hooks.AnimateTimelineScroll = AnimateTimelineScroll;
Hooks.GalleryModal = GalleryModal;
Hooks.YearTrigger = YearTrigger;
Hooks.HorizontalScrollFadeIn = HorizontalScrollFadeIn;
Hooks.AnimatePhotographyGallery = AnimatePhotographyGallery;
Hooks.DarkModeSwitch = DarkModeSwitch;

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {
    _csrf_token: csrfToken,
  },
  hooks: Hooks,
});
// Show progress bar on live navigation and form submits
topbar.config({
  barColors: {
    0: "#29d",
  },
  shadowColor: "rgba(0, 0, 0, .3)",
});
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());
// connect if there are any LiveViews on the page
liveSocket.connect();
// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

const SetLocale = () => {
  if (document.cookie.match("locale=") == null) {
    document.cookie = `locale=${navigator.language};path=/`;
    location.reload();
  }
};
SetLocale();

window.addEventListener("phx:change_locale", (e) => {
  document.cookie = `locale=${e.detail.locale};path=/`;
  location.reload();
});
