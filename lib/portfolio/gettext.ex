defmodule Portfolio.Gettext do
  @moduledoc """
  Provides internationalization (i18n) support for the Portfolio application using the Gettext API.

  This module serves as the entry point for translations, allowing you to use functions like `gettext/1`, `ngettext/3`, and their domain-specific variants throughout the application.

  All translations are stored in `.po` files located under the `priv/gettext/` directory. To add or update translations, edit the appropriate `.po` files and compile them if needed.

  ## Examples

      import Portfolio.Gettext

      gettext("Hello, world!")
      ngettext("You have one message", "You have %{count} messages", count)

  See the [Gettext documentation](https://hexdocs.pm/gettext) for more details on usage and advanced features.
  """

  use Gettext.Backend, otp_app: :portfolio
end
