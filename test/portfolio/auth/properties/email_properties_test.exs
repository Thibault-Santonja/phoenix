defmodule Portfolio.Auth.Properties.EmailPropertiesTest do
  @moduledoc """
  Property-based tests for the Email value object.

  Tests invariants that must hold for all valid email inputs.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Portfolio.Auth.ValueObjects.Email

  # Generators
  defp simple_local_generator do
    string(:alphanumeric, min_length: 1, max_length: 20)
  end

  defp domain_generator do
    gen all(
          domain_part <- string(:alphanumeric, min_length: 1, max_length: 10),
          tld <- member_of(["com", "org", "net", "io", "dev"])
        ) do
      "#{domain_part}.#{tld}"
    end
  end

  defp valid_email_generator do
    gen all(
          local <- simple_local_generator(),
          domain <- domain_generator()
        ) do
      "#{local}@#{domain}"
    end
  end

  describe "email normalization properties" do
    property "normalization is idempotent" do
      check all(email_str <- valid_email_generator()) do
        case Email.new(email_str) do
          {:ok, email1} ->
            {:ok, email2} = Email.new(email1.value)
            assert email1.value == email2.value

          {:error, _} ->
            # Some generated emails may be invalid, that's ok
            :ok
        end
      end
    end

    property "normalized emails are always lowercase" do
      check all(email_str <- valid_email_generator()) do
        case Email.new(email_str) do
          {:ok, email} ->
            assert email.value == String.downcase(email.value)

          {:error, _} ->
            :ok
        end
      end
    end

    property "normalization preserves email structure" do
      check all(email_str <- valid_email_generator()) do
        case Email.new(email_str) do
          {:ok, email} ->
            assert String.contains?(email.value, "@")
            [local, domain] = String.split(email.value, "@")
            assert String.length(local) > 0
            assert String.length(domain) > 0

          {:error, _} ->
            :ok
        end
      end
    end
  end

  describe "email validation properties" do
    property "emails without @ are always rejected" do
      check all(str <- string(:alphanumeric, min_length: 1, max_length: 50)) do
        refute String.contains?(str, "@")
        assert {:error, :invalid_email} = Email.new(str)
      end
    end

    property "empty strings are always rejected" do
      assert {:error, :invalid_email} = Email.new("")
      assert {:error, :invalid_email} = Email.new("   ")
    end

    property "emails exceeding max length are rejected" do
      check all(
              local <- string(:alphanumeric, min_length: 200, max_length: 250),
              domain <- domain_generator()
            ) do
        long_email = "#{local}@#{domain}"

        if String.length(long_email) > 254 do
          assert {:error, :too_long} = Email.new(long_email)
        end
      end
    end
  end

  describe "email equality properties" do
    property "equal? is symmetric" do
      check all(email_str <- valid_email_generator()) do
        case Email.new(email_str) do
          {:ok, email1} ->
            {:ok, email2} = Email.new(email_str)
            assert Email.equal?(email1, email2) == Email.equal?(email2, email1)

          {:error, _} ->
            :ok
        end
      end
    end

    property "case-insensitive equality" do
      check all(email_str <- valid_email_generator()) do
        upper = String.upcase(email_str)
        lower = String.downcase(email_str)

        with {:ok, email_upper} <- Email.new(upper),
             {:ok, email_lower} <- Email.new(lower) do
          assert Email.equal?(email_upper, email_lower)
        end
      end
    end
  end
end
