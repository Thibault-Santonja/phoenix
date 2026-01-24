defmodule PortfolioWeb.ThemeButtonTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PortfolioWeb.Components.ThemeButton

  describe "switch_theme_button/1" do
    test "renders theme toggle button" do
      html = render_component(&ThemeButton.switch_theme_button/1, %{})

      assert html =~ "<button"
      assert html =~ "</button>"
    end

    test "has DarkModeSwitch hook" do
      html = render_component(&ThemeButton.switch_theme_button/1, %{})

      assert html =~ "phx-hook=\"DarkModeSwitch\""
    end

    test "has default id theme-toggle" do
      html = render_component(&ThemeButton.switch_theme_button/1, %{})

      assert html =~ "id=\"theme-toggle\""
    end

    test "has aria-label for accessibility" do
      html = render_component(&ThemeButton.switch_theme_button/1, %{})

      assert html =~ "aria-label=\"Switch theme\""
    end

    test "has screen reader text" do
      html = render_component(&ThemeButton.switch_theme_button/1, %{})

      assert html =~ "sr-only"
      assert html =~ "Switch to light / dark version"
    end

    test "contains sun icon for light mode" do
      html = render_component(&ThemeButton.switch_theme_button/1, %{})

      # Sun icon is visible in light mode (dark:hidden)
      assert html =~ "dark:hidden"
      assert html =~ "<svg"
    end

    test "contains moon icon for dark mode" do
      html = render_component(&ThemeButton.switch_theme_button/1, %{})

      # Moon icon is visible in dark mode (hidden dark:block)
      assert html =~ "hidden dark:block"
    end

    test "renders two SVG icons" do
      html = render_component(&ThemeButton.switch_theme_button/1, %{})

      # Count SVG occurrences - should have 2 (sun and moon)
      svg_count = html |> String.split("<svg") |> length()
      # Split gives n+1 parts for n occurrences
      assert svg_count == 3
    end

    test "icons have proper dimensions" do
      html = render_component(&ThemeButton.switch_theme_button/1, %{})

      assert html =~ "width=\"16\""
      assert html =~ "height=\"16\""
    end
  end
end
