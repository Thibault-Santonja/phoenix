ExUnit.start(
  capture_log: true,
  # Exclude slow/network tests by default, include with: mix test --include network
  exclude: [:network, :slow]
)

Ecto.Adapters.SQL.Sandbox.mode(Portfolio.Repo, :manual)

# Define Mox mocks for external dependencies
Mox.defmock(Portfolio.Photography.Storage.MockStorage,
  for: Portfolio.Photography.Storage.PhotoStorage
)
