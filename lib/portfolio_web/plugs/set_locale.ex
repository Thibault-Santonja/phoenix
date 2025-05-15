defmodule PortfolioWeb.Plugs.SetLocale do
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
