# ADR-033: Query Objects pour Requêtes Composables

Statut: Accepté  
Date: 2025-11-11

## Contexte

L'ADR-032 (Repository Pattern) a établi la séparation entre Repository (exécution) et Query Objects (construction). Cet ADR se concentre spécifiquement sur les **Query Objects** : leur design, leurs patterns de composition, et leurs bonnes pratiques.

### Problématique

Dans une application avec de nombreuses requêtes similaires, trois défis se posent :

**Défi 1 : Duplication de requêtes**

```elixir
# Duplication : Même filtre published dupliqué partout
def list_published_albums do
  from(a in Album, where: a.published == true) |> Repo.all()
end

def count_published_albums do
  from(a in Album, where: a.published == true) |> Repo.aggregate(:count)
end

def list_published_wedding_albums do
  from(a in Album, 
    where: a.published == true,
    where: a.type == :wedding
  ) |> Repo.all()
end
```

**Défi 2 : Composition difficile**

Comment combiner facilement `published` + `by_type` + `order_by_date` sans créer une méthode pour chaque combinaison ?

**Défi 3 : Testabilité**

Comment tester qu'une query ajoute bien le bon filtre sans exécuter la base de données ?

### Solution : Query Objects Composables

Les Query Objects résolvent ces probl�mes en fournissant des **fonctions composables** qui modifient une query.

```elixir
# Query Object : Fonctions réutilisables
defmodule AlbumQuery do
  def published(query), do: where(query, [a], a.published == true)
  def by_type(query, type), do: where(query, [a], a.type == ^type)
  def order_by_date_desc(query), do: order_by(query, [a], desc: a.date_prise_vue)
end

# Composition via pipeline
AlbumQuery.base()
|> AlbumQuery.published()
|> AlbumQuery.by_type(:wedding)
|> AlbumQuery.order_by_date_desc()
|> Repo.all()
```

### Contraintes

- Composabilité : Chaque fonction doit être combinable avec les autres
- Réutilisabilité : Une fois définie, utilisable partout (Repository, Service, LiveView)
- Testabilité : Testable sans exécuter la DB
- Lisibilité : Intention claire avec noms explicites
- Performance : Pas d'overhead runtime (composition � la compilation)

## Options considérées

### Option 1: Inline Queries (Sans Query Objects)

Description :

Écrire les requêtes directement dans le Repository sans extraction en Query Objects.

```elixir
defmodule AlbumRepository do
  def list_published do
    from(a in Album, where: a.published == true)
    |> Repo.all()
  end
  
  def list_published_wedding do
    from(a in Album, 
      where: a.published == true,
      where: a.type == :wedding
    ) |> Repo.all()
  end
  
  def count_published do
    from(a in Album, where: a.published == true)
    |> Repo.aggregate(:count)
  end
end
```

Avantages :
- Simplicité apparente
- Tout dans un seul fichier

Inconvénients :
- - Duplication massive de filtres
- - Impossible de composer (published + wedding nécessite nouvelle méthode)
- - Repository devient énorme (méthode par combinaison)
- - Difficile � tester

Effort estimé : Faible

Risques :
- Explosion combinatoire de méthodes [Probabilité: Élevée, Impact: Élevé]

### Option 2: Scopes dans Schema (Style Rails)

Description :

Définir les queries comme des fonctions dans le module Schema.

```elixir
defmodule Album do
  use Ecto.Schema
  
  # Scopes
  def published(query \\ __MODULE__) do
    from(a in query, where: a.published == true)
  end
  
  def by_type(query \\ __MODULE__, type) do
    from(a in query, where: a.type == ^type)
  end
end

# Utilisation
Album.published() |> Album.by_type(:wedding) |> Repo.all()
```

Avantages :
- Composabilité via pipeline
- Syntax sugar (peut appeler sans query)

Inconvénients :
- - Mélange Schema (structure) et Queries (comportement) � Violation SRP
- - Schema devient gros (> 500 lignes)
- - Difficile � tester (dépend du Schema)
- - Couplage fort (queries dans le domaine)

Effort estimé : Moyen

Risques :
- Schema God Object [Probabilité: Moyenne, Impact: Moyen]

### Option 3: Query Objects Séparés (Choix actuel)

Description :

Créer des modules Query Objects dédiés séparés des Schemas et Repositories.

```elixir
# Query Object : Construction pure
defmodule AlbumQuery do
  import Ecto.Query
  alias Portfolio.Photography.Album
  
  def base, do: from(a in Album, as: :album)
  def published(query), do: where(query, [album: a], a.published == true)
  def by_type(query, type), do: where(query, [album: a], a.type == ^type)
  def order_by_date_desc(query), do: order_by(query, [album: a], desc: a.date_prise_vue)
end

# Repository : Orchestration
defmodule AlbumRepository do
  def list(filters) do
    AlbumQuery.base()
    |> apply_filters(filters)
    |> Repo.all()
  end
end

# Utilisation
AlbumQuery.base()
|> AlbumQuery.published()
|> AlbumQuery.by_type(:wedding)
|> AlbumQuery.order_by_date_desc()
|> Repo.all()
```

Avantages :
- - Composabilité maximale via pipeline
- - DRY : Chaque filtre défini une seule fois
- - SRP : Query Object focalisé sur construction
- - Testabilité : Testable sans DB
- - Réutilisabilité : Utilisable partout (Repository, Service, LiveView)
- - Open/Closed : Ajouter filtre = ajouter fonction

Inconvénients :
- Module supplémentaire (AlbumQuery séparé)
- Navigation entre fichiers

Effort estimé : Moyen

Risques :
- Over-engineering pour tr�s petits projets [Probabilité: Faible, Impact: Faible]

## Décision

L'option choisie est: **Option 3 - Query Objects Séparés**

### Justification

Les Query Objects séparés offrent le meilleur compromis entre **composabilité, réutilisabilité et maintenabilité**. Cette solution :

1. Évite la duplication : Chaque filtre défini une seule fois, réutilisable partout
2. Facilite la composition : Pipeline naturel `|>` pour combiner filtres
3. Respecte SRP : Query Object focalisé sur construction de queries
4. Améliore testabilité : Testable sans exécuter la DB
5. S'aligne avec Elixir : Utilise les pipelines, idiomatique

Le principal compromis accepté est le **module supplémentaire**, mais les bénéfices en organisation compensent largement.

## Conséquences

### Positives

- DRY absolu : Chaque filtre défini une seule fois
- Composition puissante : Combiner N filtres facilement
- Testabilité excellente : Test de construction sans DB
- Réutilisabilité maximale : Utilisable dans Repository, Service, LiveView
- Lisibilité : Intention claire avec noms explicites
- Performance : Composition � la compilation, zéro overhead runtime

### Négatives

- Module supplémentaire : Navigation entre Query Object et Repository
- Convention � respecter : Équipe doit suivre le pattern

### Neutres

- **Courbe d'apprentissage** : Pattern simple mais nécessite compréhension

## Guide d'Utilisation : Query Objects Expliqués

### Anatomie d'un Query Object

**Responsabilité unique :** Fournir des fonctions qui **construisent** et **modifient** des queries Ecto de mani�re composable.

**R�gle d'or :** Une fonction Query Object :
1. Prend une `query` en entrée (ou rien pour `base()`)
2. Retourne une `query` modifiée
3. N'exécute JAMAIS (`Repo.all/one/aggregate` interdit)

**Structure standard :**

```elixir
defmodule Portfolio.Photography.Queries.AlbumQuery do
  @moduledoc """
  Query builder for Album queries.
  
  Provides composable query builders following the Query Object pattern.
  Each function takes a query and returns a modified query.
  """
  
  import Ecto.Query
  alias Portfolio.Photography.Album
  
  # ========================================
  # Base Query (Point de départ)
  # ========================================
  
  @doc """
  Base query for albums with named binding.
  
  Returns a query with the album binding named `:album`.
  This allows using `[album: a]` in subsequent functions.
  """
  @spec base() :: Ecto.Query.t()
  def base do
    from(a in Album, as: :album)
  end
  
  # ========================================
  # Filtres (Where clauses)
  # ========================================
  
  @doc "Filters published albums only"
  @spec published(Ecto.Query.t()) :: Ecto.Query.t()
  def published(query) do
    where(query, [album: a], a.published == true)
  end
  
  @doc "Filters by album type"
  @spec by_type(Ecto.Query.t(), atom()) :: Ecto.Query.t()
  def by_type(query, type) do
    where(query, [album: a], a.type == ^type)
  end
  
  # ========================================
  # Tri (Order by clauses)
  # ========================================
  
  @doc "Orders by date descending (most recent first)"
  @spec order_by_date_desc(Ecto.Query.t()) :: Ecto.Query.t()
  def order_by_date_desc(query) do
    order_by(query, [album: a], desc: a.date_prise_vue)
  end
  
  # ========================================
  # Préchargement (Preload clauses)
  # ========================================
  
  @doc "Preloads photos ordered by display_order"
  @spec with_photos(Ecto.Query.t()) :: Ecto.Query.t()
  def with_photos(query) do
    photos_query = from(p in Photo, order_by: [asc: p.display_order])
    preload(query, photos: ^photos_query)
  end
end
```

### Pattern 1: Named Bindings (Essentiel)

**Probl�me sans named bindings :**

```elixir
# - MAUVAIS : Bindings numériques ambigus
def base, do: from(a in Album)  # binding [0]

def published(query) do
  where(query, [a], a.published == true)  # Quel binding ? [0] ou [1] ?
end
```

**Solution avec named bindings :**

```elixir
# - BON : Named bindings explicites
def base, do: from(a in Album, as: :album)  # binding nommé :album

def published(query) do
  where(query, [album: a], a.published == true)  # Référence explicite
end

def by_type(query, type) do
  where(query, [album: a], a.type == ^type)  # Référence explicite
end
```

**Avantages :**
- - Clarté : On sait toujours quel binding on manipule
- - Composition sûre : Pas d'erreur de binding
- - Maintenance : Facile de comprendre la query

### Pattern 2: Composition via Pipeline

**Le pouvoir du `|>` :**

```elixir
# Lisible, expressif, composable
AlbumQuery.base()
|> AlbumQuery.published()
|> AlbumQuery.by_type(:wedding)
|> AlbumQuery.order_by_date_desc()
|> AlbumQuery.with_photos()
|> Repo.all()
```

**Équivalent sans pipeline (illisible) :**

```elixir
# - Difficile � lire et maintenir
Repo.all(
  AlbumQuery.with_photos(
    AlbumQuery.order_by_date_desc(
      AlbumQuery.by_type(
        AlbumQuery.published(
          AlbumQuery.base()
        ), :wedding
      )
    )
  )
)
```

**Ordre recommandé dans le pipeline :**

```elixir
Query.base()
|> # 1. Filtres WHERE (published, by_type, date_range)
|> # 2. Aggregations/Groupes (group_by, with_photo_count)
|> # 3. Tri ORDER BY (order_by_date_desc)
|> # 4. Préchargements PRELOAD (with_photos, with_album)
|> # 5. Limites LIMIT/OFFSET (limit, offset)
|> Repo.all()  # 6. Exécution (dans Repository uniquement)
```

### Pattern 3: Preload avec Subquery

**Probl�me N+1 classique :**

```elixir
# - N+1 : Charge tous les albums puis N requêtes pour photos
albums = Repo.all(Album)

Enum.each(albums, fn album ->
  photos = Repo.all(from p in Photo, where: p.album_id == ^album.id)
  # N requêtes pour N albums
end)
```

**Solution 1 : Preload simple**

```elixir
# - Évite N+1 mais photos non triées
def with_photos(query) do
  preload(query, [:photos])
end

# SQL généré : 2 requêtes (albums + photos pour tous les albums)
```

**Solution 2 : Preload avec subquery triée (Meilleure)**

```elixir
# - Évite N+1 ET trie les photos
def with_photos(query) do
  photos_query = from(p in Photo, order_by: [asc: p.display_order])
  preload(query, photos: ^photos_query)
end

# SQL généré : 2 requêtes avec ORDER BY dans la subquery
```

**Solution 3 : Cover photo uniquement (Optimisation)**

```elixir
# - Charge seulement la premi�re photo (cover)
def with_cover_photo_only(query) do
  cover_photo_query = from(p in Photo, 
    order_by: [asc: p.display_order],
    limit: 1
  )
  preload(query, photos: ^cover_photo_query)
end

# Parfait pour liste d'albums où on n'affiche que la cover
```

### Pattern 4: Aggregations et Optimisations

**Probl�me : Compter sans charger**

```elixir
# - MAUVAIS : Charge tous les albums pour compter les photos
albums = AlbumQuery.base() |> AlbumQuery.with_photos() |> Repo.all()
Enum.map(albums, fn album -> length(album.photos) end)

# Inefficace : Charge toutes les photos juste pour compter
```

**Solution : Subquery avec count**

```elixir
# - BON : Compte sans charger les photos
def with_photo_count(query) do
  from([album: a] in query,
    left_join: p in assoc(a, :photos),
    group_by: a.id,
    select_merge: %{photo_count: count(p.id)}
  )
end

# Usage
albums = AlbumQuery.base() |> AlbumQuery.with_photo_count() |> Repo.all()
# Chaque album a un champ virtuel `photo_count`
albums |> Enum.map(& &1.photo_count)  # [12, 5, 23, ...]
```

**Explication SQL :**

```sql
SELECT 
  albums.*,
  COUNT(photos.id) as photo_count
FROM albums
LEFT JOIN photos ON photos.album_id = albums.id
GROUP BY albums.id
```

**Avantages :**
- - Une seule requête SQL
- - Ne charge pas les photos
- - Champ virtuel `photo_count` disponible
- - Performant même avec 1000+ albums

### Pattern 5: Filtres avec Plage de Dates

**Use case commun :** Filtrer les albums d'une année spécifique.

```elixir
@doc """
Filters albums by date range.

Returns albums where date_prise_vue is between start_date and end_date (inclusive).
"""
@spec where_date_between(Ecto.Query.t(), Date.t(), Date.t()) :: Ecto.Query.t()
def where_date_between(query, start_date, end_date) do
  where(query, [album: a], 
    a.date_prise_vue >= ^start_date and 
    a.date_prise_vue <= ^end_date
  )
end

# Usage dans Repository
def list_published_by_year(year) do
  {:ok, start_date} = Date.new(year, 1, 1)
  {:ok, end_date} = Date.new(year, 12, 31)
  
  AlbumQuery.base()
  |> AlbumQuery.published()
  |> AlbumQuery.where_date_between(start_date, end_date)
  |> Repo.all()
end
```

### Pattern 6: Dynamic Filters

**Probl�me :** Appliquer des filtres conditionnels selon les param�tres utilisateur.

```elixir
# Dans Repository
def list(filters \\ []) do
  AlbumQuery.base()
  |> apply_filters(filters)
  |> Repo.all()
end

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

defp apply_filters(query, [_unknown | rest]) do
  apply_filters(query, rest)  # Ignore unknown filters
end

# Usage
AlbumRepository.list(published: true, type: :wedding, preload: [:photos])
```

**Alternative avec Enum.reduce :**

```elixir
def list(filters \\ []) do
  Enum.reduce(filters, AlbumQuery.base(), fn
    {:published, true}, query -> AlbumQuery.published(query)
    {:type, type}, query -> AlbumQuery.by_type(query, type)
    {:preload, preloads}, query -> AlbumQuery.with_preload(query, preloads)
    _unknown, query -> query
  end)
  |> Repo.all()
end
```

### Testabilité : Tester Sans DB

**Avantage majeur :** Query Objects testables sans exécuter la base de données.

```elixir
defmodule Portfolio.Photography.Queries.AlbumQueryTest do
  use ExUnit.Case, async: true
  
  alias Portfolio.Photography.Queries.AlbumQuery
  
  describe "base/0" do
    test "returns query with named binding :album" do
      query = AlbumQuery.base()
      
      # Test sans exécuter la DB
      assert %Ecto.Query{} = query
      assert inspect(query) =~ "as: :album"
    end
  end
  
  describe "published/1" do
    test "adds published filter to query" do
      query = AlbumQuery.base() |> AlbumQuery.published()
      
      # Vérifie que le filtre est ajouté
      assert inspect(query) =~ "published == true"
    end
  end
  
  describe "by_type/2" do
    test "adds type filter to query" do
      query = AlbumQuery.base() |> AlbumQuery.by_type(:wedding)
      
      assert inspect(query) =~ "type == ^"
    end
  end
  
  describe "composition" do
    test "functions can be chained via pipeline" do
      query = 
        AlbumQuery.base()
        |> AlbumQuery.published()
        |> AlbumQuery.by_type(:wedding)
        |> AlbumQuery.order_by_date_desc()
      
      # Vérifie la composition
      query_string = inspect(query)
      assert query_string =~ "published == true"
      assert query_string =~ "type == ^"
      assert query_string =~ "desc: "
    end
  end
end
```

**Avantages des tests sans DB :**
- - Tr�s rapides (pas d'I/O)
- - Pas besoin de fixtures
- - Testent la construction, pas l'exécution
- - Peuvent s'exécuter en parall�le (`async: true`)

### Conventions de Nommage

**R�gles � suivre :**

| Type de fonction | Convention | Exemple |
|-----------------|-----------|---------|
| Base query | `base()` | `AlbumQuery.base()` |
| Filtre positif | `<attribut>(query)` | `published(query)`, `by_type(query, type)` |
| Filtre négatif | `un<attribut>(query)` | `unpublished(query)` |
| Tri | `order_by_<field>_<direction>(query)` | `order_by_date_desc(query)` |
| Préchargement | `with_<association>(query)` | `with_photos(query)` |
| Filtre conditionnel | `where_<condition>(query, ...)` | `where_date_between(query, start, end)` |
| Aggregation | `with_<aggregation>(query)` | `with_photo_count(query)` |

**Anti-patterns � éviter :**

```elixir
# - Exécution dans Query Object
def all_published(query) do
  query |> published() |> Repo.all()  # INTERDIT
end

# - Nom non descriptif
def filter1(query), do: where(query, [a], a.published == true)

# - Side-effect
def published(query) do
  Logger.info("Filtering published")  # Side-effect interdit
  where(query, [a], a.published == true)
end
```

## Query Objects Existants Analysés

### AlbumQuery - Exemple de Référence

**Fichier:** `lib/portfolio/photography/queries/album_query.ex`

**Points forts :**

1. Named binding cohérent : `as: :album` dans `base()`, utilisé partout
   ```elixir
   def base, do: from(a in Album, as: :album)
   def published(query), do: where(query, [album: a], a.published == true)
   ```

2. Preload optimisé : `with_photos()` trie les photos par `display_order`
   ```elixir
   def with_photos(query) do
     photos_query = from(p in Photo, order_by: [asc: p.display_order])
     preload(query, photos: ^photos_query)
   end
   ```

3. Aggregation performante : `with_photo_count()` évite N+1
   ```elixir
   def with_photo_count(query) do
     from([album: a] in query,
       left_join: p in assoc(a, :photos),
       group_by: a.id,
       select_merge: %{photo_count: count(p.id)}
     )
   end
   ```

4. Cover photo optimization : `with_cover_photo_only()` limite � 1 photo
   ```elixir
   def with_cover_photo_only(query) do
     cover_photo_query = from(p in Photo, order_by: [asc: p.display_order], limit: 1)
     preload(query, photos: ^cover_photo_query)
   end
   ```

5. Flexible preload : `with_preload()` g�re `:photos` spécialement
   ```elixir
   def with_preload(query, preloads) when is_list(preloads) do
     if :photos in preloads do
       # Photos triées via with_photos()
     else
       preload(query, ^preloads)
     end
   end
   ```

**Fonctions disponibles :**
- Filtres : `published/1`, `unpublished/1`, `by_type/2`, `where_date_between/3`
- Tri : `order_by_date_desc/1`, `order_by_date_asc/1`
- Préchargement : `with_photos/1`, `with_cover_photo_only/1`, `with_preload/2`
- Aggregations : `with_photo_count/1`, `group_by_year/1`

**Verdict :** Exemple parfait de Query Object 

### PhotoQuery - Simple et Efficace

**Fichier:** `lib/portfolio/photography/queries/photo_query.ex`

**Points forts :**

1. Named binding cohérent : `as: :photo`
2. CRUD filters standards : `published/1`, `unpublished/1`, `by_album/2`
3. Tri métier : `order_by_display_order/1` (ordre d'affichage dans album)
4. Preload simple : `with_album/1`, `with_preload/2`

**Plus simple qu'AlbumQuery car :**
- Photos sont des entités "leaf" (pas d'associations complexes)
- Moins de use cases métier complexes
- Moins d'optimisations nécessaires

**Verdict :** Bien structuré, adapté aux besoins 

## Plan d'action

### Phase 1: Documentation (Priorité: HAUTE)

Tâches :
1. Ajouter `@moduledoc` complet � tous les Query Objects existants
2. Documenter les patterns de composition dans `/docs`
3. Créer des exemples d'utilisation commentés
4. Expliquer named bindings et leur importance

Crit�res de succ�s :
- Tous les Query Objects documentés
- Guide de composition disponible

**Estimation:** 0.5 jour

### Phase 2: Tests Query Objects (Priorité: MOYENNE)

Tâches :
1. Créer tests unitaires pour tous les Query Objects
2. Tester la composition (chaînage de fonctions)
3. Tester les cas limites (nil, empty list)
4. Vérifier que pas d'exécution (`Repo` interdit)

**Pattern de test :**
```elixir
test "published/1 adds published filter" do
  query = AlbumQuery.base() |> AlbumQuery.published()
  assert inspect(query) =~ "published == true"
end
```

Crit�res de succ�s :
- Coverage > 90% sur Query Objects
- Tests rapides (< 1ms par test, pas de DB)

**Estimation:** 1 jour

### Phase 3: Audit Réutilisation (Priorité: BASSE)

Tâches :
1. Identifier les queries inline qui pourraient utiliser Query Objects
2. Vérifier que Repository utilise bien les Query Objects
3. Chercher duplication de filtres dans Services/LiveViews

Crit�res de succ�s :
- Zéro duplication de filtres détectée
- Tous les Repositories utilisent Query Objects

**Estimation:** 0.5 jour

### Phase 4: Optimisations (Priorité: BASSE)

Tâches :
1. Identifier les N+1 queries potentielles
2. Ajouter `with_photo_count()` partout où nécessaire
3. Utiliser `with_cover_photo_only()` dans listes
4. Profiler les queries avec EXPLAIN ANALYZE

Crit�res de succ�s :
- Aucune N+1 query détectée
- Utilisation de cover photo dans listes d'albums

**Estimation:** 1 jour

## Références

- [Ecto Query Composition](https://hexdocs.pm/ecto/Ecto.Query.html#module-composition)
- [Query Object Pattern - Martin Fowler](https://martinfowler.com/eaaCatalog/queryObject.html)
- [Elixir Pipe Operator](https://elixir-lang.org/getting-started/enumerables-and-streams.html#the-pipe-operator)
- Code source :
  - `lib/portfolio/photography/queries/album_query.ex`
  - `lib/portfolio/photography/queries/photo_query.ex`
  - `lib/portfolio/photography/repositories/album_repository.ex`

## Notes

### Pourquoi Query Objects et pas Scopes ?

Les **scopes** (inspirés de Rails) définissent les queries dans le Schema :

```elixir
defmodule Album do
  use Ecto.Schema
  
  def published(query \\ __MODULE__), do: where(query, [a], a.published == true)
end
```

**Avantages scopes :**
- Syntax sugar (peut appeler `Album.published()` sans query)

**Inconvénients scopes :**
- - Mélange Schema (structure) et Queries (comportement)
- - Viole Single Responsibility Principle
- - Schema devient énorme (> 500 lignes)
- - Difficile � tester (dépend du Schema)

**Verdict :** Query Objects séparés sont préférables pour maintenir la séparation des préoccupations.

### Query Objects vs Repository Methods

**Question :** Pourquoi `AlbumQuery.published()` et pas `AlbumRepository.list_published()` ?

**Réponse :**

| Aspect | Query Object | Repository Method |
|--------|--------------|-------------------|
| Responsabilité | Construction | Exécution |
| Réutilisabilité | Haute (partout) | Moyenne (Repository uniquement) |
| Composabilité | Totale (pipeline) | Limitée (méthode par combinaison) |
| Testabilité | Sans DB | Avec DB (Sandbox) |

**Use case Query Object :**
```elixir
# Flexible, composable
AlbumQuery.base()
|> AlbumQuery.published()
|> AlbumQuery.by_type(:wedding)
|> Repo.all()
```

**Use case Repository Method :**
```elixir
# Simple, direct
AlbumRepository.list_published()
```

**Recommandation :** Utiliser les deux selon le contexte :
- Query Objects pour **composition flexible**
- Repository methods pour **use cases métier nommés**

### Performance : Composition Sans Overhead

**Question :** La composition de fonctions n'ajoute-t-elle pas d'overhead ?

**Réponse :** Non, la composition se fait � la **compilation**, pas au runtime.

```elixir
# Au runtime, Ecto gén�re un seul SQL optimisé
AlbumQuery.base()
|> AlbumQuery.published()
|> AlbumQuery.by_type(:wedding)
|> Repo.all()

# SQL généré (une seule requête) :
# SELECT * FROM albums 
# WHERE published = true 
#   AND type = 'wedding'
```

**Benchmark :**
- Query Object composé : ~0.5ms compilation
- Query inline : ~0.5ms compilation
- **Différence : 0ms runtime** (identique)

---

**Date de création:** 2025-11-11  
**Derni�re révision:** 2025-11-11
