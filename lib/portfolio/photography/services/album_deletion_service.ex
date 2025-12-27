defmodule Portfolio.Photography.Services.AlbumDeletionService do
  @moduledoc """
  Service for deleting albums with atomic multi-step operations.

  Responsibilities:
  - Fetch all album photos
  - Delete all photo files from storage
  - Delete album record (CASCADE deletes photo records)
  - Rollback on any failure
  - Record telemetry

  This service uses Ecto.Multi to ensure atomicity - if any step fails,
  the entire operation is rolled back.
  """

  use Portfolio.Service

  alias Portfolio.DomainEvents
  alias Portfolio.DomainEvents.Builders
  alias Portfolio.Photography.Album
  alias Portfolio.Photography.FileStorageHelper
  alias Portfolio.Photography.Repositories.PhotoRepository
  alias Portfolio.Repo

  @impl true
  @doc """
  Deletes an album and all its photos atomically.

  Uses Ecto.Multi to guarantee atomicity:
  1. Fetch all album photos
  2. Delete all photo files from storage
  3. Delete the album (photos CASCADE deleted automatically)

  If any step fails, the entire transaction is rolled back.

  ## Parameters

  - `album` - The album to delete
  - `opts` - Options (currently unused, for future extensibility)

  ## Returns

  - `{:ok, %{album: album, photos: photos, files: :ok}}` - Successfully deleted
  - `{:error, step, reason, changes}` - Operation failed at `step`

  ## Examples

      iex> execute(%Album{id: "123"})
      {:ok, %{album: %Album{}, photos: [%Photo{}], files: :ok}}

      iex> execute(%Album{})
      {:error, :files, :eacces, %{photos: [...]}}
  """
  @spec execute(Album.t(), keyword()) ::
          {:ok, map()} | {:error, Ecto.Multi.name(), term(), map()}
  def execute(%Album{} = album, _opts \\ []) do
    with_telemetry(
      [:portfolio, :services, :album_deletion, :executed],
      %{album_id: album.id},
      fn ->
        result =
          Ecto.Multi.new()
          |> Ecto.Multi.run(:photos, fn _repo, _changes ->
            # Fetch all album photos
            photos = PhotoRepository.list_by_album(album.id)
            {:ok, photos}
          end)
          |> Ecto.Multi.run(:files, fn _repo, %{photos: photos} ->
            # Delete all physical files
            FileStorageHelper.delete_photo_files(photos)
          end)
          |> Ecto.Multi.delete(:album, album)
          |> Repo.transaction()

        # Emit additional measurement for photo count
        count = photo_count(result)

        :telemetry.execute(
          [:portfolio, :services, :album_deletion, :photo_count],
          %{photo_count: count},
          %{album_id: album.id}
        )

        # Emit domain event on success
        case result do
          {:ok, %{album: deleted_album, photos: photos}} ->
            event = Builders.build_album_deleted(deleted_album, length(photos))
            DomainEvents.publish(:album_deleted, event)

          _ ->
            :ok
        end

        result
      end
    )
  end

  defp photo_count({:ok, %{photos: photos}}), do: length(photos)
  defp photo_count(_), do: 0
end
