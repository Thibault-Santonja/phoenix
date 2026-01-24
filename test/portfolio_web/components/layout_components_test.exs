defmodule PortfolioWeb.LayoutComponentsTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PortfolioWeb.LayoutComponents

  describe "header/1" do
    test "renders header with title" do
      html =
        render_component(&LayoutComponents.header/1,
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Page Title" end}],
          subtitle: [],
          actions: []
        )

      assert html =~ "<header"
      assert html =~ "Page Title"
      assert html =~ "text-lg font-semibold"
    end

    test "renders header with subtitle" do
      html =
        render_component(&LayoutComponents.header/1,
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Title" end}],
          subtitle: [%{__slot__: :subtitle, inner_block: fn _, _ -> "Subtitle text" end}],
          actions: []
        )

      assert html =~ "Title"
      assert html =~ "Subtitle text"
      assert html =~ "text-zinc-600"
    end

    test "renders header with actions" do
      html =
        render_component(&LayoutComponents.header/1,
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Title" end}],
          subtitle: [],
          actions: [%{__slot__: :actions, inner_block: fn _, _ -> "Action Button" end}]
        )

      assert html =~ "Action Button"
      assert html =~ "flex items-center justify-between"
    end

    test "renders header with custom class" do
      html =
        render_component(&LayoutComponents.header/1,
          class: "custom-header-class",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Title" end}],
          subtitle: [],
          actions: []
        )

      assert html =~ "custom-header-class"
    end
  end

  describe "table/1" do
    test "renders table with columns" do
      rows = [
        %{id: 1, name: "Alice", email: "alice@example.com"},
        %{id: 2, name: "Bob", email: "bob@example.com"}
      ]

      html =
        render_component(&LayoutComponents.table/1,
          id: "users-table",
          rows: rows,
          col: [
            %{__slot__: :col, label: "Name", inner_block: fn _, row -> row.name end},
            %{__slot__: :col, label: "Email", inner_block: fn _, row -> row.email end}
          ],
          action: []
        )

      assert html =~ "id=\"users-table\""
      assert html =~ "<table"
      assert html =~ "<thead"
      assert html =~ "<tbody"
      assert html =~ "Name"
      assert html =~ "Email"
      assert html =~ "Alice"
      assert html =~ "Bob"
    end

    test "renders table with actions column" do
      rows = [%{id: 1, name: "Alice"}]

      html =
        render_component(&LayoutComponents.table/1,
          id: "users-table",
          rows: rows,
          col: [
            %{__slot__: :col, label: "Name", inner_block: fn _, row -> row.name end}
          ],
          action: [
            %{__slot__: :action, inner_block: fn _, _row -> "Edit" end}
          ]
        )

      assert html =~ "Edit"
      assert html =~ "sr-only"
    end

    test "renders empty table" do
      html =
        render_component(&LayoutComponents.table/1,
          id: "empty-table",
          rows: [],
          col: [
            %{__slot__: :col, label: "Name", inner_block: fn _, row -> row.name end}
          ],
          action: []
        )

      assert html =~ "id=\"empty-table\""
      assert html =~ "<thead"
      assert html =~ "Name"
    end

    test "renders table with custom row_id function" do
      rows = [%{uuid: "abc-123", name: "Test"}]

      html =
        render_component(&LayoutComponents.table/1,
          id: "custom-table",
          rows: rows,
          row_id: fn row -> "row-#{row.uuid}" end,
          col: [
            %{__slot__: :col, label: "Name", inner_block: fn _, row -> row.name end}
          ],
          action: []
        )

      assert html =~ "row-abc-123"
    end

    test "renders table with row_item transformation" do
      rows = [%{id: 1, data: %{name: "Nested"}}]

      html =
        render_component(&LayoutComponents.table/1,
          id: "transform-table",
          rows: rows,
          row_item: fn row -> row.data end,
          col: [
            %{__slot__: :col, label: "Name", inner_block: fn _, item -> item.name end}
          ],
          action: []
        )

      assert html =~ "Nested"
    end
  end

  describe "list/1" do
    test "renders list with items" do
      html =
        render_component(&LayoutComponents.list/1,
          item: [
            %{__slot__: :item, title: "Name", inner_block: fn _, _ -> "John Doe" end},
            %{__slot__: :item, title: "Email", inner_block: fn _, _ -> "john@example.com" end}
          ]
        )

      assert html =~ "<dl"
      assert html =~ "Name"
      assert html =~ "John Doe"
      assert html =~ "Email"
      assert html =~ "john@example.com"
    end

    test "renders list with proper styling" do
      html =
        render_component(&LayoutComponents.list/1,
          item: [
            %{__slot__: :item, title: "Field", inner_block: fn _, _ -> "Value" end}
          ]
        )

      assert html =~ "divide-y"
      assert html =~ "divide-zinc-100"
      assert html =~ "text-zinc-500"
      assert html =~ "text-zinc-700"
    end
  end

  describe "back/1" do
    test "renders back navigation link" do
      html =
        render_component(&LayoutComponents.back/1,
          navigate: "/posts",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Back to posts" end}]
        )

      assert html =~ "href=\"/posts\""
      assert html =~ "Back to posts"
      assert html =~ "hero-arrow-left-solid"
    end

    test "renders back link with proper styling" do
      html =
        render_component(&LayoutComponents.back/1,
          navigate: "/home",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Go back" end}]
        )

      assert html =~ "font-semibold"
      assert html =~ "text-zinc-900"
      assert html =~ "hover:text-zinc-700"
    end
  end
end
