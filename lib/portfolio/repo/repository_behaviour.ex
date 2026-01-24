defmodule Portfolio.Repo.RepositoryBehaviour do
  @moduledoc """
  Behaviour defining the standard interface for repositories.

  This behaviour establishes a consistent contract for all repositories
  in the application, enabling:

  1. **Testability**: Easy mocking via Mox or manual mocks
  2. **Documentation**: Clear interface expectations
  3. **Consistency**: All repositories follow the same patterns
  4. **Dependency Injection**: Swap implementations at runtime

  ## Core Operations

  All repositories should implement at minimum:
  - `get/2` - Fetch by ID
  - `list/1` - List with filters
  - `insert/1` - Create new record
  - `update/2` - Update existing record
  - `delete/1` - Remove record

  ## Optional Operations

  Some repositories may also implement:
  - `get_by_*/2` - Fetch by specific field
  - `count/0` - Total count
  - Domain-specific queries

  ## Usage

  Implement this behaviour in your repository:

      defmodule MyApp.UserRepository do
        @behaviour Portfolio.Repo.RepositoryBehaviour

        @impl true
        def get(id, opts \\\\ []) do
          # ...
        end

        # ... other implementations
      end

  ## Testing with Mox

      # In test_helper.exs
      Mox.defmock(MyApp.MockUserRepository, for: Portfolio.Repo.RepositoryBehaviour)

      # In config/test.exs
      config :my_app, :user_repository, MyApp.MockUserRepository

  ## Note on Flexibility

  This behaviour defines common operations. Repositories may implement
  additional domain-specific functions beyond this interface.
  """

  @doc """
  Fetches a record by its primary key (ID).

  ## Parameters

  - `id` - The primary key (usually UUID)
  - `opts` - Optional keyword list for preloads, etc.

  ## Returns

  - `{:ok, record}` - Record found
  - `{:error, :not_found}` - Record not found
  """
  @callback get(id :: term(), opts :: keyword()) ::
              {:ok, struct()} | {:error, :not_found}

  @doc """
  Lists records with optional filters.

  ## Parameters

  - `opts` - Keyword list of filters and options

  ## Common Options

  - `:preload` - Associations to preload
  - `:limit` - Maximum number of records
  - `:offset` - Number of records to skip
  - `:order_by` - Sorting criteria

  ## Returns

  List of records (may be empty)
  """
  @callback list(opts :: keyword()) :: [struct()]

  @doc """
  Inserts a new record.

  ## Parameters

  - `attrs` - Map of attributes for the new record

  ## Returns

  - `{:ok, record}` - Record created successfully
  - `{:error, changeset}` - Validation or constraint error
  """
  @callback insert(attrs :: map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}

  @doc """
  Updates an existing record.

  ## Parameters

  - `record` - The existing record to update
  - `attrs` - Map of attributes to update

  ## Returns

  - `{:ok, record}` - Record updated successfully
  - `{:error, changeset}` - Validation or constraint error
  """
  @callback update(record :: struct(), attrs :: map()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}

  @doc """
  Deletes a record.

  ## Parameters

  - `record` - The record to delete

  ## Returns

  - `{:ok, record}` - Record deleted successfully
  - `{:error, changeset}` - Constraint error (e.g., foreign key)
  """
  @callback delete(record :: struct()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}

  @doc """
  Counts total records (optional callback).

  Repositories may implement this for statistics.

  ## Returns

  Non-negative integer count
  """
  @callback count() :: non_neg_integer()

  @optional_callbacks [count: 0]
end
