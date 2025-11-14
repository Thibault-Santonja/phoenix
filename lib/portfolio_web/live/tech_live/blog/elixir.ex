defmodule PortfolioWeb.TechLive.Blog.Elixir do
  @moduledoc """
    Blog post about my Elixir usage
  """
  use PortfolioWeb, :live_view
  import PortfolioWeb.Components.{ArticleSection, BlogArticle, ArticleCodeBloc}
  import PortfolioWeb.Components.TableContent

  @impl true
  def mount(_, session, socket) do
    locale = session["locale"] || "fr"
    Gettext.put_locale(PortfolioWeb.Gettext, locale)

    {:ok, socket}
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
end
