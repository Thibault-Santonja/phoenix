defmodule Portfolio.Auth.MXValidator do
  @moduledoc """
  Valide qu'un domaine email possède des enregistrements MX valides.

  Les enregistrements MX (Mail Exchange) indiquent les serveurs responsables
  de recevoir les emails pour un domaine. Si un domaine n'a pas d'enregistrements
  MX, il ne peut pas recevoir d'emails.

  Cette validation permet de détecter :
  - Les domaines inexistants
  - Les typos dans les adresses email
  - Les domaines mal configurés
  - Les emails frauduleux

  ## Mise en cache

  Les résultats de validation sont mis en cache pendant 1 heure pour éviter
  des requêtes DNS répétées et améliorer les performances.

  ## Timeout

  Les requêtes DNS ont un timeout de 5 secondes. Si la requête échoue ou
  prend trop de temps, l'email est considéré comme invalide.

  ## Exemples

      iex> MXValidator.valid_mx?("user@gmail.com")
      true

      iex> MXValidator.valid_mx?("user@fakedomain123456.com")
      false

  ## Environnement de test

  En environnement de test, la validation MX peut être désactivée via
  la configuration pour éviter les dépendances réseau dans les tests.
  """

  require Logger

  @dns_timeout 5_000
  @cache_ttl :timer.hours(1)

  @doc """
  Vérifie si une adresse email possède des enregistrements MX valides.

  ## Paramètres

  - `email` - L'adresse email à vérifier

  ## Retourne

  `true` si le domaine possède des MX valides, `false` sinon.

  ## Exemples

      iex> valid_mx?("user@gmail.com")
      true

      iex> valid_mx?("user@invaliddomain123.com")
      false
  """
  @spec valid_mx?(String.t() | nil) :: boolean()
  def valid_mx?(nil), do: false
  def valid_mx?(""), do: false

  def valid_mx?(email) when is_binary(email) do
    cond do
      skip_mx_validation?() -> true
      domain = extract_domain(email) -> check_domain_mx(domain)
      true -> false
    end
  end

  # Vérifie les MX d'un domaine extrait
  defp check_domain_mx(domain) do
    case check_mx_records_cached(domain) do
      {:ok, _records} -> true
      {:error, _reason} -> false
    end
  end

  @doc """
  Vérifie les enregistrements MX d'un domaine.

  ## Paramètres

  - `domain` - Le domaine à vérifier

  ## Retourne

  - `{:ok, records}` - Liste des enregistrements MX
  - `{:error, reason}` - Erreur de résolution DNS

  ## Exemples

      iex> check_mx_records("gmail.com")
      {:ok, [...]}

      iex> check_mx_records("invaliddomain123.com")
      {:error, :nxdomain}
  """
  @spec check_mx_records(String.t() | nil) :: {:ok, [tuple()]} | {:error, term()}
  def check_mx_records(nil), do: {:error, :invalid_domain}
  def check_mx_records(""), do: {:error, :invalid_domain}

  def check_mx_records(domain) when is_binary(domain) do
    normalized_domain = String.downcase(domain)

    # Convertir le domaine en charlist pour :inet_res
    charlist_domain = String.to_charlist(normalized_domain)

    # Effectuer la requête DNS avec timeout
    task =
      Task.async(fn ->
        :inet_res.lookup(charlist_domain, :in, :mx)
      end)

    case Task.yield(task, @dns_timeout) || Task.shutdown(task) do
      {:ok, []} ->
        # Aucun enregistrement MX trouvé
        {:error, :no_mx_records}

      {:ok, records} when is_list(records) ->
        {:ok, records}

      nil ->
        # Timeout
        Logger.warning("DNS MX lookup timeout for domain: #{domain}")
        {:error, :timeout}

      {:exit, reason} ->
        # Erreur de résolution (domaine inexistant, etc.)
        Logger.debug("DNS MX lookup failed for domain #{domain}: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Exception during MX lookup for #{domain}: #{inspect(error)}")
      {:error, :lookup_failed}
  end

  @doc """
  Extrait le domaine d'une adresse email.

  ## Exemples

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

  # Vérifie les MX records avec cache
  @spec check_mx_records_cached(String.t()) :: {:ok, [tuple()]} | {:error, term()}
  defp check_mx_records_cached(domain) do
    cache_key = {:mx_records, domain}

    case Cachex.fetch(:portfolio_cache, cache_key, fn ->
           get_mx_for_cache(domain)
         end) do
      {:ok, result} -> result
      {:commit, result} -> result
      {:ignore, error} -> error
      _ -> {:error, :cache_error}
    end
  end

  # Récupère les MX records pour mise en cache
  defp get_mx_for_cache(domain) do
    case check_mx_records(domain) do
      {:ok, records} ->
        {:commit, {:ok, records}, ttl: @cache_ttl}

      {:error, reason} ->
        # Ne pas cacher les erreurs réseau temporaires
        if reason in [:timeout, :lookup_failed] do
          {:ignore, {:error, reason}}
        else
          # Cacher les erreurs permanentes (domaine inexistant, etc.)
          {:commit, {:error, reason}, ttl: @cache_ttl}
        end
    end
  end

  # Vérifie si on doit skip la validation MX (en test par exemple)
  defp skip_mx_validation? do
    Application.get_env(:portfolio, :skip_mx_validation, false)
  end
end
