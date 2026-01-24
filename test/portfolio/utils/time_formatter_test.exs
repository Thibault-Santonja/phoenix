defmodule Portfolio.Utils.TimeFormatterTest do
  @moduledoc """
  Tests for Portfolio.Utils.TimeFormatter module.

  Covers:
  - time_ago_fr/1 for various time units
  - time_ago_from_datetime/2 for DateTime-based calculations
  - duration_compact_fr/1 for compact duration formatting
  - Edge cases and boundary conditions
  """
  use ExUnit.Case, async: true

  alias Portfolio.Utils.TimeFormatter

  # Run doctests
  doctest Portfolio.Utils.TimeFormatter

  describe "time_ago_fr/1 - seconds" do
    test "returns '0 seconde' for zero seconds" do
      assert TimeFormatter.time_ago_fr(0) == "0 seconde"
    end

    test "returns '1 seconde' for one second" do
      assert TimeFormatter.time_ago_fr(1) == "1 seconde"
    end

    test "returns plural for multiple seconds" do
      assert TimeFormatter.time_ago_fr(2) == "2 secondes"
      assert TimeFormatter.time_ago_fr(30) == "30 secondes"
      assert TimeFormatter.time_ago_fr(59) == "59 secondes"
    end

    test "handles negative values by returning '0 seconde'" do
      assert TimeFormatter.time_ago_fr(-1) == "0 seconde"
      assert TimeFormatter.time_ago_fr(-100) == "0 seconde"
      assert TimeFormatter.time_ago_fr(-999_999) == "0 seconde"
    end
  end

  describe "time_ago_fr/1 - minutes" do
    test "returns '1 minute' for 60 seconds" do
      assert TimeFormatter.time_ago_fr(60) == "1 minute"
    end

    test "returns '1 minute' for values between 60 and 119 seconds" do
      assert TimeFormatter.time_ago_fr(61) == "1 minute"
      assert TimeFormatter.time_ago_fr(90) == "1 minute"
      assert TimeFormatter.time_ago_fr(119) == "1 minute"
    end

    test "returns plural for multiple minutes" do
      assert TimeFormatter.time_ago_fr(120) == "2 minutes"
      assert TimeFormatter.time_ago_fr(300) == "5 minutes"
      assert TimeFormatter.time_ago_fr(1800) == "30 minutes"
      assert TimeFormatter.time_ago_fr(3540) == "59 minutes"
    end
  end

  describe "time_ago_fr/1 - hours" do
    test "returns '1 heure' for 3600 seconds" do
      assert TimeFormatter.time_ago_fr(3600) == "1 heure"
    end

    test "returns '1 heure' for values between 3600 and 7199 seconds" do
      assert TimeFormatter.time_ago_fr(3601) == "1 heure"
      assert TimeFormatter.time_ago_fr(5400) == "1 heure"
      assert TimeFormatter.time_ago_fr(7199) == "1 heure"
    end

    test "returns plural for multiple hours" do
      assert TimeFormatter.time_ago_fr(7200) == "2 heures"
      assert TimeFormatter.time_ago_fr(36_000) == "10 heures"
      assert TimeFormatter.time_ago_fr(82_800) == "23 heures"
    end
  end

  describe "time_ago_fr/1 - days" do
    test "returns '1 jour' for 86400 seconds (1 day)" do
      assert TimeFormatter.time_ago_fr(86_400) == "1 jour"
    end

    test "returns plural for multiple days" do
      assert TimeFormatter.time_ago_fr(172_800) == "2 jours"
      assert TimeFormatter.time_ago_fr(604_800) == "7 jours"
      assert TimeFormatter.time_ago_fr(1_209_600) == "14 jours"
      assert TimeFormatter.time_ago_fr(2_505_600) == "29 jours"
    end
  end

  describe "time_ago_fr/1 - months" do
    test "returns '1 mois' for 2592000 seconds (30 days)" do
      assert TimeFormatter.time_ago_fr(2_592_000) == "1 mois"
    end

    test "returns plural for multiple months (same word in French)" do
      assert TimeFormatter.time_ago_fr(5_184_000) == "2 mois"
      assert TimeFormatter.time_ago_fr(15_552_000) == "6 mois"
      assert TimeFormatter.time_ago_fr(28_512_000) == "11 mois"
    end
  end

  describe "time_ago_fr/1 - years" do
    test "returns '1 an' for 31536000 seconds (365 days)" do
      assert TimeFormatter.time_ago_fr(31_536_000) == "1 an"
    end

    test "returns plural for multiple years" do
      assert TimeFormatter.time_ago_fr(63_072_000) == "2 ans"
      assert TimeFormatter.time_ago_fr(157_680_000) == "5 ans"
      assert TimeFormatter.time_ago_fr(315_360_000) == "10 ans"
    end
  end

  describe "time_ago_fr/1 - boundary conditions" do
    test "boundary between seconds and minutes" do
      assert TimeFormatter.time_ago_fr(59) == "59 secondes"
      assert TimeFormatter.time_ago_fr(60) == "1 minute"
    end

    test "boundary between minutes and hours" do
      assert TimeFormatter.time_ago_fr(3599) == "59 minutes"
      assert TimeFormatter.time_ago_fr(3600) == "1 heure"
    end

    test "boundary between hours and days" do
      assert TimeFormatter.time_ago_fr(86_399) == "23 heures"
      assert TimeFormatter.time_ago_fr(86_400) == "1 jour"
    end

    test "boundary between days and months" do
      assert TimeFormatter.time_ago_fr(2_591_999) == "29 jours"
      assert TimeFormatter.time_ago_fr(2_592_000) == "1 mois"
    end

    test "boundary between months and years" do
      assert TimeFormatter.time_ago_fr(31_535_999) == "12 mois"
      assert TimeFormatter.time_ago_fr(31_536_000) == "1 an"
    end
  end

  describe "time_ago_from_datetime/2" do
    test "calculates difference from reference time" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -120, :second)

      assert TimeFormatter.time_ago_from_datetime(past, now) == "2 minutes"
    end

    test "handles datetime in the past by hours" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -7200, :second)

      assert TimeFormatter.time_ago_from_datetime(past, now) == "2 heures"
    end

    test "handles datetime in the past by days" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -172_800, :second)

      assert TimeFormatter.time_ago_from_datetime(past, now) == "2 jours"
    end

    test "handles zero difference" do
      now = DateTime.utc_now()

      assert TimeFormatter.time_ago_from_datetime(now, now) == "0 seconde"
    end

    test "handles future datetime (negative diff) by returning '0 seconde'" do
      now = DateTime.utc_now()
      future = DateTime.add(now, 3600, :second)

      assert TimeFormatter.time_ago_from_datetime(future, now) == "0 seconde"
    end

    test "works with different timezones" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -300, :second)

      assert TimeFormatter.time_ago_from_datetime(past, now) == "5 minutes"
    end
  end

  describe "duration_compact_fr/1 - seconds only" do
    test "formats seconds correctly" do
      assert TimeFormatter.duration_compact_fr(0) == "0s"
      assert TimeFormatter.duration_compact_fr(1) == "1s"
      assert TimeFormatter.duration_compact_fr(30) == "30s"
      assert TimeFormatter.duration_compact_fr(59) == "59s"
    end
  end

  describe "duration_compact_fr/1 - minutes and seconds" do
    test "formats minutes and seconds correctly" do
      assert TimeFormatter.duration_compact_fr(60) == "1m 0s"
      assert TimeFormatter.duration_compact_fr(61) == "1m 1s"
      assert TimeFormatter.duration_compact_fr(90) == "1m 30s"
      assert TimeFormatter.duration_compact_fr(125) == "2m 5s"
      assert TimeFormatter.duration_compact_fr(3599) == "59m 59s"
    end
  end

  describe "duration_compact_fr/1 - hours, minutes and seconds" do
    test "formats hours, minutes and seconds correctly" do
      assert TimeFormatter.duration_compact_fr(3600) == "1h 0m 0s"
      assert TimeFormatter.duration_compact_fr(3661) == "1h 1m 1s"
      assert TimeFormatter.duration_compact_fr(7325) == "2h 2m 5s"
      assert TimeFormatter.duration_compact_fr(45_296) == "12h 34m 56s"
    end

    test "handles full day minus one second" do
      assert TimeFormatter.duration_compact_fr(86_399) == "23h 59m 59s"
    end
  end

  describe "duration_compact_fr/1 - days, hours and minutes" do
    test "formats days, hours and minutes correctly" do
      assert TimeFormatter.duration_compact_fr(86_400) == "1j 0h 0m"
      assert TimeFormatter.duration_compact_fr(90_000) == "1j 1h 0m"
      assert TimeFormatter.duration_compact_fr(172_800) == "2j 0h 0m"
      assert TimeFormatter.duration_compact_fr(180_000) == "2j 2h 0m"
    end

    test "handles multiple days" do
      assert TimeFormatter.duration_compact_fr(604_800) == "7j 0h 0m"
      assert TimeFormatter.duration_compact_fr(694_861) == "8j 1h 1m"
    end

    test "handles large values" do
      # 30 days
      assert TimeFormatter.duration_compact_fr(2_592_000) == "30j 0h 0m"
      # 365 days
      assert TimeFormatter.duration_compact_fr(31_536_000) == "365j 0h 0m"
    end
  end

  describe "duration_compact_fr/1 - edge cases" do
    test "boundary between seconds and minutes" do
      assert TimeFormatter.duration_compact_fr(59) == "59s"
      assert TimeFormatter.duration_compact_fr(60) == "1m 0s"
    end

    test "boundary between minutes and hours" do
      assert TimeFormatter.duration_compact_fr(3599) == "59m 59s"
      assert TimeFormatter.duration_compact_fr(3600) == "1h 0m 0s"
    end

    test "boundary between hours and days" do
      assert TimeFormatter.duration_compact_fr(86_399) == "23h 59m 59s"
      assert TimeFormatter.duration_compact_fr(86_400) == "1j 0h 0m"
    end
  end
end
