defmodule Portfolio.Services.Photography.PhotoDeletionService do
  @moduledoc """
  Service for deleting photos with atomic multi-step operations.

  Responsibilities:
  - Delete photo record from database
  - Delete photo file from storage
  - Rollback on any failure
  - Emit domain events
  - Record telemetry

  This service uses Ecto.Multi to ensure atomicity - if any step fails,
  the entire operation is rolled back.
  """

  use Portfolio.Services.Service

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.Events.PhotoDeleted
  alias Portfolio.Photography.Photo
  alias Portfolio.Photography.Storage
  alias Portfolio.Repo

  @impl true
  @doc """
  Deletes a photo and its file atomically.

  Uses Ecto.Multi to guarantee atomicity:
  1. Delete the photo record from database
  2. Delete the physical file from storage

  If any step fails, the entire transaction is rolled back.

  ## Parameters

  - `photo` - The photo to delete
  - `opts` - Options (currently unused, for future extensibility)

  ## Returns

  - `{:ok, %{photo: photo, file: :ok}}` - Successfully deleted
  - `{:error, step, reason, changes}` - Operation failed at `step`

  ## Examples

      iex> execute(%Photo{id: "123"})
      {:ok, %{photo: %Photo{}, file: :ok}}

      iex> execute(%Photo{file_path: "/invalid"})
      {:error, :file, :eacces, %{photo: %Photo{}}}
  """
  @spec execute(Photo.t(), keyword()) ::
          {:ok, map()} | {:error, Ecto.Multi.name(), term(), map()}
  def execute(%Photo{} = photo, _opts \\ []) do
    with_telemetry(
      [:portfolio, :services, :photo_deletion, :executed],
      %{photo_id: photo.id, album_id: photo.album_id},
      fn ->
        result =
          Ecto.Multi.new()
          |> Ecto.Multi.delete(:photo, photo)
          |> Ecto.Multi.run(:file, fn _repo, %{photo: deleted_photo} ->
            delete_photo_file(deleted_photo.file_path)
          end)
          |> Repo.transaction()

        # Emit domain event on success
        case result do
          {:ok, %{photo: deleted_photo}} ->
            DomainEvents.publish(:photo_deleted, %PhotoDeleted{
              photo_id: deleted_photo.id,
              album_id: deleted_photo.album_id,
              file_path: deleted_photo.file_path,
              deleted_at: DateTime.utc_now()
            })

          _ ->
            :ok
        end

        result
      end
    )
  end

  # Delete photo file, accepting :not_found as success (orphan data is acceptable)
  defp delete_photo_file(file_path) do
    case Storage.backend().delete_photo(file_path) do
      :ok ->
        {:ok, :ok}

      {:error, :not_found} ->
        # If the file doesn't exist, it's acceptable (orphaned data)
        {:ok, :ok}

      {:error, reason} ->
        # Other error - rollback the transaction
        {:error, reason}
    end
  end
end
