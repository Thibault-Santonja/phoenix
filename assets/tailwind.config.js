// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

import plugin from "tailwindcss/plugin";
import { readdirSync, readFileSync } from "fs";
import { join, basename } from "path";

export const content = [
  "./js/**/*.js",
  "../lib/portfolio_web.ex",
  "../lib/portfolio_web/**/*.*ex",
];

export const theme = {
  extend: {
    colors: {
      amvcc: {
        base: {
          100: "oklch(100% 0 0)",
          200: "oklch(98% 0 0)",
          300: "oklch(95% 0 0)",
          400: "oklch(90% 0 0)",
          500: "oklch(80% 0 0)",
          600: "oklch(60% 0 0)",
          800: "oklch(40% 0 0)",
          900: "oklch(20% 0 0)",
          content: "oklch(21% 0.006 285.885)",
        },
        content: {
          primary: "oklch(35% 0.1226 119.87)",
          secondary: "oklch(35% 0.1156 102)",
          accent: "oklch(35% 0.1453 74.18)",
          neutral: "oklch(92% 0.004 286.32)",
          info: "oklch(39% 0.07 227.392)",
          success: "oklch(40% 0.101 131.063)",
          warning: "oklch(41% 0.112 45.904)",
          error: "oklch(39% 0.141 25.723)",
        },
        primary: "oklch(85% 0.1226 119.87)",
        secondary: "oklch(85% 0.1156 102)",
        accent: "oklch(85% 0.1453 74.18)",
        neutral: "oklch(14% 0.005 285.823)",
        info: "oklch(78% 0.154 211.53)",
        success: "oklch(84% 0.238 128.85)",
        warning: "oklch(82% 0.189 84.429)",
        error: "oklch(70% 0.191 22.216)",
      },
      amvccdark: {
        base: {
          100: "oklch(14% 0 0)",
          200: "oklch(26% 0 0)",
          300: "oklch(37% 0 0)",
          content: "oklch(97% 0 0)",
        },
        primary: "oklch(85% 0.1226 119.87)",
        secondary: "oklch(85% 0.1156 102)",
        accent: "oklch(85% 0.1453 74.18)",
        neutral: "oklch(43% 0 0)",
        info: "oklch(60% 0.126 221.723)",
        success: "oklch(64% 0.2 131.684)",
        warning: "oklch(66% 0.179 58.318)",
        error: "oklch(57% 0.245 27.325)",
        content: {
          primary: "oklch(35% 0.1226 119.87)",
          secondary: "oklch(35% 0.1156 102)",
          accent: "oklch(35% 0.1453 74.18)",
          neutral: "oklch(98% 0 0)",
          info: "oklch(98% 0.019 200.873)",
          success: "oklch(98% 0.031 120.757)",
          warning: "oklch(98% 0.022 95.277)",
          error: "oklch(97% 0.013 17.38)",
        },
      },
      photo: {
        primary: "oklch(0% 0 0)",
        content: {
          primary: "oklch(100% 0 0)",
        },
      },
      tech: {
        base: {
          100: "oklch(100% 0 261)",
          200: "oklch(97% 0 262)",
          300: "oklch(94% 0 263)",
          content: "oklch(20% 0 264)",
        },
        primary: "oklch(59.435% 0.077 254.027)",
        "primary-content": "oklch(11.887% 0.015 254.027)",
        secondary: "oklch(69.651% 0.059 248.687)",
        "secondary-content": "oklch(13.93% 0.011 248.687)",
        accent: "oklch(77.464% 0.062 217.469)",
        "accent-content": "oklch(15.492% 0.012 217.469)",
        neutral: "oklch(45.229% 0.035 264.131)",
        "neutral-content": "oklch(89.925% 0.016 262.749)",
        info: "oklch(69.207% 0.062 332.664)",
        "info-content": "oklch(13.841% 0.012 332.664)",
        success: "oklch(76.827% 0.074 131.063)",
        "success-content": "oklch(15.365% 0.014 131.063)",
        warning: "oklch(85.486% 0.089 84.093)",
        "warning-content": "oklch(17.097% 0.017 84.093)",
        error: "oklch(60.61% 0.12 15.341)",
        "error-content": "oklch(12.122% 0.024 15.341)",
      },
      brand: "#FD4F00",
    },
    borderRadius: {
      selector: ".5rem",
      field: ".25rem",
      box: ".25rem",
    },
  },
};

export const plugins = [
  require("@tailwindcss/forms"),
  // Allows prefixing tailwind classes with LiveView classes to add rules
  // only when LiveView classes are applied, for example:
  //
  //     <div class="phx-click-loading:animate-ping">
  //
  plugin(({ addVariant }) =>
    addVariant("phx-click-loading", [
      ".phx-click-loading&",
      ".phx-click-loading &",
    ]),
  ),
  plugin(({ addVariant }) =>
    addVariant("phx-submit-loading", [
      ".phx-submit-loading&",
      ".phx-submit-loading &",
    ]),
  ),
  plugin(({ addVariant }) =>
    addVariant("phx-change-loading", [
      ".phx-change-loading&",
      ".phx-change-loading &",
    ]),
  ),
  // Embeds Heroicons (https://heroicons.com) into your app.css bundle
  // See your `CoreComponents.icon/1` for more information.
  //
  plugin(function ({ matchComponents, theme }) {
    let iconsDir = join(__dirname, "../deps/heroicons/optimized");
    let values = {};
    let icons = [
      ["", "/24/outline"],
      ["-solid", "/24/solid"],
      ["-mini", "/20/solid"],
      ["-micro", "/16/solid"],
    ];
    icons.forEach(([suffix, dir]) => {
      readdirSync(join(iconsDir, dir)).forEach((file) => {
        let name = basename(file, ".svg") + suffix;
        values[name] = {
          name,
          fullPath: join(iconsDir, dir, file),
        };
      });
    });
    matchComponents(
      {
        hero: ({ name, fullPath }) => {
          let content = readFileSync(fullPath)
            .toString()
            .replace(/\r?\n|\r/g, "");
          let size = theme("spacing.6");
          if (name.endsWith("-mini")) {
            size = theme("spacing.5");
          } else if (name.endsWith("-micro")) {
            size = theme("spacing.4");
          }
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            mask: `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            display: "inline-block",
            width: size,
            height: size,
          };
        },
      },
      {
        values,
      },
    );
  }),
];

let { extract } = require("../deps/tailwind_formatter/assets/js");
extract(module.exports, "../_build");
