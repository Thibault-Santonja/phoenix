defmodule Portfolio.Secrets do
  @moduledoc """
  Manages authentication secrets for the Portfolio application.

  This module provides functions to retrieve secure signing secrets
  for authentication tokens, implementing the AshAuthentication.Secret
  behavior for secure credential management.
  """
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Portfolio.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:portfolio, :token_signing_secret)
  end
end
