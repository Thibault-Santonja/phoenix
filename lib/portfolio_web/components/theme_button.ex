defmodule PortfolioWeb.Components.ThemeButton do
  @moduledoc """
  A reusable component for toggling between light and dark themes.

  This button triggers a theme switch (light ↔ dark) when clicked.
  It uses a `phx-hook` (`DarkModeSwitch`) that manages:
  - toggling the `"dark"` class on `<html>`
  - storing the selected theme in `localStorage`
  - syncing with the user's system preference if no theme is stored

  The button displays:
  - a sun icon when the theme is light
  - a moon icon when the theme is dark

  It is designed to be included in your layout or any LiveView, and requires
  the `DarkModeSwitch` hook to be registered in your JavaScript (see example below).

  ## Example usage

      <.switch_theme_button id="theme-toggle" />

  Make sure your app loads the theme early in `app.js`:

      function getSystemTheme() {
        return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
      }

      function setTheme() {
        const html = document.documentElement;
        const stored = localStorage.getItem("theme");
        const theme = stored || getSystemTheme();
        html.classList.toggle("dark", theme === "dark");
      }

      setTheme();

  And the hook (in `hooks.js`):

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
      }
  """
  use Phoenix.Component

  @doc """
    Renders a theme toggle button.
  ## Slots
  ## Attributes

    * `:id` - Optional string to uniquely identify the button in the DOM.

  ## Example

      <.switch_theme_button id="theme-toggle" />
  """
  @doc type: :component
  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  def switch_theme_button(assigns) do
    ~H"""
    <button phx-hook="DarkModeSwitch" id="theme-toggle" aria-label="Switch theme">
      <svg class="dark:hidden" width="16" height="16" xmlns="http://www.w3.org/2000/svg">
        <path
          class="fill-slate-400"
          d="M7 0h2v2H7zM12.88 1.637l1.414 1.415-1.415 1.413-1.413-1.414zM14 7h2v2h-2zM12.95 14.433l-1.414-1.413 1.413-1.415 1.415 1.414zM7 14h2v2H7zM2.98 14.364l-1.413-1.415 1.414-1.414 1.414 1.415zM0 7h2v2H0zM3.05 1.706 4.463 3.12 3.05 4.535 1.636 3.12z"
        />
        <path class="fill-slate-500" d="M8 4C5.8 4 4 5.8 4 8s1.8 4 4 4 4-1.8 4-4-1.8-4-4-4Z" />
      </svg>
      <svg class="hidden dark:block" width="16" height="16" xmlns="http://www.w3.org/2000/svg">
        <path
          class="fill-slate-400"
          d="M6.2 1C3.2 1.8 1 4.6 1 7.9 1 11.8 4.2 15 8.1 15c3.3 0 6-2.2 6.9-5.2C9.7 11.2 4.8 6.3 6.2 1Z"
        />
        <path
          class="fill-slate-500"
          d="M12.5 5a.625.625 0 0 1-.625-.625 1.252 1.252 0 0 0-1.25-1.25.625.625 0 1 1 0-1.25 1.252 1.252 0 0 0 1.25-1.25.625.625 0 1 1 1.25 0c.001.69.56 1.249 1.25 1.25a.625.625 0 1 1 0 1.25c-.69.001-1.249.56-1.25 1.25A.625.625 0 0 1 12.5 5Z"
        />
      </svg>
      <span class="sr-only">Switch to light / dark version</span>
    </button>
    """
  end
end
