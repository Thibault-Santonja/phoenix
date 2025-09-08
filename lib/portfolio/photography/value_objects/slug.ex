defmodule Portfolio.Photography.ValueObjects.Slug do
  @moduledoc """
  Value Object representing a URL-friendly slug.

  Slugs are immutable, normalized strings used in URLs to identify resources
  in a human-readable and SEO-friendly way.

  ## Characteristics

  - **Immutable**: Once created, a slug cannot be modified
  - **Normalized**: Automatically converted to lowercase, ASCII-only format
  - **URL-safe**: Contains only letters, numbers, and hyphens
  - **Validated**: Ensures the slug meets all requirements

  ## Rules

  - Lowercase only
  - ASCII only (accented characters are transliterated)
  - Hyphens instead of spaces
  - No special characters except hyphens
  - Max length: 100 characters
  - Cannot be empty

  ## Examples

      iex> Slug.new("Alexandre & Anne - Mariage 2024")
      {:ok, %Slug{value: "alexandre-anne-mariage-2024"}}

      iex> Slug.new("Café à Paris")
      {:ok, %Slug{value: "cafe-a-paris"}}

      iex> Slug.new("Multiple   Spaces")
      {:ok, %Slug{value: "multiple-spaces"}}

      iex> Slug.new("@@@@")
      {:error, :invalid_slug}

  ## Usage with Phoenix

  The Slug implements the `Phoenix.Param` protocol, allowing it to be used
  directly in Phoenix routes:

      <%= link "View Album", to: ~p"/albums/\#{album.slug}" %>
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}

  @max_length 100

  @doc """
  Creates a new Slug from a string.

  The input string is normalized according to slug rules. If the normalized
  result is valid, returns `{:ok, slug}`, otherwise returns `{:error, :invalid_slug}`.

  ## Parameters

    - `string` - The string to convert to a slug

  ## Returns

    - `{:ok, %Slug{}}` - Successfully created slug
    - `{:error, :invalid_slug}` - The string cannot be converted to a valid slug

  ## Examples

      iex> Slug.new("Hello World")
      {:ok, %Slug{value: "hello-world"}}

      iex> Slug.new("Été 2024")
      {:ok, %Slug{value: "ete-2024"}}

      iex> Slug.new("")
      {:error, :invalid_slug}
  """
  @spec new(String.t()) :: {:ok, t()} | {:error, :invalid_slug}
  def new(string) when is_binary(string) do
    normalized = normalize(string)

    if valid?(normalized) do
      {:ok, %__MODULE__{value: normalized}}
    else
      {:error, :invalid_slug}
    end
  end

  @doc """
  Creates a Slug, raising an exception on error.

  Similar to `new/1`, but raises `ArgumentError` if the slug is invalid.
  Use this when you expect the input to always be valid.

  ## Parameters

    - `string` - The string to convert to a slug

  ## Returns

    - `%Slug{}` - The created slug

  ## Raises

    - `ArgumentError` - If the string cannot be converted to a valid slug

  ## Examples

      iex> Slug.new!("Valid Title")
      %Slug{value: "valid-title"}

      iex> Slug.new!("@@@@")
      ** (ArgumentError) Invalid slug: invalid_slug
  """
  @spec new!(String.t()) :: t()
  def new!(string) do
    case new(string) do
      {:ok, slug} -> slug
      {:error, reason} -> raise ArgumentError, "Invalid slug: #{reason}"
    end
  end

  @doc """
  Normalizes a string into a valid slug format.

  This function applies all slug transformation rules:

  1. Convert to lowercase
  2. Transliterate accented characters to ASCII
  3. Remove all characters except letters, numbers, spaces, and hyphens
  4. Replace spaces with hyphens
  5. Replace multiple consecutive hyphens with a single hyphen
  6. Trim hyphens from start and end
  7. Truncate to maximum length

  ## Parameters

    - `string` - The string to normalize

  ## Returns

    - Normalized string suitable for use as a slug

  ## Examples

      iex> Slug.normalize("Hello World")
      "hello-world"

      iex> Slug.normalize("Café à Paris")
      "cafe-a-paris"

      iex> Slug.normalize("Multiple   Spaces")
      "multiple-spaces"

      iex> Slug.normalize("Special!@#$%Characters")
      "specialcharacters"
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(string) do
    string
    |> String.downcase()
    |> transliterate_accents()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
    |> String.slice(0, @max_length)
  end

  # Validates that a normalized string is a valid slug
  @spec valid?(String.t()) :: boolean()
  defp valid?(string) do
    String.length(string) > 0 and
      String.length(string) <= @max_length and
      String.match?(string, ~r/^[a-z0-9-]+$/)
  end

  # Transliterates accented characters to their ASCII equivalents
  @spec transliterate_accents(String.t()) :: String.t()
  defp transliterate_accents(string) do
    replacements = %{
      # Lowercase a variants
      "à" => "a",
      "á" => "a",
      "â" => "a",
      "ã" => "a",
      "ä" => "a",
      "å" => "a",
      # Lowercase e variants
      "è" => "e",
      "é" => "e",
      "ê" => "e",
      "ë" => "e",
      # Lowercase i variants
      "ì" => "i",
      "í" => "i",
      "î" => "i",
      "ï" => "i",
      # Lowercase o variants
      "ò" => "o",
      "ó" => "o",
      "ô" => "o",
      "õ" => "o",
      "ö" => "o",
      # Lowercase u variants
      "ù" => "u",
      "ú" => "u",
      "û" => "u",
      "ü" => "u",
      # Other characters
      "ç" => "c",
      "ñ" => "n",
      "œ" => "oe",
      "æ" => "ae",
      # Uppercase variants (in case input has uppercase)
      "À" => "a",
      "Á" => "a",
      "Â" => "a",
      "Ã" => "a",
      "Ä" => "a",
      "Å" => "a",
      "È" => "e",
      "É" => "e",
      "Ê" => "e",
      "Ë" => "e",
      "Ì" => "i",
      "Í" => "i",
      "Î" => "i",
      "Ï" => "i",
      "Ò" => "o",
      "Ó" => "o",
      "Ô" => "o",
      "Õ" => "o",
      "Ö" => "o",
      "Ù" => "u",
      "Ú" => "u",
      "Û" => "u",
      "Ü" => "u",
      "Ç" => "c",
      "Ñ" => "n",
      "Œ" => "oe",
      "Æ" => "ae"
    }

    Enum.reduce(replacements, string, fn {from, to}, acc ->
      String.replace(acc, from, to)
    end)
  end

  defimpl String.Chars do
    @moduledoc """
    Implements the String.Chars protocol for Slug.

    This allows slugs to be converted to strings using `to_string/1`.
    """

    def to_string(%Portfolio.Photography.ValueObjects.Slug{value: value}), do: value
  end

  defimpl Phoenix.Param do
    @moduledoc """
    Implements the Phoenix.Param protocol for Slug.

    This allows slugs to be used directly in Phoenix routes.
    """

    def to_param(%Portfolio.Photography.ValueObjects.Slug{value: value}), do: value
  end
end
