defmodule PortfolioWeb.Plugs.CSPNonce do
  @moduledoc """
  Plug that generates and assigns a CSP nonce for script authorization.

  The nonce is stored in the connection assigns and session, making it
  available to both controllers and LiveViews for secure script loading.

  ## Usage

  Add to your pipeline after `:fetch_session`:

      plug PortfolioWeb.Plugs.CSPNonce

  Then in your root layout, use the nonce on script tags:

      <script nonce={assigns[:csp_nonce]} src={~p"/assets/app.js"}></script>

  ## Security

  The nonce is a cryptographically secure 128-bit random value encoded in base64.
  A new nonce is generated for each request, preventing replay attacks.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    # Get the nonce from the conn assigns (set by endpoint's put_secure_headers)
    # or generate a new one if not present
    nonce = conn.assigns[:csp_nonce] || generate_nonce()

    conn
    |> assign(:csp_nonce, nonce)
    |> put_session(:csp_nonce, nonce)
  end

  defp generate_nonce do
    :crypto.strong_rand_bytes(16) |> Base.encode64()
  end
end
