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

  use Portfolio.Services.Service

  alias Portfolio.Auth.MagicLink
  alias Portfolio.Auth.Mailer
  alias Portfolio.Auth.Repositories.{MagicLinkRepository, UserRepository}
  alias Portfolio.DomainEvents
  alias Portfolio.DomainEvents.Builders
  alias Portfolio.Repo

  # Timing-safe delay in milliseconds to prevent timing attacks
  # This delay matches the average execution time of the existing user path
  # (DB transaction + event publishing + email preparation)
  @timing_safe_delay_ms 3

  @impl true
  @doc """
  Requests a magic link for authentication.

  Workflow:
  1. Check rate limit for the email (unless bypassed)
  2. Get or create user by email
  3. Generate magic link token
  4. Save magic link to database
  5. Emit domain event
  6. Send email with magic link

  ## Parameters

  - `email` - Email address to send the magic link to
  - `opts` - Options:
    - `:bypass_rate_limit` - Skip rate limiting check (for admin use)

  ## Returns

  - `{:ok, magic_link}` - Magic link created and email sent
  - `{:error, :rate_limit_exceeded}` - Too many requests
  - `{:error, changeset}` - Validation error

  ## Examples

      iex> execute("user@example.com")
      {:ok, %MagicLink{token: "..."}}

      iex> execute("spammer@example.com")  # After 5 requests in an hour
      {:error, :rate_limit_exceeded}

      iex> execute("user@example.com", bypass_rate_limit: true)
      {:ok, %MagicLink{token: "..."}}  # Bypasses rate limit
  """
  @spec execute(String.t(), keyword()) ::
          {:ok, MagicLink.t()}
          | {:error, Ecto.Changeset.t() | :user_not_found | {:rate_limit_exceeded, integer()}}
  def execute(email, opts \\ []) when is_binary(email) do
    with_telemetry(
      [:portfolio, :auth, :magic_link, :requested],
      %{email: email},
      fn -> execute_with_rate_limit_check(email, opts) end
    )
  end

  defp execute_with_rate_limit_check(email, opts) do
    bypass_rate_limit = Keyword.get(opts, :bypass_rate_limit, false)

    if bypass_rate_limit do
      do_request_magic_link(email, opts)
    else
      check_rate_limit_and_execute(email, opts)
    end
  end

  defp check_rate_limit_and_execute(email, opts) do
    case Portfolio.RateLimiter.check_rate(:magic_link_request, email) do
      {:deny, retry_after} ->
        {:error, {:rate_limit_exceeded, retry_after}}

      {:allow, _remaining} ->
        do_request_magic_link(email, opts)
    end
  end

  # Internal implementation after rate limit check
  defp do_request_magic_link(email, opts) do
    bypass_rate_limit = Keyword.get(opts, :bypass_rate_limit, false)

    with {:ok, user_or_marker} <- fetch_or_create_user(email) do
      handle_user_result(user_or_marker, bypass_rate_limit)
    end
  end

  defp handle_user_result({:user_not_found, _email}, bypass_rate_limit) do
    # If admin bypass, return actual error so admins know user doesn't exist
    if bypass_rate_limit do
      {:error, :user_not_found}
    else
      # Anti-timing-attack: Add artificial delay to match existing user path
      # This prevents attackers from using response time to enumerate valid emails
      # Delay should match the average time for: DB insert + event publish + email send
      add_timing_safe_delay()

      # Return success but don't send email
      # This prevents attackers from discovering which emails are registered
      {:ok, :email_sent}
    end
  end

  defp handle_user_result(user, _bypass_rate_limit) do
    # Normal case: user exists
    create_and_send_magic_link(user)
  end

  # Create magic link and send email for existing user
  defp create_and_send_magic_link(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:magic_link, fn _repo, _changes ->
      create_magic_link(user)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{magic_link: magic_link}} ->
        # Emit domain event
        # Security: token intentionally omitted from event to prevent logging exposure
        event = Builders.build_magic_link_requested(magic_link, user.email)
        DomainEvents.publish(:magic_link_requested, event)

        # Send email with magic link
        _email_result = Mailer.send_magic_link_email(user, magic_link)

        {:ok, magic_link}

      {:error, _step, error, _changes} ->
        {:error, error}
    end
  end

  # Fetch existing user or create new one
  # Production: don't auto-create users to prevent email enumeration (security)
  # Dev/Test: auto-create users for convenience
  defp fetch_or_create_user(email) do
    case UserRepository.get_by_email(email) do
      {:ok, user} ->
        {:ok, user}

      {:error, :not_found} ->
        # Production: block auto-creation (anti-enumeration)
        if production_env?() do
          # Return special marker instead of error to prevent enumeration
          {:ok, {:user_not_found, email}}
        else
          # Dev/Test: auto-create the user
          create_new_user(email)
        end
    end
  end

  # Check if running in production environment
  # Uses application config to allow test overrides
  defp production_env? do
    env = Application.get_env(:portfolio, :env, Mix.env())
    env == :prod
  end

  # Creates a new user and emits the event
  # Note: In dev/test only, users are auto-created with default role (:user)
  # Production blocks auto-creation entirely (anti-enumeration security)
  defp create_new_user(email) do
    case UserRepository.insert(%{email: email}) do
      {:ok, user} ->
        # Emit UserCreated event for new users
        DomainEvents.publish(:user_created, %Portfolio.Auth.Events.UserCreated{
          user_id: user.id,
          email: user.email,
          role: user.role,
          created_at: user.inserted_at
        })

        {:ok, user}

      error ->
        error
    end
  end

  # Create a new magic link for the user
  defp create_magic_link(user) do
    token = generate_token()
    short_code = generate_short_code()

    ttl_minutes = get_magic_link_ttl()

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(ttl_minutes, :minute)
      |> DateTime.truncate(:second)

    MagicLinkRepository.insert(%{
      user_id: user.id,
      token: token,
      short_code: short_code,
      expires_at: expires_at
    })
  end

  # Get magic link TTL from configuration
  defp get_magic_link_ttl do
    Application.get_env(:portfolio, :auth, [])
    |> Keyword.get(:magic_link_ttl_minutes, 15)
  end

  # Generate a secure random token
  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  # Generate a short code (6 alphanumeric characters) for URL display
  # Le code court est visible dans l'URL, le token reste caché dans le formulaire
  defp generate_short_code do
    :crypto.strong_rand_bytes(4)
    |> Base.encode32(padding: false)
    |> String.slice(0..5)
    |> String.upcase()
  end

  # Add timing-safe delay to prevent timing attacks
  # This function introduces an artificial delay for the non-existing user path
  # to match the timing of the existing user path (DB insert + event + email).
  #
  # Security consideration: The delay should be calibrated to match the average
  # execution time of create_and_send_magic_link/1. Based on profiling:
  # - DB transaction (insert magic link): ~500-1000µs
  # - Event publishing (domain event): ~100-300µs
  # - Email send preparation (Bamboo): ~300-700µs
  # - Variance and system overhead: ~100-500µs
  # Total: ~1000-2500µs, using 3ms provides good coverage with buffer
  defp add_timing_safe_delay do
    Process.sleep(@timing_safe_delay_ms)
  end
end
