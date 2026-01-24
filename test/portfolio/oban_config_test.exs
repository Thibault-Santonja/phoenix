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
      assert config[:queues][:image_processing] == 2
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

      assert limit == 2
    end
  end

  describe "Oban in test environment" do
    test "is configured for manual testing mode" do
      config = Application.get_env(:portfolio, Oban)

      assert config[:testing] == :manual
    end
  end

  describe "Oban Cron plugin configuration" do
    test "has Cron plugin configured" do
      config = Application.get_env(:portfolio, Oban)
      plugins = config[:plugins]

      assert Enum.any?(plugins, fn
               {Oban.Plugins.Cron, _opts} -> true
               _ -> false
             end),
             "Expected Oban.Plugins.Cron to be configured"
    end

    test "has SessionCleanerWorker scheduled in cron" do
      config = Application.get_env(:portfolio, Oban)
      plugins = config[:plugins]

      cron_config =
        Enum.find_value(plugins, fn
          {Oban.Plugins.Cron, opts} -> opts
          _ -> nil
        end)

      assert cron_config != nil, "Cron plugin not found in configuration"

      # Check that SessionCleanerWorker is in the crontab
      assert Enum.any?(cron_config[:crontab], fn {_schedule, worker} ->
               worker == Portfolio.Workers.SessionCleanerWorker
             end),
             "SessionCleanerWorker not found in cron schedule"
    end

    test "SessionCleanerWorker runs every 15 minutes" do
      config = Application.get_env(:portfolio, Oban)
      plugins = config[:plugins]

      cron_config =
        Enum.find_value(plugins, fn
          {Oban.Plugins.Cron, opts} -> opts
          _ -> nil
        end)

      # Find the SessionCleanerWorker entry
      session_cleaner_entry =
        Enum.find(cron_config[:crontab], fn {_schedule, worker} ->
          worker == Portfolio.Workers.SessionCleanerWorker
        end)

      assert session_cleaner_entry != nil

      {schedule, _worker} = session_cleaner_entry
      # Should run every 15 minutes: "*/15 * * * *"
      assert schedule == "*/15 * * * *",
             "Expected SessionCleanerWorker to run every 15 minutes, got: #{schedule}"
    end

    test "has MagicLinkCleanerWorker scheduled in cron" do
      config = Application.get_env(:portfolio, Oban)
      plugins = config[:plugins]

      cron_config =
        Enum.find_value(plugins, fn
          {Oban.Plugins.Cron, opts} -> opts
          _ -> nil
        end)

      assert cron_config != nil, "Cron plugin not found in configuration"

      # Check that MagicLinkCleanerWorker is in the crontab
      assert Enum.any?(cron_config[:crontab], fn {_schedule, worker} ->
               worker == Portfolio.Workers.MagicLinkCleanerWorker
             end),
             "MagicLinkCleanerWorker not found in cron schedule"
    end

    test "MagicLinkCleanerWorker runs every hour" do
      config = Application.get_env(:portfolio, Oban)
      plugins = config[:plugins]

      cron_config =
        Enum.find_value(plugins, fn
          {Oban.Plugins.Cron, opts} -> opts
          _ -> nil
        end)

      # Find the MagicLinkCleanerWorker entry
      magic_link_cleaner_entry =
        Enum.find(cron_config[:crontab], fn {_schedule, worker} ->
          worker == Portfolio.Workers.MagicLinkCleanerWorker
        end)

      assert magic_link_cleaner_entry != nil

      {schedule, _worker} = magic_link_cleaner_entry
      # Should run every hour at minute 0: "0 * * * *"
      assert schedule == "0 * * * *",
             "Expected MagicLinkCleanerWorker to run hourly, got: #{schedule}"
    end

    test "crontab has exactly the expected cleanup jobs" do
      config = Application.get_env(:portfolio, Oban)
      plugins = config[:plugins]

      cron_config =
        Enum.find_value(plugins, fn
          {Oban.Plugins.Cron, opts} -> opts
          _ -> nil
        end)

      crontab = cron_config[:crontab]

      # Extract workers from crontab
      workers = Enum.map(crontab, fn {_schedule, worker} -> worker end)

      # Should have both cleanup workers
      assert Portfolio.Workers.MagicLinkCleanerWorker in workers
      assert Portfolio.Workers.SessionCleanerWorker in workers

      # Should have exactly 2 cron jobs (no extra jobs added accidentally)
      assert length(crontab) == 2,
             "Expected exactly 2 cron jobs, found #{length(crontab)}"
    end

    test "cron schedules use valid cron syntax" do
      config = Application.get_env(:portfolio, Oban)
      plugins = config[:plugins]

      cron_config =
        Enum.find_value(plugins, fn
          {Oban.Plugins.Cron, opts} -> opts
          _ -> nil
        end)

      crontab = cron_config[:crontab]

      # Validate each cron expression
      for {schedule, worker} <- crontab do
        # Basic cron syntax: "minute hour day month weekday"
        parts = String.split(schedule, " ")
        assert length(parts) == 5, "Invalid cron syntax for #{worker}: #{schedule}"

        # Each part should be valid cron syntax: *, number, range, step, or list
        for part <- parts do
          assert part =~ ~r/^(\*|[\d]+|[\d]+-[\d]+|\*\/[\d]+|[\d,]+)$/,
                 "Invalid cron part '#{part}' in schedule '#{schedule}' for #{worker}"
        end
      end
    end
  end
end
