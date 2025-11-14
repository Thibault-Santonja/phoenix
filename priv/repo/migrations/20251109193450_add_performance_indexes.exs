defmodule Portfolio.Repo.Migrations.AddPerformanceIndexes do
  @moduledoc """
  Ajoute des indexes pour optimiser les requêtes fréquentes.

  ## Indexes ajoutés

  ### Albums
  - `albums(published)` : Pour les filtres simples sur le statut de publication
    Utilisé par: `AlbumRepository.list(published: true)`

  - `albums(type, published)` : Index composite pour filtres combinés
    Utilisé par: `AlbumRepository.list(type: :wedding, published: true)`

  ### Photos
  - `photos(album_id)` : Pour les requêtes de photos par album
    Utilisé par: `PhotoRepository.list(album_id: album_id)`
    Note: Déjà couvert partiellement par `photos(album_id, display_order)`
    mais cet index aide pour les COUNT et les requêtes sans tri

  ### User Sessions
  - `user_sessions(user_id, last_activity_at)` : Index composite pour lister
    les sessions d'un utilisateur triées par activité
    Utilisé par: `SessionService.list_user_sessions/1`

  ## Performance attendue

  - ✅ Requêtes `list_published_albums()` : scan index au lieu de full scan
  - ✅ Filtres combinés type+published : utilisation d'index composite
  - ✅ Comptage de photos par album : index scan au lieu de seq scan
  - ✅ Liste des sessions utilisateur : index scan avec tri optimisé

  ## Note sur les indexes existants

  Les indexes suivants existent déjà et sont conservés :
  - `albums(slug)` - UNIQUE
  - `albums(published, date_prise_vue)` - Pour timeline
  - `albums(type)` - Pour filtres par type
  - `photos(album_id, display_order)` - Pour tri des photos
  - `photos(processing_status)` - Pour filtres de traitement
  - `user_sessions(user_id)` - Pour recherche par utilisateur
  - `user_sessions(last_activity_at)` - Pour nettoyage expirées
  """
  use Ecto.Migration

  def up do
    # Albums: Index simple sur published pour filtres directs
    # Complète l'index composite existant albums(published, date_prise_vue)
    create_if_not_exists index(:albums, [:published])

    # Albums: Index composite type + published pour filtres combinés fréquents
    # Exemple: Lister tous les mariages publiés
    create_if_not_exists index(:albums, [:type, :published])

    # Photos: Index sur album_id seul (en plus du composite album_id, display_order)
    # Améliore les COUNT et requêtes sans tri
    create_if_not_exists index(:photos, [:album_id])

    # User Sessions: Index composite user_id + last_activity_at
    # Optimise list_user_sessions qui trie par activité
    create_if_not_exists index(:user_sessions, [:user_id, :last_activity_at])
  end

  def down do
    drop_if_exists index(:albums, [:published])
    drop_if_exists index(:albums, [:type, :published])
    drop_if_exists index(:photos, [:album_id])
    drop_if_exists index(:user_sessions, [:user_id, :last_activity_at])
  end
end
