defmodule PortfolioWeb.TechLive.Blog.Kamal do
  @moduledoc """
  Blog post about my Kamal usage
  """
  use PortfolioWeb, :live_view
  import PortfolioWeb.SEO.SchemaHelpers

  @impl true
  def mount(_, session, socket) do
    locale = session["locale"] || "fr"
    _ = Gettext.put_locale(PortfolioWeb.Gettext, locale)

    # Generate article schema for SEO
    article_json = generate_kamal_article_schema()
    breadcrumb_json = generate_kamal_breadcrumb_schema()

    {
      :ok,
      socket
      |> assign(:article_json, article_json)
      |> assign(:breadcrumb_json, breadcrumb_json)
    }
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(
      :page_title,
      gettext("layouts.tech.header") <> " • " <> gettext("tech.blog.kamal.kamal")
    )
  end

  defp generate_kamal_article_schema do
    article_schema(
      "Deploying Phoenix with Kamal",
      "A complete guide to deploying Phoenix LiveView applications using Kamal for zero-downtime deployments",
      "https://tech.thibaultsan.com/blog/kamal",
      ~U[2025-05-01 00:00:00Z]
    )
  end

  defp generate_kamal_breadcrumb_schema do
    breadcrumbs = [
      %{name: "Home", url: "https://tech.thibaultsan.com"},
      %{name: "Blog", url: "https://tech.thibaultsan.com"},
      %{name: "Kamal", url: "https://tech.thibaultsan.com/blog/kamal"}
    ]

    breadcrumb_schema(breadcrumbs)
  end
end
