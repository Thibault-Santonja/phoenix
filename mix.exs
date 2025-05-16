defmodule Portfolio.MixProject do
  use Mix.Project

  def project do
    {tag, description} = git_version()

    [
      app: :portfolio,
      version: tag,
      description: "Thibault San · " <> description,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      deps: deps()
    ]
  end

  defp git_version() do
    # pulls version information from "nearest" git tag or sha hash-ish
    with {tag, _} <- System.cmd("git", ~w[describe --dirty --tags --always --first-parent]),
         version <-
           tag
           |> String.trim()
           |> String.split("-")
           |> List.first()
           |> String.replace_prefix("v", "")
           |> String.trim(),
         true <- String.match?(version, ~r/^\d*\.\d*\.\d*$/) do
      {version, tag}
    else
      _ ->
        {"0.1.0", "0.1.0-dev"}
    end
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Portfolio.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:tidewave, "~> 0.1", only: [:dev]},
      {:mishka_chelekom, "~> 0.0", only: [:dev]},
      {:live_debugger, "~> 0.2", only: [:dev]},
      {:ash_phoenix, "~> 2.0"},
      {:ash, "~> 3.0"},
      {:igniter, "~> 0.5", only: [:dev, :test]},
      {:phoenix, "~> 1.7.21"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:tailwind_formatter, "~> 0.4.2", only: [:dev, :test], runtime: false},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},
      # For CI
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind portfolio", "esbuild portfolio"],
      "assets.deploy": [
        "tailwind portfolio --minify",
        "esbuild portfolio --minify",
        "phx.digest"
      ]
    ]
  end
end
