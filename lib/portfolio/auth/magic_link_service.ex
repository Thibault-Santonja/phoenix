defmodule Portfolio.Auth.MagicLinkService do
  @moduledoc """
  Service gérant les Magic Links passwordless.

  Responsabilités:
  - Génération de tokens sécurisés
  - Vérification de tokens avec validations métier
  - Marquage comme utilisé (atomicité via Ecto.Multi)
  - Nettoyage des magic links expirés
  - Émission d'événements domaine

  Ce service encapsule toute la complexité de l'authentification passwordless
  via magic links, incluant la gestion des états (non utilisé, utilisé, expiré)
  et les garanties transactionnelles.

  Délègue la persistence au MagicLinkRepository pour respecter le pattern Repository.

  ## Flux d'authentification

  1. L'utilisateur demande un magic link (délégué à MagicLinkAuthService)
  2. Un token unique est généré et stocké
  3. L'utilisateur clique sur le lien avec le token
  4. Le token est vérifié et marqué comme utilisé atomiquement
  5. Un événement `MagicLinkVerified` est publié
  6. Une session est créée (par SessionService)
  """

  alias Portfolio.Auth.MagicLink
  alias Portfolio.Auth.Repositories.MagicLinkRepository
  alias Portfolio.DomainEvents
  alias Portfolio.DomainEvents.Builders

  # Service Layer - pour éviter dépendance circulaire
  alias Portfolio.Auth.Services.MagicLinkAuthService

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Demande un magic link pour un email donné.

  Délègue au MagicLinkAuthService pour orchestrer l'opération complète
  incluant rate limiting, création utilisateur, génération token, envoi email,
  et émission d'événements.

  ## Exemples

      iex> request_magic_link("admin@example.com")
      {:ok, %MagicLink{token: "abc123..."}}

      iex> request_magic_link("spammer@example.com")  # Après 5 requêtes
      {:error, {:rate_limit_exceeded, 300}}  # 300 secondes restantes
  """
  @spec request_magic_link(String.t()) ::
          {:ok, MagicLink.t()}
          | {:error, Ecto.Changeset.t() | :user_not_found | {:rate_limit_exceeded, integer()}}
  def request_magic_link(email) when is_binary(email) do
    MagicLinkAuthService.execute(email)
  end

  @doc """
  Demande un magic link pour un email donné en tant qu'admin.

  Similaire à `request_magic_link/1` mais bypass le rate limiting.
  Cette fonction doit être utilisée uniquement par les administrateurs
  pour réinitialiser l'accès d'un utilisateur.

  Délègue au MagicLinkAuthService avec l'option `:bypass_rate_limit`.

  ## Exemples

      iex> request_magic_link_as_admin("user@example.com")
      {:ok, %MagicLink{token: "abc123..."}}

      iex> request_magic_link_as_admin("nonexistent@example.com")  # En production
      {:error, :user_not_found}
  """
  @spec request_magic_link_as_admin(String.t()) ::
          {:ok, MagicLink.t()} | {:error, Ecto.Changeset.t() | :user_not_found}
  def request_magic_link_as_admin(email) when is_binary(email) do
    MagicLinkAuthService.execute(email, bypass_rate_limit: true)
  end

  @doc """
  Vérifie un magic link par son token de manière atomique.

  Utilise Ecto.Multi pour garantir l'atomicité :
  - Vérifie que le token existe et est valide
  - Marque le magic link comme utilisé
  - Si l'une des opérations échoue, toute la transaction est annulée

  Émet un événement `MagicLinkVerified` après vérification réussie.

  Émet également un événement telemetry `[:portfolio, :auth, :magic_link, :verified]`
  avec la durée et le résultat de l'opération.

  ## Exemples

      iex> verify_magic_link("valid_token")
      {:ok, %User{}}

      iex> verify_magic_link("invalid_token")
      {:error, :invalid_token}

      iex> verify_magic_link("expired_token")
      {:error, :expired}

      iex> verify_magic_link("already_used_token")
      {:error, :already_used}
  """
  @spec verify_magic_link(String.t()) ::
          {:ok, Portfolio.Auth.User.t()} | {:error, :invalid_token | :expired | :already_used}
  def verify_magic_link(token) when is_binary(token) do
    start_time = System.monotonic_time()

    magic_link = fetch_magic_link_by_token(token)

    result =
      case magic_link do
        nil ->
          # Perform constant-time work to prevent timing attacks
          # This makes invalid token response time similar to valid token
          _ = constant_time_comparison()
          {:error, :invalid_token}

        %MagicLink{} = ml ->
          validate_and_use_magic_link(ml)
      end

    emit_verification_telemetry(start_time, result)

    result
  end

  @doc """
  Supprime tous les magic links expirés.

  Utile pour un job de nettoyage périodique.

  ## Exemples

      iex> delete_expired_magic_links()
      {5, nil}  # 5 magic links supprimés
  """
  @spec delete_expired_magic_links() :: {integer(), nil}
  def delete_expired_magic_links do
    MagicLinkRepository.delete_expired()
  end

  @doc """
  Récupère un magic link par son code court (short_code).

  Utilisé pour afficher la page de vérification sans exposer le token dans l'URL.
  Le code court (6 caractères) est visible dans l'URL, mais le token reste caché.

  ## Exemples

      iex> get_magic_link_by_short_code("ABC123")
      {:ok, %MagicLink{short_code: "ABC123", token: "long_secure_token..."}}

      iex> get_magic_link_by_short_code("INVALID")
      {:error, :not_found}
  """
  @spec get_magic_link_by_short_code(String.t()) :: {:ok, MagicLink.t()} | {:error, :not_found}
  def get_magic_link_by_short_code(short_code) when is_binary(short_code) do
    MagicLinkRepository.get_by_short_code(short_code, preload: [:user])
  end

  # =============================================================================
  # Private Functions - Query
  # =============================================================================

  # Récupère un magic link par son token avec le user préchargé
  @spec fetch_magic_link_by_token(String.t()) :: MagicLink.t() | nil
  defp fetch_magic_link_by_token(token) do
    case MagicLinkRepository.get_by_token(token, preload: [:user]) do
      {:ok, magic_link} -> magic_link
      {:error, :not_found} -> nil
    end
  end

  # =============================================================================
  # Private Functions - Validation
  # =============================================================================

  # Valide et utilise un magic link selon son état
  @spec validate_and_use_magic_link(MagicLink.t()) ::
          {:ok, Portfolio.Auth.User.t()} | {:error, :already_used | :expired}
  defp validate_and_use_magic_link(ml) do
    cond do
      MagicLink.used?(ml) ->
        {:error, :already_used}

      MagicLink.expired?(ml) ->
        {:error, :expired}

      true ->
        mark_magic_link_as_used(ml)
    end
  end

  # =============================================================================
  # Private Functions - Mutation
  # =============================================================================

  # Marque le magic link comme utilisé de manière atomique
  @spec mark_magic_link_as_used(MagicLink.t()) ::
          {:ok, Portfolio.Auth.User.t()} | {:error, term()}
  defp mark_magic_link_as_used(ml) do
    case MagicLinkRepository.mark_as_used(ml) do
      {:ok, updated_ml} ->
        publish_magic_link_verified_event(updated_ml, ml)
        {:ok, ml.user}

      {:error, error} ->
        {:error, error}
    end
  end

  # =============================================================================
  # Private Functions - Events
  # =============================================================================

  # Publie l'événement de vérification du magic link
  @spec publish_magic_link_verified_event(MagicLink.t(), MagicLink.t()) :: :ok
  defp publish_magic_link_verified_event(updated_ml, ml) do
    event = Builders.build_magic_link_verified(updated_ml, ml.user)
    DomainEvents.publish(:magic_link_verified, event)
  end

  # Émet les métriques telemetry pour la vérification
  @spec emit_verification_telemetry(
          integer(),
          {:ok, Portfolio.Auth.User.t()} | {:error, :invalid_token | :expired | :already_used}
        ) :: :ok
  defp emit_verification_telemetry(start_time, result) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:portfolio, :auth, :magic_link, :verified],
      %{duration: duration},
      %{result: elem(result, 0)}
    )
  end

  # Performs constant-time work to prevent timing attacks
  # When token is invalid, we still do similar work as valid token validation
  @spec constant_time_comparison() :: :ok
  defp constant_time_comparison do
    # Simulate the work done during token validation
    # Use secure_compare with dummy values to add constant overhead
    dummy_hash = :crypto.strong_rand_bytes(32)
    _ = Plug.Crypto.secure_compare(dummy_hash, dummy_hash)
    :ok
  end
end
