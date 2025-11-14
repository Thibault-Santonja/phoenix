# Méthodologie de qualité de code - Standards et pratiques

Date : 1 juillet 2025
Auteur : Thibault Santonja
Statut : Actif et appliqué

## Table des matières

1. [Vision de la qualité](#vision-de-la-qualité)
2. [Principes architecturaux](#principes-architecturaux)
3. [Méthodologie TDD](#méthodologie-tdd)
4. [Standards de code](#standards-de-code)
5. [Revue de code et Git workflow](#revue-de-code-et-git-workflow)
6. [Outillage et automatisation](#outillage-et-automatisation)
7. [Documentation](#documentation)
8. [Dette technique](#dette-technique)
9. [Garantir la qualité à long terme](#garantir-la-qualité-à-long-terme)

---

## Vision de la qualité

### Définition de la qualité pour ce projet

La qualité du code n'est pas une fin en soi, mais un moyen d'atteindre cinq objectifs essentiels :
- la maintenabilité : le code doit rester facile à modifier dans 6 à 12 mois.
- la fiabilité : le code doit se comporter de manière prévisible.
- la lisibilité : un nouveau contributeur doit pouvoir comprendre rapidement le code.
- l'évolutivité : l'architecture doit supporter la croissance du projet.
- l'expérience développeur : le code doit être agréable à écrire et à lire.

### Objectifs non-négociables

Tout le code doit être testé. Sans chercher 100% de couverture, la couche domaine doit être pleinement testée. ~90% de couverture est un bon compromis, avec des tests unitaires (happy path, edge cases, error handling, etc.) et des tests d'intégration. L'architecture doit clairement suivre les principes du DDD et de la Clean Architecture. Les idiomes et conventions Elixir doivent être respectés. La documentation doit être vivante et auto-explicative. La compilation doit s'effectuer sans avertissements.

### Compromis assumés

Pour un projet de cette échelle, plusieurs compromis délibérés ont été acceptés :
- pas de CI/CD complète (pour l'instant).
- pas de revue par les pairs (mais une auto-revue systématique).
- pas de monitoring avancé.

Ces compromis seront réévalués si le projet grandit.

---

## Principes architecturaux

### SOLID appliqué à Elixir/Phoenix

#### Single Responsibility Principle

Chaque module ne devrait avoir qu'une seule raison de changer. Plutôt que de créer un module Album qui gère la création, l'envoi d'emails, l'upload de photos et la génération de PDF, ces préoccupations sont séparées en modules distincts :
- Album pour le schéma et les validations ;
- AlbumRepository pour la persistance ;
- AlbumMailer pour les emails ;
- PhotoUploader pour la gestion des fichiers.

```elixir
# Mauvais : Module qui fait trop
defmodule Album do
  def create(attrs), do: ...
  def send_email(album), do: ...
  def upload_photo(file), do: ...
  def generate_pdf(album), do: ...
end

# Bon : Responsabilités séparées
defmodule Album do
  # Schema + validations uniquement
end

defmodule AlbumRepository do
  # Persistance uniquement
end

defmodule AlbumMailer do
  # Emails uniquement
end

defmodule PhotoUploader do
  # Upload uniquement
end
```

Cette séparation garantit que les changements restent isolés et que les tests demeurent simples.

#### Open/Closed Principle

Les modules doivent être ouverts à l'extension mais fermés à la modification. L'utilisation des behaviours permet d'y parvenir :

```elixir
defmodule Storage do
  @callback store(binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
end

defmodule Storage.Local do
  @behaviour Storage
  def store(data, filename), do: ...
end

defmodule Storage.S3 do
  @behaviour Storage
  def store(data, filename), do: ...
end

# Configuration runtime
storage_adapter = Application.get_env(:portfolio, :storage_adapter)
storage_adapter.store(data, filename)
```

L'adaptateur de stockage peut être configuré à l'exécution sans modifier le code existant.

#### Liskov Substitution Principle

Dans la programmation fonctionnelle, ce principe est principalement assuré par les spécifications de types. Toutes les implémentations d'une spec donnée doivent respecter son contrat :

```elixir
@spec process(User.t()) :: {:ok, result()} | {:error, reason()}
def process(%User{role: "admin"} = user), do: ...
def process(%User{role: "user"} = user), do: ...
```

Les deux implémentations honorent le même contrat.

#### Interface Segregation Principle

Les petits modules avec des APIs minimales sont préférables aux interfaces monolithiques avec de nombreuses fonctions. Plutôt qu'un AlbumService avec dix fonctions : AlbumRepository pour les opérations CRUD, PublishService pour l'état de publication, PhotoManager pour les opérations sur les photos, et AlbumExporter pour l'export de données.

#### Dependency Inversion Principle

Le domaine ne dépend jamais de l'infrastructure. L'architecture s'écoule du Domaine (Album, Photo) à travers le Repository (AlbumRepository) vers l'Infrastructure (Repo, Base de données). La couche domaine ne doit pas mentionner de requêtes Ecto ou SQL. Les repositories abstraient la persistance, permettant de changer de base de données sans toucher au code domaine. Bien qu'exceptionnel, le changement de base de données peut être une tâche complexe et dangereuse, cette séparation est donc cruciale.

**Architecture appliquée** :
```
Domain (Album, Photo)          # Ne connaît pas Ecto/SQL
   ↑ dépend
Repository (AlbumRepository)   # Abstrait la persistance
   ↑ dépend
Infrastructure (Repo, DB)      # On peut changer de DB sans toucher au domain
```


### DRY (Don't Repeat Yourself)

Chaque élément de connaissance devrait avoir une représentation unique faisant autorité. Cependant, DRY ne signifie pas fusionner du code d'apparence similaire ayant des sémantiques différentes. Deux fonctions qui se ressemblent mais servent des objectifs différents devraient rester séparées.

Par exemple, valider les emails utilisateurs et valider les emails admin peut utiliser des patterns regex similaires, mais ils représentent des règles métier différentes et ne devraient pas être abstraits en une seule fonction.

### KISS (Keep It Simple, Stupid)

La solution la plus simple et qui fonctionne doit être choisie. Pour ce projet, les contextes sont suffisants sans couche de service additionnelle. Un GenServer simple est utilisé pour le nettoyage plutôt qu'Oban. Les magic links restent simples sans authentification multi-facteurs. Bref, la simplicité est la clef.

La question à se poser systématiquement : "Cette abstraction est-elle vraiment nécessaire ?"

### YAGNI (You Aren't Gonna Need It)

N'implémenter que ce dont le projet a besoin maintenant. Les permissions granulaires, le soft delete, le multi-tenancy, une API et son versionnement n'ont pas été implémentés. Ces fonctionnalités seront ajoutées quand le besoin deviendra réel.

### Domain-Driven Design (DDD)

Le Domain-Driven Design est une approche de conception logicielle qui place le domaine métier au centre de l'architecture. Plutôt que de partir de la technologie ou de la base de données, cette approche part du métier et de ses règles.

#### Principes fondamentaux

Le DDD repose sur plusieurs concepts clés qui structurent la pensée et le code.

##### Ubiquitous Language (Langage Omniprésent)

Le langage utilisé dans le code doit être le même que celui utilisé par les experts métier. Si un photographe parle d'"albums", de "séries" et de "tirages", le code doit utiliser ces mêmes termes, pas des "collections", "groupes" ou "images".

Ce langage doit être cohérent partout : dans le code, la documentation, les discussions, les tests. Quand un développeur et un expert métier parlent ensemble, ils utilisent exactement les mêmes mots.

Exemple concret :
```elixir
# Bon : Utilise le vocabulaire métier
defmodule Portfolio.Photography.Album do
  field :title, :string
  field :chapter, Ecto.Enum  # "Chapter" = terme du photographe
  field :event_date, :date
end

# Mauvais : Vocabulaire technique générique
defmodule Portfolio.ImageCollection do
  field :name, :string
  field :category, :string
  field :timestamp, :datetime
end
```

##### Bounded Context (Contexte Borné)

Un bounded context est une frontière explicite autour d'un modèle métier cohérent. À l'intérieur de cette frontière, tous les termes et règles ont une signification précise et unique.

Ce projet contient plusieurs bounded contexts :
- Photography : Gestion des albums et photos
- Auth : Authentification et gestion des utilisateurs

Le mot "User" peut avoir des significations différentes selon le contexte. Dans Auth, c'est quelqu'un qui se connecte. Dans Photography, ce pourrait être un photographe ou un client. Les bounded contexts évitent cette confusion.

```elixir
# Contexte Auth
defmodule Portfolio.Auth.User do
  field :email, :string
  field :role, Ecto.Enum
end

# Exemple avec un contexte Client séparé
defmodule Portfolio.Client.Customer do
  field :name, :string
  field :contact_email, :string
  # Pas de mot de passe ici, c'est un autre concept
end
```

##### Entities (Entités)

Une entité est un objet qui a une identité unique qui persiste dans le temps, même si ses attributs changent. Deux entités sont différentes même si tous leurs attributs sont identiques, car elles ont des identités différentes.

Photo est une entité : deux photos peuvent avoir le même titre, la même date, mais ce sont deux photos différentes car elles ont des IDs différents.

```elixir
defmodule Portfolio.Photography.Photo do
  schema "photos" do
    field :id, :binary_id  # L'identité unique
    field :title, :string
    field :description, :string
    # Même si deux photos ont le même titre/description,
    # elles restent distinctes grâce à leur ID
  end
end
```

##### Value Objects (Objets Valeur)

Un value object est un objet sans identité propre, défini uniquement par ses attributs. Deux value objects avec les mêmes attributs sont considérés comme identiques.

Exemple concret :
```elixir
defmodule Portfolio.Photography.ValueObjects.Slug do
  @enforce_keys [:value]
  defstruct [:value]
  
  def new(title) do
    slug_value = 
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
    
    %__MODULE__{value: slug_value}
  end
end

# Deux slugs avec la même valeur sont identiques
slug1 = Slug.new("Mon Album")  # %Slug{value: "mon-album"}
slug2 = Slug.new("Mon Album")  # %Slug{value: "mon-album"}
# slug1 == slug2 → true (pas besoin d'ID)
```

##### Aggregates (Agrégats)

Un aggregate est un groupe d'objets traités comme une unité pour la cohérence des données. Il a une racine (aggregate root) qui est la seule entité accessible de l'extérieur.

Album est un aggregate root qui contient des Photos. Pour modifier une photo, le passage par l'album est obligatoire :

```elixir
# Album est la racine d'agrégat
defmodule Portfolio.Photography.Album do
  schema "albums" do
    field :title, :string
    has_many :photos, Photo  # Les photos sont dans l'agrégat
  end
  
  # On ne peut pas modifier une photo sans passer par l'album
  def add_photo(%Album{} = album, photo_attrs) do
    # Validation au niveau de l'agrégat
    # Par exemple : un album ne peut pas avoir plus de 100 photos
    if length(album.photos) >= 100 do
      {:error, :album_full}
    else
      # Création de la photo dans le contexte de l'album
      {:ok, photo}
    end
  end
end
```

Règles importantes :
- Une Photo ne doit jamais être modifiée directement sans passer par son Album
- Toutes les règles métier sont dans l'aggregate root
- La cohérence est garantie au niveau de l'agrégat

##### Repositories (Dépôts)

Les repositories abstraient la persistance des aggregates. Ils permettent de sauver et récupérer des objets domaine sans que le domaine connaisse les détails de la base de données.

```elixir
defmodule Portfolio.Photography.Repositories.AlbumRepository do
  alias Portfolio.Repo
  alias Portfolio.Photography.Album
  
  # Le domaine demande un album, pas un SELECT SQL
  def get(id) do
    Repo.get(Album, id)
    |> Repo.preload(:photos)
  end
  
  # Le domaine sauve un album, pas INSERT INTO
  def save(%Album{} = album) do
    Repo.insert_or_update(album)
  end
end
```

Le domaine ne sait pas comment les données sont stockées. Un changement de PostgreSQL à MongoDB pourrait se faire sans modifier le code domaine.

##### Domain Events (Événements Domaine)

Les domain events capturent des faits métier qui se sont produits. Ils permettent la communication entre bounded contexts sans couplage direct.

Exemple d'implémentation :
```elixir
defmodule Portfolio.Photography.Events.AlbumPublished do
  defstruct [:album_id, :title, :published_at]
end

# Quand un album est publié
def publish_album(album) do
  # ... logique de publication ...
  
  # Émettre l'événement
  event = %AlbumPublished{
    album_id: album.id,
    title: album.title,
    published_at: DateTime.utc_now()
  }
  
  EventBus.publish(event)
  {:ok, album}
end

# D'autres contextes peuvent réagir
defmodule Portfolio.Notification.AlbumPublishedHandler do
  def handle(%AlbumPublished{} = event) do
    # Envoyer une notification
    # Sans que Photography connaisse Notification
  end
end
```

##### Services (Services Domaine)

Un service domaine encapsule une logique métier qui ne correspond pas naturellement à une entité ou un value object. Il représente une opération ou un processus métier.

```elixir
defmodule Portfolio.Photography.Services.PhotoUploadService do
  # Ce service orchestre plusieurs opérations
  def upload_photos(album, uploads) do
    with :ok <- validate_album_capacity(album, uploads),
         {:ok, stored_files} <- store_files(uploads),
         {:ok, photos} <- create_photo_records(album, stored_files),
         :ok <- schedule_processing(photos) do
      {:ok, photos}
    end
  end
  
  # Cette logique ne rentre pas dans Album ou Photo
  # C'est un processus métier complexe
end
```

#### Application pratique

Le projet applique le DDD de manière pragmatique :

```
lib/portfolio/
├── photography/              # Bounded Context
│   ├── album.ex             # Aggregate Root (Entity)
│   ├── photo.ex             # Entity dans l'agrégat
│   ├── value_objects/
│   │   └── slug.ex          # Value Object
│   ├── repositories/
│   │   ├── album_repository.ex
│   │   └── photo_repository.ex
│   ├── services/
│   │   └── photo_upload_service.ex
│   └── events/
│       ├── album_published.ex
│       └── photo_uploaded.ex
└── auth/                     # Autre Bounded Context
    ├── user.ex
    └── session.ex
```

#### Bénéfices du DDD

Le DDD apporte plusieurs avantages concrets.

Premièrement, la clarté : le code reflète exactement le métier. Un expert métier peut lire le code et le comprendre.

Deuxièmement, la maintenabilité : quand les règles métier changent, l'emplacement de la modification est clair.

Troisièmement, la testabilité : le domaine est isolé de l'infrastructure, facile à tester.

Quatrièmement, l'évolutivité : les bounded contexts peuvent évoluer indépendamment.

#### Quand utiliser le DDD

Le DDD n'est pas toujours nécessaire. Il apporte le plus de valeur quand :
- Le domaine métier est complexe avec de nombreuses règles
- Le projet va durer longtemps et évoluer
- Il y a une vraie collaboration avec des experts métier
- L'équipe comprend et accepte les concepts DDD

Pour un CRUD simple, le DDD peut être de la sur-ingénierie. Pour notre portfolio photographique avec ses règles de publication, ses validations métier et ses workflows complexes, le DDD apporte une vraie valeur.

## Méthodologie TDD

### Workflow Red-Green-Refactor

Le cycle TDD consiste en trois phases :
1. Red : écrire un test qui échoue.
2. Green : écrire le code minimal pour faire passer le test.
3. Refactor : améliorer le code sans changer le comportement. Puis répéter.

Considérons cet exemple. Le cycle commence avec un test qui échoue, attendant la génération d'un slug à partir d'un titre. Le test échoue car le champ slug n'existe pas. Du code minimal est ensuite écrit pour le faire passer, peut-être naïvement en convertissant le titre en minuscules. Finalement, une refactorisation vers une implémentation robuste gère les caractères spéciaux et les espaces, en s'assurant que le test continue de passer.

### Structure des tests

Les tests sont organisés pour refléter la structure de l'application :

```
test/portfolio/
├── photography/
│   ├── album_test.exs
│   ├── photo_test.exs
│   ├── repositories/
│   │   ├── album_repository_test.exs
│   │   └── photo_repository_test.exs
│   └── photography_test.exs
└── auth/
    ├── user_test.exs
    ├── magic_link_test.exs
    └── auth_test.exs
```

Chaque module de test utilise des blocs descriptifs et suit un pattern cohérent :

```elixir
defmodule Portfolio.Photography.AlbumTest do
  use Portfolio.DataCase

  alias Portfolio.Photography.Album

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = valid_attrs()
      changeset = Album.changeset(%Album{}, attrs)
      assert changeset.valid?
    end

    test "invalid without title" do
      attrs = Map.delete(valid_attrs(), :title)
      changeset = Album.changeset(%Album{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).title
    end
  end

  defp valid_attrs do
    %{
      title: "Test Album",
      type: :wedding,
      date_prise_vue: ~D[2024-01-01]
    }
  end
end
```

### Objectifs de couverture

La couche domaine et les repositories doivent viser 100% de couverture pour assurer la qualité actuelle et surtout future (pas de regressions). Les contextes visent 90% de couverture. Les contrôleurs et LiveViews visent 70% ou plus des chemins principaux. Évidemment, la couverture ne signifie pas que les tests soient bons et que l'application est 100% robuste (c'est d'ailleurs impossible). C'est cependant un indice de qualité à ne pas négliger. On sera tous d'accord pour dire qu'une couverture de 0% est pour le coup assurément une mauvaise qualité.

On peut vérifier la couverture via `mix test --cover`.

### Tests d'intégration

Les tests d'intégration vérifient les interactions entre les couches :

```elixir
defmodule Portfolio.PhotographyTest do
  use Portfolio.DataCase

  alias Portfolio.Photography

  describe "create_album/1" do
    test "creates album with valid data" do
      attrs = %{title: "Test", type: :wedding, date_prise_vue: ~D[2024-01-01]}

      assert {:ok, album} = Photography.create_album(attrs)
      assert album.title == "Test"
      assert album.slug == "test"
      assert album.type == :wedding
    end

    test "returns error changeset with invalid data" do
      attrs = %{title: "AB"}

      assert {:error, changeset} = Photography.create_album(attrs)
      assert "should be at least 3 character(s)" in errors_on(changeset).title
    end
  end
end
```

### Quand ne pas tester

Je saute les tests pour le code trivial comme les getters et setters, les fichiers de configuration, les migrations de base de données (testées via rollback), et le boilerplate Phoenix généré. Le focus reste sur la logique métier, les règles de validation et les requêtes complexes.

## Standards de code

### Conventions Elixir

> [Guide officiel](https://hexdocs.pm/elixir/naming-conventions.html)

Nous suivons les conventions de nommage officielles d'Elixir. Les modules utilisent PascalCase. Les fonctions et variables utilisent snake_case. Les atoms utilisent les minuscules. Les attributs de module servent de constantes. L'indentation utilise 2 espaces, jamais de tabulations. Les lignes ne doivent pas dépasser 98 caractères.

Le pattern matching est préféré à la logique conditionnelle :

```elixir
# Préféré
def process({:ok, result}), do: result
def process({:error, reason}), do: handle_error(reason)

# À éviter
def process(result) do
  if elem(result, 0) == :ok do
    elem(result, 1)
  else
    handle_error(elem(result, 1))
  end
end
```

Les pipes améliorent la clarté :

```elixir
# Préféré
data
|> process()
|> transform()
|> save()

# Moins lisible
save(transform(process(data)))
```

### Formatter

La configuration du formatter se trouve dans `.formatter.exs` :

```elixir
[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
```

Les commandes `mix format` pour formater tout le code ou `mix format --check-formatted` pour vérifier sans modification sont à utiliser. Un hook git pre-commit assure le formatage avant commit.

### Credo (Linter)

Credo est installé comme dépendance de développement. Les commandes `mix credo` pour une analyse complète, `mix credo --strict` pour la CI, ou `mix credo suggest` pour des suggestions uniquement sont disponibles.

Credo vérifie la cohérence du nommage et l'ordre des paramètres, identifie les problèmes de design comme les fonctions longues et le code imbriqué, améliore la lisibilité via la documentation des modules et les specs, met en évidence les opportunités de refactoring, et avertit des variables inutilisées et fonctions dépréciées.

### Dialyzer (Vérification de types)

Dialyzer, installé via dialyxir, fournit une vérification de types statique. La première exécution est lente lors de la construction du cache PLT, mais les exécutions suivantes sont rapides. Les specs importantes doivent être ajoutées aux fonctions publiques :

```elixir
@spec create_album(map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
def create_album(attrs) do
  # ...
end

@spec list_albums(keyword()) :: [Album.t()]
def list_albums(opts \\ []) do
  # ...
end
```

Cela détecte les erreurs de types à la compilation.

### Documentation avec ExDoc

La documentation des modules et fonctions suit ces conventions :

```elixir
defmodule Portfolio.Photography do
  @moduledoc """
  Contexte Photography pour la gestion des albums et photos.

  Ce module expose l'API publique pour :
  - Créer, lire, modifier, supprimer des albums
  - Gérer les photos d'un album
  - Publier et dépublier des albums
  """

  @doc """
  Liste tous les albums avec options de filtrage.

  ## Options

    * `:filters` - Keyword list de filtres (type, published, year)
    * `:order` - Ordre de tri (default: desc par date_prise_vue)
    * `:preload` - Associations à précharger (ex: [:photos])

  ## Exemples

      iex> Photography.list_albums()
      [%Album{}, ...]

      iex> Photography.list_albums(filters: [type: :wedding], preload: [:photos])
      [%Album{photos: [...]}, ...]
  """
  @spec list_albums(keyword()) :: [Album.t()]
  def list_albums(opts \\ []) do
    # ...
  end
end
```

Générez la documentation avec `mix docs` et ouvrez-la à `doc/index.html`.

## Revue de code et Git workflow

### Workflow Git

Le workflow utilise une branche main de production avec des branches de fonctionnalités pour le développement. Les commits doivent être atomiques, chaque commit représentant une seule responsabilité.

Bons commits :
```
feat(auth): Add magic link email sending
fix(auth): Fix microseconds error in datetime fields
docs(auth): Add architecture study
```

Mauvais commits :
```
Add features and fix bugs
```

### Format des messages de commit

La convention suivit est *Conventional Commits* :

```
<type>(<scope>): <description>

[corps optionnel]

[pied de page optionnel]
```

Types :
- `feat`: Nouvelle fonctionnalité
- `fix`: Correction de bug
- `docs`: Documentation
- `style`: Formatage (pas de changement de code)
- `refactor`: Refactoring sans changer le comportement
- `test`: Ajout/modification de tests
- `chore`: Tâches de maintenance

Exemples :
```
feat(photography): Add Album aggregate and repository
fix(auth): Truncate microseconds for utc_datetime fields
docs(studies): Add photography domain architecture study
refactor(photography): Simplify context API by removing service layer
test(auth): Add session expiration test cases
chore(deps): Update Phoenix to 1.8.1
```

### Checklist d'auto-revue

Avant chaque commit, vérifier :
- Code : Pas d'avertissements de compilation, mix format appliqué, les tests passent, credo clean, specs ajoutées pour les fonctions publiques.
- Tests : Nouveaux tests pour la nouvelle logique, cas limites couverts, tests lisibles avec des noms descriptifs.
- Documentation : @moduledoc pour les nouveaux modules, @doc pour les fonctions publiques, README à jour si nécessaire, études architecturales pour les décisions majeures.
- Architecture : Respect du DDD et de la Clean Architecture, pas de couplage domaine vers infrastructure, principes SOLID suivis, pas de sur-ingénierie.
- Sécurité : Pas de secrets codés en dur, validations en place, pas de risque d'injection SQL (Ecto protège), pas d'exposition de données sensibles.

### Règle du boy scout

Laissez le code plus propre que vous ne l'avez trouvé. Lorsque vous touchez un fichier, améliorez ce qui l'entoure. Renommez les variables mal nommées. Ajoutez les tests manquants. Documentez les fonctions obscures. Cependant, évitez le refactoring massif hors du scope du commit.

## Documentation

### Niveaux de documentation

La documentation existe à plusieurs niveaux :
- Le code auto-documenté avec des noms explicites et une structure claire ;
- Les commentaires inline pour le "pourquoi" (jamais pour le "quoi") ;
- @doc et @moduledoc pour les APIs publiques ;
- Le README pour la vue d'ensemble du projet ;
- Les études architecturales pour les décisions majeures et les compromis.

### Quand commenter

Bons commentaires expliquant les contournements, les considérations d'optimisation et le travail futur :

```elixir
# HACK: Contournement pour bug Ecto 3.11, à retirer après mise à jour
# Voir issue: https://github.com/elixir-ecto/ecto/issues/1234

# OPTIMIZE: Cette requête pourrait être optimisée avec un index
# Performance acceptable pour < 10k albums

# TODO: Ajouter support multi-langue
```

Mauvais commentaires décrivant ce que le code fait évidemment :

```elixir
# Récupérer l'utilisateur
user = get_user(id)

# Boucler sur les albums
Enum.each(albums, fn album ->
  # Traiter l'album
  process(album)
end)
```

### Structure du README

Les sections essentielles incluent :
- Description du projet
- Instructions de setup
- Vue d'ensemble de l'architecture avec liens vers la documentation détaillée
- Guide de développement
- Guide de test
- Processus de déploiement
- Information de licence

### Études architecturales

Une étude architecturale est écrite lors d'une décision architecturale majeure, de l'évaluation de compromis complexes, de la considération d'alternatives, ou de l'introduction d'un nouveau domaine métier. Il existe une template dans `docs/studies/auth-system-architecture.md`.

## Dette technique

La dette technique identifiée se présente sous quatre types :
- Délibérée et prudente : "Pas le temps de faire proprement maintenant, refactorisation à venir" ;
- Délibérée et imprudente : "Pas le temps de concevoir" ;
- Accidentelle et prudente : "Maintenant la bonne approche est claire" ;
- Accidentelle et imprudente : "Qu'est-ce que le design ?".

La dette de type 1 doit être correctement documentée. Un fichier `docs/technical_debt.md` pourra être créé pour cela quand nécessaire. Afin de prioriser les résolutions, une matrice de décision peut être utilisée :

```
Impact Business
    ↑
 4  |  [Refactor maintenant]    [Planifier]
    |
 2  |  [À considérer]           [Ignorer]
    |-----------------------------------------> Effort
            2                       4
```
> Cela impacte-t-il les utilisateurs ?
> Bloque-t-il de nouvelles fonctionnalités ?
> Augmente-t-il les bugs ?
> Ou est-ce juste "pas élégant" ?

## Garantir la qualité à long terme

### Audits périodiques

Tâches mensuelles :
- Réviser la documentation de dette technique
- Vérifier la couverture des tests (objectif : plus de 90%)
- Lancer `mix credo --strict`
- Vérifier les dépendances obsolètes avec `mix hex.outdated`

Tâches trimestrielles :
- Refactoriser une zone de dette technique
- Mettre à jour les dépendances majeures
- Réviser la pertinence de l'architecture
- Mettre à jour les études architecturales

### Métriques à suivre

Métriques de code : Les avertissements de compilation doivent être à 0. La couverture des tests doit viser au minimum 90% pour le domaine et 70% globalement. La complexité cyclomatique doit rester sous 10 par fonction.

Métriques de performance : [TODO]

Afin d'éviter l'enfer des dépendances, où un projet accumule trop de dépendances, rendant la maintenance difficile, l'objectif est de maintenir un total des dépendances en production sous 30.

Pas de CVE connues.

### Évolution de l'architecture

L'architecture doit évoluer avec les besoins. Les questions suivantes doivent être posées régulièrement : Les contextes bornés sont-ils toujours pertinents ? Y a-t-il duplication entre les domaines ? Les repositories sont-ils toujours suffisants ? Une couche service est-elle nécessaire ? L'API du contexte est-elle trop complexe ?

Documentez chaque évolution avec des études architecturales mises à jour.

### Formation continue

Ressources Elixir/Phoenix :
- [Elixir School](https://elixirschool.com/)
- [Phoenix Guides](https://hexdocs.pm/phoenix/overview.html)
- [Pragmatic Studio Courses](https://pragmaticstudio.com/elixir)
- [Elixir Forum](https://elixirforum.com/)
- [AppSignal](https://appsignal.com/)

DDD/Clean Architecture :
- "Domain-Driven Design" - Eric Evans
- "Clean Architecture" - Robert C. Martin
- "Implementing Domain-Driven Design" - Vaughn Vernon

Qualité code :
- "The Pragmatic Programmer" - Hunt & Thomas
- "Refactoring" - Martin Fowler
- "Clean Code" - Robert C. Martin
