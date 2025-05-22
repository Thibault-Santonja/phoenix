defmodule PortfolioWeb.TechLive.Index do
  use PortfolioWeb, :live_view
  import PortfolioWeb.Components.ArticleCard

  @impl true
  def mount(_, session, socket) do
    Gettext.put_locale(PortfolioWeb.Gettext, session["locale"])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :page_title, gettext("The tech blog"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="border-tech-base-300 bg-tech-base-100 mx-auto w-fit border px-6 py-12 shadow-lg transition-all duration-500 md:px-[3rem] md:m-[5rem] md:rounded-lg">
      <header class="space-y-4 text-center">
        <h1 class="text-tech-primary animate-fade-in-up text-3xl font-bold md:text-4xl">
          {gettext("Welcome to Thibault's dev blog")}
        </h1>
        <p class="text-tech-muted-foreground animate-fade-in-up text-base delay-100 md:text-lg">
          {gettext(
            "A growing collection of ideas, tools, and experiments in web development, DevOps, and medieval digital humanities."
          )}
        </p>
      </header>

      <.article_card_list
        card_class="border-tech-base-300 bg-tech-base-100 hover:bg-tech-base-200"
        header_class="text-tech-accent"
        title={gettext("My latest articles")}
      >
        <:article_card
          url={~p"/blog/ci"}
          icon="hero-wrench-screwdriver-solid"
          title={gettext("The Project CI")}
          description={
            gettext(
              "Explore how the site is built and deployed using GitHub Actions, Docker, and Elixir Phoenix."
            )
          }
        />
        <:article_card
          url={~p"/blog/kamal"}
          icon="hero-server-stack-solid"
          title={gettext("Deploying with Kamal")}
          description={
            gettext(
              "How I use Kamal to deploy Phoenix apps with Docker on a VPS — simple, elegant, and production-ready."
            )
          }
        />
        <:article_card
          url={~p"/blog/elixir"}
          icon="hero-beaker-solid"
          title={gettext("The future-proof Elixir programing language")}
          description={
            gettext(
              "Quick dig into Elixir's concurrency model and its impact on building scalable applications."
            )
          }
        />
      </.article_card_list>

      <article class="mt-16 text-center">
        <p class="text-tech-muted-foreground animate-fade-in-up text-sm delay-300">
          {gettext(
            "The tech blog is under construction — come back soon for articles on Elixir, Phoenix, CI/CD, and more !."
          )}
        </p>
      </article>
    </section>
    """
  end
end
