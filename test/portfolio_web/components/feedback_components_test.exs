defmodule PortfolioWeb.FeedbackComponentsTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.JS
  alias PortfolioWeb.FeedbackComponents

  describe "modal/1" do
    test "renders hidden modal by default" do
      html =
        render_component(&FeedbackComponents.modal/1,
          id: "test-modal",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Modal content" end}]
        )

      assert html =~ "id=\"test-modal\""
      assert html =~ "hidden"
      assert html =~ "test-modal-bg"
      assert html =~ "test-modal-container"
    end

    test "renders modal with custom id" do
      html =
        render_component(&FeedbackComponents.modal/1,
          id: "custom-modal",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        )

      assert html =~ "id=\"custom-modal\""
      assert html =~ "custom-modal-bg"
      assert html =~ "custom-modal-container"
      assert html =~ "custom-modal-content"
    end

    test "modal includes close button with aria-label" do
      html =
        render_component(&FeedbackComponents.modal/1,
          id: "test-modal",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        )

      assert html =~ "aria-label="
      assert html =~ "hero-x-mark-solid"
    end

    test "modal includes accessibility attributes" do
      html =
        render_component(&FeedbackComponents.modal/1,
          id: "test-modal",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        )

      assert html =~ "role=\"dialog\""
      assert html =~ "aria-modal=\"true\""
      assert html =~ "aria-labelledby=\"test-modal-title\""
      assert html =~ "aria-describedby=\"test-modal-description\""
    end
  end

  describe "flash/1" do
    test "renders info flash message" do
      html =
        render_component(&FeedbackComponents.flash/1,
          kind: :info,
          flash: %{"info" => "Success message"}
        )

      assert html =~ "Success message"
      assert html =~ "bg-emerald-50"
      assert html =~ "text-emerald-800"
      assert html =~ "role=\"alert\""
    end

    test "renders error flash message" do
      html =
        render_component(&FeedbackComponents.flash/1,
          kind: :error,
          flash: %{"error" => "Error occurred"}
        )

      assert html =~ "Error occurred"
      assert html =~ "bg-rose-50"
      assert html =~ "text-rose-900"
    end

    test "renders flash with title" do
      html =
        render_component(&FeedbackComponents.flash/1,
          kind: :info,
          title: "Notice",
          flash: %{"info" => "Message content"}
        )

      assert html =~ "Notice"
      assert html =~ "Message content"
      assert html =~ "hero-information-circle-mini"
    end

    test "renders error flash with exclamation icon" do
      html =
        render_component(&FeedbackComponents.flash/1,
          kind: :error,
          title: "Error",
          flash: %{"error" => "Something went wrong"}
        )

      assert html =~ "hero-exclamation-circle-mini"
    end

    test "does not render when flash is empty" do
      html =
        render_component(&FeedbackComponents.flash/1,
          kind: :info,
          flash: %{}
        )

      # Should not render content
      refute html =~ "role=\"alert\""
    end

    test "uses custom id when provided" do
      html =
        render_component(&FeedbackComponents.flash/1,
          id: "custom-flash",
          kind: :info,
          flash: %{"info" => "Test"}
        )

      assert html =~ "id=\"custom-flash\""
    end

    test "uses default id based on kind" do
      html =
        render_component(&FeedbackComponents.flash/1,
          kind: :error,
          flash: %{"error" => "Test"}
        )

      assert html =~ "id=\"flash-error\""
    end
  end

  describe "flash_group/1" do
    test "renders flash group container" do
      html =
        render_component(&FeedbackComponents.flash_group/1,
          flash: %{}
        )

      assert html =~ "id=\"flash-group\""
    end

    test "renders with custom id" do
      html =
        render_component(&FeedbackComponents.flash_group/1,
          id: "my-flash-group",
          flash: %{}
        )

      assert html =~ "id=\"my-flash-group\""
    end

    test "renders info flash when present" do
      html =
        render_component(&FeedbackComponents.flash_group/1,
          flash: %{"info" => "Info message"}
        )

      assert html =~ "Info message"
    end

    test "renders error flash when present" do
      html =
        render_component(&FeedbackComponents.flash_group/1,
          flash: %{"error" => "Error message"}
        )

      assert html =~ "Error message"
    end

    test "renders client-error flash with reconnecting message" do
      html =
        render_component(&FeedbackComponents.flash_group/1,
          flash: %{}
        )

      assert html =~ "id=\"client-error\""
      assert html =~ "hidden"
    end

    test "renders server-error flash" do
      html =
        render_component(&FeedbackComponents.flash_group/1,
          flash: %{}
        )

      assert html =~ "id=\"server-error\""
      assert html =~ "hidden"
    end
  end

  describe "show/2" do
    test "returns JS struct with show command" do
      js = FeedbackComponents.show("#element")

      assert %JS{} = js
      # JS struct contains ops for show transition
      assert js.ops != []
    end

    test "chains with existing JS struct" do
      initial_js = JS.push("event")
      js = FeedbackComponents.show(initial_js, "#element")

      assert %JS{} = js
      # Should have more ops than initial
      assert length(js.ops) > length(initial_js.ops)
    end
  end

  describe "hide/2" do
    test "returns JS struct with hide command" do
      js = FeedbackComponents.hide("#element")

      assert %JS{} = js
      assert js.ops != []
    end

    test "chains with existing JS struct" do
      initial_js = JS.push("event")
      js = FeedbackComponents.hide(initial_js, "#element")

      assert %JS{} = js
      assert length(js.ops) > length(initial_js.ops)
    end
  end

  describe "show_modal/2" do
    test "returns JS struct with modal show commands" do
      js = FeedbackComponents.show_modal("my-modal")

      assert %JS{} = js
      # Should contain multiple operations for modal animation
      assert length(js.ops) >= 4
    end

    test "chains with existing JS struct" do
      initial_js = JS.push("event")
      js = FeedbackComponents.show_modal(initial_js, "my-modal")

      assert %JS{} = js
      assert length(js.ops) > length(initial_js.ops)
    end
  end

  describe "hide_modal/2" do
    test "returns JS struct with modal hide commands" do
      js = FeedbackComponents.hide_modal("my-modal")

      assert %JS{} = js
      # Should contain multiple operations for modal animation
      assert length(js.ops) >= 4
    end

    test "chains with existing JS struct" do
      initial_js = JS.push("event")
      js = FeedbackComponents.hide_modal(initial_js, "my-modal")

      assert %JS{} = js
      assert length(js.ops) > length(initial_js.ops)
    end
  end
end
