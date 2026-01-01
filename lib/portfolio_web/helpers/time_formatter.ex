defmodule PortfolioWeb.Helpers.TimeFormatter do
  @moduledoc """
  Helper functions for formatting time-related values.

  Provides human-readable "time ago" formatting with i18n support.
  """

  use Gettext, backend: PortfolioWeb.Gettext

  @doc """
  Formats a DateTime into a human-readable "time ago" string.

  Returns a localized string representing how long ago the datetime was.
  Uses the current Gettext locale for translations.

  ## Examples

      iex> now = DateTime.utc_now()
      iex> result = PortfolioWeb.Helpers.TimeFormatter.time_ago(now)
      iex> String.contains?(result, "0")
      true

      iex> past = DateTime.add(DateTime.utc_now(), -120, :second)
      iex> result = PortfolioWeb.Helpers.TimeFormatter.time_ago(past)
      iex> String.contains?(result, "2")
      true

  ## Time ranges

  - Less than 60 seconds: "X seconds"
  - Less than 1 hour: "X minutes"
  - Less than 1 day: "X hours"
  - Less than 30 days: "X days"
  - 30+ days: "X months"
  """
  @spec time_ago(DateTime.t()) :: String.t()
  def time_ago(datetime) when is_struct(datetime, DateTime) do
    diff_seconds = seconds_ago(datetime)
    format_duration(diff_seconds)
  end

  @doc """
  Calculates the number of seconds between now and a given datetime.

  ## Examples

      iex> now = DateTime.utc_now()
      iex> PortfolioWeb.Helpers.TimeFormatter.seconds_ago(now)
      0

      iex> past = DateTime.add(DateTime.utc_now(), -60, :second)
      iex> result = PortfolioWeb.Helpers.TimeFormatter.seconds_ago(past)
      iex> result >= 59 and result <= 61
      true
  """
  @spec seconds_ago(DateTime.t()) :: non_neg_integer()
  def seconds_ago(datetime) when is_struct(datetime, DateTime) do
    DateTime.diff(DateTime.utc_now(), datetime, :second) |> max(0)
  end

  @doc """
  Formats a duration in seconds into a human-readable string.

  The output is localized using Gettext. Examples show French locale.

  ## Examples

      iex> result = PortfolioWeb.Helpers.TimeFormatter.format_duration(30)
      iex> String.contains?(result, "30")
      true

      iex> result = PortfolioWeb.Helpers.TimeFormatter.format_duration(120)
      iex> String.contains?(result, "2")
      true

      iex> result = PortfolioWeb.Helpers.TimeFormatter.format_duration(7200)
      iex> String.contains?(result, "2")
      true

      iex> result = PortfolioWeb.Helpers.TimeFormatter.format_duration(172800)
      iex> String.contains?(result, "2")
      true

      iex> result = PortfolioWeb.Helpers.TimeFormatter.format_duration(5184000)
      iex> String.contains?(result, "2")
      true
  """
  @spec format_duration(non_neg_integer()) :: String.t()
  def format_duration(seconds) when is_integer(seconds) and seconds >= 0 do
    cond do
      seconds < 60 ->
        ngettext("time.second", "time.seconds", seconds, count: seconds)

      seconds < 3600 ->
        minutes = div(seconds, 60)
        ngettext("time.minute", "time.minutes", minutes, count: minutes)

      seconds < 86_400 ->
        hours = div(seconds, 3600)
        ngettext("time.hour", "time.hours", hours, count: hours)

      seconds < 2_592_000 ->
        days = div(seconds, 86_400)
        ngettext("time.day", "time.days", days, count: days)

      true ->
        months = div(seconds, 2_592_000)
        ngettext("time.month", "time.months", months, count: months)
    end
  end

  @doc """
  Converts seconds to the appropriate time unit tuple.

  Returns a tuple of `{value, unit}` where unit is the largest
  unit that fits the duration.

  ## Examples

      iex> PortfolioWeb.Helpers.TimeFormatter.to_time_unit(30)
      {30, :seconds}

      iex> PortfolioWeb.Helpers.TimeFormatter.to_time_unit(120)
      {2, :minutes}

      iex> PortfolioWeb.Helpers.TimeFormatter.to_time_unit(7200)
      {2, :hours}

      iex> PortfolioWeb.Helpers.TimeFormatter.to_time_unit(172800)
      {2, :days}

      iex> PortfolioWeb.Helpers.TimeFormatter.to_time_unit(5184000)
      {2, :months}
  """
  @spec to_time_unit(non_neg_integer()) ::
          {non_neg_integer(), :seconds | :minutes | :hours | :days | :months}
  def to_time_unit(seconds) when is_integer(seconds) and seconds >= 0 do
    cond do
      seconds < 60 -> {seconds, :seconds}
      seconds < 3600 -> {div(seconds, 60), :minutes}
      seconds < 86_400 -> {div(seconds, 3600), :hours}
      seconds < 2_592_000 -> {div(seconds, 86_400), :days}
      true -> {div(seconds, 2_592_000), :months}
    end
  end
end
