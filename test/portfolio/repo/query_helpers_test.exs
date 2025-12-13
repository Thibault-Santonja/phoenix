defmodule Portfolio.Repo.QueryHelpersTest do
  use Portfolio.DataCase, async: true

  import Ecto.Query
  import Portfolio.Repo.QueryHelpers

  alias Portfolio.Photography.Album

  describe "maybe_preload/2" do
    test "returns query unchanged when preloads is nil" do
      query = from(a in Album)
      assert maybe_preload(query, nil) == query
    end

    test "returns query unchanged when preloads is empty list" do
      query = from(a in Album)
      assert maybe_preload(query, []) == query
    end

    test "applies preload when given a list of associations" do
      query = from(a in Album)
      result = maybe_preload(query, [:photos])

      # Verify the query has preload applied
      assert %Ecto.Query{preloads: preloads} = result
      assert preloads == [:photos]
    end

    test "applies preload when given a single atom" do
      query = from(a in Album)
      result = maybe_preload(query, :photos)

      assert %Ecto.Query{preloads: preloads} = result
      assert preloads == [:photos]
    end

    test "handles multiple preloads" do
      query = from(a in Album)
      result = maybe_preload(query, [:photos, :cover_photo])

      assert %Ecto.Query{preloads: preloads} = result
      assert preloads == [:photos, :cover_photo]
    end
  end

  describe "wrap_result/1" do
    test "returns {:error, :not_found} for nil" do
      assert wrap_result(nil) == {:error, :not_found}
    end

    test "returns {:ok, value} for non-nil values" do
      assert wrap_result(%{id: 1}) == {:ok, %{id: 1}}
      assert wrap_result("string") == {:ok, "string"}
      assert wrap_result(123) == {:ok, 123}
      assert wrap_result([1, 2, 3]) == {:ok, [1, 2, 3]}
    end

    test "returns {:ok, value} for structs" do
      album = %Album{title: "Test"}
      assert wrap_result(album) == {:ok, album}
    end

    test "returns {:ok, false} for false value (not nil)" do
      assert wrap_result(false) == {:ok, false}
    end
  end

  describe "maybe_limit/2" do
    test "returns query unchanged when limit is nil" do
      query = from(a in Album)
      assert maybe_limit(query, nil) == query
    end

    test "applies limit when given positive integer" do
      query = from(a in Album)
      result = maybe_limit(query, 10)

      assert %Ecto.Query{limit: limit_expr} = result
      # Limit is stored as parameter reference in AST
      assert limit_expr.params == [{10, :integer}]
    end

    test "applies limit of 1" do
      query = from(a in Album)
      result = maybe_limit(query, 1)

      assert %Ecto.Query{limit: limit_expr} = result
      assert limit_expr.params == [{1, :integer}]
    end
  end

  describe "maybe_offset/2" do
    test "returns query unchanged when offset is nil" do
      query = from(a in Album)
      assert maybe_offset(query, nil) == query
    end

    test "applies offset when given non-negative integer" do
      query = from(a in Album)
      result = maybe_offset(query, 20)

      assert %Ecto.Query{offset: offset_expr} = result
      assert offset_expr.params == [{20, :integer}]
    end

    test "applies offset of 0" do
      query = from(a in Album)
      result = maybe_offset(query, 0)

      assert %Ecto.Query{offset: offset_expr} = result
      assert offset_expr.params == [{0, :integer}]
    end
  end

  describe "maybe_order_by/2" do
    test "returns query unchanged when order_by is nil" do
      query = from(a in Album)
      assert maybe_order_by(query, nil) == query
    end

    test "returns query unchanged when order_by is empty list" do
      query = from(a in Album)
      assert maybe_order_by(query, []) == query
    end

    test "applies order_by when given keyword list" do
      query = from(a in Album)
      result = maybe_order_by(query, desc: :inserted_at)

      assert %Ecto.Query{order_bys: order_bys} = result
      assert length(order_bys) == 1
    end

    test "applies multiple order_by clauses" do
      query = from(a in Album)
      result = maybe_order_by(query, desc: :inserted_at, asc: :title)

      assert %Ecto.Query{order_bys: order_bys} = result
      assert length(order_bys) == 1
    end
  end

  describe "integration with Repo" do
    test "helpers can be chained together" do
      query =
        from(a in Album)
        |> maybe_preload([:photos])
        |> maybe_limit(10)
        |> maybe_offset(5)
        |> maybe_order_by(desc: :inserted_at)

      assert query.preloads == [:photos]
      assert query.limit.params == [{10, :integer}]
      assert query.offset.params == [{5, :integer}]
      assert length(query.order_bys) == 1
    end

    test "nil values in chain are handled correctly" do
      query =
        from(a in Album)
        |> maybe_preload(nil)
        |> maybe_limit(nil)
        |> maybe_offset(nil)
        |> maybe_order_by(nil)

      # Should be unchanged from base query
      assert query.preloads == []
      assert query.limit == nil
      assert query.offset == nil
      assert query.order_bys == []
    end
  end
end
