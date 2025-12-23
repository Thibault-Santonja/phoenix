defmodule PortfolioWeb.FormComponentsTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PortfolioWeb.FormComponents

  describe "simple_form/1" do
    test "renders form with proper structure" do
      assigns = %{
        for: %{},
        inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Form content" end}],
        actions: []
      }

      html = render_component(&FormComponents.simple_form/1, assigns)

      assert html =~ "<form"
      assert html =~ "Form content"
    end

    test "renders form with actions slot" do
      assigns = %{
        for: %{},
        inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}],
        actions: [%{__slot__: :actions, inner_block: fn _, _ -> "Submit Button" end}]
      }

      html = render_component(&FormComponents.simple_form/1, assigns)

      assert html =~ "Submit Button"
      assert html =~ "flex items-center justify-between"
    end
  end

  describe "button/1" do
    test "renders button with default type" do
      html =
        render_component(&FormComponents.button/1,
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Click me" end}]
        )

      assert html =~ "<button"
      assert html =~ "Click me"
      assert html =~ "rounded-lg"
      assert html =~ "bg-zinc-900"
    end

    test "renders button with custom type" do
      html =
        render_component(&FormComponents.button/1,
          type: "submit",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Submit" end}]
        )

      assert html =~ "type=\"submit\""
    end

    test "renders button with custom class" do
      html =
        render_component(&FormComponents.button/1,
          class: "ml-4 custom-class",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Styled" end}]
        )

      assert html =~ "ml-4 custom-class"
    end

    test "renders disabled button" do
      html =
        render_component(&FormComponents.button/1,
          disabled: true,
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Disabled" end}]
        )

      assert html =~ "disabled"
    end
  end

  describe "input/1 with text type" do
    test "renders text input with label" do
      html =
        render_component(&FormComponents.input/1,
          id: "name",
          name: "user[name]",
          type: "text",
          label: "Name",
          value: "",
          errors: []
        )

      assert html =~ "type=\"text\""
      assert html =~ "id=\"name\""
      assert html =~ "name=\"user[name]\""
      assert html =~ "Name"
    end

    test "renders input with value" do
      html =
        render_component(&FormComponents.input/1,
          id: "email",
          name: "user[email]",
          type: "email",
          label: "Email",
          value: "test@example.com",
          errors: []
        )

      assert html =~ "value=\"test@example.com\""
    end

    test "renders input with errors" do
      html =
        render_component(&FormComponents.input/1,
          id: "email",
          name: "user[email]",
          type: "email",
          label: "Email",
          value: "",
          errors: ["is invalid"]
        )

      assert html =~ "is invalid"
      assert html =~ "border-rose-400"
      assert html =~ "hero-exclamation-circle-mini"
    end

    test "renders input without errors styling when valid" do
      html =
        render_component(&FormComponents.input/1,
          id: "email",
          name: "user[email]",
          type: "text",
          label: "Email",
          value: "valid@example.com",
          errors: []
        )

      assert html =~ "border-zinc-300"
      refute html =~ "border-rose-400"
    end
  end

  describe "input/1 with checkbox type" do
    test "renders checkbox input" do
      html =
        render_component(&FormComponents.input/1,
          id: "remember",
          name: "user[remember]",
          type: "checkbox",
          label: "Remember me",
          value: false,
          errors: []
        )

      assert html =~ "type=\"checkbox\""
      assert html =~ "Remember me"
      assert html =~ "type=\"hidden\""
      assert html =~ "value=\"false\""
    end

    test "renders checked checkbox" do
      html =
        render_component(&FormComponents.input/1,
          id: "remember",
          name: "user[remember]",
          type: "checkbox",
          label: "Remember me",
          value: true,
          checked: true,
          errors: []
        )

      assert html =~ "checked"
    end
  end

  describe "input/1 with select type" do
    test "renders select input" do
      html =
        render_component(&FormComponents.input/1,
          id: "country",
          name: "user[country]",
          type: "select",
          label: "Country",
          options: [{"France", "fr"}, {"Germany", "de"}],
          value: nil,
          errors: []
        )

      assert html =~ "<select"
      assert html =~ "Country"
      assert html =~ "France"
      assert html =~ "Germany"
      assert html =~ "value=\"fr\""
      assert html =~ "value=\"de\""
    end

    test "renders select with prompt" do
      html =
        render_component(&FormComponents.input/1,
          id: "country",
          name: "user[country]",
          type: "select",
          label: "Country",
          prompt: "Select a country",
          options: [{"France", "fr"}],
          value: nil,
          errors: []
        )

      assert html =~ "Select a country"
    end

    test "renders select with selected value" do
      html =
        render_component(&FormComponents.input/1,
          id: "country",
          name: "user[country]",
          type: "select",
          label: "Country",
          options: [{"France", "fr"}, {"Germany", "de"}],
          value: "de",
          errors: []
        )

      assert html =~ "selected"
    end

    test "renders multiple select" do
      html =
        render_component(&FormComponents.input/1,
          id: "tags",
          name: "post[tags]",
          type: "select",
          label: "Tags",
          options: [{"Elixir", "elixir"}, {"Phoenix", "phoenix"}],
          value: [],
          multiple: true,
          errors: []
        )

      assert html =~ "multiple"
    end
  end

  describe "input/1 with textarea type" do
    test "renders textarea" do
      html =
        render_component(&FormComponents.input/1,
          id: "description",
          name: "post[description]",
          type: "textarea",
          label: "Description",
          value: "Some content",
          errors: []
        )

      assert html =~ "<textarea"
      assert html =~ "Description"
      assert html =~ "Some content"
      assert html =~ "min-h-[6rem]"
    end

    test "renders textarea with errors" do
      html =
        render_component(&FormComponents.input/1,
          id: "description",
          name: "post[description]",
          type: "textarea",
          label: "Description",
          value: "",
          errors: ["can't be blank"]
        )

      # HTML encodes apostrophe as &#39;
      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
      assert html =~ "border-rose-400"
    end
  end

  describe "label/1" do
    test "renders label with for attribute" do
      html =
        render_component(&FormComponents.label/1,
          for: "email",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Email" end}]
        )

      assert html =~ "<label"
      assert html =~ "for=\"email\""
      assert html =~ "Email"
      assert html =~ "font-semibold"
    end

    test "renders label without for attribute" do
      html =
        render_component(&FormComponents.label/1,
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Label text" end}]
        )

      assert html =~ "<label"
      assert html =~ "Label text"
    end
  end

  describe "error/1" do
    test "renders error message with icon" do
      html =
        render_component(&FormComponents.error/1,
          inner_block: [
            %{__slot__: :inner_block, inner_block: fn _, _ -> "Field is required" end}
          ]
        )

      assert html =~ "Field is required"
      assert html =~ "text-rose-600"
      assert html =~ "hero-exclamation-circle-mini"
    end
  end

  describe "translate_error/1" do
    test "translates error without count" do
      result = FormComponents.translate_error({"is invalid", []})
      assert result == "is invalid"
    end

    test "translates error with count" do
      result =
        FormComponents.translate_error({"should be at least %{count} character(s)", [count: 3]})

      assert result =~ "3"
    end
  end

  describe "translate_errors/2" do
    test "translates errors for a specific field" do
      errors = [
        {:email, {"is invalid", []}},
        {:email, {"can't be blank", []}},
        {:name, {"is required", []}}
      ]

      result = FormComponents.translate_errors(errors, :email)

      assert length(result) == 2
      assert "is invalid" in result
      assert "can't be blank" in result
    end

    test "returns empty list when no errors for field" do
      errors = [{:name, {"is required", []}}]

      result = FormComponents.translate_errors(errors, :email)

      assert result == []
    end
  end
end
