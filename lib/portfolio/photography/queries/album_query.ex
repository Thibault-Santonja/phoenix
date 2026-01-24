defmodule Portfolio.Photography.Queries.AlbumQuery do
  @moduledoc """
  Query builder for Album queries.

  Separates query construction logic from repository,
  following the Query Object pattern from DDD.

  This module provides composable query builders that can be chained
  to construct complex queries while keeping the repository focused
  on data access operations.

  ## Examples

      iex> AlbumQuery.base()
      ...> |> AlbumQuery.published()
      ...> |> AlbumQuery.order_by_date_desc()
      #Ecto.Query<...>

      iex> AlbumQuery.base()
      ...> |> AlbumQuery.by_type("wedding")
      ...> |> AlbumQuery.with_photos()
      #Ecto.Query<...>

  """

  import Ecto.Query

  alias Portfolio.Photography.Album
  alias Portfolio.Photography.Photo

  @doc """
  Base query for albums.

  Returns a query with the album binding named `:album`.

  ## Examples

      iex> AlbumQuery.base()
      #Ecto.Query<from a0 in Portfolio.Photography.Album, as: :album>

  """
  @spec base() :: Ecto.Query.t()
  def base do
    from(a in Album, as: :album)
  end

  @doc """
  Filters albums by type.

  ## Examples

      iex> AlbumQuery.base() |> AlbumQuery.by_type("wedding")
      #Ecto.Query<...>

  """
  @spec by_type(Ecto.Query.t(), String.t() | atom()) :: Ecto.Query.t()
  def by_type(query, type) when is_binary(type) or is_atom(type) do
    where(query, [album: a], a.type == ^type)
  end

  @doc """
  Filters published albums only.

  ## Examples

      iex> AlbumQuery.base() |> AlbumQuery.published()
      #Ecto.Query<...>

  """
  @spec published(Ecto.Query.t()) :: Ecto.Query.t()
  def published(query) do
    where(query, [album: a], a.published == true)
  end

  @doc """
  Filters unpublished albums only.

  ## Examples

      iex> AlbumQuery.base() |> AlbumQuery.unpublished()
      #Ecto.Query<...>

  """
  @spec unpublished(Ecto.Query.t()) :: Ecto.Query.t()
  def unpublished(query) do
    where(query, [album: a], a.published == false)
  end

  @doc """
  Orders albums by date descending (most recent first).

  When dates are equal, orders by inserted_at descending (most recently created first).

  ## Examples

      iex> AlbumQuery.base() |> AlbumQuery.order_by_date_desc()
      #Ecto.Query<...>

  """
  @spec order_by_date_desc(Ecto.Query.t()) :: Ecto.Query.t()
  def order_by_date_desc(query) do
    order_by(query, [album: a], desc: a.date_prise_vue, desc: a.inserted_at)
  end

  @doc """
  Orders albums by date ascending (oldest first).

  ## Examples

      iex> AlbumQuery.base() |> AlbumQuery.order_by_date_asc()
      #Ecto.Query<...>

  """
  @spec order_by_date_asc(Ecto.Query.t()) :: Ecto.Query.t()
  def order_by_date_asc(query) do
    order_by(query, [album: a], asc: a.date_prise_vue)
  end

  @doc """
  Preloads photos ordered by display_order.

  Photos are automatically sorted by their display_order field.

  ## Examples

      iex> AlbumQuery.base() |> AlbumQuery.with_photos()
      #Ecto.Query<...>

  """
  @spec with_photos(Ecto.Query.t()) :: Ecto.Query.t()
  def with_photos(query) do
    photos_query = from(p in Photo, order_by: [asc: p.display_order])
    preload(query, photos: ^photos_query)
  end

  @doc """
  Preloads associations.

  Accepts a single association or a list of associations.
  If `:photos` is requested, automatically uses ordered photos.

  ## Examples

      iex> AlbumQuery.base() |> AlbumQuery.with_preload(:photos)
      #Ecto.Query<...>

      iex> AlbumQuery.base() |> AlbumQuery.with_preload([:photos])
      #Ecto.Query<...>

  """
  @spec with_preload(Ecto.Query.t(), atom() | [atom()]) :: Ecto.Query.t()
  def with_preload(query, preloads) when is_list(preloads) do
    if :photos in preloads do
      preloads_without_photos = Enum.reject(preloads, &(&1 == :photos))

      query
      |> preload(^preloads_without_photos)
      |> with_photos()
    else
      preload(query, ^preloads)
    end
  end

  def with_preload(query, preload) when is_atom(preload) do
    with_preload(query, [preload])
  end

  @doc """
  Groups albums by year of date_prise_vue.

  Returns tuples of {year, album} for grouping.
  Useful for grouping published albums by year.

  ## Examples

      iex> AlbumQuery.base()
      ...> |> AlbumQuery.published()
      ...> |> AlbumQuery.group_by_year()
      #Ecto.Query<...>

  """
  @spec group_by_year(Ecto.Query.t()) :: Ecto.Query.t()
  def group_by_year(query) do
    query
    |> select([album: a], {fragment("EXTRACT(YEAR FROM ?)", a.date_prise_vue), a})
    |> order_by([album: a], desc: fragment("EXTRACT(YEAR FROM ?)", a.date_prise_vue))
  end

  @doc """
  Adds photo count to each album with an optimized subquery.

  Uses LEFT JOIN + GROUP BY to avoid N+1 query problem.
  The count is added as a virtual `photo_count` field on each album.

  ## Examples

      iex> AlbumQuery.base() |> AlbumQuery.with_photo_count()
      #Ecto.Query<...>

  """
  @spec with_photo_count(Ecto.Query.t()) :: Ecto.Query.t()
  def with_photo_count(query) do
    from([album: a] in query,
      left_join: p in assoc(a, :photos),
      group_by: a.id,
      select_merge: %{photo_count: count(p.id)}
    )
  end

  @doc """
  Loads only the first photo (cover photo) instead of all photos.

  Uses a preload with a limited subquery to load only the first photo
  sorted by display_order.

  ## Examples

      iex> AlbumQuery.base() |> AlbumQuery.with_cover_photo_only()
      #Ecto.Query<...>

  """
  @spec with_cover_photo_only(Ecto.Query.t()) :: Ecto.Query.t()
  def with_cover_photo_only(query) do
    cover_photo_query =
      from(p in Photo,
        order_by: [asc: p.display_order],
        limit: 1
      )

    from(a in query,
      preload: [photos: ^cover_photo_query]
    )
  end

  @doc """
  Filters albums by date range.

  Returns albums where date_prise_vue is between start_date and end_date (inclusive).

  ## Parameters

  - `query` - The Ecto query
  - `start_date` - Start date (Date struct)
  - `end_date` - End date (Date struct)

  ## Examples

      iex> start_date = ~D[2024-01-01]
      iex> end_date = ~D[2024-12-31]
      iex> AlbumQuery.base() |> AlbumQuery.where_date_between(start_date, end_date)
      #Ecto.Query<...>

  """
  @spec where_date_between(Ecto.Query.t(), Date.t(), Date.t()) :: Ecto.Query.t()
  def where_date_between(query, %Date{} = start_date, %Date{} = end_date) do
    where(query, [album: a], a.date_prise_vue >= ^start_date and a.date_prise_vue <= ^end_date)
  end
end
