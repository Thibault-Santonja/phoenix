defmodule Portfolio.Photography.Services.SlugGenerator do
  @moduledoc """
  Service de génération de slugs uniques avec résolution automatique de collisions.

  Ce service implémente une stratégie de résolution de collisions par suffix date intelligent:
  1. Slug base (depuis titre normalisé)
  2. Si collision : Slug + année
  3. Si collision : Slug + année-mois
  4. Si collision : Slug + année-mois-jour
  5. Si collision : Erreur (impossible avec même titre ET même jour)

  ## Exemples

      iex> generate_unique_slug("Voyage Japon", ~D[2024-05-15])
      {:ok, "voyage-japon"}

      # Si "voyage-japon" existe déjà
      iex> generate_unique_slug("Voyage Japon", ~D[2025-06-20])
      {:ok, "voyage-japon-2025"}

      # Si "voyage-japon" et "voyage-japon-2024" existent
      iex> generate_unique_slug("Voyage Japon", ~D[2024-08-20])
      {:ok, "voyage-japon-2024-08"}

  ## Pattern DDD

  Ce service appartient à la couche Domain/Application:
  - **Service Pattern**: Encapsule logique métier complexe (génération slug + collision)
  - **Domain-Driven**: Utilise Value Object Slug et Repository
  - **Stateless**: Pas d'état, fonctions pures
  - **Testable**: Comportement déterministe, facile à tester

  ## Architecture

  ```
  SlugGenerator (Service)
       ↓ uses
  Slug (Value Object) ← normalisation
       ↓ queries
  AlbumRepository ← vérification collision
  ```
  """

  alias Portfolio.Photography.Repositories.AlbumRepository
  alias Portfolio.Photography.ValueObjects.Slug

  @doc """
  Génère un slug unique basé sur le titre et la date de prise de vue.

  Applique une stratégie de résolution de collision automatique si le slug
  généré existe déjà dans la base de données.

  ## Paramètres

    * `title` - Titre de l'album (string)
    * `date_prise_vue` - Date de prise de vue (Date)

  ## Valeurs de retour

    * `{:ok, slug}` - Slug unique généré avec succès
    * `{:error, :invalid_slug}` - Titre invalide (vide ou uniquement caractères spéciaux)
    * `{:error, :too_long}` - Slug résultant trop long (> 100 caractères)
    * `{:error, :unable_to_generate_unique_slug}` - Toutes les stratégies épuisées

  ## Stratégie de résolution de collision

  1. **Tentative 0**: Slug base (ex: "voyage-japon")
  2. **Tentative 1**: Slug + année (ex: "voyage-japon-2024")
  3. **Tentative 2**: Slug + année-mois (ex: "voyage-japon-2024-05")
  4. **Tentative 3**: Slug + année-mois-jour (ex: "voyage-japon-2024-05-15")

  Si toutes les tentatives échouent (collision sur même titre + même date complète),
  retourne une erreur car impossible de générer un slug unique.

  ## Exemples

      iex> generate_unique_slug("Château d'Été", ~D[2024-07-01])
      {:ok, "chateau-d-ete"}

      iex> generate_unique_slug("", ~D[2024-01-01])
      {:error, :invalid_slug}

      iex> generate_unique_slug("Mariage Claire & Damien 🎉", ~D[2024-06-15])
      {:ok, "mariage-claire-damien"}

  ## Notes

  - La normalisation est gérée par le Value Object `Slug`
  - La vérification de collision utilise `AlbumRepository.get_by_slug/2`
  - Le processus est déterministe (mêmes paramètres = même résultat)
  - Les mois et jours sont padded avec zéro (ex: "01", "05")
  """
  @spec generate_unique_slug(String.t(), Date.t()) ::
          {:ok, String.t()}
          | {:error, :invalid_slug | :too_long | :unable_to_generate_unique_slug}
  def generate_unique_slug(title, date_prise_vue) when is_binary(title) do
    case Slug.new(title) do
      {:ok, slug} ->
        base_slug = Slug.to_string(slug)
        attempt_unique_slug(base_slug, date_prise_vue, 0)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Tente de générer un slug unique en appliquant les suffixes progressivement
  # attempt: 0 = base, 1 = year, 2 = year-month, 3 = year-month-day
  @spec attempt_unique_slug(String.t(), Date.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, :unable_to_generate_unique_slug}
  defp attempt_unique_slug(base_slug, date, attempt) when attempt <= 3 do
    candidate = build_candidate_slug(base_slug, date, attempt)

    case AlbumRepository.get_by_slug(candidate) do
      {:error, :not_found} ->
        # Slug disponible
        {:ok, candidate}

      {:ok, _existing_album} ->
        # Collision, essayer prochain niveau
        attempt_unique_slug(base_slug, date, attempt + 1)
    end
  end

  defp attempt_unique_slug(_base_slug, _date, _attempt) do
    # Toutes les stratégies épuisées (attempt > 3)
    {:error, :unable_to_generate_unique_slug}
  end

  # Construit un slug candidat selon le niveau de tentative
  @spec build_candidate_slug(String.t(), Date.t(), non_neg_integer()) :: String.t()
  defp build_candidate_slug(base, _date, 0), do: base

  defp build_candidate_slug(base, date, 1) do
    "#{base}-#{date.year}"
  end

  defp build_candidate_slug(base, date, 2) do
    "#{base}-#{date.year}-#{pad(date.month)}"
  end

  defp build_candidate_slug(base, date, 3) do
    "#{base}-#{date.year}-#{pad(date.month)}-#{pad(date.day)}"
  end

  # Pad un nombre avec un zéro si < 10
  @spec pad(integer()) :: String.t()
  defp pad(num) when num < 10, do: "0#{num}"
  defp pad(num), do: "#{num}"
end
