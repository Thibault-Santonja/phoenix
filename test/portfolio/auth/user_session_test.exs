defmodule Portfolio.Auth.UserSessionTest do
  @moduledoc """
  Tests pour le schéma UserSession.
  """

  use ExUnit.Case, async: true

  alias Portfolio.Auth.UserSession

  doctest UserSession

  describe "hash_token_value/1" do
    test "returns consistent hash for same input" do
      token = "test_token_123"
      hash1 = UserSession.hash_token_value(token)
      hash2 = UserSession.hash_token_value(token)

      assert hash1 == hash2
    end

    test "returns different hash for different input" do
      hash1 = UserSession.hash_token_value("token1")
      hash2 = UserSession.hash_token_value("token2")

      assert hash1 != hash2
    end

    test "returns 64 character hex string (SHA-256)" do
      hash = UserSession.hash_token_value("any_token")

      assert String.length(hash) == 64
      assert String.match?(hash, ~r/^[0-9a-f]+$/)
    end
  end
end
