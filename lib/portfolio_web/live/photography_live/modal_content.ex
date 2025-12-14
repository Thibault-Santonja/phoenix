defmodule PortfolioWeb.PhotographyLive.ModalContent do
  @moduledoc """
  Component for rendering modal content in the photography section.

  Provides the modal shell and delegates chapter-specific content
  to ChapterContent module for better maintainability.
  """

  use PortfolioWeb, :html

  alias PortfolioWeb.Helpers.AlbumTypeFormatter
  alias PortfolioWeb.PhotographyLive.ChapterContent

  attr :modal_chapter, :string, required: true
  attr :language, :string, required: true

  def chapter_modal(assigns) do
    ~H"""
    <div class={[
      "bg-black opacity-80",
      "h-full p-8 md:p-16 lg:p-32",
      "space-y-8 md:space-y-16",
      "flex flex-col"
    ]}>
      <header class="flex justify-between items-center">
        <h2 class="text-2xl font-bold uppercase">
          {AlbumTypeFormatter.format_chapter_title(@modal_chapter)}
        </h2>
        <button class={["text-white text-2xl font-bold", "close-modal"]} phx-click="close_modal">
          &times;
        </button>
      </header>

      <div class="space-y-4">
        <ChapterContent.render chapter={@modal_chapter} />
      </div>

      <nav class="flex">
        <button
          :if={@modal_chapter}
          class={[
            "close-modal",
            "grow-0",
            "block mt-8 mx-auto",
            "group hover:scale-110 duration-300",
            "py-3 px-5"
          ]}
          phx-click="close_modal"
        >
          {gettext("photography.close")}
          <.icon
            name="hero-x-circle-solid"
            class={[
              "ml-2 h-5 w-5",
              "group-hover:rotate-[1.57rad] duration-500 ease-out"
            ]}
          />
        </button>

        <.show_more_link
          :if={@modal_chapter in ~w(reenactment amvcc music)}
          href={~p"/timeline/#{@modal_chapter}"}
        />
        <.show_more_link :if={@modal_chapter in ~w(china)} href={~p"/gallery/#{@modal_chapter}"} />
      </nav>
    </div>
    """
  end

  defp show_more_link(assigns) do
    ~H"""
    <a
      href={@href}
      class={[
        "grow-0",
        "block mt-8 mx-auto",
        "group hover:scale-110 duration-300",
        "py-2 px-4",
        "rounded-lg border-2"
      ]}
    >
      {gettext("photography.show_more")}
      <.icon
        name="hero-arrow-right-circle-solid"
        class={[
          "ml-2 h-5 w-5",
          "group-hover:rotate-[6.283rad] duration-500 ease-out"
        ]}
      />
    </a>
    """
  end
end
