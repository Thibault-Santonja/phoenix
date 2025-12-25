defmodule Portfolio.Repo.FilterBuilderTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Repo.FilterBuilder

  import Ecto.Query

  # Use a simple schema for testing
  defmodule TestSchema do
    use Ecto.Schema

    schema "test_items" do
      field :status, :string
      field :category, :string
      field :priority, :integer
      timestamps()
    end
  end

  defp base_query do
    from(t in TestSchema, as: :test)
  end

  describe "apply_filters/3" do
    test "returns query unchanged when opts is empty list" do
      query = base_query()

      result = FilterBuilder.apply_filters(query, [], %{})

      assert result == query
    end

    test "applies single filter with custom handler" do
      query = base_query()
      handlers = %{status: fn q, value -> where(q, [t], t.status == ^value) end}

      result = FilterBuilder.apply_filters(query, [status: "active"], handlers)

      # Verify WHERE clause was added
      assert %Ecto.Query{wheres: [_where]} = result
    end

    test "applies multiple filters with custom handlers" do
      query = base_query()

      handlers = %{
        status: fn q, value -> where(q, [t], t.status == ^value) end,
        category: fn q, value -> where(q, [t], t.category == ^value) end
      }

      result =
        FilterBuilder.apply_filters(query, [status: "active", category: "tech"], handlers)

      # Verify both WHERE clauses were added
      assert %Ecto.Query{wheres: wheres} = result
      assert length(wheres) == 2
    end

    test "applies common filters without custom handlers" do
      query = base_query()

      result = FilterBuilder.apply_filters(query, [limit: 10, offset: 5], %{})

      # Verify limit and offset were applied
      assert %Ecto.Query{limit: limit, offset: offset} = result
      assert limit != nil
      assert offset != nil
    end

    test "mixes custom handlers and common filters" do
      query = base_query()
      handlers = %{status: fn q, value -> where(q, [t], t.status == ^value) end}

      result =
        FilterBuilder.apply_filters(query, [status: "active", limit: 10], handlers)

      # Verify both custom filter and limit were applied
      assert %Ecto.Query{wheres: [_where], limit: limit} = result
      assert limit != nil
    end

    test "ignores unknown filters silently" do
      query = base_query()

      result =
        FilterBuilder.apply_filters(query, [unknown_filter: "value", limit: 10], %{})

      # Only limit should be applied, unknown filter ignored
      assert %Ecto.Query{limit: limit} = result
      assert limit != nil
    end

    test "uses empty handlers map by default" do
      query = base_query()

      result = FilterBuilder.apply_filters(query, limit: 5)

      assert %Ecto.Query{limit: limit} = result
      assert limit != nil
    end

    test "applies filters in order" do
      query = base_query()

      handlers = %{
        priority: fn q, value -> where(q, [t], t.priority > ^value) end
      }

      result =
        FilterBuilder.apply_filters(query, [priority: 5, limit: 10, offset: 2], handlers)

      assert %Ecto.Query{wheres: [_], limit: limit, offset: offset} = result
      assert limit != nil
      assert offset != nil
    end
  end

  describe "apply_single_filter/4" do
    test "uses custom handler when available" do
      query = base_query()
      handlers = %{status: fn q, value -> where(q, [t], t.status == ^value) end}

      result = FilterBuilder.apply_single_filter(query, :status, "active", handlers)

      assert %Ecto.Query{wheres: [_where]} = result
    end

    test "falls back to common filter when no custom handler" do
      query = base_query()

      result = FilterBuilder.apply_single_filter(query, :limit, 10, %{})

      assert %Ecto.Query{limit: limit} = result
      assert limit != nil
    end

    test "returns query unchanged for unknown filter" do
      query = base_query()

      result = FilterBuilder.apply_single_filter(query, :unknown, "value", %{})

      # Query should be unchanged
      assert result == query
    end

    test "custom handler takes precedence over common filter" do
      query = base_query()
      # Custom limit handler that does something different
      handlers = %{limit: fn q, _value -> where(q, [t], t.status == "limited") end}

      result = FilterBuilder.apply_single_filter(query, :limit, 10, handlers)

      # Should use custom handler, not common filter
      assert %Ecto.Query{wheres: [_where], limit: nil} = result
    end
  end

  describe "common_filter?/1" do
    test "returns true for :preload" do
      assert FilterBuilder.common_filter?(:preload)
    end

    test "returns true for :limit" do
      assert FilterBuilder.common_filter?(:limit)
    end

    test "returns true for :offset" do
      assert FilterBuilder.common_filter?(:offset)
    end

    test "returns true for :order_by" do
      assert FilterBuilder.common_filter?(:order_by)
    end

    test "returns false for custom filter keys" do
      refute FilterBuilder.common_filter?(:status)
      refute FilterBuilder.common_filter?(:category)
      refute FilterBuilder.common_filter?(:user_id)
      refute FilterBuilder.common_filter?(:search)
    end

    test "returns false for nil" do
      refute FilterBuilder.common_filter?(nil)
    end
  end

  describe "apply_common_filter/3 - preload" do
    test "returns query unchanged when preload is nil" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :preload, nil)

      assert result == query
    end

    test "returns query unchanged when preload is empty list" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :preload, [])

      assert result == query
    end

    test "applies preload for list of associations" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :preload, [:photos, :user])

      assert %Ecto.Query{preloads: preloads} = result
      assert preloads == [:photos, :user]
    end

    test "applies preload for single atom association" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :preload, :photos)

      assert %Ecto.Query{preloads: preloads} = result
      assert preloads == [:photos]
    end
  end

  describe "apply_common_filter/3 - limit" do
    test "returns query unchanged when limit is nil" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :limit, nil)

      assert result == query
    end

    test "applies limit for positive integer" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :limit, 10)

      assert %Ecto.Query{limit: limit} = result
      assert limit != nil
    end

    test "applies limit of 1" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :limit, 1)

      assert %Ecto.Query{limit: limit} = result
      assert limit != nil
    end

    test "returns query unchanged for zero limit" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :limit, 0)

      # Zero is not valid (guard requires limit > 0), falls through to fallback
      assert result == query
    end

    test "returns query unchanged for negative limit" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :limit, -5)

      assert result == query
    end

    test "returns query unchanged for non-integer limit" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :limit, "10")

      assert result == query
    end
  end

  describe "apply_common_filter/3 - offset" do
    test "returns query unchanged when offset is nil" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :offset, nil)

      assert result == query
    end

    test "applies offset for non-negative integer" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :offset, 5)

      assert %Ecto.Query{offset: offset} = result
      assert offset != nil
    end

    test "applies offset of 0" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :offset, 0)

      assert %Ecto.Query{offset: offset} = result
      assert offset != nil
    end

    test "returns query unchanged for negative offset" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :offset, -5)

      assert result == query
    end

    test "returns query unchanged for non-integer offset" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :offset, "10")

      assert result == query
    end
  end

  describe "apply_common_filter/3 - order_by" do
    test "returns query unchanged when order_by is nil" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :order_by, nil)

      assert result == query
    end

    test "returns query unchanged when order_by is empty list" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :order_by, [])

      assert result == query
    end

    test "applies order_by with desc specification" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :order_by, desc: :inserted_at)

      assert %Ecto.Query{order_bys: [_order]} = result
    end

    test "applies order_by with asc specification" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :order_by, asc: :name)

      assert %Ecto.Query{order_bys: [_order]} = result
    end

    test "applies order_by with multiple fields" do
      query = base_query()

      result =
        FilterBuilder.apply_common_filter(query, :order_by, desc: :priority, asc: :name)

      assert %Ecto.Query{order_bys: [_order]} = result
    end

    test "returns query unchanged for non-list order_by" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :order_by, :inserted_at)

      # Atom is not a list, falls through to fallback
      assert result == query
    end
  end

  describe "apply_common_filter/3 - fallback" do
    test "returns query unchanged for unknown common filter" do
      query = base_query()

      result = FilterBuilder.apply_common_filter(query, :unknown, "value")

      assert result == query
    end
  end

  describe "integration scenarios" do
    test "complex filtering with all common filters" do
      query = base_query()

      handlers = %{
        status: fn q, value -> where(q, [t], t.status == ^value) end,
        min_priority: fn q, value -> where(q, [t], t.priority >= ^value) end
      }

      opts = [
        status: "active",
        min_priority: 3,
        preload: [:photos],
        order_by: [desc: :inserted_at],
        limit: 20,
        offset: 10
      ]

      result = FilterBuilder.apply_filters(query, opts, handlers)

      assert %Ecto.Query{
               wheres: wheres,
               preloads: [:photos],
               order_bys: [_],
               limit: limit,
               offset: offset
             } = result

      assert length(wheres) == 2
      assert limit != nil
      assert offset != nil
    end

    test "pagination pattern" do
      query = base_query()
      page = 3
      per_page = 25

      opts = [
        order_by: [desc: :inserted_at],
        limit: per_page,
        offset: (page - 1) * per_page
      ]

      result = FilterBuilder.apply_filters(query, opts, %{})

      assert %Ecto.Query{order_bys: [_], limit: limit, offset: offset} = result
      assert limit != nil
      assert offset != nil
    end

    test "filtering with preloads only" do
      query = base_query()

      result = FilterBuilder.apply_filters(query, [preload: [:user, :photos]], %{})

      assert %Ecto.Query{preloads: [:user, :photos]} = result
    end
  end
end
