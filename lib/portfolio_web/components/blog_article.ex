defmodule PortfolioWeb.Components.BlogArticle do
  @moduledoc """
  Default Blog Article component
  """
  use Phoenix.Component

  @doc """
  Renders a styled blog article.

  ## Slots

    * `:title` - the article title (typically used in an <h1>)
    * `:inner_block` - the content of the article

  ## Example

      <.blog_article>
        <:title>My Article Title</:title>

        article sections
      </.blog_article>
  """
  attr :title, :string, doc: "Title of the article"
  attr :overview, :string, required: false, default: nil, doc: "Title of the article"
  slot :inner_block, doc: "Inner block that renders HEEx content"

  def blog_article(assigns) do
    ~H"""
    <section class="border-tech-base-300 bg-tech-base-100 mx-auto rounded-lg border px-6 py-12 shadow-lg md:px-[3rem] md:m-[5rem]">
      <h1 class="text-tech-primary text-balance mb-16 text-center text-3xl font-thin uppercase">
        {render_slot(@title)}
      </h1>

      <div class="flex flex-col gap-4">
        <p :if={@overview} class="italic">
          {render_slot(@overview)}
        </p>

        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
