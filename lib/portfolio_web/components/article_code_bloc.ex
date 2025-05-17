defmodule PortfolioWeb.Components.ArticleCodeBloc do
  @moduledoc """
  Default Article code bloc component
  """
  use Phoenix.Component

  @doc """
  Renders a styled code bloc.

  ## Slots

    * `:inner_block` - the main content of the code bloc

  ## Example

      <.code_bloc>
        <code>This is the content of the section.</code>
      </.code_bloc>
  """
  @doc type: :component
  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  slot :inner_block, doc: "Inner block that renders HEEx content"

  def code_bloc(assigns) do
    ~H"""
    <pre class="bg-tech-neutral text-tech-neutral-content mb-6 overflow-auto rounded-lg p-4 text-sm">
    {render_slot(@inner_block)}
    </pre>
    """
  end
end
