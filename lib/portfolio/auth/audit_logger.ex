defmodule Portfolio.Auth.AuditLogger do
  @moduledoc """
  Service for recording audit logs of sensitive actions.

  This module provides a simple interface for creating audit logs
  during administrative actions or security modifications.

  ## Usage

      # In a service or controller
      AuditLogger.log_user_role_changed(
        user,
        old_role: :user,
        new_role: :admin,
        performed_by: current_user,
        ip_address: "192.168.1.1"
      )

      # Or generically
      AuditLogger.log(
        action: :custom_action,
        resource_type: "CustomResource",
        resource_id: resource.id,
        changes: %{"field" => %{"from" => "old", "to" => "new"}},
        performed_by_id: current_user.id
      )

  ## Predefined Actions

  - `log_user_role_changed/3` - User role change
  - `log_user_deleted/3` - User deletion
  - `log_sessions_revoked/3` - Session revocation
  - `log_magic_link_sent/3` - Magic link sent by admin

  ## Best Practices

  - Always include `performed_by_id` when available
  - Include `ip_address` and `user_agent` for sensitive actions
  - Use `metadata` for additional context
  - Audit logs are insert-only (never updated or deleted)
  """

  require Logger

  import Ecto.Query

  alias Portfolio.Auth.AuditLog
  alias Portfolio.Auth.User
  alias Portfolio.Repo

  @type audit_opts :: [
          performed_by_id: Ecto.UUID.t() | nil,
          performed_by: User.t() | nil,
          ip_address: String.t() | nil,
          user_agent: String.t() | nil,
          metadata: map()
        ]

  @doc """
  Records a generic audit log.

  ## Options

  - `:action` (required) - Action performed (atom or string)
  - `:resource_type` (required) - Resource type (string)
  - `:resource_id` - Resource ID (UUID)
  - `:changes` - Map of changes
  - `:metadata` - Additional metadata
  - `:performed_by_id` - User ID
  - `:performed_by` - User struct (alternative to performed_by_id)
  - `:ip_address` - IP address
  - `:user_agent` - User agent

  ## Examples

      iex> log(
      ...>   action: :custom_action,
      ...>   resource_type: "User",
      ...>   resource_id: user.id,
      ...>   performed_by: current_user
      ...> )
      {:ok, %AuditLog{}}
  """
  @spec log(Keyword.t()) :: {:ok, AuditLog.t()} | {:error, Ecto.Changeset.t()}
  def log(opts) do
    action = Keyword.fetch!(opts, :action) |> to_string()
    resource_type = Keyword.fetch!(opts, :resource_type)

    attrs = %{
      action: action,
      resource_type: resource_type,
      resource_id: Keyword.get(opts, :resource_id),
      changes: Keyword.get(opts, :changes, %{}),
      metadata: Keyword.get(opts, :metadata, %{}),
      performed_by_id: extract_performed_by_id(opts),
      ip_address: Keyword.get(opts, :ip_address),
      user_agent: Keyword.get(opts, :user_agent)
    }

    result =
      %AuditLog{}
      |> AuditLog.changeset(attrs)
      |> Repo.insert()

    log_result(result)
    result
  end

  @doc """
  Records a user role change.

  ## Examples

      iex> log_user_role_changed(user,
      ...>   old_role: :user,
      ...>   new_role: :admin,
      ...>   performed_by: admin_user,
      ...>   ip_address: "192.168.1.1"
      ...> )
      {:ok, %AuditLog{}}
  """
  @spec log_user_role_changed(User.t(), Keyword.t()) ::
          {:ok, AuditLog.t()} | {:error, Ecto.Changeset.t()}
  def log_user_role_changed(user, opts \\ []) do
    old_role = Keyword.fetch!(opts, :old_role) |> to_string()
    new_role = Keyword.fetch!(opts, :new_role) |> to_string()

    log(
      action: :user_role_changed,
      resource_type: "User",
      resource_id: user.id,
      changes: %{
        "role" => %{"from" => old_role, "to" => new_role}
      },
      metadata: Keyword.get(opts, :metadata, %{}),
      performed_by_id: extract_performed_by_id(opts),
      performed_by: Keyword.get(opts, :performed_by),
      ip_address: Keyword.get(opts, :ip_address),
      user_agent: Keyword.get(opts, :user_agent)
    )
  end

  @doc """
  Records a user deletion.

  ## Examples

      iex> log_user_deleted(user,
      ...>   performed_by: admin_user,
      ...>   ip_address: "192.168.1.1",
      ...>   metadata: %{"reason" => "account cleanup"}
      ...> )
      {:ok, %AuditLog{}}
  """
  @spec log_user_deleted(User.t(), Keyword.t()) ::
          {:ok, AuditLog.t()} | {:error, Ecto.Changeset.t()}
  def log_user_deleted(user, opts \\ []) do
    log(
      action: :user_deleted,
      resource_type: "User",
      resource_id: user.id,
      changes: %{
        "email" => user.email,
        "role" => to_string(user.role),
        "name" => user.name
      },
      metadata: Keyword.get(opts, :metadata, %{}),
      performed_by_id: extract_performed_by_id(opts),
      performed_by: Keyword.get(opts, :performed_by),
      ip_address: Keyword.get(opts, :ip_address),
      user_agent: Keyword.get(opts, :user_agent)
    )
  end

  @doc """
  Records user session revocation.

  ## Examples

      iex> log_sessions_revoked(user,
      ...>   session_count: 3,
      ...>   performed_by: admin_user,
      ...>   ip_address: "192.168.1.1"
      ...> )
      {:ok, %AuditLog{}}
  """
  @spec log_sessions_revoked(User.t(), Keyword.t()) ::
          {:ok, AuditLog.t()} | {:error, Ecto.Changeset.t()}
  def log_sessions_revoked(user, opts \\ []) do
    session_count = Keyword.get(opts, :session_count, 0)

    log(
      action: :sessions_revoked,
      resource_type: "User",
      resource_id: user.id,
      changes: %{},
      metadata:
        Map.merge(
          %{"session_count" => session_count},
          Keyword.get(opts, :metadata, %{})
        ),
      performed_by_id: extract_performed_by_id(opts),
      performed_by: Keyword.get(opts, :performed_by),
      ip_address: Keyword.get(opts, :ip_address),
      user_agent: Keyword.get(opts, :user_agent)
    )
  end

  @doc """
  Records a magic link sent by an admin.

  ## Examples

      iex> log_magic_link_sent(user,
      ...>   performed_by: admin_user,
      ...>   ip_address: "192.168.1.1"
      ...> )
      {:ok, %AuditLog{}}
  """
  @spec log_magic_link_sent(User.t(), Keyword.t()) ::
          {:ok, AuditLog.t()} | {:error, Ecto.Changeset.t()}
  def log_magic_link_sent(user, opts \\ []) do
    log(
      action: :magic_link_sent,
      resource_type: "User",
      resource_id: user.id,
      changes: %{},
      metadata: Keyword.get(opts, :metadata, %{}),
      performed_by_id: extract_performed_by_id(opts),
      performed_by: Keyword.get(opts, :performed_by),
      ip_address: Keyword.get(opts, :ip_address),
      user_agent: Keyword.get(opts, :user_agent)
    )
  end

  @doc """
  Retrieves audit logs for a specific resource.

  ## Examples

      iex> get_logs_for_resource("User", user.id)
      [%AuditLog{}, ...]

      iex> get_logs_for_resource("User", user.id, limit: 10)
      [%AuditLog{}, ...]
  """
  @spec get_logs_for_resource(String.t(), Ecto.UUID.t(), Keyword.t()) :: [AuditLog.t()]
  def get_logs_for_resource(resource_type, resource_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(log in AuditLog,
      where: log.resource_type == ^resource_type and log.resource_id == ^resource_id,
      order_by: [desc: log.inserted_at],
      limit: ^limit,
      preload: [:performed_by]
    )
    |> Repo.all()
  end

  @doc """
  Retrieves audit logs for a given user (actions performed BY this user).

  ## Examples

      iex> get_logs_by_user(admin_user.id)
      [%AuditLog{}, ...]
  """
  @spec get_logs_by_user(Ecto.UUID.t(), Keyword.t()) :: [AuditLog.t()]
  def get_logs_by_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(log in AuditLog,
      where: log.performed_by_id == ^user_id,
      order_by: [desc: log.inserted_at],
      limit: ^limit,
      preload: [:performed_by]
    )
    |> Repo.all()
  end

  # Extracts the user ID from options
  @spec extract_performed_by_id(Keyword.t()) :: Ecto.UUID.t() | nil
  defp extract_performed_by_id(opts) do
    cond do
      Keyword.has_key?(opts, :performed_by_id) ->
        Keyword.get(opts, :performed_by_id)

      Keyword.has_key?(opts, :performed_by) ->
        case Keyword.get(opts, :performed_by) do
          %User{id: id} -> id
          _ -> nil
        end

      true ->
        nil
    end
  end

  # Logs the insertion result
  @spec log_result({:ok, AuditLog.t()} | {:error, Ecto.Changeset.t()}) :: :ok
  defp log_result({:ok, audit_log}) do
    Logger.info("Audit log created",
      action: audit_log.action,
      resource_type: audit_log.resource_type,
      resource_id: audit_log.resource_id,
      performed_by_id: audit_log.performed_by_id
    )

    :ok
  end

  defp log_result({:error, changeset}) do
    Logger.error("Failed to create audit log",
      errors: inspect(changeset.errors)
    )

    :ok
  end
end
