defmodule Portfolio.Photography.Queries.PhotoQuery do
  @moduledoc """
  Query builder for Photo queries.

  Separates query construction logic from repository,
  following the Query Object pattern from DDD.

  This module provides composable query builders for Photo queries,
  keeping the repository focused on data access operations.

  ## Examples

      iex> PhotoQuery.base()
      ...> |> PhotoQuery.by_album(album_id)
      ...> |> PhotoQuery.order_by_display_order()
      #Ecto.Query<...>

      iex> PhotoQuery.base()
      ...> |> PhotoQuery.published()
      ...> |> PhotoQuery.with_album()
      #Ecto.Query<...>

  """

  import Ecto.Query

  alias Portfolio.Photography.Photo

  @doc """
  Base query for photos.

  Returns a query with the photo binding named `:photo`.

  ## Examples

      iex> PhotoQuery.base()
      #Ecto.Query<from p0 in Portfolio.Photography.Photo, as: :photo>

  """
  @spec base() :: Ecto.Query.t()
  def base do
    from(p in Photo, as: :photo)
  end

  @doc """
  Filters photos by album ID.

  ## Examples

      iex> PhotoQuery.base() |> PhotoQuery.by_album(album_id)
      #Ecto.Query<...>

  """
  @spec by_album(Ecto.Query.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  def by_album(query, album_id) do
    where(query, [photo: p], p.album_id == ^album_id)
  end

  @doc """
  Filters published photos only.

  ## Examples

      iex> PhotoQuery.base() |> PhotoQuery.published()
      #Ecto.Query<...>

  """
  @spec published(Ecto.Query.t()) :: Ecto.Query.t()
  def published(query) do
    where(query, [photo: p], p.published == true)
  end

  @doc """
  Filters unpublished photos only.

  ## Examples

      iex> PhotoQuery.base() |> PhotoQuery.unpublished()
      #Ecto.Query<...>

  """
  @spec unpublished(Ecto.Query.t()) :: Ecto.Query.t()
  def unpublished(query) do
    where(query, [photo: p], p.published == false)
  end

  @doc """
  Orders photos by display_order ascending.

  ## Examples

      iex> PhotoQuery.base() |> PhotoQuery.order_by_display_order()
      #Ecto.Query<...>

  """
  @spec order_by_display_order(Ecto.Query.t()) :: Ecto.Query.t()
  def order_by_display_order(query) do
    order_by(query, [photo: p], asc: p.display_order)
  end

  @doc """
  Orders photos by taken_at descending (most recent first).

  ## Examples

      iex> PhotoQuery.base() |> PhotoQuery.order_by_date_desc()
      #Ecto.Query<...>

  """
  @spec order_by_date_desc(Ecto.Query.t()) :: Ecto.Query.t()
  def order_by_date_desc(query) do
    order_by(query, [photo: p], desc: p.taken_at)
  end

  @doc """
  Preloads the album association.

  ## Examples

      iex> PhotoQuery.base() |> PhotoQuery.with_album()
      #Ecto.Query<...>

  """
  @spec with_album(Ecto.Query.t()) :: Ecto.Query.t()
  def with_album(query) do
    preload(query, [:album])
  end

  @doc """
  Preloads associations.

  Accepts a single association or a list of associations.

  ## Examples

      iex> PhotoQuery.base() |> PhotoQuery.with_preload(:album)
      #Ecto.Query<...>

      iex> PhotoQuery.base() |> PhotoQuery.with_preload([:album])
      #Ecto.Query<...>

  """
  @spec with_preload(Ecto.Query.t(), atom() | [atom()]) :: Ecto.Query.t()
  def with_preload(query, preloads) when is_list(preloads) do
    preload(query, ^preloads)
  end

  def with_preload(query, preload) when is_atom(preload) do
    with_preload(query, [preload])
  end
end
