import type { Hook, HookInstance, ViewHook } from "phoenix_live_view";
import type Sortable from "sortablejs";

// =============================================================================
// Types
// =============================================================================

interface FocusTrap {
  activate: () => void;
  deactivate: () => void;
}

interface EventHandlerEntry {
  element: HTMLElement;
  mouseenter: (e: MouseEvent) => void;
  mouseleave: (e: MouseEvent) => void;
}

interface ImageClickHandler {
  element: HTMLElement;
  handler: () => void;
}

// Anime.js types (simplified)
interface AnimeModule {
  animate: (target: string | Element, params: object) => AnimeAnimation;
  utils: {
    $: (selector: string) => Element[];
  };
  createDraggable: (target: string, options: object) => Draggable;
  createSpring: (options: object) => unknown;
  onScroll: (options: object) => unknown;
}

interface AnimeAnimation {
  pause: () => void;
}

interface Draggable {
  destroy: () => void;
}

// =============================================================================
// Hook State Interfaces
// =============================================================================

interface AnimateThisState {
  rotations: number;
  $logo: Element | undefined;
  $button: HTMLElement | undefined;
  animate: AnimeModule["animate"] | undefined;
  bounceAnimation: AnimeAnimation | undefined;
  draggable: Draggable | undefined;
  rotateLogo: (() => void) | undefined;
}

interface AnimateGalleryState {
  eventHandlers: EventHandlerEntry[];
  images: Element[];
  cleanupEventHandlers: () => void;
}

interface AnimatePathState {
  animation: AnimeAnimation | null;
  $path: SVGPathElement | undefined;
}

interface AnimateTimelineScrollState {
  scrollContainer: EventTarget | null;
  observer: IntersectionObserver | undefined;
  scrollHandler: ((e: WheelEvent) => void) | undefined;
  enableScrollSync: (timeline: HTMLElement, container: EventTarget) => void;
  disableScrollSync: (container: EventTarget) => void;
}

interface GalleryModalState {
  modal: HTMLElement | null;
  modalImage: HTMLImageElement | null;
  backdrop: HTMLElement | null;
  transitionDuration: number;
  imageClickHandlers: ImageClickHandler[];
  currentIndex: number;
  images: HTMLImageElement[];
  previouslyFocusedElement: Element | null;
  focusTrap: FocusTrap | null;
  backdropClickHandler: (() => void) | undefined;
  keydownHandler: ((e: KeyboardEvent) => void) | undefined;
  isModalOpen: () => boolean;
  openModal: (index: number) => void;
  closeModal: () => void;
  showPrevious: () => void;
  showNext: () => void;
  showImage: (index: number) => void;
  updateModalImage: () => void;
}

interface YearTriggerState {
  initialized: boolean;
  yearEl: HTMLElement | null;
  animate: AnimeModule["animate"] | undefined;
  navLinks: NodeListOf<HTMLElement> | undefined;
  sections: NodeListOf<HTMLElement> | undefined;
  currentYear: number;
  observer: IntersectionObserver | undefined;
  animateNavYearMenu: ((activeYear: number) => void) | undefined;
  animateDigitRoll:
    | ((digitWrapper: HTMLElement, fromDigit: number, toDigit: number) => void)
    | undefined;
}

interface HorizontalScrollFadeInState {
  handleWheel: ((e: WheelEvent) => void) | undefined;
  animateItems: (duration: number) => void;
}

interface DarkModeSwitchState {
  clickHandler: (() => void) | undefined;
}

interface ParallaxHeroState {
  ticking: boolean;
  img: HTMLImageElement | null;
  updateParallax: (() => void) | undefined;
  handleScroll: (() => void) | undefined;
}

interface SmoothScrollState {
  handleClick: ((e: MouseEvent) => void) | undefined;
  anchors: NodeListOf<Element> | undefined;
}

interface PhotoSortableState {
  sortable: Sortable | null;
  initializeSortable: () => Promise<void>;
}

interface CountdownState {
  interval: ReturnType<typeof setInterval> | undefined;
}

interface InfiniteScrollState {
  pending: boolean;
  observer: IntersectionObserver | undefined;
}

// =============================================================================
// Typed Hook Helper
// =============================================================================

/**
 * Helper type to get typed access to hook state.
 * Usage: const state = this as unknown as TypedHook<MyState>;
 */
type TypedHook<T> = ViewHook & T;

// =============================================================================
// Utilities
// =============================================================================

// Conditional logging: only log in development mode
const isDev = window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1";
// eslint-disable-next-line no-console
const log = isDev ? console.log.bind(console) : (): void => {};

// Focus trap utility for accessible modals
const createFocusTrap = (container: HTMLElement): FocusTrap => {
  const focusableSelectors = [
    "button:not([disabled])",
    "[href]",
    "input:not([disabled])",
    "select:not([disabled])",
    "textarea:not([disabled])",
    '[tabindex]:not([tabindex="-1"])',
  ].join(", ");

  const getFocusableElements = (): HTMLElement[] => {
    return Array.from(container.querySelectorAll<HTMLElement>(focusableSelectors)).filter(
      (el) => el.offsetParent !== null
    );
  };

  const handleKeydown = (e: KeyboardEvent): void => {
    if (e.key !== "Tab") {
      return;
    }

    const focusable = getFocusableElements();
    if (focusable.length === 0) {
      e.preventDefault();
      return;
    }

    const firstElement = focusable[0];
    const lastElement = focusable[focusable.length - 1];

    if (e.shiftKey) {
      if (
        document.activeElement === firstElement ||
        !focusable.includes(document.activeElement as HTMLElement)
      ) {
        e.preventDefault();
        lastElement.focus();
      }
    } else {
      if (
        document.activeElement === lastElement ||
        !focusable.includes(document.activeElement as HTMLElement)
      ) {
        e.preventDefault();
        firstElement.focus();
      }
    }
  };

  return {
    activate: (): void => {
      container.addEventListener("keydown", handleKeydown);
      const focusable = getFocusableElements();
      if (focusable.length > 0) {
        focusable[0].focus();
      } else if (container.tabIndex >= 0) {
        container.focus();
      }
    },
    deactivate: (): void => {
      container.removeEventListener("keydown", handleKeydown);
    },
  };
};

// =============================================================================
// Lazy Loading
// =============================================================================

let animeModule: AnimeModule | null = null;
let sortableModule: typeof Sortable | null = null;

const loadAnimejs = async (): Promise<AnimeModule> => {
  if (!animeModule) {
    animeModule = (await import("animejs")) as unknown as AnimeModule;
  }
  return animeModule;
};

const loadSortable = async (): Promise<typeof Sortable> => {
  if (!sortableModule) {
    const module = await import("sortablejs");
    sortableModule = module.default;
  }
  return sortableModule;
};

// =============================================================================
// Hooks
// =============================================================================

export const AnimateThis: Hook = {
  async mounted() {
    const hook = this as unknown as TypedHook<AnimateThisState>;

    try {
      const { animate, utils, createDraggable, createSpring } = await loadAnimejs();

      const [$logo] = utils.$(".logo.js");
      const [$button] = utils.$("#button") as HTMLElement[];
      hook.rotations = 0;
      hook.$logo = $logo;
      hook.$button = $button;
      hook.animate = animate;

      hook.bounceAnimation = animate(".logo.js", {
        scale: [
          { to: 1.1, ease: "inOut(3)", duration: 200 },
          { to: 1, ease: createSpring({ stiffness: 300 }) },
        ],
        loop: true,
        loopDelay: 250,
      });

      hook.draggable = createDraggable(".logo.js", {
        container: [0, 0, 0, 0],
        releaseEase: createSpring({ stiffness: 200 }),
      });

      hook.rotateLogo = (): void => {
        hook.rotations++;
        if (hook.$button) {
          hook.$button.innerText = `rotations: ${hook.rotations}`;
        }
        if (hook.animate && hook.$logo) {
          hook.animate(hook.$logo, {
            rotate: hook.rotations * 360,
            ease: "out(4)",
            duration: 1500,
          });
        }
      };

      if ($button) {
        $button.addEventListener("click", hook.rotateLogo);
      }
    } catch (error) {
      log("AnimateThis initialization failed:", error);
    }
  },

  disconnected() {
    const hook = this as unknown as TypedHook<AnimateThisState>;
    if (hook.bounceAnimation) {
      hook.bounceAnimation.pause();
    }
  },

  destroyed() {
    const hook = this as unknown as TypedHook<AnimateThisState>;
    if (hook.$button && hook.rotateLogo) {
      hook.$button.removeEventListener("click", hook.rotateLogo);
    }
    if (hook.bounceAnimation) {
      hook.bounceAnimation.pause();
      hook.bounceAnimation = undefined;
    }
    if (hook.draggable && typeof hook.draggable.destroy === "function") {
      hook.draggable.destroy();
      hook.draggable = undefined;
    }
  },
};

export const AnimateGallery: Hook = {
  async mounted() {
    const hook = this as unknown as TypedHook<AnimateGalleryState>;
    hook.eventHandlers = [];
    hook.images = [];

    hook.cleanupEventHandlers = (): void => {
      hook.eventHandlers.forEach(({ element, mouseenter, mouseleave }) => {
        element.removeEventListener("mouseenter", mouseenter as EventListener);
        element.removeEventListener("mouseleave", mouseleave as EventListener);
      });
      hook.eventHandlers = [];
    };

    try {
      const { animate, utils, onScroll } = await loadAnimejs();

      const debug = false;
      hook.images = utils.$(".gallery__image");
      const [container] = utils.$(".follower");

      const animateImage = (el: Element, from: number, to: number): void => {
        hook.images
          .filter((item: Element) => item !== el)
          .forEach(($image: Element) => {
            animate($image, {
              opacity: [from, to],
              ease: "out(6)",
              duration: 500,
            });
          });
      };

      const hover = (el: Element): void => animateImage(el, 1, 0.4);
      const unhover = (el: Element): void => animateImage(el, 0.4, 1);

      hook.images.forEach(($image: HTMLElement, i: number) => {
        animate($image, {
          opacity: [0, 1],
          translateY: [100, 0],
          ease: "out(3)",
          duration: 2000,
          delay: i * 120,
          autoplay: onScroll({
            target: $image,
            container: container,
            debug,
          }),
        });

        const mouseenterHandler = (e: MouseEvent): void => hover(e.target as Element);
        const mouseleaveHandler = (e: MouseEvent): void => unhover(e.target as Element);

        $image.addEventListener("mouseenter", mouseenterHandler, false);
        $image.addEventListener("mouseleave", mouseleaveHandler, false);

        hook.eventHandlers.push({
          element: $image,
          mouseenter: mouseenterHandler,
          mouseleave: mouseleaveHandler,
        });
      });
    } catch (error) {
      log("AnimateGallery initialization failed:", error);
    }
  },

  disconnected() {
    const hook = this as unknown as TypedHook<AnimateGalleryState>;
    hook.cleanupEventHandlers();
  },

  destroyed() {
    const hook = this as unknown as TypedHook<AnimateGalleryState>;
    hook.cleanupEventHandlers();
  },
};

export const AnimatePath: Hook = {
  async mounted() {
    const hook = this as unknown as TypedHook<AnimatePathState>;
    hook.animation = null;

    try {
      const { animate, utils } = await loadAnimejs();

      const [$path] = utils.$("#path-zigzag") as SVGPathElement[];
      if (!$path) {
        return;
      }

      hook.$path = $path;
      const length = $path.getTotalLength();
      $path.style.strokeDasharray = String(length);
      $path.style.strokeDashoffset = String(length);

      hook.animation = animate($path, {
        strokeDashoffset: [length, 0],
        duration: 2200,
        delay: 300,
        easing: "easeInOutSine",
      });
    } catch (error) {
      log("AnimatePath initialization failed:", error);
    }
  },

  disconnected() {
    const hook = this as unknown as TypedHook<AnimatePathState>;
    if (hook.animation) {
      hook.animation.pause();
    }
  },

  destroyed() {
    const hook = this as unknown as TypedHook<AnimatePathState>;
    if (hook.animation) {
      hook.animation.pause();
      hook.animation = null;
    }
  },
};

export const AnimateTimelineScroll: Hook = {
  mounted() {
    const hook = this as unknown as TypedHook<AnimateTimelineScrollState>;
    const timeline = hook.el as HTMLElement;
    const container = timeline.closest("#timeline_container") || window;
    hook.scrollContainer = container;

    hook.enableScrollSync = (tl: HTMLElement, cont: EventTarget): void => {
      hook.scrollHandler = (e: WheelEvent): void => {
        const atStart = tl.scrollLeft === 0;
        const atEnd = tl.scrollLeft + tl.clientWidth >= tl.scrollWidth - 1;

        const goingUp = e.deltaY < 0;
        const goingDown = e.deltaY > 0;

        const allowVerticalScroll = (goingUp && atStart) || (goingDown && atEnd);

        if (!allowVerticalScroll) {
          tl.scrollLeft += e.deltaY;
          e.preventDefault();
        }
      };

      cont.addEventListener("wheel", hook.scrollHandler as EventListener, {
        passive: false,
      });
    };

    hook.disableScrollSync = (cont: EventTarget): void => {
      if (hook.scrollHandler) {
        cont.removeEventListener("wheel", hook.scrollHandler as EventListener);
        hook.scrollHandler = undefined;
      }
    };

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          hook.enableScrollSync(timeline, container);
        } else {
          hook.disableScrollSync(container);
        }
      },
      {
        root: null,
        rootMargin: "-20% 0px -50% 0px",
      }
    );

    observer.observe(timeline);
    hook.observer = observer;
  },

  disconnected() {
    const hook = this as unknown as TypedHook<AnimateTimelineScrollState>;
    hook.disableScrollSync(hook.scrollContainer || window);
  },

  destroyed() {
    const hook = this as unknown as TypedHook<AnimateTimelineScrollState>;
    hook.observer?.disconnect?.();
    hook.disableScrollSync(hook.scrollContainer || window);
    hook.scrollContainer = null;
  },
};

export const GalleryModal: Hook = {
  mounted() {
    const hook = this as unknown as TypedHook<GalleryModalState>;
    hook.modal = document.getElementById("image-modal");
    hook.modalImage = document.getElementById("modal-image") as HTMLImageElement;
    hook.backdrop = document.getElementById("modal-backdrop");
    hook.transitionDuration = 150;
    hook.imageClickHandlers = [];
    hook.currentIndex = -1;
    hook.images = Array.from(document.querySelectorAll<HTMLImageElement>(".gallery__image img"));
    hook.previouslyFocusedElement = null;
    hook.focusTrap = null;

    hook.isModalOpen = (): boolean => {
      return hook.modal !== null && !hook.modal.classList.contains("hidden");
    };

    hook.updateModalImage = (): void => {
      const img = hook.images[hook.currentIndex];
      if (!img || !hook.modalImage || !hook.modal) {
        return;
      }

      const src = img.getAttribute("data-full_image_src") || img.src;
      hook.modalImage.src = src;
      hook.modalImage.alt = img.alt || `Image ${hook.currentIndex + 1} of ${hook.images.length}`;

      hook.modal.setAttribute(
        "aria-label",
        `Image ${hook.currentIndex + 1} of ${hook.images.length}. Use arrow keys to navigate.`
      );
    };

    hook.openModal = (index: number): void => {
      if (!hook.modal || !hook.modalImage) {return;}

      hook.previouslyFocusedElement = document.activeElement;
      hook.currentIndex = index;
      hook.updateModalImage();

      hook.modal.classList.remove("hidden");
      hook.modal.classList.add("flex");

      hook.modal.setAttribute("role", "dialog");
      hook.modal.setAttribute("aria-modal", "true");
      hook.modal.setAttribute("aria-label", "Image gallery viewer");

      if (!hook.modal.hasAttribute("tabindex")) {
        hook.modal.setAttribute("tabindex", "-1");
      }

      if (!hook.focusTrap) {
        hook.focusTrap = createFocusTrap(hook.modal);
      }
      hook.focusTrap.activate();

      setTimeout(() => {
        if (hook.modalImage) {
          hook.modalImage.classList.remove("scale-50", "opacity-0");
          hook.modalImage.classList.add("scale-100", "opacity-100");
        }
      }, hook.transitionDuration);
    };

    hook.closeModal = (): void => {
      if (!hook.modal || !hook.modalImage) {return;}

      if (hook.focusTrap) {
        hook.focusTrap.deactivate();
      }

      hook.modalImage.classList.remove("scale-100", "opacity-100");
      hook.modalImage.classList.add("scale-50", "opacity-0");

      setTimeout(() => {
        if (hook.modal && hook.modalImage) {
          hook.modal.classList.add("hidden");
          hook.modal.classList.remove("flex");
          hook.modalImage.src = "";
          hook.currentIndex = -1;

          if (hook.previouslyFocusedElement && "focus" in hook.previouslyFocusedElement) {
            (hook.previouslyFocusedElement as HTMLElement).focus();
            hook.previouslyFocusedElement = null;
          }
        }
      }, hook.transitionDuration);
    };

    hook.showPrevious = (): void => {
      if (hook.images.length === 0) {return;}
      hook.currentIndex = (hook.currentIndex - 1 + hook.images.length) % hook.images.length;
      hook.updateModalImage();
    };

    hook.showNext = (): void => {
      if (hook.images.length === 0) {return;}
      hook.currentIndex = (hook.currentIndex + 1) % hook.images.length;
      hook.updateModalImage();
    };

    hook.showImage = (index: number): void => {
      if (index >= 0 && index < hook.images.length) {
        hook.currentIndex = index;
        hook.updateModalImage();
      }
    };

    hook.images.forEach((img: HTMLImageElement, index: number) => {
      const clickHandler = (): void => {
        hook.openModal(index);
      };

      img.addEventListener("click", clickHandler);
      hook.imageClickHandlers.push({ element: img, handler: clickHandler });
    });

    hook.backdropClickHandler = (): void => {
      hook.closeModal();
    };

    if (hook.backdrop) {
      hook.backdrop.addEventListener("click", hook.backdropClickHandler);
    }

    hook.keydownHandler = (e: KeyboardEvent): void => {
      if (!hook.isModalOpen()) {return;}

      switch (e.key) {
        case "Escape":
          e.preventDefault();
          hook.closeModal();
          break;
        case "ArrowLeft":
          e.preventDefault();
          hook.showPrevious();
          break;
        case "ArrowRight":
          e.preventDefault();
          hook.showNext();
          break;
        case "Home":
          e.preventDefault();
          hook.showImage(0);
          break;
        case "End":
          e.preventDefault();
          hook.showImage(hook.images.length - 1);
          break;
      }
    };

    window.addEventListener("keydown", hook.keydownHandler);
  },

  disconnected() {
    const hook = this as unknown as TypedHook<GalleryModalState>;
    if (hook.keydownHandler) {
      window.removeEventListener("keydown", hook.keydownHandler);
    }
  },

  destroyed() {
    const hook = this as unknown as TypedHook<GalleryModalState>;

    hook.imageClickHandlers.forEach(({ element, handler }) => {
      element.removeEventListener("click", handler);
    });

    if (hook.backdrop && hook.backdropClickHandler) {
      hook.backdrop.removeEventListener("click", hook.backdropClickHandler);
    }

    if (hook.keydownHandler) {
      window.removeEventListener("keydown", hook.keydownHandler);
    }
  },
};

export const YearTrigger: Hook = {
  async mounted() {
    const hook = this as unknown as TypedHook<YearTriggerState>;

    if (hook.initialized) {return;}
    hook.initialized = true;

    hook.yearEl = document.getElementById("timeline-year");
    if (!hook.yearEl) {return;}

    try {
      const { animate } = await loadAnimejs();
      hook.animate = animate;
    } catch (error) {
      log("YearTrigger: Failed to load animejs:", error);
      return;
    }

    hook.navLinks = document.querySelectorAll("[data-anchor-year]");
    hook.sections = document.querySelectorAll("[data-year]");
    hook.currentYear = parseInt(
      [...hook.yearEl.querySelectorAll(".digit")].map((d: Element) => d.textContent).join("")
    );

    hook.animateNavYearMenu = (activeYear: number): void => {
      hook.navLinks?.forEach((link: HTMLElement) => {
        const isActive = parseInt(link.dataset.year || "0") === activeYear;
        link.classList.toggle("opacity-100", isActive);
        link.classList.toggle("opacity-60", !isActive);
        link.classList.toggle("font-semibold", isActive);
      });
    };

    hook.animateDigitRoll = (
      digitWrapper: HTMLElement,
      fromDigit: number,
      toDigit: number
    ): void => {
      if (!hook.animate) {return;}

      digitWrapper.innerHTML = "";
      const sign = fromDigit > toDigit;
      const toElY = sign ? "translateY(100%)" : "translateY(-100%)";
      const fromElYTranslation = sign ? ["0%", "-100%"] : ["0%", "100%"];
      const toElYTranslation = sign ? ["100%", "0%"] : ["-100%", "0%"];

      const fromEl = document.createElement("div");
      fromEl.textContent = String(fromDigit);
      fromEl.style.position = "absolute";
      fromEl.style.top = "0";
      fromEl.style.left = "0";
      fromEl.style.right = "0";
      fromEl.style.textAlign = "center";
      fromEl.style.opacity = "1";
      fromEl.style.transform = "translateY(0%)";

      const toEl = document.createElement("div");
      toEl.textContent = String(toDigit);
      toEl.style.position = "absolute";
      toEl.style.top = "0";
      toEl.style.left = "0";
      toEl.style.right = "0";
      toEl.style.textAlign = "center";
      toEl.style.opacity = "0";
      toEl.style.transform = toElY;

      const container = document.createElement("div");
      container.style.position = "relative";
      container.style.height = "1em";
      container.appendChild(fromEl);
      container.appendChild(toEl);

      digitWrapper.appendChild(container);

      hook.animate(fromEl, {
        translateY: fromElYTranslation,
        opacity: [1, 0],
        duration: 500,
        easing: "easeInOutCubic",
      });

      hook.animate(toEl, {
        translateY: toElYTranslation,
        opacity: [0, 1],
        duration: 500,
        easing: "easeInOutCubic",
      });
    };

    hook.observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => Math.abs(a.boundingClientRect.top) - Math.abs(b.boundingClientRect.top));

        const topEntry = visible[0];
        if (!topEntry) {return;}

        const newYear = parseInt((topEntry.target as HTMLElement).dataset.year || "0");
        if (newYear !== hook.currentYear && hook.yearEl && hook.animateDigitRoll) {
          const fromStr = String(hook.currentYear).padStart(4, "0");
          const toStr = String(newYear).padStart(4, "0");
          const digitWrappers = hook.yearEl.querySelectorAll(".digit-wrapper");

          for (let i = 0; i < 4; i++) {
            const fromDigit = parseInt(fromStr[i]);
            const toDigit = parseInt(toStr[i]);

            if (fromDigit !== toDigit) {
              hook.animateDigitRoll(digitWrappers[i] as HTMLElement, fromDigit, toDigit);
            }
          }

          hook.currentYear = newYear;
          hook.animateNavYearMenu?.(newYear);
        }
      },
      {
        rootMargin: "-20% 0px -80% 0px",
      }
    );

    hook.animateNavYearMenu(hook.currentYear);
    hook.sections?.forEach((section: Element) => hook.observer?.observe(section));
  },

  destroyed() {
    const hook = this as unknown as TypedHook<YearTriggerState>;
    if (hook.observer) {
      hook.observer.disconnect();
    }
    hook.initialized = false;
  },
};

export const HorizontalScrollFadeIn: Hook = {
  mounted() {
    const hook = this as unknown as TypedHook<HorizontalScrollFadeInState>;

    hook.animateItems = (duration: number): void => {
      const items = hook.el.querySelectorAll("li");

      items.forEach((el: Element, i: number) => {
        if (duration) {
          setTimeout(() => {
            el.classList.add("opacity-100");
          }, i * duration);
        } else {
          el.classList.add("opacity-100");
        }
      });
    };

    hook.handleWheel = (e: WheelEvent): void => {
      if (e.deltaY === 0) {return;}

      e.preventDefault();

      hook.el.scrollBy({
        left: e.deltaY,
      });
    };

    hook.el.addEventListener("wheel", hook.handleWheel, { passive: false });
    hook.animateItems(100);
  },

  updated() {
    const hook = this as unknown as TypedHook<HorizontalScrollFadeInState>;
    hook.animateItems(0);
  },

  destroyed() {
    const hook = this as unknown as TypedHook<HorizontalScrollFadeInState>;
    if (hook.handleWheel) {
      hook.el.removeEventListener("wheel", hook.handleWheel);
    }
  },
};

export const AnimatePhotographyGallery: Hook = {
  mounted() {
    const hook = this as unknown as HookInstance;
    const [header] = document.getElementsByClassName("project-title");
    if (!header) {return;}

    setTimeout(() => {
      header.classList.replace("opacity-0", "opacity-100");
    }, 300);

    setTimeout(() => {
      hook.el.classList.replace("opacity-0", "opacity-100");
      hook.el.classList.replace("translate-y-8", "translate-y-0");
    }, 275);
  },
};

export const DarkModeSwitch: Hook = {
  mounted() {
    const hook = this as unknown as TypedHook<DarkModeSwitchState>;
    const html = document.documentElement;

    hook.clickHandler = (): void => {
      const isDark = html.classList.contains("dark");
      const newTheme = isDark ? "light" : "dark";

      html.classList.toggle("dark", newTheme === "dark");

      try {
        localStorage.setItem("theme", newTheme);
      } catch (e) {
        log("Could not persist theme preference:", e);
      }
    };
    hook.el.addEventListener("click", hook.clickHandler);
  },

  destroyed() {
    const hook = this as unknown as TypedHook<DarkModeSwitchState>;
    if (hook.clickHandler) {
      hook.el.removeEventListener("click", hook.clickHandler);
    }
  },
};

export const ParallaxHero: Hook = {
  mounted() {
    const hook = this as unknown as TypedHook<ParallaxHeroState>;
    hook.ticking = false;
    hook.img = hook.el.querySelector("img");

    hook.updateParallax = (): void => {
      if (!hook.img) {return;}
      const scrolled = window.pageYOffset;
      const speed = scrolled * 0.5;
      hook.img.style.transform = `translateY(${speed}px)`;
      hook.ticking = false;
    };

    hook.handleScroll = (): void => {
      if (!hook.ticking) {
        hook.ticking = true;
        requestAnimationFrame(hook.updateParallax!);
      }
    };

    window.addEventListener("scroll", hook.handleScroll, { passive: true });
  },

  disconnected() {
    const hook = this as unknown as TypedHook<ParallaxHeroState>;
    if (hook.handleScroll) {
      window.removeEventListener("scroll", hook.handleScroll);
    }
  },

  destroyed() {
    const hook = this as unknown as TypedHook<ParallaxHeroState>;
    if (hook.handleScroll) {
      window.removeEventListener("scroll", hook.handleScroll);
    }
    hook.img = null;
  },
};

export const SmoothScroll: Hook = {
  mounted() {
    const hook = this as unknown as TypedHook<SmoothScrollState>;
    const anchors = hook.el.querySelectorAll('a[href^="#"]');

    hook.handleClick = (e: MouseEvent): void => {
      e.preventDefault();
      const href = (e.currentTarget as HTMLAnchorElement).getAttribute("href");
      if (!href) {return;}

      let target: Element | null = document.querySelector(href);

      if (!target && href.startsWith("#year-")) {
        const yearAnchor = href.substring(1);
        target = document.querySelector(`[data-album-year-anchor="${yearAnchor}"]`);
      }

      if (target) {
        target.scrollIntoView({
          behavior: "smooth",
          block: "start",
        });
      }
    };

    anchors.forEach((anchor: Element) => {
      anchor.addEventListener("click", hook.handleClick as EventListener);
    });

    hook.anchors = anchors;
  },

  destroyed() {
    const hook = this as unknown as TypedHook<SmoothScrollState>;
    if (hook.anchors && hook.handleClick) {
      hook.anchors.forEach((anchor: Element) => {
        anchor.removeEventListener("click", hook.handleClick as EventListener);
      });
    }
  },
};

export const PhotoSortable: Hook = {
  async mounted() {
    const hook = this as unknown as TypedHook<PhotoSortableState>;
    log("PhotoSortable mounted", hook.el);
    hook.sortable = null;

    hook.initializeSortable = async (): Promise<void> => {
      const isReordering = (hook.el as HTMLElement).dataset.reordering === "true";
      log("Initializing sortable, reordering:", isReordering);

      if (hook.sortable) {
        log("Destroying existing sortable");
        hook.sortable.destroy();
        hook.sortable = null;
      }

      if (isReordering) {
        log("Creating sortable instance");

        const SortableLib = await loadSortable();

        const items = hook.el.querySelectorAll(".sortable-item");
        log("Found sortable items:", items.length);

        hook.sortable = SortableLib.create(hook.el as HTMLElement, {
          animation: 150,
          draggable: ".sortable-item",
          handle: ".sortable-item",
          ghostClass: "sortable-ghost",
          chosenClass: "sortable-chosen",
          dragClass: "sortable-drag",
          forceFallback: false,
          fallbackClass: "sortable-fallback",
          fallbackOnBody: true,
          swapThreshold: 0.65,
          direction: "horizontal",

          onStart: (evt: Sortable.SortableEvent): void => {
            log("Drag started", evt.oldIndex);
          },

          onEnd: (evt: Sortable.SortableEvent): void => {
            log("Drag ended", evt.oldIndex, "->", evt.newIndex);

            const photoIds = Array.from(
              hook.el.querySelectorAll("[data-photo-id]") as NodeListOf<HTMLElement>
            ).map((el: HTMLElement) => el.dataset.photoId);

            log("New order:", photoIds);

            hook.pushEvent("reorder_photos", { photo_ids: photoIds });
          },
        });

        log("Sortable instance created:", hook.sortable);
      }
    };

    try {
      await hook.initializeSortable();
    } catch (error) {
      log("PhotoSortable initialization failed:", error);
    }
  },

  async updated() {
    const hook = this as unknown as TypedHook<PhotoSortableState>;
    log("PhotoSortable updated", {
      reordering: (hook.el as HTMLElement).dataset.reordering,
    });
    try {
      await hook.initializeSortable();
    } catch (error) {
      log("PhotoSortable re-initialization failed:", error);
    }
  },

  disconnected() {
    const hook = this as unknown as TypedHook<PhotoSortableState>;
    log("PhotoSortable disconnected");
    if (hook.sortable) {
      hook.sortable.destroy();
      hook.sortable = null;
    }
  },

  destroyed() {
    const hook = this as unknown as TypedHook<PhotoSortableState>;
    log("PhotoSortable destroyed");
    if (hook.sortable) {
      hook.sortable.destroy();
      hook.sortable = null;
    }
  },
};

export const RateLimitCountdown: Hook = {
  mounted() {
    const hook = this as unknown as TypedHook<CountdownState>;
    const retryAfter = parseInt((hook.el as HTMLElement).dataset.retryAfter || "0", 10);
    const display = document.getElementById("countdown-display");

    if (!display || !retryAfter) {return;}

    let remaining = retryAfter;

    const updateDisplay = (): void => {
      const minutes = Math.floor(remaining / 60);
      const seconds = remaining % 60;

      if (minutes > 0) {
        display.textContent = `${minutes}min ${seconds}s`;
      } else {
        display.textContent = `${seconds}s`;
      }
    };

    updateDisplay();

    hook.interval = setInterval(() => {
      remaining--;

      if (remaining <= 0) {
        clearInterval(hook.interval);
        window.location.reload();
      } else {
        updateDisplay();
      }
    }, 1000);
  },

  destroyed() {
    const hook = this as unknown as TypedHook<CountdownState>;
    if (hook.interval) {
      clearInterval(hook.interval);
    }
  },
};

export const MagicLinkExpiration: Hook = {
  mounted() {
    const hook = this as unknown as TypedHook<CountdownState>;
    const expiresIn = parseInt((hook.el as HTMLElement).dataset.expiresIn || "0", 10);
    const display = document.getElementById("magic-link-countdown");

    if (!display || !expiresIn) {return;}

    let remaining = expiresIn;

    const updateDisplay = (): void => {
      const minutes = Math.floor(remaining / 60);
      const seconds = remaining % 60;

      if (minutes > 0) {
        display.textContent = `${minutes}min ${seconds}s`;
      } else if (seconds > 0) {
        display.textContent = `${seconds}s`;
      } else {
        display.textContent = "expiré";
        const grandparent = display.parentElement?.parentElement?.parentElement;
        if (grandparent) {
          grandparent.classList.remove("bg-green-50");
          grandparent.classList.add("bg-red-50");
        }
        const paragraph = display.parentElement?.querySelector("p");
        if (paragraph) {
          paragraph.textContent =
            "Le lien de connexion a expiré. Veuillez demander un nouveau lien.";
        }
      }
    };

    updateDisplay();

    hook.interval = setInterval(() => {
      remaining--;

      if (remaining < 0) {
        clearInterval(hook.interval);
      } else {
        updateDisplay();
      }
    }, 1000);
  },

  destroyed() {
    const hook = this as unknown as TypedHook<CountdownState>;
    if (hook.interval) {
      clearInterval(hook.interval);
    }
  },
};

export const InfiniteScroll: Hook = {
  mounted() {
    const hook = this as unknown as TypedHook<InfiniteScrollState>;
    hook.pending = false;

    hook.observer = new IntersectionObserver(
      (entries) => {
        const target = entries[0];
        if (target.isIntersecting && !hook.pending) {
          hook.pending = true;
          hook.pushEvent("load_more", {}, () => {
            hook.pending = false;
          });
        }
      },
      {
        root: null,
        rootMargin: "1200px",
        threshold: 0,
      }
    );

    hook.observer.observe(hook.el);
  },

  destroyed() {
    const hook = this as unknown as TypedHook<InfiniteScrollState>;
    if (hook.observer) {
      hook.observer.disconnect();
    }
  },
};
