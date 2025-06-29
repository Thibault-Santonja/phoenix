defmodule Portfolio.Secrets do
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
