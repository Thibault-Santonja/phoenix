defmodule Portfolio.Auth.DisposableEmailChecker do
  @moduledoc """
  Checks if an email address uses a disposable/temporary domain.

  Disposable email services allow creating temporary addresses
  to avoid spam. However, they are often used to bypass
  registration restrictions and create fake accounts.

  This module maintains a list of the most common disposable domains and
  provides functions to detect them.

  ## Examples

      iex> DisposableEmailChecker.disposable?("user@mailinator.com")
      true

      iex> DisposableEmailChecker.disposable?("user@gmail.com")
      false

  ## Domain List

  The list of disposable domains is manually maintained in this module.
  It can be extended over time by adding new domains
  to the `@disposable_domains` list.

  For a more complete production solution, consider using:
  - An external API (e.g.: https://www.block-disposable-email.com/)
  - A regularly updated database
  - An external configuration file
  """

  # List of most common disposable email domains
  # Source: https://github.com/disposable-email-domains/disposable-email-domains
  @disposable_domains [
    "10minutemail.com",
    "guerrillamail.com",
    "mailinator.com",
    "temp-mail.org",
    "throwaway.email",
    "getnada.com",
    "tempmail.com",
    "yopmail.com",
    "fakeinbox.com",
    "maildrop.cc",
    "sharklasers.com",
    "grr.la",
    "guerrillamailblock.com",
    "pokemail.net",
    "spam4.me",
    "trashmail.com",
    "mohmal.com",
    "dispostable.com",
    "mintemail.com",
    "emailondeck.com",
    "mytemp.email",
    "temp-mail.io",
    "tempr.email",
    "inboxkitten.com",
    "throwam.com"
  ]

  @doc """
  Checks if an email address uses a disposable domain.

  ## Parameters

  - `email` - The email address to check

  ## Returns

  `true` if the email uses a disposable domain, `false` otherwise.

  ## Examples

      iex> disposable?("user@mailinator.com")
      true

      iex> disposable?("user@gmail.com")
      false

      iex> disposable?(nil)
      false
  """
  @spec disposable?(String.t() | nil) :: boolean()
  def disposable?(nil), do: false
  def disposable?(""), do: false

  def disposable?(email) when is_binary(email) do
    case extract_domain(email) do
      nil ->
        false

      domain ->
        normalized_domain = String.downcase(domain)

        # Check if the domain or a parent domain is disposable
        Enum.any?(@disposable_domains, fn disposable ->
          # Exact match or subdomain (e.g.: subdomain.mailinator.com)
          normalized_domain == disposable or
            String.ends_with?(normalized_domain, "." <> disposable)
        end)
    end
  end

  @doc """
  Extracts the domain from an email address.

  ## Examples

      iex> extract_domain("user@example.com")
      "example.com"

      iex> extract_domain("invalid")
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
  Returns the complete list of known disposable domains.

  ## Examples

      iex> domains = disposable_domains()
      iex> "mailinator.com" in domains
      true
  """
  @spec disposable_domains() :: [String.t()]
  def disposable_domains, do: @disposable_domains
end
