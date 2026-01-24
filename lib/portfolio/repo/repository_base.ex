defmodule Portfolio.Repo.RepositoryBase do
  @moduledoc """
  Base module providing common repository patterns and utilities.

  This module defines shared behaviors and utilities for all repositories,
  ensuring consistency across the codebase and reducing duplication.

  ## Usage

  Use this module in your repository to get access to common patterns:

      defmodule MyRepository do
        use Portfolio.Repo.RepositoryBase

        @schema MySchema
        @filter_handlers %{
          status: &__MODULE__.filter_by_status/2
        }

        def list(opts \\\\ []) do
          base_query()
          |> apply_filters(opts, @filter_handlers)
          |> Repo.all()
        end
      end

  ## Provided Functions

  When you `use` this module, you get:

  - `apply_filters/3` - Apply filters using handlers + common filters
  - `wrap_result/1` - Wrap nil/value in {:ok, _}/{:error, :not_found}
  - `maybe_preload/2` - Conditionally apply preloads
  - `base_query/0` - Returns `from(s in @schema)` (requires @schema)

  ## Design Principles

  1. **Liskov Substitution**: All repositories behave consistently
  2. **DRY**: Common patterns defined once
  3. **Open/Closed**: Extend via @filter_handlers, not code changes
  """

  @doc """
  Provides repository base functionality when used.

  ## Options

  No options currently supported, but the macro is designed for future extension.

  ## Generated Functions

  - `apply_filters/2` and `apply_filters/3` - Filter application
  - `wrap_result/1` - Result wrapping
  - `maybe_preload/2` - Conditional preloading
  - `base_query/0` - Base query from @schema (if defined)
  """
  defmacro __using__(_opts) do
    quote do
      import Ecto.Query, warn: false
      import Portfolio.Repo.FilterBuilder, only: [apply_filters: 3, apply_single_filter: 4]
      import Portfolio.Repo.QueryHelpers, only: [wrap_result: 1, maybe_preload: 2]

      alias Portfolio.Repo

      # Default empty filter handlers - override in your repository
      @filter_handlers %{}

      # Allow repositories to override filter_handlers before compile
      @before_compile Portfolio.Repo.RepositoryBase
    end
  end

  alias Portfolio.Repo.FilterBuilder

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      @doc """
      Applies filters using the repository's defined handlers.

      Uses the module's @filter_handlers attribute for custom filters
      and falls back to common filters (preload, limit, offset, order_by).
      """
      def apply_repo_filters(query, opts) do
        FilterBuilder.apply_filters(query, opts, @filter_handlers)
      end
    end
  end
end
