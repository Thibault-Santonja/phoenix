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
  updated() {
    console.log("updated");
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
          animate(timeline.querySelectorAll(".event"), {
            opacity: [0, 1],
            translateY: [30, 0],
            delay: 100,
            duration: 800,
            easing: "easeOutQuad",
          });
          this.enableScrollSync(timeline, container);
        } else {
          this.disableScrollSync(container);
        }
      },
      {
        root: null,
        threshold: 0.5, // 50% visible
        rootMargin: "-20% 0px -70% 0px", // zone d’activation centrée verticalement
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
