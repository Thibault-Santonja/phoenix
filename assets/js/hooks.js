// Conditional logging: only log in development mode
const isDev = window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1";
const log = isDev ? console.log.bind(console) : () => {};

// Lazy-loaded module cache to avoid multiple imports
let animeModule = null;
let sortableModule = null;

// Lazy-load animejs (only when first needed)
const loadAnimejs = async () => {
  if (!animeModule) {
    animeModule = await import("animejs");
  }
  return animeModule;
};

// Lazy-load sortablejs (only when first needed)
const loadSortable = async () => {
  if (!sortableModule) {
    sortableModule = await import("sortablejs");
  }
  return sortableModule.default;
};

export const AnimateThis = {
  async mounted() {
    try {
      const { animate, utils, createDraggable, createSpring } = await loadAnimejs();

      const [$logo] = utils.$(".logo.js");
      const [$button] = utils.$("#button");
      this.rotations = 0;
      this.$logo = $logo;
      this.$button = $button;
      this.animate = animate;

      // Created a bounce animation loop
      this.bounceAnimation = animate(".logo.js", {
        scale: [
          { to: 1.1, ease: "inOut(3)", duration: 200 },
          { to: 1, ease: createSpring({ stiffness: 300 }) },
        ],
        loop: true,
        loopDelay: 250,
      });

      // Make the logo draggable around its center
      this.draggable = createDraggable(".logo.js", {
        container: [0, 0, 0, 0],
        releaseEase: createSpring({ stiffness: 200 }),
      });

      // Animate logo rotation on click
      this.rotateLogo = () => {
        this.rotations++;
        this.$button.innerText = `rotations: ${this.rotations}`;
        this.animate(this.$logo, {
          rotate: this.rotations * 360,
          ease: "out(4)",
          duration: 1500,
        });
      };

      if ($button) {
        $button.addEventListener("click", this.rotateLogo);
      }
    } catch (error) {
      log("AnimateThis initialization failed:", error);
    }
  },

  disconnected() {
    // Pause animations during navigation
    if (this.bounceAnimation) {
      this.bounceAnimation.pause();
    }
  },

  destroyed() {
    if (this.$button && this.rotateLogo) {
      this.$button.removeEventListener("click", this.rotateLogo);
    }
    if (this.bounceAnimation) {
      this.bounceAnimation.pause();
      this.bounceAnimation = null;
    }
    if (this.draggable && typeof this.draggable.destroy === "function") {
      this.draggable.destroy();
      this.draggable = null;
    }
  },
};

export const AnimateGallery = {
  async mounted() {
    this.eventHandlers = [];
    this.images = [];

    try {
      const { animate, utils, onScroll } = await loadAnimejs();

      const debug = false;
      this.images = utils.$(".gallery__image");
      const [container] = utils.$(".follower");

      const animateImage = (el, from, to) => {
        this.images
          .filter((item) => item !== el)
          .forEach(($image) => {
            animate($image, {
              opacity: [from, to],
              ease: "out(6)",
              duration: 500,
            });
          });
      };

      const hover = (el) => animateImage(el, 1, 0.4);
      const unhover = (el) => animateImage(el, 0.4, 1);

      this.images.forEach(($image, i) => {
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

        const mouseenterHandler = (e) => hover(e.target);
        const mouseleaveHandler = (e) => unhover(e.target);

        $image.addEventListener("mouseenter", mouseenterHandler, false);
        $image.addEventListener("mouseleave", mouseleaveHandler, false);

        this.eventHandlers.push({
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
    // Clean up event handlers during navigation
    this.cleanupEventHandlers();
  },

  destroyed() {
    this.cleanupEventHandlers();
  },

  cleanupEventHandlers() {
    if (this.eventHandlers) {
      this.eventHandlers.forEach(({ element, mouseenter, mouseleave }) => {
        element.removeEventListener("mouseenter", mouseenter);
        element.removeEventListener("mouseleave", mouseleave);
      });
      this.eventHandlers = [];
    }
  },
};

export const AnimatePath = {
  async mounted() {
    this.animation = null;

    try {
      const { animate, utils } = await loadAnimejs();

      const [$path] = utils.$("#path-zigzag");
      if (!$path) {
        return;
      }

      this.$path = $path;
      const length = $path.getTotalLength();
      $path.style.strokeDasharray = length;
      $path.style.strokeDashoffset = length;

      this.animation = animate($path, {
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
    if (this.animation) {
      this.animation.pause();
    }
  },

  destroyed() {
    if (this.animation) {
      this.animation.pause();
      this.animation = null;
    }
  },
};

export const AnimateTimelineScroll = {
  mounted() {
    const timeline = this.el;
    const container = this.el.closest("#timeline_container") || window;
    this.scrollContainer = container;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          // animate(timeline.querySelectorAll(".event"), {
          //   opacity: [0, 1],
          //   translateY: [30, 0],
          //   delay: 100,
          //   duration: 800,
          //   easing: "easeOutQuad",
          // });
          this.enableScrollSync(timeline, container);
        } else {
          this.disableScrollSync(container);
        }
      },
      {
        root: null,
        // threshold: 0.2, // 20% visible
        rootMargin: "-20% 0px -50% 0px", // zone d'activation centrée verticalement
      }
    );

    observer.observe(timeline);
    this.observer = observer;
  },

  disconnected() {
    // Pause scroll sync during navigation
    this.disableScrollSync(this.scrollContainer || window);
  },

  destroyed() {
    this.observer?.disconnect?.();
    this.disableScrollSync(this.scrollContainer || window);
    this.scrollContainer = null;
  },

  enableScrollSync(timeline, container) {
    this.scrollHandler = (e) => {
      const atStart = timeline.scrollLeft === 0;
      const atEnd = timeline.scrollLeft + timeline.clientWidth >= timeline.scrollWidth - 1;

      const goingUp = e.deltaY < 0;
      const goingDown = e.deltaY > 0;

      // Allow vertical scroll only at edges
      const allowVerticalScroll = (goingUp && atStart) || (goingDown && atEnd);

      if (!allowVerticalScroll) {
        timeline.scrollLeft += e.deltaY;
        e.preventDefault();
      }
    };

    container.addEventListener("wheel", this.scrollHandler, { passive: false });
  },

  disableScrollSync(container) {
    if (this.scrollHandler) {
      container.removeEventListener("wheel", this.scrollHandler);
      this.scrollHandler = null;
    }
  },
};

export const GalleryModal = {
  mounted() {
    this.modal = document.getElementById("image-modal");
    this.modalImage = document.getElementById("modal-image");
    this.backdrop = document.getElementById("modal-backdrop");
    this.transitionDuration = 150;
    this.imageClickHandlers = [];

    document.querySelectorAll(".gallery__image img").forEach((img) => {
      const clickHandler = () => {
        const src = img.getAttribute("data-full_image_src") || img.src;
        this.modalImage.src = src;
        this.modalImage.alt = img.alt || "";
        this.modal.classList.remove("hidden");
        this.modal.classList.add("flex");

        // Start zoom-in animation
        setTimeout(() => {
          this.modalImage.classList.remove("scale-50", "opacity-0");
          this.modalImage.classList.add("scale-100", "opacity-100");
        }, this.transitionDuration);
      };

      img.addEventListener("click", clickHandler);
      this.imageClickHandlers.push({ element: img, handler: clickHandler });
    });

    // Close modal on click outside
    this.backdropClickHandler = () => {
      this.modalImage.classList.remove("scale-100", "opacity-100");
      this.modalImage.classList.add("scale-50", "opacity-0");

      setTimeout(() => {
        this.modal.classList.add("hidden");
        this.modal.classList.remove("flex");
        this.modalImage.src = "";
      }, this.transitionDuration);
    };

    if (this.backdrop) {
      this.backdrop.addEventListener("click", this.backdropClickHandler);
    }

    // Close modal on ESC key
    this.keydownHandler = (e) => {
      if (e.key === "Escape") {
        this.modal.classList.add("hidden");
        this.modal.classList.remove("flex");
        this.modalImage.src = "";
      }
    };

    window.addEventListener("keydown", this.keydownHandler);
  },

  destroyed() {
    // Clean up image click handlers
    this.imageClickHandlers.forEach(({ element, handler }) => {
      element.removeEventListener("click", handler);
    });

    // Clean up backdrop click handler
    if (this.backdrop && this.backdropClickHandler) {
      this.backdrop.removeEventListener("click", this.backdropClickHandler);
    }

    // Clean up keydown handler
    if (this.keydownHandler) {
      window.removeEventListener("keydown", this.keydownHandler);
    }
  },
};

export const YearTrigger = {
  async mounted() {
    // Use instance-level flag instead of global to allow proper cleanup
    if (this.initialized) {
      return;
    }
    this.initialized = true;

    this.yearEl = document.getElementById("timeline-year");
    if (!this.yearEl) {
      return;
    }

    try {
      // Lazy-load animejs only when needed
      const { animate } = await loadAnimejs();
      this.animate = animate;
    } catch (error) {
      log("YearTrigger: Failed to load animejs:", error);
      return;
    }

    this.navLinks = document.querySelectorAll("[data-anchor-year]");
    this.sections = document.querySelectorAll("[data-year]");
    this.currentYear = parseInt(
      [...this.yearEl.querySelectorAll(".digit")].map((d) => d.textContent).join("")
    );

    // Use arrow functions to preserve 'this' context
    this.animateNavYearMenu = (activeYear) => {
      this.navLinks.forEach((link) => {
        const isActive = parseInt(link.dataset.year) === activeYear;
        link.classList.toggle("opacity-100", isActive);
        link.classList.toggle("opacity-60", !isActive);
        link.classList.toggle("font-semibold", isActive);
      });
    };

    this.animateDigitRoll = (digitWrapper, fromDigit, toDigit) => {
      digitWrapper.innerHTML = ""; // Clear previous
      const sign = fromDigit > toDigit;
      const toElY = sign ? "translateY(100%)" : "translateY(-100%)";
      const fromElYTranslation = sign ? ["0%", "-100%"] : ["0%", "100%"];
      const toElYTranslation = sign ? ["100%", "0%"] : ["-100%", "0%"];

      const fromEl = document.createElement("div");
      fromEl.textContent = fromDigit;
      fromEl.style.position = "absolute";
      fromEl.style.top = "0";
      fromEl.style.left = "0";
      fromEl.style.right = "0";
      fromEl.style.textAlign = "center";
      fromEl.style.opacity = "1";
      fromEl.style.transform = "translateY(0%)";

      const toEl = document.createElement("div");
      toEl.textContent = toDigit;
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

      this.animate(fromEl, {
        translateY: fromElYTranslation,
        opacity: [1, 0],
        duration: 500,
        easing: "easeInOutCubic",
      });

      this.animate(toEl, {
        translateY: toElYTranslation,
        opacity: [0, 1],
        duration: 500,
        easing: "easeInOutCubic",
      });
    };

    this.observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => Math.abs(a.boundingClientRect.top) - Math.abs(b.boundingClientRect.top));

        const topEntry = visible[0];
        if (!topEntry) {
          return;
        }

        const newYear = parseInt(topEntry.target.dataset.year);
        if (newYear !== this.currentYear) {
          const fromStr = String(this.currentYear).padStart(4, "0");
          const toStr = String(newYear).padStart(4, "0");
          const digitWrappers = this.yearEl.querySelectorAll(".digit-wrapper");

          for (let i = 0; i < 4; i++) {
            const fromDigit = parseInt(fromStr[i]);
            const toDigit = parseInt(toStr[i]);

            if (fromDigit !== toDigit) {
              this.animateDigitRoll(digitWrappers[i], fromDigit, toDigit);
            }
          }

          this.currentYear = newYear;

          // Update navbar highlight
          this.animateNavYearMenu(newYear);
        }
      },
      {
        rootMargin: "-20% 0px -80% 0px",
      }
    );

    this.animateNavYearMenu(this.currentYear);
    this.sections.forEach((section) => this.observer.observe(section));
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
    this.initialized = false;
  },
};

export const HorizontalScrollFadeIn = {
  animateItems(duration) {
    const items = this.el.querySelectorAll("li");

    items.forEach((el, i) => {
      if (duration) {
        setTimeout(() => {
          el.classList.add("opacity-100");
        }, i * duration); // duration increasing between each appearing
      } else {
        el.classList.add("opacity-100");
      }
    });
  },

  mounted() {
    this.handleWheel = (e) => {
      if (e.deltaY === 0) {
        return;
      }

      // prevent the page from scrolling vertically
      e.preventDefault();

      // Scroll horizontally
      this.el.scrollBy({
        left: e.deltaY,
        // behavior: "smooth",
      });
    };

    this.el.addEventListener("wheel", this.handleWheel, { passive: false });
    this.animateItems(100);
  },

  updated() {
    this.animateItems(0);
  },

  destroyed() {
    if (this.handleWheel) {
      this.el.removeEventListener("wheel", this.handleWheel);
    }
  },
};

export const AnimatePhotographyGallery = {
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

export const DarkModeSwitch = {
  mounted() {
    const html = document.documentElement;
    this.clickHandler = () => {
      const isDark = html.classList.contains("dark");
      const newTheme = isDark ? "light" : "dark";

      html.classList.toggle("dark", newTheme === "dark");

      // Safely persist theme preference (localStorage may throw if quota exceeded or disabled)
      try {
        localStorage.setItem("theme", newTheme);
      } catch (e) {
        // Graceful degradation: theme still toggles, just won't persist
        log("Could not persist theme preference:", e);
      }
    };
    this.el.addEventListener("click", this.clickHandler);
  },

  destroyed() {
    if (this.clickHandler) {
      this.el.removeEventListener("click", this.clickHandler);
    }
  },
};

export const ParallaxHero = {
  mounted() {
    this.handleScroll = () => {
      const scrolled = window.pageYOffset;
      const img = this.el.querySelector("img");
      if (img) {
        const speed = scrolled * 0.5;
        img.style.transform = `translateY(${speed}px)`;
      }
    };

    window.addEventListener("scroll", this.handleScroll, { passive: true });
  },

  destroyed() {
    window.removeEventListener("scroll", this.handleScroll);
  },
};

export const SmoothScroll = {
  mounted() {
    // Handle smooth scroll for all anchor links within this element
    const anchors = this.el.querySelectorAll('a[href^="#"]');

    this.handleClick = (e) => {
      e.preventDefault();
      const href = e.currentTarget.getAttribute("href");

      // Try to find element by ID first (standard anchor)
      let target = document.querySelector(href);

      // If not found and it's a year anchor (#year-XXXX), find first album with that year
      if (!target && href.startsWith("#year-")) {
        const yearAnchor = href.substring(1); // Remove the #
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
      anchor.addEventListener("click", this.handleClick);
    });

    this.anchors = anchors;
  },

  destroyed() {
    if (this.anchors) {
      this.anchors.forEach((anchor) => {
        anchor.removeEventListener("click", this.handleClick);
      });
    }
  },
};

export const PhotoSortable = {
  async mounted() {
    log("PhotoSortable mounted", this.el);
    this.sortable = null;
    try {
      await this.initializeSortable();
    } catch (error) {
      log("PhotoSortable initialization failed:", error);
      // Graceful degradation - photos remain visible but not sortable
    }
  },

  async updated() {
    log("PhotoSortable updated", {
      reordering: this.el.dataset.reordering,
    });
    // Re-initialize sortable when reordering mode changes
    try {
      await this.initializeSortable();
    } catch (error) {
      log("PhotoSortable re-initialization failed:", error);
    }
  },

  disconnected() {
    // Called during LiveView navigation - cleanup but don't fully destroy
    log("PhotoSortable disconnected");
    if (this.sortable) {
      this.sortable.destroy();
      this.sortable = null;
    }
  },

  destroyed() {
    log("PhotoSortable destroyed");
    if (this.sortable) {
      this.sortable.destroy();
      this.sortable = null;
    }
  },

  async initializeSortable() {
    const isReordering = this.el.dataset.reordering === "true";
    log("Initializing sortable, reordering:", isReordering);

    // Destroy existing sortable instance
    if (this.sortable) {
      log("Destroying existing sortable");
      this.sortable.destroy();
      this.sortable = null;
    }

    // Only create sortable if in reordering mode
    if (isReordering) {
      log("Creating sortable instance");

      // Lazy-load Sortable only when needed
      const Sortable = await loadSortable();

      const items = this.el.querySelectorAll(".sortable-item");
      log("Found sortable items:", items.length);

      this.sortable = Sortable.create(this.el, {
        animation: 150,
        draggable: ".sortable-item",
        handle: ".sortable-item",
        ghostClass: "sortable-ghost",
        chosenClass: "sortable-chosen",
        dragClass: "sortable-drag",
        forceFallback: false, // Changed to false to try native drag
        fallbackClass: "sortable-fallback",
        fallbackOnBody: true,
        swapThreshold: 0.65,
        direction: "horizontal", // Added for grid support

        onStart: (evt) => {
          log("Drag started", evt.oldIndex);
        },

        onEnd: (evt) => {
          log("Drag ended", evt.oldIndex, "->", evt.newIndex);

          // Get all photo IDs in the new order
          const photoIds = Array.from(this.el.querySelectorAll("[data-photo-id]")).map(
            (el) => el.dataset.photoId
          );

          log("New order:", photoIds);

          // Send the new order to the server
          this.pushEvent("reorder_photos", { photo_ids: photoIds });
        },
      });

      log("Sortable instance created:", this.sortable);
    }
  },
};

export const RateLimitCountdown = {
  mounted() {
    const retryAfter = parseInt(this.el.dataset.retryAfter, 10);
    const display = document.getElementById("countdown-display");

    if (!display || !retryAfter) {
      return;
    }

    let remaining = retryAfter;

    const updateDisplay = () => {
      const minutes = Math.floor(remaining / 60);
      const seconds = remaining % 60;

      if (minutes > 0) {
        display.textContent = `${minutes}min ${seconds}s`;
      } else {
        display.textContent = `${seconds}s`;
      }
    };

    updateDisplay();

    this.interval = setInterval(() => {
      remaining--;

      if (remaining <= 0) {
        clearInterval(this.interval);
        window.location.reload();
      } else {
        updateDisplay();
      }
    }, 1000);
  },

  destroyed() {
    if (this.interval) {
      clearInterval(this.interval);
    }
  },
};

export const MagicLinkExpiration = {
  mounted() {
    const expiresIn = parseInt(this.el.dataset.expiresIn, 10);
    const display = document.getElementById("magic-link-countdown");

    if (!display || !expiresIn) {
      return;
    }

    let remaining = expiresIn;

    const updateDisplay = () => {
      const minutes = Math.floor(remaining / 60);
      const seconds = remaining % 60;

      if (minutes > 0) {
        display.textContent = `${minutes}min ${seconds}s`;
      } else if (seconds > 0) {
        display.textContent = `${seconds}s`;
      } else {
        display.textContent = "expiré";
        display.parentElement.parentElement.parentElement.classList.remove("bg-green-50");
        display.parentElement.parentElement.parentElement.classList.add("bg-red-50");
        display.parentElement.querySelector("p").textContent =
          "Le lien de connexion a expiré. Veuillez demander un nouveau lien.";
      }
    };

    updateDisplay();

    this.interval = setInterval(() => {
      remaining--;

      if (remaining < 0) {
        clearInterval(this.interval);
      } else {
        updateDisplay();
      }
    }, 1000);
  },

  destroyed() {
    if (this.interval) {
      clearInterval(this.interval);
    }
  },
};

export const InfiniteScroll = {
  mounted() {
    this.pending = false;

    this.observer = new IntersectionObserver(
      (entries) => {
        const target = entries[0];
        if (target.isIntersecting && !this.pending) {
          this.pending = true;
          this.pushEvent("load_more", {}, () => {
            this.pending = false;
          });
        }
      },
      {
        root: null,
        // Trigger 1200px before reaching the marker (approximately 2-3 albums)
        // Similar to Instagram/Twitter strategy for smooth infinite scroll
        rootMargin: "1200px",
        threshold: 0,
      }
    );

    this.observer.observe(this.el);
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
  },
};
