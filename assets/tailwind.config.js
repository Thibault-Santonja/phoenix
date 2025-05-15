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
        // base_100: "oklch(100% 0 0)",
        // base_200: "oklch(98% 0 0)",
        // base_300: "oklch(95% 0 0)",
        // base_400: "oklch(90% 0 0)",
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
        pcontent: "oklch(35% 0.1226 119.87)",
        secondary: "oklch(85% 0.1156 102)",
        scontent: "oklch(35% 0.1156 102)",
        accent: "oklch(85% 0.1453 74.18)",
        acontent: "oklch(35% 0.1453 74.18)",
        neutral: "oklch(43% 0 0)",
        ncontent: "oklch(98% 0 0)",
        info: "oklch(60% 0.126 221.723)",
        icontent: "oklch(98% 0.019 200.873)",
        success: "oklch(64% 0.2 131.684)",
        sucontent: "oklch(98% 0.031 120.757)",
        warning: "oklch(66% 0.179 58.318)",
        wcontent: "oklch(98% 0.022 95.277)",
        error: "oklch(57% 0.245 27.325)",
        econtent: "oklch(97% 0.013 17.38)",
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
