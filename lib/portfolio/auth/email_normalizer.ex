defmodule Portfolio.Auth.EmailNormalizer do
  @moduledoc """
  Normalizes email addresses to avoid duplicates.

  ## Responsibilities

  - Convert to lowercase
  - Remove spaces
  - Apply provider-specific rules (Gmail, etc.)

  ## Gmail Normalization

  Gmail ignores dots (.) in the local part of the email.
  For example, these addresses are equivalent:
  - `john.doe@gmail.com`
  - `johndoe@gmail.com`
  - `j.o.h.n.d.o.e@gmail.com`

  This normalization prevents a user from creating multiple accounts
  by simply adding dots to their Gmail address.

  ## Examples

      iex> EmailNormalizer.normalize("John.Doe@Gmail.Com")
      "johndoe@gmail.com"

      iex> EmailNormalizer.normalize("john.doe@example.com")
      "john.doe@example.com"

      iex> EmailNormalizer.normalize("john.doe+work@gmail.com")
      "johndoe+work@gmail.com"
  """

  @gmail_domains ["gmail.com", "googlemail.com"]

  @doc """
  Normalizes an email address according to provider rules.

  ## Parameters

  - `email` - The email address to normalize (can be nil)

  ## Returns

  The normalized email, or nil if the input is nil.

  ## Examples

      iex> EmailNormalizer.normalize("John.Doe@Gmail.Com")
      "johndoe@gmail.com"

      iex> EmailNormalizer.normalize("  user@example.com  ")
      "user@example.com"

      iex> EmailNormalizer.normalize(nil)
      nil
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil
  def normalize(""), do: ""

  def normalize(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
    |> normalize_by_domain()
  end

  @doc """
  Checks if a domain is a Gmail domain.

  ## Examples

      iex> EmailNormalizer.gmail_domain?("gmail.com")
      true

      iex> EmailNormalizer.gmail_domain?("googlemail.com")
      true

      iex> EmailNormalizer.gmail_domain?("yahoo.com")
      false
  """
  @spec gmail_domain?(String.t()) :: boolean()
  def gmail_domain?(domain) when is_binary(domain) do
    String.downcase(domain) in @gmail_domains
  end

  # Normalizes according to the email domain
  @spec normalize_by_domain(String.t()) :: String.t()
  defp normalize_by_domain(email) do
    case String.split(email, "@") do
      [local, domain] when length([local, domain]) == 2 ->
        if gmail_domain?(domain) do
          normalize_gmail_local(local, domain)
        else
          email
        end

      _ ->
        # Invalid email, return as is
        email
    end
  end

  # Normalizes the local part of a Gmail email
  @spec normalize_gmail_local(String.t(), String.t()) :: String.t()
  defp normalize_gmail_local(local, domain) do
    # Gmail ignores dots in the local part
    # But preserves + for aliases (e.g.: user+tag@gmail.com)
    normalized_local =
      case String.split(local, "+", parts: 2) do
        [base] ->
          # No +, remove all dots
          String.replace(base, ".", "")

        [base, tag] ->
          # With +, remove dots only before the +
          String.replace(base, ".", "") <> "+" <> tag
      end

    normalized_local <> "@" <> domain
  end
end
