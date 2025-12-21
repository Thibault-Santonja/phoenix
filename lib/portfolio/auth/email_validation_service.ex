defmodule Portfolio.Auth.EmailValidationService do
  @moduledoc """
  Service de validation des adresses email.

  Centralise toute la logique de validation d'email pour le domaine Auth.
  Ce service orchestre les différentes validations (format, domaine jetable,
  enregistrements MX) et fournit une interface unifiée pour les changesets.

  ## Responsabilités

  - Validation du format d'email
  - Détection des domaines jetables (disposable)
  - Vérification des enregistrements MX
  - Validation de l'unicité (via Repo)

  ## Pattern DDD

  Ce service encapsule la logique de validation métier qui était auparavant
  dispersée dans le schema User. Il permet de :
  - Réutiliser la validation dans d'autres contextes
  - Tester la validation indépendamment
  - Modifier les règles de validation sans toucher au schema

  ## Exemples

      iex> EmailValidationService.validate_email(changeset)
      %Ecto.Changeset{}

      iex> EmailValidationService.valid?("user@gmail.com")
      {:ok, "user@gmail.com"}

      iex> EmailValidationService.valid?("user@mailinator.com")
      {:error, :disposable_email}
  """

  import Ecto.Changeset

  alias Portfolio.Auth.DisposableEmailChecker
  alias Portfolio.Auth.MXValidator

  @max_email_length 320

  @type validation_error ::
          :required
          | :too_long
          | :invalid_format
          | :disposable_email
          | :invalid_mx

  @doc """
  Valide une adresse email et retourne le résultat.

  Exécute toutes les validations dans l'ordre :
  1. Présence (non nil/vide)
  2. Longueur (max 320 caractères)
  3. Format (contient @)
  4. Domaine non jetable
  5. Enregistrements MX valides

  ## Exemples

      iex> EmailValidationService.valid?("user@gmail.com")
      {:ok, "user@gmail.com"}

      iex> EmailValidationService.valid?(nil)
      {:error, :required}

      iex> EmailValidationService.valid?("user@mailinator.com")
      {:error, :disposable_email}
  """
  @spec valid?(String.t() | nil) :: {:ok, String.t()} | {:error, validation_error()}
  def valid?(nil), do: {:error, :required}
  def valid?(""), do: {:error, :required}

  def valid?(email) when is_binary(email) do
    normalized = String.trim(email) |> String.downcase()

    with :ok <- validate_length(normalized),
         :ok <- validate_format(normalized),
         :ok <- validate_not_disposable(normalized),
         :ok <- validate_mx(normalized) do
      {:ok, normalized}
    end
  end

  @doc """
  Applique toutes les validations d'email à un changeset.

  Cette fonction est conçue pour être utilisée dans les changesets Ecto.
  Elle applique les validations dans l'ordre et ajoute des erreurs
  traduisibles au changeset.

  ## Exemples

      iex> changeset = User.changeset(%User{}, %{email: "user@gmail.com"})
      iex> EmailValidationService.validate_email(changeset)
      %Ecto.Changeset{valid?: true}

      iex> changeset = User.changeset(%User{}, %{email: "user@mailinator.com"})
      iex> EmailValidationService.validate_email(changeset)
      %Ecto.Changeset{valid?: false, errors: [email: {"les adresses email temporaires ne sont pas autorisées", []}]}
  """
  @spec validate_email(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_length(:email, max: @max_email_length)
    |> validate_not_disposable_email()
    |> validate_mx_records()
    |> unsafe_validate_unique(:email, Portfolio.Repo)
    |> unique_constraint(:email)
  end

  @doc """
  Applique les validations d'email sans vérification d'unicité.

  Utile pour valider un email avant de l'insérer dans un contexte
  où l'unicité sera vérifiée séparément.

  ## Exemples

      iex> EmailValidationService.validate_email_format(changeset)
      %Ecto.Changeset{}
  """
  @spec validate_email_format(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_email_format(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_length(:email, max: @max_email_length)
    |> validate_not_disposable_email()
    |> validate_mx_records()
  end

  @doc """
  Vérifie si un email utilise un domaine jetable.

  ## Exemples

      iex> EmailValidationService.disposable?("user@mailinator.com")
      true

      iex> EmailValidationService.disposable?("user@gmail.com")
      false
  """
  @spec disposable?(String.t() | nil) :: boolean()
  defdelegate disposable?(email), to: DisposableEmailChecker

  @doc """
  Vérifie si un domaine email possède des enregistrements MX valides.

  ## Exemples

      iex> EmailValidationService.valid_mx?("user@gmail.com")
      true
  """
  @spec valid_mx?(String.t() | nil) :: boolean()
  defdelegate valid_mx?(email), to: MXValidator

  @doc """
  Retourne le message d'erreur pour un type d'erreur de validation.

  ## Exemples

      iex> EmailValidationService.error_message(:disposable_email)
      "les adresses email temporaires ne sont pas autorisées"
  """
  @spec error_message(validation_error()) :: String.t()
  def error_message(:required), do: "est requis"
  def error_message(:too_long), do: "est trop long (max #{@max_email_length} caractères)"
  def error_message(:invalid_format), do: "format invalide"

  def error_message(:disposable_email),
    do: "les adresses email temporaires ne sont pas autorisées"

  def error_message(:invalid_mx), do: "ce domaine ne peut pas recevoir d'emails"

  # Validations internes

  @spec validate_length(String.t()) :: :ok | {:error, :too_long}
  defp validate_length(email) do
    if String.length(email) <= @max_email_length do
      :ok
    else
      {:error, :too_long}
    end
  end

  @spec validate_format(String.t()) :: :ok | {:error, :invalid_format}
  defp validate_format(email) do
    if String.contains?(email, "@") do
      :ok
    else
      {:error, :invalid_format}
    end
  end

  @spec validate_not_disposable(String.t()) :: :ok | {:error, :disposable_email}
  defp validate_not_disposable(email) do
    if DisposableEmailChecker.disposable?(email) do
      {:error, :disposable_email}
    else
      :ok
    end
  end

  @spec validate_mx(String.t()) :: :ok | {:error, :invalid_mx}
  defp validate_mx(email) do
    if MXValidator.valid_mx?(email) do
      :ok
    else
      {:error, :invalid_mx}
    end
  end

  # Validation de changeset pour emails jetables
  @spec validate_not_disposable_email(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_not_disposable_email(changeset) do
    email = get_field(changeset, :email)

    if email && DisposableEmailChecker.disposable?(email) do
      add_error(changeset, :email, error_message(:disposable_email))
    else
      changeset
    end
  end

  # Validation de changeset pour les enregistrements MX
  @spec validate_mx_records(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_mx_records(changeset) do
    email = get_field(changeset, :email)

    if email && !MXValidator.valid_mx?(email) do
      add_error(changeset, :email, error_message(:invalid_mx))
    else
      changeset
    end
  end
end
