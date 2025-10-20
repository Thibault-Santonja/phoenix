defmodule Portfolio.Photography.ValueObjects.Slug do
  @moduledoc """
  Value Object pour les slugs URL-safe.

  ## Invariants

  - Minuscules alphanumériques + tirets uniquement
  - Maximum 100 caractères
  - Pas de tirets au début/fin
  - Ne peut pas être vide

  ## Exemples

      iex> Slug.new("Paris 2024")
      {:ok, %Slug{value: "paris-2024"}}

      iex> Slug.new("Invalid!@#")
      {:ok, %Slug{value: "invalid"}}

      iex> Slug.new("")
      {:error, :invalid_slug}

      iex> Slug.new(String.duplicate("a", 150))
      {:error, :too_long}

  ## Pattern DDD

  Un Value Object est :
  - **Immutable :** Ne peut être modifié après création
  - **Auto-validant :** Garantit ses invariants à la création
  - **Égalité par valeur :** Deux slugs identiques sont égaux
  - **Sans identité :** Pas d'ID, comparaison par attributs
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}

  @max_length 100

  @doc """
  Crée un nouveau Slug à partir d'une chaîne.

  Normalise automatiquement :
  - Conversion en minuscules
  - Suppression des caractères spéciaux
  - Remplacement des espaces par des tirets
  - Suppression des tirets multiples
  - Suppression des tirets en début/fin

  ## Exemples

      iex> Slug.new("Paris 2024")
      {:ok, %Slug{value: "paris-2024"}}

      iex> Slug.new("Hello   World!!!")
      {:ok, %Slug{value: "hello-world"}}

      iex> Slug.new("")
      {:error, :invalid_slug}
  """
  @spec new(String.t()) :: {:ok, t()} | {:error, :invalid_slug | :too_long}
  def new(str) when is_binary(str) do
    slug_value =
      str
      |> String.downcase()
      |> transliterate()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")

    cond do
      slug_value == "" ->
        {:error, :invalid_slug}

      String.length(slug_value) > @max_length ->
        {:error, :too_long}

      true ->
        {:ok, %__MODULE__{value: slug_value}}
    end
  end

  @doc """
  Crée un Slug en levant une exception en cas d'erreur.

  Utile quand on sait que l'entrée est valide.

  ## Exemples

      iex> Slug.new!("Paris 2024")
      %Slug{value: "paris-2024"}

      iex> Slug.new!("")
      ** (ArgumentError) Invalid slug: invalid_slug
  """
  @spec new!(String.t()) :: t()
  def new!(str) do
    case new(str) do
      {:ok, slug} -> slug
      {:error, reason} -> raise ArgumentError, "Invalid slug: #{reason}"
    end
  end

  @doc """
  Extrait la valeur string du Slug.

  ## Exemples

      iex> {:ok, slug} = Slug.new("test")
      iex> Slug.to_string(slug)
      "test"
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{value: value}), do: value

  # Translitère les caractères accentués en caractères ASCII
  @spec transliterate(String.t()) :: String.t()
  defp transliterate(str) do
    # Convertir en graphemes pour traiter caractère par caractère
    str
    |> String.graphemes()
    |> Enum.map(&transliterate_char/1)
    |> Enum.join()
  end

  # Translitère un caractère individuel
  defp transliterate_char(char) do
    case char do
      c when c in ~w(à á â ã ä å ā ă) -> "a"
      "æ" -> "ae"
      "ç" -> "c"
      c when c in ~w(è é ê ë ē ė ę) -> "e"
      c when c in ~w(ì í î ï ī į) -> "i"
      c when c in ~w(ñ ń) -> "n"
      c when c in ~w(ò ó ô õ ö ø ō ő) -> "o"
      "œ" -> "oe"
      c when c in ~w(ù ú û ü ū ű) -> "u"
      c when c in ~w(ý ÿ) -> "y"
      c when c in ~w(' ' ') -> ""
      _ -> char
    end
  end

  @doc """
  Vérifie si deux slugs sont égaux (égalité par valeur).

  ## Exemples

      iex> {:ok, slug1} = Slug.new("test")
      iex> {:ok, slug2} = Slug.new("test")
      iex> Slug.equal?(slug1, slug2)
      true
  """
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{value: v1}, %__MODULE__{value: v2}), do: v1 == v2
end

# Implémente le protocole String.Chars pour conversion automatique
defimpl String.Chars, for: Portfolio.Photography.ValueObjects.Slug do
  def to_string(%{value: value}), do: value
end
