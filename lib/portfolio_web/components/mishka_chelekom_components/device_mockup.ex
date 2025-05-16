defmodule PortfolioWeb.Components.DeviceMockup do
  @moduledoc """
  The `PortfolioWeb.Components.DeviceMockup` module provides a customizable component for displaying
  various device mockups such as iPhone, Android, Watch, Laptop, iPad, and iMac.

  It supports different color themes and includes options for adding images or custom
  content to represent device screens.

  ## Features:
  - Supports multiple device types: `iphone`, `android`, `watch`, `laptop`, `ipad`, and `imac`.
  - Customizable color themes with various pre-defined options.
  - Flexible layout options, allowing you to include images or custom content within the device frame.
  - Easily integrable with other components for displaying responsive media content or
  application previews.
  """
  use Phoenix.Component
  import PortfolioWeb.Components.Image, only: [image: 1]

  @doc """
  The `device_mockup` component renders a responsive device mockup for various devices like
  `iphone`, `android`, `ipad`, `laptop`, and `imac`.

  It supports different colors, images, and slot-based content to simulate device screens.

  ## Examples

  ```elixir
  # iPhone mockup with image
  <.device_mockup image="https://example.com/mockup-2-light.png" />

  # Watch mockup with custom image
  <.device_mockup image="https://example.com/watch-screen-image.png" type="watch"/>

  # iPad mockup with image and additional content
  <.device_mockup image="https://example.com/tablet-mockup-image.png" type="ipad">
    <div class="text-center">This is inside the iPad mockup</div>
  </.device_mockup>

  # iMac mockup with image and nested content
  <.device_mockup image="https://example.com/screen-image-imac.png" type="imac">
    <div class="flex justify-center items-center h-full">iMac Screen Content</div>
  </.device_mockup>

  # Laptop mockup with content slot
  <.device_mockup type="laptop"><div class="p-4">Laptop Screen Content Here</div></.device_mockup>

  # Android mockup with image and content
  <.device_mockup image="https://example.com/mockup-1-light.png" type="android"
  >
    <div class="text-center">Android Device Content</div>
  </.device_mockup>

  # Custom content inside various mockups with color themes
  <.device_mockup color="primary">
    <div class="bg-white h-full flex flex-col gap-2 justify-between">
      <div class="pt-8 pb-2 px-1">
        Sample text content for primary color theme.
      </div>
      <div class="border-t py-2 px-5">
        <div class="w-full h-7 bg-gray-300 text-gray-500 rounded-lg text-center flex items-center justify-center">
          mishka.tools
        </div>
      </div>
    </div>
  </.device_mockup>

  <.device_mockup color="success">
    <div class="bg-white h-full flex flex-col gap-2 justify-between">
      <div class="pt-8 pb-2 px-1">
        Success-themed device content with additional styling.
      </div>
      <div class="border-t py-2 px-5">
        <div class="w-full h-7 bg-gray-300 text-gray-500 rounded-lg text-center flex items-center justify-center">
          mishka.tools
        </div>
      </div>
    </div>
  </.device_mockup>

  <.device_mockup color="danger">
    <div class="bg-white h-full flex flex-col gap-2 justify-between">
      <div class="pt-8 pb-2 px-1">
        Danger-themed device mockup with content and styling.
      </div>
      <div class="border-t py-2 px-5">
        <div class="w-full h-7 bg-gray-300 text-gray-500 rounded-lg text-center flex items-center justify-center">
          mishka.tools
        </div>
      </div>
    </div>
  </.device_mockup>

  <.device_mockup color="dark">
    <div class="bg-white h-full flex flex-col gap-2 justify-between">
      <div class="pt-8 pb-2 px-1">
        Dark-themed device mockup with content and additional options.
      </div>
      <div class="border-t py-2 px-5">
        <div class="w-full h-7 bg-gray-300 text-gray-500 rounded-lg text-center flex items-center justify-center">
          mishka.tools
        </div>
      </div>
    </div>
  </.device_mockup>
  ```
  """
  @doc type: :component
  attr :id, :string,
    default: nil,
    doc: "A unique identifier is used to manage state and interaction"

  attr :class, :string, default: nil, doc: "Custom CSS class for additional styling"
  attr :color, :string, default: "base", doc: "Determines color theme"
  attr :alt, :string, default: nil, doc: "Media link description"
  attr :type, :string, default: "iphone", doc: "android watch laptop iphone ipad imac"
  attr :image, :string, default: nil, doc: "Image displayed alongside of an item"
  attr :image_class, :string, default: nil, doc: "Determines custom class for the image"

  attr :rest, :global,
    include: ~w(android watch laptop iphone ipad imac),
    doc:
      "Global attributes can define defaults which are merged with attributes provided by the caller"

  slot :inner_block, doc: "Inner block that renders HEEx content"

  def device_mockup(%{type: "watch"} = assigns) do
    ~H"""
    <div class={["w-fit", color_class(@color), @class]}>
      <div class="mock-base rounded-t-[2.5rem] h-[63px] max-w-[133px] relative mx-auto"></div>
      <div class="mock-base border-[10px] rounded-[2.5rem] h-[213px] w-[208px] relative mx-auto">
        <div class="mock-base h-[41px] w-[6px] -end-[16px] top-[40px] rounded-e-lg absolute"></div>
        <div class="mock-base h-[32px] w-[6px] -end-[16px] top-[88px] rounded-e-lg absolute"></div>
        <div class="rounded-[2rem] h-[193px] w-[188px] overflow-hidden bg-white dark:bg-[#404040]">
          <.image
            :if={!is_nil(@image)}
            class={@image_class || "h-[193px] w-[188px]"}
            src={@image}
            alt={@alt}
          />
          {render_slot(@inner_block)}
        </div>
      </div>
      <div class="mock-base rounded-b-[2.5rem] h-[63px] max-w-[133px] relative mx-auto"></div>
    </div>
    """
  end

  def device_mockup(%{type: "android"} = assigns) do
    ~H"""
    <div class={["w-fit", color_class(@color), @class]}>
      <div class="mock-base border-[14px] h-[600px] w-[300px] relative mx-auto rounded-xl shadow-xl">
        <div class="mock-base w-[148px] h-[18px] rounded-b-[1rem] absolute top-0 left-1/2 -translate-x-1/2">
        </div>
        <div class="mock-base h-[32px] w-[3px] -start-[17px] top-[72px] rounded-s-lg absolute"></div>
        <div class="mock-base h-[46px] w-[3px] -start-[17px] top-[124px] rounded-s-lg absolute"></div>
        <div class="mock-base h-[46px] w-[3px] -start-[17px] top-[178px] rounded-s-lg absolute"></div>
        <div class="mock-base h-[64px] w-[3px] -end-[17px] top-[142px] rounded-e-lg absolute"></div>
        <div class="w-[272px] h-[572px] overflow-hidden rounded bg-white dark:bg-[#404040]">
          <.image
            :if={!is_nil(@image)}
            class={@image_class || "w-[272px] h-[572px]"}
            src={@image}
            alt={@alt}
          />
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  def device_mockup(%{type: "laptop"} = assigns) do
    ~H"""
    <div class={["max-w-fit md:max-w-[512px]", color_class(@color), @class]}>
      <div class="mock-base border-[8px] h-[172px] max-w-[301px] relative mx-auto rounded-t-xl md:h-[294px] md:max-w-[512px]">
        <div class="h-[156px] overflow-hidden rounded bg-white dark:bg-[#404040] md:h-[278px]">
          <.image
            :if={!is_nil(@image)}
            class={@image_class || "h-[140px] w-full md:h-[262px]"}
            src={@image}
            alt={@alt}
          />
          {render_slot(@inner_block)}
        </div>
      </div>
      <div class="mock-darker-base h-[17px] max-w-[351px] relative mx-auto rounded-t-sm rounded-b-xl md:h-[21px] md:max-w-[597px]">
        <div class="mock-base w-[56px] h-[5px] absolute top-0 left-1/2 -translate-x-1/2 rounded-b-xl md:w-[96px] md:h-[8px]">
        </div>
      </div>
    </div>
    """
  end

  def device_mockup(%{type: "ipad"} = assigns) do
    ~H"""
    <div class={["max-w-fit md:max-w-[512px]", color_class(@color), @class]}>
      <div class="mock-base border-[14px] rounded-[2.5rem] h-[454px] max-w-[341px] relative mx-auto md:h-[682px] md:max-w-[512px]">
        <div class="mock-base h-[32px] w-[3px] -start-[17px] top-[72px] rounded-s-lg absolute"></div>
        <div class="mock-base h-[46px] w-[3px] -start-[17px] top-[124px] rounded-s-lg absolute"></div>
        <div class="mock-base h-[46px] w-[3px] -start-[17px] top-[178px] rounded-s-lg absolute"></div>
        <div class="mock-base h-[64px] w-[3px] -end-[17px] top-[142px] rounded-e-lg absolute"></div>
        <div class="h-[426px] overflow-hidden rounded-3xl bg-white dark:bg-[#404040] md:h-[654px]">
          <.image
            :if={!is_nil(@image)}
            class={@image_class || "h-[426px] md:h-[654px]"}
            src={@image}
            alt={@alt}
          />
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  def device_mockup(%{type: "imac"} = assigns) do
    ~H"""
    <div class={["max-w-fit md:max-w-[512px]", color_class(@color), @class]}>
      <div class="mock-base border-[16px] h-[172px] max-w-[301px] relative mx-auto rounded-t-xl md:h-[294px] md:max-w-[512px]">
        <div class="h-[140px] overflow-hidden bg-white dark:bg-[#404040] md:h-[262px]">
          <.image
            :if={!is_nil(@image)}
            class={@image_class || "h-[140px] w-full md:h-[262px]"}
            src={@image}
            alt={@alt}
          />
          {render_slot(@inner_block)}
        </div>
      </div>
      <div class="mock-darker-base h-[24px] max-w-[301px] relative mx-auto rounded-b-xl md:h-[42px] md:max-w-[512px]">
      </div>
      <div class="mock-base h-[55px] max-w-[83px] relative mx-auto rounded-b-xl md:h-[95px] md:max-w-[142px]">
      </div>
    </div>
    """
  end

  def device_mockup(assigns) do
    ~H"""
    <div class={["w-fit", color_class(@color), @class]}>
      <div class="mock-base border-[14px] rounded-[2.5rem] h-[600px] w-[300px] relative mx-auto shadow-xl">
        <div class="mock-base w-[148px] h-[18px] rounded-b-[1rem] absolute top-0 left-1/2 -translate-x-1/2">
        </div>
        <div class="mock-base h-[46px] w-[3px] -start-[17px] top-[124px] rounded-s-lg absolute"></div>
        <div class="mock-base h-[46px] w-[3px] -start-[17px] top-[178px] rounded-s-lg absolute"></div>
        <div class="mock-base h-[64px] w-[3px] -end-[17px] top-[142px] rounded-e-lg absolute"></div>
        <div class="w-[272px] h-[572px] overflow-hidden rounded-3xl bg-white dark:bg-[#404040]">
          <.image
            :if={!is_nil(@image)}
            class={@image_class || "w-[272px] h-[572px]"}
            src={@image}
            alt={@alt}
          />
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  defp color_class("base") do
    [
      "[&_.mock-base]:bg-[#f1f3f5] [&_.mock-darker-base]:bg-[#dee2e6] [&_.mock-base]:border-[#e4e4e7]",
      "dark:[&_.mock-base]:bg-[#2e2e2e] dark:[&_.mock-darker-base]:bg-[#424242] dark:[&_.mock-base]:border-[#27272a]"
    ]
  end

  defp color_class("natural") do
    [
      "[&_.mock-base]:bg-[#4B4B4B] [&_.mock-darker-base]:bg-black [&_.mock-base]:border-[#282828]",
      "dark:[&_.mock-base]:bg-[#DDDDDD] dark:[&_.mock-darker-base]:bg-white dark:[&_.mock-base]:border-[#E8E8E8]"
    ]
  end

  defp color_class("primary") do
    [
      "[&_.mock-base]:bg-[#007F8C] [&_.mock-darker-base]:bg-[#1A535A] [&_.mock-base]:border-[#016974]",
      "dark:[&_.mock-base]:bg-[#01B8CA] dark:[&_.mock-darker-base]:bg-[#B0E7EF] dark:[&_.mock-base]:border-[#77D5E3]"
    ]
  end

  defp color_class("secondary") do
    [
      "[&_.mock-base]:bg-[#266EF1] [&_.mock-darker-base]:bg-[#1948A3] [&_.mock-base]:border-[#175BCC]",
      "dark:[&_.mock-base]:bg-[#6DAAFB] dark:[&_.mock-darker-base]:bg-[#CDDEFF] dark:[&_.mock-base]:border-[#A8C8FE]"
    ]
  end

  defp color_class("success") do
    [
      "[&_.mock-base]:bg-[#0E8345] [&_.mock-darker-base]:bg-[#0D572D] [&_.mock-base]:border-[#166C3B]",
      "dark:[&_.mock-base]:bg-[#06C167] dark:[&_.mock-darker-base]:bg-[#B1EAC2] dark:[&_.mock-base]:border-[#7FD99A]"
    ]
  end

  defp color_class("warning") do
    [
      "[&_.mock-base]:bg-[#CA8D01] [&_.mock-darker-base]:bg-[#654600] [&_.mock-base]:border-[#976A01]",
      "dark:[&_.mock-base]:bg-[#FDC034] dark:[&_.mock-darker-base]:bg-[#FEDF99] dark:[&_.mock-base]:border-[#FDD067]"
    ]
  end

  defp color_class("danger") do
    [
      "[&_.mock-base]:bg-[#DE1135] [&_.mock-darker-base]:bg-[#950F22] [&_.mock-base]:border-[#BB032A]",
      "dark:[&_.mock-base]:bg-[#FC7F79] dark:[&_.mock-darker-base]:bg-[#FFD2CD] dark:[&_.mock-base]:border-[#FFB2AB]"
    ]
  end

  defp color_class("info") do
    [
      "[&_.mock-base]:bg-[#0B84BA] [&_.mock-darker-base]:bg-[#06425D] [&_.mock-base]:border-[#08638C]",
      "dark:[&_.mock-base]:bg-[#3EB7ED] dark:[&_.mock-darker-base]:bg-[#9FDBF6] dark:[&_.mock-base]:border-[#6EC9F2]"
    ]
  end

  defp color_class("misc") do
    [
      "[&_.mock-base]:bg-[#8750C5] [&_.mock-darker-base]:bg-[#442863] [&_.mock-base]:border-[#653C94]",
      "dark:[&_.mock-base]:bg-[#BA83F9] dark:[&_.mock-darker-base]:bg-[#DDC1FC] dark:[&_.mock-base]:border-[#CBA2FA]"
    ]
  end

  defp color_class("dawn") do
    [
      "[&_.mock-base]:bg-[#A86438] [&_.mock-darker-base]:bg-[#54321C] [&_.mock-base]:border-[#7E4B2A]",
      "dark:[&_.mock-base]:bg-[#DB976B] dark:[&_.mock-darker-base]:bg-[#EDCBB5] dark:[&_.mock-base]:border-[#E4B190]"
    ]
  end

  defp color_class("silver") do
    [
      "[&_.mock-base]:bg-[#868686] [&_.mock-darker-base]:bg-[#5E5E5E] [&_.mock-base]:border-[#727272]",
      "dark:[&_.mock-base]:bg-[#A6A6A6] dark:[&_.mock-darker-base]:bg-[#DDDDDD] dark:[&_.mock-base]:border-[#BBBBBB]"
    ]
  end
end
