defmodule PortfolioTest.Fixtures.AuthFixtures do
  @moduledoc """
  Test fixtures for the Auth context.

  These helpers use the application's public API to ensure generated
  data respects business rules and constraints. This approach provides
  better confidence than bypassing the application logic.

  See docs/guides/generating-data-functions.md for more information.
  """

  alias Portfolio.Auth
  alias Portfolio.Repo

  @doc """
  Creates a user through the registration API.

  This ensures the user is created with proper validations and business rules.

  ## Options

    * `:email` - User email (generates unique email if not provided)
    * `:name` - User name (optional)
    * `:role` - User role (defaults to "admin")

  ## Examples

      iex> user = create_user()
      iex> user.email
      "user-123@example.com"

      iex> user = create_user(email: "test@example.com", name: "Test User")
      iex> user.name
      "Test User"
  """
  def create_user(attrs \\ []) do
    email =
      Keyword.get_lazy(attrs, :email, fn ->
        "user#{System.unique_integer([:positive])}@example.com"
      end)

    name = Keyword.get(attrs, :name)
    role = Keyword.get(attrs, :role, "admin")

    params =
      %{email: email, role: role}
      |> maybe_add(:name, name)

    # Use registration changeset to respect business rules
    user =
      %Auth.User{}
      |> Auth.User.registration_changeset(params)
      |> Repo.insert!()

    user
  end

  @doc """
  Creates a magic link for authentication.

  Generates a valid, unexpired magic link token for the given user.

  ## Options

    * `:user` - User to create magic link for (creates new user if not provided)
    * `:expires_at` - Expiration datetime (defaults to 15 minutes from now)
    * `:used_at` - Mark as already used (defaults to nil)

  ## Examples

      iex> user = create_user()
      iex> magic_link = create_magic_link(user: user)
      iex> magic_link.used_at
      nil

      iex> expired_link = create_magic_link(
      ...>   expires_at: DateTime.add(DateTime.utc_now(), -1, :hour)
      ...> )
  """
  def create_magic_link(attrs \\ []) do
    user = Keyword.get_lazy(attrs, :user, &create_user/0)

    expires_at =
      Keyword.get_lazy(attrs, :expires_at, fn ->
        DateTime.add(DateTime.utc_now(), 15, :minute)
        |> DateTime.truncate(:second)
      end)

    used_at = Keyword.get(attrs, :used_at)

    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    magic_link =
      %Auth.MagicLink{}
      |> Auth.MagicLink.changeset(%{
        user_id: user.id,
        token: token,
        expires_at: expires_at,
        used_at: used_at
      })
      |> Repo.insert!()

    # Preload user if requested
    if Keyword.get(attrs, :preload_user, false) do
      Repo.preload(magic_link, :user)
    else
      magic_link
    end
  end

  @doc """
  Creates an authenticated session for a user.

  This uses the Auth context's create_session function to ensure
  the session is created with proper token generation and validation.

  ## Options

    * `:user` - User to create session for (creates new user if not provided)

  ## Examples

      iex> user = create_user()
      iex> session = create_session(user: user)
      iex> session.user_id == user.id
      true

      iex> session = create_session()  # Creates user automatically
  """
  def create_session(attrs \\ []) do
    user = Keyword.get_lazy(attrs, :user, &create_user/0)

    {:ok, session} = Auth.create_session(user)
    session
  end

  @doc """
  Creates a user and immediately logs them in, returning the session.

  This is a convenience helper for tests that need an authenticated user.

  ## Options

  Same as `create_user/1`, plus:
    * `:preload_user` - Whether to preload the user on the session (default: false)

  ## Examples

      iex> session = create_authenticated_user()
      iex> session.token
      "abc123..."
  """
  def create_authenticated_user(attrs \\ []) do
    preload_user = Keyword.get(attrs, :preload_user, false)
    user = create_user(attrs)
    session = create_session(user: user)

    if preload_user do
      Repo.preload(session, :user)
    else
      session
    end
  end

  @doc """
  Requests a magic link through the public API.

  This ensures the entire magic link request flow is tested,
  including email validation and magic link generation.

  ## Options

    * `:email` - Email to request magic link for
    * `:create_user` - Whether to create user first (default: true)

  ## Examples

      iex> {:ok, magic_link} = request_magic_link(email: "test@example.com")
      iex> magic_link.token
      "abc123..."
  """
  def request_magic_link(attrs \\ []) do
    email =
      Keyword.get_lazy(attrs, :email, fn ->
        "user#{System.unique_integer([:positive])}@example.com"
      end)

    # Optionally create user first
    if Keyword.get(attrs, :create_user, true) do
      create_user(email: email)
    end

    Auth.request_magic_link(email)
  end

  @doc """
  Authenticates a user through the complete magic link flow.

  This creates a user, requests a magic link, and verifies it,
  simulating the complete authentication journey.

  ## Options

  Same as `create_user/1`

  ## Examples

      iex> {:ok, user} = authenticate_with_magic_link()
      iex> user.email
      "user-123@example.com"
  """
  def authenticate_with_magic_link(attrs \\ []) do
    email =
      Keyword.get_lazy(attrs, :email, fn ->
        "user#{System.unique_integer([:positive])}@example.com"
      end)

    # Create user
    _user = create_user(Keyword.put(attrs, :email, email))

    # Request and verify magic link
    {:ok, magic_link} = Auth.request_magic_link(email)
    Auth.verify_magic_link(magic_link.token)
  end

  # Private helpers

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
