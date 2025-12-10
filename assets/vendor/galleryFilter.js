const GalleryFilter = {
  mounted() {
    // Extract configuration from data attributes and normalize to lowercase.
    // If data-default-filter isn't provided, it defaults to "all".
    this.defaultFilter = (this.el.dataset.defaultFilter || "all").toLowerCase();

    // Cache DOM elements.
    this.items = Array.from(this.el.querySelectorAll("[data-gallery-item]"));
    this.filterButtons = Array.from(
      this.el.querySelectorAll("[data-gallery-filter]"),
    );

    // Set up event listeners.
    this._setupEventListeners();

    // Apply initial filter without animation.
    this.applyFilter(this.defaultFilter, null, true);
  },

  /**
   * Set up click and keydown event listeners for filter buttons.
   */
  _setupEventListeners() {
    this.clickHandlers = new Map();
    this.keydownHandlers = new Map();

    this.filterButtons.forEach((btn) => {
      const clickHandler = () => {
        if (btn.disabled) return;
        // Normalize filter value to lowercase for consistent matching.
        const category = (btn.dataset.category || "").toLowerCase();
        if (category) this.applyFilter(category, btn);
      };

      const keydownHandler = (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          btn.click();
        }
      };

      btn.addEventListener("click", clickHandler);
      btn.addEventListener("keydown", keydownHandler);

      this.clickHandlers.set(btn, clickHandler);
      this.keydownHandlers.set(btn, keydownHandler);
    });
  },

  /**
   * Clean up event listeners when hook is destroyed.
   */
  destroyed() {
    if (this.filterButtons && this.clickHandlers && this.keydownHandlers) {
      this.filterButtons.forEach((btn) => {
        const clickHandler = this.clickHandlers.get(btn);
        const keydownHandler = this.keydownHandlers.get(btn);

        if (clickHandler) btn.removeEventListener("click", clickHandler);
        if (keydownHandler) btn.removeEventListener("keydown", keydownHandler);
      });

      this.clickHandlers.clear();
      this.keydownHandlers.clear();
    }
  },

  /**
   * Check if the item should be visible for the given category.
   * If the selected category equals the defaultFilter (which acts as "all"),
   * then all items are shown; otherwise, only items matching the category are shown.
   * @param {HTMLElement} item - Gallery item element.
   * @param {string} category - Category to check.
   * @returns {boolean} True if the item should be visible.
   */
  _isItemVisible(item, category) {
    if (category === this.defaultFilter) return true;
    // Here, we expect that the data attribute contains a comma-separated string
    // representing an array of categories (e.g. "sky" or "sky,flowers").
    const rawCategories = item.dataset.category || "";
    if (!rawCategories) return false;

    const itemCategories = rawCategories
      .split(",")
      .map((c) => c.trim().toLowerCase());
    return itemCategories.includes(category);
  },

  /**
   * Capture current positions of items.
   * @returns {Map<HTMLElement, DOMRect>} A map of items to their positions.
   */
  _captureItemPositions() {
    const positions = new Map();
    this.items.forEach((item) => {
      // Only record positions for currently visible items; hidden ones
      // will be treated as "new" during the next animation.
      if (item.style.display === "none") return;
      positions.set(item, item.getBoundingClientRect());
    });
    return positions;
  },

  /**
   * Update visibility of items based on the current filter.
   * @param {string} category - Filter category.
   */
  _updateItemVisibility(category) {
    this.items.forEach((item) => {
      const isVisible = this._isItemVisible(item, category);
      item.style.display = isVisible ? "" : "none";
      if (isVisible) {
        item.style.opacity = "0";
        item.style.transform = "scale(0.95)";
      }
    });
  },

  /**
   * Show items immediately without animation.
   */
  _showItemsImmediately() {
    this.items.forEach((item) => {
      if (item.style.display !== "none") {
        item.style.opacity = "1";
        item.style.transform = "scale(1)";
      }
    });
  },

  /**
   * Animate items from previous positions to their new positions.
   * @param {Map<HTMLElement, DOMRect>} beforePositions - Map of items and their previous positions.
   * @param {function} onComplete - Callback function when all animations are complete.
   */
  _animateItems(beforePositions, onComplete) {
    // Check for reduced motion preference - skip animation if set
    const prefersReducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;

    if (prefersReducedMotion) {
      this._showItemsImmediately();
      onComplete && onComplete();
      return;
    }

    // Force browser reflow to ensure new positions are calculated.
    void this.el.offsetWidth;

    const visibleItems = this.items.filter(
      (item) => item.style.display !== "none",
    );
    let animationsRemaining = visibleItems.length;
    const TRANSITION_TIMEOUT = 400; // 300ms transition + 100ms margin

    if (animationsRemaining === 0) {
      onComplete && onComplete();
      return;
    }

    const decrementAndComplete = () => {
      animationsRemaining--;
      if (animationsRemaining === 0) {
        onComplete && onComplete();
      }
    };

    visibleItems.forEach((item) => {
      const before = beforePositions.get(item);
      const after = item.getBoundingClientRect();

      // Items that were previously hidden have no `before` position:
      // just fade/scale them in without a FLIP translation.
      if (!before) {
        item.style.opacity = "0";
        item.style.transform = "scale(0.95)";
        requestAnimationFrame(() => {
          item.style.transition = "transform 300ms ease, opacity 300ms ease";
          item.style.transform = "scale(1)";
          item.style.opacity = "1";

          // Set timeout fallback in case transitionend doesn't fire
          let completed = false;
          const fallbackTimeout = setTimeout(() => {
            if (!completed) {
              completed = true;
              item.style.transition = "";
              decrementAndComplete();
            }
          }, TRANSITION_TIMEOUT);

          item.addEventListener(
            "transitionend",
            () => {
              if (!completed) {
                completed = true;
                clearTimeout(fallbackTimeout);
                item.style.transition = "";
                decrementAndComplete();
              }
            },
            { once: true },
          );
        });
        return;
      }

      const dx = before.left - after.left;
      const dy = before.top - after.top;

      if (dx || dy) {
        item.style.transform = `translate(${dx}px, ${dy}px) scale(0.95)`;
      }

      item.style.opacity = "0";

      requestAnimationFrame(() => {
        item.style.transition = "transform 300ms ease, opacity 300ms ease";
        item.style.transform = "translate(0, 0) scale(1)";
        item.style.opacity = "1";

        // Set timeout fallback in case transitionend doesn't fire
        let completed = false;
        const fallbackTimeout = setTimeout(() => {
          if (!completed) {
            completed = true;
            item.style.transition = "";
            decrementAndComplete();
          }
        }, TRANSITION_TIMEOUT);

        item.addEventListener(
          "transitionend",
          () => {
            if (!completed) {
              completed = true;
              clearTimeout(fallbackTimeout);
              item.style.transition = "";
              decrementAndComplete();
            }
          },
          { once: true },
        );
      });
    });
  },

  /**
   * Update active state of filter buttons.
   * The active button remains disabled, while the others are enabled.
   * @param {string} activeCategory - Current active category.
   */
  _updateActiveFilterButton(activeCategory) {
    this.filterButtons.forEach((btn) => {
      const btnCategory = (btn.dataset.category || "").toLowerCase();
      const isActive = btnCategory === activeCategory;
      btn.setAttribute("aria-pressed", isActive);
      if (isActive) {
        btn.classList.add("active");
        btn.disabled = true;
      } else {
        btn.classList.remove("active");
        btn.disabled = false;
      }
    });
  },

  /**
   * Apply a filter to the gallery items.
   * @param {string} category - Category to filter by.
   * @param {HTMLElement|null} clickedButton - The button that was clicked (optional).
   * @param {boolean} [skipAnimation=false] - Whether to skip the animation.
   */
  applyFilter(category, clickedButton = null, skipAnimation = false) {
    // Track the latest requested category so animations from older clicks
    // can't re-activate stale buttons.
    this._activeFilterCategory = category;

    // Disable only the clicked button immediately.
    if (clickedButton) {
      clickedButton.disabled = true;
    }
    const beforePositions = this._captureItemPositions();
    this._updateItemVisibility(category);

    if (skipAnimation) {
      this._showItemsImmediately();
      this._updateActiveFilterButton(this._activeFilterCategory);
      return;
    }

    this._animateItems(beforePositions, () => {
      this._updateActiveFilterButton(this._activeFilterCategory);
    });
  },
};

export default GalleryFilter;
