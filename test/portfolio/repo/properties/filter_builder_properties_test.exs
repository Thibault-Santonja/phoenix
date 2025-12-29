defmodule Portfolio.Repo.Properties.FilterBuilderPropertiesTest do
  @moduledoc """
  Property-based tests for the FilterBuilder module.

  Tests invariants that must hold for all valid filter inputs:
  - Idempotency of filter application
  - Order independence of commutative filters
  - Identity property for nil/empty filters
  - Composition correctness
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Ecto.Query
  alias Portfolio.Repo.FilterBuilder

  # =============================================================================
  # Generators
  # =============================================================================

  defp positive_integer_generator do
    integer(1..1000)
  end

  defp non_negative_integer_generator do
    integer(0..1000)
  end

  defp preload_generator do
    member_of([
      [],
      [:user],
      [:photos],
      [:album],
      [:user, :photos],
      [:album, :photos]
    ])
  end

  defp order_by_generator do
    member_of([
      [],
      [asc: :id],
      [desc: :id],
      [asc: :inserted_at],
      [desc: :inserted_at],
      [desc: :inserted_at, asc: :id]
    ])
  end

  defp common_filter_key_generator do
    member_of([:preload, :limit, :offset, :order_by])
  end

  defp unknown_filter_key_generator do
    member_of([:foo, :bar, :unknown_filter, :custom_thing])
  end

  # A simple schema for testing
  defmodule TestSchema do
    use Ecto.Schema

    schema "test_items" do
      field(:name, :string)
      field(:status, :string)
      timestamps()
    end
  end

  defp base_query do
    from(t in TestSchema)
  end

  # =============================================================================
  # Properties for common_filter?/1
  # =============================================================================

  describe "common_filter?/1 properties" do
    property "returns true only for known common filters" do
      check all(key <- common_filter_key_generator()) do
        assert FilterBuilder.common_filter?(key) == true
      end
    end

    property "returns false for unknown filters" do
      check all(key <- unknown_filter_key_generator()) do
        assert FilterBuilder.common_filter?(key) == false
      end
    end

    property "returns false for arbitrary atoms" do
      check all(
              str <- string(:alphanumeric, min_length: 5, max_length: 20),
              str not in ["preload", "limit", "offset", "order_by"]
            ) do
        key = String.to_atom(str)
        assert FilterBuilder.common_filter?(key) == false
      end
    end
  end

  # =============================================================================
  # Properties for apply_common_filter/3 - Identity
  # =============================================================================

  describe "apply_common_filter/3 identity properties" do
    property "nil values return unchanged query for all common filters" do
      check all(key <- common_filter_key_generator()) do
        query = base_query()
        result = FilterBuilder.apply_common_filter(query, key, nil)
        # Query should be structurally equivalent
        assert inspect(result) == inspect(query)
      end
    end

    property "empty lists return unchanged query for preload and order_by" do
      check all(key <- member_of([:preload, :order_by])) do
        query = base_query()
        result = FilterBuilder.apply_common_filter(query, key, [])
        assert inspect(result) == inspect(query)
      end
    end
  end

  # =============================================================================
  # Properties for apply_common_filter/3 - Limit
  # =============================================================================

  describe "apply_common_filter/3 limit properties" do
    property "positive integers produce valid limit queries" do
      check all(limit <- positive_integer_generator()) do
        query = base_query()
        result = FilterBuilder.apply_common_filter(query, :limit, limit)

        # The query should have a limit clause
        assert result.limit != nil
        # Ecto uses AST representation for interpolated values
        assert result.limit.params != nil or result.limit.expr != nil
      end
    end

    property "limit modifies the query" do
      check all(limit <- positive_integer_generator()) do
        query = base_query()
        result = FilterBuilder.apply_common_filter(query, :limit, limit)

        # Result should be different from base query
        assert result.limit != nil
        assert query.limit == nil
      end
    end
  end

  # =============================================================================
  # Properties for apply_common_filter/3 - Offset
  # =============================================================================

  describe "apply_common_filter/3 offset properties" do
    property "non-negative integers produce valid offset queries" do
      check all(offset <- non_negative_integer_generator()) do
        query = base_query()
        result = FilterBuilder.apply_common_filter(query, :offset, offset)

        assert result.offset != nil
        # Ecto uses AST representation for interpolated values
        assert result.offset.params != nil or result.offset.expr != nil
      end
    end

    property "offset modifies the query" do
      check all(offset <- non_negative_integer_generator()) do
        query = base_query()
        result = FilterBuilder.apply_common_filter(query, :offset, offset)

        assert result.offset != nil
        assert query.offset == nil
      end
    end
  end

  # =============================================================================
  # Properties for apply_filters/3
  # =============================================================================

  describe "apply_filters/3 properties" do
    property "empty options return unchanged query" do
      query = base_query()
      result = FilterBuilder.apply_filters(query, [], %{})
      assert inspect(result) == inspect(query)
    end

    property "unknown filters are silently ignored" do
      check all(
              key <- unknown_filter_key_generator(),
              value <- integer()
            ) do
        query = base_query()
        result = FilterBuilder.apply_filters(query, [{key, value}], %{})
        assert inspect(result) == inspect(query)
      end
    end

    property "filters can be composed in any order for independent filters" do
      check all(
              limit <- positive_integer_generator(),
              offset <- non_negative_integer_generator()
            ) do
        query = base_query()

        result1 = FilterBuilder.apply_filters(query, [limit: limit, offset: offset], %{})
        result2 = FilterBuilder.apply_filters(query, [offset: offset, limit: limit], %{})

        # Both should have limit and offset set
        assert result1.limit != nil
        assert result1.offset != nil
        assert result2.limit != nil
        assert result2.offset != nil
      end
    end

    property "custom handlers take precedence over common filters" do
      check all(limit <- positive_integer_generator()) do
        query = base_query()

        # Custom handler that marks the query with a where clause instead
        handlers = %{
          limit: fn q, _value -> where(q, [t], t.id == ^999) end
        }

        result = FilterBuilder.apply_filters(query, [limit: limit], handlers)
        # Custom handler was called (added where, not limit)
        assert result.limit == nil
        assert result.wheres != []
      end
    end

    property "multiple filters accumulate correctly" do
      check all(
              limit <- positive_integer_generator(),
              offset <- non_negative_integer_generator(),
              preloads <- preload_generator()
            ) do
        query = base_query()

        result =
          FilterBuilder.apply_filters(
            query,
            [limit: limit, offset: offset, preload: preloads],
            %{}
          )

        assert result.limit != nil
        assert result.offset != nil

        if preloads != [] do
          assert result.preloads != []
        end
      end
    end
  end

  # =============================================================================
  # Properties for apply_single_filter/4
  # =============================================================================

  describe "apply_single_filter/4 properties" do
    property "delegates to custom handler when present" do
      check all(value <- integer()) do
        query = base_query()
        called = :atomics.new(1, signed: false)

        handlers = %{
          test_filter: fn q, _v ->
            :atomics.add(called, 1, 1)
            q
          end
        }

        _result = FilterBuilder.apply_single_filter(query, :test_filter, value, handlers)
        assert :atomics.get(called, 1) == 1
      end
    end

    property "falls back to common filter when no handler" do
      check all(limit <- positive_integer_generator()) do
        query = base_query()
        result = FilterBuilder.apply_single_filter(query, :limit, limit, %{})

        assert result.limit != nil
      end
    end

    property "returns unchanged query for unknown filter without handler" do
      check all(
              key <- unknown_filter_key_generator(),
              value <- integer()
            ) do
        query = base_query()
        result = FilterBuilder.apply_single_filter(query, key, value, %{})

        assert inspect(result) == inspect(query)
      end
    end
  end

  # =============================================================================
  # Properties for preload handling
  # =============================================================================

  describe "preload handling properties" do
    property "single atom preload is converted to list" do
      check all(preload <- member_of([:user, :photos, :album])) do
        query = base_query()
        result = FilterBuilder.apply_common_filter(query, :preload, preload)

        assert result.preloads == [preload]
      end
    end

    property "list preloads are preserved" do
      check all(preloads <- preload_generator(), preloads != []) do
        query = base_query()
        result = FilterBuilder.apply_common_filter(query, :preload, preloads)

        assert result.preloads == preloads
      end
    end
  end

  # =============================================================================
  # Properties for order_by handling
  # =============================================================================

  describe "order_by handling properties" do
    property "order_by specifications are applied" do
      check all(order_spec <- order_by_generator(), order_spec != []) do
        query = base_query()
        result = FilterBuilder.apply_common_filter(query, :order_by, order_spec)

        assert result.order_bys != []
      end
    end
  end
end
