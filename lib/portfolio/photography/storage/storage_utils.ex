defmodule Portfolio.Photography.Storage.StorageUtils do
  @moduledoc """
  Utility functions for storage operations.

  Provides helper functions for file system operations used by storage adapters.
  """

  @doc """
  Calculates the total size of a directory recursively.

  Returns 0 if the directory doesn't exist or can't be read.
  """
  @spec calculate_directory_size(String.t()) :: non_neg_integer()
  def calculate_directory_size(dir_path) do
    case File.ls(dir_path) do
      {:ok, entries} ->
        Enum.reduce(entries, 0, fn entry, acc ->
          acc + calculate_entry_size(dir_path, entry)
        end)

      {:error, _reason} ->
        0
    end
  end

  @doc """
  Gets the file extension for a given MIME type.

  Falls back to "jpg" if the MIME type has no known extensions.

  ## Examples

      iex> alias Portfolio.Photography.Storage.StorageUtils
      iex> StorageUtils.get_extension_for_mime("image/jpeg")
      "jpg"

      iex> alias Portfolio.Photography.Storage.StorageUtils
      iex> StorageUtils.get_extension_for_mime("image/png")
      "png"

      iex> alias Portfolio.Photography.Storage.StorageUtils
      iex> StorageUtils.get_extension_for_mime("image/webp")
      "webp"
  """
  @spec get_extension_for_mime(String.t()) :: String.t()
  def get_extension_for_mime(mime_type) do
    case MIME.extensions(mime_type) do
      [ext | _] -> ext
      [] -> "jpg"
    end
  end

  # Calculate size of a single entry (file or directory)
  @spec calculate_entry_size(String.t(), String.t()) :: non_neg_integer()
  defp calculate_entry_size(dir_path, entry) do
    full_path = Path.join(dir_path, entry)

    cond do
      File.dir?(full_path) -> calculate_directory_size(full_path)
      File.regular?(full_path) -> get_file_size(full_path)
      true -> 0
    end
  end

  # Get file size, returning 0 on error
  @spec get_file_size(String.t()) :: non_neg_integer()
  defp get_file_size(file_path) do
    case File.stat(file_path) do
      {:ok, %{size: size}} -> size
      {:error, _} -> 0
    end
  end
end
