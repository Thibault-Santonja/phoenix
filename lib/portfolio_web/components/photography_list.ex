defmodule PortfolioWeb.Components.PhotographyList do
  @moduledoc """
  A set of UI components for displaying a list of photography chapters, each optionally
  accompanied by a background image and a button that triggers an interaction (e.g. modal).

  This module defines two main components:

  - `photography_list/1`: A container component that wraps a list of `photography_list_element/1` items.
  - `photography_list_element/1`: An individual element representing a photography chapter,
    with optional background imagery and interactivity.

  These components are intended to be used in a full-screen list or navigation context,
  especially within photo galleries or portfolio pages.

  ## Example Usage

      <.photography_list id="gallery">
        <.photography_list_element
          chapter="reenactment"
          chapter_string="Re-enactment"
          image_source="/images/image.webp"
          image_source_string="My photography"
        />
      </.photography_list>

  ## Features

  - Supports background image rendering for each list item.
  - Allows customization through CSS classes.
  - Integrates with `phx-click` and `phx-value-chapter` for interactive events.
  """

  use Phoenix.Component

  @doc """
  A `dropdown` component that displays a list of options or content when triggered.
  It can be activated by a click or hover, and positioned in various directions relative to its parent.

  ## Examples

  ```elixir
  <.photography_list id="gallery">
    <.photography_list_element
      chapter="reenactment"
      image_source_string="My photography"
      />
  </.photography_list>
  ```
  """
  @doc type: :component
  attr :id, :string,
    default: "gallery",
    doc: "A unique identifier is used to manage state and interaction"

  attr :class, :string, default: nil, doc: "Custom CSS class for additional styling"

  slot :inner_block, required: false, doc: "Inner block that renders HEEx content"

  def photography_list(assigns) do
    ~H"""
    <ul
      id={@id}
      class={[
        "h-full text-lg sm:text-2xl justify-center",
        "flex items-stretch flex-col flex-nowrap",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </ul>
    """
  end

  attr :chapter, :string, doc: "Chapter of reference"
  attr :chapter_string, :string, doc: "Chapter of reference for printing"
  attr :image_source, :string, default: nil, doc: "Chapter image"
  attr :image_source_string, :string, doc: "Chapter image alternative text"
  attr :class, :string, default: nil, doc: "Custom CSS class for additional styling"

  def photography_list_element(assigns) do
    ~H"""
    <li id={"gallery-#{@chapter}"} class={@class}>
      <button
        class="font-black hover:uppercase h-full"
        phx-click="open_modal"
        phx-value-chapter={@chapter}
      >
        {@chapter_string}
      </button>
      <img
        loading="lazy"
        class={[
          "absolute top-0 left-0 -z-10",
          "aspect-auto object-cover",
          "min-w-screen min-h-screen"
        ]}
        src={@image_source || chapter_image(@chapter)}
        alt={@image_source_string}
      />
    </li>
    """
  end

  def chapter_image(nil), do: ""
  def chapter_image(""), do: ""
  def chapter_image(name), do: "/images/photography/#{name}.webp"
end
