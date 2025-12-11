ExUnit.start(capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(Portfolio.Repo, :manual)

# Define Mox mocks for external dependencies
Mox.defmock(Portfolio.Photography.Storage.MockStorage,
  for: Portfolio.Photography.Storage.PhotoStorage
)
