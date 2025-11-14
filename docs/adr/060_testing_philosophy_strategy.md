# ADR-060: Philosophie et Stratégie de Testing

Statut: Accepté  
Date: 2025-11-11

## Contexte

Les tests automatisés sont essentiels pour garantir la qualité, la maintenabilité et la confiance dans le code. Cependant, toutes les stratégies de testing ne se valent pas : certaines maximisent la confiance tout en minimisant la maintenance, d'autres créent des tests fragiles qui cassent à chaque refactoring.

### Problématique

**Voir aussi** : ADR-061 (Precommit Quality Gates) pour l'automatisation de l'exécution des tests

Choix critiques en stratégie de testing :

Que tester ?
- Tester l'implémentation (modules internes, fonctions privées) ?
- Tester l'interface (API publique, comportement observable) ?

À quel niveau ?
- Tests unitaires (fonctions isolées) ?
- Tests d'intégration (modules combinés) ?
- Tests end-to-end (workflow complet) ?

Comment maintenir ?
- Tests couplés à l'implémentation (fragiles au refactoring) ?
- Tests découplés (résistants au refactoring) ?

Sans philosophie claire :
- Risque de sur-testing (tests redondants, maintenance élevée)
- Risque de sous-testing (bugs en production)
- Tests fragiles cassant à chaque refactoring
- Perte de confiance dans la suite de tests

## Options Considérées

### Option 1: Test Unitaire Exhaustif (TDD Classique)

Approche : Tester chaque fonction, module et cas limite individuellement avec mocks.

Exemple :

```elixir
# Test de l'implémentation interne
describe "AlbumRepository.build_query/1" do
  test "includes photos when :photos in preload" do
    query = AlbumRepository.build_query(preload: [:photos])
    
    # Teste la structure interne de la query
    assert %Ecto.Query{} = query
    assert query.preloads == [:photos]
  end
end

# Mock des dépendances
defmodule MockPhotoStorage do
  def store_photo(_upload, _opts), do: {:ok, %{photo_id: "mock-id"}}
end
```

Avantages :
- Couverture maximale (chaque ligne testée)
- Tests rapides (mocks, pas de DB)
- Détection bugs précise (fonction exacte identifiée)

Inconvénients :
- Tests couplés à l'implémentation (refactoring casse tests)
- Mocks créent fausse confiance (tests passent, prod échoue)
- Maintenance élevée (tests à modifier à chaque refactor)
- Ne teste pas intégration réelle

Décision : Rejeté comme stratégie principale. Tests unitaires complémentaires uniquement.

### Option 2: Test End-to-End Exclusif

Approche : Tester uniquement via l'interface utilisateur finale (LiveView, navigateur).

Exemple :

```elixir
# Test complet workflow
test "user creates album with photos and publishes", %{conn: conn} do
  {:ok, view, _html} = live(conn, "/admin/albums/new")
  
  # Créer album
  view |> form("#album-form", album: %{title: "Test"}) |> render_submit()
  
  # Upload photos
  view |> file_input("#upload", :photos, [%{path: "test.jpg"}])
  
  # Publier
  view |> element("#publish-btn") |> render_click()
  
  # Vérifier visible sur timeline
  {:ok, timeline, _} = live(conn, "/timeline")
  assert timeline |> element("#album-test") |> has_element?()
end
```

Avantages :
- Confiance maximale (teste vraiment ce que l'utilisateur fait)
- Tests découplés implémentation (refactoring safe)
- Détecte bugs intégration

Inconvénients :
- Tests lents (LiveView complet, DB, fichiers)
- Difficile à débugger (stack trace profonde)
- Edge cases difficiles à tester (erreurs spécifiques)
- Feedback loop lent (attendre tests longs)

Décision : Rejeté comme stratégie exclusive. E2E complémentaires uniquement.

### Option 3: Test Pyramide (Classique)

Approche : Majorité tests unitaires (base pyramide), moins d'intégration (milieu), peu d'E2E (sommet).

Répartition classique :
- 70% tests unitaires (fonctions isolées)
- 20% tests intégration (modules combinés)
- 10% tests E2E (workflow complet)

Avantages :
- Balance rapidité/confiance
- Standard industrie bien documenté
- Tests rapides majoritaires

Inconvénients :
- Tests unitaires couplés implémentation (fragiles)
- Mocks créent gaps intégration
- Maintenance élevée (majorité tests fragiles)

Décision : Rejeté. Pyramide inversée préférée (voir Option 4).

### Option 4: Pyramide Inversée + Interface Testing (CHOIX RETENU)

Approche : Majorité tests d'intégration à l'interface publique, complété par tests unitaires ciblés et quelques E2E.

Répartition :
- 60% tests intégration interface (LiveView, Context API)
- 30% tests unitaires (Value Objects, logique pure)
- 10% tests E2E (workflows critiques complets)

Principe directeur : Tester les interfaces, pas l'implémentation

Exemple :

```elixir
# Test interface Context (intégration)
describe "Photography.create_album/2" do
  test "creates album with valid attrs" do
    attrs = %{title: "Wedding", type: :wedding, date_prise_vue: ~D[2024-01-01]}
    
    assert {:ok, album} = Photography.create_album(attrs, %{user: user()})
    assert album.title == "Wedding"
    assert album.slug == "wedding"
    # Teste comportement observable, pas implémentation interne
  end
end

# Test interface LiveView (intégration)
describe "AlbumLive.New" do
  test "creates album through form submission" do
    {:ok, view, _} = live(conn, "/admin/albums/new")
    
    view |> form("#album-form", album: valid_attrs()) |> render_submit()
    
    assert_redirected(view, ~p"/admin/albums/#{album.id}/edit")
    assert Photography.list_albums() |> length() == 1
  end
end

# Test unitaire Value Object (logique pure)
describe "Slug.new/1" do
  test "converts title to URL-friendly slug" do
    assert {:ok, slug} = Slug.new("Héllo Wörld!")
    assert to_string(slug) == "hello-world"
  end
end
```

Avantages :
- Tests résistants au refactoring (testent interface, pas implémentation)
- Confiance élevée (DB réelle, intégrations réelles)
- Maintenance faible (tests cassent uniquement si comportement change)
- Feedback rapide (tests intégration raisonnablement rapides)
- Documentation vivante (tests montrent usage API)

Inconvénients :
- Tests plus lents que pur unitaire (mais acceptable)
- Setup parfois complexe (fixtures, DB)
- Quelques tests E2E restent lents

Décision : ACCEPTÉ - Meilleur compromis confiance/maintenance pour développeur solo.

## Décision

L'option choisie est : Option 4 - Pyramide Inversée + Interface Testing

Stratégie de testing du portfolio Photography basée sur les principes :

1. Tester l'interface publique, pas l'implémentation
2. Privilégier tests d'intégration à l'interface des Contexts
3. Tests unitaires uniquement pour logique pure complexe
4. Quelques tests E2E pour workflows critiques
5. Aucun mock sauf cas exceptionnels

### Justification

Cette approche est inspirée de l'article de référence "Towards Maintainable Elixir" et maximise :

Confiance :
- Tests utilisent vraie DB (Ecto Sandbox)
- Vraies intégrations (pas de mocks)
- Tests cassent uniquement si comportement réellement cassé

Maintenance :
- Tests découplés implémentation
- Refactoring n'impacte pas tests (tant qu'interface stable)
- Moins de tests fragiles

Documentation :
- Tests montrent usage réel des APIs
- Exemples concrets pour futurs développeurs

## Stratégie de Testing Détaillée

### Niveaux de Test

#### 1. Tests d'Intégration Interface (60% - Priorité HAUTE)

Cible : APIs publiques des Contexts (Photography, Auth)

Philosophie : Tester le comportement observable via l'interface publique.

Exemple - Context Photography :

```elixir
# test/portfolio/photography_test.exs
defmodule Portfolio.PhotographyTest do
  use Portfolio.DataCase
  
  alias Portfolio.Photography
  
  describe "create_album/2" do
    test "creates album with valid attributes" do
      attrs = %{
        title: "My Wedding",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        location: "Paris"
      }
      
      assert {:ok, album} = Photography.create_album(attrs, %{user: user()})
      
      # Teste résultat observable, pas implémentation
      assert album.title == "My Wedding"
      assert album.slug == "my-wedding"
      assert album.type == :wedding
      assert album.published == false
    end
    
    test "returns error with invalid attributes" do
      attrs = %{title: "", type: :invalid}
      
      assert {:error, changeset} = Photography.create_album(attrs, %{user: user()})
      assert "can't be blank" in errors_on(changeset).title
    end
  end
  
  describe "publish_album/2" do
    test "publishes album and emits domain event" do
      album = insert(:album, published: false)
      
      assert {:ok, published_album} = Photography.publish_album(album.id, %{user: user()})
      assert published_album.published == true
      
      # Vérifie side effect (domain event)
      assert_received {:album_published, %{album_id: ^album_id}}
    end
  end
end
```

Caractéristiques :
- Teste via interface publique `Photography.*`
- DB réelle (Ecto Sandbox)
- Pas de mock Repository/Query
- Vérifie comportement observable (résultat + side effects)

Fichiers concernés :
- `test/portfolio/photography_test.exs` (57 tests)
- `test/portfolio/auth_test.exs` (44 tests)

#### 2. Tests d'Intégration LiveView (60% - Priorité HAUTE)

Cible : Interfaces utilisateur LiveView

Philosophie : Tester via l'interface LiveView, pas les fonctions internes.

Exemple - AlbumLive.New :

```elixir
# test/portfolio_web/live/admin/album_live/new_test.exs
defmodule PortfolioWeb.Admin.AlbumLive.NewTest do
  use PortfolioWeb.ConnCase
  
  import Phoenix.LiveViewTest
  
  describe "album creation" do
    test "renders new album form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/albums/new")
      
      assert html =~ "Nouvel album"
      assert has_element?(view, "#album-form")
    end
    
    test "creates album on valid submission", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")
      
      form_data = %{
        "album" => %{
          "title" => "Wedding Album",
          "type" => "wedding",
          "date_prise_vue" => "2024-06-15"
        }
      }
      
      view |> form("#album-form", form_data) |> render_submit()
      
      # Vérifie redirect (comportement observable)
      assert_redirected(view, ~p"/admin/albums/#{album.id}/edit")
      
      # Vérifie album créé en DB (side effect)
      assert Photography.list_albums() |> length() == 1
    end
    
    test "displays validation errors on invalid submission", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/albums/new")
      
      invalid_data = %{"album" => %{"title" => ""}}
      
      html = view |> form("#album-form", invalid_data) |> render_change()
      
      assert html =~ "can&#39;t be blank"
    end
  end
end
```

Caractéristiques :
- Teste via LiveView complet (pas fonctions handle_event isolées)
- Pas de mock Context
- Vérifie render HTML + side effects DB
- Tests découplés structure interne LiveView

Fichiers concernés :
- `test/portfolio_web/live/admin/album_live/*.exs` (122 tests)
- `test/portfolio_web/live/admin/photo_live/*.exs` (15 tests)
- `test/portfolio_web/live/photography/*.exs` (32 tests)

#### 3. Tests d'Intégration Workflow Complet (10% - Priorité MOYENNE)

Cible : Workflows critiques bout-en-bout

Philosophie : Tester scénarios utilisateur complets multi-étapes.

Exemple - Album Management :

```elixir
# test/portfolio_web/integration/album_management_test.exs
defmodule PortfolioWeb.Integration.AlbumManagementTest do
  use PortfolioWeb.ConnCase, async: true
  
  import Phoenix.LiveViewTest
  
  describe "complete album lifecycle" do
    test "user creates, uploads, publishes and views album" do
      # 1. Créer album
      {:ok, view, _} = live(conn, "/admin/albums/new")
      view |> form("#album-form", album: valid_attrs()) |> render_submit()
      
      # 2. Upload photos
      {:ok, edit_view, _} = live(conn, "/admin/albums/#{album.id}/edit")
      upload_photos(edit_view, ["photo1.jpg", "photo2.jpg"])
      
      # 3. Publier album
      edit_view |> element("#publish-btn") |> render_click()
      
      # 4. Vérifier visible sur timeline public
      {:ok, timeline, html} = live(build_conn(), "/timeline")
      assert html =~ "Wedding Album"
      assert has_element?(timeline, "#album-#{album.id}")
    end
  end
end
```

Caractéristiques :
- Teste workflow complet réaliste
- Plusieurs étapes liées
- Transition entre pages LiveView
- Vérifie état final observable

Fichiers concernés :
- `test/portfolio_web/integration/album_management_test.exs` (32 tests)
- `test/portfolio_web/integration/auth_flow_test.exs` (21 tests)

#### 4. Tests Unitaires Ciblés (30% - Priorité MOYENNE)

Cible : Logique pure complexe (Value Objects, transformations)

Philosophie : Tester uniquement logique métier isolée sans dépendances.

Exemple - Value Object Slug :

```elixir
# test/portfolio/photography/value_objects/slug_test.exs
defmodule Portfolio.Photography.ValueObjects.SlugTest do
  use ExUnit.Case
  
  alias Portfolio.Photography.ValueObjects.Slug
  
  describe "new/1" do
    test "converts ASCII text to lowercase slug" do
      assert {:ok, slug} = Slug.new("Hello World")
      assert to_string(slug) == "hello-world"
    end
    
    test "handles accented characters" do
      assert {:ok, slug} = Slug.new("Café François")
      assert to_string(slug) == "cafe-francois"
    end
    
    test "removes special characters" do
      assert {:ok, slug} = Slug.new("Hello! @World #2024")
      assert to_string(slug) == "hello-world-2024"
    end
    
    test "returns error for empty slug" do
      assert {:error, :empty_slug} = Slug.new("!@#$%")
    end
  end
end
```

Caractéristiques :
- Logique pure (pas de side effects)
- Pas de DB, pas de dépendances externes
- Tests rapides (< 1ms)
- Edge cases exhaustifs

Fichiers concernés :
- `test/portfolio/photography/value_objects/slug_test.exs` (27 tests)
- `test/portfolio/auth/value_objects/email_test.exs` (32 tests)
- `test/portfolio/image_processor_test.exs` (30 tests)

#### 5. Tests Unitaires Ecto Changesets (30% - Priorité BASSE)

Cible : Validations Ecto complexes

Philosophie : Tester validations schema quand logique non triviale.

Exemple - User Changeset :

```elixir
# test/portfolio/auth/user_test.exs
describe "changeset/2" do
  test "validates email format" do
    valid_emails = ["user@example.com", "user+tag@example.com"]
    invalid_emails = ["notanemail", "@example.com", "user@"]
    
    for email <- valid_emails do
      changeset = User.changeset(%User{}, %{email: email, role: :admin})
      assert changeset.valid?
    end
    
    for email <- invalid_emails do
      changeset = User.changeset(%User{}, %{email: email, role: :admin})
      refute changeset.valid?
    end
  end
  
  test "normalizes email to lowercase" do
    changeset = User.changeset(%User{}, %{email: "Test@EXAMPLE.COM", role: :admin})
    assert Ecto.Changeset.get_change(changeset, :email) == "test@example.com"
  end
end
```

Caractéristiques :
- Teste changeset isolément (pas via Context)
- Utile pour validations complexes (regex, transformations)
- Skip si validations triviales (validate_required)

Fichiers concernés :
- `test/portfolio/auth/user_test.exs` (40 tests)
- `test/portfolio/photography/album_test.exs` (27 tests)
- `test/portfolio/photography/photo_test.exs` (46 tests)

### Ce Que l'On Ne Teste PAS

Principe : Ne pas tester l'implémentation interne.

Exemples de tests à éviter :

```elixir
# ❌ MAUVAIS : Teste implémentation Repository
test "AlbumRepository uses correct query" do
  query = AlbumRepository.build_query(preload: [:photos])
  assert query.preloads == [:photos]  # Couplé à Ecto.Query interne
end

# ✅ BON : Teste comportement via Context
test "list_albums/1 preloads photos when requested" do
  album = insert(:album)
  insert(:photo, album: album)
  
  [album] = Photography.list_albums(preload: [:photos])
  assert length(album.photos) == 1  # Teste résultat observable
end

# ❌ MAUVAIS : Teste fonction privée LiveView
test "handle_event :save calls update_album" do
  # Mock Context.update_album
  # Appel handle_event directement
end

# ✅ BON : Teste via interface LiveView
test "submitting form updates album" do
  {:ok, view, _} = live(conn, "/admin/albums/#{album.id}/edit")
  view |> form("#album-form", album: %{title: "Updated"}) |> render_submit()
  
  assert Photography.get_album!(album.id).title == "Updated"
end

# ❌ MAUVAIS : Mock Repository dans test Context
test "create_album calls AlbumRepository.insert" do
  expect(MockRepository, :insert, fn _ -> {:ok, %Album{}} end)
  Photography.create_album(attrs, scope)
end

# ✅ BON : Test Context avec vraie DB
test "create_album persists album to database" do
  {:ok, album} = Photography.create_album(attrs, scope)
  assert Repo.get(Album, album.id)  # Vraie DB via Ecto Sandbox
end
```

### Règles de Testing

#### Règle 1: Tester le Comportement, Pas l'Implémentation

Principe : Tests doivent vérifier QUOI (résultat), pas COMMENT (implémentation).

Exemple :

```elixir
# ❌ Teste comment (implémentation)
test "uses Enum.map to transform photos" do
  # Vérifie qu'on utilise Enum.map spécifiquement
end

# ✅ Teste quoi (comportement)
test "transforms photos to thumbnails" do
  photos = [photo1, photo2]
  thumbnails = PhotoService.generate_thumbnails(photos)
  
  assert length(thumbnails) == 2
  assert Enum.all?(thumbnails, &(&1.size == :thumbnail))
end
```

#### Règle 2: Pas de Mocks Sauf Exception

Principe : Utiliser vraies dépendances (DB, filesystem) via Ecto Sandbox et tmpdir.

Exceptions autorisées :
- Services externes (email SMTP, APIs tierces)
- Services coûteux (traitement ML, encoding vidéo)
- Randomness (Enum.random, timestamps)

Exemple :

```elixir
# ✅ Pas de mock DB (Ecto Sandbox)
test "creates album in database" do
  {:ok, album} = Photography.create_album(attrs, scope)
  assert Repo.get(Album, album.id)  # Vraie requête DB
end

# ✅ Pas de mock filesystem (tmpdir)
test "stores photo file" do
  {:ok, metadata} = LocalStorage.store_photo(upload, [])
  assert File.exists?(metadata.storage_path)  # Vrai fichier
end

# ✅ Mock service externe acceptable
test "sends magic link email" do
  expect(MockMailer, :send, fn email ->
    assert email.to == "user@example.com"
    assert email.subject =~ "Magic Link"
    :ok
  end)
  
  MagicLinkService.request_link("user@example.com")
end
```

#### Règle 3: Tests Async par Défaut

Principe : Utiliser `async: true` sauf si nécessité absolue de synchrone.

Cas synchrone requis :
- Modification état global (env vars, configuration)
- Tests Oban workers (jobs queue)
- Tests avec side effects partagés

Exemple :

```elixir
# ✅ Async (majorité des tests)
defmodule Portfolio.PhotographyTest do
  use Portfolio.DataCase, async: true  # Tests parallèles
end

# ❌ Sync uniquement si nécessaire
defmodule Portfolio.Workers.ImageVariantWorkerTest do
  use Portfolio.DataCase, async: false  # Oban queue partagée
end
```

Bénéfice : Suite de tests passe en 6s au lieu de 30s+ (parallélisation).

#### Règle 4: Setup Minimal et Explicite

Principe : Créer uniquement données nécessaires au test, explicitement dans le test.

Exemple :

```elixir
# ❌ Setup trop large
setup do
  user = insert(:user)
  album = insert(:album, user: user)
  photo1 = insert(:photo, album: album)
  photo2 = insert(:photo, album: album)
  
  {:ok, user: user, album: album, photos: [photo1, photo2]}
end

# Test utilise uniquement album
test "deletes album", %{album: album} do
  # user et photos inutiles
end

# ✅ Setup minimal par test
test "deletes album" do
  album = insert(:album)  # Uniquement ce qui est nécessaire
  Photography.delete_album(album.id)
  
  refute Repo.get(Album, album.id)
end

test "deletes album with photos" do
  album = insert(:album)
  insert_list(2, :photo, album: album)  # Photos uniquement si nécessaire
  
  Photography.delete_album(album.id)
  
  assert Photography.list_photos(album.id) == []
end
```

Bénéfice : Tests plus clairs (données visibles), moins de coupling.

#### Règle 5: Un Concept par Test

Principe : Chaque test vérifie un seul comportement ou cas limite.

Exemple :

```elixir
# ❌ Test vérifie plusieurs concepts
test "album validation" do
  # Teste title requis
  assert {:error, _} = Photography.create_album(%{title: ""})
  
  # Teste type valide
  assert {:error, _} = Photography.create_album(%{type: :invalid})
  
  # Teste date passée
  assert {:error, _} = Photography.create_album(%{date_prise_vue: ~D[2099-01-01]})
end

# ✅ Un concept par test
test "requires title" do
  assert {:error, changeset} = Photography.create_album(%{title: ""})
  assert "can't be blank" in errors_on(changeset).title
end

test "validates type is in allowed list" do
  assert {:error, changeset} = Photography.create_album(%{type: :invalid})
  assert "is invalid" in errors_on(changeset).type
end

test "rejects future dates" do
  future = Date.add(Date.utc_today(), 1)
  assert {:error, changeset} = Photography.create_album(%{date_prise_vue: future})
  assert "ne peut pas être dans le futur" in errors_on(changeset).date_prise_vue
end
```

Bénéfice : Erreur précise (nom test identifie problème), debug facile.

### Fixtures et Helpers

#### Factory Pattern (ExMachina Alternative)

Le projet utilise des helpers custom au lieu d'ExMachina :

```elixir
# test/support/fixtures/photography_fixtures.ex
defmodule PortfolioTest.Fixtures.PhotographyFixtures do
  alias Portfolio.Repo
  alias Portfolio.Photography.{Album, Photo}
  
  def album_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        title: "Default Album",
        type: :wedding,
        date_prise_vue: ~D[2024-01-01],
        slug: "default-album-#{System.unique_integer()}"
      })
    
    %Album{}
    |> Album.changeset(attrs)
    |> Repo.insert!()
  end
  
  def photo_fixture(album, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        album_id: album.id,
        photo_id: "photo-#{System.unique_integer()}",
        display_order: 1
      })
    
    %Photo{}
    |> Photo.changeset(attrs)
    |> Repo.insert!()
  end
end
```

Usage :

```elixir
test "lists albums" do
  album1 = album_fixture(title: "Wedding")
  album2 = album_fixture(title: "Concert")
  
  albums = Photography.list_albums()
  assert length(albums) == 2
end
```

Avantages vs ExMachina :
- Pas de dépendance supplémentaire
- Control total sur création
- Attributs explicites (pas de magie)

### Coverage et Métriques

#### ExCoveralls Configuration

```elixir
# mix.exs
test_coverage: [tool: ExCoveralls],
preferred_cli_env: [
  coveralls: :test,
  "coveralls.detail": :test,
  "coveralls.html": :test
]
```

#### Commandes Coverage

```bash
# Coverage basique
mix coveralls

# Coverage HTML avec détails
mix coveralls.html
open cover/excoveralls.html

# Coverage détaillé par fichier
mix coveralls.detail
```

#### Objectifs Coverage

Cibles par layer :

Layer | Coverage Objectif | Justification
---|---|---
Contexts (Photography, Auth) | ≥ 90% | API critique, logique métier
LiveViews | ≥ 80% | Interface utilisateur, paths principaux
Value Objects | ≥ 95% | Logique pure, edge cases exhaustifs
Repositories | ≥ 70% | Intégration DB, queries simples
Workers | ≥ 85% | Background jobs, error handling

Coverage global actuel : ~82% (objectif ≥ 85%)

Fichiers exclus coverage :
- Layouts, Components UI (testés manuellement)
- Migrations (code généré)
- Seeds (données dev)

### Organisation Tests

#### Structure Répertoires

```
test/
├── portfolio/                    # Tests Contexts (Domain)
│   ├── auth/                    # Context Auth
│   │   ├── user_test.exs
│   │   ├── magic_link_service_test.exs
│   │   └── session_service_test.exs
│   ├── photography/             # Context Photography
│   │   ├── album_test.exs
│   │   ├── photo_test.exs
│   │   ├── repositories/
│   │   ├── queries/
│   │   └── value_objects/
│   └── photography_test.exs     # Tests interface publique Context
│
├── portfolio_web/               # Tests Interface Web
│   ├── live/                    # Tests LiveView
│   │   ├── admin/
│   │   │   ├── album_live/
│   │   │   └── photo_live/
│   │   └── photography/
│   ├── integration/             # Tests Workflows
│   │   ├── album_management_test.exs
│   │   └── auth_flow_test.exs
│   └── controllers/
│
└── support/                     # Helpers et Fixtures
    ├── conn_case.ex
    ├── data_case.ex
    └── fixtures/
        ├── auth_fixtures.ex
        └── photography_fixtures.ex
```

#### Naming Conventions

Conventions de nommage :

Pattern | Exemple | Usage
---|---|---
`*_test.exs` | `album_test.exs` | Tests unitaires/intégration standard
`*_live_test.exs` | `index_live_test.exs` | Tests LiveView
`*_integration_test.exs` | `album_management_test.exs` | Tests workflow complet

### Statistiques Actuelles

Métriques projet :
- 52 fichiers tests
- 825 tests (776 passent, 5 failures temporaires)
- 8.2s temps exécution (1.8s async, 6.3s sync)
- Coverage : ~82%

Répartition tests :
- Tests Context (photography_test.exs, auth_test.exs) : ~100 tests
- Tests LiveView (admin, photography) : ~220 tests
- Tests Integration (album_management, auth_flow) : ~53 tests
- Tests Value Objects / Changesets : ~200 tests
- Tests Repositories / Queries : ~100 tests
- Tests Workers / Services : ~80 tests
- Tests Controllers / Helpers : ~70 tests

## Plan d'Action

### Court Terme (Priorité: HAUTE)

1. Fixer tests échouant actuellement
   - 5 failures détectés lors du run
   - Investiguer causes (regex email login_test.exs)
   - Corriger et vérifier suite passe à 100%
   - Estimation : 0.5 jour

2. Augmenter coverage Contexts
   - Context Photography : 87% → 92%
   - Context Auth : 84% → 90%
   - Focus edge cases manquants
   - Estimation : 1 jour

3. Documentation testing
   - Guide testing dans `docs/testing/`
   - Exemples pattern interface testing
   - Best practices fixtures
   - Estimation : 0.5 jour

### Moyen Terme (Priorité: MOYENNE)

1. Améliorer tests intégration
   - Ajouter workflows critiques manquants
   - Photo sorting drag&drop
   - Album batch operations
   - Estimation : 1 jour

2. Tests performance
   - Benchmarks upload photos
   - Tests N+1 queries (liste albums)
   - Estimation : 1 jour

3. Refactor fixtures
   - Simplifier photography_fixtures
   - Ajouter helpers fréquents
   - Estimation : 0.5 jour

### Long Terme (Priorité: BASSE)

1. Property-based testing
   - StreamData pour Value Objects
   - Tests Slug avec inputs aléatoires
   - Tests Email validation exhaustive
   - Estimation : 2 jours

2. Mutation testing
   - Outil Muzak (Elixir mutation testing)
   - Détecter tests inefficaces
   - Estimation : 1 jour

3. Visual regression testing
   - Percy.io pour UI screenshots
   - Détection changements visuels
   - Estimation : 2 jours

## Conséquences

### Positives

- Tests résistants au refactoring (interface, pas implémentation)
- Confiance élevée (vraie DB, vraies intégrations)
- Maintenance faible (tests cassent uniquement si comportement change)
- Documentation vivante (tests montrent usage APIs)
- Feedback rapide (suite complète 8s)
- Coverage élevé (82%) avec objectif clair (85%+)
- Parallélisation (async: true) réduit temps tests

### Négatives

- Tests plus lents que pur unitaire (mais acceptable 8s)
- Setup parfois complexe (fixtures, DB sandbox)
- Quelques tests E2E restent lents
- Pas de mocks = difficile de tester certains edge cases (APIs externes)

### Neutres

- Stratégie non-standard (pyramide inversée vs classique)
- Requiert discipline (éviter tester implémentation)
- Learning curve pour nouveaux développeurs (comprendre philosophie)

## Références

### Articles et Guides

- **Towards Maintainable Elixir Testing** : Guide fondateur de la philosophie
- Testing Elixir (Livre) : Jeffrey Matthias & Andrea Leopardi
- GOOS (Growing Object-Oriented Software Guided by Tests) : Freeman & Pryce

### Documentation Elixir/Phoenix

- ExUnit : https://hexdocs.pm/ex_unit/
- Phoenix LiveView Testing : https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html
- Ecto Sandbox : https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html

### Outils

- ExCoveralls : https://github.com/parroty/excoveralls
- Mox : https://github.com/dashbitco/mox (mocking si nécessaire)
- StreamData : https://github.com/whatyouhide/stream_data (property-based)

### Fichiers Code Concernés

- `test/portfolio/photography_test.exs` : Tests interface Context Photography
- `test/portfolio/auth_test.exs` : Tests interface Context Auth
- `test/portfolio_web/integration/album_management_test.exs` : Tests workflow complet
- `test/portfolio_web/live/admin/album_live/*.exs` : Tests LiveView
- `test/support/fixtures/photography_fixtures.ex` : Fixtures helpers

### ADRs Connexes

- ADR-061 : Precommit Quality Gates (mix precommit, CI/CD)
- ADR-042 : Telemetry Metrics Monitoring (tests performance)

---

Date de création: 2025-11-11  
Dernière révision: 2025-11-11
