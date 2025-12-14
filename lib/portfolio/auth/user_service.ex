defmodule Portfolio.Auth.UserService do
  @moduledoc """
  Service for managing the user lifecycle.

  Responsibilities:
  - Retrieving users (by email, by ID)
  - Creating users (dev/test only)
  - Updating user profiles
  - Deleting users (with business rule PU-006)
  - User statistics

  This service encapsulates all business logic related to users,
  separated from other concerns of the Auth context (magic links, sessions).

  Delegates persistence to UserRepository to respect the Repository pattern.
  """

  alias Portfolio.Auth.Repositories.UserRepository
  alias Portfolio.Auth.SessionService
  alias Portfolio.Auth.User

  # =============================================================================
  # Query Functions
  # =============================================================================

  @doc """
  Retrieves a user by their email.

  ## Examples

      iex> get_user_by_email("admin@example.com")
      {:ok, %User{}}

      iex> get_user_by_email("unknown@example.com")
      {:error, :not_found}
  """
  @spec get_user_by_email(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def get_user_by_email(email) when is_binary(email) do
    UserRepository.get_by_email(email)
  end

  @doc """
  Retrieves or creates a user by email.

  In development, the user is created automatically if they don't exist.
  In production, only existing users can log in.

  ## Examples

      iex> get_or_create_user("admin@example.com")
      {:ok, %User{}}

      iex> get_or_create_user("unknown@example.com")  # In production
      {:error, :user_not_found}
  """
  @spec get_or_create_user(String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | :user_not_found}
  def get_or_create_user(email) when is_binary(email) do
    case get_user_by_email(email) do
      {:ok, user} ->
        {:ok, user}

      {:error, :not_found} ->
        create_user_if_allowed(email)
    end
  end

  @doc """
  Retrieves a user by their ID.

  ## Examples

      iex> get_user("123e4567-e89b-12d3-a456-426614174000")
      {:ok, %User{}}

      iex> get_user("invalid-uuid")
      {:error, :not_found}
  """
  @spec get_user(Ecto.UUID.t()) :: {:ok, User.t()} | {:error, :not_found}
  def get_user(id), do: UserRepository.get(id)

  @doc """
  Lists all users in the system with optional filters.

  ## Options

  - `:role` - Filter by role (`:admin` or `:user`)

  ## Examples

      iex> list_users()
      [%User{}, %User{}]

      iex> list_users(role: :admin)
      [%User{role: :admin}]
  """
  @spec list_users(keyword()) :: [User.t()]
  def list_users(opts \\ []) do
    UserRepository.list(opts)
  end

  # =============================================================================
  # Mutation Functions
  # =============================================================================

  @doc """
  Returns a changeset for modifying a user profile.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{}

      iex> change_user(user, %{name: "New Name"})
      %Ecto.Changeset{}
  """
  @spec change_user(User.t(), map()) :: Ecto.Changeset.t()
  def change_user(user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates a user's profile.

  Only the name field can be modified.

  ## Examples

      iex> update_user(user, %{name: "New Name"})
      {:ok, %User{}}

      iex> update_user(user, %{name: ""})
      {:error, %Ecto.Changeset{}}
  """
  @spec update_user(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user(user, attrs) do
    UserRepository.update_profile(user, attrs)
  end

  @doc """
  Updates a user via the admin interface.

  Allows modifying the user's role and name.

  Protection: An admin cannot modify their own role.
  Pass the current admin's ID via :current_user_id in opts.

  ## Examples

      iex> update_user_as_admin(user, %{role: :user}, current_user_id: admin.id)
      {:ok, %User{}}

      iex> update_user_as_admin(user, %{role: :admin}, current_user_id: user.id)
      {:error, %Ecto.Changeset{errors: [role: {"you cannot modify your own role", []}]}}

      iex> update_user_as_admin(user, %{role: :invalid})
      {:error, %Ecto.Changeset{}}
  """
  @spec update_user_as_admin(User.t(), map(), keyword()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_as_admin(user, attrs, opts \\ []) do
    old_role = user.role

    case UserRepository.update_as_admin(user, attrs, opts) do
      {:ok, updated_user} ->
        # If role changed, invalidate all session caches to force fresh data reload
        # This ensures role changes take effect immediately across all devices
        # without logging the user out completely
        if updated_user.role != old_role do
          invalidate_user_session_caches(updated_user)
        end

        {:ok, updated_user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Invalidates all session caches for a user without deleting the sessions
  # This forces the next request to reload fresh user data from the database
  # Note: session.token is already hashed (stored hashed in DB), matching the cache key format
  @spec invalidate_user_session_caches(User.t()) :: :ok
  defp invalidate_user_session_caches(user) do
    sessions = SessionService.list_user_sessions(user.id)

    Enum.each(sessions, fn session ->
      # Cache key uses the hashed token (session.token is already hashed in DB)
      cache_key = {:session, session.token}
      _ = Cachex.del(:portfolio_cache, cache_key)
    end)

    :ok
  end

  @doc """
  Deletes a user and all their associated data.

  Also deletes all sessions and magic links for the user
  via foreign key cascade constraints.

  **Business rule PU-006**: Prevents deletion of the last administrator
  to avoid completely locking access to the system.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(last_admin)
      {:error, :last_admin}

      iex> delete_user(invalid_user)
      {:error, %Ecto.Changeset{}}
  """
  @spec delete_user(User.t()) ::
          {:ok, User.t()} | {:error, :last_admin} | {:error, Ecto.Changeset.t()}
  def delete_user(%User{role: :admin} = user) do
    # PU-006: Verify that at least one other admin remains
    if count_admin_users() <= 1 do
      {:error, :last_admin}
    else
      UserRepository.delete(user)
    end
  end

  def delete_user(user) do
    UserRepository.delete(user)
  end

  # =============================================================================
  # Statistics Functions
  # =============================================================================

  @doc """
  Counts the total number of users in the system.

  ## Examples

      iex> count_users()
      5
  """
  @spec count_users() :: non_neg_integer()
  def count_users do
    UserRepository.count()
  end

  @doc """
  Counts the number of administrators.

  ## Examples

      iex> count_admin_users()
      2
  """
  @spec count_admin_users() :: non_neg_integer()
  def count_admin_users do
    UserRepository.count_admins()
  end

  @doc """
  Counts the number of regular users.

  ## Examples

      iex> count_regular_users()
      3
  """
  @spec count_regular_users() :: non_neg_integer()
  def count_regular_users do
    UserRepository.count_regular_users()
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  # Creates a user only if the environment allows it
  @spec create_user_if_allowed(String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | :user_not_found}
  if Mix.env() in [:dev, :test] do
    defp create_user_if_allowed(email) do
      # In development and test, automatically create the user
      UserRepository.insert(%{email: email})
    end
  else
    defp create_user_if_allowed(_email) do
      # In production, refuse the connection
      {:error, :user_not_found}
    end
  end
end
