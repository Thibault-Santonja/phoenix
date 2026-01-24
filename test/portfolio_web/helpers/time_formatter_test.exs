defmodule PortfolioWeb.Helpers.TimeFormatterTest do
  use ExUnit.Case, async: true

  alias PortfolioWeb.Helpers.TimeFormatter

  doctest PortfolioWeb.Helpers.TimeFormatter

  describe "format_duration/1" do
    test "formats seconds (< 60)" do
      assert TimeFormatter.format_duration(0) =~ "0"
      assert TimeFormatter.format_duration(1) =~ "1"
      assert TimeFormatter.format_duration(30) =~ "30"
      assert TimeFormatter.format_duration(59) =~ "59"
    end

    test "formats minutes (60 - 3599)" do
      assert TimeFormatter.format_duration(60) =~ "1"
      assert TimeFormatter.format_duration(120) =~ "2"
      assert TimeFormatter.format_duration(3599) =~ "59"
    end

    test "formats hours (3600 - 86399)" do
      assert TimeFormatter.format_duration(3600) =~ "1"
      assert TimeFormatter.format_duration(7200) =~ "2"
      assert TimeFormatter.format_duration(86_399) =~ "23"
    end

    test "formats days (86400 - 2591999)" do
      assert TimeFormatter.format_duration(86_400) =~ "1"
      assert TimeFormatter.format_duration(172_800) =~ "2"
      assert TimeFormatter.format_duration(2_591_999) =~ "29"
    end

    test "formats months (>= 2592000)" do
      assert TimeFormatter.format_duration(2_592_000) =~ "1"
      assert TimeFormatter.format_duration(5_184_000) =~ "2"
      assert TimeFormatter.format_duration(31_104_000) =~ "12"
    end
  end

  describe "to_time_unit/1" do
    test "returns seconds for < 60" do
      assert {0, :seconds} = TimeFormatter.to_time_unit(0)
      assert {30, :seconds} = TimeFormatter.to_time_unit(30)
      assert {59, :seconds} = TimeFormatter.to_time_unit(59)
    end

    test "returns minutes for 60 - 3599" do
      assert {1, :minutes} = TimeFormatter.to_time_unit(60)
      assert {2, :minutes} = TimeFormatter.to_time_unit(120)
      assert {59, :minutes} = TimeFormatter.to_time_unit(3599)
    end

    test "returns hours for 3600 - 86399" do
      assert {1, :hours} = TimeFormatter.to_time_unit(3600)
      assert {2, :hours} = TimeFormatter.to_time_unit(7200)
      assert {23, :hours} = TimeFormatter.to_time_unit(86_399)
    end

    test "returns days for 86400 - 2591999" do
      assert {1, :days} = TimeFormatter.to_time_unit(86_400)
      assert {2, :days} = TimeFormatter.to_time_unit(172_800)
      assert {29, :days} = TimeFormatter.to_time_unit(2_591_999)
    end

    test "returns months for >= 2592000" do
      assert {1, :months} = TimeFormatter.to_time_unit(2_592_000)
      assert {2, :months} = TimeFormatter.to_time_unit(5_184_000)
      assert {12, :months} = TimeFormatter.to_time_unit(31_104_000)
    end
  end

  describe "seconds_ago/1" do
    test "returns 0 for current time" do
      now = DateTime.utc_now()
      assert TimeFormatter.seconds_ago(now) == 0
    end

    test "returns positive value for past datetime" do
      past = DateTime.add(DateTime.utc_now(), -60, :second)
      result = TimeFormatter.seconds_ago(past)
      # Allow 1 second tolerance for test execution time
      assert result >= 59 and result <= 61
    end

    test "returns 0 for future datetime (clamped)" do
      future = DateTime.add(DateTime.utc_now(), 60, :second)
      # seconds_ago clamps negative values to 0
      assert TimeFormatter.seconds_ago(future) == 0
    end
  end

  describe "time_ago/1" do
    test "formats recent datetime as seconds" do
      recent = DateTime.add(DateTime.utc_now(), -10, :second)
      result = TimeFormatter.time_ago(recent)
      assert is_binary(result)
      assert String.contains?(result, "1") or String.contains?(result, "0")
    end

    test "formats datetime from minutes ago" do
      minutes_ago = DateTime.add(DateTime.utc_now(), -300, :second)
      result = TimeFormatter.time_ago(minutes_ago)
      assert is_binary(result)
      assert String.contains?(result, "5") or String.contains?(result, "4")
    end

    test "formats datetime from hours ago" do
      hours_ago = DateTime.add(DateTime.utc_now(), -7200, :second)
      result = TimeFormatter.time_ago(hours_ago)
      assert is_binary(result)
      assert String.contains?(result, "2")
    end

    test "formats datetime from days ago" do
      days_ago = DateTime.add(DateTime.utc_now(), -172_800, :second)
      result = TimeFormatter.time_ago(days_ago)
      assert is_binary(result)
      assert String.contains?(result, "2")
    end

    test "formats datetime from months ago" do
      months_ago = DateTime.add(DateTime.utc_now(), -5_184_000, :second)
      result = TimeFormatter.time_ago(months_ago)
      assert is_binary(result)
      assert String.contains?(result, "2")
    end
  end

  describe "edge cases" do
    test "handles boundary between seconds and minutes" do
      assert {59, :seconds} = TimeFormatter.to_time_unit(59)
      assert {1, :minutes} = TimeFormatter.to_time_unit(60)
    end

    test "handles boundary between minutes and hours" do
      assert {59, :minutes} = TimeFormatter.to_time_unit(3599)
      assert {1, :hours} = TimeFormatter.to_time_unit(3600)
    end

    test "handles boundary between hours and days" do
      assert {23, :hours} = TimeFormatter.to_time_unit(86_399)
      assert {1, :days} = TimeFormatter.to_time_unit(86_400)
    end

    test "handles boundary between days and months" do
      assert {29, :days} = TimeFormatter.to_time_unit(2_591_999)
      assert {1, :months} = TimeFormatter.to_time_unit(2_592_000)
    end

    test "handles very large values" do
      # 10 years in seconds
      ten_years = 315_360_000
      {months, :months} = TimeFormatter.to_time_unit(ten_years)
      assert months == 121
    end
  end
end
