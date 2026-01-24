defmodule PortfolioWeb.Helpers.PaginationHelperTest do
  use ExUnit.Case, async: true

  alias PortfolioWeb.Helpers.PaginationHelper

  doctest PortfolioWeb.Helpers.PaginationHelper

  describe "offset/2" do
    test "returns 0 for first page" do
      assert PaginationHelper.offset(1, 30) == 0
      assert PaginationHelper.offset(1, 50) == 0
    end

    test "calculates correct offset for subsequent pages" do
      assert PaginationHelper.offset(2, 30) == 30
      assert PaginationHelper.offset(3, 30) == 60
      assert PaginationHelper.offset(2, 50) == 50
    end
  end

  describe "build_opts/3" do
    test "returns limit and offset" do
      assert PaginationHelper.build_opts(1, 30) == [limit: 30, offset: 0]
      assert PaginationHelper.build_opts(2, 50) == [limit: 50, offset: 50]
    end

    test "merges extra options" do
      opts = PaginationHelper.build_opts(1, 30, extra: [preload: [:album], order_by: :title])

      assert Keyword.get(opts, :limit) == 30
      assert Keyword.get(opts, :offset) == 0
      assert Keyword.get(opts, :preload) == [:album]
      assert Keyword.get(opts, :order_by) == :title
    end
  end

  describe "total_pages/2" do
    test "calculates correct number of pages" do
      assert PaginationHelper.total_pages(100, 30) == 4
      assert PaginationHelper.total_pages(90, 30) == 3
      assert PaginationHelper.total_pages(91, 30) == 4
    end

    test "returns 1 for zero items" do
      assert PaginationHelper.total_pages(0, 30) == 1
    end

    test "returns 1 when items fit on one page" do
      assert PaginationHelper.total_pages(15, 30) == 1
      assert PaginationHelper.total_pages(30, 30) == 1
    end
  end

  describe "display_range/3" do
    test "returns correct range for first page" do
      assert PaginationHelper.display_range(1, 30, 100) == {1, 30}
    end

    test "returns correct range for middle pages" do
      assert PaginationHelper.display_range(2, 30, 100) == {31, 60}
      assert PaginationHelper.display_range(3, 30, 100) == {61, 90}
    end

    test "caps to at total count for last page" do
      assert PaginationHelper.display_range(4, 30, 100) == {91, 100}
    end

    test "returns zeros for empty results" do
      assert PaginationHelper.display_range(1, 30, 0) == {0, 0}
    end
  end

  describe "clamp_page/2" do
    test "clamps page below 1 to 1" do
      assert PaginationHelper.clamp_page(0, 10) == 1
      assert PaginationHelper.clamp_page(-5, 10) == 1
    end

    test "clamps page above total to total" do
      assert PaginationHelper.clamp_page(15, 10) == 10
    end

    test "keeps valid page unchanged" do
      assert PaginationHelper.clamp_page(5, 10) == 5
    end

    test "handles edge case of 0 total pages" do
      assert PaginationHelper.clamp_page(5, 0) == 1
    end
  end

  describe "parse_page/1" do
    test "parses valid page numbers" do
      assert PaginationHelper.parse_page("1") == 1
      assert PaginationHelper.parse_page("5") == 5
      assert PaginationHelper.parse_page("100") == 100
    end

    test "returns 1 for invalid input" do
      assert PaginationHelper.parse_page("invalid") == 1
      assert PaginationHelper.parse_page("1.5") == 1
      assert PaginationHelper.parse_page("") == 1
    end

    test "returns 1 for nil" do
      assert PaginationHelper.parse_page(nil) == 1
    end

    test "returns 1 for negative numbers" do
      assert PaginationHelper.parse_page("-1") == 1
      assert PaginationHelper.parse_page("0") == 1
    end
  end

  describe "has_next_page?/2" do
    test "returns true when more pages exist" do
      assert PaginationHelper.has_next_page?(1, 3) == true
      assert PaginationHelper.has_next_page?(2, 3) == true
    end

    test "returns false on last page" do
      assert PaginationHelper.has_next_page?(3, 3) == false
    end
  end

  describe "has_prev_page?/1" do
    test "returns false on first page" do
      assert PaginationHelper.has_prev_page?(1) == false
    end

    test "returns true on subsequent pages" do
      assert PaginationHelper.has_prev_page?(2) == true
      assert PaginationHelper.has_prev_page?(10) == true
    end
  end

  describe "page_range/3" do
    test "returns full range when total pages is small" do
      assert PaginationHelper.page_range(1, 3) == 1..3
      assert PaginationHelper.page_range(2, 5) == 1..5
      assert PaginationHelper.page_range(3, 7) == 1..7
    end

    test "returns first max_pages when near start" do
      assert PaginationHelper.page_range(1, 10) == 1..7
      assert PaginationHelper.page_range(2, 10) == 1..7
      assert PaginationHelper.page_range(3, 10) == 1..7
      assert PaginationHelper.page_range(4, 10) == 1..7
    end

    test "returns last max_pages when near end" do
      assert PaginationHelper.page_range(10, 10) == 4..10
      assert PaginationHelper.page_range(9, 10) == 4..10
      assert PaginationHelper.page_range(8, 10) == 4..10
      assert PaginationHelper.page_range(7, 10) == 4..10
    end

    test "centers range around current page in middle" do
      assert PaginationHelper.page_range(5, 10) == 2..8
      assert PaginationHelper.page_range(6, 10) == 3..9
      assert PaginationHelper.page_range(10, 20) == 7..13
      assert PaginationHelper.page_range(15, 30) == 12..18
    end

    test "handles single page" do
      assert PaginationHelper.page_range(1, 1) == 1..1
    end

    test "handles zero total pages" do
      assert PaginationHelper.page_range(1, 0) == 1..1
    end

    test "respects custom max_pages option" do
      assert PaginationHelper.page_range(5, 20, max_pages: 5) == 3..7
      assert PaginationHelper.page_range(1, 10, max_pages: 3) == 1..3
      assert PaginationHelper.page_range(10, 10, max_pages: 5) == 6..10
    end
  end
end
