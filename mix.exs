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
      deps: deps(),
      compilers: Mix.compilers(),
      listeners: if(Mix.env() == :dev, do: [Phoenix.CodeReloader], else: []),
      test_coverage: [
        tool: ExCoveralls,
        threshold: 90,
        ignore_modules: [
          Portfolio.Workers.ExifExtractionWorker,
          Portfolio.Workers.ImageVariantWorker,
          Portfolio.Bootstrap.Worker,
          Portfolio.ImageProcessing.Services.ImageProcessingService
        ]
      ],
      # Reduce parallel compilation to avoid ETS race conditions
      elixirc_options: [warnings_as_errors: false],
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [
          :error_handling,
          :underspecs,
          :unmatched_returns
        ],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
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

  # CLI configuration for preferred environments
  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        precommit: :test
      ]
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
      {:sourceror, "~> 1.10", only: [:dev, :test]},
      {:tidewave, "~> 0.5", only: [:dev]},
      {:mishka_chelekom, "~> 0.0", only: [:dev]},
      {:live_debugger, "~> 0.5", only: [:dev]},
      {:finch, "~> 0.20"},
      {:oban, "~> 2.20"},
      {:igniter, "~> 0.7", only: [:dev, :test]},
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.8.3", override: true},
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.1"},
      {:floki, ">= 0.30.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.7"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.4", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.19"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.2"},
      {:bandit, "~> 1.8"},
      {:hammer, "~> 7.1"},
      {:fuse, "~> 2.5"},
      {:cachex, "~> 4.1"},
      {:exiftool, "~> 0.2"},
      {:vix, "~> 0.35"},
      # For CI, Documentation and Code Quality
      {:ex_doc, "~> 0.39", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.10", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:stream_data, "~> 1.2", only: [:dev, :test]},
      {:benchee, "~> 1.5", only: :dev},
      {:benchee_html, "~> 1.0", only: :dev}
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
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": [
        "cmd --cd assets npm install",
        "tailwind.install --if-missing",
        "esbuild.install --if-missing"
      ],
      "assets.build": ["tailwind portfolio", "esbuild portfolio"],
      "assets.deploy": [
        "tailwind portfolio --minify",
        "esbuild portfolio --minify",
        "phx.digest"
      ]
    ]
  end
end
