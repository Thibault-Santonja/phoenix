defmodule Mix.Tasks.Precommit do
  @moduledoc """
  Runs all pre-commit checks and displays a colored summary.

  ## Checks (in order)

  1. **compiler** - Compile with warnings as errors
  2. **formatter** - Check code formatting
  3. **credo** - Static code analysis (strict mode)
  4. **sobelow** - Phoenix security scanner
  5. **deps_audit** - Check for vulnerable dependencies
  6. **deps_unlock** - Check for unused dependencies
  7. **dialyzer** - Type checking (optional, skipped if PLT not built)
  8. **ex_unit** - Run tests
  9. **ex_doc** - Generate documentation

  ## Usage

      mix precommit           # Run all checks
      mix precommit --quick   # Skip dialyzer (faster)
  """

  use Mix.Task

  @shortdoc "Runs all pre-commit checks with colored summary"

  @checks [
    {:compiler, "compile --warnings-as-errors", :required},
    {:formatter, "format --check-formatted", :required},
    {:credo, "credo --strict", :required},
    {:sobelow, "sobelow --config", :required},
    {:deps_audit, "deps.audit", :required},
    {:deps_unlock, "deps.unlock --check-unused", :optional},
    {:dialyzer, "dialyzer", :optional},
    {:ex_unit, "test", :required},
    {:ex_doc, "docs", :required}
  ]

  @impl Mix.Task
  def run(args) do
    quick_mode = "--quick" in args

    IO.puts("")
    IO.puts(cyan("=> Running pre-commit checks"))
    IO.puts("")

    start_time = System.monotonic_time(:second)
    checks = filter_checks(@checks, quick_mode)
    results = Enum.map(checks, &run_check/1)
    total_time = System.monotonic_time(:second) - start_time

    IO.puts("")
    print_summary(results, total_time)

    if all_required_passed?(results), do: :ok, else: Mix.raise("Pre-commit checks failed")
  end

  defp filter_checks(checks, true), do: Enum.reject(checks, fn {n, _, _} -> n == :dialyzer end)
  defp filter_checks(checks, false), do: checks

  defp run_check({name, command, importance}) do
    IO.puts(blue("=> ") <> "running " <> bright(to_string(name)))

    start_time = System.monotonic_time(:second)
    result = execute_check(name, command)
    duration = System.monotonic_time(:second) - start_time

    print_check_result(result, duration)
    {name, result, duration, importance}
  end

  defp execute_check(:dialyzer, _cmd), do: run_dialyzer()
  defp execute_check(_name, command), do: run_mix_task(command)

  defp run_dialyzer do
    if File.exists?("priv/plts/dialyzer.plt") do
      run_mix_task("dialyzer")
    else
      :skipped
    end
  end

  defp run_mix_task(command) do
    Mix.Task.rerun("do", String.split(command))
    :ok
  rescue
    Mix.Error -> :error
  catch
    :exit, _ -> :error
  end

  defp print_check_result(result, duration) do
    {text, color} = status_display(result)
    IO.puts(blue("=> ") <> color.(text) <> " in " <> yellow(format_duration(duration)))
    IO.puts("")
  end

  defp status_display(:ok), do: {"done", &green/1}
  defp status_display(:skipped), do: {"skipped", &yellow/1}
  defp status_display(:error), do: {"failed", &red/1}

  defp print_summary(results, total_time) do
    IO.puts(cyan("=> ") <> "finished in " <> bright(format_duration(total_time)))
    IO.puts("")

    Enum.each(results, &print_result_line/1)

    IO.puts("")
    print_final_status(results, total_time)
    IO.puts("")
  end

  defp print_result_line({name, status, duration, _importance}) do
    {symbol, color, text} = result_display(status)

    IO.puts(
      "  " <>
        color.(symbol) <>
        " " <>
        magenta(String.pad_trailing(to_string(name), 14)) <>
        " " <>
        color.(String.pad_trailing(text, 8)) <>
        "in " <> yellow(format_duration(duration))
    )
  end

  defp result_display(:ok), do: {"V", &green/1, "success"}
  defp result_display(:error), do: {"X", &red/1, "failed"}
  defp result_display(:skipped), do: {"-", &yellow/1, "skipped"}

  defp print_final_status(results, total_time) do
    failed = count_failed_required(results)
    skipped = count_skipped(results)

    cond do
      failed > 0 ->
        IO.puts(red(bright("failed")) <> " (#{failed} required check(s) failed)")

      skipped > 0 ->
        IO.puts(
          green(bright("ok")) <>
            " #{format_duration(total_time)}" <> yellow(" (#{skipped} skipped)")
        )

      true ->
        IO.puts(green(bright("ok")) <> " #{format_duration(total_time)}")
    end
  end

  defp all_required_passed?(results) do
    results
    |> Enum.filter(fn {_, _, _, imp} -> imp == :required end)
    |> Enum.all?(fn {_, status, _, _} -> status == :ok end)
  end

  defp count_failed_required(results) do
    Enum.count(results, fn {_, s, _, i} -> s == :error and i == :required end)
  end

  defp count_skipped(results), do: Enum.count(results, fn {_, s, _, _} -> s == :skipped end)

  defp format_duration(s) when s < 60, do: "0:#{String.pad_leading(to_string(s), 2, "0")}"

  defp format_duration(s),
    do: "#{div(s, 60)}:#{String.pad_leading(to_string(rem(s, 60)), 2, "0")}"

  # ANSI color helpers
  defp cyan(t), do: IO.ANSI.cyan() <> t <> IO.ANSI.reset()
  defp blue(t), do: IO.ANSI.blue() <> t <> IO.ANSI.reset()
  defp green(t), do: IO.ANSI.green() <> t <> IO.ANSI.reset()
  defp red(t), do: IO.ANSI.red() <> t <> IO.ANSI.reset()
  defp yellow(t), do: IO.ANSI.yellow() <> t <> IO.ANSI.reset()
  defp magenta(t), do: IO.ANSI.magenta() <> t <> IO.ANSI.reset()
  defp bright(t), do: IO.ANSI.bright() <> t <> IO.ANSI.reset()
end
