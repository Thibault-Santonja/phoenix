import {
  animate,
  utils,
  createDraggable,
  createSpring,
  onScroll,
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
    const [$timeline] = utils.$("#timeline");
    const events = utils.$(".event");
    const scrollY = window.scrollY;

    animate($timeline, {
      translateX: -scrollY * 0.5,
      duration: 30000,
      easing: "easeOutQuad",
    });

    events.forEach(($event) => {
      animate($event, {
        opacity: [0, 1],
        translateY: [20, 0],
        delay: animate.stagger(150),
        duration: 800,
        easing: "easeOutQuad",
      });
    });
  },
};
