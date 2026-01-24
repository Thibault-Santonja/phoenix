# ADR-032: Repository Pattern pour l'Acc�s aux Données

Statut: Accepté  
Date: 2025-11-11

## Contexte

Dans une application Elixir/Phoenix avec Ecto, la question de l'acc�s aux données est centrale. Ecto est déj� une excellente abstraction de la base de données, offrant des changesets, des queries composables et un syst�me de migration robuste.

Pourtant, ce projet utilise une couche supplémentaire : le **Repository Pattern**. Cette décision mérite d'être documentée et justifiée, car elle n'est pas évidente dans l'écosyst�me Elixir où beaucoup de projets utilisent Ecto directement dans les Contexts.

### Problématique

Trois approches sont possibles pour l'acc�s aux données dans une architecture Clean Architecture / DDD :

**Approche 1 : Ecto Direct dans Context**
```elixir
defmodule Portfolio.Photography do
  import Ecto.Query
  
  def list_published_albums do
    from(a in Album, where: a.published == true)
    |> Repo.all()
  end
end
```

**Approche 2 : Repository Pattern (approche actuelle)**
```elixir
defmodule Portfolio.Photography do
  def list_published_albums do
    AlbumRepository.list(published: true)
  end
end

defmodule AlbumRepository do
  def list(filters) do
    AlbumQuery.base()
    |> apply_filters(filters)
    |> Repo.all()
  end
end
```

**Approche 3 : Repository + Query Objects (approche actuelle avec séparation)**
```elixir
# Query Object : Construction de requêtes composables
defmodule AlbumQuery do
  def base, do: from(a in Album)
  def published(query), do: where(query, [a], a.published == true)
end

# Repository : Exécution et orchestration
defmodule AlbumRepository do
  def list(filters) do
    AlbumQuery.base()
    |> apply_filters(filters)
    |> Repo.all()
  end
end
```

### Questions � résoudre

1. Pourquoi ajouter une couche Repository alors qu'Ecto est déj� une abstraction ?
2. Pourquoi séparer Repository et Query Objects en deux modules distincts ?
3. Comment standardiser les conventions de retour (tuples vs valeurs directes) ?
4. Quand créer des méthodes spécifiques vs utiliser des méthodes génériques ?
5. Quand utiliser SQL brut vs Ecto.Query dans un Repository ?

### Contraintes

- Maintien de la séparation des préoccupations : Le domaine ne doit pas dépendre d'Ecto
- Réutilisabilité : Éviter la duplication des requêtes entre Contexts
- Testabilité : Faciliter les tests unitaires et d'intégration
- Performance : Support des requêtes optimisées (SQL brut si nécessaire)
- Pragmatisme : Éviter l'over-engineering, rester simple

### Impact si aucune décision n'est prise

Sans r�gles claires sur l'acc�s aux données :
- Mélange d'approches (Ecto direct + Repository) � incohérence
- Duplication des requêtes entre Contexts
- Difficile de savoir où placer une nouvelle requête
- Conventions de retour incohérentes (tuples vs valeurs directes)
- Tests difficiles � écrire (dépendances enchevêtrées)

## Options considérées

### Option 1: Ecto Direct dans Contexts (Approche minimaliste)

Description :

Les Contexts utilisent Ecto directement sans couche Repository intermédiaire. Les requêtes SQL sont construites et exécutées directement dans les fonctions du Context.

```elixir
defmodule Portfolio.Photography do
  import Ecto.Query
  alias Portfolio.Repo
  alias Portfolio.Photography.Album
  
  def list_published_albums do
    from(a in Album, 
      where: a.published == true,
      order_by: [desc: a.date_prise_vue],
      preload: [:photos]
    )
    |> Repo.all()
  end
  
  def list_albums_by_type(type) do
    from(a in Album, where: a.type == ^type)
    |> Repo.all()
  end
  
  def create_album(attrs) do
    %Album{}
    |> Album.changeset(attrs)
    |> Repo.insert()
  end
end
```

Avantages :
- Simplicité maximale : Pas de couche supplémentaire, code direct
- Moins de fichiers : Tout dans le Context, pas de navigation entre modules
- **Convention Elixir/Phoenix** : Beaucoup de projets Elixir font ainsi
- Pas de boilerplate : Pas besoin de wrapper chaque fonction Ecto

Inconvénients :
- Duplication de requêtes : Si plusieurs Contexts utilisent Album, duplication des queries
- Context devient gros : Mélange de logique métier et construction de requêtes
- Difficile � tester : Impossible de tester les requêtes sans exécuter le Context complet
- Couplage fort : Le Context dépend directement d'Ecto (violation Dependency Inversion)
- Réutilisabilité limitée : Requêtes complexes dupliquées entre Admin, API, Public contexts

**Exemple de duplication :**
```elixir
# Photography Context
def admin_list_albums do
  from(a in Album, order_by: [desc: a.inserted_at])
  |> Repo.all()
end

# API Context
def list_albums do
  from(a in Album, order_by: [desc: a.inserted_at])  # DUPLIQUÉ
  |> Repo.all()
end
```

Effort estimé : Faible (pas de Repository � créer)

Risques :
- Dette technique importante si le projet grandit [Probabilité: Élevée, Impact: Moyen]
- Duplication de code [Probabilité: Élevée, Impact: Moyen]

### Option 2: Repository Pattern Simple (Sans Query Objects)

Description :

Créer des modules Repository qui encapsulent toute la logique d'acc�s aux données (construction + exécution des requêtes). Pas de séparation Query Objects.

```elixir
defmodule Portfolio.Photography.Repositories.AlbumRepository do
  import Ecto.Query
  alias Portfolio.Repo
  alias Portfolio.Photography.Album
  
  # CRUD
  def insert(attrs), do: %Album{} |> Album.changeset(attrs) |> Repo.insert()
  def update(album, attrs), do: album |> Album.changeset(attrs) |> Repo.update()
  def delete(album), do: Repo.delete(album)
  def get(id), do: case Repo.get(Album, id), do: (nil -> {:error, :not_found}; a -> {:ok, a})
  
  # Queries métier
  def list_published do
    from(a in Album, where: a.published == true)
    |> Repo.all()
  end
  
  def list_by_type(type) do
    from(a in Album, where: a.type == ^type)
    |> Repo.all()
  end
  
  def list_published_by_year(year) do
    start_date = Date.new!(year, 1, 1)
    end_date = Date.new!(year, 12, 31)
    
    from(a in Album,
      where: a.published == true,
      where: a.date_prise_vue >= ^start_date,
      where: a.date_prise_vue <= ^end_date,
      order_by: [desc: a.date_prise_vue]
    )
    |> Repo.all()
  end
end

# Utilisation dans Context
defmodule Portfolio.Photography do
  def list_published_albums do
    AlbumRepository.list_published()
  end
end
```

Avantages :
- Encapsulation : Toute la logique d'acc�s Album dans un seul module
- Réutilisabilité : Évite duplication entre Contexts
- Testabilité : Repository testable en isolation
- Séparation des préoccupations : Context ne connaît pas les détails Ecto

Inconvénients :
- Duplication interne : Duplication de patterns de queries dans le Repository
- Difficile � composer : `list_published()` et `list_by_type()` sont séparées, difficile de combiner
- Prolifération de méthodes : Besoin d'une méthode pour chaque combinaison de filtres
- Repository devient énorme : Peut atteindre 500+ lignes avec toutes les queries métier

**Exemple de duplication interne :**
```elixir
def list_published do
  from(a in Album, 
    where: a.published == true,
    order_by: [desc: a.date_prise_vue]
  ) |> Repo.all()
end

def list_published_by_type(type) do
  from(a in Album, 
    where: a.published == true,  # Dupliqué
    where: a.type == ^type,
    order_by: [desc: a.date_prise_vue]  # Dupliqué
  ) |> Repo.all()
end
```

Effort estimé : Moyen

Risques :
- Repository devient God Object [Probabilité: Moyenne, Impact: Moyen]

### Option 3: Repository + Query Objects (Approche actuelle)

Description :

Séparer la **construction** des requêtes (Query Objects) et l'**exécution** (Repository). Les Query Objects fournissent des fonctions composables qui modifient une query, le Repository les orchestre et exécute.

Architecture :

```
Context
   �
Repository (Orchestration + Exécution)
   �
Query Objects (Construction composable)
   �
Ecto.Query
   �
Database
```

Implémentation :

```elixir
# Query Object : Construction composable
defmodule Portfolio.Photography.Queries.AlbumQuery do
  import Ecto.Query
  alias Portfolio.Photography.Album
  
  @doc "Query de base pour Album"
  def base, do: from(a in Album)
  
  @doc "Filtre les albums publiés"
  def published(query) do
    from a in query, where: a.published == true
  end
  
  @doc "Filtre par type d'album"
  def by_type(query, type) do
    from a in query, where: a.type == ^type
  end
  
  @doc "Filtre par plage de dates"
  def where_date_between(query, start_date, end_date) do
    from a in query,
      where: a.date_prise_vue >= ^start_date,
      where: a.date_prise_vue <= ^end_date
  end
  
  @doc "Tri par date décroissante"
  def order_by_date_desc(query) do
    from a in query, order_by: [desc: a.date_prise_vue]
  end
  
  @doc "Précharge des associations"
  def with_preload(query, preloads) do
    from a in query, preload: ^preloads
  end
end

# Repository : Orchestration + Exécution
defmodule Portfolio.Photography.Repositories.AlbumRepository do
  alias Portfolio.Photography.Queries.AlbumQuery
  alias Portfolio.Repo
  
  @doc "Liste des albums avec filtres composables"
  def list(filters \\ []) do
    AlbumQuery.base()
    |> apply_filters(filters)
    |> Repo.all()
  end
  
  @doc "Liste des albums publiés pour une année"
  def list_published_by_year(year, opts \\ []) do
    {:ok, start_date} = Date.new(year, 1, 1)
    {:ok, end_date} = Date.new(year, 12, 31)
    
    AlbumQuery.base()
    |> AlbumQuery.published()
    |> AlbumQuery.where_date_between(start_date, end_date)
    |> AlbumQuery.order_by_date_desc()
    |> maybe_preload(opts[:preload])
    |> Repo.all()
  end
  
  # Applique les filtres en utilisant Query Objects
  defp apply_filters(query, []), do: query
  
  defp apply_filters(query, [{:published, true} | rest]) do
    query |> AlbumQuery.published() |> apply_filters(rest)
  end
  
  defp apply_filters(query, [{:type, type} | rest]) do
    query |> AlbumQuery.by_type(type) |> apply_filters(rest)
  end
  
  defp apply_filters(query, [_other | rest]) do
    apply_filters(query, rest)
  end
end

# Utilisation dans Context (composition flexible)
def list_published_wedding_albums do
  AlbumRepository.list(published: true, type: :wedding)
end
```

Avantages :
- Composition puissante : Combiner des filtres facilement via pipeline
  ```elixir
  AlbumQuery.base()
  |> AlbumQuery.published()
  |> AlbumQuery.by_type(:wedding)
  |> AlbumQuery.order_by_date_desc()
  |> Repo.all()
  ```
- DRY : Chaque query composable est définie une seule fois, réutilisable partout
- **Open/Closed Principle** : Ajouter un nouveau filtre = ajouter une fonction dans Query Object, pas de modification du Repository
- Testabilité excellente : Query Objects testables sans exécuter la DB
  ```elixir
  test "published/1 adds published filter" do
    query = AlbumQuery.base() |> AlbumQuery.published()
    assert inspect(query) =~ "published == true"
  end
  ```
- Lisibilité : Pipeline Elixir naturel, intention claire
- Réutilisabilité : Query Objects utilisables dans Repository, Services, et même LiveView si nécessaire

Inconvénients :
- Deux fichiers : Navigation entre Query Object et Repository
- **Courbe d'apprentissage** : Développeurs juniors doivent comprendre la séparation
- **Over-engineering possible** : Pour requêtes tr�s simples, Query Object peut être overkill

Effort estimé : Moyen

Risques :
- Over-engineering pour petits projets [Probabilité: Faible, Impact: Faible]

## Décision

L'option choisie est: **Option 3 - Repository + Query Objects**

### Justification de la décision

**Crit�res de décision:**

- **Alignement avec Clean Architecture/DDD:** Excellente séparation des préoccupations. Le domaine (Album, Photo) ne dépend pas d'Ecto. Les Repositories et Query Objects sont dans l'Infrastructure Layer.

- **Impact sur la dette technique:** Réduit drastiquement la duplication de requêtes. Facilite les évolutions futures (ajouter un filtre = ajouter une fonction Query Object).

- **Maintenabilité:** Optimale. Query Objects sont de petits modules (< 150 lignes) focalisés. Repositories restent raisonnables (< 300 lignes). Facile de trouver une query.

- **Testabilité:** Excellente. Query Objects testables sans DB (test de construction de query). Repositories testables avec Ecto.Sandbox (test d'exécution).

- **Performance:** Neutre. Pas d'overhead runtime (composition � la compilation). Permet optimisations SQL si nécessaire.

- **Réutilisabilité:** Maximale. Query Objects réutilisables dans Repository, Services, LiveView queries.

- **Pragmatisme:** Bon équilibre. Pas d'over-engineering (pas de Event Sourcing, pas de CQRS complet), juste une séparation construction/exécution.

**Décision finale:**

Le pattern Repository + Query Objects est le meilleur compromis entre **organisation, réutilisabilité et pragmatisme**. Cette solution :

1. Respecte les principes Clean Architecture (séparation Infrastructure/Application/Domain)
2. Évite la duplication via composition de Query Objects
3. Facilite les tests (Query Objects sans DB, Repositories avec Sandbox)
4. Reste simple (pas de patterns complexes comme Event Sourcing)
5. S'aligne avec les bonnes pratiques Elixir (pipelines, composition)

Les principaux compromis acceptés :
- **Deux fichiers** au lieu d'un (Repository + Query Object) � Compensé par meilleure organisation
- **Courbe d'apprentissage** pour développeurs juniors � Compensé par documentation claire (cet ADR)


### Clarification : Quand utiliser Query Objects ?

**Important :** Query Objects ne sont pas obligatoires pour tous les contextes. Le choix dépend de la complexité des requêtes.

#### Seuil de décision

**Utiliser Query Objects SI le contexte a AU MOINS UN de ces critères :**

1. **Plus de 5 combinaisons de filtres** différentes dans les queries
2. **Logique de query réutilisée dans 3+ endroits** (Repository, Services, LiveView)
3. **Besoin de composition dynamique** (ex: filtres admin avec 10+ critères possibles)
4. **Queries complexes** avec multiples jointures, aggregations, window functions
5. **Contexte public avec filtrage riche** (ex: e-commerce avec 20+ filtres produits)

**Ne PAS utiliser Query Objects SI :**

1. **Queries simples** : Principalement `get_by_X`, `list_by_Y`, `delete_by_Z`
2. **Peu de variations** : 2-3 requêtes différentes au total
3. **Pas de composition** : Chaque query est standalone, pas de filtres combinables
4. **Contexte interne** : Admin simple, Auth, Configuration

#### Exemples concrets dans ce projet

##### Photography Context → AVEC Query Objects ✅

**Justification :**
- 50+ combinaisons de queries possibles (published × type × year × ordering)
- Composition dynamique nécessaire (filtres publics + filtres admin)
- Queries réutilisées dans Repository, Services, LiveView
- Complexité métier élevée (albums, photos, variants, exif, filtres multiples)

```elixir
# Composition riche
PhotoQuery.base()
|> PhotoQuery.published()          # Filtre 1
|> PhotoQuery.by_album(album_id)   # Filtre 2
|> PhotoQuery.order_by_date_desc() # Tri
|> PhotoQuery.with_preload([:album, :variants])  # Preload
|> Repo.all()
```

##### Auth Context → SANS Query Objects ✅

**Justification :**
- Queries simples : `get_by_email`, `get_by_token`, `list_by_user`
- Peu de variations (15-20 queries simples au total)
- Pas de composition nécessaire (chaque query est standalone)
- Contexte interne (pas de filtrage public complexe)

```elixir
# Queries simples directes dans Repository
def get_by_email(email) do
  case Repo.get_by(User, email: email) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end

def list_by_user(user_id, opts \\ []) do
  from(s in UserSession, where: s.user_id == ^user_id)
  |> Repo.all()
end
```

**Raison pragmatique :** Query Objects ajouteraient 200-300 lignes de code pour un gain minimal. Le code actuel est lisible, testable, et maintenable sans surarchitecture.

#### Décision architecturale

**Pattern Repository** : Obligatoire pour tous les contextes (séparation Infrastructure/Domain)
**Pattern Query Objects** : Optionnel, décision pragmatique basée sur la complexité

Cette approche hybride respecte les principes :
- **YAGNI** : Ne pas sur-architecturer Auth avec Query Objects non nécessaires
- **Clean Architecture** : Tous les contextes ont des Repositories (séparation Infrastructure)
- **Pragmatisme** : Choisir le bon outil selon le besoin réel

## Conséquences

### Positives

- Code DRY : Chaque query composable définie une seule fois, réutilisable partout
- Composition puissante : Combiner des filtres facilement via pipelines Elixir
- Testabilité excellente : Query Objects testables sans DB, Repositories avec Sandbox
- **Évolutivité** : Ajouter un filtre = ajouter une fonction, pas de modification des existantes (Open/Closed)
- Lisibilité : Intention claire avec noms de fonctions explicites
- Réutilisabilité maximale : Query Objects utilisables dans multiples contextes
- Maintenance facile : Petits modules focalisés, facile de trouver une query

### Négatives

- Navigation entre fichiers : Comprendre une query nécessite d'ouvrir Query Object + Repository (mais organisation logique compense)
- **Courbe d'apprentissage** : Développeurs juniors doivent comprendre la séparation (documentation nécessaire)
- **Potentiel over-engineering** : Pour requêtes tr�s simples (`get by id`), Query Object peut sembler lourd

### Neutres

- Deux modules par entité : `AlbumRepository` + `AlbumQuery`, `PhotoRepository` + `PhotoQuery` (organisation claire mais plus de fichiers)
- Convention � respecter : Équipe doit suivre les r�gles (Query Object = construction, Repository = exécution)

## Guide d'Utilisation : Repository Pattern Expliqué

Cette section est un guide éducatif pour comprendre et appliquer le Repository Pattern dans ce projet.

### Anatomie du Pattern : Trois Couches

```

�  Context (Application Layer)                    �
�  - API publique du bounded context              �
�  - Orchestre Repository + Services              �
�  - Ajoute telemetry, cache                      �
��
                     �
         �
         �                        �
         ��                        ��
    
�  Repository      �    �  Query Object        �
�  (Execution)     �>�  (Construction)      �
�                  �    �                      �
�  - CRUD          �    �  - base()            �
�  - Orchestration �    �  - published()       �
�  - Repo.all()    �    �  - by_type()         �
��    �
         �
         ��

�  Ecto + DB       �
�
```

### Query Objects : Construction Composable

**Responsabilité :** Fournir des fonctions qui construisent et modifient des queries Ecto de mani�re composable.

**R�gle d'or :** Une fonction Query Object prend une `query` en entrée et retourne une `query` modifiée. Jamais d'exécution (`Repo.all/one/aggregate`).

**Pattern standard :**

```elixir
defmodule Portfolio.Photography.Queries.AlbumQuery do
  import Ecto.Query
  alias Portfolio.Photography.Album
  
  @doc """
  Query de base pour Album.
  
  Point de départ pour toutes les queries Album.
  """
  @spec base() :: Ecto.Query.t()
  def base, do: from(a in Album)
  
  @doc """
  Filtre les albums publiés.
  
  ## Exemples
  
      iex> AlbumQuery.base() |> AlbumQuery.published() |> Repo.all()
      [%Album{published: true}, ...]
  """
  @spec published(Ecto.Query.t()) :: Ecto.Query.t()
  def published(query) do
    from a in query, where: a.published == true
  end
  
  @doc """
  Filtre par type d'album.
  
  ## Param�tres
  
  - `query` - Query Ecto � modifier
  - `type` - Type d'album (:wedding, :couples, :music, etc.)
  """
  @spec by_type(Ecto.Query.t(), atom()) :: Ecto.Query.t()
  def by_type(query, type) do
    from a in query, where: a.type == ^type
  end
end
```

**Avantages de cette approche :**

1. **Composition via pipeline**
   ```elixir
   # Lisible, expressif, fonctionnel
   AlbumQuery.base()
   |> AlbumQuery.published()
   |> AlbumQuery.by_type(:wedding)
   |> AlbumQuery.order_by_date_desc()
   |> Repo.all()
   ```

2. **Réutilisabilité totale**
   ```elixir
   # Dans AlbumRepository
   def list_published do
     AlbumQuery.base() |> AlbumQuery.published() |> Repo.all()
   end
   
   # Dans AlbumRepository, autre méthode
   def count_published do
     AlbumQuery.base() |> AlbumQuery.published() |> Repo.aggregate(:count)
   end
   
   # Dans Service, même query réutilisée
   def some_complex_workflow do
     query = AlbumQuery.base() |> AlbumQuery.published()
     # ...
   end
   ```

3. **Testabilité sans DB**
   ```elixir
   defmodule AlbumQueryTest do
     use ExUnit.Case
     
     test "published/1 adds published filter to query" do
       query = AlbumQuery.base() |> AlbumQuery.published()
       
       # Test sans exécuter la DB
       assert inspect(query) =~ "published == true"
     end
   end
   ```

### Repository : Orchestration et Exécution

**Responsabilité :** Orchestrer les Query Objects et exécuter les requêtes via `Repo`.

**R�gle d'or :** Repository = CRUD + méthodes métier qui utilisent Query Objects + `Repo.all/one/aggregate`.

**Pattern standard :**

```elixir
defmodule Portfolio.Photography.Repositories.AlbumRepository do
  import Ecto.Query
  alias Portfolio.Photography.{Album, Queries.AlbumQuery}
  alias Portfolio.Repo
  
  # ========================================
  # CRUD Standard
  # ========================================
  
  @doc """
  Ins�re un nouvel album.
  
  ## Exemples
  
      iex> insert(%{title: "Mon Album", type: :wedding})
      {:ok, %Album{}}
      
      iex> insert(%{title: ""})
      {:error, %Ecto.Changeset{}}
  """
  @spec insert(map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs) do
    %Album{}
    |> Album.changeset(attrs)
    |> Repo.insert()
  end
  
  @doc """
  Récup�re un album par son ID.
  
  ## Retour
  
  - `{:ok, album}` si trouvé
  - `{:error, :not_found}` si non trouvé
  
  ## Exemples
  
      iex> get("valid-uuid")
      {:ok, %Album{}}
      
      iex> get("invalid-uuid")
      {:error, :not_found}
  """
  @spec get(Ecto.UUID.t(), keyword()) :: {:ok, Album.t()} | {:error, :not_found}
  def get(id, opts \\ []) do
    case Repo.get(Album, id) do
      nil -> {:error, :not_found}
      album -> {:ok, maybe_preload(album, opts[:preload])}
    end
  end
  
  # ========================================
  # Méthodes Métier avec Query Objects
  # ========================================
  
  @doc """
  Liste des albums avec filtres composables.
  
  ## Filtres disponibles
  
  - `:published` - boolean
  - `:type` - atom
  - `:preload` - list of atoms
  - `:limit` - integer
  
  ## Exemples
  
      iex> list()
      [%Album{}, ...]
      
      iex> list(published: true, type: :wedding)
      [%Album{published: true, type: :wedding}]
  """
  @spec list(keyword()) :: [Album.t()]
  def list(filters \\ []) do
    AlbumQuery.base()
    |> apply_filters(filters)
    |> Repo.all()
  end
  
  @doc """
  Liste des albums publiés pour une année spécifique.
  
  Utilise Query Objects pour composer la requête.
  
  ## Param�tres
  
  - `year` - Année (integer 1..9999)
  - `opts` - Options [:preload]
  """
  @spec list_published_by_year(integer(), keyword()) :: [Album.t()]
  def list_published_by_year(year, opts \\ []) do
    {:ok, start_date} = Date.new(year, 1, 1)
    {:ok, end_date} = Date.new(year, 12, 31)
    
    # Composition via Query Objects
    AlbumQuery.base()
    |> AlbumQuery.published()
    |> AlbumQuery.where_date_between(start_date, end_date)
    |> AlbumQuery.order_by_date_desc()
    |> maybe_preload(opts[:preload])
    |> Repo.all()
  end
  
  # ========================================
  # Fonctions Privées d'Orchestration
  # ========================================
  
  defp apply_filters(query, []), do: query
  
  defp apply_filters(query, [{:published, true} | rest]) do
    query |> AlbumQuery.published() |> apply_filters(rest)
  end
  
  defp apply_filters(query, [{:type, type} | rest]) do
    query |> AlbumQuery.by_type(type) |> apply_filters(rest)
  end
  
  defp apply_filters(query, [{:preload, preloads} | rest]) do
    query |> AlbumQuery.with_preload(preloads) |> apply_filters(rest)
  end
  
  defp apply_filters(query, [_other | rest]), do: apply_filters(query, rest)
end
```

### Conventions de Retour : Guide Complet

Un des aspects les plus importants du Repository Pattern est la cohérence des types de retour. Voici le guide complet.

#### Convention 1 : Queries sur UNE entité � Tuple

**R�gle :** Si la fonction recherche UNE entité spécifique, retourner `{:ok, entity} | {:error, :not_found}`.

**Justification :** Distinction claire entre "trouvé" et "non trouvé". Permet de chaîner avec `with`.

```elixir
@spec get(Ecto.UUID.t(), keyword()) :: {:ok, Album.t()} | {:error, :not_found}
def get(id, opts \\ []) do
  case Repo.get(Album, id) do
    nil -> {:error, :not_found}
    album -> {:ok, album}
  end
end

@spec get_by_slug(String.t(), keyword()) :: {:ok, Album.t()} | {:error, :not_found}
def get_by_slug(slug, opts \\ []) do
  case Repo.get_by(Album, slug: slug) do
    nil -> {:error, :not_found}
    album -> {:ok, album}
  end
end

# Utilisation dans Context
def show_album(id) do
  with {:ok, album} <- AlbumRepository.get(id),
       {:ok, photos} <- PhotoRepository.list_by_album(album.id) do
    {:ok, %{album: album, photos: photos}}
  end
end
```

**Exception :** Fournir aussi une version bang (`get!`) qui raise si not found (convention Ecto).

```elixir
@spec get!(Ecto.UUID.t(), keyword()) :: Album.t()
def get!(id, opts \\ []) do
  Repo.get!(Album, id)
end
```

#### Convention 2 : Queries sur COLLECTIONS � Liste directe

**R�gle :** Si la fonction retourne plusieurs entités, retourner `[entity]` directement (jamais de tuple).

**Justification :** Liste vide est un résultat valide, pas une erreur. Wrapping inutile.

```elixir
@spec list(keyword()) :: [Album.t()]
def list(filters \\ []) do
  AlbumQuery.base()
  |> apply_filters(filters)
  |> Repo.all()
end

@spec list_by_album(Ecto.UUID.t()) :: [Photo.t()]
def list_by_album(album_id) do
  PhotoQuery.base()
  |> PhotoQuery.by_album(album_id)
  |> Repo.all()
end

# Utilisation dans Context
def list_albums do
  albums = AlbumRepository.list()  # [] si vide, pas d'erreur
  
  case albums do
    [] -> {:ok, :empty}
    albums -> {:ok, albums}
  end
end
```

Pourquoi pas `{:ok, []} | {:error, :not_found}` ?

Parce que liste vide n'est pas une erreur. C'est un résultat valide signifiant "aucun album ne correspond aux crit�res".

#### Convention 3 : Aggregations/Compteurs � Valeur directe

**R�gle :** Si la fonction retourne un compteur ou une aggregation, retourner la valeur directement.

**Justification :** Compter ne peut jamais "échouer". Minimum retourné : 0.

```elixir
@spec count_all() :: non_neg_integer()
def count_all do
  Repo.aggregate(Album, :count)
end

@spec count_published() :: non_neg_integer()
def count_published do
  AlbumQuery.base()
  |> AlbumQuery.published()
  |> Repo.aggregate(:count)
end

# Utilisation dans Context
def stats do
  total = AlbumRepository.count_all()        # 0 si vide
  published = AlbumRepository.count_published()  # 0 si aucun publié
  
  {:ok, %{total: total, published: published}}
end
```

**Erreur � éviter :**

```elixir
# - Inutile de wrapper
def count_all do
  {:ok, Repo.aggregate(Album, :count)}
end

# - Forcerait � unwrapper partout
{:ok, count} = AlbumRepository.count_all()
```

#### Convention 4 : Mutations (CUD) � Tuple Ecto

**R�gle :** Create, Update, Delete retournent toujours `{:ok, entity} | {:error, changeset}` (convention Ecto).

**Justification :** Validation peut échouer. Changeset contient les erreurs de validation.

```elixir
@spec insert(map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
def insert(attrs) do
  %Album{}
  |> Album.changeset(attrs)
  |> Repo.insert()
end

@spec update(Album.t(), map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
def update(album, attrs) do
  album
  |> Album.changeset(attrs)
  |> Repo.update()
end

@spec delete(Album.t()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
def delete(album) do
  Repo.delete(album)
end

# Utilisation dans Context
def create_album(attrs) do
  case AlbumRepository.insert(attrs) do
    {:ok, album} -> 
      Logger.info("Album created", album_id: album.id)
      {:ok, album}
      
    {:error, changeset} ->
      Logger.error("Album creation failed", errors: changeset.errors)
      {:error, changeset}
  end
end
```

#### Convention 5 : Opérations complexes � Tuple explicite

**R�gle :** Opérations avec multiples raisons d'échec retournent `{:ok, result} | {:error, reason}` avec `reason` explicite.

```elixir
@spec reorder(Ecto.UUID.t(), [Ecto.UUID.t()]) :: {:ok, integer()} | {:error, :invalid_photos | :database_error}
def reorder(album_id, photo_ids) do
  # Multiples raisons d'échec possibles
  with {:ok, _photos} <- validate_photos_belong_to_album(album_id, photo_ids),
       {:ok, count} <- execute_reorder_query(photo_ids) do
    {:ok, count}
  else
    {:error, :invalid_photos} -> {:error, :invalid_photos}
    {:error, reason} -> {:error, :database_error}
  end
end
```

#### Tableau récapitulatif

| Type d'opération | Retour | Exemple |
|-----------------|--------|---------|
| Get une entité | `{:ok, entity} \| {:error, :not_found}` | `get(id)`, `get_by_slug(slug)` |
| Get une entité (bang) | `entity \| raises` | `get!(id)` |
| Liste/Collection | `[entity]` | `list()`, `list_by_album(id)` |
| Compteur/Aggregation | `integer` | `count_all()`, `count_published()` |
| Mutation (CUD) | `{:ok, entity} \| {:error, changeset}` | `insert()`, `update()`, `delete()` |
| Opération complexe | `{:ok, result} \| {:error, reason}` | `reorder()`, `complex_query()` |

### Méthodes Spécifiques vs Génériques : Guide de Décision

**Question :** Faut-il créer une méthode Repository pour chaque besoin métier ou privilégier des méthodes génériques avec filtres ?

#### Approche Hybride Recommandée

**R�gle pragmatique :**

1. **Méthodes génériques pour CRUD + filtres simples**
   ```elixir
   def list(filters \\ [])  # Accepte :type, :published, :preload, :limit
   def get(id, opts \\ [])
   def insert(attrs)
   def update(entity, attrs)
   def delete(entity)
   ```

2. **Méthodes spécifiques pour use cases métier complexes**
   ```elixir
   def list_published_by_year(year, opts \\ [])
   def list_published_years()  # SQL optimisé EXTRACT(YEAR)
   def count_by_processing_status()  # GROUP BY aggregation
   def reorder(album_id, photo_ids)  # SQL complexe avec CASE WHEN
   ```

#### Crit�res de Décision

**Créer une méthode spécifique si AU MOINS UN crit�re :**

| Crit�re | Exemple |
|---------|---------|
| - SQL optimisé nécessaire | `list_published_years()` avec `EXTRACT(YEAR)` |
| - Aggregation complexe (GROUP BY) | `count_by_processing_status()` |
| - Use case métier nommé | `list_published_by_year(year)` |
| - SQL brut requis | `reorder(album_id, photo_ids)` avec CASE WHEN |
| - Logique orchestration complexe | Validation + transaction + rollback |

**Utiliser méthode générique si :**

| Crit�re | Exemple |
|---------|---------|
| - Filtres simples (1-3 where clauses) | `list(type: :wedding, published: true)` |
| - Combinaison rare de filtres | Pas besoin de `list_wedding_published_with_photos()` |
| - Query Ecto standard | Simple `where`, `order_by`, `preload` |

#### Exemples Concrets

**- Méthode spécifique justifiée : SQL optimisé**

```elixir
@doc """
Liste les années ayant des albums publiés.

Utilise SQL optimisé avec EXTRACT(YEAR) pour éviter de charger
tous les albums. Plus rapide que `list() |> Enum.map(&(&1.year))`.
"""
def list_published_years do
  from(a in Album,
    where: a.published == true,
    select: fragment("CAST(EXTRACT(YEAR FROM ?) AS INTEGER)", a.date_prise_vue),
    distinct: true,
    order_by: [desc: fragment("CAST(EXTRACT(YEAR FROM ?) AS INTEGER)", a.date_prise_vue)]
  )
  |> Repo.all()
end
```

**- Méthode spécifique justifiée : Aggregation GROUP BY**

```elixir
@doc """
Compte les photos par statut de traitement.

Retourne une map avec compteurs pour chaque statut.
"""
def count_by_processing_status do
  query =
    from p in Photo,
      select: {p.processing_status, count(p.id)},
      group_by: p.processing_status
  
  results = Repo.all(query)
  
  # Transform en map user-friendly
  %{
    pending: get_count(results, "pending"),
    processing: get_count(results, "processing"),
    completed: get_count(results, "completed"),
    failed: get_count(results, "failed")
  }
end
```

**- Méthode générique suffit : Filtres simples**

```elixir
# - Inutile de créer
def list_published_wedding_albums do
  AlbumQuery.base()
  |> AlbumQuery.published()
  |> AlbumQuery.by_type(:wedding)
  |> Repo.all()
end

# - Utiliser méthode générique
AlbumRepository.list(published: true, type: :wedding)
```

### SQL Brut dans Repository : Quand et Comment

**Question :** Quand est-il acceptable d'utiliser SQL brut (`Repo.query`) dans un Repository au lieu d'Ecto.Query ?

#### R�gle de Décision

**- SQL brut justifié si AU MOINS UN crit�re :**

1. **Ecto ne peut pas exprimer la requête** (ou tr�s difficilement)
   - CASE WHEN dynamique avec N conditions
   - Window functions complexes
   - Recursive CTEs
   - Fonctions PostgreSQL spécifiques non supportées par Ecto

2. **Optimisation critique** (apr�s profiling avec EXPLAIN ANALYZE)
   - Requête Ecto gén�re un plan SQL sous-optimal
   - Différence de performance mesurable (> 2x)
   - Query fréquente (hot path)

3. **Batch operations atomiques**
   - UPDATE de N lignes en une seule requête
   - INSERT de N lignes avec COPY
   - Opération atomique critique

**- SQL brut déconseillé si :**

1. Ecto peut exprimer facilement la requête
2. Pas de bénéfice performance réel (toujours profiler avant)
3. Perte de portabilité (requête spécifique PostgreSQL sans alternative)

#### Exemple Justifié : `PhotoRepository.reorder/2`

**Contexte :** Réorganiser l'ordre d'affichage de N photos en une seule requête atomique.

**Alternative Ecto (na�ve) :**

```elixir
# - N requêtes UPDATE (lent, pas atomique)
def reorder_naive(album_id, photo_ids) do
  photo_ids
  |> Enum.with_index()
  |> Enum.each(fn {photo_id, index} ->
    from(p in Photo, where: p.id == ^photo_id)
    |> Repo.update_all(set: [display_order: index, updated_at: DateTime.utc_now()])
  end)
end

# Probl�me : N requêtes, pas atomique, lent
```

**Solution SQL brut (optimisée) :**

```elixir
# - 1 seule requête UPDATE avec CASE WHEN (atomique, rapide)
def reorder(album_id, photo_ids) when is_list(photo_ids) do
  multi =
    Ecto.Multi.new()
    |> Ecto.Multi.run(:validate_photos, fn _repo, _changes ->
      validate_photos_belong_to_album(album_id, photo_ids)
    end)
    |> Ecto.Multi.run(:reorder_photos, fn repo, %{validate_photos: _photos} ->
      execute_reorder_query(repo, photo_ids)
    end)
  
  case Repo.transaction(multi) do
    {:ok, %{reorder_photos: count}} -> {:ok, count}
    {:error, :validate_photos, :invalid_photos, _} -> {:error, :invalid_photos}
    {:error, _step, reason, _} -> {:error, reason}
  end
end

defp execute_reorder_query(repo, photo_ids) do
  query = """
  UPDATE photos
  SET
    display_order = CASE
      #{build_case_when_clauses(photo_ids)}
    END,
    updated_at = $1
  WHERE id = ANY($#{length(photo_ids) + 2}::uuid[])
  """
  
  params = [DateTime.utc_now()] ++ 
           Enum.map(photo_ids, &Ecto.UUID.dump!/1) ++ 
           [Enum.map(photo_ids, &Ecto.UUID.dump!/1)]
  
  case repo.query(query, params) do
    {:ok, %{num_rows: count}} -> {:ok, count}
    {:error, reason} -> {:error, reason}
  end
end

defp build_case_when_clauses(photo_ids) do
  photo_ids
  |> Enum.with_index()
  |> Enum.map_join(" ", fn {_id, idx} ->
    "WHEN id = $#{idx + 2}::uuid THEN #{idx}"
  end)
end
```

**Justification :**

- - Atomicité : Toutes les photos mises � jour en 1 transaction
- - Performance : 1 requête vs N requêtes (O(1) vs O(N))
- - Ecto limité : Difficile d'exprimer CASE WHEN dynamique en Ecto
- - Encapsulation : SQL brut caché dans Repository, interface propre

**Bonne pratique appliquée :**

```elixir
@doc """
Réorganise l'ordre d'affichage des photos atomiquement.

**Implémentation SQL brute** : Cette fonction utilise une requête
SQL avec CASE WHEN pour mettre � jour toutes les photos en une
seule transaction atomique.

Alternative Ecto (non utilisée) :
- Enum.each avec update individuel = N requêtes DB
- Performance : O(N) requêtes vs O(1) requête

## Performance

Benchmark sur 50 photos :
- SQL brut : ~15ms
- Ecto na�f : ~250ms (16x plus lent)

## Param�tres

- `album_id` - ID de l'album contenant les photos
- `photo_ids` - Liste ordonnée des IDs (premier = display_order 0)

## Exemples

    iex> reorder(album_id, [photo3_id, photo1_id, photo2_id])
    {:ok, 3}
"""
@spec reorder(Ecto.UUID.t(), [Ecto.UUID.t()]) :: {:ok, integer()} | {:error, :invalid_photos}
def reorder(album_id, photo_ids), do: # ...
```

## Plan d'action

### Phase 1: Audit Acc�s Direct � Repo (Priorité: CRITIQUE)

**Objectif :** Vérifier que tous les acc�s DB passent bien par les Repositories.

Tâches :

1. **Grep tous les appels directs � Repo**
   ```bash
   grep -r "Repo\.\(all\|one\|get\|insert\|update\|delete\|aggregate\)" lib/portfolio --exclude-dir=repositories
   ```

2. **Identifier les violations**
   - Contexts appelant `Repo` directement
   - Services appelant `Repo` directement
   - LiveViews appelant `Repo` directement

3. **Créer todo list des refactorings**
   - Prioriser par criticité (Contexts > Services > LiveViews)
   - Estimer effort de refactoring

Crit�res de succ�s :
- Zéro appel direct � `Repo` en dehors de `/repositories` et `/queries`
- Todo list priorisée créée

**Estimation:** 0.5 jour

### Phase 2: Standardisation Retours Repository (Priorité: HAUTE)

**Objectif :** Harmoniser les conventions de retour selon le guide défini.

Tâches :

1. **Auditer tous les Repositories**
   - Vérifier les retours de `get/get_by_X` � Tuple 
   - Vérifier les retours de `list/list_by_X` � Liste directe 
   - Vérifier les retours de `count_X` � Integer direct 
   - Vérifier les retours de `insert/update/delete` � Tuple 

2. **Corriger les incohérences**
   - Actuellement : Aucune correction majeure nécessaire (déj� cohérent )
   - Documenter les conventions dans `@moduledoc` de chaque Repository

3. **Créer tests pour valider conventions**
   ```elixir
   test "get/1 returns tuple {:ok, entity} when found" do
     album = album_fixture()
     assert {:ok, ^album} = AlbumRepository.get(album.id)
   end
   
   test "get/1 returns {:error, :not_found} when not found" do
     assert {:error, :not_found} = AlbumRepository.get(Ecto.UUID.generate())
   end
   
   test "list/0 returns list (empty if no results)" do
     assert [] = AlbumRepository.list()
     
     album_fixture()
     assert [%Album{}] = AlbumRepository.list()
   end
   
   test "count_all/0 returns integer directly" do
     assert 0 = AlbumRepository.count_all()
     
     album_fixture()
     assert 1 = AlbumRepository.count_all()
   end
   ```

Crit�res de succ�s :
- Conventions documentées dans chaque Repository
- Tests couvrant les conventions

**Estimation:** 1 jour

### Phase 3: Documentation Pattern Repository (Priorité: HAUTE)

Tâches :

1. **Documenter séparation Repository/Query Objects**
   - Expliquer pourquoi deux modules (cet ADR )
   - Créer exemples commentés
   - Ajouter diagrammes si nécessaire

2. **Créer guide de décision méthodes spécifiques vs génériques**
   - Tableau de décision
   - Exemples de chaque cas
   - Anti-patterns � éviter

3. **Documenter quand utiliser SQL brut**
   - Crit�res de justification
   - Pattern `@doc` avec explication
   - Exemples de profiling (EXPLAIN ANALYZE)

4. **Ajouter ce contenu dans README ou `/docs`**

Crit�res de succ�s :
- Documentation compl�te accessible
- Développeurs juniors peuvent suivre le guide

**Estimation:** 1 jour

### Phase 4: Tests Repositories (Priorité: MOYENNE)

**Objectif :** Assurer couverture de test compl�te des Repositories.

Tâches :

1. **Vérifier stratégie de test actuelle**
   - Utilisation d'Ecto.Sandbox (recommandé )
   - Pas de mocking des Repositories (bon choix )

2. **Créer tests manquants**
   - Tous les Repositories doivent avoir tests CRUD
   - Tests des méthodes métier spécifiques
   - Tests des cas d'erreur (not_found, changeset invalid)

3. **Pattern de test standard**
   ```elixir
   defmodule Portfolio.Photography.Repositories.AlbumRepositoryTest do
     use Portfolio.DataCase, async: true
     
     alias Portfolio.Photography.Repositories.AlbumRepository
     
     describe "insert/1" do
       test "creates album with valid attrs" do
         attrs = %{title: "Test", type: :wedding, date_prise_vue: ~D[2024-01-01]}
         assert {:ok, album} = AlbumRepository.insert(attrs)
         assert album.title == "Test"
       end
       
       test "returns error with invalid attrs" do
         attrs = %{title: ""}
         assert {:error, changeset} = AlbumRepository.insert(attrs)
         assert "can't be blank" in errors_on(changeset).title
       end
     end
     
     describe "get/1" do
       test "returns {:ok, album} when found" do
         album = album_fixture()
         assert {:ok, found} = AlbumRepository.get(album.id)
         assert found.id == album.id
       end
       
       test "returns {:error, :not_found} when not found" do
         assert {:error, :not_found} = AlbumRepository.get(Ecto.UUID.generate())
       end
     end
   end
   ```

Crit�res de succ�s :
- Coverage > 90% sur tous les Repositories
- Tests pour happy path + error cases

**Estimation:** 2 jours

### Phase 5: Optimisations SQL (Priorité: BASSE)

**Objectif :** Identifier et optimiser les requêtes lentes.

Tâches :

1. **Profiler les requêtes existantes**
   ```elixir
   # Ajouter dans Repository pour debug
   query
   |> Repo.all()
   |> tap(fn results ->
     # En dev uniquement
     if Mix.env() == :dev do
       IO.inspect(Repo.explain(:all, query), label: "EXPLAIN")
     end
   end)
   ```

2. **Identifier les N+1 queries**
   - Vérifier les preloads manquants
   - Ajouter preloads dans Query Objects

3. **Auditer SQL brut existant**
   - `PhotoRepository.reorder/2` � Justifié 
   - Autres queries SQL brutes ? � Documenter justification

4. **Ajouter indexes si nécessaire**
   - Albums : `published`, `type`, `date_prise_vue`
   - Photos : `album_id`, `display_order`, `processing_status`

Crit�res de succ�s :
- Aucune N+1 query détectée
- Toutes les queries < 50ms (95th percentile)

**Estimation:** 1 jour

### Rollback Plan

Si le pattern Repository + Query Objects pose des probl�mes :

1. **Identifier les Repositories problématiques**
   - Trop complexes (> 500 lignes)
   - Query Objects inutilisés
   - Trop de méthodes spécifiques

2. **Options de simplification**
   - Fusionner Query Object dans Repository si peu utilisé
   - Supprimer méthodes spécifiques peu utilisées
   - Revenir � Ecto direct dans Context si Repository = simple proxy

3. **Documenter les raisons** du rollback pour apprentissage

**Probabilité de rollback:** Tr�s faible (architecture solide et éprouvée)

## Repositories Existants Analysés

### AlbumRepository - Bien Structuré

**Fichier:** `lib/portfolio/photography/repositories/album_repository.ex`

**Points forts :**
- - Séparation claire : Utilise `AlbumQuery` pour construction
- - Conventions retour cohérentes : Tuples pour `get`, liste pour `list`, integer pour `count`
- - Méthodes spécifiques justifiées :
  - `list_published_years()` � SQL optimisé EXTRACT(YEAR)
  - `list_published_by_year(year)` � Use case métier nommé
  - `list_published_by_year()` � Groupement par année
- - Documentation compl�te avec `@moduledoc` et `@doc`
- - CRUD standard : insert, update, delete, get, list

**Améliorations possibles :**
- Documenter pourquoi `list_published_years()` utilise SQL optimisé
- Ajouter benchmark dans documentation

**Verdict :** Exemple de référence 

### PhotoRepository - Bien Structuré avec SQL Brut Justifié

**Fichier:** `lib/portfolio/photography/repositories/photo_repository.ex`

**Points forts :**
- - Utilise `PhotoQuery` pour composition
- - SQL brut justifié dans `reorder/2` :
  - Atomicité : UPDATE de N photos en 1 requête
  - Performance : CASE WHEN plus rapide que N updates
  - Bien encapsulé : Interface simple, complexité cachée
- - Méthodes métier spécifiques :
  - `count_by_processing_status()` � GROUP BY aggregation
  - `get_oldest_by_processing_status()` � Use case monitoring
  - `list_by_processing_status()` � Filtrage métier
- - Validation business dans `reorder/2` (photos appartiennent � l'album)
- - Transaction Ecto.Multi pour atomicité

**Améliorations possibles :**
- Documenter benchmark de `reorder/2` (SQL brut vs Ecto na�f)
- Ajouter `@doc` expliquant pourquoi SQL brut nécessaire

**Verdict :** Excellent exemple de SQL brut justifié 

## Références

- [Repository Pattern - Martin Fowler](https://martinfowler.com/eaaCatalog/repository.html)
- [Ecto Query Composition](https://hexdocs.pm/ecto/Ecto.Query.html#module-composition)
- [Railway Oriented Programming - F#](https://fsharpforfunandprofit.com/rop/)
- [Clean Architecture - Robert C. Martin](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- Code source :
  - `lib/portfolio/photography/repositories/album_repository.ex`
  - `lib/portfolio/photography/repositories/photo_repository.ex`
  - `lib/portfolio/photography/queries/album_query.ex`
  - `lib/portfolio/photography/queries/photo_query.ex`

## Notes

### Pourquoi Repository avec Ecto ? Réponse Approfondie

Cette question revient souvent : **"Ecto est déj� une abstraction, pourquoi ajouter Repository ?"**

**Réponse courte :** Repository n'est pas pour abstraire la DB (Ecto le fait déj�), mais pour **encapsuler les requêtes métier réutilisables**.

**Réponse longue :**

Ecto abstrait excellemment la DB (changesets, migrations, queries). Mais Ecto ne résout pas :
1. **Duplication de requêtes** entre Contexts (Admin, API, Public)
2. **Composition de filtres** complexes (published + type + year)
3. **Testabilité des queries** sans exécuter la DB
4. **Encapsulation de SQL optimisé** (EXTRACT, GROUP BY, CASE WHEN)

Repository + Query Objects résout ces probl�mes en ajoutant une couche de **composition métier** par-dessus Ecto.

**Analogie :**

```
Ecto = Marteau (outil de base)
Repository = Établi de menuisier (organisation des outils)
Query Objects = Gabarits réutilisables (patterns de coupe)
```

Ecto seul = travailler avec un marteau par terre.  
Repository = travailler sur un établi organisé avec gabarits.

### Alternative : Scopes Ecto (Non Retenue)

Certains projets Elixir utilisent des **scopes** (inspirés de Rails) au lieu de Query Objects.

```elixir
defmodule Album do
  use Ecto.Schema
  
  # Scopes dans le schema
  def published(query \\ __MODULE__) do
    from a in query, where: a.published == true
  end
  
  def by_type(query \\ __MODULE__, type) do
    from a in query, where: a.type == ^type
  end
end

# Utilisation
Album.published() |> Album.by_type(:wedding) |> Repo.all()
```

**Pourquoi pas retenu :**

1. Mélange Schema et Queries : Viole Single Responsibility
2. Schema devient gros : Schemas > 500 lignes
3. Difficile � tester : Scopes dépendent du Schema
4. Moins flexible : Query Objects sont des modules séparés, plus composables

**Verdict :** Query Objects séparés sont préférables pour ce projet.

### Migration Future : CQRS

Si le projet évolue vers **CQRS** (Command Query Responsibility Segregation) :

**Command Side :** Repositories actuels (Write Model)  
**Query Side :** Nouveaux Query Services (Read Model optimisé)

```elixir
# Command Side (écriture)
AlbumRepository.insert(attrs)
AlbumRepository.update(album, attrs)

# Query Side (lecture optimisée)
AlbumQueryService.list_published_by_year_with_stats(2024)
# � Lecture depuis une vue matérialisée ou cache
```

Cette migration serait naturelle car les Repositories sont déj� séparés des Queries.

---

**Date de création:** 2025-11-11  
**Derni�re révision:** 2025-11-11
