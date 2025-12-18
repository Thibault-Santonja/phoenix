defmodule PortfolioWeb.Helpers.SortHelperTest do
  use ExUnit.Case, async: true

  alias PortfolioWeb.Helpers.SortHelper

  describe "next_sort_state/3" do
    test "returns ascending for non-date column when no sort active" do
      assert SortHelper.next_sort_state("title", nil, nil) == {"title", "asc"}
    end

    test "returns descending for date column when no sort active" do
      assert SortHelper.next_sort_state("date", nil, nil) == {"date", "desc"}
    end

    test "returns ascending when clicking on a different column" do
      assert SortHelper.next_sort_state("title", "type", "asc") == {"title", "asc"}
      assert SortHelper.next_sort_state("title", "type", "desc") == {"title", "asc"}
    end

    test "returns descending for date when clicking on a different column" do
      assert SortHelper.next_sort_state("date", "title", "asc") == {"date", "desc"}
    end

    test "cycles non-date column: asc -> desc" do
      assert SortHelper.next_sort_state("title", "title", "asc") == {"title", "desc"}
    end

    test "cycles non-date column: desc -> none" do
      assert SortHelper.next_sort_state("title", "title", "desc") == {nil, nil}
    end

    test "cycles date column: desc -> asc" do
      assert SortHelper.next_sort_state("date", "date", "desc") == {"date", "asc"}
    end

    test "cycles date column: asc -> none" do
      assert SortHelper.next_sort_state("date", "date", "asc") == {nil, nil}
    end
  end

  describe "initial_sort_order/1" do
    test "date column starts with descending" do
      assert SortHelper.initial_sort_order("date") == {"date", "desc"}
    end

    test "non-date columns start with ascending" do
      assert SortHelper.initial_sort_order("title") == {"title", "asc"}
      assert SortHelper.initial_sort_order("type") == {"type", "asc"}
      assert SortHelper.initial_sort_order("published") == {"published", "asc"}
    end
  end

  describe "cycle_sort_order/2" do
    test "date desc cycles to asc" do
      assert SortHelper.cycle_sort_order("date", "desc") == {"date", "asc"}
    end

    test "date asc cycles to none" do
      assert SortHelper.cycle_sort_order("date", "asc") == {nil, nil}
    end

    test "non-date asc cycles to desc" do
      assert SortHelper.cycle_sort_order("title", "asc") == {"title", "desc"}
      assert SortHelper.cycle_sort_order("type", "asc") == {"type", "desc"}
    end

    test "non-date desc cycles to none" do
      assert SortHelper.cycle_sort_order("title", "desc") == {nil, nil}
      assert SortHelper.cycle_sort_order("type", "desc") == {nil, nil}
    end

    test "nil order cycles to none" do
      assert SortHelper.cycle_sort_order("title", nil) == {nil, nil}
    end

    test "invalid order cycles to none" do
      assert SortHelper.cycle_sort_order("title", "invalid") == {nil, nil}
    end
  end

  describe "sort_icon/3" do
    test "returns up arrow for ascending sort" do
      assert SortHelper.sort_icon("title", "title", "asc") == "↑"
    end

    test "returns down arrow for descending sort" do
      assert SortHelper.sort_icon("title", "title", "desc") == "↓"
    end

    test "returns empty string when column is not sorted" do
      assert SortHelper.sort_icon("title", "date", "asc") == ""
      assert SortHelper.sort_icon("title", "date", "desc") == ""
    end

    test "returns empty string when no column is sorted" do
      assert SortHelper.sort_icon("title", nil, nil) == ""
    end

    test "returns empty string when sort order is nil" do
      assert SortHelper.sort_icon("title", "title", nil) == ""
    end
  end

  describe "build_order_by/4" do
    @column_mapping %{
      "title" => :title,
      "date" => :date_prise_vue,
      "type" => :type,
      "photos" => :photo_count
    }

    @default_order [desc: :date_prise_vue]

    test "builds ascending order clause" do
      assert SortHelper.build_order_by("title", "asc", @column_mapping) == [asc: :title]
      assert SortHelper.build_order_by("date", "asc", @column_mapping) == [asc: :date_prise_vue]
    end

    test "builds descending order clause" do
      assert SortHelper.build_order_by("title", "desc", @column_mapping) == [desc: :title]
      assert SortHelper.build_order_by("photos", "desc", @column_mapping) == [desc: :photo_count]
    end

    test "returns default order when sort_by is nil" do
      assert SortHelper.build_order_by(nil, "asc", @column_mapping, @default_order) ==
               @default_order
    end

    test "returns default order when sort_order is nil" do
      assert SortHelper.build_order_by("title", nil, @column_mapping, @default_order) ==
               @default_order
    end

    test "returns default order for unknown column" do
      assert SortHelper.build_order_by("unknown", "asc", @column_mapping, @default_order) ==
               @default_order
    end

    test "returns empty list when no default order provided" do
      assert SortHelper.build_order_by(nil, nil, @column_mapping) == []
      assert SortHelper.build_order_by("unknown", "asc", @column_mapping) == []
    end
  end
end
