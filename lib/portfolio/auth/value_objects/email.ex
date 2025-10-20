defmodule Portfolio.Auth.ValueObjects.Email do
  @moduledoc """
  Value Object pour les adresses email.

  Valide selon RFC 5322 (simplifié).

  ## Invariants

  - Format email valide
  - Normalisé en minuscules
  - Pas d'espaces blancs
  - Maximum 254 caractères (RFC limite)

  ## Exemples

      iex> Email.new("user@example.com")
      {:ok, %Email{value: "user@example.com"}}

      iex> Email.new("USER@EXAMPLE.COM")
      {:ok, %Email{value: "user@example.com"}}

      iex> Email.new("invalid")
      {:error, :invalid_email}

  ## Pattern DDD

  Un Value Object est :
  - **Immutable :** Ne peut être modifié après création
  - **Auto-validant :** Garantit ses invariants à la création
  - **Égalité par valeur :** Deux emails identiques sont égaux
  - **Sans identité :** Pas d'ID, comparaison par attributs
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}

  # Regex simplifié conforme RFC 5322
  @email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  @max_length 254

  @doc """
  Crée un nouveau Email à partir d'une chaîne.

  Normalise automatiquement :
  - Conversion en minuscules
  - Suppression des espaces blancs
  - Validation du format

  ## Exemples

      iex> Email.new("user@example.com")
      {:ok, %Email{value: "user@example.com"}}

      iex> Email.new("  USER@EXAMPLE.COM  ")
      {:ok, %Email{value: "user@example.com"}}

      iex> Email.new("invalid")
      {:error, :invalid_email}
  """
  @spec new(String.t()) :: {:ok, t()} | {:error, :invalid_email | :too_long}
  def new(str) when is_binary(str) do
    normalized = str |> String.trim() |> String.downcase()

    cond do
      String.length(normalized) > @max_length ->
        {:error, :too_long}

      Regex.match?(@email_regex, normalized) ->
        {:ok, %__MODULE__{value: normalized}}

      true ->
        {:error, :invalid_email}
    end
  end

  @doc """
  Crée un Email en levant une exception en cas d'erreur.

  Utile quand on sait que l'entrée est valide.

  ## Exemples

      iex> Email.new!("user@example.com")
      %Email{value: "user@example.com"}

      iex> Email.new!("invalid")
      ** (ArgumentError) Invalid email: invalid_email
  """
  @spec new!(String.t()) :: t()
  def new!(str) do
    case new(str) do
      {:ok, email} -> email
      {:error, reason} -> raise ArgumentError, "Invalid email: #{reason}"
    end
  end

  @doc """
  Extrait la valeur string de l'Email.

  ## Exemples

      iex> {:ok, email} = Email.new("user@example.com")
      iex> Email.to_string(email)
      "user@example.com"
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{value: value}), do: value

  @doc """
  Vérifie si deux emails sont égaux (égalité par valeur).

  ## Exemples

      iex> {:ok, email1} = Email.new("user@example.com")
      iex> {:ok, email2} = Email.new("USER@EXAMPLE.COM")
      iex> Email.equal?(email1, email2)
      true
  """
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{value: v1}, %__MODULE__{value: v2}), do: v1 == v2
end

# Implémente le protocole String.Chars pour conversion automatique
defimpl String.Chars, for: Portfolio.Auth.ValueObjects.Email do
  def to_string(%{value: value}), do: value
end
