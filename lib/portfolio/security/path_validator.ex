defmodule Portfolio.Security.PathValidator do
  @moduledoc """
  Validates file paths to prevent directory traversal attacks.

  This module provides centralized path validation for all file operations
  in the application, ensuring paths stay within allowed boundaries.

  ## Security

  Directory traversal (path traversal) is a vulnerability where an attacker
  can access files outside the intended directory by using sequences like
  `../` or absolute paths. This module prevents such attacks by:

  1. Expanding paths to absolute form
  2. Checking paths start with allowed base directories
  3. Rejecting paths containing traversal patterns

  ## Usage

      iex> PathValidator.validate("/uploads/photos/abc123", "/uploads")
      :ok

      iex> PathValidator.validate("/uploads/../etc/passwd", "/uploads")
      {:error, :path_traversal_detected}

      iex> PathValidator.safe_join("/uploads", "photos", "../../../etc/passwd")
      {:error, :path_traversal_detected}
  """

  require Logger

  @type validation_error :: :path_traversal_detected | :invalid_path | :outside_allowed_directory

  @doc """
  Validates that a path is safe and within an allowed base directory.

  ## Parameters

    * `path` - The path to validate
    * `allowed_base` - The base directory that the path must be within

  ## Returns

    * `:ok` - Path is valid and within the allowed directory
    * `{:error, :path_traversal_detected}` - Path contains traversal patterns
    * `{:error, :outside_allowed_directory}` - Path is outside allowed base

  ## Examples

      iex> PathValidator.validate("/app/uploads/photos/abc", "/app/uploads")
      :ok

      iex> PathValidator.validate("/app/uploads/../secrets", "/app/uploads")
      {:error, :path_traversal_detected}

      iex> PathValidator.validate("/etc/passwd", "/app/uploads")
      {:error, :outside_allowed_directory}
  """
  @spec validate(String.t(), String.t()) :: :ok | {:error, validation_error()}
  def validate(path, allowed_base) when is_binary(path) and is_binary(allowed_base) do
    cond do
      contains_traversal_pattern?(path) ->
        log_traversal_attempt(path, allowed_base, :pattern_detected)
        {:error, :path_traversal_detected}

      not within_allowed_directory?(path, allowed_base) ->
        log_traversal_attempt(path, allowed_base, :outside_directory)
        {:error, :outside_allowed_directory}

      true ->
        :ok
    end
  end

  def validate(path, _allowed_base) when is_nil(path) do
    {:error, :invalid_path}
  end

  @doc """
  Validates that a path is safe and returns the expanded absolute path.

  Same as `validate/2` but returns the normalized path on success.

  ## Examples

      iex> PathValidator.validate_and_expand("./photos/abc", "/app/uploads")
      {:ok, "/app/uploads/photos/abc"}

      iex> PathValidator.validate_and_expand("../etc/passwd", "/app/uploads")
      {:error, :path_traversal_detected}
  """
  @spec validate_and_expand(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, validation_error()}
  def validate_and_expand(path, allowed_base) do
    case validate(path, allowed_base) do
      :ok -> {:ok, Path.expand(path)}
      error -> error
    end
  end

  @doc """
  Safely joins path segments and validates the result.

  Use this instead of `Path.join/2` when joining user-provided path segments.

  ## Parameters

    * `base` - The base directory (trusted)
    * `segments` - One or more path segments to join (potentially untrusted)

  ## Returns

    * `{:ok, path}` - The safely joined and validated path
    * `{:error, reason}` - Validation failed

  ## Examples

      iex> PathValidator.safe_join("/uploads", "photos", "abc123")
      {:ok, "/uploads/photos/abc123"}

      iex> PathValidator.safe_join("/uploads", "photos", "../../../etc/passwd")
      {:error, :path_traversal_detected}

      iex> PathValidator.safe_join("/uploads", ["photos", "abc123", "image.jpg"])
      {:ok, "/uploads/photos/abc123/image.jpg"}
  """
  @spec safe_join(String.t(), String.t() | [String.t()]) ::
          {:ok, String.t()} | {:error, validation_error()}
  def safe_join(base, segments) when is_list(segments) do
    # Check each segment individually for traversal patterns
    if Enum.any?(segments, &contains_traversal_pattern?/1) do
      log_traversal_attempt(inspect(segments), base, :segment_pattern)
      {:error, :path_traversal_detected}
    else
      joined = Path.join([base | segments])
      validate_and_expand(joined, base)
    end
  end

  def safe_join(base, segment) when is_binary(segment) do
    safe_join(base, [segment])
  end

  @spec safe_join(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, validation_error()}
  def safe_join(base, segment1, segment2) do
    safe_join(base, [segment1, segment2])
  end

  @doc """
  Validates a photo_id format for use in file paths.

  Photo IDs should be 8-character hex strings (SHA256 prefix) or valid UUIDs.
  This prevents injection of traversal patterns via photo_id parameters.

  ## Examples

      iex> PathValidator.validate_photo_id("a3f2b8c4")
      :ok

      iex> PathValidator.validate_photo_id("550e8400-e29b-41d4-a716-446655440000")
      :ok

      iex> PathValidator.validate_photo_id("../etc")
      {:error, :invalid_photo_id}
  """
  @spec validate_photo_id(String.t()) :: :ok | {:error, :invalid_photo_id}
  def validate_photo_id(photo_id) when is_binary(photo_id) do
    cond do
      # 8-character hex string (SHA256 prefix)
      Regex.match?(~r/^[a-f0-9]{8}$/i, photo_id) ->
        :ok

      # UUID format
      Regex.match?(
        ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
        photo_id
      ) ->
        :ok

      true ->
        Logger.warning("Invalid photo_id format", photo_id: photo_id)
        {:error, :invalid_photo_id}
    end
  end

  def validate_photo_id(_), do: {:error, :invalid_photo_id}

  @doc """
  Validates a filename for safe storage.

  Rejects filenames containing path separators or traversal patterns.

  ## Examples

      iex> PathValidator.validate_filename("image.jpg")
      :ok

      iex> PathValidator.validate_filename("../malicious.jpg")
      {:error, :invalid_filename}

      iex> PathValidator.validate_filename("path/to/file.jpg")
      {:error, :invalid_filename}
  """
  @spec validate_filename(String.t()) :: :ok | {:error, :invalid_filename}
  def validate_filename(filename) when is_binary(filename) do
    cond do
      String.contains?(filename, ["../", "..\\", "/", "\\"]) ->
        Logger.warning("Invalid filename with path separator", filename: filename)
        {:error, :invalid_filename}

      String.starts_with?(filename, ".") and filename != "." ->
        # Allow dotfiles but log them
        Logger.debug("Dotfile filename", filename: filename)
        :ok

      String.length(filename) > 255 ->
        Logger.warning("Filename too long", filename: filename, length: String.length(filename))
        {:error, :invalid_filename}

      true ->
        :ok
    end
  end

  def validate_filename(_), do: {:error, :invalid_filename}

  # Private functions

  @spec contains_traversal_pattern?(String.t()) :: boolean()
  defp contains_traversal_pattern?(path) do
    # Check for common traversal patterns
    # Check for null bytes (can bypass some filters)
    # Check for URL-encoded traversal
    String.contains?(path, ["../", "..\\", ".."]) or
      String.contains?(path, <<0>>) or
      String.contains?(path, ["%2e%2e", "%2E%2E", "%252e"])
  end

  @spec within_allowed_directory?(String.t(), String.t()) :: boolean()
  defp within_allowed_directory?(path, allowed_base) do
    # Expand both paths to absolute form for accurate comparison
    absolute_path = Path.expand(path)
    absolute_base = Path.expand(allowed_base)

    # Ensure base ends with separator for accurate prefix matching
    normalized_base =
      if String.ends_with?(absolute_base, "/") do
        absolute_base
      else
        absolute_base <> "/"
      end

    # Path must start with base or be exactly the base
    absolute_path == absolute_base or String.starts_with?(absolute_path, normalized_base)
  end

  defp log_traversal_attempt(path, allowed_base, reason) do
    Logger.warning("Path traversal attempt detected",
      attempted_path: path,
      allowed_base: allowed_base,
      reason: reason,
      caller: get_caller_info()
    )
  end

  defp get_caller_info do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, stacktrace} ->
        stacktrace
        |> Enum.drop(4)
        |> Enum.take(1)
        |> Enum.map(fn {mod, fun, arity, _} -> "#{mod}.#{fun}/#{arity}" end)
        |> List.first()

      _ ->
        "unknown"
    end
  end
end
