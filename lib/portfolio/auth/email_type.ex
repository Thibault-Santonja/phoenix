defmodule Portfolio.Auth.EmailType do
  @moduledoc """
  Custom Ecto.Type for email addresses with automatic normalization and validation.

  This type ensures that all email addresses stored in the database are:
  - Normalized to lowercase
  - Trimmed of whitespace
  - Validated according to RFC 5321 standards

  ## Normalization

  Email addresses are automatically normalized when cast:
  - Converted to lowercase: "USER@EXAMPLE.COM" → "user@example.com"
  - Trimmed of whitespace: "  user@example.com  " → "user@example.com"

  ## Validation

  Email addresses must:
  - Contain exactly one @ symbol
  - Have a non-empty local part (before @)
  - Have a valid domain with at least one dot
  - Not exceed 320 characters (64 local + @ + 255 domain)
  - Not contain invalid characters or patterns

  ## Examples

      iex> EmailType.cast("USER@EXAMPLE.COM")
      {:ok, "user@example.com"}

      iex> EmailType.cast("  user@example.com  ")
      {:ok, "user@example.com"}

      iex> EmailType.cast("invalid")
      :error
  """

  use Ecto.Type

  @max_length 320
  alias Portfolio.Auth.EmailNormalizer

  @max_local_length 64
  @max_domain_length 255

  # RFC 5322 compliant email regex (simplified but robust)
  @email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/

  @doc """
  Returns the underlying Ecto type for email addresses.

  Email addresses are stored as strings in the database.
  """
  @impl Ecto.Type
  def type, do: :string

  @doc """
  Casts a value to a normalized email address.

  Returns `{:ok, email}` if the value is a valid email after normalization,
  or `:error` if the value is invalid.

  ## Examples

      iex> EmailType.cast("USER@EXAMPLE.COM")
      {:ok, "user@example.com"}

      iex> EmailType.cast("  user@example.com  ")
      {:ok, "user@example.com"}

      iex> EmailType.cast("invalid")
      :error
  """
  @impl Ecto.Type
  def cast(email) when is_binary(email) do
    normalized = normalize(email)

    if valid?(normalized) do
      {:ok, normalized}
    else
      :error
    end
  end

  def cast(_), do: :error

  @doc """
  Loads an email address from the database.

  Email addresses in the database are assumed to already be normalized.
  """
  @impl Ecto.Type
  def load(email) when is_binary(email), do: {:ok, email}
  def load(_), do: :error

  @doc """
  Dumps an email address to the database.

  Email addresses are stored as-is, assuming they were normalized during casting.
  """
  @impl Ecto.Type
  def dump(email) when is_binary(email), do: {:ok, email}
  def dump(_), do: :error

  @doc """
  Compares two email addresses for equality.

  Email addresses are compared after normalization, so
  "USER@EXAMPLE.COM" equals "user@example.com".
  """
  @impl Ecto.Type
  def equal?(email1, email2) when is_binary(email1) and is_binary(email2) do
    normalize(email1) == normalize(email2)
  end

  def equal?(_, _), do: false

  @doc """
  Normalizes an email address by converting to lowercase, trimming whitespace,
  and applying provider-specific rules (e.g., Gmail dot normalization).

  ## Examples

      iex> EmailType.normalize("USER@EXAMPLE.COM")
      "user@example.com"

      iex> EmailType.normalize("  user@example.com  ")
      "user@example.com"

      iex> EmailType.normalize("John.Doe@Gmail.Com")
      "johndoe@gmail.com"
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(email) when is_binary(email) do
    # Utiliser EmailNormalizer qui gère lowercase, trim, et règles spécifiques
    EmailNormalizer.normalize(email)
  end

  @doc """
  Validates whether a string is a valid email address.

  Returns `true` if the email is valid, `false` otherwise.

  ## Examples

      iex> EmailType.valid?("user@example.com")
      true

      iex> EmailType.valid?("invalid")
      false

      iex> EmailType.valid?(nil)
      false
  """
  @spec valid?(String.t() | nil) :: boolean()
  def valid?(email) when is_binary(email) do
    with true <- byte_size(email) > 0 and byte_size(email) <= @max_length,
         [local, domain] <- String.split(email, "@"),
         true <- byte_size(local) > 0 and byte_size(local) <= @max_local_length,
         true <- byte_size(domain) > 0 and byte_size(domain) <= @max_domain_length,
         true <- String.contains?(domain, "."),
         true <- Regex.match?(@email_regex, email),
         true <- valid_local_part?(local),
         true <- valid_domain?(domain) do
      true
    else
      _ -> false
    end
  end

  def valid?(_), do: false

  # Private helper functions

  defp valid_local_part?(local) do
    # Check for invalid patterns in local part
    not (String.starts_with?(local, ".") or
           String.ends_with?(local, ".") or
           String.contains?(local, ".."))
  end

  defp valid_domain?(domain) do
    # Check for invalid patterns in domain
    parts = String.split(domain, ".")

    # Domain must have at least 2 parts (e.g., "example.com")
    # No empty parts
    # No part starts or ends with hyphen
    # TLD must be at least 2 characters
    length(parts) >= 2 and
      Enum.all?(parts, &(byte_size(&1) > 0)) and
      Enum.all?(parts, fn part ->
        not (String.starts_with?(part, "-") or String.ends_with?(part, "-"))
      end) and
      String.length(List.last(parts)) >= 2
  end
end
