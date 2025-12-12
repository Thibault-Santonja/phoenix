defmodule Mix.Tasks.Precommit do
  @moduledoc """
  Runs all pre-commit checks and displays a colored summary.

  This task mirrors the CI pipeline checks to ensure code quality before commit.

  ## Checks (in order)

  1. **compiler** - Compile with warnings as errors (all warnings)
  2. **formatter** - Check code formatting
  3. **credo** - Static code analysis (strict mode, all issues)
  4. **sobelow** - Phoenix security scanner (exit on issues)
  5. **deps_audit** - Check for vulnerable dependencies
  6. **hex_audit** - Check for retired Hex packages
  7. **deps_unlock** - Check for unused dependencies
  8. **gettext** - Check translations are up to date
  9. **dialyzer** - Type checking (required, skipped only if PLT not built)
  10. **ex_unit** - Run tests with coverage threshold
  11. **ex_doc** - Generate documentation

  ## Usage

      mix precommit           # Run all checks
      mix precommit --quick   # Skip dialyzer and docs (faster)
      mix precommit --no-test # Skip tests (for quick lint check)
  """

  use Mix.Task

  @shortdoc "Runs all pre-commit checks with colored summary"

  @checks [
    # Compilation with all warnings as errors
    {:compiler, "compile --warnings-as-errors --all-warnings", :required},
    # Code formatting
    {:formatter, "format --check-formatted", :required},
    # Static analysis - strict mode with all priority levels
    {:credo, "credo --strict --all", :required},
    # Security scanner - exit on any issue found
    {:sobelow, "sobelow --config --exit low", :required},
    # Vulnerability checks
    {:deps_audit, "deps.audit", :required},
    {:hex_audit, "hex.audit", :required},
    # Unused dependencies
    {:deps_unlock, "deps.unlock --check-unused", :required},
    # Translations must be up to date
    {:gettext, "gettext.extract --check-up-to-date", :required},
    # Type checking (required but can be skipped if PLT not built yet)
    {:dialyzer, "dialyzer", :dialyzer},
    # Tests with coverage (threshold enforced in coveralls.json)
    {:ex_unit, "coveralls", :required},
    # Documentation generation
    {:ex_doc, "docs", :optional}
  ]

  @impl Mix.Task
  def run(args) do
    quick_mode = "--quick" in args
    no_test_mode = "--no-test" in args

    IO.puts("")
    IO.puts(cyan("=> Running pre-commit checks (strict mode)"))
    IO.puts("")

    start_time = System.monotonic_time(:second)
    checks = filter_checks(@checks, quick_mode, no_test_mode)
    results = Enum.map(checks, &run_check/1)
    total_time = System.monotonic_time(:second) - start_time

    IO.puts("")
    print_summary(results, total_time)

    if all_passed?(results), do: :ok, else: Mix.raise("Pre-commit checks failed")
  end

  defp filter_checks(checks, quick_mode, no_test_mode) do
    checks
    |> maybe_reject(quick_mode, [:dialyzer, :ex_doc])
    |> maybe_reject(no_test_mode, [:ex_unit])
  end

  defp maybe_reject(checks, false, _names), do: checks

  defp maybe_reject(checks, true, names) do
    Enum.reject(checks, fn {name, _, _} -> name in names end)
  end

  defp run_check({name, command, importance}) do
    IO.puts(blue("=> ") <> "running " <> bright(to_string(name)))

    start_time = System.monotonic_time(:second)
    result = execute_check(name, command)
    duration = System.monotonic_time(:second) - start_time

    print_check_result(result, duration)
    {name, result, duration, importance}
  end

  defp execute_check(:dialyzer, _cmd), do: run_dialyzer()
  defp execute_check(:hex_audit, _cmd), do: run_hex_audit()
  defp execute_check(_name, command), do: run_mix_task(command)

  defp run_dialyzer do
    if File.exists?("priv/plts/dialyzer.plt") do
      run_mix_task("dialyzer")
    else
      IO.puts(yellow("  PLT not found - run 'mix dialyzer --plt' first"))
      :skipped
    end
  end

  defp run_hex_audit do
    # hex.audit is a hex task, not a mix task
    case System.cmd("mix", ["hex.audit"], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {_output, _} -> :error
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
    failed = count_failed(results)
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

  # All checks must pass (required) or be skipped (dialyzer without PLT)
  defp all_passed?(results) do
    Enum.all?(results, fn {_, status, _, importance} ->
      status == :ok or (status == :skipped and importance in [:optional, :dialyzer])
    end)
  end

  defp count_failed(results) do
    Enum.count(results, fn {_, status, _, importance} ->
      status == :error and importance != :optional
    end)
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
