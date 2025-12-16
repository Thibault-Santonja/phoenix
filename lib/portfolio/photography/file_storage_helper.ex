defmodule Portfolio.Photography.FileStorageHelper do
  @moduledoc """
  Helper module for file storage operations.

  Centralizes file deletion logic to eliminate duplication between
  album and photo deletion services. Provides consistent error handling
  and "orphan-tolerant" deletion behavior.

  ## Design Principles

  1. **DRY**: Single implementation for file deletion logic
  2. **Orphan Tolerance**: Missing files are not errors (data cleanup scenarios)
  3. **Batch Support**: Efficient handling of multiple file deletions

  ## Usage

      # Delete a single file
      FileStorageHelper.delete_file("/photos/123.jpg")
      # => {:ok, :deleted} | {:ok, :not_found} | {:error, reason}

      # Delete multiple files (all must succeed)
      FileStorageHelper.delete_files(["/photos/1.jpg", "/photos/2.jpg"])
      # => {:ok, :ok} | {:error, reason}
  """

  alias Portfolio.Photography.Storage

  @type delete_result :: {:ok, :ok} | {:error, term()}

  @doc """
  Deletes a single file from storage.

  Returns `{:ok, :deleted}` on successful deletion, `{:ok, :not_found}` if
  the file was already missing (orphan-tolerant), or `{:error, reason}` on failure.

  ## Parameters

  - `file_path` - Path to the file to delete

  ## Examples

      iex> delete_file("/photos/existing.jpg")
      {:ok, :deleted}

      iex> delete_file("/photos/missing.jpg")
      {:ok, :not_found}

      iex> delete_file("/photos/no_access.jpg")
      {:error, :eacces}
  """
  @spec delete_file(String.t()) :: delete_result()
  def delete_file(file_path) when is_binary(file_path) do
    case Storage.backend().delete_photo(file_path) do
      :ok -> {:ok, :ok}
      {:error, :not_found} -> {:ok, :ok}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes multiple files from storage.

  Attempts to delete all files. Considers the operation successful if all files
  are either deleted or were already missing (orphan-tolerant).

  Returns `{:ok, :ok}` if all deletions succeeded, or `{:error, reason}` with
  the first encountered error.

  ## Parameters

  - `file_paths` - List of file paths to delete

  ## Examples

      iex> delete_files(["/photos/1.jpg", "/photos/2.jpg"])
      {:ok, :ok}

      iex> delete_files(["/photos/1.jpg", "/photos/no_access.jpg"])
      {:error, :eacces}
  """
  @spec delete_files([String.t()]) :: {:ok, :ok} | {:error, term()}
  def delete_files([]), do: {:ok, :ok}

  def delete_files(file_paths) when is_list(file_paths) do
    results = Enum.map(file_paths, &delete_file/1)

    if Enum.all?(results, &deletion_successful?/1) do
      {:ok, :ok}
    else
      # Find and return the first real error
      case Enum.find(results, &deletion_failed?/1) do
        {:error, reason} -> {:error, reason}
        # Should not happen, but fallback
        _ -> {:error, :unknown}
      end
    end
  end

  @doc """
  Deletes files associated with a list of photo structs.

  Extracts file paths from photo structs and deletes them all.
  This is a convenience function for batch deletion in album operations.

  ## Parameters

  - `photos` - List of photo structs with `file_path` field

  ## Examples

      iex> delete_photo_files([%Photo{file_path: "/photos/1.jpg"}])
      {:ok, :ok}
  """
  @spec delete_photo_files([map()]) :: {:ok, :ok} | {:error, term()}
  def delete_photo_files(photos) when is_list(photos) do
    file_paths = Enum.map(photos, & &1.file_path)
    delete_files(file_paths)
  end

  # A deletion is successful if the file was deleted or was already missing
  @spec deletion_successful?(delete_result()) :: boolean()
  defp deletion_successful?({:ok, _}), do: true
  defp deletion_successful?(_), do: false

  # A deletion failed if it returned an error
  @spec deletion_failed?(delete_result()) :: boolean()
  defp deletion_failed?({:error, _}), do: true
  defp deletion_failed?(_), do: false
end
