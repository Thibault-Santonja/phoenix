defmodule Portfolio.Photography.Services.AlbumPublicationService do
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

  use Portfolio.Service

  alias Portfolio.CacheManager
  alias Portfolio.DomainEvents
  alias Portfolio.DomainEvents.Builders
  alias Portfolio.Photography.Album
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
  @spec execute(Album.t(), keyword()) ::
          {:ok, Album.t()} | {:error, Ecto.Changeset.t() | atom()}
  def execute(%Album{} = album, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)

    start_time = System.monotonic_time()

    result =
      with {:ok, album} <- update_album_atomically(album),
           :ok <- invalidate_albums_cache(),
           :ok <- emit_publication_event(album, user_id) do
        {:ok, album}
      else
        {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
          {:error, changeset}

        {:error, reason} ->
          {:error, reason}
      end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:portfolio, :services, :album_publication, :executed],
      %{duration: duration},
      %{result: elem(result, 0), album_id: album.id, user_id: user_id}
    )

    result
  end

  # Atomically update album published status in database
  defp update_album_atomically(album) do
    AlbumRepository.update(album, %{published: true})
  end

  # Emit domain event for album publication
  defp emit_publication_event(album, user_id) do
    event = Builders.build_album_published(album, user_id)
    DomainEvents.publish(:album_published, event)
    :ok
  end

  # Invalidate all caches related to published albums
  defp invalidate_albums_cache do
    CacheManager.invalidate_albums()
  end
end
