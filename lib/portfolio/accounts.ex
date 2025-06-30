defmodule Portfolio.Accounts do
  @moduledoc """
  Accounts domain for the Portfolio application.

  This domain manages user accounts and authentication tokens, providing
  the core functionality for user management and authentication across
  the application. It aggregates resources like User and Token to create
  a complete authentication system.
  """
  use Ash.Domain,
    otp_app: :portfolio

  resources do
    resource Portfolio.Accounts.Token
    resource Portfolio.Accounts.User
  end
end
