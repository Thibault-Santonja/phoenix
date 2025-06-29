defmodule Portfolio.Accounts do
  use Ash.Domain,
    otp_app: :portfolio

  resources do
    resource Portfolio.Accounts.Token
    resource Portfolio.Accounts.User
  end
end
