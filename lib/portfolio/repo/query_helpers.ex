defmodule Portfolio.Repo.QueryHelpers do
  @moduledoc """
  Shared query helper functions for repositories.

  This module provides common query operations used across multiple
  repositories to reduce code duplication and ensure consistent behavior.

  ## Usage

      import Portfolio.Repo.QueryHelpers

      # In a repository function:
      query
      |> maybe_preload(opts[:preload])
      |> Repo.one()
  """

  import Ecto.Query, warn: false

  @doc """
  Conditionally applies preloads to a query.

  Returns the query unchanged if preloads is nil or empty.
  Otherwise, applies the specified preloads.

  ## Parameters

  - `query` - The Ecto query to modify
  - `preloads` - List of associations to preload, nil, or empty list

  ## Examples

      iex> query |> maybe_preload(nil)
      # Returns query unchanged

      iex> query |> maybe_preload([])
      # Returns query unchanged

      iex> query |> maybe_preload([:user])
      # Returns query with user preloaded

      iex> query |> maybe_preload([:user, :photos])
      # Returns query with user and photos preloaded
  """
  @spec maybe_preload(Ecto.Query.t(), nil | [atom()]) :: Ecto.Query.t()
  def maybe_preload(query, nil), do: query
  def maybe_preload(query, []), do: query
  def maybe_preload(query, preloads) when is_list(preloads), do: preload(query, ^preloads)
  def maybe_preload(query, preload) when is_atom(preload), do: preload(query, ^[preload])

  @doc """
  Wraps a query result in an ok/error tuple.

  Converts nil results to `{:error, :not_found}` and non-nil results
  to `{:ok, result}`.

  ## Parameters

  - `result` - The result from Repo.one() or similar

  ## Examples

      iex> wrap_result(nil)
      {:error, :not_found}

      iex> wrap_result(%User{id: 1})
      {:ok, %User{id: 1}}
  """
  @spec wrap_result(term() | nil) :: {:ok, term()} | {:error, :not_found}
  def wrap_result(nil), do: {:error, :not_found}
  def wrap_result(result), do: {:ok, result}

  @doc """
  Conditionally applies a limit to a query.

  Returns the query unchanged if limit is nil.

  ## Examples

      iex> query |> maybe_limit(nil)
      # Returns query unchanged

      iex> query |> maybe_limit(10)
      # Returns query with LIMIT 10
  """
  @spec maybe_limit(Ecto.Query.t(), nil | pos_integer()) :: Ecto.Query.t()
  def maybe_limit(query, nil), do: query
  def maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)

  @doc """
  Conditionally applies an offset to a query.

  Returns the query unchanged if offset is nil.

  ## Examples

      iex> query |> maybe_offset(nil)
      # Returns query unchanged

      iex> query |> maybe_offset(20)
      # Returns query with OFFSET 20
  """
  @spec maybe_offset(Ecto.Query.t(), nil | non_neg_integer()) :: Ecto.Query.t()
  def maybe_offset(query, nil), do: query

  def maybe_offset(query, offset) when is_integer(offset) and offset >= 0,
    do: offset(query, ^offset)

  @doc """
  Conditionally applies ordering to a query.

  Returns the query unchanged if order_by is nil or empty.

  ## Examples

      iex> query |> maybe_order_by(nil)
      # Returns query unchanged

      iex> query |> maybe_order_by([desc: :inserted_at])
      # Returns query ordered by inserted_at DESC
  """
  @spec maybe_order_by(Ecto.Query.t(), nil | keyword()) :: Ecto.Query.t()
  def maybe_order_by(query, nil), do: query
  def maybe_order_by(query, []), do: query
  def maybe_order_by(query, order_spec) when is_list(order_spec), do: order_by(query, ^order_spec)
end
