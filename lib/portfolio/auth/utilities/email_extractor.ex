defmodule Portfolio.Auth.Utilities.EmailExtractor do
  @moduledoc """
  Utility module for extracting domain from email addresses.

  This module centralizes the domain extraction logic that was previously
  duplicated across multiple modules (MXValidator, DisposableEmailChecker,
  EmailNormalizer) to follow the DRY principle.

  ## Examples

      iex> EmailExtractor.extract_domain("user@example.com")
      "example.com"

      iex> EmailExtractor.extract_domain("USER@EXAMPLE.COM")
      "example.com"

      iex> EmailExtractor.extract_domain("invalid")
      nil

      iex> EmailExtractor.extract_domain(nil)
      nil
  """

  @doc """
  Extracts and normalizes the domain from an email address.

  Returns the domain part of the email address in lowercase,
  or nil if the email is invalid, nil, or empty.

  ## Parameters

  - `email` - The email address to extract the domain from

  ## Returns

  - The lowercase domain string if valid
  - `nil` if the email is nil, empty, or doesn't contain a valid domain

  ## Examples

      iex> Portfolio.Auth.Utilities.EmailExtractor.extract_domain("user@example.com")
      "example.com"

      iex> Portfolio.Auth.Utilities.EmailExtractor.extract_domain("user@SUB.EXAMPLE.COM")
      "sub.example.com"

      iex> Portfolio.Auth.Utilities.EmailExtractor.extract_domain("invalid-email")
      nil

      iex> Portfolio.Auth.Utilities.EmailExtractor.extract_domain("")
      nil

      iex> Portfolio.Auth.Utilities.EmailExtractor.extract_domain(nil)
      nil
  """
  @spec extract_domain(String.t() | nil) :: String.t() | nil
  def extract_domain(nil), do: nil
  def extract_domain(""), do: nil

  def extract_domain(email) when is_binary(email) do
    case String.split(email, "@") do
      [_local, domain] when byte_size(domain) > 0 ->
        String.downcase(domain)

      _ ->
        nil
    end
  end

  @doc """
  Checks if an email has a valid domain part.

  ## Examples

      iex> Portfolio.Auth.Utilities.EmailExtractor.valid_domain?("user@example.com")
      true

      iex> Portfolio.Auth.Utilities.EmailExtractor.valid_domain?("invalid")
      false
  """
  @spec valid_domain?(String.t() | nil) :: boolean()
  def valid_domain?(email), do: extract_domain(email) != nil
end
