defmodule Portfolio.Bootstrap.WorkerTest do
  @moduledoc """
  Tests for Portfolio.Bootstrap.Worker GenServer.

  Note: The Bootstrap.Worker ignores init in test environment,
  so we test the module's logic through unit tests of its behavior.
  """
  use Portfolio.DataCase, async: false

  alias Portfolio.Bootstrap.Worker

  describe "start_link/1" do
    test "returns :ignore in test environment" do
      # In test env, the worker should ignore startup
      assert :ignore = Worker.start_link([])
    end
  end

  describe "init/1" do
    test "returns :ignore in test environment" do
      # Direct call to init should also ignore in test
      assert :ignore = Worker.init([])
    end
  end

  describe "module structure" do
    test "defines start_link/1 function" do
      assert function_exported?(Worker, :start_link, 1)
    end

    test "is a GenServer" do
      # Verify it uses GenServer behavior
      behaviors = Worker.__info__(:attributes)[:behaviour] || []
      assert GenServer in behaviors
    end
  end
end
