defmodule PortfolioWeb.TechLive.Index do
  use PortfolioWeb, :live_view

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

      <article class="mt-12">
        <h2 class="text-tech-primary animate-fade-in-up mb-6 text-center text-xl font-semibold delay-200">
          {gettext("My latest articles")}
        </h2>
        <%!-- <ul class="flex flex-col justify-evenly flex-wrap sm:flex-row sm:space-x-8 sm:space-y-0"> --%>
        <ul class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 max-w-fill">
          <li>
            <a
              href={~p"/blog/ci"}
              class="group border-tech-base-300 bg-tech-base-100 block rounded-xl border p-6 shadow-sm transition-all duration-300 hover:bg-tech-base-200 hover:shadow-md"
            >
              <div class="mb-3 flex items-center space-x-4">
                <.icon
                  name="hero-wrench-screwdriver-solid"
                  class="text-tech-accent h-6 w-6 flex-none transition group-hover:rotate-12"
                />
                <h3 class="text-tech-accent text-lg font-medium">
                  {gettext("The Project CI")}
                </h3>
              </div>
              <p class="text-tech-muted-foreground text-sm">
                {gettext(
                  "Explore how the site is built and deployed using GitHub Actions, Docker, and Elixir Phoenix."
                )}
              </p>
            </a>
          </li>

          <li>
            <a
              href={~p"/blog/kamal"}
              class="group border-tech-base-300 bg-tech-base-100 block rounded-xl border p-6 shadow-sm transition-all duration-300 hover:bg-tech-base-200 hover:shadow-md"
            >
              <div class="mb-3 flex items-center space-x-4">
                <.icon
                  name="hero-server-stack-solid"
                  class="text-tech-accent h-6 w-6 flex-none transition group-hover:rotate-12"
                />
                <h3 class="text-tech-accent text-lg font-medium">
                  {gettext("Deploying with Kamal")}
                </h3>
              </div>
              <p class="text-tech-muted-foreground text-sm">
                {gettext(
                  "How I use Kamal to deploy Phoenix apps with Docker on a VPS — simple, elegant, and production-ready."
                )}
              </p>
            </a>
          </li>

          <li>
            <a
              href={~p"/blog/elixir"}
              class="group border-tech-base-300 bg-tech-base-100 block rounded-xl border p-6 shadow-sm transition-all duration-300 hover:bg-tech-base-200 hover:shadow-md"
            >
              <div class="mb-3 flex items-center space-x-4">
                <.icon
                  name="hero-language-solid"
                  class="text-tech-accent h-6 w-6 flex-none transition group-hover:rotate-12"
                />
                <h3 class="text-tech-accent text-lg font-medium">
                  {gettext("The future-proof Elixir programing language")}
                </h3>
              </div>
              <p class="text-tech-muted-foreground text-sm">
                {gettext(
                  "Quick dig into Elixir's concurrency model and its impact on building scalable applications."
                )}
              </p>
            </a>
          </li>
        </ul>
      </article>

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
