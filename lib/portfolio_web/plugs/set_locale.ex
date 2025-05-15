defmodule PortfolioWeb.Plugs.SetLocale do
  @moduledoc """
    Plug responsible for defining the user's locale for the web application.

    This plug checks whether a cookie named `"locale"` is present in the HTTP request. If this cookie contains a supported language (defined in `Gettext.known_locales/1`), this is used to set the active locale via `Gettext.put_locale/2`. The locale is also stored in the session (`:locale`).

    If no valid locale is found, the default value `"fr"` is used.
  """
  import Plug.Conn
  @behaviour Plug
  @supported_locales Gettext.known_locales(PortfolioWeb.Gettext)

  def init(opts), do: opts

  def call(%Plug.Conn{req_cookies: %{"locale" => locale}} = conn, _) when locale != nil do
    locale = String.slice(locale, 0..1)

    if locale in @supported_locales do
      Gettext.put_locale(PortfolioWeb.Gettext, locale)
      put_session(conn, :locale, locale)
    else
      conn
    end
  end

  def call(conn, _) do
    put_session(conn, :locale, "fr")
  end
end
