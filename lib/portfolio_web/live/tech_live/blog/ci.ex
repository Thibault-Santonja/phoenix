defmodule PortfolioWeb.TechLive.Blog.Ci do
  @moduledoc """
    Blog post about my CI usage
  """
  use PortfolioWeb, :live_view
  import PortfolioWeb.SEO.SchemaHelpers

  @impl true
  def mount(_, session, socket) do
    locale = session["locale"] || "fr"
    _ = Gettext.put_locale(PortfolioWeb.Gettext, locale)

    # Generate article schema for SEO
    article_json = generate_ci_article_schema()
    breadcrumb_json = generate_ci_breadcrumb_schema()

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
    |> assign(:page_title, gettext("layouts.tech.header") <> " • " <> gettext("tech.blog.ci.ci"))
  end

  defp generate_ci_article_schema do
    article_schema(
      "Continuous Integration for Phoenix LiveView",
      "A comprehensive guide to setting up CI/CD for Phoenix LiveView applications using GitHub Actions, Mise, and Docker",
      "https://tech.thibaultsan.com/blog/ci",
      ~U[2025-05-20 00:00:00Z]
    )
  end

  defp generate_ci_breadcrumb_schema do
    breadcrumbs = [
      %{name: "Home", url: "https://tech.thibaultsan.com"},
      %{name: "Blog", url: "https://tech.thibaultsan.com"},
      %{name: "CI/CD", url: "https://tech.thibaultsan.com/blog/ci"}
    ]

    breadcrumb_schema(breadcrumbs)
  end
end
