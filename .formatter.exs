[
  import_deps: [:ash_phoenix, :ash, :reactor, :phoenix],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter, TailwindFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"]
]
