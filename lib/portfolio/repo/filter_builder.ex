defmodule Portfolio.Repo.FilterBuilder do
  @moduledoc """
  Generic filter builder for repository queries.

  This module provides a declarative way to apply filters to Ecto queries,
  eliminating code duplication across repositories. Each repository can define
  its own custom filter handlers while reusing common patterns.

  ## Usage

  In your repository, define a `@filter_handlers` map and use `apply_filters/3`:

      defmodule MyRepository do
        import Portfolio.Repo.FilterBuilder

        @filter_handlers %{
          status: &__MODULE__.filter_by_status/2,
          category: &__MODULE__.filter_by_category/2
        }

        def list(opts \\\\ []) do
          MySchema
          |> from()
          |> apply_filters(opts, @filter_handlers)
          |> Repo.all()
        end

        def filter_by_status(query, status), do: where(query, [m], m.status == ^status)
        def filter_by_category(query, cat), do: where(query, [m], m.category == ^cat)
      end

  ## Built-in Filters

  The following filters are handled automatically by `apply_common_filter/3`:

  - `:preload` - Preload associations
  - `:limit` - Limit number of results
  - `:offset` - Skip results for pagination
  - `:order_by` - Order results

  ## Design Principles

  1. **DRY**: Common filters (preload, limit, offset, order_by) are handled once
  2. **Open/Closed**: Custom filters are added via handler maps, not code changes
  3. **Liskov**: All repositories use the same interface for filtering
  """

  import Ecto.Query, warn: false

  @type filter_handler :: (Ecto.Query.t(), term() -> Ecto.Query.t())
  @type filter_handlers :: %{atom() => filter_handler()}

  @doc """
  Applies a list of filters to a query using custom handlers.

  Iterates through the filter options and applies each one using either:
  1. A custom handler from the `handlers` map
  2. A built-in common filter handler
  3. Skips unknown filters (allows extension without breaking)

  ## Parameters

  - `query` - The base Ecto query
  - `opts` - Keyword list of filter options
  - `handlers` - Map of filter names to handler functions

  ## Examples

      iex> handlers = %{status: &filter_by_status/2}
      iex> apply_filters(query, [status: :active, limit: 10], handlers)
      # Returns query with status filter and limit applied
  """
  @spec apply_filters(Ecto.Query.t(), keyword(), filter_handlers()) :: Ecto.Query.t()
  def apply_filters(query, opts, handlers \\ %{})

  def apply_filters(query, [], _handlers), do: query

  def apply_filters(query, [{key, value} | rest], handlers) do
    query
    |> apply_single_filter(key, value, handlers)
    |> apply_filters(rest, handlers)
  end

  @doc """
  Applies a single filter to a query.

  Checks custom handlers first, then falls back to common filters.
  Unknown filters are silently ignored to allow forward compatibility.

  ## Parameters

  - `query` - The Ecto query
  - `key` - The filter key (atom)
  - `value` - The filter value
  - `handlers` - Map of custom filter handlers

  ## Examples

      iex> apply_single_filter(query, :limit, 10, %{})
      # Returns query with LIMIT 10

      iex> apply_single_filter(query, :status, :active, %{status: &handler/2})
      # Returns query with custom status filter applied
  """
  @spec apply_single_filter(Ecto.Query.t(), atom(), term(), filter_handlers()) :: Ecto.Query.t()
  def apply_single_filter(query, key, value, handlers) do
    cond do
      # Check for custom handler first
      Map.has_key?(handlers, key) ->
        handler = Map.get(handlers, key)
        handler.(query, value)

      # Fall back to common filters
      common_filter?(key) ->
        apply_common_filter(query, key, value)

      # Unknown filter - skip silently (allows extension)
      true ->
        query
    end
  end

  @doc """
  Checks if a filter key is a common/built-in filter.

  Common filters are: :preload, :limit, :offset, :order_by

  ## Examples

      iex> common_filter?(:limit)
      true

      iex> common_filter?(:status)
      false
  """
  @spec common_filter?(atom()) :: boolean()
  def common_filter?(key) when key in [:preload, :limit, :offset, :order_by], do: true
  def common_filter?(_key), do: false

  @doc """
  Applies a common/built-in filter to a query.

  ## Supported Filters

  - `:preload` - Preloads associations (list of atoms or single atom)
  - `:limit` - Limits number of results (positive integer)
  - `:offset` - Skips results for pagination (non-negative integer)
  - `:order_by` - Orders results (keyword list like `[desc: :inserted_at]`)

  ## Examples

      iex> apply_common_filter(query, :limit, 10)
      # query with LIMIT 10

      iex> apply_common_filter(query, :preload, [:user, :photos])
      # query with user and photos preloaded

      iex> apply_common_filter(query, :order_by, [desc: :inserted_at])
      # query ordered by inserted_at DESC
  """
  @spec apply_common_filter(Ecto.Query.t(), atom(), term()) :: Ecto.Query.t()
  def apply_common_filter(query, :preload, nil), do: query
  def apply_common_filter(query, :preload, []), do: query

  def apply_common_filter(query, :preload, preloads) when is_list(preloads) do
    preload(query, ^preloads)
  end

  def apply_common_filter(query, :preload, preload) when is_atom(preload) do
    preload(query, ^[preload])
  end

  def apply_common_filter(query, :limit, nil), do: query

  def apply_common_filter(query, :limit, limit) when is_integer(limit) and limit > 0 do
    limit(query, ^limit)
  end

  def apply_common_filter(query, :offset, nil), do: query

  def apply_common_filter(query, :offset, offset) when is_integer(offset) and offset >= 0 do
    offset(query, ^offset)
  end

  def apply_common_filter(query, :order_by, nil), do: query
  def apply_common_filter(query, :order_by, []), do: query

  def apply_common_filter(query, :order_by, order_spec) when is_list(order_spec) do
    order_by(query, ^order_spec)
  end

  # Fallback for invalid values - return query unchanged
  def apply_common_filter(query, _key, _value), do: query
end
