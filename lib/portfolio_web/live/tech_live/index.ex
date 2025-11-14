defmodule PortfolioWeb.TechLive.Index do
  use PortfolioWeb, :live_view
  import PortfolioWeb.Components.ArticleCard

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
    assign(socket, :page_title, gettext("tech.blog.title"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="border-tech-base-300 bg-tech-base-100 mx-auto w-fit border px-6 py-12 shadow-lg transition-all duration-500 md:px-[3rem] md:m-[5rem] md:rounded-lg">
      <header class="space-y-4 text-center">
        <h1 class="text-tech-primary animate-fade-in-up text-3xl font-bold md:text-4xl">
          {gettext("tech.blog.welcome")}
        </h1>
        <p class="text-tech-muted-foreground animate-fade-in-up text-base delay-100 md:text-lg">
          {gettext("tech.blog.description")}
        </p>
      </header>

      <.article_card_list
        card_class="border-tech-base-300 bg-tech-base-100 hover:bg-tech-base-200"
        header_class="text-tech-accent"
        title={gettext("tech.blog.latest_articles")}
      >
        <:article_card
          url={~p"/blog/ci"}
          icon="hero-wrench-screwdriver-solid"
          title={gettext("tech.blog.ci_title")}
          description={gettext("tech.blog.ci_description")}
        />
        <:article_card
          url={~p"/blog/kamal"}
          icon="hero-server-stack-solid"
          title={gettext("tech.blog.kamal_title")}
          description={gettext("tech.blog.kamal_description")}
        />
        <:article_card
          url={~p"/blog/elixir"}
          icon="hero-beaker-solid"
          title={gettext("tech.blog.elixir_title")}
          description={gettext("tech.blog.elixir_description")}
        />
      </.article_card_list>

      <article class="mt-16 text-center">
        <p class="text-tech-muted-foreground animate-fade-in-up text-sm delay-300">
          {gettext("tech.blog.under_construction")}
        </p>
      </article>
    </section>
    """
  end
end
