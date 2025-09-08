defmodule Portfolio.Auth.Events do
  @moduledoc """
  Domain events for the Auth bounded context.

  These events represent important business occurrences in the Auth domain.
  They allow other parts of the system to react to authentication events
  without creating tight coupling.

  ## Events

  - `MagicLinkRequested` - A user has requested a magic link for authentication
  - `MagicLinkVerified` - A magic link has been successfully verified
  """

  defmodule MagicLinkRequested do
    @moduledoc """
    Event raised when a user requests a magic link for authentication.

    This event is triggered when a user submits their email to receive
    a passwordless authentication link.

    ## Fields

    - `magic_link_id` - Unique identifier of the magic link
    - `email` - Email address of the user requesting authentication
    - `token` - The magic link token (hashed in database)
    - `requested_at` - Timestamp when the magic link was requested
    - `expires_at` - Timestamp when the magic link will expire

    ## Use Cases

    - Send authentication email to user
    - Log authentication attempts
    - Track login request metrics
    - Implement rate limiting
    """

    @enforce_keys [:magic_link_id, :email, :token, :requested_at, :expires_at]
    defstruct [:magic_link_id, :email, :token, :requested_at, :expires_at]

    @type t :: %__MODULE__{
            magic_link_id: Ecto.UUID.t(),
            email: String.t(),
            token: String.t(),
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
