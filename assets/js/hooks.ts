import type { Hook } from "phoenix_live_view";
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
    try {
      const { animate, utils, createDraggable, createSpring } = await loadAnimejs();

      const [$logo] = utils.$(".logo.js");
      const [$button] = utils.$("#button") as HTMLElement[];
      (this as any).rotations = 0;
      (this as any).$logo = $logo;
      (this as any).$button = $button;
      (this as any).animate = animate;

      (this as any).bounceAnimation = animate(".logo.js", {
        scale: [
          { to: 1.1, ease: "inOut(3)", duration: 200 },
          { to: 1, ease: createSpring({ stiffness: 300 }) },
        ],
        loop: true,
        loopDelay: 250,
      });

      (this as any).draggable = createDraggable(".logo.js", {
        container: [0, 0, 0, 0],
        releaseEase: createSpring({ stiffness: 200 }),
      });

      (this as any).rotateLogo = (): void => {
        (this as any).rotations++;
        (this as any).$button.innerText = `rotations: ${(this as any).rotations}`;
        (this as any).animate((this as any).$logo, {
          rotate: (this as any).rotations * 360,
          ease: "out(4)",
          duration: 1500,
        });
      };

      if ($button) {
        $button.addEventListener("click", (this as any).rotateLogo);
      }
    } catch (error) {
      log("AnimateThis initialization failed:", error);
    }
  },

  disconnected() {
    if ((this as any).bounceAnimation) {
      (this as any).bounceAnimation.pause();
    }
  },

  destroyed() {
    if ((this as any).$button && (this as any).rotateLogo) {
      (this as any).$button.removeEventListener("click", (this as any).rotateLogo);
    }
    if ((this as any).bounceAnimation) {
      (this as any).bounceAnimation.pause();
      (this as any).bounceAnimation = null;
    }
    if ((this as any).draggable && typeof (this as any).draggable.destroy === "function") {
      (this as any).draggable.destroy();
      (this as any).draggable = null;
    }
  },
};

export const AnimateGallery: Hook = {
  async mounted() {
    (this as any).eventHandlers = [] as EventHandlerEntry[];
    (this as any).images = [] as Element[];

    try {
      const { animate, utils, onScroll } = await loadAnimejs();

      const debug = false;
      (this as any).images = utils.$(".gallery__image");
      const [container] = utils.$(".follower");

      const animateImage = (el: Element, from: number, to: number): void => {
        (this as any).images
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

      (this as any).images.forEach(($image: HTMLElement, i: number) => {
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

        (this as any).eventHandlers.push({
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
    (this as any).cleanupEventHandlers();
  },

  destroyed() {
    (this as any).cleanupEventHandlers();
  },

  cleanupEventHandlers() {
    if ((this as any).eventHandlers) {
      (this as any).eventHandlers.forEach(
        ({ element, mouseenter, mouseleave }: EventHandlerEntry) => {
          element.removeEventListener("mouseenter", mouseenter as EventListener);
          element.removeEventListener("mouseleave", mouseleave as EventListener);
        }
      );
      (this as any).eventHandlers = [];
    }
  },
};

export const AnimatePath: Hook = {
  async mounted() {
    (this as any).animation = null;

    try {
      const { animate, utils } = await loadAnimejs();

      const [$path] = utils.$("#path-zigzag") as SVGPathElement[];
      if (!$path) {
        return;
      }

      (this as any).$path = $path;
      const length = $path.getTotalLength();
      $path.style.strokeDasharray = String(length);
      $path.style.strokeDashoffset = String(length);

      (this as any).animation = animate($path, {
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
    if ((this as any).animation) {
      (this as any).animation.pause();
    }
  },

  destroyed() {
    if ((this as any).animation) {
      (this as any).animation.pause();
      (this as any).animation = null;
    }
  },
};

export const AnimateTimelineScroll: Hook = {
  mounted() {
    const timeline = this.el as HTMLElement;
    const container = timeline.closest("#timeline_container") || window;
    (this as any).scrollContainer = container;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          (this as any).enableScrollSync(timeline, container);
        } else {
          (this as any).disableScrollSync(container);
        }
      },
      {
        root: null,
        rootMargin: "-20% 0px -50% 0px",
      }
    );

    observer.observe(timeline);
    (this as any).observer = observer;
  },

  disconnected() {
    (this as any).disableScrollSync((this as any).scrollContainer || window);
  },

  destroyed() {
    (this as any).observer?.disconnect?.();
    (this as any).disableScrollSync((this as any).scrollContainer || window);
    (this as any).scrollContainer = null;
  },

  enableScrollSync(timeline: HTMLElement, container: EventTarget) {
    (this as any).scrollHandler = (e: WheelEvent): void => {
      const atStart = timeline.scrollLeft === 0;
      const atEnd = timeline.scrollLeft + timeline.clientWidth >= timeline.scrollWidth - 1;

      const goingUp = e.deltaY < 0;
      const goingDown = e.deltaY > 0;

      const allowVerticalScroll = (goingUp && atStart) || (goingDown && atEnd);

      if (!allowVerticalScroll) {
        timeline.scrollLeft += e.deltaY;
        e.preventDefault();
      }
    };

    container.addEventListener("wheel", (this as any).scrollHandler as EventListener, {
      passive: false,
    });
  },

  disableScrollSync(container: EventTarget) {
    if ((this as any).scrollHandler) {
      container.removeEventListener("wheel", (this as any).scrollHandler as EventListener);
      (this as any).scrollHandler = null;
    }
  },
};

export const GalleryModal: Hook = {
  mounted() {
    (this as any).modal = document.getElementById("image-modal");
    (this as any).modalImage = document.getElementById("modal-image") as HTMLImageElement;
    (this as any).backdrop = document.getElementById("modal-backdrop");
    (this as any).transitionDuration = 150;
    (this as any).imageClickHandlers = [] as ImageClickHandler[];
    (this as any).currentIndex = -1;
    (this as any).images = Array.from(
      document.querySelectorAll<HTMLImageElement>(".gallery__image img")
    );
    (this as any).previouslyFocusedElement = null;
    (this as any).focusTrap = null;

    (this as any).images.forEach((img: HTMLImageElement, index: number) => {
      const clickHandler = (): void => {
        (this as any).openModal(index);
      };

      img.addEventListener("click", clickHandler);
      (this as any).imageClickHandlers.push({ element: img, handler: clickHandler });
    });

    (this as any).backdropClickHandler = (): void => {
      (this as any).closeModal();
    };

    if ((this as any).backdrop) {
      (this as any).backdrop.addEventListener("click", (this as any).backdropClickHandler);
    }

    (this as any).keydownHandler = (e: KeyboardEvent): void => {
      if (!(this as any).isModalOpen()) {
        return;
      }

      switch (e.key) {
        case "Escape":
          e.preventDefault();
          (this as any).closeModal();
          break;
        case "ArrowLeft":
          e.preventDefault();
          (this as any).showPrevious();
          break;
        case "ArrowRight":
          e.preventDefault();
          (this as any).showNext();
          break;
        case "Home":
          e.preventDefault();
          (this as any).showImage(0);
          break;
        case "End":
          e.preventDefault();
          (this as any).showImage((this as any).images.length - 1);
          break;
      }
    };

    window.addEventListener("keydown", (this as any).keydownHandler);
  },

  isModalOpen(): boolean {
    return (this as any).modal && !(this as any).modal.classList.contains("hidden");
  },

  openModal(index: number) {
    (this as any).previouslyFocusedElement = document.activeElement;
    (this as any).currentIndex = index;
    (this as any).updateModalImage();

    (this as any).modal.classList.remove("hidden");
    (this as any).modal.classList.add("flex");

    (this as any).modal.setAttribute("role", "dialog");
    (this as any).modal.setAttribute("aria-modal", "true");
    (this as any).modal.setAttribute("aria-label", "Image gallery viewer");

    if (!(this as any).modal.hasAttribute("tabindex")) {
      (this as any).modal.setAttribute("tabindex", "-1");
    }

    if (!(this as any).focusTrap) {
      (this as any).focusTrap = createFocusTrap((this as any).modal);
    }
    (this as any).focusTrap.activate();

    setTimeout(
      () => {
        (this as any).modalImage.classList.remove("scale-50", "opacity-0");
        (this as any).modalImage.classList.add("scale-100", "opacity-100");
      },
      (this as any).transitionDuration
    );
  },

  closeModal() {
    if ((this as any).focusTrap) {
      (this as any).focusTrap.deactivate();
    }

    (this as any).modalImage.classList.remove("scale-100", "opacity-100");
    (this as any).modalImage.classList.add("scale-50", "opacity-0");

    setTimeout(
      () => {
        (this as any).modal.classList.add("hidden");
        (this as any).modal.classList.remove("flex");
        (this as any).modalImage.src = "";
        (this as any).currentIndex = -1;

        if ((this as any).previouslyFocusedElement) {
          (this as any).previouslyFocusedElement.focus();
          (this as any).previouslyFocusedElement = null;
        }
      },
      (this as any).transitionDuration
    );
  },

  showPrevious() {
    if ((this as any).images.length === 0) {
      return;
    }
    (this as any).currentIndex =
      ((this as any).currentIndex - 1 + (this as any).images.length) % (this as any).images.length;
    (this as any).updateModalImage();
  },

  showNext() {
    if ((this as any).images.length === 0) {
      return;
    }
    (this as any).currentIndex = ((this as any).currentIndex + 1) % (this as any).images.length;
    (this as any).updateModalImage();
  },

  showImage(index: number) {
    if (index >= 0 && index < (this as any).images.length) {
      (this as any).currentIndex = index;
      (this as any).updateModalImage();
    }
  },

  updateModalImage() {
    const img = (this as any).images[(this as any).currentIndex] as HTMLImageElement;
    if (!img) {
      return;
    }

    const src = img.getAttribute("data-full_image_src") || img.src;
    (this as any).modalImage.src = src;
    (this as any).modalImage.alt =
      img.alt || `Image ${(this as any).currentIndex + 1} of ${(this as any).images.length}`;

    (this as any).modal.setAttribute(
      "aria-label",
      `Image ${(this as any).currentIndex + 1} of ${(this as any).images.length}. Use arrow keys to navigate.`
    );
  },

  disconnected() {
    if ((this as any).keydownHandler) {
      window.removeEventListener("keydown", (this as any).keydownHandler);
    }
  },

  destroyed() {
    (this as any).imageClickHandlers.forEach(({ element, handler }: ImageClickHandler) => {
      element.removeEventListener("click", handler);
    });

    if ((this as any).backdrop && (this as any).backdropClickHandler) {
      (this as any).backdrop.removeEventListener("click", (this as any).backdropClickHandler);
    }

    if ((this as any).keydownHandler) {
      window.removeEventListener("keydown", (this as any).keydownHandler);
    }
  },
};

export const YearTrigger: Hook = {
  async mounted() {
    if ((this as any).initialized) {
      return;
    }
    (this as any).initialized = true;

    (this as any).yearEl = document.getElementById("timeline-year");
    if (!(this as any).yearEl) {
      return;
    }

    try {
      const { animate } = await loadAnimejs();
      (this as any).animate = animate;
    } catch (error) {
      log("YearTrigger: Failed to load animejs:", error);
      return;
    }

    (this as any).navLinks = document.querySelectorAll("[data-anchor-year]");
    (this as any).sections = document.querySelectorAll("[data-year]");
    (this as any).currentYear = parseInt(
      [...(this as any).yearEl.querySelectorAll(".digit")]
        .map((d: Element) => d.textContent)
        .join("")
    );

    (this as any).animateNavYearMenu = (activeYear: number): void => {
      (this as any).navLinks.forEach((link: HTMLElement) => {
        const isActive = parseInt(link.dataset.year || "0") === activeYear;
        link.classList.toggle("opacity-100", isActive);
        link.classList.toggle("opacity-60", !isActive);
        link.classList.toggle("font-semibold", isActive);
      });
    };

    (this as any).animateDigitRoll = (
      digitWrapper: HTMLElement,
      fromDigit: number,
      toDigit: number
    ): void => {
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

      (this as any).animate(fromEl, {
        translateY: fromElYTranslation,
        opacity: [1, 0],
        duration: 500,
        easing: "easeInOutCubic",
      });

      (this as any).animate(toEl, {
        translateY: toElYTranslation,
        opacity: [0, 1],
        duration: 500,
        easing: "easeInOutCubic",
      });
    };

    (this as any).observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => Math.abs(a.boundingClientRect.top) - Math.abs(b.boundingClientRect.top));

        const topEntry = visible[0];
        if (!topEntry) {
          return;
        }

        const newYear = parseInt((topEntry.target as HTMLElement).dataset.year || "0");
        if (newYear !== (this as any).currentYear) {
          const fromStr = String((this as any).currentYear).padStart(4, "0");
          const toStr = String(newYear).padStart(4, "0");
          const digitWrappers = (this as any).yearEl.querySelectorAll(".digit-wrapper");

          for (let i = 0; i < 4; i++) {
            const fromDigit = parseInt(fromStr[i]);
            const toDigit = parseInt(toStr[i]);

            if (fromDigit !== toDigit) {
              (this as any).animateDigitRoll(digitWrappers[i], fromDigit, toDigit);
            }
          }

          (this as any).currentYear = newYear;
          (this as any).animateNavYearMenu(newYear);
        }
      },
      {
        rootMargin: "-20% 0px -80% 0px",
      }
    );

    (this as any).animateNavYearMenu((this as any).currentYear);
    (this as any).sections.forEach((section: Element) => (this as any).observer.observe(section));
  },

  destroyed() {
    if ((this as any).observer) {
      (this as any).observer.disconnect();
    }
    (this as any).initialized = false;
  },
};

export const HorizontalScrollFadeIn: Hook = {
  animateItems(duration: number) {
    const items = this.el.querySelectorAll("li");

    items.forEach((el: Element, i: number) => {
      if (duration) {
        setTimeout(() => {
          el.classList.add("opacity-100");
        }, i * duration);
      } else {
        el.classList.add("opacity-100");
      }
    });
  },

  mounted() {
    (this as any).handleWheel = (e: WheelEvent): void => {
      if (e.deltaY === 0) {
        return;
      }

      e.preventDefault();

      this.el.scrollBy({
        left: e.deltaY,
      });
    };

    this.el.addEventListener("wheel", (this as any).handleWheel, { passive: false });
    (this as any).animateItems(100);
  },

  updated() {
    (this as any).animateItems(0);
  },

  destroyed() {
    if ((this as any).handleWheel) {
      this.el.removeEventListener("wheel", (this as any).handleWheel);
    }
  },
};

export const AnimatePhotographyGallery: Hook = {
  mounted() {
    const [header] = document.getElementsByClassName("project-title");
    if (!header) {
      return;
    }

    setTimeout(() => {
      header.classList.replace("opacity-0", "opacity-100");
    }, 300);

    setTimeout(() => {
      this.el.classList.replace("opacity-0", "opacity-100");
      this.el.classList.replace("translate-y-8", "translate-y-0");
    }, 275);
  },
};

export const DarkModeSwitch: Hook = {
  mounted() {
    const html = document.documentElement;
    (this as any).clickHandler = (): void => {
      const isDark = html.classList.contains("dark");
      const newTheme = isDark ? "light" : "dark";

      html.classList.toggle("dark", newTheme === "dark");

      try {
        localStorage.setItem("theme", newTheme);
      } catch (e) {
        log("Could not persist theme preference:", e);
      }
    };
    this.el.addEventListener("click", (this as any).clickHandler);
  },

  destroyed() {
    if ((this as any).clickHandler) {
      this.el.removeEventListener("click", (this as any).clickHandler);
    }
  },
};

export const ParallaxHero: Hook = {
  mounted() {
    (this as any).ticking = false;
    (this as any).img = this.el.querySelector("img");

    (this as any).updateParallax = (): void => {
      if (!(this as any).img) {
        return;
      }
      const scrolled = window.pageYOffset;
      const speed = scrolled * 0.5;
      (this as any).img.style.transform = `translateY(${speed}px)`;
      (this as any).ticking = false;
    };

    (this as any).handleScroll = (): void => {
      if (!(this as any).ticking) {
        (this as any).ticking = true;
        requestAnimationFrame((this as any).updateParallax);
      }
    };

    window.addEventListener("scroll", (this as any).handleScroll, { passive: true });
  },

  disconnected() {
    window.removeEventListener("scroll", (this as any).handleScroll);
  },

  destroyed() {
    window.removeEventListener("scroll", (this as any).handleScroll);
    (this as any).img = null;
  },
};

export const SmoothScroll: Hook = {
  mounted() {
    const anchors = this.el.querySelectorAll('a[href^="#"]');

    (this as any).handleClick = (e: MouseEvent): void => {
      e.preventDefault();
      const href = (e.currentTarget as HTMLAnchorElement).getAttribute("href");
      if (!href) {
        return;
      }

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

    anchors.forEach((anchor) => {
      anchor.addEventListener("click", (this as any).handleClick);
    });

    (this as any).anchors = anchors;
  },

  destroyed() {
    if ((this as any).anchors) {
      (this as any).anchors.forEach((anchor: Element) => {
        anchor.removeEventListener("click", (this as any).handleClick);
      });
    }
  },
};

export const PhotoSortable: Hook = {
  async mounted() {
    log("PhotoSortable mounted", this.el);
    (this as any).sortable = null;
    try {
      await (this as any).initializeSortable();
    } catch (error) {
      log("PhotoSortable initialization failed:", error);
    }
  },

  async updated() {
    log("PhotoSortable updated", {
      reordering: (this.el as HTMLElement).dataset.reordering,
    });
    try {
      await (this as any).initializeSortable();
    } catch (error) {
      log("PhotoSortable re-initialization failed:", error);
    }
  },

  disconnected() {
    log("PhotoSortable disconnected");
    if ((this as any).sortable) {
      (this as any).sortable.destroy();
      (this as any).sortable = null;
    }
  },

  destroyed() {
    log("PhotoSortable destroyed");
    if ((this as any).sortable) {
      (this as any).sortable.destroy();
      (this as any).sortable = null;
    }
  },

  async initializeSortable() {
    const isReordering = (this.el as HTMLElement).dataset.reordering === "true";
    log("Initializing sortable, reordering:", isReordering);

    if ((this as any).sortable) {
      log("Destroying existing sortable");
      (this as any).sortable.destroy();
      (this as any).sortable = null;
    }

    if (isReordering) {
      log("Creating sortable instance");

      const SortableLib = await loadSortable();

      const items = this.el.querySelectorAll(".sortable-item");
      log("Found sortable items:", items.length);

      (this as any).sortable = SortableLib.create(this.el as HTMLElement, {
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

          const photoIds = Array.from(this.el.querySelectorAll<HTMLElement>("[data-photo-id]")).map(
            (el) => el.dataset.photoId
          );

          log("New order:", photoIds);

          this.pushEvent("reorder_photos", { photo_ids: photoIds });
        },
      });

      log("Sortable instance created:", (this as any).sortable);
    }
  },
};

export const RateLimitCountdown: Hook = {
  mounted() {
    const retryAfter = parseInt((this.el as HTMLElement).dataset.retryAfter || "0", 10);
    const display = document.getElementById("countdown-display");

    if (!display || !retryAfter) {
      return;
    }

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

    (this as any).interval = setInterval(() => {
      remaining--;

      if (remaining <= 0) {
        clearInterval((this as any).interval);
        window.location.reload();
      } else {
        updateDisplay();
      }
    }, 1000);
  },

  destroyed() {
    if ((this as any).interval) {
      clearInterval((this as any).interval);
    }
  },
};

export const MagicLinkExpiration: Hook = {
  mounted() {
    const expiresIn = parseInt((this.el as HTMLElement).dataset.expiresIn || "0", 10);
    const display = document.getElementById("magic-link-countdown");

    if (!display || !expiresIn) {
      return;
    }

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

    (this as any).interval = setInterval(() => {
      remaining--;

      if (remaining < 0) {
        clearInterval((this as any).interval);
      } else {
        updateDisplay();
      }
    }, 1000);
  },

  destroyed() {
    if ((this as any).interval) {
      clearInterval((this as any).interval);
    }
  },
};

export const InfiniteScroll: Hook = {
  mounted() {
    (this as any).pending = false;

    (this as any).observer = new IntersectionObserver(
      (entries) => {
        const target = entries[0];
        if (target.isIntersecting && !(this as any).pending) {
          (this as any).pending = true;
          this.pushEvent("load_more", {}, () => {
            (this as any).pending = false;
          });
        }
      },
      {
        root: null,
        rootMargin: "1200px",
        threshold: 0,
      }
    );

    (this as any).observer.observe(this.el);
  },

  destroyed() {
    if ((this as any).observer) {
      (this as any).observer.disconnect();
    }
  },
};
