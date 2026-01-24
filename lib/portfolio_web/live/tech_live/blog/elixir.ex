defmodule PortfolioWeb.TechLive.Blog.Elixir do
  @moduledoc """
    Blog post about my Elixir usage
  """
  use PortfolioWeb, :live_view
  import PortfolioWeb.Components.{ArticleSection, BlogArticle, ArticleCodeBloc}
  import PortfolioWeb.Components.TableContent
  import PortfolioWeb.SEO.SchemaHelpers

  @impl true
  def mount(_, session, socket) do
    locale = session["locale"] || "fr"
    _ = Gettext.put_locale(PortfolioWeb.Gettext, locale)

    # Generate article schema for SEO
    article_json = generate_elixir_article_schema()
    breadcrumb_json = generate_elixir_breadcrumb_schema()

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
      gettext("layouts.tech.header") <> " • " <> gettext("tech.blog.elixir.elixir")
    )
  end

  defp generate_elixir_article_schema do
    article_schema(
      "Why Elixir for Web Development",
      "An in-depth exploration of Elixir and Phoenix LiveView for building modern, real-time web applications",
      "https://tech.thibaultsan.com/blog/elixir",
      ~U[2025-05-10 00:00:00Z]
    )
  end

  defp generate_elixir_breadcrumb_schema do
    breadcrumbs = [
      %{name: "Home", url: "https://tech.thibaultsan.com"},
      %{name: "Blog", url: "https://tech.thibaultsan.com"},
      %{name: "Elixir", url: "https://tech.thibaultsan.com/blog/elixir"}
    ]

    breadcrumb_schema(breadcrumbs)
  end
end
