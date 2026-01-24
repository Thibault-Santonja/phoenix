defmodule Portfolio.CDNTest do
  use ExUnit.Case, async: true

  alias Portfolio.CDN

  describe "CDN behaviour" do
    test "defines invalidate/1 callback" do
      # Verify the behaviour callback is defined
      callbacks = CDN.behaviour_info(:callbacks)
      assert {:invalidate, 1} in callbacks
    end
  end

  defmodule MockCDN do
    @moduledoc false
    @behaviour Portfolio.CDN

    @impl true
    def invalidate(paths) when is_list(paths) do
      send(self(), {:cdn_invalidate, paths})
      :ok
    end
  end

  defmodule FailingCDN do
    @moduledoc false
    @behaviour Portfolio.CDN

    @impl true
    def invalidate(_paths) do
      {:error, :api_timeout}
    end
  end

  describe "CDN implementations" do
    test "MockCDN successfully invalidates paths" do
      paths = ["/albums/wedding", "/albums/portrait"]
      assert :ok = MockCDN.invalidate(paths)
      assert_received {:cdn_invalidate, ^paths}
    end

    test "FailingCDN returns error" do
      assert {:error, :api_timeout} = FailingCDN.invalidate(["/test"])
    end

    test "invalidate accepts empty list" do
      assert :ok = MockCDN.invalidate([])
      assert_received {:cdn_invalidate, []}
    end

    test "invalidate accepts single path" do
      assert :ok = MockCDN.invalidate(["/albums/single"])
      assert_received {:cdn_invalidate, ["/albums/single"]}
    end
  end
end
