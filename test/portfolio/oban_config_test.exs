defmodule Portfolio.ObanConfigTest do
  @moduledoc """
  Tests for Oban configuration.

  These tests verify that Oban is properly configured with the correct
  queues, plugins, and settings for background job processing.
  """
  use ExUnit.Case, async: true

  describe "Oban configuration" do
    test "has correct queues configured" do
      config = Application.get_env(:portfolio, Oban)

      assert config[:queues][:default] == 10
      assert config[:queues][:image_processing] == 3
    end

    test "has Pruner plugin configured" do
      config = Application.get_env(:portfolio, Oban)
      plugins = config[:plugins]

      assert Enum.any?(plugins, fn
               {Oban.Plugins.Pruner, opts} -> opts[:max_age] == 60 * 60 * 24 * 7
               _ -> false
             end)
    end

    test "uses correct repo" do
      config = Application.get_env(:portfolio, Oban)

      assert config[:repo] == Portfolio.Repo
    end

    test "uses Basic engine" do
      config = Application.get_env(:portfolio, Oban)

      assert config[:engine] == Oban.Engines.Basic
    end

    test "image_processing queue limit is configurable" do
      limit = Application.get_env(:portfolio, :oban_image_processing)[:limit]

      assert limit == 3
    end
  end

  describe "Oban in test environment" do
    test "is configured for manual testing mode" do
      config = Application.get_env(:portfolio, Oban)

      assert config[:testing] == :manual
    end
  end
end
