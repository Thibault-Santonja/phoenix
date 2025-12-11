defmodule PortfolioWeb.Plugs.CSPNonceTest do
  use PortfolioWeb.ConnCase, async: true

  alias PortfolioWeb.Plugs.CSPNonce

  defp init_session(conn) do
    conn
    |> Plug.Test.init_test_session(%{})
  end

  describe "init/1" do
    test "returns options unchanged" do
      opts = [some: :option]
      assert CSPNonce.init(opts) == opts
    end

    test "handles empty options" do
      assert CSPNonce.init([]) == []
    end
  end

  describe "call/2" do
    test "generates a nonce and assigns it to conn", %{conn: conn} do
      conn =
        conn
        |> init_session()
        |> CSPNonce.call([])

      assert conn.assigns[:csp_nonce]
      assert is_binary(conn.assigns[:csp_nonce])
    end

    test "nonce is base64 encoded", %{conn: conn} do
      conn =
        conn
        |> init_session()
        |> CSPNonce.call([])

      nonce = conn.assigns[:csp_nonce]

      # Should be valid base64
      assert {:ok, _decoded} = Base.decode64(nonce)
    end

    test "nonce is stored in session", %{conn: conn} do
      conn =
        conn
        |> init_session()
        |> CSPNonce.call([])

      assert get_session(conn, :csp_nonce) == conn.assigns[:csp_nonce]
    end

    test "uses existing nonce from assigns if present", %{conn: conn} do
      existing_nonce = "existing-nonce-value"

      conn =
        conn
        |> init_session()
        |> assign(:csp_nonce, existing_nonce)
        |> CSPNonce.call([])

      assert conn.assigns[:csp_nonce] == existing_nonce
    end

    test "generates different nonces for different requests", %{conn: conn} do
      conn1 =
        conn
        |> init_session()
        |> CSPNonce.call([])

      conn2 =
        build_conn()
        |> init_session()
        |> CSPNonce.call([])

      refute conn1.assigns[:csp_nonce] == conn2.assigns[:csp_nonce]
    end

    test "nonce has sufficient entropy (16 bytes = 128 bits)", %{conn: conn} do
      conn =
        conn
        |> init_session()
        |> CSPNonce.call([])

      nonce = conn.assigns[:csp_nonce]

      {:ok, decoded} = Base.decode64(nonce)
      # 16 bytes = 128 bits of entropy
      assert byte_size(decoded) == 16
    end
  end
end
