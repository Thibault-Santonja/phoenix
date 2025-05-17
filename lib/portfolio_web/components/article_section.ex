defmodule PortfolioWeb.Components.ArticleSection do
  @moduledoc """
  Default Article component
  """
  use Phoenix.Component

  @doc """
  Renders a styled article section.

  ## Slots

    * `:title` - the section title (typically used in an <h2>)
    * `:inner_block` - the main content of the section

  ## Example

      <.article_section>
        <:title>My Section Title</:title>
        <p>This is the content of the section.</p>
      </.article_section>
  """
  @doc type: :component
  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :title, :string,
    default: nil,
    doc: "Article title"

  slot :inner_block,
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  def article_section(assigns) do
    ~H"""
    <article id={@id} class="bg-tech-base-50 lg:p-10 pt-[5rem]">
      <h2 class="text-tech-secondary mb-6 text-2xl font-semibold tracking-tight">
        {@title}
      </h2>
      <div class="indent-8 prose prose-tech max-w-none flex flex-col space-y-4">
        {render_slot(@inner_block)}
      </div>
    </article>
    """
  end
end
