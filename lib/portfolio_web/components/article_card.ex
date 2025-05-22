defmodule PortfolioWeb.Components.ArticleCard do
  @moduledoc """
  Renders a grid of stylized article cards with support for dynamic icons, titles, and descriptions.

  This component provides two main functions:

    * `article_card_list/1` – renders a titled grid list of article cards.
    * `article_card/1` – renders a single article card with optional icon and custom classes.

  ## Usage

  Use `article_card_list/1` to render a group of articles in a responsive grid layout.
  Each item in the slot represents an individual article.

  ```heex
  <.article_card_list title="Latest Articles">
    <:article_card
      url="/blog/my-article"
      icon="hero-pencil-square"
      title="My First Post"
      description="An overview of my journey into Elixir and Phoenix."
    />
    <:article_card
      url="/blog/phoenix-liveview"
      icon="hero-fire"
      title="LiveView Magic"
      description="Exploring real-time UI with Phoenix LiveView."
    />
  </.article_card_list>
  ```
  Use article_card/1 independently if you want to render a single card outside of a list.

  ```heex
  <.article_card
    url="/blog/single-post"
    icon="hero-sparkles"
    title="Spotlight"
    description="A featured article on the homepage."
  />
  ```

  Attributes

  Both components support customization via:

      :title — section or article title.

      :card_class — custom class for the card container.

      :header_class — custom class for the card header/icon area.

  The slot for article_card_list accepts:

      :url — link to the article (required)

      :icon — name of the icon to display

      :title — title of the article (required)

      :description — short summary or excerpt (required)

  Icons are expected to be compatible with the PortfolioWeb.Components.Icon component.

  """
  use Phoenix.Component
  import PortfolioWeb.Components.Icon

  attr :title, :string, required: false, default: "", doc: "Group title"
  attr :card_class, :string, required: false, default: "", doc: "Article card class"
  attr :header_class, :string, required: false, default: "", doc: "Article card class"

  slot :article_card do
    attr :url, :string, required: true, doc: "Article URL"
    attr :icon, :string, required: false, doc: "Article icon"
    attr :title, :string, required: true, doc: "Title of the article"
    attr :description, :string, required: true, doc: "Article description"
  end

  def article_card_list(assigns) do
    ~H"""
    <article class="mt-12">
      <h2 class="text-tech-primary animate-fade-in-up mb-6 text-center text-xl font-semibold delay-200">
        {@title}
      </h2>
      <%!-- <ul class="flex flex-col justify-evenly flex-wrap sm:flex-row sm:space-x-8 sm:space-y-0"> --%>
      <ul class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 max-w-fill">
        <li :for={{card, index} <- Enum.with_index(@article_card, 1)} id={"article-card-#{index}"}>
          <.article_card
            url={card[:url]}
            icon={card[:icon]}
            title={card[:title]}
            description={card[:description]}
            card_class={@card_class}
            header_class={@header_class}
          />
        </li>
      </ul>
    </article>
    """
  end

  @doc """
  Renders a styled blog article.

  ## Slots

    * `:title` - the article title (typically used in an <h1>)
    * `:inner_block` - the content of the article

  ## Example

      <.article_card
        url={~p"/blog/article"}
        icon="hero-wrench-screwdriver-solid"
        title="My title"
        description="Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
      />
  """
  attr :url, :string, required: true, doc: "Article URL"
  attr :icon, :string, required: false, doc: "Article icon"
  attr :title, :string, required: true, doc: "Title of the article"
  attr :description, :string, required: true, doc: "Article description"
  attr :card_class, :string, required: false, doc: "Card class"
  attr :header_class, :string, required: false, doc: "Header class"

  def article_card(assigns) do
    ~H"""
    <a
      href={@url}
      class={[
        "group  block rounded-xl border p-6 shadow-sm transition-all duration-300  hover:shadow-md",
        @card_class
      ]}
    >
      <div class="mb-3 flex items-center space-x-4">
        <.icon
          name={@icon}
          class={[
            "h-6 w-6 flex-none transition group-hover:rotate-12",
            @header_class
          ]}
        />
        <h3 class={[
          "text-lg font-medium",
          @header_class
        ]}>
          {@title}
        </h3>
      </div>
      <p class="text-tech-muted-foreground text-sm">
        {@description}
      </p>
    </a>
    """
  end
end
