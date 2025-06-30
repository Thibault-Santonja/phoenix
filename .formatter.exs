[
  import_deps: [
    :ash_oban,
    :oban,
    :ash_authentication_phoenix,
    :ash_authentication,
    :ash_sqlite,
    :ash_phoenix,
    :ash,
    :reactor,
    :phoenix
  ],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"]
]
