const Carousel = {
  mounted() {
    // Initialize properties to safe defaults to prevent cleanup errors
    this.eventHandlers = {};
    this.prevButtons = [];
    this.nextButtons = [];
    this.indicators = [];
    this.indicatorClickHandlers = [];
    this._tornDown = false;

    try {
      this.initializeElements();
      this.setupState();
      this.setupEventListeners();
      this.setupImageLoadHandling();
      this.setupKeyboardNavigation();
      this.setupTouchNavigation();
      this.setupResizeHandling();
      this.showInitialSlide();
      this.setupAutoplay();
      this.setupIntersectionObserver();

      this.handleEvent("select-slide", ({ index }) => this.selectSlide(index));
    } catch (error) {
      console.error(`Carousel initialization error: ${error.message}`);
    }
  },

  disconnected() {
    this.teardown();
  },

  destroyed() {
    this.teardown();
  },

  teardown() {
    // Prevent double teardown
    if (this._tornDown) return;
    this._tornDown = true;

    // Clean up event listeners
    this.cleanupEventListeners();

    // Stop autoplay and clear timer
    this.stopAutoplay();

    // Clear user interaction timeout
    if (this.userInteractionTimeout) {
      clearTimeout(this.userInteractionTimeout);
      this.userInteractionTimeout = null;
    }

    // Clear resize timeout
    if (this.resizeTimeout) {
      clearTimeout(this.resizeTimeout);
      this.resizeTimeout = null;
    }

    // Disconnect intersection observer
    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect();
      this.intersectionObserver = null;
    }
  },

  initializeElements() {
    this.slides = this.el.querySelectorAll(".slide");
    if (!this.slides.length) {
      throw new Error("No slides found in carousel");
    }

    this.indicators = this.el.querySelectorAll(".carousel-indicator");
    this.prevButtons = [
      this.el.querySelector(`#${this.el.id}-carousel-prev`),
    ].filter(Boolean);
    this.nextButtons = [
      this.el.querySelector(`#${this.el.id}-carousel-next`),
    ].filter(Boolean);
    this.imageLoaders = this.el.querySelectorAll(
      `[id^="${this.el.id}-carousel-slide-image-"]`,
    );

    this.prevButtons.forEach((button) => {
      if (!button.getAttribute("aria-label")) {
        button.setAttribute("aria-label", "Previous slide");
      }
    });

    this.nextButtons.forEach((button) => {
      if (!button.getAttribute("aria-label")) {
        button.setAttribute("aria-label", "Next slide");
      }
    });

    if (!this.el.getAttribute("role")) {
      this.el.setAttribute("role", "region");
      this.el.setAttribute("aria-roledescription", "carousel");
    }

    // Set sanitized ARIA attributes for each slide
    this.slides.forEach((slide, index) => {
      slide.setAttribute("role", "group");
      slide.setAttribute("aria-roledescription", "slide");
      slide.setAttribute(
        "aria-label",
        `Slide ${this.sanitizeNumber(index) + 1} of ${this.sanitizeNumber(this.slides.length)}`,
      );
    });
  },

  setupState() {
    // Validate active index strictly
    const rawIndex = this.el.dataset.activeIndex;
    this.activeIndex = /^\d+$/.test(rawIndex)
      ? Math.max(1, Math.min(parseInt(rawIndex, 10), this.slides.length))
      : 1;

    this.totalSlides = this.slides.length;

    // Validate class names to prevent injection
    this.classes = {
      activeSlide:
        this.sanitizeClassName(this.el.dataset.activeSlideClass) ||
        "active-slide z-10",
      hiddenSlide:
        this.sanitizeClassName(this.el.dataset.hiddenSlideClass) || "opacity-0",
      activeIndicator:
        this.sanitizeClassName(this.el.dataset.activeIndicatorClass) ||
        "active-indicator",
    };

    // Validate boolean values
    this.shouldAutoplay = this.el.dataset.autoplay === "true";

    // Validate numeric values and add a maximum for safety
    const rawInterval = parseInt(this.el.dataset.autoplayInterval, 10);
    this.autoplayInterval =
      !isNaN(rawInterval) && rawInterval > 0
        ? Math.min(rawInterval, 30000)
        : 5000;

    this.autoplayTimer = null;
    this.userInteractionDelay = 7000;
    this.userInteractionTimeout = null;
    this.isHovered = false;
    this.isTouching = false;
    this.touchStartX = null;
    this.touchEndX = null;
    this.minSwipeDistance = 50;
  },

  setupEventListeners() {
    this.eventHandlers = {
      prevClick: (e) => {
        this.handleUserInteraction();
        this.handlePrevClick(e);
      },
      nextClick: (e) => {
        this.handleUserInteraction();
        this.handleNextClick(e);
      },
      indicatorClick: (index) => {
        this.handleUserInteraction();
        this.handleIndicatorClick(index + 1);
      },
      mouseEnter: () => {
        this.isHovered = true;
        if (this.shouldAutoplay && this.el.dataset.pauseOnHover !== "false") {
          this.stopAutoplay();
        }
      },
      mouseLeave: () => {
        this.isHovered = false;
        if (
          this.shouldAutoplay &&
          !this.isTouching &&
          this.el.dataset.pauseOnHover !== "false"
        ) {
          this.startAutoplay();
        }
      },
      touchStart: (e) => {
        this.isTouching = true;
        this.touchStartX = e.touches[0].clientX;
        if (this.shouldAutoplay) {
          this.stopAutoplay();
        }
      },
      touchMove: (e) => {
        if (!this.isTouching) return;
        this.touchEndX = e.touches[0].clientX;
      },
      touchEnd: () => {
        this.isTouching = false;
        this.handleSwipe();
        // Autoplay resumption is handled by handleUserInteraction() in handleSwipe()
        // to respect the same userInteractionDelay cooldown as button/keyboard interactions
      },
      keyDown: (e) => this.handleKeyDown(e),
      resize: () => this.handleResize(),
    };

    this.prevButtons.forEach((button) => {
      button?.addEventListener("click", this.eventHandlers.prevClick);
    });

    this.nextButtons.forEach((button) => {
      button?.addEventListener("click", this.eventHandlers.nextClick);
    });

    this.indicatorClickHandlers = [];
    this.indicators?.forEach((indicator, index) => {
      const handler = () => this.eventHandlers.indicatorClick(index);
      this.indicatorClickHandlers.push(handler);
      indicator.addEventListener("click", handler);
    });

    if (this.el.dataset.pauseOnHover !== "false") {
      this.el.addEventListener("mouseenter", this.eventHandlers.mouseEnter);
      this.el.addEventListener("mouseleave", this.eventHandlers.mouseLeave);
    }
  },

  cleanupEventListeners() {
    // Guard against missing handlers or button arrays/NodeLists
    // Use forEach support check to handle both Array and NodeList
    if (
      this.prevButtons &&
      typeof this.prevButtons.forEach === "function" &&
      this.eventHandlers?.prevClick
    ) {
      this.prevButtons.forEach((button) => {
        button?.removeEventListener("click", this.eventHandlers.prevClick);
      });
    }

    if (
      this.nextButtons &&
      typeof this.nextButtons.forEach === "function" &&
      this.eventHandlers?.nextClick
    ) {
      this.nextButtons.forEach((button) => {
        button?.removeEventListener("click", this.eventHandlers.nextClick);
      });
    }

    // indicators is a NodeList from querySelectorAll, not an Array
    if (
      this.indicators &&
      typeof this.indicators.forEach === "function" &&
      Array.isArray(this.indicatorClickHandlers)
    ) {
      this.indicators.forEach((indicator, index) => {
        if (this.indicatorClickHandlers[index]) {
          indicator?.removeEventListener(
            "click",
            this.indicatorClickHandlers[index],
          );
        }
      });
    }

    if (this.eventHandlers?.mouseEnter) {
      this.el.removeEventListener("mouseenter", this.eventHandlers.mouseEnter);
    }
    if (this.eventHandlers?.mouseLeave) {
      this.el.removeEventListener("mouseleave", this.eventHandlers.mouseLeave);
    }

    if (this.eventHandlers?.keyDown) {
      document.removeEventListener("keydown", this.eventHandlers.keyDown);
    }
    if (this.eventHandlers?.resize) {
      window.removeEventListener("resize", this.eventHandlers.resize);
    }

    if (this.eventHandlers?.touchStart) {
      this.el.removeEventListener("touchstart", this.eventHandlers.touchStart);
    }
    if (this.eventHandlers?.touchMove) {
      this.el.removeEventListener("touchmove", this.eventHandlers.touchMove);
    }
    if (this.eventHandlers?.touchEnd) {
      this.el.removeEventListener("touchend", this.eventHandlers.touchEnd);
    }
  },

  setupKeyboardNavigation() {
    document.addEventListener("keydown", this.eventHandlers.keyDown);
  },

  handleKeyDown(e) {
    const hasFocus =
      this.el.contains(document.activeElement) ||
      document.activeElement === this.el;

    if (!hasFocus) return;

    if (e.key === "ArrowLeft" || e.key === "ArrowUp") {
      this.handleUserInteraction();
      this.handlePrevClick(e);
      e.preventDefault();
    } else if (e.key === "ArrowRight" || e.key === "ArrowDown") {
      this.handleUserInteraction();
      this.handleNextClick(e);
      e.preventDefault();
    }
  },

  setupTouchNavigation() {
    this.el.addEventListener("touchstart", this.eventHandlers.touchStart, {
      passive: true,
    });
    this.el.addEventListener("touchmove", this.eventHandlers.touchMove, {
      passive: true,
    });
    this.el.addEventListener("touchend", this.eventHandlers.touchEnd);
  },

  handleSwipe() {
    if (this.touchStartX == null || this.touchEndX == null) return;

    const swipeDistance = this.touchEndX - this.touchStartX;

    if (Math.abs(swipeDistance) > this.minSwipeDistance) {
      // Apply same userInteractionDelay cooldown as button/keyboard interactions
      this.handleUserInteraction();
      const evt = new Event("swipe");
      if (swipeDistance > 0) {
        this.handlePrevClick(evt);
      } else {
        this.handleNextClick(evt);
      }
    }

    this.touchStartX = null;
    this.touchEndX = null;
  },

  setupResizeHandling() {
    window.addEventListener("resize", this.eventHandlers.resize);
  },

  handleResize() {
    if (this.resizeTimeout) {
      clearTimeout(this.resizeTimeout);
    }

    this.resizeTimeout = setTimeout(() => {
      this.updateSlideSizes();
    }, 100);
  },

  updateSlideSizes() {
    const containerWidth = this.el.clientWidth;
    this.slides.forEach((slide) => {
      const img = slide.querySelector("img");
      if (img && img.naturalWidth > 0 && img.naturalHeight > 0) {
        const aspectRatio = img.naturalHeight / img.naturalWidth;
        img.style.maxHeight = `${containerWidth * aspectRatio}px`;
      }
    });
  },

  setupIntersectionObserver() {
    if ("IntersectionObserver" in window && this.shouldAutoplay) {
      this.intersectionObserver = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (entry.isIntersecting) {
              if (this.shouldAutoplay && !this.isHovered && !this.isTouching) {
                this.startAutoplay();
              }
            } else {
              this.stopAutoplay();
            }
          });
        },
        { threshold: 0.2 },
      );
      this.intersectionObserver.observe(this.el);
    }
  },

  handlePrevClick(e) {
    const targetIndex =
      this.activeIndex > 1 ? this.activeIndex - 1 : this.totalSlides;
    this.navigateToSlide(targetIndex);
    e.stopPropagation();
  },

  handleNextClick(e) {
    const targetIndex =
      this.activeIndex < this.totalSlides ? this.activeIndex + 1 : 1;
    this.navigateToSlide(targetIndex);
    e.stopPropagation();
  },

  handleIndicatorClick(targetIndex) {
    if (targetIndex === this.activeIndex) return;
    this.navigateToSlide(targetIndex);
  },

  navigateToSlide(targetIndex) {
    // Validate targetIndex strictly
    if (
      !/^\d+$/.test(String(targetIndex)) ||
      targetIndex < 1 ||
      targetIndex > this.totalSlides
    ) {
      console.warn(`Invalid slide index: ${targetIndex}`);
      return;
    }

    const currentSlide = this.slides[this.activeIndex - 1];
    const targetSlide = this.slides[targetIndex - 1];

    if (!currentSlide || !targetSlide) {
      console.warn("Cannot navigate: missing slide elements");
      return;
    }

    const targetImage = targetSlide.querySelector("img");

    this.announceSlideChange(targetIndex);

    this.performSlideTransition(currentSlide, targetSlide, targetIndex);

    if (
      targetImage &&
      !targetImage.complete &&
      targetImage.naturalWidth === 0
    ) {
      this.showImageLoadingOverlay(targetImage, targetSlide);
    }

    const event = new CustomEvent("carousel:slide-changed", {
      bubbles: true,
      detail: {
        previousIndex: parseInt(this.activeIndex, 10),
        currentIndex: parseInt(targetIndex, 10),
        totalSlides: parseInt(this.totalSlides, 10),
      },
    });
    this.el.dispatchEvent(event);
  },

  announceSlideChange(targetIndex) {
    let liveRegion = document.getElementById(`${this.el.id}-live-region`);

    if (!liveRegion) {
      liveRegion = document.createElement("div");
      liveRegion.id = `${this.el.id}-live-region`;
      liveRegion.className = "sr-only";
      liveRegion.setAttribute("aria-live", "polite");
      liveRegion.setAttribute("aria-atomic", "true");
      this.el.appendChild(liveRegion);
    }

    liveRegion.textContent = `Slide ${targetIndex} of ${this.totalSlides}`;
  },

  performSlideTransition(currentSlide, targetSlide, targetIndex) {
    currentSlide.classList.add("transition-opacity", "duration-300");
    targetSlide.classList.add("transition-opacity", "duration-300");

    currentSlide.classList.remove(...this.classes.activeSlide.split(" "));
    currentSlide.classList.add(...this.classes.hiddenSlide.split(" "));
    currentSlide.setAttribute("aria-hidden", "true");

    targetSlide.classList.remove(...this.classes.hiddenSlide.split(" "));
    targetSlide.classList.add(...this.classes.activeSlide.split(" "));
    targetSlide.setAttribute("aria-hidden", "false");

    this.updateIndicators(targetIndex);

    this.activeIndex = targetIndex;
  },

  updateIndicators(targetIndex) {
    const indicatorClasses = this.classes.activeIndicator.split(" ");
    this.indicators?.forEach((indicator, index) => {
      const isActive = index + 1 === targetIndex;

      if (isActive) {
        indicator.classList.add(...indicatorClasses);
        indicator.setAttribute("aria-current", "true");
      } else {
        indicator.classList.remove(...indicatorClasses);
        indicator.setAttribute("aria-current", "false");
      }

      indicator.setAttribute("aria-label", `Go to slide ${index + 1}`);
    });
  },

  selectSlide(index) {
    this.handleIndicatorClick(index);
  },

  setupAutoplay() {
    if (this.shouldAutoplay) {
      this.startAutoplay();
    }
  },

  startAutoplay() {
    if (this.isHovered && this.el.dataset.pauseOnHover !== "false") return;
    if (this.isTouching) return;

    clearInterval(this.autoplayTimer);
    this.autoplayTimer = setInterval(() => {
      const nextIndex =
        this.activeIndex < this.totalSlides ? this.activeIndex + 1 : 1;
      this.navigateToSlide(nextIndex);
    }, this.autoplayInterval);
  },

  stopAutoplay() {
    clearInterval(this.autoplayTimer);
    this.autoplayTimer = null;
  },

  handleUserInteraction() {
    this.stopAutoplay();
    clearTimeout(this.userInteractionTimeout);
    this.userInteractionTimeout = setTimeout(() => {
      if (this.shouldAutoplay && !this.isHovered && !this.isTouching) {
        this.startAutoplay();
      }
    }, this.userInteractionDelay);
  },

  showInitialSlide() {
    this.slides.forEach((slide, index) => {
      const isActive = index + 1 === this.activeIndex;
      this.toggleSlideVisibility(slide, isActive);
      if (this.indicators[index]) {
        this.toggleIndicatorState(this.indicators[index], isActive);
      }
    });
  },

  toggleSlideVisibility(slide, isActive) {
    if (isActive) {
      slide.classList.add(...this.classes.activeSlide.split(" "));
      slide.classList.remove(...this.classes.hiddenSlide.split(" "));
      slide.setAttribute("aria-hidden", "false");
      slide.setAttribute("tabindex", "0");
    } else {
      slide.classList.remove(...this.classes.activeSlide.split(" "));
      slide.classList.add(...this.classes.hiddenSlide.split(" "));
      slide.setAttribute("aria-hidden", "true");
      slide.setAttribute("tabindex", "-1");
    }
  },

  toggleIndicatorState(indicator, isActive) {
    const indicatorClasses = this.classes.activeIndicator.split(" ");
    if (isActive) {
      indicator.classList.add(...indicatorClasses);
      indicator.setAttribute("aria-current", "true");
    } else {
      indicator.classList.remove(...indicatorClasses);
      indicator.setAttribute("aria-current", "false");
    }
  },

  setupImageLoadHandling() {
    this.imageLoaders.forEach((img) => {
      const overlay = this.createLoadingOverlay(img);
      if (!overlay) return;

      const slide = img.closest(".slide");
      if (slide) {
        slide.style.minHeight = "300px";
        overlay.style.minHeight = "300px";
      }

      // Guard against missing parentNode if image is detached from DOM
      if (!img.parentNode) {
        return;
      }

      img.parentNode.insertBefore(overlay, img.nextSibling);

      if (img.complete && img.naturalWidth > 0) {
        overlay.remove();
        if (slide) {
          slide.style.removeProperty("min-height");
        }
      } else {
        if (
          "loading" in HTMLImageElement.prototype &&
          !img.hasAttribute("loading")
        ) {
          img.loading = "lazy";
        }

        img.addEventListener(
          "load",
          () => {
            overlay.classList.add("fade-out");
            setTimeout(() => overlay.remove(), 300);
            if (slide) {
              slide.style.removeProperty("min-height");
            }
          },
          { once: true },
        );

        img.addEventListener(
          "error",
          () => {
            overlay.textContent = "";
            const errorDiv = document.createElement("div");
            errorDiv.className = "text-red-500 py-10";
            errorDiv.textContent = "Failed to load image";
            overlay.appendChild(errorDiv);
            overlay.classList.remove("animate-pulse");
          },
          { once: true },
        );
      }
    });
  },

  createLoadingOverlay(img) {
    if (!img) return null;

    const overlay = document.createElement("div");
    overlay.className =
      "absolute inset-0 bg-gray-200 dark:bg-gray-800 animate-pulse flex items-center justify-center transition-opacity duration-300";
    overlay.id = img.id + "-loading";

    const spinner = document.createElement("div");
    spinner.className =
      "animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-primary";
    overlay.appendChild(spinner);

    return overlay;
  },

  showImageLoadingOverlay(img, slide) {
    const existingOverlay = document.getElementById(img.id + "-loading");

    if (!existingOverlay && img) {
      const overlay = this.createLoadingOverlay(img);
      if (overlay) {
        slide.appendChild(overlay);

        img.addEventListener(
          "load",
          () => {
            overlay.classList.add("fade-out");
            setTimeout(() => overlay.remove(), 300);
          },
          { once: true },
        );
      }
    }
  },

  // Helper method: sanitizes a number input
  sanitizeNumber(value) {
    const num = parseInt(value, 10);
    return !isNaN(num) ? num : 0;
  },

  // Helper method: sanitizes class names for Tailwind CSS
  // Allows: alphanumeric, dash, underscore, colon (variants), forward slash (fractions/opacity),
  // square brackets (arbitrary values), period (decimals), percent, and hash (colors)
  // Examples: "md:w-1/2", "hover:bg-red-500/80", "w-[200px]", "text-[#ff0000]"
  sanitizeClassName(classString) {
    if (!classString || typeof classString !== "string") return null;
    return classString
      .split(" ")
      .map((name) => name.replace(/[^a-zA-Z0-9_\-:\/\[\].%#]/g, ""))
      .filter((name) => name.length > 0)
      .join(" ");
  },
};

export default Carousel;
