defmodule Portfolio.DomainEvents.Builders do
  @moduledoc """
  Event builders for domain events.

  Centralizes the construction of domain events to ensure consistency
  and reduce duplication across services. Each builder function creates
  a properly structured event with all required fields.

  ## Usage

      alias Portfolio.DomainEvents.Builders

      event = Builders.build_album_deleted(album, photos, user_id)
      DomainEvents.publish(:album_deleted, event)

  """

  alias Portfolio.Auth.Events.{
    MagicLinkRequested,
    MagicLinkVerified,
    SessionCreated,
    UserCreated
  }

  alias Portfolio.Photography.Events.{
    AlbumDeleted,
    AlbumPublished,
    AlbumUnpublished,
    PhotoDeleted,
    PhotoUploaded
  }

  # =============================================================================
  # Photography Event Builders
  # =============================================================================

  @doc """
  Builds an AlbumPublished event.

  ## Parameters

  - `album` - The album that was published
  - `user_id` - ID of the user who published the album (optional)

  ## Examples

      iex> album = %Album{id: "123", title: "Wedding", slug: "wedding-2024"}
      iex> event = Builders.build_album_published(album, "user-456")
      iex> event.album_id
      "123"

  """
  @spec build_album_published(map(), Ecto.UUID.t() | nil) :: AlbumPublished.t()
  def build_album_published(album, user_id \\ nil) do
    %AlbumPublished{
      album_id: album.id,
      title: album.title,
      slug: album.slug,
      published_at: DateTime.utc_now(),
      user_id: user_id
    }
  end

  @doc """
  Builds an AlbumUnpublished event.

  ## Parameters

  - `album` - The album that was unpublished
  - `user_id` - ID of the user who unpublished the album (optional)

  ## Examples

      iex> album = %Album{id: "123", title: "Wedding", slug: "wedding-2024"}
      iex> event = Builders.build_album_unpublished(album, "user-456")
      iex> event.album_id
      "123"

  """
  @spec build_album_unpublished(map(), Ecto.UUID.t() | nil) :: AlbumUnpublished.t()
  def build_album_unpublished(album, user_id \\ nil) do
    %AlbumUnpublished{
      album_id: album.id,
      title: album.title,
      slug: album.slug,
      unpublished_at: DateTime.utc_now(),
      user_id: user_id
    }
  end

  @doc """
  Builds an AlbumDeleted event.

  ## Parameters

  - `album` - The album that was deleted
  - `photo_count` - Number of photos that were deleted with the album
  - `user_id` - ID of the user who deleted the album (optional)

  ## Examples

      iex> album = %Album{id: "123", title: "Wedding", slug: "wedding-2024"}
      iex> event = Builders.build_album_deleted(album, 25, "user-456")
      iex> event.photo_count
      25

  """
  @spec build_album_deleted(map(), non_neg_integer(), Ecto.UUID.t() | nil) :: AlbumDeleted.t()
  def build_album_deleted(album, photo_count, user_id \\ nil) do
    %AlbumDeleted{
      album_id: album.id,
      title: album.title,
      slug: album.slug,
      deleted_at: DateTime.utc_now(),
      user_id: user_id,
      photo_count: photo_count
    }
  end

  @doc """
  Builds a PhotoUploaded event.

  ## Parameters

  - `photo` - The photo that was uploaded

  ## Examples

      iex> photo = %Photo{id: "123", album_id: "456", file_path: "/uploads/photo.jpg", hash: "abc123"}
      iex> event = Builders.build_photo_uploaded(photo)
      iex> event.photo_id
      "123"

  """
  @spec build_photo_uploaded(map()) :: PhotoUploaded.t()
  def build_photo_uploaded(photo) do
    %PhotoUploaded{
      photo_id: photo.id,
      album_id: photo.album_id,
      file_path: photo.file_path,
      hash: photo.hash,
      uploaded_at: DateTime.utc_now()
    }
  end

  @doc """
  Builds a PhotoDeleted event.

  ## Parameters

  - `photo` - The photo that was deleted

  ## Examples

      iex> photo = %Photo{id: "123", album_id: "456", file_path: "/uploads/photo.jpg"}
      iex> event = Builders.build_photo_deleted(photo)
      iex> event.photo_id
      "123"

  """
  @spec build_photo_deleted(map()) :: PhotoDeleted.t()
  def build_photo_deleted(photo) do
    %PhotoDeleted{
      photo_id: photo.id,
      album_id: photo.album_id,
      file_path: photo.file_path,
      deleted_at: DateTime.utc_now()
    }
  end

  # =============================================================================
  # Auth Event Builders
  # =============================================================================

  @doc """
  Builds a UserCreated event.

  ## Parameters

  - `user` - The user that was created

  ## Examples

      iex> user = %User{id: "123", email: "test@example.com", role: :user}
      iex> event = Builders.build_user_created(user)
      iex> event.email
      "test@example.com"

  """
  @spec build_user_created(map()) :: UserCreated.t()
  def build_user_created(user) do
    %UserCreated{
      user_id: user.id,
      email: user.email,
      role: user.role,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Builds a SessionCreated event.

  ## Parameters

  - `session` - The session that was created
  - `user` - The user associated with the session
  - `expires_at` - When the session expires (optional, defaults to session.expires_at)

  ## Examples

      iex> session = %UserSession{id: "123", inserted_at: ~U[2024-01-01 00:00:00Z]}
      iex> user = %User{id: "456", email: "test@example.com"}
      iex> expires_at = ~U[2024-01-31 00:00:00Z]
      iex> event = Builders.build_session_created(session, user, expires_at)
      iex> event.user_id
      "456"

  """
  @spec build_session_created(map(), map(), DateTime.t()) :: SessionCreated.t()
  def build_session_created(session, user, expires_at) do
    %SessionCreated{
      session_id: session.id,
      user_id: user.id,
      email: user.email,
      created_at: session.inserted_at,
      expires_at: expires_at
    }
  end

  @doc """
  Builds a MagicLinkRequested event.

  Note: The plaintext token is intentionally NOT included for security.

  ## Parameters

  - `magic_link` - The magic link that was created
  - `email` - The email address associated with the request

  ## Examples

      iex> magic_link = %MagicLink{id: "123", short_code: "ABC123", expires_at: ~U[2024-01-01 00:00:00Z]}
      iex> event = Builders.build_magic_link_requested(magic_link, "test@example.com")
      iex> event.short_code
      "ABC123"

  """
  @spec build_magic_link_requested(map(), String.t()) :: MagicLinkRequested.t()
  def build_magic_link_requested(magic_link, email) do
    %MagicLinkRequested{
      magic_link_id: magic_link.id,
      email: email,
      short_code: magic_link.short_code,
      requested_at: DateTime.utc_now(),
      expires_at: magic_link.expires_at
    }
  end

  @doc """
  Builds a MagicLinkVerified event.

  ## Parameters

  - `magic_link` - The magic link that was verified
  - `user` - The user who was authenticated

  ## Examples

      iex> magic_link = %MagicLink{id: "123"}
      iex> user = %User{id: "456", email: "test@example.com"}
      iex> event = Builders.build_magic_link_verified(magic_link, user)
      iex> event.user_id
      "456"

  """
  @spec build_magic_link_verified(map(), map()) :: MagicLinkVerified.t()
  def build_magic_link_verified(magic_link, user) do
    %MagicLinkVerified{
      magic_link_id: magic_link.id,
      user_id: user.id,
      email: user.email,
      verified_at: DateTime.utc_now()
    }
  end
end
