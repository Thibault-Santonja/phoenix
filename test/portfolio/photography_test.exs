defmodule Portfolio.PhotographyTest do
  use ExUnit.Case, async: true

  alias Portfolio.Photography

  describe "module structure" do
    test "module exists and compiles" do
      assert Code.ensure_loaded?(Photography)
    end

    test "has complete moduledoc" do
      {:docs_v1, _, :elixir, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Photography)

      assert moduledoc =~ "Photography Bounded Context"
      assert moduledoc =~ "Ubiquitous Language"
      assert moduledoc =~ "Architecture"
      assert moduledoc =~ "Exemples"
    end
  end
end
