defmodule PortfolioWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  This module serves as the main entry point for all UI components.
  It re-exports components from specialized modules:

  - `FormComponents` - Form inputs, labels, buttons
  - `FeedbackComponents` - Modals, flash messages, JS commands
  - `LayoutComponents` - Headers, tables, lists, navigation
  - `AdminComponents` - Dashboard cards, badges, admin-specific elements

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component

  # Re-export all components from specialized modules
  defdelegate simple_form(assigns), to: PortfolioWeb.FormComponents
  defdelegate button(assigns), to: PortfolioWeb.FormComponents
  defdelegate input(assigns), to: PortfolioWeb.FormComponents
  defdelegate label(assigns), to: PortfolioWeb.FormComponents
  defdelegate error(assigns), to: PortfolioWeb.FormComponents
  defdelegate translate_error(msg_opts), to: PortfolioWeb.FormComponents
  defdelegate translate_errors(errors, field), to: PortfolioWeb.FormComponents

  defdelegate modal(assigns), to: PortfolioWeb.FeedbackComponents
  defdelegate flash(assigns), to: PortfolioWeb.FeedbackComponents
  defdelegate flash_group(assigns), to: PortfolioWeb.FeedbackComponents
  defdelegate show(js \\ %Phoenix.LiveView.JS{}, selector), to: PortfolioWeb.FeedbackComponents
  defdelegate hide(js \\ %Phoenix.LiveView.JS{}, selector), to: PortfolioWeb.FeedbackComponents
  defdelegate show_modal(js \\ %Phoenix.LiveView.JS{}, id), to: PortfolioWeb.FeedbackComponents
  defdelegate hide_modal(js \\ %Phoenix.LiveView.JS{}, id), to: PortfolioWeb.FeedbackComponents

  defdelegate header(assigns), to: PortfolioWeb.LayoutComponents
  defdelegate table(assigns), to: PortfolioWeb.LayoutComponents
  defdelegate list(assigns), to: PortfolioWeb.LayoutComponents
  defdelegate back(assigns), to: PortfolioWeb.LayoutComponents

  defdelegate stat_card(assigns), to: PortfolioWeb.AdminComponents
  defdelegate back_to_dashboard(assigns), to: PortfolioWeb.AdminComponents
  defdelegate admin_logout_button(assigns), to: PortfolioWeb.AdminComponents
  defdelegate action_card(assigns), to: PortfolioWeb.AdminComponents
  defdelegate badge(assigns), to: PortfolioWeb.AdminComponents
  defdelegate filter_badge(assigns), to: PortfolioWeb.AdminComponents
  defdelegate primary_button(assigns), to: PortfolioWeb.AdminComponents
  defdelegate link_button(assigns), to: PortfolioWeb.AdminComponents

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end
end
