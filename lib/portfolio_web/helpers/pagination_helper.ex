defmodule PortfolioWeb.Helpers.PaginationHelper do
  @moduledoc """
  Helper functions for pagination across LiveViews.

  Provides consistent pagination logic for admin and public pages,
  eliminating duplication of offset/limit calculations.

  ## Usage

      # In LiveView mount
      socket
      |> assign(:page, 1)
      |> assign(:per_page, 30)

      # When loading data
      opts = PaginationHelper.build_opts(page, per_page)
      # => [limit: 30, offset: 0]

      # Calculate total pages
      total_pages = PaginationHelper.total_pages(total_count, per_page)

      # Get display range for "Showing X to Y of Z"
      {from, to} = PaginationHelper.display_range(page, per_page, total_count)
  """

  @doc """
  Calculates the offset for a given page and per_page value.

  ## Examples

      iex> PaginationHelper.offset(1, 30)
      0

      iex> PaginationHelper.offset(2, 30)
      30

      iex> PaginationHelper.offset(3, 50)
      100
  """
  @spec offset(pos_integer(), pos_integer()) :: non_neg_integer()
  def offset(page, per_page) when page >= 1 and per_page >= 1 do
    (page - 1) * per_page
  end

  @doc """
  Builds pagination options for queries.

  Returns a keyword list with `:limit` and `:offset` keys.

  ## Options

    * `:extra` - Additional options to merge (default: `[]`)

  ## Examples

      iex> PaginationHelper.build_opts(1, 30)
      [limit: 30, offset: 0]

      iex> PaginationHelper.build_opts(2, 50, extra: [preload: [:album]])
      [limit: 50, offset: 50, preload: [:album]]
  """
  @spec build_opts(pos_integer(), pos_integer(), keyword()) :: keyword()
  def build_opts(page, per_page, opts \\ []) do
    extra = Keyword.get(opts, :extra, [])

    [limit: per_page, offset: offset(page, per_page)]
    |> Keyword.merge(extra)
  end

  @doc """
  Calculates the total number of pages.

  ## Examples

      iex> PaginationHelper.total_pages(100, 30)
      4

      iex> PaginationHelper.total_pages(90, 30)
      3

      iex> PaginationHelper.total_pages(0, 30)
      1
  """
  @spec total_pages(non_neg_integer(), pos_integer()) :: pos_integer()
  def total_pages(total_count, per_page) when per_page >= 1 do
    max(1, ceil(total_count / per_page))
  end

  @doc """
  Returns the display range for pagination info.

  Returns a tuple `{from, to}` for "Showing X to Y of Z" displays.

  ## Examples

      iex> PaginationHelper.display_range(1, 30, 100)
      {1, 30}

      iex> PaginationHelper.display_range(2, 30, 100)
      {31, 60}

      iex> PaginationHelper.display_range(4, 30, 100)
      {91, 100}

      iex> PaginationHelper.display_range(1, 30, 0)
      {0, 0}
  """
  @spec display_range(pos_integer(), pos_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def display_range(_page, _per_page, 0), do: {0, 0}

  def display_range(page, per_page, total_count) when page >= 1 and per_page >= 1 do
    from = (page - 1) * per_page + 1
    to = min(page * per_page, total_count)
    {from, to}
  end

  @doc """
  Clamps a page number to valid bounds.

  Ensures the page is at least 1 and at most the total pages.

  ## Examples

      iex> PaginationHelper.clamp_page(0, 10)
      1

      iex> PaginationHelper.clamp_page(5, 3)
      3

      iex> PaginationHelper.clamp_page(2, 5)
      2
  """
  @spec clamp_page(integer(), pos_integer()) :: pos_integer()
  def clamp_page(page, total_pages) do
    page
    |> max(1)
    |> min(max(1, total_pages))
  end

  @doc """
  Parses a page parameter from string input.

  Returns 1 for invalid or nil inputs.

  ## Examples

      iex> PaginationHelper.parse_page("3")
      3

      iex> PaginationHelper.parse_page("invalid")
      1

      iex> PaginationHelper.parse_page(nil)
      1

      iex> PaginationHelper.parse_page("-1")
      1
  """
  @spec parse_page(String.t() | nil) :: pos_integer()
  def parse_page(nil), do: 1

  def parse_page(page_str) when is_binary(page_str) do
    case Integer.parse(page_str) do
      {page, ""} when page >= 1 -> page
      _ -> 1
    end
  end

  def parse_page(_), do: 1

  @doc """
  Checks if there are more pages after the current one.

  ## Examples

      iex> PaginationHelper.has_next_page?(1, 3)
      true

      iex> PaginationHelper.has_next_page?(3, 3)
      false
  """
  @spec has_next_page?(pos_integer(), pos_integer()) :: boolean()
  def has_next_page?(current_page, total_pages) do
    current_page < total_pages
  end

  @doc """
  Checks if there are pages before the current one.

  ## Examples

      iex> PaginationHelper.has_prev_page?(1)
      false

      iex> PaginationHelper.has_prev_page?(2)
      true
  """
  @spec has_prev_page?(pos_integer()) :: boolean()
  def has_prev_page?(current_page) do
    current_page > 1
  end

  @doc """
  Generates a range of page numbers to display in pagination controls.

  Centers the range around the current page, showing at most `max_pages` numbers.
  Handles edge cases near the start and end of the total pages.

  ## Options

    * `:max_pages` - Maximum number of page buttons to show (default: 7)

  ## Examples

      iex> PaginationHelper.page_range(1, 10)
      1..7

      iex> PaginationHelper.page_range(5, 10)
      2..8

      iex> PaginationHelper.page_range(9, 10)
      4..10

      iex> PaginationHelper.page_range(2, 3)
      1..3

      iex> PaginationHelper.page_range(1, 1)
      1..1
  """
  @spec page_range(pos_integer(), pos_integer(), keyword()) :: Range.t()
  def page_range(current_page, total_pages, opts \\ [])

  def page_range(_current_page, 0, _opts), do: 1..1

  def page_range(current_page, total_pages, opts) when current_page >= 1 and total_pages >= 1 do
    max_pages = Keyword.get(opts, :max_pages, 7)
    half = div(max_pages, 2)

    cond do
      total_pages <= max_pages ->
        1..total_pages

      current_page <= half + 1 ->
        1..max_pages

      current_page >= total_pages - half ->
        (total_pages - max_pages + 1)..total_pages

      true ->
        (current_page - half)..(current_page + half)
    end
  end
end
