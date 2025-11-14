import {
  animate,
  utils,
  createDraggable,
  createSpring,
  onScroll,
  stagger,
} from "animejs";
import Sortable from "sortablejs";

// Conditional logging: only log in development mode
const isDev =
  window.location.hostname === "localhost" ||
  window.location.hostname === "127.0.0.1";
const log = isDev ? console.log.bind(console) : () => {};

export const AnimateThis = {
  mounted() {
    const [$logo] = utils.$(".logo.js");
    const [$button] = utils.$("#button");
    let rotations = 0;

    // Created a bounce animation loop
    animate(".logo.js", {
      scale: [
        { to: 1.1, ease: "inOut(3)", duration: 200 },
        { to: 1, ease: createSpring({ stiffness: 300 }) },
      ],
      loop: true,
      loopDelay: 250,
    });

    // Make the logo draggable around its center
    createDraggable(".logo.js", {
      container: [0, 0, 0, 0],
      releaseEase: createSpring({ stiffness: 200 }),
    });

    // Animate logo rotation on click
    const rotateLogo = () => {
      rotations++;
      $button.innerText = `rotations: ${rotations}`;
      animate($logo, {
        rotate: rotations * 360,
        ease: "out(4)",
        duration: 1500,
      });
    };

    $button.addEventListener("click", rotateLogo);
  },
};

export const AnimateGallery = {
  mounted() {
    const debug = false;
    const images = utils.$(".gallery__image");
    const container = utils.$("follower");
    let i = 0;

    images.forEach(($image) => {
      animate($image, {
        opacity: [0, 1],
        translateY: [100, 0],
        ease: "out(3)",
        duration: 2000,
        delay: i * 120,
        autoplay: onScroll({
          target: $image,
          container: container, // $image.parentNode,
          debug,
        }),
      });

      $image.addEventListener(
        "mouseenter",
        function (e) {
          hover(e.target);
        },
        false,
      );

      $image.addEventListener(
        "mouseleave",
        function (e) {
          unhover(e.target);
        },
        false,
      );

      i++;
    });

    function hover(el) {
      animateImage(el, 1, 0.4);
    }

    function unhover(el) {
      animateImage(el, 0.4, 1);
    }

    function animateImage(el, from, to) {
      images
        .filter(function (item) {
          return item !== el;
        })
        .forEach(($image) => {
          animate($image, {
            opacity: [from, to],
            ease: "out(6)",
            duration: 500,
          });
        });
    }
  },
};

export const AnimatePath = {
  mounted() {
    const [$path] = utils.$("#path-zigzag");

    const length = $path.getTotalLength();
    $path.style.strokeDasharray = length;
    $path.style.strokeDashoffset = length;

    animate($path, {
      strokeDashoffset: [length, 0],
      duration: 2200,
      delay: 300,
      easing: "easeInOutSine",
    });
  },
};

export const AnimateTimelineScroll = {
  mounted() {
    const timeline = this.el;
    const container = this.el.closest("#timeline_container") || window;

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
        rootMargin: "-20% 0px -50% 0px", // zone d’activation centrée verticalement
      },
    );

    observer.observe(timeline);
    this.observer = observer;
  },

  destroyed() {
    this.observer?.disconnect?.();
    this.disableScrollSync(window); // clean up
  },

  enableScrollSync(timeline, container) {
    this.scrollHandler = (e) => {
      const atStart = timeline.scrollLeft === 0;
      const atEnd =
        timeline.scrollLeft + timeline.clientWidth >= timeline.scrollWidth - 1;

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
    const modal = document.getElementById("image-modal");
    const modalImage = document.getElementById("modal-image");
    const backdrop = document.getElementById("modal-backdrop");
    const transitionDuration = 150;

    document.querySelectorAll(".gallery__image img").forEach((img) => {
      img.addEventListener("click", () => {
        const src = img.getAttribute("data-full_image_src") || img.src;
        modalImage.src = src;
        modalImage.alt = img.alt || "";
        modal.classList.remove("hidden");
        modal.classList.add("flex");

        // Start zoom-in animation
        setTimeout(() => {
          modalImage.classList.remove("scale-50", "opacity-0");
          modalImage.classList.add("scale-100", "opacity-100");
        }, transitionDuration);
      });
    });

    // Close modal on click outside or ESC
    backdrop.addEventListener("click", () => {
      modalImage.classList.remove("scale-100", "opacity-100");
      modalImage.classList.add("scale-50", "opacity-0");

      setTimeout(() => {
        modal.classList.add("hidden");
        modal.classList.remove("flex");
        modalImage.src = "";
      }, transitionDuration);
    });

    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        modal.classList.add("hidden");
        modal.classList.remove("flex");
        modalImage.src = "";
      }
    });
  },
};

export const YearTrigger = {
  mounted() {
    if (window.__yearObserverInitialized) return;
    window.__yearObserverInitialized = true;

    const yearEl = document.getElementById("timeline-year");
    const navLinks = document.querySelectorAll("[data-anchor-year]");
    const sections = document.querySelectorAll("[data-year]");
    let currentYear = parseInt(
      [...yearEl.querySelectorAll(".digit")].map((d) => d.textContent).join(""),
    );

    function animateNavYearMenu(activeYear) {
      navLinks.forEach((link) => {
        const isActive = parseInt(link.dataset.year) === activeYear;
        link.classList.toggle("opacity-100", isActive);
        link.classList.toggle("opacity-60", !isActive);
        link.classList.toggle("font-semibold", isActive);
      });
    }

    function animateDigitRoll(digitWrapper, fromDigit, toDigit) {
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

      animate(fromEl, {
        translateY: fromElYTranslation,
        opacity: [1, 0],
        duration: 500,
        easing: "easeInOutCubic",
      });

      animate(toEl, {
        translateY: toElYTranslation,
        opacity: [0, 1],
        duration: 500,
        easing: "easeInOutCubic",
        // complete: () => {
        //   digitWrapper.innerHTML = `
        //     <span class="digit inline-block w-full text-center">${toDigit}</span>
        //   `;
        // },
      });
    }

    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort(
            (a, b) =>
              Math.abs(a.boundingClientRect.top) -
              Math.abs(b.boundingClientRect.top),
          );

        const topEntry = visible[0];
        if (!topEntry) return;

        const newYear = parseInt(topEntry.target.dataset.year);
        if (newYear !== currentYear) {
          const fromStr = String(currentYear).padStart(4, "0");
          const toStr = String(newYear).padStart(4, "0");
          const digitWrappers = yearEl.querySelectorAll(".digit-wrapper");

          for (let i = 0; i < 4; i++) {
            const fromDigit = parseInt(fromStr[i]);
            const toDigit = parseInt(toStr[i]);

            if (fromDigit != toDigit) {
              animateDigitRoll(digitWrappers[i], fromDigit, toDigit);
            }
          }

          currentYear = newYear;

          // Update navbar highlight
          animateNavYearMenu(newYear);
        }
      },
      {
        rootMargin: "-20% 0px -80% 0px",
      },
    );

    animateNavYearMenu(currentYear);
    sections.forEach((section) => observer.observe(section));
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
      if (e.deltaY === 0) return;

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
    [header] = document.getElementsByClassName("project-title");

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
    this.el.addEventListener("click", () => {
      const isDark = html.classList.contains("dark");
      const newTheme = isDark ? "light" : "dark";

      html.classList.toggle("dark", newTheme === "dark");
      localStorage.setItem("theme", newTheme);
    });
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
        target = document.querySelector(
          `[data-album-year-anchor="${yearAnchor}"]`,
        );
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
  mounted() {
    log("PhotoSortable mounted", this.el);
    this.sortable = null;
    this.initializeSortable();
  },

  updated() {
    log("PhotoSortable updated", {
      reordering: this.el.dataset.reordering,
    });
    // Re-initialize sortable when reordering mode changes
    this.initializeSortable();
  },

  destroyed() {
    log("PhotoSortable destroyed");
    if (this.sortable) {
      this.sortable.destroy();
    }
  },

  initializeSortable() {
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
          const photoIds = Array.from(
            this.el.querySelectorAll("[data-photo-id]"),
          ).map((el) => el.dataset.photoId);

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

    if (!display || !retryAfter) return;

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

    if (!display || !expiresIn) return;

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
        display.parentElement.parentElement.parentElement.classList.remove(
          "bg-green-50",
        );
        display.parentElement.parentElement.parentElement.classList.add(
          "bg-red-50",
        );
        display.parentElement.querySelector("p").innerHTML =
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
      },
    );

    this.observer.observe(this.el);
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
  },
};
