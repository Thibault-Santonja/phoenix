# 🗺️ Roadmap - Refactoring Architecture & Qualité

**Objectif**: Améliorer l'architecture du projet selon les principes DDD et Clean Architecture

**Date**: 26 Octobre 2025  
**Auteur**: Thibault San  
**Status**: 🟡 En cours

---

## 📋 Table des Matières

1. [Contexte](#contexte)
2. [Scores Actuels](#scores-actuels)
3. [Sprint 1 - Critiques](#sprint-1---critiques)
4. [Sprint 2 - Importantes](#sprint-2---importantes)
5. [Sprint 3 - Améliorations](#sprint-3---améliorations)
6. [Règles de Travail](#règles-de-travail)

---

## 🎯 Contexte

Suite à la code review complète du projet (26 octobre 2025), plusieurs violations architecturales et opportunités d'amélioration ont été identifiées.

**Score global actuel** : 7.6/10

Le projet respecte bien les principes DDD et Clean Architecture dans l'ensemble, mais présente quelques violations critiques qui doivent être corrigées pour maintenir la qualité exceptionnelle visée.

---

## 📊 Scores Actuels

### Par Bounded Context

| Context | Score | Points Forts | Points Faibles |
|---------|-------|--------------|----------------|
| **Auth** | 8.5/10 | Tests 100%, Sécurité excellente, DDD respecté | Pas de Domain Events, Email validation basique |
| **Photography** | 7.5/10 | Structure DDD claire, Repositories abstraits | Logique métier dans repo, Pas de Value Objects |

### Par Couche

| Couche | Score | Problèmes Critiques |
|--------|-------|---------------------|
| **Domain** | 8/10 | Manque Value Objects (Slug), Pas de Domain Events |
| **Application** | 8/10 | Bon découplage, Context bien définis |
| **Infrastructure** | 7/10 | Logique métier dans repos (sorting) |
| **Presentation** | 6.5/10 | **File I/O dans LiveView** (violation critique) |

---

## 🚨 Sprint 1 - Issues Critiques (Priorité MAXIMALE)

> **Règle** : Avant chaque issue, RELIRE `docs/RULES.md` en entier

### Issue #66 : Extraire File I/O du LiveView vers FileStorage

**Problème** : Violation critique de Clean Architecture

**Localisation** : `lib/portfolio_web/live/admin/album_live/edit.ex:70-79`

**Code problématique** :
```elixir
# ❌ MAUVAIS : File I/O dans la couche Presentation
def handle_event("delete_photo", %{"id" => id}, socket) do
  photo = Photography.get_photo!(id)
  
  # File I/O directement dans LiveView
  if File.exists?(photo.file_path) do
    File.rm!(photo.file_path)
  end
  
  Photography.delete_photo(photo)
  # ...
end
```

**Solution attendue** :

1. **Créer behaviour FileStorage** (si pas déjà fait) :
```elixir
# lib/portfolio/photography/storage/file_storage.ex
defmodule Portfolio.Photography.Storage.FileStorage do
  @moduledoc """
  Behaviour for file storage operations.
  Abstracts file system operations from the domain.
  """
  
  @callback store_photo(album_slug :: String.t(), upload :: map()) ::
    {:ok, %{file_path: String.t(), hash: String.t()}} | {:error, term()}
  
  @callback delete_photo(file_path :: String.t()) :: 
    :ok | {:error, term()}
  
  @callback get_photo_path(file_path :: String.t()) :: 
    {:ok, String.t()} | {:error, :not_found}
  
  @callback photo_exists?(file_path :: String.t()) :: boolean()
end
```

2. **Implémenter LocalStorage** :
```elixir
# lib/portfolio/photography/storage/local_storage.ex
defmodule Portfolio.Photography.Storage.LocalStorage do
  @behaviour Portfolio.Photography.Storage.FileStorage
  
  @impl true
  def delete_photo(file_path) do
    if File.exists?(file_path) do
      case File.rm(file_path) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :not_found}
    end
  end
  
  @impl true
  def photo_exists?(file_path) do
    File.exists?(file_path)
  end
  
  # ... autres implémentations
end
```

3. **Modifier Photography context** :
```elixir
# lib/portfolio/photography.ex
def delete_photo(%Photo{} = photo) do
  with :ok <- storage().delete_photo(photo.file_path),
       {:ok, _} <- PhotoRepository.delete(photo) do
    {:ok, photo}
  end
end

defp storage do
  Application.get_env(:portfolio, :file_storage, LocalStorage)
end
```

4. **Nettoyer LiveView** :
```elixir
# lib/portfolio_web/live/admin/album_live/edit.ex
def handle_event("delete_photo", %{"id" => id}, socket) do
  photo = Photography.get_photo!(id)
  
  # ✅ BON : Déléguer au context
  case Photography.delete_photo(photo) do
    {:ok, _} ->
      updated_album = Photography.get_album!(socket.assigns.album.id, preload: [:photos])
      
      {:noreply,
       socket
       |> assign(:album, updated_album)
       |> put_flash(:info, "Photo supprimée")}
    
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Erreur : #{inspect(reason)}")}
  end
end
```

**Checklist** :
- [ ] Créer behaviour FileStorage (si absent)
- [ ] Implémenter LocalStorage.delete_photo/1
- [ ] Implémenter LocalStorage.photo_exists?/1
- [ ] Modifier Photography.delete_photo/1 pour utiliser storage
- [ ] Nettoyer edit.ex (retirer File.rm!, File.exists?)
- [ ] Configuration Application.get_env
- [ ] Tests : LocalStorage.delete_photo/1
- [ ] Tests : Photography.delete_photo/1 avec storage mock
- [ ] Tests : LiveView delete_photo event
- [ ] `mix precommit` OK
- [ ] Commit : `refactor: Extract file I/O from LiveView to FileStorage service`

**Estimation** : 2-3h

---

### Issue #67 : Implémenter PhotoRepository.reorder/2 avec Ecto.Multi

**Problème** : N+1 queries lors du réordonnancement, logique métier dans LiveView

**Localisation** : `lib/portfolio_web/live/admin/album_live/edit.ex:109-114`

**Code problématique** :
```elixir
# ❌ MAUVAIS : N+1 queries, logique métier dans LiveView
def handle_event("save_photo_order", _params, socket) do
  socket.assigns.temp_photo_order
  |> Enum.with_index()
  |> Enum.each(fn {photo_id, index} ->
    photo = Photography.get_photo!(photo_id)  # N queries
    Photography.update_photo(photo, %{display_order: index})  # N queries
  end)
  # ...
end
```

**Solution attendue** :

1. **Créer PhotoRepository.reorder/2** :
```elixir
# lib/portfolio/photography/repositories/photo_repository.ex
@doc """
Reorders photos by updating their display_order in a single transaction.

## Parameters
  - photo_ids: List of photo IDs in the desired order
  
## Returns
  - {:ok, updated_count} on success
  - {:error, reason} on failure
  
## Examples
    iex> reorder([photo3.id, photo1.id, photo2.id])
    {:ok, 3}
"""
@spec reorder([Ecto.UUID.t()]) :: {:ok, integer()} | {:error, term()}
def reorder(photo_ids) when is_list(photo_ids) do
  Multi.new()
  |> Multi.run(:validate_photos, fn repo, _changes ->
    photos = repo.all(from p in Photo, where: p.id in ^photo_ids)
    
    if length(photos) == length(photo_ids) do
      {:ok, photos}
    else
      {:error, :photos_not_found}
    end
  end)
  |> Multi.run(:reorder, fn repo, %{validate_photos: photos} ->
    # Build updates
    updates =
      photo_ids
      |> Enum.with_index()
      |> Enum.map(fn {photo_id, index} ->
        {photo_id, index}
      end)
      |> Map.new()
    
    # Batch update using single query
    photo_ids_with_order =
      Enum.map(photo_ids, fn id ->
        %{id: id, display_order: updates[id]}
      end)
    
    # Use Ecto's insert_all with ON CONFLICT for batch update
    result = repo.insert_all(
      Photo,
      photo_ids_with_order,
      on_conflict: {:replace, [:display_order, :updated_at]},
      conflict_target: :id,
      returning: [:id]
    )
    
    {:ok, result}
  end)
  |> Repo.transaction()
  |> case do
    {:ok, %{reorder: {count, _}}} -> {:ok, count}
    {:error, _failed_operation, reason, _changes} -> {:error, reason}
  end
end
```

2. **Alternative avec Enum.reduce** (plus simple) :
```elixir
@spec reorder([Ecto.UUID.t()]) :: {:ok, integer()} | {:error, term()}
def reorder(photo_ids) when is_list(photo_ids) do
  multi =
    photo_ids
    |> Enum.with_index()
    |> Enum.reduce(Multi.new(), fn {photo_id, index}, multi ->
      Multi.update(
        multi,
        {:photo, photo_id},
        fn _changes ->
          Photo
          |> Repo.get!(photo_id)
          |> Ecto.Changeset.change(display_order: index)
        end
      )
    end)
  
  case Repo.transaction(multi) do
    {:ok, _} -> {:ok, length(photo_ids)}
    {:error, _failed_op, reason, _changes} -> {:error, reason}
  end
end
```

3. **Exposer via Photography context** :
```elixir
# lib/portfolio/photography.ex
@doc """
Reorders photos within an album.

## Parameters
  - photo_ids: List of photo IDs in the desired display order
  
## Examples
    iex> reorder_photos([photo3.id, photo1.id, photo2.id])
    {:ok, 3}
"""
@spec reorder_photos([Ecto.UUID.t()]) :: {:ok, integer()} | {:error, term()}
def reorder_photos(photo_ids) do
  PhotoRepository.reorder(photo_ids)
end
```

4. **Nettoyer LiveView** :
```elixir
# lib/portfolio_web/live/admin/album_live/edit.ex
def handle_event("save_photo_order", _params, socket) do
  case Photography.reorder_photos(socket.assigns.temp_photo_order) do
    {:ok, count} ->
      updated_album = Photography.get_album!(socket.assigns.album.id, preload: [:photos])
      
      {:noreply,
       socket
       |> assign(:album, updated_album)
       |> assign(:reordering_mode, false)
       |> assign(:temp_photo_order, [])
       |> put_flash(:info, "Ordre de #{count} photos enregistré")}
    
    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Erreur : #{inspect(reason)}")}
  end
end
```

**Checklist** :
- [ ] Implémenter PhotoRepository.reorder/2 avec Ecto.Multi
- [ ] @moduledoc et @doc complets
- [ ] @spec pour Dialyzer
- [ ] Exposer Photography.reorder_photos/1
- [ ] Nettoyer LiveView (retirer Enum.each + N queries)
- [ ] Tests unitaires PhotoRepository.reorder/2 :
  - [ ] Cas nominal : 3 photos réordonnées
  - [ ] Cas erreur : photo_id invalide
  - [ ] Vérifier transaction atomique (rollback si erreur)
- [ ] Tests intégration Photography.reorder_photos/1
- [ ] Tests LiveView : save_photo_order utilise nouveau code
- [ ] `mix precommit` OK
- [ ] Commit : `refactor: Implement PhotoRepository.reorder with Ecto.Multi to avoid N+1 queries`

**Estimation** : 2-3h

---

### Issue #68 : Corriger fixtures tests (maps → keyword lists)

**Problème** : Tests utilisent maps au lieu de keyword lists, causant erreurs de compilation

**Localisation** : `test/portfolio_web/live/admin/album_live/edit_test.exs` et autres

**Code problématique** :
```elixir
# ❌ MAUVAIS : Maps au lieu de keyword lists
album = album_fixture(%{
  title: "Test Album",
  type: "wedding"
})
```

**Code attendu** :
```elixir
# ✅ BON : Keyword lists
album = album_fixture(
  title: "Test Album",
  type: "wedding"
)
```

**Solution** :

1. **Vérifier signature des fixtures** :
```elixir
# test/support/fixtures/photography_fixtures.ex
def album_fixture(attrs \\ []) when is_list(attrs) do  # Keyword list
  # ...
end
```

2. **Corriger tous les appels** :
```bash
# Trouver tous les usages problématiques
grep -r "album_fixture(%{" test/
grep -r "photo_fixture(%{" test/
grep -r "user_fixture(%{" test/
```

3. **Remplacer systematiquement** :
```elixir
# Avant
album_fixture(%{title: "Test", type: "wedding"})

# Après
album_fixture(title: "Test", type: "wedding")
```

**Checklist** :
- [ ] Audit de tous les fichiers test/ avec grep
- [ ] Corriger album_fixture calls
- [ ] Corriger photo_fixture calls
- [ ] Corriger user_fixture calls (si applicable)
- [ ] Vérifier signatures des fixtures (attrs \\ [])
- [ ] `mix test` → 100% des tests passent
- [ ] `mix precommit` OK
- [ ] Commit : `test: Fix fixture calls to use keyword lists instead of maps`

**Estimation** : 1h

---

## 🔶 Sprint 2 - Issues Importantes (Priorité Haute)

> **Règle** : Avant chaque issue, RELIRE `docs/RULES.md` en entier

### Issue #69 : Ajouter Domain Events (AlbumPublished, PhotoUploaded)

**Problème** : Couplage fort entre contextes (Auth.Mailer appelé directement)

**Bénéfices** :
- Découplage entre bounded contexts
- Extensibilité (ajouter listeners sans modifier émetteur)
- Audit trail automatique

**Solution** :

1. **Créer module Domain Events** :
```elixir
# lib/portfolio/domain_events.ex
defmodule Portfolio.DomainEvents do
  @moduledoc """
  Domain Events system for decoupling bounded contexts.
  
  Uses Phoenix.PubSub for event broadcasting.
  """
  
  alias Phoenix.PubSub
  
  @pubsub Portfolio.PubSub
  
  @doc "Publishes a domain event"
  @spec publish(atom(), map()) :: :ok
  def publish(event_type, payload) do
    PubSub.broadcast(@pubsub, topic(event_type), {event_type, payload})
  end
  
  @doc "Subscribes to a domain event type"
  @spec subscribe(atom()) :: :ok
  def subscribe(event_type) do
    PubSub.subscribe(@pubsub, topic(event_type))
  end
  
  defp topic(event_type), do: "domain_events:#{event_type}"
end
```

2. **Définir événements Photography** :
```elixir
# lib/portfolio/photography/events.ex
defmodule Portfolio.Photography.Events do
  @moduledoc "Domain events for Photography bounded context"
  
  defmodule AlbumPublished do
    @moduledoc "Raised when an album is published"
    
    defstruct [:album_id, :title, :slug, :published_at, :user_id]
    
    @type t :: %__MODULE__{
      album_id: Ecto.UUID.t(),
      title: String.t(),
      slug: String.t(),
      published_at: DateTime.t(),
      user_id: Ecto.UUID.t() | nil
    }
  end
  
  defmodule PhotoUploaded do
    @moduledoc "Raised when a photo is uploaded"
    
    defstruct [:photo_id, :album_id, :file_path, :hash, :uploaded_at]
    
    @type t :: %__MODULE__{
      photo_id: Ecto.UUID.t(),
      album_id: Ecto.UUID.t(),
      file_path: String.t(),
      hash: String.t(),
      uploaded_at: DateTime.t()
    }
  end
end
```

3. **Émettre événements depuis Photography** :
```elixir
# lib/portfolio/photography.ex
alias Portfolio.DomainEvents
alias Portfolio.Photography.Events.{AlbumPublished, PhotoUploaded}

def publish_album(%Album{} = album, user_id \\ nil) do
  with {:ok, album} <- validate_publishable(album),
       {:ok, album} <- AlbumRepository.update(album, %{published: true}) do
    
    # Émettre l'événement
    DomainEvents.publish(:album_published, %AlbumPublished{
      album_id: album.id,
      title: album.title,
      slug: album.slug,
      published_at: DateTime.utc_now(),
      user_id: user_id
    })
    
    {:ok, album}
  end
end

def upload_photos(album_id, uploads) do
  # ... logique upload
  
  Enum.each(uploaded_photos, fn photo ->
    DomainEvents.publish(:photo_uploaded, %PhotoUploaded{
      photo_id: photo.id,
      album_id: album_id,
      file_path: photo.file_path,
      hash: photo.hash,
      uploaded_at: DateTime.utc_now()
    })
  end)
  
  {:ok, uploaded_photos}
end
```

4. **Créer Event Handlers** :
```elixir
# lib/portfolio/photography/event_handlers/album_published_handler.ex
defmodule Portfolio.Photography.EventHandlers.AlbumPublishedHandler do
  @moduledoc """
  Handles AlbumPublished events.
  
  Could send notifications, update analytics, etc.
  """
  
  use GenServer
  
  alias Portfolio.DomainEvents
  require Logger
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end
  
  def init(_) do
    DomainEvents.subscribe(:album_published)
    {:ok, %{}}
  end
  
  def handle_info({:album_published, event}, state) do
    Logger.info("Album published: #{event.title} (#{event.album_id})")
    
    # Future: Send notification, update search index, etc.
    
    {:noreply, state}
  end
end
```

5. **Ajouter au Supervision Tree** :
```elixir
# lib/portfolio/application.ex
children = [
  # ...
  Portfolio.Photography.EventHandlers.AlbumPublishedHandler,
  # ...
]
```

**Checklist** :
- [ ] Créer Portfolio.DomainEvents
- [ ] Créer Photography.Events (AlbumPublished, PhotoUploaded)
- [ ] Émettre :album_published dans publish_album/2
- [ ] Émettre :photo_uploaded dans upload_photos/2
- [ ] Créer AlbumPublishedHandler
- [ ] Ajouter handler au supervision tree
- [ ] Tests : publish émet événements
- [ ] Tests : handlers reçoivent événements
- [ ] Documentation @moduledoc complète
- [ ] `mix precommit` OK
- [ ] Commit : `feat: Add Domain Events system for decoupling contexts`

**Estimation** : 3-4h

---

### Issue #70 : Créer Value Object Slug

**Problème** : Logique de slug dupliquée, pas de type fort

**Localisation** : Logique dans `Album.generate_slug/1` et `Photo.generate_slug_from_filename/1`

**Solution** :

1. **Créer Value Object** :
```elixir
# lib/portfolio/photography/value_objects/slug.ex
defmodule Portfolio.Photography.ValueObjects.Slug do
  @moduledoc """
  Value Object representing a URL-friendly slug.
  
  Slugs are immutable, normalized strings used in URLs.
  
  ## Rules
  - Lowercase
  - ASCII only (transliterate accents)
  - Hyphens instead of spaces
  - No special characters except hyphens
  - Max length: 100 characters
  
  ## Examples
      iex> Slug.new("Alexandre & Anne - Mariage 2024")
      {:ok, %Slug{value: "alexandre-anne-mariage-2024"}}
      
      iex> Slug.new("Café à Paris")
      {:ok, %Slug{value: "cafe-a-paris"}}
  """
  
  @enforce_keys [:value]
  defstruct [:value]
  
  @type t :: %__MODULE__{value: String.t()}
  
  @max_length 100
  
  @doc "Creates a new Slug from a string"
  @spec new(String.t()) :: {:ok, t()} | {:error, :invalid_slug}
  def new(string) when is_binary(string) do
    normalized = normalize(string)
    
    if valid?(normalized) do
      {:ok, %__MODULE__{value: normalized}}
    else
      {:error, :invalid_slug}
    end
  end
  
  @doc "Creates a Slug, raising on error"
  @spec new!(String.t()) :: t()
  def new!(string) do
    case new(string) do
      {:ok, slug} -> slug
      {:error, reason} -> raise ArgumentError, "Invalid slug: #{reason}"
    end
  end
  
  @doc "Normalizes a string into a valid slug"
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
  
  @spec valid?(String.t()) :: boolean()
  defp valid?(string) do
    String.length(string) > 0 and
    String.length(string) <= @max_length and
    String.match?(string, ~r/^[a-z0-9-]+$/)
  end
  
  @spec transliterate_accents(String.t()) :: String.t()
  defp transliterate_accents(string) do
    replacements = %{
      "à" => "a", "â" => "a", "ä" => "a",
      "é" => "e", "è" => "e", "ê" => "e", "ë" => "e",
      "î" => "i", "ï" => "i",
      "ô" => "o", "ö" => "o",
      "ù" => "u", "û" => "u", "ü" => "u",
      "ç" => "c",
      "œ" => "oe", "æ" => "ae"
    }
    
    Enum.reduce(replacements, string, fn {from, to}, acc ->
      String.replace(acc, from, to)
    end)
  end
  
  defimpl String.Chars do
    def to_string(%Portfolio.Photography.ValueObjects.Slug{value: value}), do: value
  end
  
  defimpl Phoenix.Param do
    def to_param(%Portfolio.Photography.ValueObjects.Slug{value: value}), do: value
  end
end
```

2. **Utiliser dans Album** :
```elixir
# lib/portfolio/photography/album.ex
alias Portfolio.Photography.ValueObjects.Slug

defp generate_slug(changeset) do
  if title = get_change(changeset, :title) do
    case Slug.new(title) do
      {:ok, slug} -> put_change(changeset, :slug, to_string(slug))
      {:error, _} -> add_error(changeset, :title, "ne peut pas être converti en slug valide")
    end
  else
    changeset
  end
end
```

3. **Tests Value Object** :
```elixir
# test/portfolio/photography/value_objects/slug_test.exs
defmodule Portfolio.Photography.ValueObjects.SlugTest do
  use ExUnit.Case, async: true
  
  alias Portfolio.Photography.ValueObjects.Slug
  
  describe "new/1" do
    test "creates slug from simple string" do
      assert {:ok, %Slug{value: "hello-world"}} = Slug.new("Hello World")
    end
    
    test "transliterates French accents" do
      assert {:ok, %Slug{value: "cafe-a-paris"}} = Slug.new("Café à Paris")
    end
    
    test "removes special characters" do
      assert {:ok, %Slug{value: "alexandre-anne"}} = Slug.new("Alexandre & Anne")
    end
    
    test "truncates to max length" do
      long_string = String.duplicate("a", 150)
      assert {:ok, %Slug{value: value}} = Slug.new(long_string)
      assert String.length(value) == 100
    end
    
    test "returns error for empty result" do
      assert {:error, :invalid_slug} = Slug.new("@@@@")
    end
  end
  
  describe "new!/1" do
    test "raises on invalid slug" do
      assert_raise ArgumentError, fn ->
        Slug.new!("@@@@")
      end
    end
  end
  
  describe "String.Chars protocol" do
    test "converts to string" do
      {:ok, slug} = Slug.new("Hello World")
      assert to_string(slug) == "hello-world"
    end
  end
end
```

**Checklist** :
- [ ] Créer Portfolio.Photography.ValueObjects.Slug
- [ ] Implémenter new/1, new!/1, normalize/1
- [ ] Implémenter transliterate_accents/1
- [ ] Implémenter String.Chars protocol
- [ ] Implémenter Phoenix.Param protocol
- [ ] Modifier Album.generate_slug/1 pour utiliser Slug
- [ ] Modifier Photo (si applicable)
- [ ] Tests unitaires complets (accents, max length, special chars)
- [ ] Documentation @moduledoc avec exemples
- [ ] @spec pour toutes fonctions publiques
- [ ] `mix precommit` OK
- [ ] Commit : `feat: Create Slug Value Object for URL normalization`

**Estimation** : 2-3h

---

### Issue #71 : Ajouter Telemetry pour métriques métier

**Problème** : Pas de visibilité sur les opérations critiques

**Bénéfices** :
- Monitoring des performances
- Alertes sur erreurs
- Métriques métier (uploads, publications)

**Solution** :

1. **Ajouter événements Telemetry** :
```elixir
# lib/portfolio/photography.ex
def create_album(attrs) do
  start_time = System.monotonic_time()
  
  result = AlbumService.create_album(attrs)
  
  duration = System.monotonic_time() - start_time
  
  :telemetry.execute(
    [:portfolio, :photography, :album, :created],
    %{duration: duration},
    %{result: elem(result, 0)}  # :ok or :error
  )
  
  result
end

def upload_photos(album_id, uploads) do
  start_time = System.monotonic_time()
  count = length(uploads)
  
  result = PhotoService.upload_photos(album_id, uploads)
  
  duration = System.monotonic_time() - start_time
  
  :telemetry.execute(
    [:portfolio, :photography, :photos, :uploaded],
    %{duration: duration, count: count},
    %{album_id: album_id, result: elem(result, 0)}
  )
  
  result
end
```

2. **Créer Telemetry Handler** :
```elixir
# lib/portfolio/telemetry.ex
defmodule Portfolio.Telemetry do
  @moduledoc """
  Telemetry supervisor and event handlers.
  
  Defines all telemetry events emitted by the application.
  """
  
  use Supervisor
  import Telemetry.Metrics
  
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end
  
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  def metrics do
    [
      # Photography metrics
      counter("portfolio.photography.album.created.count"),
      distribution("portfolio.photography.album.created.duration",
        unit: {:native, :millisecond}
      ),
      
      counter("portfolio.photography.photos.uploaded.count"),
      sum("portfolio.photography.photos.uploaded.total", 
        measurement: :count
      ),
      distribution("portfolio.photography.photos.uploaded.duration",
        unit: {:native, :millisecond}
      ),
      
      # Auth metrics
      counter("portfolio.auth.magic_link.requested.count"),
      counter("portfolio.auth.magic_link.verified.count"),
      
      # Phoenix metrics (déjà présents)
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router.dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      )
    ]
  end
  
  defp periodic_measurements do
    []
  end
end
```

3. **Logger Handler** :
```elixir
# lib/portfolio_web/telemetry.ex (modifier existant)
def handle_event([:portfolio, :photography, :album, :created], measurements, metadata, _config) do
  Logger.info("Album created in #{measurements.duration}ms - result: #{metadata.result}")
end

def handle_event([:portfolio, :photography, :photos, :uploaded], measurements, metadata, _config) do
  Logger.info("#{measurements.count} photos uploaded in #{measurements.duration}ms - album: #{metadata.album_id}")
end
```

4. **Attacher handlers** :
```elixir
# lib/portfolio/application.ex
def start(_type, _args) do
  # Attach telemetry handlers
  :telemetry.attach_many(
    "portfolio-telemetry",
    [
      [:portfolio, :photography, :album, :created],
      [:portfolio, :photography, :photos, :uploaded],
      [:portfolio, :auth, :magic_link, :requested],
      [:portfolio, :auth, :magic_link, :verified]
    ],
    &PortfolioWeb.Telemetry.handle_event/4,
    nil
  )
  
  # ...
end
```

**Checklist** :
- [ ] Ajouter telemetry events dans Photography context
- [ ] Ajouter telemetry events dans Auth context
- [ ] Définir metrics dans Portfolio.Telemetry
- [ ] Créer handlers dans PortfolioWeb.Telemetry
- [ ] Attacher handlers dans Application.start/2
- [ ] Tests : vérifier émission événements
- [ ] Documentation événements telemetry
- [ ] `mix precommit` OK
- [ ] Commit : `feat: Add Telemetry for business metrics and monitoring`

**Estimation** : 2-3h

---

### Issue #72 : Configurer Dialyzer

**Problème** : Pas de vérification de types statique

**Bénéfices** :
- Détection erreurs de types à la compilation
- Documentation types vivante
- Meilleure qualité code

**Solution** :

1. **Ajouter dépendance** :
```elixir
# mix.exs
defp deps do
  [
    # ...
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
  ]
end
```

2. **Configuration** :
```elixir
# mix.exs
def project do
  [
    # ...
    dialyzer: [
      plt_add_apps: [:ex_unit, :mix],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      flags: [
        :error_handling,
        :underspecs,
        :unmatched_returns
      ],
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  ]
end
```

3. **Générer PLT** :
```bash
mix dialyzer --plt
```

4. **Corriger warnings** :
```bash
mix dialyzer
```

5. **Ajouter @spec manquantes** :

Exemples de specs à ajouter :
```elixir
# lib/portfolio/photography.ex
@spec create_album(map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
@spec get_album!(Ecto.UUID.t()) :: Album.t() | no_return()
@spec list_albums(keyword()) :: [Album.t()]
@spec delete_photo(Photo.t()) :: {:ok, Photo.t()} | {:error, term()}

# lib/portfolio/auth.ex
@spec request_magic_link(String.t()) :: {:ok, MagicLink.t()} | {:error, term()}
@spec verify_magic_link(String.t()) :: {:ok, User.t()} | {:error, :invalid | :expired | :used}
```

**Checklist** :
- [ ] Ajouter dialyxir à mix.exs
- [ ] Configurer dialyzer options
- [ ] `mix deps.get`
- [ ] `mix dialyzer --plt` (génération PLT, ~5-10 min)
- [ ] `mix dialyzer` → identifier warnings
- [ ] Ajouter @spec manquantes dans Photography
- [ ] Ajouter @spec manquantes dans Auth
- [ ] Ajouter @spec dans repositories
- [ ] Corriger tous warnings Dialyzer
- [ ] Créer .dialyzer_ignore.exs si nécessaire (warnings externes)
- [ ] Ajouter `dialyzer` à alias precommit
- [ ] Documentation : comment utiliser Dialyzer
- [ ] `mix precommit` OK (avec dialyzer)
- [ ] Commit : `chore: Configure Dialyzer for static type checking`

**Estimation** : 2-3h (+ temps génération PLT)

---

## 🟢 Sprint 3 - Améliorations (Priorité Moyenne)

> **Règle** : Avant chaque issue, RELIRE `docs/RULES.md` en entier

### Issue #73 : Extraire logique sorting des Repositories vers Query Objects

**Problème** : Repositories contiennent logique métier (tri, filtrage)

**Localisation** : `lib/portfolio/photography/repositories/album_repository.ex:40-50`

**Solution** :

1. **Créer Query Objects** :
```elixir
# lib/portfolio/photography/queries/album_query.ex
defmodule Portfolio.Photography.Queries.AlbumQuery do
  @moduledoc """
  Query builder for Album queries.
  
  Separates query construction logic from repository.
  """
  
  import Ecto.Query
  
  alias Portfolio.Photography.Album
  
  @doc "Base query for albums"
  @spec base() :: Ecto.Query.t()
  def base do
    from(a in Album, as: :album)
  end
  
  @doc "Filters albums by type"
  @spec by_type(Ecto.Query.t(), String.t()) :: Ecto.Query.t()
  def by_type(query, type) do
    where(query, [album: a], a.type == ^type)
  end
  
  @doc "Filters published albums"
  @spec published(Ecto.Query.t()) :: Ecto.Query.t()
  def published(query) do
    where(query, [album: a], a.published == true)
  end
  
  @doc "Orders albums by date descending"
  @spec order_by_date_desc(Ecto.Query.t()) :: Ecto.Query.t()
  def order_by_date_desc(query) do
    order_by(query, [album: a], desc: a.date_prise_vue)
  end
  
  @doc "Preloads photos ordered by display_order"
  @spec with_photos(Ecto.Query.t()) :: Ecto.Query.t()
  def with_photos(query) do
    photos_query = from p in Portfolio.Photography.Photo, order_by: [asc: p.display_order]
    preload(query, [photos: ^photos_query])
  end
  
  @doc "Groups albums by year"
  @spec group_by_year(Ecto.Query.t()) :: Ecto.Query.t()
  def group_by_year(query) do
    query
    |> select([album: a], {fragment("EXTRACT(YEAR FROM ?)", a.date_prise_vue), a})
    |> order_by([album: a], desc: fragment("EXTRACT(YEAR FROM ?)", a.date_prise_vue))
  end
end
```

2. **Simplifier Repository** :
```elixir
# lib/portfolio/photography/repositories/album_repository.ex
defmodule Portfolio.Photography.Repositories.AlbumRepository do
  import Ecto.Query
  
  alias Portfolio.Repo
  alias Portfolio.Photography.Album
  alias Portfolio.Photography.Queries.AlbumQuery
  
  @doc "Lists albums with optional filters"
  @spec list(keyword()) :: [Album.t()]
  def list(filters \\ []) do
    AlbumQuery.base()
    |> apply_filters(filters)
    |> Repo.all()
  end
  
  defp apply_filters(query, []), do: query
  
  defp apply_filters(query, [{:type, type} | rest]) do
    query
    |> AlbumQuery.by_type(type)
    |> apply_filters(rest)
  end
  
  defp apply_filters(query, [{:published, true} | rest]) do
    query
    |> AlbumQuery.published()
    |> apply_filters(rest)
  end
  
  defp apply_filters(query, [{:order, :date_desc} | rest]) do
    query
    |> AlbumQuery.order_by_date_desc()
    |> apply_filters(rest)
  end
  
  defp apply_filters(query, [{:preload, preloads} | rest]) when is_list(preloads) do
    query
    |> apply_preloads(preloads)
    |> apply_filters(rest)
  end
  
  defp apply_filters(query, [_unknown | rest]), do: apply_filters(query, rest)
  
  defp apply_preloads(query, preloads) do
    if :photos in preloads do
      AlbumQuery.with_photos(query)
    else
      preload(query, ^preloads)
    end
  end
  
  @doc "Lists published albums grouped by year"
  @spec list_published_by_year() :: %{integer() => [Album.t()]}
  def list_published_by_year do
    AlbumQuery.base()
    |> AlbumQuery.published()
    |> AlbumQuery.group_by_year()
    |> AlbumQuery.with_photos()
    |> Repo.all()
    |> Enum.group_by(fn {year, _album} -> trunc(year) end, fn {_year, album} -> album end)
  end
end
```

**Checklist** :
- [ ] Créer Portfolio.Photography.Queries.AlbumQuery
- [ ] Implémenter fonctions query builders
- [ ] Créer Portfolio.Photography.Queries.PhotoQuery (si nécessaire)
- [ ] Refactoriser AlbumRepository pour utiliser Query Objects
- [ ] Refactoriser PhotoRepository pour utiliser Query Objects
- [ ] Tests Query Objects (isolation)
- [ ] Tests Repository (vérifier aucune régression)
- [ ] Documentation @moduledoc complète
- [ ] `mix precommit` OK
- [ ] Commit : `refactor: Extract query logic from repositories to Query Objects`

**Estimation** : 3-4h

---

### Issue #74 : Améliorer validation email (RFC 5322)

**Problème** : Regex email trop basique

**Localisation** : `lib/portfolio/auth/user.ex:40`

**Code actuel** :
```elixir
validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
```

**Solution** :

```elixir
# lib/portfolio/auth/user.ex
@email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

def changeset(user, attrs) do
  user
  |> cast(attrs, [:email, :name, :role])
  |> validate_required([:email, :role])
  |> validate_email()
  |> validate_inclusion(:role, ["viewer", "admin", "superadmin"])
  |> unique_constraint(:email)
end

defp validate_email(changeset) do
  changeset
  |> validate_format(:email, @email_regex, message: "doit être un email valide")
  |> validate_length(:email, max: 160)
  |> update_change(:email, &String.downcase/1)
end
```

**Tests** :
```elixir
test "validates email format" do
  valid_emails = [
    "user@example.com",
    "user+tag@example.co.uk",
    "user.name@example.com",
    "user_name@example-domain.com"
  ]
  
  invalid_emails = [
    "invalid",
    "@example.com",
    "user@",
    "user @example.com",
    "user@example .com"
  ]
  
  for email <- valid_emails do
    changeset = User.changeset(%User{}, %{email: email, role: "viewer"})
    assert changeset.valid?, "#{email} should be valid"
  end
  
  for email <- invalid_emails do
    changeset = User.changeset(%User{}, %{email: email, role: "viewer"})
    refute changeset.valid?, "#{email} should be invalid"
  end
end
```

**Checklist** :
- [ ] Remplacer regex email par version RFC 5322
- [ ] Ajouter validate_length max 160
- [ ] Ajouter update_change pour downcase
- [ ] Tests emails valides (10+ cas)
- [ ] Tests emails invalides (10+ cas)
- [ ] `mix precommit` OK
- [ ] Commit : `fix: Improve email validation with RFC 5322 compliant regex`

**Estimation** : 1h

---

### Issue #75 : Refactoriser duplications LiveView (DRY)

**Problème** : Code dupliqué entre New et Edit LiveViews

**Solution** :

1. **Extraire FormComponent** :
```elixir
# lib/portfolio_web/live/admin/album_live/form_component.ex
defmodule PortfolioWeb.Admin.AlbumLive.FormComponent do
  use PortfolioWeb, :live_component
  
  alias Portfolio.Photography
  
  @impl true
  def update(%{album: album} = assigns, socket) do
    changeset = Photography.change_album(album)
    
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(changeset))
     |> assign(:types, album_types())}
  end
  
  @impl true
  def handle_event("validate", %{"album" => album_params}, socket) do
    changeset =
      socket.assigns.album
      |> Photography.change_album(album_params)
      |> Map.put(:action, :validate)
    
    {:noreply, assign(socket, :form, to_form(changeset))}
  end
  
  @impl true
  def handle_event("save", %{"album" => album_params}, socket) do
    save_album(socket, socket.assigns.action, album_params)
  end
  
  defp save_album(socket, :new, album_params) do
    case Photography.create_album(album_params) do
      {:ok, album} ->
        notify_parent({:saved, album})
        
        {:noreply,
         socket
         |> put_flash(:info, "Album créé avec succès")
         |> push_navigate(to: ~p"/admin/albums/#{album.id}/edit")}
      
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
  
  defp save_album(socket, :edit, album_params) do
    case Photography.update_album(socket.assigns.album, album_params) do
      {:ok, album} ->
        notify_parent({:saved, album})
        
        {:noreply,
         socket
         |> put_flash(:info, "Album mis à jour")
         |> push_navigate(to: ~p"/admin/albums")}
      
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
  
  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
  
  defp album_types do
    [
      {"Couples", "couples"},
      {"Mariage", "wedding"},
      {"Maternité", "motherhood"},
      {"Événements", "events"},
      {"Paysage", "landscape"},
      {"Street", "street"},
      {"Musique", "music"},
      {"Reconstitution", "reenactment"}
    ]
  end
end
```

2. **Template FormComponent** :
```heex
<div>
  <.header>
    <%= @title %>
  </.header>
  
  <.form for={@form} id="album-form" phx-target={@myself} phx-change="validate" phx-submit="save">
    <.input field={@form[:title]} type="text" label="Titre" />
    <.input field={@form[:type]} type="select" label="Type" options={@types} />
    <.input field={@form[:description]} type="textarea" label="Description" />
    <.input field={@form[:location]} type="text" label="Lieu" />
    <.input field={@form[:date_prise_vue]} type="date" label="Date de prise de vue" />
    <.input field={@form[:date_fin_prise_vue]} type="date" label="Date de fin (optionnel)" />
    <.input field={@form[:reference_link]} type="url" label="Lien de référence" />
    
    <:actions>
      <.button phx-disable-with="Enregistrement...">
        <%= if @action == :new, do: "Créer", else: "Mettre à jour" %>
      </.button>
    </:actions>
  </.form>
</div>
```

3. **Simplifier New LiveView** :
```elixir
# lib/portfolio_web/live/admin/album_live/new.ex
defmodule PortfolioWeb.Admin.AlbumLive.New do
  use PortfolioWeb, :live_view
  
  alias Portfolio.Photography.Album
  
  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :album, %Album{})}
  end
  
  @impl true
  def handle_info({FormComponent, {:saved, _album}}, socket) do
    {:noreply, socket}
  end
end
```

4. **Simplifier Edit LiveView** :
```elixir
# Similar simplification
```

**Checklist** :
- [ ] Créer FormComponent réutilisable
- [ ] Migrer New pour utiliser FormComponent
- [ ] Migrer Edit pour utiliser FormComponent
- [ ] Tests New (aucune régression)
- [ ] Tests Edit (aucune régression)
- [ ] Supprimer code dupliqué
- [ ] `mix credo --strict` → 0 duplication warnings
- [ ] `mix precommit` OK
- [ ] Commit : `refactor: Extract shared album form into reusable component`

**Estimation** : 2-3h

---

### Issue #76 : Implémenter structured logging avec metadata

**Problème** : Logs basiques sans contexte

**Solution** :

```elixir
# lib/portfolio/photography.ex
require Logger

def create_album(attrs) do
  Logger.metadata(action: :create_album, user_id: attrs[:user_id])
  
  case AlbumService.create_album(attrs) do
    {:ok, album} ->
      Logger.info("Album created successfully",
        album_id: album.id,
        slug: album.slug,
        type: album.type
      )
      {:ok, album}
    
    {:error, changeset} ->
      Logger.warning("Album creation failed",
        errors: format_changeset_errors(changeset)
      )
      {:error, changeset}
  end
end

defp format_changeset_errors(changeset) do
  Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
end
```

**Configuration** :
```elixir
# config/config.exs
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :action, :album_id]
```

**Checklist** :
- [ ] Ajouter Logger.metadata dans actions critiques
- [ ] Ajouter structured logging Photography
- [ ] Ajouter structured logging Auth
- [ ] Configurer metadata logger
- [ ] Tests : vérifier logs émis
- [ ] Documentation bonnes pratiques logging
- [ ] `mix precommit` OK
- [ ] Commit : `feat: Implement structured logging with metadata`

**Estimation** : 2h

---

## 📚 Règles de Travail

### Avant Chaque Issue

**OBLIGATOIRE** : Relire `docs/RULES.md` en entier

Points clés à vérifier :
- [ ] Je respecte DDD (Domain → Application → Infrastructure)
- [ ] Je respecte Clean Architecture (dépendances vers l'intérieur)
- [ ] Je respecte SOLID (surtout SRP, DIP)
- [ ] J'écris les tests AVANT ou EN PARALLÈLE du code (TDD)
- [ ] Je documente (@moduledoc, @doc, @spec)
- [ ] Je ne duplique pas le code (DRY)

### Pendant le Développement

1. **TDD strict** :
   - ❌ RED : Test qui échoue
   - ✅ GREEN : Implémentation minimale
   - ♻️ REFACTOR : Amélioration

2. **Documentation complète** :
   - @moduledoc sur tous les modules
   - @doc sur fonctions publiques
   - @spec pour Dialyzer
   - Exemples dans @doc si pertinent

3. **Tests exhaustifs** :
   - Happy path
   - Edge cases
   - Error cases
   - Objectif : > 80% coverage

### Avant Chaque Commit

**Checklist NON NÉGOCIABLE** :

- [ ] ✅ Tous les points de l'issue implémentés
- [ ] 🧪 Tests complets (happy + edge + erreurs)
- [ ] 🏗️ Architecture propre (DDD + Clean)
- [ ] 📐 Code propre (SOLID + Clean Code)
- [ ] ✔️ `mix precommit` passe (format + credo + test)
- [ ] 📝 Documentation complète
- [ ] 🚫 `.gitignore` N'EST PAS dans le commit
- [ ] 💬 Message commit descriptif

### Format des Commits

```
type: description courte (max 50 caractères)

- Détail 1
- Détail 2
- Détail 3

Issue #N
```

**Types** : `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`, `perf:`

**INTERDICTION** : Mentionner génération de code, Claude, Anthropic

---

## 📈 Progression

### Sprint 1 (Critiques)
- [ ] Issue #66 : FileStorage service
- [ ] Issue #67 : PhotoRepository.reorder avec Ecto.Multi
- [ ] Issue #68 : Fixtures maps → keyword lists

**Estimation totale** : 5-7h

### Sprint 2 (Importantes)
- [ ] Issue #69 : Domain Events
- [ ] Issue #70 : Value Object Slug
- [ ] Issue #71 : Telemetry
- [ ] Issue #72 : Dialyzer

**Estimation totale** : 9-12h

### Sprint 3 (Améliorations)
- [ ] Issue #73 : Query Objects
- [ ] Issue #74 : Email validation
- [ ] Issue #75 : Refactor duplications LiveView
- [ ] Issue #76 : Structured logging

**Estimation totale** : 8-10h

---

**ESTIMATION GLOBALE** : 22-29h

**Objectif final** : Score > 9/10 en respectant à 100% DDD, Clean Architecture et SOLID

---

**Dernière mise à jour** : 26 octobre 2025
