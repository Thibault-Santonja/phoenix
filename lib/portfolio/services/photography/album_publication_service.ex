defmodule Portfolio.Services.Photography.AlbumPublicationService do
  @moduledoc """
  Service for publishing albums with full orchestration.

  Responsibilities:
  - Update album published status
  - Invalidate cache
  - Emit domain events
  - Record telemetry

  This service encapsulates the complex workflow of publishing an album,
  which involves database updates, cache invalidation, event emission,
  and telemetry tracking.
  """

  use Portfolio.Services.Service

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.Album
  alias Portfolio.Photography.Events.AlbumPublished
  alias Portfolio.Photography.Repositories.AlbumRepository

  @impl true
  @doc """
  Publishes an album by making it visible to the public.

  ## Parameters

  - `album` - The album to publish
  - `opts` - Options
    - `:user_id` - ID of the user publishing the album (optional)

  ## Returns

  - `{:ok, album}` - Successfully published album
  - `{:error, changeset}` - Validation or database error

  ## Examples

      iex> execute(%Album{}, user_id: "user-123")
      {:ok, %Album{published: true}}

      iex> execute(%Album{}, [])
      {:ok, %Album{published: true}}
  """
  @spec execute(Album.t(), keyword()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def execute(%Album{} = album, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    with_telemetry(
      [:portfolio, :services, :album_publication, :executed],
      %{album_id: album.id, user_id: user_id},
      fn ->
        with {:ok, album} <- AlbumRepository.update(album, %{published: true}) do
          # Invalidate cache
          invalidate_albums_cache()

          # Emit domain event
          DomainEvents.publish(:album_published, %AlbumPublished{
            album_id: album.id,
            title: album.title,
            slug: album.slug,
            published_at: DateTime.utc_now(),
            user_id: user_id
          })

          {:ok, album}
        end
      end
    )
  end

  # Invalidate all caches related to published albums
  defp invalidate_albums_cache do
    Cachex.del(:portfolio_cache, {:published_albums_by_year, []})
    Cachex.del(:portfolio_cache, {:published_albums_by_year, [:photos]})
    :ok
  end
end
