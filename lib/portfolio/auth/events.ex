defmodule Portfolio.Auth.Events do
  @moduledoc """
  Domain events for the Auth bounded context.

  These events represent important business occurrences in the Auth domain.
  They allow other parts of the system to react to authentication events
  without creating tight coupling.

  ## Events

  - `UserCreated` - A new user has been created in the system
  - `SessionCreated` - A user session has been created (successful login)
  - `MagicLinkRequested` - A user has requested a magic link for authentication
  - `MagicLinkVerified` - A magic link has been successfully verified
  """

  defmodule UserCreated do
    @moduledoc """
    Event raised when a new user is created in the system.

    This event is triggered when a user record is first created,
    typically during the first magic link request.

    ## Fields

    - `user_id` - Unique identifier of the new user
    - `email` - Email address of the new user
    - `role` - Role assigned to the user
    - `created_at` - Timestamp when the user was created

    ## Use Cases

    - Send welcome email
    - Log user registration metrics
    - Initialize user preferences
    - Trigger onboarding workflow
    """

    @enforce_keys [:user_id, :email, :role, :created_at]
    defstruct [:user_id, :email, :role, :created_at]

    @type t :: %__MODULE__{
            user_id: Ecto.UUID.t(),
            email: String.t(),
            role: atom(),
            created_at: DateTime.t()
          }
  end

  defmodule SessionCreated do
    @moduledoc """
    Event raised when a user session is created (successful login).

    This event is triggered when a user successfully authenticates
    and a session is created.

    ## Fields

    - `session_id` - Unique identifier of the session
    - `user_id` - ID of the authenticated user
    - `email` - Email address of the authenticated user
    - `created_at` - Timestamp when the session was created
    - `expires_at` - Timestamp when the session will expire

    ## Use Cases

    - Log authentication events
    - Track active sessions
    - Update user last_login timestamp
    - Monitor login patterns for security
    """

    @enforce_keys [:session_id, :user_id, :email, :created_at, :expires_at]
    defstruct [:session_id, :user_id, :email, :created_at, :expires_at]

    @type t :: %__MODULE__{
            session_id: Ecto.UUID.t(),
            user_id: Ecto.UUID.t(),
            email: String.t(),
            created_at: DateTime.t(),
            expires_at: DateTime.t()
          }
  end

  defmodule MagicLinkRequested do
    @moduledoc """
    Event raised when a user requests a magic link for authentication.

    This event is triggered when a user submits their email to receive
    a passwordless authentication link.

    ## Fields

    - `magic_link_id` - Unique identifier of the magic link
    - `email` - Email address of the user requesting authentication
    - `short_code` - Short code (6 characters) visible in URL
    - `requested_at` - Timestamp when the magic link was requested
    - `expires_at` - Timestamp when the magic link will expire

    ## Security Note

    The plaintext token is intentionally NOT included in this event
    to prevent accidental logging or exposure of sensitive authentication data.
    Event consumers should not need the raw token.

    ## Use Cases

    - Log authentication attempts (without token)
    - Track login request metrics
    - Implement rate limiting
    """

    @enforce_keys [:magic_link_id, :email, :short_code, :requested_at, :expires_at]
    defstruct [:magic_link_id, :email, :short_code, :requested_at, :expires_at]

    @type t :: %__MODULE__{
            magic_link_id: Ecto.UUID.t(),
            email: String.t(),
            short_code: String.t(),
            requested_at: DateTime.t(),
            expires_at: DateTime.t()
          }
  end

  defmodule MagicLinkVerified do
    @moduledoc """
    Event raised when a magic link is successfully verified.

    This event is triggered when a user clicks a valid magic link
    and is successfully authenticated.

    ## Fields

    - `magic_link_id` - Unique identifier of the verified magic link
    - `user_id` - ID of the authenticated user
    - `email` - Email address of the authenticated user
    - `verified_at` - Timestamp when the magic link was verified

    ## Use Cases

    - Log successful authentication
    - Update user last_login timestamp
    - Track authentication metrics
    - Trigger welcome notifications for new users
    """

    @enforce_keys [:magic_link_id, :user_id, :email, :verified_at]
    defstruct [:magic_link_id, :user_id, :email, :verified_at]

    @type t :: %__MODULE__{
            magic_link_id: Ecto.UUID.t(),
            user_id: Ecto.UUID.t(),
            email: String.t(),
            verified_at: DateTime.t()
          }
  end
end
