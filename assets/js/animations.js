import {
  animate,
  utils,
  createDraggable,
  createSpring,
  onScroll,
  stagger,
} from "animejs";

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
        // loop: true,
        // alternate: true,
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

    const observer = new IntersectionObserver((entries) => {
      entries.forEach(
        (entry) => {
          if (entry.isIntersecting) {
            const newYear = parseInt(entry.target.dataset.year);

            if (newYear !== currentYear) {
              animate(yearEl, {
                innerHTML: [currentYear, newYear],
                easing: "easeInOutQuad",
                round: true,
                duration: 300,
              });

              currentYear = newYear;

              // Update navbar highlight
              navLinks.forEach((link) => {
                const isActive = parseInt(link.dataset.year) === newYear;
                link.classList.toggle("opacity-100", isActive);
                link.classList.toggle("opacity-60", !isActive);
                link.classList.toggle("font-semibold", isActive);
                link.classList.toggle("underline", isActive);
              });
            }
          }
        },
        {
          root: null,
          rootMargin: "-50% 0px -50% 0px", // zone d’activation centrée verticalement
        },
      );
    });

    sections.forEach((section) => observer.observe(section));
  },
};
