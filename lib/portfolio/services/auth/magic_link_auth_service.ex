defmodule Portfolio.Services.Auth.MagicLinkAuthService do
  @moduledoc """
  Service for magic link authentication workflow.

  Responsibilities:
  - Rate limiting check
  - Get or create user
  - Create magic link token
  - Send email notification
  - Emit domain events
  - Record telemetry

  This service encapsulates the complex workflow of requesting a magic link,
  which involves rate limiting, user management, token generation, email sending,
  and event emission.
  """

  @behaviour Portfolio.Services.Service

  alias Portfolio.Auth.{MagicLink, User}
  alias Portfolio.Auth.Events.MagicLinkRequested
  alias Portfolio.Auth.Mailer
  alias Portfolio.DomainEvents
  alias Portfolio.Repo

  @impl true
  @doc """
  Requests a magic link for authentication.

  Workflow:
  1. Check rate limit for the email
  2. Get or create user by email
  3. Generate magic link token
  4. Save magic link to database
  5. Emit domain event
  6. Send email with magic link

  ## Parameters

  - `email` - Email address to send the magic link to
  - `opts` - Options (currently unused)

  ## Returns

  - `{:ok, magic_link}` - Magic link created and email sent
  - `{:error, :rate_limit_exceeded}` - Too many requests
  - `{:error, changeset}` - Validation error

  ## Examples

      iex> execute("user@example.com")
      {:ok, %MagicLink{token: "..."}}

      iex> execute("spammer@example.com")  # After 5 requests in an hour
      {:error, :rate_limit_exceeded}
  """
  @spec execute(String.t(), keyword()) ::
          {:ok, MagicLink.t()}
          | {:error, Ecto.Changeset.t() | :user_not_found | :rate_limit_exceeded}
  def execute(email, _opts \\ []) when is_binary(email) do
    start_time = System.monotonic_time()

    # Check rate limit
    result =
      case Portfolio.RateLimiter.check_rate(:magic_link_request, email) do
        {:deny, _retry_after} ->
          {:error, :rate_limit_exceeded}

        {:allow, _remaining} ->
          do_request_magic_link(email)
      end

    # Record telemetry (using auth namespace for backward compatibility)
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:portfolio, :auth, :magic_link, :requested],
      %{duration: duration},
      %{email: email, result: elem(result, 0)}
    )

    result
  end

  # Internal implementation after rate limit check
  defp do_request_magic_link(email) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:user, fn _repo, _changes ->
      get_or_create_user(email)
    end)
    |> Ecto.Multi.run(:magic_link, fn _repo, %{user: user} ->
      create_magic_link(user)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, magic_link: magic_link}} ->
        # Emit domain event
        DomainEvents.publish(:magic_link_requested, %MagicLinkRequested{
          magic_link_id: magic_link.id,
          email: user.email,
          token: magic_link.token,
          requested_at: magic_link.inserted_at,
          expires_at: magic_link.expires_at
        })

        # Send email with magic link
        Mailer.send_magic_link_email(user, magic_link)

        {:ok, magic_link}

      {:error, _step, error, _changes} ->
        {:error, error}
    end
  end

  # Get existing user or create new one
  defp get_or_create_user(email) do
    case Repo.get_by(User, email: email) do
      nil ->
        %User{}
        |> User.changeset(%{email: email, role: "admin"})
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  # Create a new magic link for the user
  defp create_magic_link(user) do
    token = generate_token()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(15, :minute)
      |> DateTime.truncate(:second)

    %MagicLink{}
    |> MagicLink.changeset(%{
      user_id: user.id,
      token: token,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  # Generate a secure random token
  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
