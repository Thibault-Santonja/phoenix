defmodule Portfolio.Auth.DisposableEmailChecker do
  @moduledoc """
  Checks if an email address uses a disposable/temporary domain.

  Uses `Portfolio.Auth.Utilities.EmailExtractor` for domain extraction (DRY).

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
  @disposable_domains_list [
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

  # MapSet for O(1) lookup performance instead of O(n) linear search
  @disposable_domains_set MapSet.new(@disposable_domains_list)

  # Delegate domain extraction to centralized utility (DRY)
  defdelegate extract_domain(email), to: Portfolio.Auth.Utilities.EmailExtractor

  @doc """
  Checks if an email address uses a disposable domain.

  ## Parameters

  - `email` - The email address to check

  ## Returns

  `true` if the email uses a disposable domain, `false` otherwise.

  ## Examples

      iex> DisposableEmailChecker.disposable?("user@mailinator.com")
      true

      iex> DisposableEmailChecker.disposable?("user@gmail.com")
      false

      iex> DisposableEmailChecker.disposable?(nil)
      false
  """
  @spec disposable?(String.t() | nil) :: boolean()
  def disposable?(nil), do: false
  def disposable?(""), do: false

  def disposable?(email) when is_binary(email) do
    case extract_domain(email) do
      nil -> false
      domain -> check_domain_disposable(String.downcase(domain))
    end
  end

  # O(1) lookup for exact match, then O(n) for subdomain check
  @spec check_domain_disposable(String.t()) :: boolean()
  defp check_domain_disposable(normalized_domain) do
    MapSet.member?(@disposable_domains_set, normalized_domain) or
      subdomain_of_disposable?(normalized_domain)
  end

  # Check if domain is a subdomain of a disposable domain (e.g.: subdomain.mailinator.com)
  @spec subdomain_of_disposable?(String.t()) :: boolean()
  defp subdomain_of_disposable?(domain) do
    Enum.any?(@disposable_domains_list, fn disposable ->
      String.ends_with?(domain, "." <> disposable)
    end)
  end

  @doc """
  Returns the complete list of known disposable domains.

  ## Examples

      iex> domains = DisposableEmailChecker.disposable_domains()
      iex> "mailinator.com" in domains
      true
  """
  @spec disposable_domains() :: [String.t()]
  def disposable_domains, do: @disposable_domains_list
end
