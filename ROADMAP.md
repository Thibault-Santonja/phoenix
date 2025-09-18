# Portfolio - Roadmap & Technical Debt

## 🔴 High Priority

### Issue #86 - Migrate hardcoded albums to database (3-4h)
**Status**: Todo  
**Category**: Data Migration  
**Impact**: Removes data duplication, centralizes album management

**Problem**:
- Timeline and Gallery LiveViews have hardcoded album data mixed with database albums
- Source of truth is unclear
- Double maintenance effort to update an album
- Risk of data desynchronization

**Files affected**:
- `lib/portfolio_web/live/photography_live/timeline.ex` (lines 22-215)
- `lib/portfolio_web/live/photography_live/gallery.ex` (lines 7-17, 23-45)

**Solution**:
1. Create migration script to import hardcoded albums into database
2. Remove `@data` module attribute from Timeline
3. Refactor Gallery to use `Photography.get_album_by_slug/2`
4. Add `get_album_by_slug/2` function to Photography context
5. Update tests

**Acceptance Criteria**:
- [ ] All hardcoded albums imported to DB
- [ ] Timeline uses only DB data
- [ ] Gallery uses only DB data
- [ ] Tests pass
- [ ] No breaking changes to URLs

---

### Issue #87 - Extract PhotoUpload and PhotoGrid LiveComponents (3-4h)
**Status**: Todo  
**Category**: Refactoring  
**Impact**: Improves maintainability, reduces God LiveView complexity

**Problem**:
- `AlbumLive.Edit` has too many responsibilities (150 lines, 10 handle_event callbacks)
- Complex state management (`:editing_photo`, `:photo_form`, `:reordering_mode`, `:temp_photo_order`)
- Difficult to test and maintain

**Files affected**:
- `lib/portfolio_web/live/admin/album_live/edit.ex`
- `lib/portfolio_web/live/admin/album_live/edit.html.heex`

**Solution**:
1. Create `PhotoUploadComponent` for photo upload logic
2. Create `PhotoGridComponent` for photo display + actions
3. Create `PhotoEditModal` component for individual photo editing
4. Create `PhotoReorderComponent` for drag & drop reordering
5. Update Edit LiveView to orchestrate components
6. Update template to use new components

**New files**:
- `lib/portfolio_web/live/admin/album_live/photo_upload_component.ex`
- `lib/portfolio_web/live/admin/album_live/photo_grid_component.ex`
- `lib/portfolio_web/live/admin/album_live/photo_edit_modal.ex`
- `lib/portfolio_web/live/admin/album_live/photo_reorder_component.ex`

**Acceptance Criteria**:
- [ ] Edit LiveView reduced to <80 lines
- [ ] Each component has single responsibility
- [ ] Photo upload works as before
- [ ] Photo editing works as before
- [ ] Photo reordering works as before
- [ ] Tests pass

---

### Issue #88 - Internationalize admin interface (1-2h)
**Status**: Todo  
**Category**: I18n  
**Impact**: Language consistency, enables multi-language admin

**Problem**:
- Admin interface has hardcoded French strings
- Inconsistent with rest of codebase (English)
- Cannot be internationalized

**Files affected**:
- `lib/portfolio_web/live/admin/album_live/form_component.ex`
- `lib/portfolio_web/live/admin/album_live/edit.html.heex`
- `lib/portfolio_web/live/admin/album_live/index.html.heex`
- `lib/portfolio_web/live/auth_live/login.html.heex`

**Solution**:
1. Replace all hardcoded strings with `gettext/1` calls
2. Add translations to `priv/gettext/*/LC_MESSAGES/default.po`
3. Update flash messages to use gettext

**Acceptance Criteria**:
- [ ] No hardcoded French strings in admin
- [ ] All strings use gettext
- [ ] French translations added
- [ ] English translations added
- [ ] Admin works in both languages

---

## 🟡 Medium Priority

### Issue #89 - Add telemetry helper to Service behaviour (1h)
**Status**: Todo  
**Category**: Code Quality  
**Impact**: Reduces code duplication (5 occurrences)

**Problem**:
- Pattern `start_time / result / duration / telemetry.execute` duplicated in all 5 services
- Violates DRY principle
- Harder to maintain consistent telemetry

**Files affected**:
- `lib/portfolio/services/service.ex`
- `lib/portfolio/services/photography/album_publication_service.ex`
- `lib/portfolio/services/photography/photo_upload_service.ex`
- `lib/portfolio/services/photography/album_deletion_service.ex`
- `lib/portfolio/services/auth/magic_link_auth_service.ex`

**Solution**:
1. Add `with_telemetry/3` macro to Service behaviour
2. Update all services to use the helper
3. Ensure telemetry events remain identical
4. Update tests if needed

**Acceptance Criteria**:
- [ ] `with_telemetry/3` helper implemented
- [ ] All 5 services refactored to use helper
- [ ] Telemetry events unchanged
- [ ] Tests pass
- [ ] No breaking changes

---

### Issue #90 - Optimize PhotoRepository.reorder/2 performance (2h)
**Status**: Todo  
**Category**: Performance  
**Impact**: N queries → 1 query for photo reordering

**Problem**:
- `reorder/2` executes N separate UPDATE queries for N photos
- For 100 photos = 100 queries
- Performance degradation on large albums

**File affected**:
- `lib/portfolio/photography/repositories/photo_repository.ex` (lines 132-142)

**Solution**:
Use Ecto fragments with CASE WHEN for single-query batch update:

```elixir
|> Multi.run(:reorder_photos, fn repo, %{validate_photos: _photos} ->
  now = DateTime.utc_now()
  
  # Build CASE WHEN expression for all photos at once
  case_expr = 
    Enum.with_index(photo_ids)
    |> Enum.reduce(dynamic([p], p.display_order), fn {photo_id, index}, acc ->
      dynamic([p], fragment("CASE WHEN ? = ? THEN ? ELSE ? END",
        p.id, ^photo_id, ^index, ^acc))
    end)
  
  {count, _} =
    from(p in Photo, where: p.id in ^photo_ids)
    |> repo.update_all(set: [display_order: case_expr, updated_at: now])
  
  {:ok, count}
end)
```

**Acceptance Criteria**:
- [ ] Single UPDATE query for all photos
- [ ] Functionality unchanged
- [ ] Tests pass
- [ ] Benchmark shows improvement for >20 photos

---

### Issue #91 - Add comprehensive tests for Query Objects (2-3h)
**Status**: Todo  
**Category**: Testing  
**Impact**: Increases confidence in refactoring, prevents regressions

**Problem**:
- Only `with_photo_count/1` and `with_cover_photo_only/1` have tests
- Other query functions (`by_type/2`, `published/1`, `unpublished/1`, `order_by_date_desc/1`) are untested
- No guarantee SQL queries are correct
- Risk of regression during refactoring

**File to update**:
- `test/portfolio/photography/queries/album_query_test.exs`

**Solution**:
Add test coverage for all AlbumQuery functions:
- `by_type/2` - test filtering by album type
- `published/1` - test filtering published albums
- `unpublished/1` - test filtering unpublished albums
- `order_by_date_desc/1` - test ordering by date
- `with_preload/2` - test preloading associations

**Acceptance Criteria**:
- [ ] 100% test coverage on AlbumQuery
- [ ] Each query function has at least 2 test cases
- [ ] Tests verify correct SQL generation
- [ ] Tests verify correct results
- [ ] All tests pass

---

## 🟢 Low Priority

### Issue #92 - Translate Photography context documentation to English (1h)
**Status**: Todo  
**Category**: Documentation  
**Impact**: Consistency, accessibility for international contributors

**Problem**:
- Photography context moduledoc is in French
- Rest of codebase (specs, comments) is in English
- Inconsistent documentation language

**File affected**:
- `lib/portfolio/photography.ex` (lines 1-35)

**Solution**:
1. Translate all French documentation to English
2. Keep French domain terms if they represent ubiquitous language
3. Update examples to use English descriptions

**Acceptance Criteria**:
- [ ] All documentation in English
- [ ] No French comments or docs remain
- [ ] Examples updated
- [ ] Ubiquitous language section remains clear

---

### Issue #93 - Centralize cache keys management (1h)
**Status**: Todo  
**Category**: Maintainability  
**Impact**: Better cache invalidation, more flexible cache strategy

**Problem**:
- Cache keys hardcoded in `Photography.invalidate_albums_cache/0`
- Only 2 specific cache keys invalidated
- New preload combinations not invalidated
- No central cache key management

**Files affected**:
- `lib/portfolio/photography.ex` (lines 106-107, 135-149)

**Solution**:
1. Create `Portfolio.CacheKeys` module
2. Centralize all cache key generation
3. Add function to list all matching cache keys
4. Update invalidation to use pattern matching

**New file**:
- `lib/portfolio/cache_keys.ex`

**Example**:
```elixir
defmodule Portfolio.CacheKeys do
  def published_albums_by_year(preloads \\ []) do
    {:published_albums_by_year, Enum.sort(preloads)}
  end
  
  def all_published_albums_keys do
    Cachex.keys!(:portfolio_cache)
    |> Enum.filter(&match?({:published_albums_by_year, _}, &1))
  end
end
```

**Acceptance Criteria**:
- [ ] CacheKeys module created
- [ ] All cache key generation centralized
- [ ] Invalidation uses pattern matching
- [ ] Tests pass
- [ ] Cache works as before

---

### Issue #94 - Add email validation to Login LiveView (30min)
**Status**: Todo  
**Category**: UX  
**Impact**: Better user experience, immediate feedback

**Problem**:
- No client-side validation before submitting email
- User waits for request to know if email is malformed
- Poor UX

**File affected**:
- `lib/portfolio_web/live/auth_live/login.ex`

**Solution**:
1. Add changeset for email validation
2. Add `phx-change="validate"` event
3. Show validation errors in real-time
4. Validate format before submitting

**Acceptance Criteria**:
- [ ] Email validation on input change
- [ ] Error displayed if invalid format
- [ ] Submit disabled if invalid
- [ ] Tests pass

---

### Issue #95 - Remove get_or_create_user/1 duplication (15min)
**Status**: Todo  
**Category**: Code Quality  
**Impact**: Removes duplication between Auth context and MagicLinkAuthService

**Problem**:
- `get_or_create_user/1` in Auth context
- `fetch_or_create_user/1` in MagicLinkAuthService (private)
- Same logic, different names
- Confusion about which to use

**File affected**:
- `lib/portfolio/auth.ex` (lines 37-62)

**Solution**:
Remove `get_or_create_user/1` from Auth context, keep only in service as private function.

**Acceptance Criteria**:
- [ ] `get_or_create_user/1` removed from Auth context
- [ ] Service continues using private `fetch_or_create_user/1`
- [ ] No breaking changes to public API
- [ ] Tests pass

---

### Issue #96 - Extract max filename length constant in LocalStorage (5min)
**Status**: Todo  
**Category**: Code Quality  
**Impact**: Removes magic number, adds clarity

**Problem**:
- `String.slice(0, 50)` hardcoded without explanation
- Magic number difficult to adjust if needed

**File affected**:
- `lib/portfolio/photography/storage/local_storage.ex` (line 91)

**Solution**:
```elixir
@max_filename_length 50  # Max base name length to prevent filesystem issues

defp build_filename(original_name, hash, extension) do
  base_name =
    original_name
    |> Path.rootname()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
    |> String.slice(0, @max_filename_length)
  # ...
end
```

**Acceptance Criteria**:
- [ ] Module attribute `@max_filename_length` added
- [ ] Magic number replaced
- [ ] Comment explains rationale
- [ ] Tests pass

---

---

## 🔴 HIGH PRIORITY (Suite - Issues post Code Review)

### Issue #97 - Mettre en place suite de tests complète (16-20h)
**Status**: Todo  
**Category**: Testing  
**Impact**: CRITIQUE - Permet refactoring en confiance, détecte régressions, garantit invariants

**Problem**:
- ❌ **Couverture actuelle : 0%**
- Aucun test unitaire sur domain models
- Aucun test d'intégration sur services
- Aucun test sur repositories
- Impossible de refactorer sans risque
- Violations d'invariants possibles non détectées

**Phase 1 - Tests Domain Models (6-8h)**:

Files to create:
- `test/portfolio/photography/album_test.exs`
- `test/portfolio/photography/photo_test.exs`
- `test/portfolio/photography/value_objects/slug_test.exs`
- `test/portfolio/auth/user_test.exs`
- `test/portfolio/auth/magic_link_test.exs`
- `test/portfolio/auth/user_session_test.exs`

Test coverage needed:
- Album changeset validations (date_not_future, date_range, required fields)
- Photo changeset validations (display_order, mime_type, slug generation)
- Slug normalization (accents, special chars, max length, edge cases)
- User email validation (format, uniqueness, normalization)
- MagicLink expired?/valid?/used? predicates
- UserSession expired? with different timestamps

**Phase 2 - Tests Services (4-6h)**:

Files to create:
- `test/portfolio/services/photography/album_publication_service_test.exs`
- `test/portfolio/services/photography/album_deletion_service_test.exs`
- `test/portfolio/services/photography/photo_upload_service_test.exs`
- `test/portfolio/services/auth/magic_link_auth_service_test.exs`

Test coverage needed:
- AlbumPublicationService: publishes album, emits event, invalidates cache
- AlbumDeletionService: deletes album + photos + files atomically
- PhotoUploadService: parallel uploads, partial failures, timeouts
- MagicLinkAuthService: rate limiting, user creation, token generation

**Phase 3 - Tests Repositories & Query Objects (3-4h)**:

Files to create:
- `test/portfolio/photography/repositories/album_repository_test.exs`
- `test/portfolio/photography/repositories/photo_repository_test.exs`

Test coverage needed:
- PhotoRepository.reorder/2 optimized (single UPDATE query)
- AlbumQuery functions composition
- Preloading strategies
- Pagination if implemented

**Phase 4 - Tests LiveViews (3-4h)**:

Files to create:
- `test/portfolio_web/live/admin/album_live/index_test.exs`
- `test/portfolio_web/live/admin/album_live/edit_test.exs`
- `test/portfolio_web/live/auth_live/login_test.exs`

Test coverage needed:
- Album CRUD operations through LiveView
- Photo upload and reordering
- Magic link login flow
- Authorization checks

**Acceptance Criteria**:
- [ ] ✅ Couverture >= 80% sur domain models
- [ ] ✅ Couverture >= 80% sur services
- [ ] ✅ Couverture >= 70% sur repositories
- [ ] ✅ Tests LiveViews critiques couverts
- [ ] ✅ `mix test` passe à 100%
- [ ] ✅ `mix coveralls` >= 75% overall

**Priority**: 🔴 URGENT - Blocage pour tout refactoring futur

---

### Issue #98 - Optimiser PhotoRepository.reorder (N+1 fix) (2-3h)
**Status**: Todo  
**Category**: Performance  
**Impact**: MAJEUR - O(n) queries → O(1), critique pour albums >50 photos

**Problem**:
- ❌ **100 photos = 100 requêtes UPDATE**
- Pattern N+1 dans `reorder/2` (lignes 136-147)
- Performance catastrophique sur gros albums
- Commentaire TODO dans le code reconnaît le problème

**Current Implementation**:
```elixir
# portfolio/photography/repositories/photo_repository.ex:136-147
Enum.reduce(fn {photo_id, index}, acc ->
  {count, _} =
    from(p in Photo, where: p.id == ^photo_id)
    |> repo.update_all(set: [display_order: index, updated_at: DateTime.utc_now()])
  acc + count
end)
```

**Solution - Single UPDATE with CASE WHEN**:
```elixir
|> Multi.run(:reorder_photos, fn repo, %{validate_photos: _photos} ->
  now = DateTime.utc_now()
  
  # Build parameterized query with CASE WHEN
  case_whens = 
    Enum.map_join(Enum.with_index(photo_ids), " ", fn {_id, idx} ->
      "WHEN id = $#{idx + 2} THEN #{idx}"
    end)
  
  query = """
  UPDATE photos
  SET 
    display_order = CASE #{case_whens} END,
    updated_at = $1
  WHERE id = ANY($#{length(photo_ids) + 2}::uuid[])
  """
  
  params = [now | photo_ids] ++ [photo_ids]
  
  case repo.query(query, params) do
    {:ok, %{num_rows: count}} -> {:ok, count}
    {:error, reason} -> {:error, reason}
  end
end)
```

**Benchmark Required**:
```elixir
# test/portfolio/photography/repositories/photo_repository_benchmark.exs
Benchee.run(%{
  "N queries (current)" => fn {album, photo_ids} ->
    PhotoRepository.reorder(album.id, photo_ids)
  end,
  "Single CASE WHEN (optimized)" => fn {album, photo_ids} ->
    PhotoRepository.reorder_optimized(album.id, photo_ids)
  end
}, inputs: %{
  "10 photos" => setup_album_with_photos(10),
  "50 photos" => setup_album_with_photos(50),
  "100 photos" => setup_album_with_photos(100),
  "500 photos" => setup_album_with_photos(500)
})
```

**Acceptance Criteria**:
- [ ] ✅ Single UPDATE query pour N photos
- [ ] ✅ Benchmark montre >80% amélioration pour 100+ photos
- [ ] ✅ Tests existants passent
- [ ] ✅ Nouveau test vérifie nombre de queries (QueryCounter)
- [ ] ✅ Pas de régression fonctionnelle

**Priority**: 🔴 URGENT - Impact performance critique

---

### Issue #99 - Ajouter index DB manquants (1-2h)
**Status**: Todo  
**Category**: Performance  
**Impact**: MAJEUR - Queries lentes sur albums.slug, published albums, sessions

**Problem**:
- ❌ `albums.slug` requêté sans index (Gallery lookup)
- ❌ `albums (published, date_prise_vue)` sans index composite (Timeline)
- ❌ `user_sessions.last_activity_at` sans index (cleanup job)
- ❌ `magic_links.expires_at` sans index (cleanup job)
- Queries lentes avec volumétrie croissante

**Current Queries Impacted**:
```elixir
# Sans index sur slug - O(n) table scan
Photography.get_album_by_slug("mariage-2024")

# Sans index composite - O(n) table scan + sort
Photography.list_published_albums_by_year()

# Sans index - O(n) table scan
Auth.delete_expired_sessions()
Auth.delete_expired_magic_links()
```

**Solution - Migration**:
```elixir
# priv/repo/migrations/YYYYMMDDHHMMSS_add_missing_indexes.exs
defmodule Portfolio.Repo.Migrations.AddMissingIndexes do
  use Ecto.Migration
  
  def change do
    # Index pour recherche par slug (Gallery)
    create_if_not_exists index(:albums, [:slug])
    
    # Index composite pour albums publiés par date (Timeline)
    # WHERE clause pour index partiel (plus petit, plus rapide)
    create_if_not_exists index(
      :albums, 
      [:published, :date_prise_vue], 
      where: "published = true",
      name: :albums_published_date_index
    )
    
    # Index pour cleanup des sessions expirées
    create_if_not_exists index(:user_sessions, [:last_activity_at])
    
    # Index pour cleanup des magic links expirés
    create_if_not_exists index(:magic_links, [:expires_at])
    
    # OPTIONNEL - Index GIN pour recherche full-text sur titres
    # Nécessite extension pg_trgm
    execute """
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE INDEX IF NOT EXISTS albums_title_trgm_idx 
    ON albums USING gin(title gin_trgm_ops);
    """, """
    DROP INDEX IF EXISTS albums_title_trgm_idx;
    DROP EXTENSION IF EXISTS pg_trgm;
    """
  end
end
```

**Benchmark Before/After**:
```elixir
# Créer 10,000 albums de test
albums = Enum.map(1..10_000, fn i ->
  create_album(title: "Album #{i}", slug: "album-#{i}", published: rem(i, 2) == 0)
end)

# BEFORE (sans index)
Benchee.run(%{
  "get_album_by_slug" => fn -> Photography.get_album_by_slug("album-5000") end,
  "list_published_albums_by_year" => fn -> Photography.list_published_albums_by_year() end
})

# Appliquer migration

# AFTER (avec index)
Benchee.run(%{
  "get_album_by_slug" => fn -> Photography.get_album_by_slug("album-5000") end,
  "list_published_albums_by_year" => fn -> Photography.list_published_albums_by_year() end
})
```

**Acceptance Criteria**:
- [ ] ✅ Migration créée et appliquée
- [ ] ✅ Index créés en dev, test, prod
- [ ] ✅ Queries utilisent les index (vérifier EXPLAIN ANALYZE)
- [ ] ✅ Benchmark montre amélioration significative
- [ ] ✅ Pas de régression fonctionnelle

**Priority**: 🔴 URGENT - Impact performance critique

---

## 🟡 MEDIUM PRIORITY (Suite - Issues post Code Review)

### Issue #100 - Implémenter event handlers réels (6-8h)
**Status**: Todo  
**Category**: Architecture  
**Impact**: IMPORTANT - Démontre pattern complet, ajoute features utiles

**Problem**:
- ⚠️ **Tous les event handlers sont des stubs**
- AlbumPublishedHandler : log seulement
- PhotoUploadedHandler : log seulement  
- MagicLinkHandler : log seulement
- Aucune logique métier réelle
- Pattern incomplet

**Phase 1 - PhotoUploadedHandler (4h)**:

Implémentation réelle:
```elixir
def handle_info({:photo_uploaded, %PhotoUploaded{} = event}, state) do
  try do
    photo = Photography.get_photo!(event.photo_id)
    
    # 1. Extraire métadonnées EXIF
    exif_data = extract_exif(event.file_path)
    Photography.update_photo(photo, %{exif_data: exif_data})
    
    # 2. Générer thumbnails (small, medium, large)
    generate_thumbnails(event.file_path, photo.id)
    
    # 3. Mettre à jour statistiques album
    update_album_stats(event.album_id)
    
    Logger.info("Photo processing completed", photo_id: event.photo_id)
    {:noreply, state}
  rescue
    error ->
      Logger.error("Photo processing failed", 
        error: inspect(error),
        photo_id: event.photo_id
      )
      DeadLetterQueue.push(:photo_processing_failed, event)
      {:noreply, state}
  end
end

defp extract_exif(file_path) do
  # Utiliser library Exiftool ou ExifReader
  case ExifReader.read(file_path) do
    {:ok, data} -> 
      %{
        camera: data["Make"],
        lens: data["LensModel"],
        iso: data["ISO"],
        aperture: data["FNumber"],
        shutter_speed: data["ExposureTime"],
        focal_length: data["FocalLength"]
      }
    {:error, _} -> %{}
  end
end

defp generate_thumbnails(file_path, photo_id) do
  sizes = [
    {300, 300, :small},
    {800, 800, :medium},
    {1920, 1920, :large}
  ]
  
  Enum.each(sizes, fn {width, height, size} ->
    dest = thumbnail_path(photo_id, size)
    ImageMagick.resize(file_path, dest, width: width, height: height)
  end)
end
```

Dependencies needed:
```elixir
# mix.exs
{:exif_reader, "~> 0.1.0"},  # EXIF extraction
{:mogrify, "~> 0.9.0"},      # ImageMagick wrapper
```

**Phase 2 - AlbumPublishedHandler (2h)**:

Implémentation:
```elixir
def handle_info({:album_published, %AlbumPublished{} = event}, state) do
  # 1. Invalider CDN cache si utilisé
  invalidate_cdn_cache(event.album_slug)
  
  # 2. Notifier services externes (Analytics, sitemap)
  notify_analytics(:album_published, event)
  regenerate_sitemap()
  
  # 3. Optionnel: Webhook pour notifications
  send_webhook(:album_published, event)
  
  {:noreply, state}
end
```

**Phase 3 - MagicLinkHandler (2h)**:

Implémentation:
```elixir
def handle_info({:magic_link_requested, %MagicLinkRequested{} = event}, state) do
  # 1. Envoyer email avec Swoosh
  email = 
    Email.new()
    |> Email.to(event.email)
    |> Email.from("noreply@portfolio.com")
    |> Email.subject("Lien de connexion")
    |> Email.html_body(render_magic_link_email(event))
  
  Mailer.deliver(email)
  
  # 2. Logger pour audit
  Logger.info("Magic link sent", email: event.email)
  
  {:noreply, state}
end
```

**Acceptance Criteria**:
- [ ] ✅ PhotoUploadedHandler extrait EXIF
- [ ] ✅ PhotoUploadedHandler génère thumbnails
- [ ] ✅ AlbumPublishedHandler invalide cache
- [ ] ✅ MagicLinkHandler envoie email
- [ ] ✅ Gestion d'erreur avec try/rescue
- [ ] ✅ Dead letter queue pour failures
- [ ] ✅ Tests pour chaque handler

**Priority**: 🟡 IMPORTANT - Ajoute valeur métier

---

### Issue #101 - Améliorer gestion d'erreurs dans services (3-4h)
**Status**: Todo  
**Category**: Reliability  
**Impact**: IMPORTANT - Garantit atomicité, évite états inconsistents

**Problem**:
- ⚠️ AlbumPublicationService : cache invalidation hors transaction
- ⚠️ PhotoUploadService : pas de rollback sur échec partiel
- ⚠️ LocalStorage : pas de vérification intégrité post-copie
- Risque d'états inconsistants (album publié mais cache stale)

**Solution 1 - AlbumPublicationService atomique**:

Current (problématique):
```elixir
with {:ok, album} <- AlbumRepository.update(album, %{published: true}) do
  invalidate_albums_cache()  # Hors transaction!
  DomainEvents.publish(...)
  {:ok, album}
end
```

Fixed (atomique):
```elixir
Ecto.Multi.new()
|> Ecto.Multi.update(:album, Album.changeset(album, %{published: true}))
|> Ecto.Multi.run(:cache, fn _repo, %{album: _album} ->
  case invalidate_albums_cache() do
    :ok -> {:ok, :ok}
    {:error, reason} -> {:error, reason}
  end
end)
|> Ecto.Multi.run(:event, fn _repo, %{album: album} ->
  DomainEvents.publish(:album_published, %AlbumPublished{...})
  {:ok, :ok}
end)
|> Repo.transaction()
|> case do
  {:ok, %{album: album}} -> {:ok, album}
  {:error, :album, changeset, _} -> {:error, changeset}
  {:error, _step, reason, _} -> {:error, reason}
end
```

**Solution 2 - PhotoUploadService avec rollback**:

Current (partial success):
```elixir
if Enum.all?(results, &match?({:ok, {:ok, _}}, &1)) do
  {:ok, photos_metadata}
else
  # Retourne erreur mais fichiers déjà uploadés restent
  {:error, first_error}
end
```

Fixed (rollback ou partial success explicite):
```elixir
{successes, failures} = partition_results(results)

cond do
  Enum.empty?(failures) ->
    {:ok, successes}
  
  Enum.empty?(successes) ->
    {:error, {:all_failed, failures}}
  
  true ->
    # Partial success - rollback ou continuer?
    case opts[:on_partial_failure] do
      :rollback ->
        # Supprimer fichiers uploadés avec succès
        Enum.each(successes, fn meta -> storage().delete_photo(meta.file_path) end)
        {:error, {:partial_failure_rollback, failures}}
      
      :keep ->
        # Garder succès, logger failures
        Logger.warning("Partial upload success", 
          successes: length(successes),
          failures: length(failures)
        )
        {:ok, {:partial, successes, failures}}
      
      _ ->
        # Default: rollback
        ...
    end
end
```

**Solution 3 - LocalStorage integrity check**:

```elixir
def store_photo(album_slug, upload) do
  with {:ok, hash} <- compute_hash(upload.path),
       {:ok, dest_path} <- build_destination_path(album_slug, upload, hash),
       :ok <- copy_file(upload.path, dest_path),
       :ok <- verify_integrity(dest_path, hash) do  # Nouveau!
    {:ok, %{file_path: public_path, hash: hash}}
  end
end

defp verify_integrity(path, expected_hash) do
  case compute_hash(path) do
    {:ok, ^expected_hash} -> :ok
    {:ok, actual_hash} -> 
      File.rm(path)  # Supprimer fichier corrompu
      {:error, {:integrity_check_failed, expected: expected_hash, actual: actual_hash}}
    error -> error
  end
end
```

**Acceptance Criteria**:
- [ ] ✅ AlbumPublicationService utilise Ecto.Multi
- [ ] ✅ PhotoUploadService gère partial failures proprement
- [ ] ✅ LocalStorage vérifie intégrité
- [ ] ✅ Tests vérifient atomicité
- [ ] ✅ Tests vérifient rollback sur erreur

**Priority**: 🟡 IMPORTANT - Garantit fiabilité

---

### Issue #102 - Optimiser AdminAlbumLive index (1-2h)
**Status**: Todo  
**Category**: Performance  
**Impact**: MOYEN - Réduit mémoire et queries sur index admin

**Problem**:
- ⚠️ `list_albums(preload: [:photos])` charge toutes les photos
- N+1 potentiel si 100 albums × 50 photos = 5000 photos en RAM
- Photos préchargées mais souvent inutilisées (juste le count affiché)

**Current Implementation**:
```elixir
# lib/portfolio_web/live/admin/album_live/index.ex:15
albums = Photography.list_albums(preload: [:photos])
```

**Solution - Utiliser photo_count**:
```elixir
# 1. Ajouter fonction au context
def list_albums_with_count(filters \\ []) do
  AlbumRepository.list(filters)
  |> Enum.map(fn album ->
    count = Repo.one(from p in Photo, where: p.album_id == ^album.id, select: count())
    %{album | photo_count: count}
  end)
end

# Mieux: utiliser Query Object
def list_albums_with_count(filters \\ []) do
  AlbumQuery.base()
  |> AlbumQuery.with_photo_count()
  |> apply_filters(filters)
  |> Repo.all()
end

# 2. Utiliser dans LiveView
albums = Photography.list_albums_with_count()
```

**Alternative - LiveView Streams**:
```elixir
def mount(_params, _session, socket) do
  albums = Photography.list_albums_with_count()
  
  {:ok,
   socket
   |> assign(:page_title, "Albums")
   |> stream(:albums, albums)}
end

def handle_event("delete", %{"id" => id}, socket) do
  album = Photography.get_album!(id)
  
  case Photography.delete_album(album) do
    {:ok, _} ->
      {:noreply,
       socket
       |> stream_delete(:albums, album)
       |> put_flash(:info, "Album supprimé")}
    # ...
  end
end
```

Template:
```heex
<div id="albums" phx-update="stream">
  <div :for={{id, album} <- @streams.albums} id={id}>
    <h3>{album.title}</h3>
    <p>{album.photo_count} photos</p>
  </div>
</div>
```

**Acceptance Criteria**:
- [ ] ✅ Utilise photo_count au lieu de preload photos
- [ ] ✅ Streams pour updates incrémentales
- [ ] ✅ Mémoire réduite (vérifier avec Observer)
- [ ] ✅ Fonctionnalité identique
- [ ] ✅ Tests passent

**Priority**: 🟡 MOYEN - Optimisation UX admin

---

## 🟢 LOW PRIORITY (Suite - Issues post Code Review)

### Issue #103 - Ajouter pagination aux repositories (2-3h)
**Status**: Todo  
**Category**: Scalability  
**Impact**: FAIBLE - Prépare volumétrie future (>1000 albums)

**Problem**:
- `list/1` ramène tous les albums sans limite
- OK pour <100 albums
- Problème si volumétrie augmente (>1000 albums)

**Solution - Scrivener ou pagination manuelle**:

Option 1 - Scrivener:
```elixir
# mix.exs
{:scrivener_ecto, "~> 2.7"}

# Repository
def list_paginated(filters \\ [], page: page, page_size: page_size) do
  AlbumQuery.base()
  |> apply_filters(filters)
  |> Repo.paginate(page: page, page_size: page_size)
end
```

Option 2 - Pagination manuelle:
```elixir
def list_paginated(filters \\ [], opts \\ []) do
  page = Keyword.get(opts, :page, 1)
  page_size = Keyword.get(opts, :page_size, 20)
  
  query = 
    AlbumQuery.base()
    |> apply_filters(filters)
    |> limit(^page_size)
    |> offset(^((page - 1) * page_size))
  
  albums = Repo.all(query)
  total = Repo.one(from a in Album, select: count())
  
  %{
    albums: albums,
    page: page,
    page_size: page_size,
    total: total,
    total_pages: ceil(total / page_size)
  }
end
```

**Acceptance Criteria**:
- [ ] Pagination ajoutée aux repositories
- [ ] LiveView index utilise pagination
- [ ] Navigation page précédente/suivante
- [ ] Tests passent

**Priority**: 🟢 FAIBLE - Nice to have

---

### Issue #104 - Configuration runtime (1-2h)
**Status**: Todo  
**Category**: Flexibility  
**Impact**: FAIBLE - Améliore configurabilité

**Problem**:
- RateLimiter limits hardcodées
- Slug max_length hardcodé
- Pas configurable sans recompilation

**Solution**:
```elixir
# config/runtime.exs
config :portfolio, Portfolio.RateLimiter,
  magic_link_request: {5, :timer.hours(1)},
  photo_upload: {100, :timer.hours(1)}

config :portfolio, Portfolio.Photography.ValueObjects.Slug,
  max_length: 100

# Modules
defp get_limit(action) do
  limits = Application.get_env(:portfolio, Portfolio.RateLimiter)
  Keyword.get(limits, action, @default_limits[action])
end

defp max_length do
  Application.get_env(:portfolio, Portfolio.Photography.ValueObjects.Slug)[:max_length] || 100
end
```

**Acceptance Criteria**:
- [ ] Configuration via runtime.exs
- [ ] Pas de recompilation nécessaire
- [ ] Tests passent

**Priority**: 🟢 FAIBLE - Nice to have

---

### Issue #105 - Health check endpoint + monitoring (2-3h)
**Status**: Todo  
**Category**: Observability  
**Impact**: FAIBLE - Utile pour Kubernetes/monitoring

**Problem**:
- Pas d'endpoint /health
- Kubernetes readiness/liveness probes manquantes
- Monitoring difficile

**Solution**:
```elixir
# lib/portfolio_web/controllers/health_controller.ex
defmodule PortfolioWeb.HealthController do
  use PortfolioWeb, :controller
  
  def index(conn, _params) do
    checks = %{
      database: check_database(),
      cache: check_cache(),
      pubsub: check_pubsub(),
      storage: check_storage()
    }
    
    status = if Enum.all?(checks, fn {_k, v} -> v == :ok end), do: :ok, else: :error
    
    json(conn, %{
      status: status,
      checks: checks,
      timestamp: DateTime.utc_now()
    })
  end
  
  defp check_database do
    case Repo.query("SELECT 1") do
      {:ok, _} -> :ok
      _ -> :error
    end
  end
  
  defp check_cache do
    case Cachex.set(:portfolio_cache, :health_check, true, ttl: 1000) do
      {:ok, _} -> :ok
      _ -> :error
    end
  end
end

# Router
scope "/", PortfolioWeb do
  get "/health", HealthController, :index
end
```

**Acceptance Criteria**:
- [ ] Endpoint /health retourne status
- [ ] Vérifie DB, cache, PubSub, storage
- [ ] Kubernetes probes configurées
- [ ] Tests passent

**Priority**: 🟢 FAIBLE - Ops nice to have

---

## 📊 Summary (Updated)

### Par Priorité
- **🔴 High Priority**: 6 issues (27-35h total)
  - #86-88: Issues originales (8-10h)
  - #97-99: Issues post code review URGENT (19-25h)

- **🟡 Medium Priority**: 6 issues (14-18h total)
  - #89-91: Issues originales (5-6h)
  - #100-102: Issues post code review IMPORTANT (10-14h)

- **🟢 Low Priority**: 8 issues (8-13h total)
  - #92-96: Issues originales (3-4h)
  - #103-105: Issues post code review (5-9h)

### Par Catégorie
- **Testing**: 2 issues (#91, #97) - 18-23h - 🔴 CRITIQUE
- **Performance**: 4 issues (#90, #98, #99, #102) - 6-9h - 🔴 URGENT
- **Architecture**: 3 issues (#87, #100, #101) - 12-16h - 🟡 IMPORTANT
- **Code Quality**: 3 issues (#89, #95, #96) - 1.5-2h - 🟡 MOYEN
- **I18n**: 2 issues (#88, #92) - 2-3h - 🟢 FAIBLE
- **Scalability**: 2 issues (#103, #104) - 3-5h - 🟢 FAIBLE
- **Data**: 1 issue (#86) - 3-4h - 🔴 IMPORTANT
- **Maintainability**: 1 issue (#93) - 1h - 🟢 FAIBLE
- **UX**: 1 issue (#94) - 30min - 🟢 FAIBLE
- **Observability**: 1 issue (#105) - 2-3h - 🟢 FAIBLE

**Total Estimated Effort**: 49-66 hours

### Roadmap Recommandé

**Sprint 1 (1 semaine) - CRITIQUE**:
1. #97 - Tests complets (priorité absolue)
2. #98 - Fix N+1 PhotoRepository
3. #99 - Index DB

**Sprint 2 (1 semaine) - IMPORTANT**:
4. #100 - Event handlers réels
5. #101 - Gestion d'erreurs services
6. #86 - Migration hardcoded albums

**Sprint 3 (3-4 jours) - AMÉLIORATIONS**:
7. #87 - Extract LiveComponents
8. #89 - Telemetry helper (déjà fait ✅)
9. #91 - Query Objects tests (déjà fait ✅)

**Sprint 4 (2-3 jours) - POLISH**:
10. #88 - i18n admin
11. #102 - Optimiser AdminAlbumLive
12. Issues restantes selon besoin

---

## 🔴 HIGH PRIORITY (Suite - Issues Frontend post Code Review)

### Issue #106 - Retirer scripts inline et migrer vers hooks JS (2-3h)
**Status**: Todo  
**Category**: Frontend / Best Practices  
**Impact**: URGENT - Violation des guidelines Phoenix, risque sécurité CSP

**Problem**:
- ❌ **Scripts `<script>` inline dans templates HEEx**
- Violation des best practices Phoenix/LiveView
- Incompatible avec Content Security Policy (CSP)
- Code JavaScript non réutilisable
- Difficile à tester

**Files affected**:
- `lib/portfolio_web/live/amvcc_live/blog.html.heex` (lignes 13-52)
- `lib/portfolio_web/live/amvcc_live/index.html.heex` (lignes 13-52)

**Current Implementation (INCORRECT)**:
```heex
<script>
  document.addEventListener('DOMContentLoaded', function() {
    // Parallax effect for background image
    window.addEventListener('scroll', function() {
      const scrolled = window.pageYOffset;
      const parallax = document.querySelector('#hero img');
      const speed = scrolled * 0.5;

      if (parallax) {
        parallax.style.transform = `translateY(${speed}px)`;
      }
    });
  });
</script>
```

**Solution - Migrer vers Phoenix Hooks**:

1. Créer le hook dans `assets/js/hooks.js`:
```javascript
export const ParallaxHero = {
  mounted() {
    this.handleScroll = () => {
      const scrolled = window.pageYOffset;
      const img = this.el.querySelector('img');
      if (img) {
        img.style.transform = `translateY(${scrolled * 0.5}px)`;
      }
    };
    
    window.addEventListener('scroll', this.handleScroll, { passive: true });
  },
  
  destroyed() {
    window.removeEventListener('scroll', this.handleScroll);
  }
};
```

2. Enregistrer dans `assets/js/app.js`:
```javascript
import { ParallaxHero } from "./hooks"

let Hooks = {
  // ... existing hooks
  ParallaxHero
}
```

3. Utiliser dans le template:
```heex
<article id="hero" phx-hook="ParallaxHero" phx-update="ignore" class="...">
  <img src="..." alt="..." />
</article>
```

**Acceptance Criteria**:
- [ ] ✅ Tous les `<script>` inline retirés
- [ ] ✅ Hooks JavaScript créés dans `assets/js/hooks.js`
- [ ] ✅ Templates utilisent `phx-hook`
- [ ] ✅ Fonctionnalité identique (parallax fonctionne)
- [ ] ✅ Pas de warnings CSP
- [ ] ✅ Code JavaScript testable

**Priority**: 🔴 URGENT - Violation best practices

---

### Issue #107 - Retirer console.log() de production (30min)
**Status**: Todo  
**Category**: Frontend / Code Quality  
**Impact**: URGENT - Pollution logs navigateur, fuite d'informations

**Problem**:
- ❌ **6+ `console.log()` dans `hooks.js`**
- Logs visibles en production
- Pollution de la console navigateur
- Potentielle fuite d'informations sensibles

**File affected**:
- `assets/js/hooks.js` (lignes 372, 376, 378, 382, 400, 410)

**Current Implementation**:
```javascript
export const PhotoSortable = {
  mounted() {
    console.log("PhotoSortable mounted", this.el);  // ❌
    // ...
  },
  
  updated() {
    console.log("PhotoSortable updated", {  // ❌
      reordering: this.el.dataset.reordering,
    });
  }
}
```

**Solution - Logging conditionnel**:

```javascript
// En haut de hooks.js
const isDev = process.env.NODE_ENV === 'development';
const log = isDev ? console.log.bind(console) : () => {};
const warn = isDev ? console.warn.bind(console) : () => {};
const error = console.error.bind(console); // Toujours logger les erreurs

export const PhotoSortable = {
  mounted() {
    log("PhotoSortable mounted", this.el);
    // ...
  },
  
  updated() {
    log("PhotoSortable updated", {
      reordering: this.el.dataset.reordering,
    });
  },
  
  handleError(err) {
    error("PhotoSortable error:", err); // ✅ Toujours logger
  }
}
```

**Acceptance Criteria**:
- [ ] ✅ Tous les `console.log()` remplacés par `log()`
- [ ] ✅ Logger conditionnel implémenté
- [ ] ✅ Aucun log en production (vérifier build)
- [ ] ✅ Logs visibles en développement
- [ ] ✅ Erreurs toujours loggées

**Priority**: 🔴 URGENT - Qualité code

---

## 🟡 MEDIUM PRIORITY (Suite - Issues Frontend)

### Issue #108 - Ajouter attributs alt sur images (1-2h)
**Status**: Todo  
**Category**: Frontend / Accessibilité  
**Impact**: IMPORTANT - A11y, SEO, conformité WCAG

**Problem**:
- ⚠️ **30+ images sans attribut `alt` ou avec `alt=""` vide**
- Non-conformité WCAG 2.1 niveau A
- Mauvais pour SEO
- Utilisateurs de screen readers ne peuvent pas comprendre le contenu

**Files affected**:
- `lib/portfolio_web/live/amvcc_live/index.html.heex` (lignes 20, 288, etc.)
- `lib/portfolio_web/live/photography_live/timeline.html.heex`
- `lib/portfolio_web/live/photography_live/gallery.html.heex`
- Tous les templates avec images

**Current Implementation (INCORRECT)**:
```heex
<img
  src="https://www.amvcc.com/wp-content/uploads/2024/09/IMG_0697-1536x1024.jpg"
  loading="lazy"
/>
```

**Solution**:
```heex
<img
  src="https://www.amvcc.com/wp-content/uploads/2024/09/IMG_0697-1536x1024.jpg"
  alt={gettext("AMVCC Seigneuriales de Coucy 2024 - Medieval reenactment event with knights in armor")}
  loading="lazy"
/>
```

**Guidelines pour alt text**:
- Décrire le contenu de l'image de façon concise
- Inclure le contexte si pertinent
- Utiliser gettext pour internationalisation
- Images décoratives: `alt=""` (explicite)
- Portraits: `alt={gettext("Portrait of %{name}", name: @album.title)}`

**Acceptance Criteria**:
- [ ] ✅ Toutes les images ont un attribut `alt`
- [ ] ✅ Descriptions pertinentes et contextuelles
- [ ] ✅ Utilisation de gettext pour i18n
- [ ] ✅ Images décoratives avec `alt=""` explicite
- [ ] ✅ Validation avec axe DevTools
- [ ] ✅ Score Lighthouse Accessibility > 90

**Priority**: 🟡 IMPORTANT - Accessibilité critique

---

### Issue #109 - Traduire interface admin avec gettext (2-3h)
**Status**: Todo  
**Category**: Frontend / i18n  
**Impact**: IMPORTANT - Cohérence linguistique, i18n complète

**Problem**:
- ⚠️ **Interface admin entièrement en français hardcodé**
- Inconsistant avec le reste de l'app (gettext partout)
- Impossible de passer en anglais
- Strings non réutilisables

**Files affected**:
- `lib/portfolio_web/live/admin/album_live/edit.html.heex`
- `lib/portfolio_web/live/admin/album_live/index.html.heex`
- `lib/portfolio_web/live/admin/album_live/form_component.ex`
- `lib/portfolio_web/live/admin/profile_live/edit.html.heex`

**Current Implementation (INCORRECT)**:
```heex
<h2 class="text-xl font-semibold mb-4">Informations du compte</h2>
<p class="text-gray-600 mb-6">Gérez vos informations personnelles</p>
<button type="submit">Enregistrer les modifications</button>
```

**Solution**:
```heex
<h2 class="text-xl font-semibold mb-4">{gettext("Account information")}</h2>
<p class="text-gray-600 mb-6">{gettext("Manage your personal information")}</p>
<button type="submit">{gettext("Save changes")}</button>
```

**Étapes**:
1. Identifier tous les strings hardcodés
2. Remplacer par `gettext/1` ou `dgettext/2`
3. Ajouter traductions dans `priv/gettext/fr/LC_MESSAGES/default.po`
4. Ajouter traductions dans `priv/gettext/en/LC_MESSAGES/default.po`
5. Tester switch langue

**Acceptance Criteria**:
- [ ] ✅ Aucun string français hardcodé dans admin
- [ ] ✅ Tous les textes utilisent gettext
- [ ] ✅ Traductions FR complètes
- [ ] ✅ Traductions EN complètes
- [ ] ✅ Switch langue fonctionne
- [ ] ✅ Cohérence avec reste de l'app

**Priority**: 🟡 IMPORTANT - Cohérence i18n

---

### Issue #110 - Créer LocaleHook pour éviter duplication (1h)
**Status**: Todo  
**Category**: Frontend / Code Quality  
**Impact**: IMPORTANT - DRY, maintenabilité

**Problem**:
- ⚠️ **Code dupliqué dans tous les LiveViews**
- Pattern `Gettext.put_locale` répété 20+ fois
- Violation du principe DRY
- Difficile à maintenir

**Files affected**:
- Tous les LiveViews (20+ fichiers)

**Current Implementation (DUPLICATED)**:
```elixir
defmodule PortfolioWeb.TechLive.Index do
  use PortfolioWeb, :live_view
  
  def mount(_, session, socket) do
    Gettext.put_locale(PortfolioWeb.Gettext, session["locale"])  # ❌ Dupliqué
    {:ok, socket}
  end
end
```

**Solution - Créer hook réutilisable**:

1. Créer `lib/portfolio_web/live/locale_hook.ex`:
```elixir
defmodule PortfolioWeb.LocaleHook do
  @moduledoc """
  Hook LiveView pour gérer la locale automatiquement.
  
  Configure la locale Gettext basée sur la session utilisateur.
  Fallback sur "fr" si locale non définie.
  
  ## Usage
  
      defmodule MyLiveView do
        use PortfolioWeb, :live_view
        
        on_mount PortfolioWeb.LocaleHook
      end
  """
  
  import Phoenix.LiveView
  
  def on_mount(:default, _params, session, socket) do
    locale = session["locale"] || "fr"
    Gettext.put_locale(PortfolioWeb.Gettext, locale)
    {:cont, assign(socket, :locale, locale)}
  end
end
```

2. Utiliser dans les LiveViews:
```elixir
defmodule PortfolioWeb.TechLive.Index do
  use PortfolioWeb, :live_view
  
  on_mount PortfolioWeb.LocaleHook  # ✅ Une seule ligne
  
  def mount(_, _, socket) do
    # Locale déjà configurée
    {:ok, socket}
  end
end
```

3. Optionnel - Ajouter au `live_view` helpers dans `portfolio_web.ex`:
```elixir
def live_view do
  quote do
    use Phoenix.LiveView
    on_mount PortfolioWeb.LocaleHook  # ✅ Automatique pour tous
    # ...
  end
end
```

**Acceptance Criteria**:
- [ ] ✅ `LocaleHook` module créé
- [ ] ✅ Tous les LiveViews refactorés pour utiliser le hook
- [ ] ✅ Code dupliqué éliminé
- [ ] ✅ Locale correctement configurée partout
- [ ] ✅ Tests passent
- [ ] ✅ Documentation moduledoc complète

**Priority**: 🟡 IMPORTANT - Refactoring DRY

---

## 🟢 LOW PRIORITY (Suite - Issues Frontend)

### Issue #111 - Améliorer loading states sur formulaires (2-3h)
**Status**: Todo  
**Category**: Frontend / UX  
**Impact**: FAIBLE - Améliore UX, feedback utilisateur

**Problem**:
- Pas d'indicateurs de chargement visuels
- Utilisateur ne sait pas si action en cours
- Boutons cliquables pendant soumission
- Peut causer double-soumission

**Files affected**:
- `lib/portfolio_web/live/admin/album_live/edit.html.heex`
- `lib/portfolio_web/live/admin/album_live/form_component.ex`
- `lib/portfolio_web/live/auth_live/login.html.heex`
- Tous les formulaires

**Current Implementation**:
```heex
<.button type="submit">
  Enregistrer
</.button>
```

**Solution - Loading states**:
```heex
<.button 
  type="submit"
  phx-disable-with={gettext("Saving...")}
  class="relative group"
>
  <span class="phx-submit-loading:opacity-0 transition-opacity">
    {gettext("Save")}
  </span>
  <.icon 
    name="hero-arrow-path" 
    class="absolute inset-0 m-auto hidden phx-submit-loading:block h-5 w-5 animate-spin" 
  />
</.button>
```

**Améliorations supplémentaires**:
- Désactiver inputs pendant soumission
- Griser le formulaire
- Afficher progress bar pour uploads
- Toast notifications après succès

**Acceptance Criteria**:
- [ ] ✅ Tous les boutons submit ont `phx-disable-with`
- [ ] ✅ Spinner visible pendant soumission
- [ ] ✅ Bouton désactivé pendant traitement
- [ ] ✅ Feedback visuel clair
- [ ] ✅ Pas de double-soumission possible

**Priority**: 🟢 FAIBLE - Nice to have UX

---

### Issue #112 - Optimiser images hero (eager loading) (1h)
**Status**: Todo  
**Category**: Frontend / Performance  
**Impact**: FAIBLE - Améliore LCP, Core Web Vitals

**Problem**:
- Images hero/critiques en `loading="lazy"`
- Retarde affichage première vue
- Mauvais score LCP (Largest Contentful Paint)
- Impact négatif SEO

**Files affected**:
- `lib/portfolio_web/live/index.html.heex`
- `lib/portfolio_web/live/photography_live/index.html.heex`
- Toutes les pages avec images au-dessus du fold

**Current Implementation (INCORRECT)**:
```heex
<img
  srcset="/images/photography/street_640.webp 320w, ..."
  src="/images/photography/street_960.webp"
  loading="lazy"  <!-- ❌ Mauvais pour hero image -->
  alt="Street photography"
/>
```

**Solution**:
```heex
<img
  srcset="/images/photography/street_640.webp 320w, ..."
  src="/images/photography/street_960.webp"
  loading="eager"
  fetchpriority="high"
  alt="Street photography"
/>
```

**Bonus - Preload dans layout**:
```heex
<!-- lib/portfolio_web/components/layouts/root.html.heex -->
<link 
  rel="preload" 
  as="image" 
  href="/images/photography/street_960.webp"
  imagesrcset="/images/photography/street_640.webp 320w, ..."
/>
```

**Acceptance Criteria**:
- [ ] ✅ Images hero utilisent `loading="eager"`
- [ ] ✅ Attribut `fetchpriority="high"` ajouté
- [ ] ✅ Preload des images critiques (optionnel)
- [ ] ✅ Score LCP < 2.5s (Google PageSpeed)
- [ ] ✅ Pas de régression sur autres images

**Priority**: 🟢 FAIBLE - Optimisation performance

---

### Issue #113 - Ajouter tests frontend LiveView (4-6h)
**Status**: Todo  
**Category**: Frontend / Testing  
**Impact**: FAIBLE - Prévention régressions, confiance refactoring

**Problem**:
- ❌ **Aucun test frontend LiveView**
- Impossible de détecter régressions UI
- Refactoring risqué
- Pas de garantie que features fonctionnent

**Phase 1 - Tests Navigation (2h)**:

Files to create:
- `test/portfolio_web/live/photography_live/timeline_test.exs`
- `test/portfolio_web/live/photography_live/gallery_test.exs`

Test coverage:
- Navigation entre pages
- Affichage albums par année
- Ouverture modal photos
- Filtres par type

**Phase 2 - Tests Interaction (2h)**:

Files to create:
- `test/portfolio_web/live/admin/album_live/edit_test.exs`
- `test/portfolio_web/live/admin/album_live/index_test.exs`

Test coverage:
- Upload photos
- Réorganisation drag & drop
- Édition métadonnées
- Suppression album

**Phase 3 - Tests Accessibilité (1-2h)**:

Test coverage:
- Présence attributs ARIA
- Navigation clavier
- Labels formulaires
- Semantic HTML

**Exemple de test**:
```elixir
defmodule PortfolioWeb.PhotographyLive.TimelineTest do
  use PortfolioWeb.ConnCase, async: true
  
  import Phoenix.LiveViewTest
  
  test "displays published albums by year", %{conn: conn} do
    album_2024 = insert(:album, published: true, date_prise_vue: ~D[2024-06-15])
    album_2023 = insert(:album, published: true, date_prise_vue: ~D[2023-08-20])
    
    {:ok, view, html} = live(conn, ~p"/photography")
    
    assert html =~ "2024"
    assert html =~ "2023"
    assert has_element?(view, "#album-#{album_2024.id}")
    assert has_element?(view, "#album-#{album_2023.id}")
  end
  
  test "opens photo modal on click", %{conn: conn} do
    album = insert(:album, :with_photos, published: true)
    photo = List.first(album.photos)
    
    {:ok, view, _html} = live(conn, ~p"/photography")
    
    view
    |> element("#photo-#{photo.id}")
    |> render_click()
    
    assert has_element?(view, "#photo-modal")
    assert has_element?(view, "img[src*='#{photo.file_path}']")
  end
end
```

**Acceptance Criteria**:
- [ ] ✅ Tests navigation principales routes
- [ ] ✅ Tests interactions utilisateur
- [ ] ✅ Tests formulaires admin
- [ ] ✅ Tests accessibilité basiques
- [ ] ✅ Couverture > 60% sur LiveViews
- [ ] ✅ Tous les tests passent

**Priority**: 🟢 FAIBLE - Amélioration qualité

---

## 📊 Summary (Updated avec Frontend)

### Par Priorité
- **🔴 High Priority**: 8 issues (32-43h total)
  - #86-88: Issues originales (8-10h)
  - #97-99: Issues backend URGENT (19-25h)
  - #106-107: Issues frontend URGENT (2.5-3.5h)

- **🟡 Medium Priority**: 9 issues (21-29h total)
  - #89-91: Issues originales (5-6h)
  - #100-102: Issues backend IMPORTANT (10-14h)
  - #108-110: Issues frontend IMPORTANT (4-6h)

- **🟢 Low Priority**: 11 issues (15-22h total)
  - #92-96: Issues originales (3-4h)
  - #103-105: Issues backend (5-9h)
  - #111-113: Issues frontend (7-10h)

### Par Catégorie
- **Testing**: 3 issues (#91, #97, #113) - 22-29h - 🔴 CRITIQUE
- **Performance**: 5 issues (#90, #98, #99, #102, #112) - 7-10h - 🔴 URGENT
- **Architecture**: 3 issues (#87, #100, #101) - 12-16h - 🟡 IMPORTANT
- **Frontend/Best Practices**: 2 issues (#106, #107) - 2.5-3.5h - 🔴 URGENT
- **Accessibilité**: 1 issue (#108) - 1-2h - 🟡 IMPORTANT
- **i18n**: 3 issues (#88, #92, #109) - 4-6h - 🟡 IMPORTANT
- **Code Quality**: 4 issues (#89, #95, #96, #110) - 2.5-3h - 🟡 MOYEN
- **UX**: 2 issues (#94, #111) - 2.5-3.5h - 🟢 FAIBLE
- **Scalability**: 2 issues (#103, #104) - 3-5h - 🟢 FAIBLE
- **Data**: 1 issue (#86) - 3-4h - 🔴 IMPORTANT
- **Maintainability**: 1 issue (#93) - 1h - 🟢 FAIBLE
- **Observability**: 1 issue (#105) - 2-3h - 🟢 FAIBLE

**Total Estimated Effort**: 68-94 heures (3-4 semaines à temps plein)

### Roadmap Recommandé (Updated)

**Sprint 1 (1 semaine) - CRITIQUE** :
1. #97 - Tests backend complets (priorité absolue) - 16-20h
2. #106 - Retirer scripts inline (frontend) - 2-3h
3. #107 - Retirer console.log() (frontend) - 30min
4. #98 - Fix N+1 PhotoRepository - 2-3h
5. #99 - Index DB - 1-2h

**Sprint 2 (1 semaine) - IMPORTANT** :
6. #100 - Event handlers réels - 6-8h
7. #101 - Gestion d'erreurs services - 3-4h
8. #108 - Attributs alt images (a11y) - 1-2h
9. #109 - Traduire admin (i18n) - 2-3h
10. #110 - LocaleHook refactoring - 1h

**Sprint 3 (3-4 jours) - AMÉLIORATIONS** :
11. #86 - Migration hardcoded albums - 3-4h
12. #87 - Extract LiveComponents - 3-4h
13. #102 - Optimiser AdminAlbumLive - 1-2h
14. #88 - i18n admin (si pas fait) - 1-2h

**Sprint 4 (2-3 jours) - POLISH** :
15. #111 - Loading states - 2-3h
16. #112 - Optimiser images hero - 1h
17. #113 - Tests frontend - 4-6h
18. Issues restantes selon priorité

**Next Steps**:
1. **COMMENCER PAR #97** (tests backend) - Blocage pour tout le reste
2. **PUIS #106 et #107** (scripts inline + console.log) - Quick wins frontend
3. Créer feature branches: `issue/97-comprehensive-tests`, `issue/106-remove-inline-scripts`, etc.
4. Run `mix test` après chaque change
5. Run `mix precommit` avant merge
6. Mettre à jour ce roadmap au fur et à mesure

### Scores Actuels (Post Review Complète)

**Backend** : 8.5/10 (architecture) → 6.4/10 (réel avec tests à 0%)  
**Frontend** : 7.5/10 (global)

**Score Global Projet** : **7.0/10**

**Potentiel avec tous les fixes** : **8.8/10** ⭐⭐⭐⭐⭐
