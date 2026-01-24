defmodule Portfolio.Utils.TimeFormatter do
  @moduledoc """
  Utility module for formatting time durations in French.

  This module provides functions to convert time durations (in seconds)
  to human-readable French strings, commonly used for "time ago" displays.
  """

  @doc """
  Formats a duration in seconds as a French "time ago" string.

  Returns a human-readable string representing the time duration in French,
  using appropriate units (seconds, minutes, hours, days, months, years).

  ## Examples

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(0)
      "0 seconde"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(1)
      "1 seconde"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(10)
      "10 secondes"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(45)
      "45 secondes"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(60)
      "1 minute"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(90)
      "1 minute"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(120)
      "2 minutes"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(300)
      "5 minutes"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(3600)
      "1 heure"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(7200)
      "2 heures"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(86400)
      "1 jour"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(172800)
      "2 jours"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(604800)
      "7 jours"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(2592000)
      "1 mois"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(5184000)
      "2 mois"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(31536000)
      "1 an"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(63072000)
      "2 ans"

      iex> Portfolio.Utils.TimeFormatter.time_ago_fr(-10)
      "0 seconde"

  """
  @spec time_ago_fr(integer()) :: String.t()
  def time_ago_fr(seconds) when is_integer(seconds) and seconds < 0, do: "0 seconde"

  def time_ago_fr(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 ->
        format_unit(seconds, "seconde", "secondes")

      seconds < 3600 ->
        minutes = div(seconds, 60)
        format_unit(minutes, "minute", "minutes")

      seconds < 86_400 ->
        hours = div(seconds, 3600)
        format_unit(hours, "heure", "heures")

      seconds < 2_592_000 ->
        days = div(seconds, 86_400)
        format_unit(days, "jour", "jours")

      seconds < 31_536_000 ->
        months = div(seconds, 2_592_000)
        format_unit(months, "mois", "mois")

      true ->
        years = div(seconds, 31_536_000)
        format_unit(years, "an", "ans")
    end
  end

  @doc """
  Formats a DateTime as a French "time ago" string relative to now.

  ## Examples

      iex> now = DateTime.utc_now()
      iex> past = DateTime.add(now, -120, :second)
      iex> Portfolio.Utils.TimeFormatter.time_ago_from_datetime(past, now)
      "2 minutes"

  """
  @spec time_ago_from_datetime(DateTime.t(), DateTime.t()) :: String.t()
  def time_ago_from_datetime(
        %DateTime{} = datetime,
        %DateTime{} = reference \\ DateTime.utc_now()
      ) do
    diff = DateTime.diff(reference, datetime, :second)
    time_ago_fr(max(0, diff))
  end

  @doc """
  Formats a duration in seconds as a compact French string.

  Uses abbreviated units for compact display.

  ## Examples

      iex> Portfolio.Utils.TimeFormatter.duration_compact_fr(90)
      "1m 30s"

      iex> Portfolio.Utils.TimeFormatter.duration_compact_fr(3661)
      "1h 1m 1s"

      iex> Portfolio.Utils.TimeFormatter.duration_compact_fr(86400)
      "1j 0h 0m"

  """
  @spec duration_compact_fr(non_neg_integer()) :: String.t()
  def duration_compact_fr(seconds) when is_integer(seconds) and seconds >= 0 do
    cond do
      seconds < 60 ->
        "#{seconds}s"

      seconds < 3600 ->
        minutes = div(seconds, 60)
        secs = rem(seconds, 60)
        "#{minutes}m #{secs}s"

      seconds < 86_400 ->
        hours = div(seconds, 3600)
        minutes = div(rem(seconds, 3600), 60)
        secs = rem(seconds, 60)
        "#{hours}h #{minutes}m #{secs}s"

      true ->
        days = div(seconds, 86_400)
        hours = div(rem(seconds, 86_400), 3600)
        minutes = div(rem(seconds, 3600), 60)
        "#{days}j #{hours}h #{minutes}m"
    end
  end

  # Private helpers

  defp format_unit(0, singular, _plural), do: "0 #{singular}"
  defp format_unit(1, singular, _plural), do: "1 #{singular}"
  defp format_unit(n, _singular, plural), do: "#{n} #{plural}"
end
