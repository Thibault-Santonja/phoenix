defmodule Portfolio.Repo do
  @moduledoc """
  Ecto repository for the Portfolio application.

  Provides database access using PostgreSQL adapter.
  """

  use Ecto.Repo,
    otp_app: :portfolio,
    adapter: Ecto.Adapters.Postgres
end
