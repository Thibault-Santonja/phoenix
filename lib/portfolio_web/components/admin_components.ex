defmodule PortfolioWeb.AdminComponents do
  @moduledoc """
  Admin-specific UI components.

  This module provides components for the admin dashboard and back-office:
  - Stat cards for metrics display
  - Action cards for navigation
  - Badges and filters
  - Admin-specific buttons and links
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: PortfolioWeb.Endpoint,
    router: PortfolioWeb.Router,
    statics: PortfolioWeb.static_paths()

  # Shared color configurations to avoid duplication
  @card_colors %{
    "blue" => %{
      border: "border-blue-500 hover:border-blue-600",
      hover: "hover:border-blue-400",
      icon_bg: "bg-blue-100",
      icon_text: "text-blue-600"
    },
    "green" => %{
      border: "border-green-500",
      hover: "hover:border-green-400",
      icon_bg: "bg-green-100",
      icon_text: "text-green-600"
    },
    "purple" => %{
      border: "border-purple-500",
      hover: "hover:border-purple-400",
      icon_bg: "bg-purple-100",
      icon_text: "text-purple-600"
    },
    "orange" => %{
      border: "border-orange-500 hover:border-orange-600",
      hover: "hover:border-orange-400",
      icon_bg: "bg-orange-100",
      icon_text: "text-orange-600"
    },
    "red" => %{
      border: "border-red-500",
      hover: "hover:border-red-400",
      icon_bg: "bg-red-100",
      icon_text: "text-red-600"
    }
  }

  @badge_colors %{
    "gray" => "bg-gray-100 text-gray-800",
    "green" => "bg-green-100 text-green-800",
    "orange" => "bg-orange-100 text-orange-800",
    "blue" => "bg-blue-100 text-blue-800",
    "red" => "bg-red-100 text-red-800",
    "indigo" => "bg-indigo-100 text-indigo-800",
    "purple" => "bg-purple-100 text-purple-800",
    "yellow" => "bg-yellow-100 text-yellow-800"
  }

  @link_colors %{
    "indigo" => "text-indigo-600 hover:text-indigo-900",
    "red" => "text-red-600 hover:text-red-900",
    "gray" => "text-gray-600 hover:text-gray-900"
  }

  @doc """
  Renders a dashboard statistic card.

  ## Examples

      <.stat_card
        title="Total Albums"
        value={@stats.total_albums}
        icon="hero-folder"
        color="blue"
        navigate={~p"/admin/albums"}
      />

      <.stat_card
        title="Total Photos"
        value={@stats.total_photos}
        icon="hero-photo"
        color="green"
      >
        <:footer>
          Optional footer content
        </:footer>
      </.stat_card>
  """
  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "blue", values: ~w(blue green purple orange red)
  attr :navigate, :string, default: nil
  attr :class, :string, default: nil
  slot :footer, doc: "optional footer content"

  def stat_card(assigns) do
    assigns = assign(assigns, :colors, @card_colors[assigns.color])

    ~H"""
    <.stat_card_wrapper navigate={@navigate} colors={@colors} class={@class}>
      <div class="flex items-center justify-between">
        <div>
          <p class="text-sm font-medium text-gray-600">{@title}</p>
          <p class="text-3xl font-bold text-gray-900 mt-2">{@value}</p>
        </div>
        <div class={["rounded-full p-3", @colors.icon_bg]}>
          <PortfolioWeb.CoreComponents.icon name={@icon} class={"w-8 h-8 #{@colors.icon_text}"} />
        </div>
      </div>
      <div :if={@footer != []} class="mt-4">
        {render_slot(@footer)}
      </div>
    </.stat_card_wrapper>
    """
  end

  # Private component to handle the wrapper (div or link)
  attr :navigate, :string, default: nil
  attr :colors, :map, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp stat_card_wrapper(%{navigate: nil} = assigns) do
    ~H"""
    <div class={["bg-white rounded-lg shadow p-6 border-l-4", @colors.border, @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp stat_card_wrapper(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "bg-white rounded-lg shadow p-6 border-l-4 hover:shadow-lg transition-all cursor-pointer block",
        @colors.border,
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Renders a back to dashboard link.

  ## Examples

      <.back_to_dashboard />
  """
  def back_to_dashboard(assigns) do
    ~H"""
    <div class="mb-4">
      <.link
        navigate={~p"/admin"}
        class="inline-flex items-center text-sm text-gray-600 hover:text-gray-900"
      >
        <PortfolioWeb.CoreComponents.icon name="hero-chevron-left" class="w-4 h-4 mr-2" />
        Retour au tableau de bord
      </.link>
    </div>
    """
  end

  @doc """
  Renders a logout button for admin pages.

  ## Examples

      <.admin_logout_button current_user={@current_user} />
  """
  attr :current_user, :map, required: true
  attr :class, :string, default: nil

  def admin_logout_button(assigns) do
    ~H"""
    <div :if={@current_user} class={["flex items-center gap-4", @class]}>
      <span class="text-sm text-gray-600">
        Connecté en tant que
        <span class="font-medium text-gray-900">
          {@current_user.name || @current_user.email}
        </span>
      </span>
      <span class="text-gray-300">|</span>
      <.link
        href={~p"/logout"}
        method="delete"
        class="text-sm text-gray-600 hover:text-gray-900 font-medium"
      >
        Déconnexion
      </.link>
    </div>
    """
  end

  @doc """
  Renders an action card for quick navigation.

  ## Examples

      <.action_card
        title="Gérer les albums"
        description="Créer, modifier et organiser vos albums photo"
        icon="hero-folder"
        color="blue"
        navigate={~p"/admin/albums"}
      />
  """
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :icon, :string, required: true
  attr :color, :string, default: "blue", values: ~w(blue green purple orange)
  attr :navigate, :string, required: true
  attr :class, :string, default: nil

  def action_card(assigns) do
    assigns = assign(assigns, :colors, @card_colors[assigns.color])

    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "bg-white rounded-lg shadow hover:shadow-lg transition-shadow p-6 border border-gray-200",
        @colors.hover,
        @class
      ]}
    >
      <div class="flex items-start">
        <div class={["rounded-lg p-3", @colors.icon_bg]}>
          <PortfolioWeb.CoreComponents.icon name={@icon} class={"w-6 h-6 #{@colors.icon_text}"} />
        </div>
        <div class="ml-4 flex-1">
          <h3 class="text-lg font-semibold text-gray-900">{@title}</h3>
          <p class="mt-1 text-sm text-gray-600">{@description}</p>
        </div>
        <PortfolioWeb.CoreComponents.icon name="hero-chevron-right" class="w-5 h-5 text-gray-400" />
      </div>
    </.link>
    """
  end

  @doc """
  Renders a colored badge component.

  Useful for displaying status, types, or categories.

  ## Examples

      <.badge color="green">Publié</.badge>
      <.badge color="orange">Brouillon</.badge>
      <.badge color="blue">Concert</.badge>
  """
  attr :color, :string,
    default: "gray",
    values: ~w(gray green orange blue red indigo purple yellow)

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    assigns = assign(assigns, :color_class, @badge_colors[assigns.color])

    ~H"""
    <span class={[
      "inline-flex rounded-full px-2 text-xs font-semibold leading-5",
      @color_class,
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Renders a filter badge/button with active state.

  Used for filter buttons in admin interfaces.

  ## Examples

      <.filter_badge navigate={~p"/admin/albums"} active={true}>
        Tous <span class="ml-1.5 text-xs">(42)</span>
      </.filter_badge>

      <.filter_badge navigate={~p"/admin/albums?filter=published"} active={false} color="green">
        Publiés <span class="ml-1.5 text-xs">(25)</span>
      </.filter_badge>
  """
  attr :navigate, :string, required: true
  attr :active, :boolean, default: false
  attr :color, :string, default: "indigo", values: ~w(indigo green orange blue red)
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def filter_badge(assigns) do
    active_class =
      if assigns.active,
        do: @badge_colors[assigns.color],
        else: "bg-gray-100 text-gray-700 hover:bg-gray-200"

    assigns = assign(assigns, :active_class, active_class)

    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "inline-flex items-center px-3 py-1 rounded-full text-sm font-medium transition-colors",
        @active_class,
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Renders a primary action button.

  Consistent styling for primary actions across the admin interface.

  ## Examples

      <.primary_button navigate={~p"/admin/albums/new"}>
        Nouvel album
      </.primary_button>

      <.primary_button navigate={~p"/admin/albums/new"} class="w-full">
        Créer un album
      </.primary_button>
  """
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def primary_button(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      patch={@patch}
      class={[
        "inline-flex items-center justify-center rounded-md border border-transparent",
        "bg-indigo-600 px-4 py-2 text-sm font-medium text-white shadow-sm",
        "hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Renders a link styled as a button.

  Used for action links like "Éditer" and "Supprimer".

  ## Examples

      <.link_button color="indigo" navigate={~p"/admin/albums/\#{id}/edit"}>
        Éditer
      </.link_button>

      <.link_button color="red" phx-click="delete" phx-value-id={id} confirm="Êtes-vous sûr ?">
        Supprimer
      </.link_button>
  """
  attr :color, :string, default: "indigo", values: ~w(indigo red gray)
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :href, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-id data-confirm)
  slot :inner_block, required: true

  def link_button(assigns) do
    assigns = assign(assigns, :color_class, @link_colors[assigns.color])

    ~H"""
    <.link
      :if={@navigate}
      navigate={@navigate}
      class={[@color_class, @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    <.link
      :if={@patch && !@navigate}
      patch={@patch}
      class={[@color_class, @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    <a
      :if={!@navigate && !@patch}
      href={@href || "#"}
      class={[@color_class, @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </a>
    """
  end
end
