# ADR-015: URLs Basées sur Slugs pour SEO

Statut: Accepté
Date: 2025-05

## Contexte

Le portfolio photographique expose des albums et photos publiquement. La structure des URLs impacte directement le référencement naturel (SEO) et l'expérience utilisateur.

### Besoins fonctionnels

1. SEO : URLs descriptives indexables par moteurs de recherche
2. Lisibilité : URLs compréhensibles par humains (partage réseaux sociaux)
3. Stabilité : URLs permanentes (liens externes, favoris navigateur)
4. Unicité : Garantie d'absence de collision entre albums
5. Maintenance : Possibilité de corriger slug sans casser liens existants

### Contraintes techniques

1. Phoenix LiveView : Routes dynamiques avec param�tres
2. PostgreSQL : Contrainte unicité slug
3. Cache : Lookup rapide par slug (route publique fréquente)
4. Multilingue : Support accents français (Château, Événement)

### Problématique

Comment structurer les URLs pour optimiser le SEO, garantir la stabilité des liens dans le temps, et gérer les collisions de slugs, tout en permettant des corrections manuelles sans impact SEO négatif ?

---

## Options Considérées

### Option 1 : URLs basées sur IDs (UUIDs)

Utilisation d'identifiants UUID dans les URLs.

**Description :**
```
/albums/550e8400-e29b-41d4-a716-446655440000
/albums/550e8400-e29b-41d4-a716-446655440000/photos/7c9e6679-7425-40de-944b-e07fc1f90ae7
```

**Avantages :**
- Unicité garantie (UUID v4 = collision quasi impossible)
- Stabilité absolue (UUID jamais modifié)
- Performance lookup : Index primaire DB (O(log n))
- Simplicité : Pas de génération slug

**Inconvénients :**
- SEO catastrophique : Aucun mot-clé, URL non descriptive
- Lisibilité nulle : Impossible de deviner contenu
- UX partage : URL rebutante sur réseaux sociaux
- Mémorisation impossible

**Effort estimé :** Aucun (implémentation par défaut Phoenix)

**Risques :**
- Perte SEO majeure [Probabilité: Certaine, Impact: Élevé]

**Rejeté** : Incompatible avec besoin SEO portfolio photographique.

### Option 2 : URLs basées sur IDs numériques

Utilisation d'auto-increment integer.

**Description :**
```
/albums/42
/albums/42/photos/1337
```

**Avantages :**
- Unicité garantie (séquence PostgreSQL)
- URLs courtes (3-5 caract�res)
- Performance lookup excellente (integer vs UUID)
- Stabilité absolue

**Inconvénients :**
- SEO médiocre : Aucun mot-clé descriptif
- Lisibilité faible : Numéro non signifiant
- Sécurité : Énumération facile (album/1, album/2, album/3...)
- Exposition volume : "/albums/3" rév�le seulement 3 albums (peu professionnel)

**Effort estimé :** Faible (changement type clé primaire)

**Risques :**
- SEO insuffisant [Probabilité: Certaine, Impact: Élevé]
- Énumération [Probabilité: Certaine, Impact: Faible]

**Rejeté** : SEO insuffisant pour portfolio professionnel.

### Option 3 : URLs basées sur slugs purs �

Utilisation de slugs générés depuis titres (ex: "voyage-japon-2024").

**Description :**
```
/albums/voyage-japon-2024
/albums/mariage-claire-damien-juin-2024
/albums/voyage-japon-2024/photos/temple-kyoto
```

**Avantages :**
- SEO optimal : Mots-clés dans URL (Google indexe "voyage japon 2024")
- Lisibilité maximale : URL auto-descriptive
- UX partage : URL attrayante réseaux sociaux (Twitter, Facebook preview)
- Mémorisation possible : "thibaultsan.com/albums/voyage-japon-2024"
- Professionnalisme : Standard industrie (Medium, WordPress, Ghost)

**Inconvénients :**
- Complexité génération : Normalisation titre � slug (accents, espaces, caract�res spéciaux)
- Gestion collisions : Titres identiques nécessitent suffix
- Stabilité : Modification titre = risque changement slug = liens cassés
- Performance : Lookup string vs integer (mitigé par index)

**Effort estimé :** Moyen (Value Object Slug + collision logic)

**Risques :**
- Collision slugs [Probabilité: Faible, Impact: Moyen]
- Modification accidentelle slug [Probabilité: Moyenne, Impact: Élevé]

### Option 4 : URLs hybrides ID + Slug

Combinaison ID (unicité) + Slug (SEO).

**Description :**
```
/albums/42-voyage-japon-2024
/albums/mariage-claire-damien-juin-2024-550e8400
```

**Avantages :**
- SEO : Mots-clés présents dans URL
- Unicité garantie : ID résout collisions
- Stabilité : ID immuable, slug peut changer sans casser lien
- Tolérance : `/albums/42-ancien-slug` redirige vers `/albums/42-nouveau-slug`

**Inconvénients :**
- URLs plus longues (ID + slug)
- Complexité routing : Parser ID + slug
- Esthétique : "42-" ou "-550e8400" pollue URL
- Confusion : Quelle partie est significative ?

**Effort estimé :** Moyen (parsing route custom)

**Risques :**
- Complexité routing [Probabilité: Moyenne, Impact: Faible]

**Rejeté** : Compromis inutile, slug pur + redirections 301 suffisant.

---

## Décision

L'option choisie est : **Option 3 - URLs basées sur slugs purs**

Avec architecture complémentaire :
- Value Object `Slug` pour validation et normalisation
- Résolution collision automatique (suffix date)
- Slug immutable sauf modification manuelle volontaire
- Redirections 301 canoniques pour préserver SEO

### Crit�res de décision

**Alignement avec l'architecture :**
- DDD : `Slug` = Value Object auto-validant
- Clean Architecture : Génération slug dans Domain Layer
- Ports & Adapters : SlugGenerator behaviour (testable, mockable)

**Impact sur la dette technique :**
- Complexité maîtrisée : Value Object encapsule logic
- Tests exhaustifs : Collision, normalisation, accents
- Migration données : Génération slugs pour albums existants

**Maintenabilité :**
- Code explicite : `Slug.new("Paris 2024")` � `{:ok, %Slug{value: "paris-2024"}}`
- Validation centralisée : Invariants garantis (minuscules, max 100 chars)
- Évolutivité : Ajout translittération langues (japonais, chinois) facile

**Performance :**
- Lookup slug : Index unique DB (O(log n))
- Cache : `{:album_by_slug, "voyage-japon"}` TTL 1h
- Génération slug : ~1ms (négligeable vs upload photo)

**Sécurité :**
- Pas d'énumération : Slugs non prédictibles
- Validation stricte : Injection slug impossible (alphanumeric + tirets uniquement)
- Path traversal : Validation empêche `../../../etc/passwd`

**Coût/Effort :**
- Implémentation : 1 semaine (Value Object + collision + redirections)
- Maintenance : Faible (logic encapsulée)
- SEO gain : Critique (différence majeure ranking Google)

**Réversibilité :**
- Migration UUID : Possible (garder slug en colonne secondaire)
- Aucune perte données : Slugs conservés

### Décision finale

Adoption slugs URL-friendly avec les justifications suivantes :

1. SEO critique : Portfolio photographique dépend du trafic organique Google (recherche "photographe mariage Paris", "voyage Japon photos")

2. Expérience utilisateur : URLs `/albums/voyage-japon-2024` vs `/albums/550e8400...` = partage réseaux sociaux amélioré

3. Professionnalisme : Standard industrie (tous portfolios pros utilisent slugs)

4. Stabilité garantie : Redirections 301 canoniques préservent SEO même si slug modifié

5. Performance acceptable : Index unique + cache = lookup rapide (< 10ms)

---

## Architecture Technique

### Value Object Slug

**Implémentation actuelle :**

```elixir
# lib/portfolio/photography/value_objects/slug.ex
defmodule Portfolio.Photography.ValueObjects.Slug do
  @moduledoc """
  Value Object pour slugs URL-safe.
  
  Invariants :
  - Minuscules alphanumériques + tirets uniquement
  - Maximum 100 caract�res
  - Pas de tirets au début/fin
  - Non vide
  """
  
  @enforce_keys [:value]
  defstruct [:value]
  
  @type t :: %__MODULE__{value: String.t()}
  
  @max_length 100
  
  @spec new(String.t()) :: {:ok, t()} | {:error, :invalid_slug | :too_long}
  def new(str) when is_binary(str) do
    slug_value =
      str
      |> String.downcase()
      |> transliterate()                        # é � e, ç � c
      |> String.replace(~r/[^a-z0-9\s-]/, "")  # Supprimer spéciaux
      |> String.replace(~r/\s+/, "-")           # Espaces � tirets
      |> String.replace(~r/-+/, "-")            # Tirets multiples � 1
      |> String.trim("-")                       # Supprimer tirets début/fin
    
    cond do
      slug_value == "" -> {:error, :invalid_slug}
      String.length(slug_value) > @max_length -> {:error, :too_long}
      true -> {:ok, %__MODULE__{value: slug_value}}
    end
  end
  
  # Translittération accents français
  defp transliterate_char(char) when char in ~w(� � â ã ä å), do: "a"
  defp transliterate_char("ç"), do: "c"
  defp transliterate_char(char) when char in ~w(� é ê �), do: "e"
  # ... (voir code complet)
end
```

**Exemples normalisation :**
```elixir
Slug.new("Paris 2024")                    # {:ok, %Slug{value: "paris-2024"}}
Slug.new("Château d'Événements!")         # {:ok, %Slug{value: "chateau-d-evenements"}}
Slug.new("Hello   World!!!")              # {:ok, %Slug{value: "hello-world"}}
Slug.new("Mariage Claire & Damien �")    # {:ok, %Slug{value: "mariage-claire-damien"}}
Slug.new("")                              # {:error, :invalid_slug}
Slug.new(String.duplicate("a", 150))      # {:error, :too_long}
```

### Génération Slug avec Résolution Collision

**Stratégie : Suffix date intelligent**

```elixir
# lib/portfolio/photography/services/slug_generator.ex
defmodule Portfolio.Photography.Services.SlugGenerator do
  @moduledoc """
  Service de génération de slugs uniques avec résolution automatique de collisions.
  
  Stratégie collision :
  1. Slug base (depuis titre)
  2. Si collision : Slug + année
  3. Si collision : Slug + année-mois
  4. Si collision : Slug + année-mois-jour
  5. Si collision : Erreur (impossible même jour/titre)
  """
  
  alias Portfolio.Photography.ValueObjects.Slug
  alias Portfolio.Photography.Repositories.AlbumRepository
  
  @spec generate_unique_slug(String.t(), Date.t()) :: {:ok, String.t()} | {:error, term()}
  def generate_unique_slug(title, date_prise_vue) do
    base_slug = 
      case Slug.new(title) do
        {:ok, slug} -> Slug.to_string(slug)
        {:error, reason} -> {:error, reason}
      end
    
    attempt_unique_slug(base_slug, date_prise_vue, 0)
  end
  
  defp attempt_unique_slug(base_slug, date, attempt) when attempt <= 3 do
    candidate = build_candidate_slug(base_slug, date, attempt)
    
    case AlbumRepository.get_by_slug(candidate) do
      nil -> 
        {:ok, candidate}
      
      _existing_album -> 
        attempt_unique_slug(base_slug, date, attempt + 1)
    end
  end
  
  defp attempt_unique_slug(_base_slug, _date, _attempt) do
    {:error, :unable_to_generate_unique_slug}
  end
  
  defp build_candidate_slug(base, date, 0), do: base
  
  defp build_candidate_slug(base, date, 1) do
    "#{base}-#{date.year}"
  end
  
  defp build_candidate_slug(base, date, 2) do
    "#{base}-#{date.year}-#{pad(date.month)}"
  end
  
  defp build_candidate_slug(base, date, 3) do
    "#{base}-#{date.year}-#{pad(date.month)}-#{pad(date.day)}"
  end
  
  defp pad(num) when num < 10, do: "0#{num}"
  defp pad(num), do: "#{num}"
end
```

**Exemples collision :**
```elixir
# Album 1
titre: "Voyage Japon"
date: 2024-05-15
slug: "voyage-japon"  # OK

# Album 2 (même titre, année différente)
titre: "Voyage Japon"
date: 2025-06-20
slug: "voyage-japon-2025"  # Collision résolue automatiquement

# Album 3 (même titre, même année)
titre: "Voyage Japon"
date: 2024-08-10
slug: "voyage-japon-2024-08"  # Collision avec album 1

# Album 4 (cas extrême : même titre, même jour)
titre: "Voyage Japon"
date: 2024-05-15
slug: "voyage-japon-2024-05-15"  # Tr�s improbable mais géré
```

### Slug Immutable par Défaut

**Comportement :**
- Création album : Slug généré automatiquement depuis titre
- Modification titre : Slug **non regénéré** (stabilité URLs)
- Modification slug manuelle : Warning UI + confirmation utilisateur

**Changeset Album :**

```elixir
# lib/portfolio/photography/album.ex
def changeset(album, attrs) do
  album
  |> cast(attrs, [:title, :slug, :type, :date_prise_vue, ...])
  |> validate_required([:title, :type, :date_prise_vue])
  |> generate_slug_if_new()  # Seulement si nouveau
  |> unique_constraint(:slug)
end

defp generate_slug_if_new(changeset) do
  case get_change(changeset, :slug) do
    # Slug déj� fourni (modification manuelle) : Conserver
    slug when is_binary(slug) and slug != "" ->
      changeset
    
    # Nouveau album sans slug : Générer
    nil ->
      if get_field(changeset, :id) == nil do
        title = get_change(changeset, :title) || get_field(changeset, :title)
        date = get_change(changeset, :date_prise_vue) || get_field(changeset, :date_prise_vue)
        
        case SlugGenerator.generate_unique_slug(title, date) do
          {:ok, slug} -> put_change(changeset, :slug, slug)
          {:error, _} -> add_error(changeset, :slug, "impossible to generate unique slug")
        end
      else
        # Album existant, modification titre : Ne pas regénérer slug
        changeset
      end
  end
end
```

**UI Admin Warning :**

```heex
<!-- lib/portfolio_web/live/admin/album_live/form_component.html.heex -->
<.input 
  field={@form[:title]} 
  label="Titre" 
  required 
/>

<.input 
  field={@form[:slug]} 
  label="Slug (URL)" 
  help="Modifier le slug impactera le SEO. Les anciennes URLs seront redirigées automatiquement."
/>

<.alert color="warning" :if={slug_manually_changed?(@form)}>
  <div class="flex items-start gap-3">
    <Heroicons.exclamation_triangle class="w-5 h-5 mt-0.5 flex-shrink-0" />
    <div>
      <p class="font-semibold">Attention : Modification du slug détectée</p>
      <p class="text-sm mt-1">
        Modifier le slug cassera les liens existants vers cet album et impactera 
        négativement le référencement Google.
      </p>
      <p class="text-sm mt-2">
        Une redirection automatique (301) sera créée depuis l'ancien slug 
        "<code class="font-mono bg-gray-100 px-1"><%=@original_slug%></code>" 
        pour préserver le SEO.
      </p>
    </div>
  </div>
</.alert>
```

### Redirections 301 Canoniques

**Probl�me : Chaîne de redirects**

Si slug modifié 2 fois :
```
"voyage-japon" � "voyage-japon-2024" � "voyage-japon-2024-complet"
```

Sans syst�me canonique, requête ancienne = 404.

**Solution : Slug canonique**

```elixir
# priv/repo/migrations/XXX_create_slug_redirects.exs
defmodule Portfolio.Repo.Migrations.CreateSlugRedirects do
  use Ecto.Migration

  def change do
    create table(:slug_redirects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :old_slug, :string, null: false
      add :canonical_slug, :string, null: false  # Slug actuel (pas "new")
      add :resource_type, :string, null: false   # "album" ou "photo"
      add :resource_id, :binary_id, null: false
      
      timestamps(type: :utc_datetime)
    end
    
    create index(:slug_redirects, [:old_slug, :resource_type])
    create index(:slug_redirects, [:resource_id])
  end
end
```

**Schema :**

```elixir
# lib/portfolio/photography/slug_redirect.ex
defmodule Portfolio.Photography.SlugRedirect do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  
  schema "slug_redirects" do
    field :old_slug, :string
    field :canonical_slug, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    
    timestamps(type: :utc_datetime)
  end
  
  def changeset(redirect, attrs) do
    redirect
    |> cast(attrs, [:old_slug, :canonical_slug, :resource_type, :resource_id])
    |> validate_required([:old_slug, :canonical_slug, :resource_type, :resource_id])
    |> validate_inclusion(:resource_type, ["album", "photo"])
  end
end
```

**Logic Update Slug :**

```elixir
# lib/portfolio/photography.ex
def update_album_slug(album, new_slug) do
  Repo.transaction(fn ->
    # 1. Invalider toutes redirections pointant vers slug actuel
    #    (pour gérer chaîne de redirects)
    from(r in SlugRedirect,
      where: r.canonical_slug == ^album.slug and r.resource_type == "album"
    )
    |> Repo.update_all(set: [canonical_slug: new_slug])
    
    # 2. Créer nouvelle redirection (ancien � nouveau)
    %SlugRedirect{}
    |> SlugRedirect.changeset(%{
      old_slug: album.slug,
      canonical_slug: new_slug,
      resource_type: "album",
      resource_id: album.id
    })
    |> Repo.insert!()
    
    # 3. Mettre � jour slug album
    album
    |> Ecto.Changeset.change(slug: new_slug)
    |> Repo.update!()
    
    # 4. Invalider cache
    Cachex.del(:portfolio_cache, {:album_by_slug, album.slug})
    Cachex.del(:portfolio_cache, {:album_by_slug, new_slug})
  end)
end
```

**Exemple chaîne redirects :**

```
Initial : slug = "voyage-japon"
Update 1 : slug = "voyage-japon-2024"
Update 2 : slug = "voyage-japon-2024-complet"

Table slug_redirects apr�s Update 2 :
| old_slug            | canonical_slug              |
|---------------------|----------------------------|
| voyage-japon        | voyage-japon-2024-complet  | � Mis � jour
| voyage-japon-2024   | voyage-japon-2024-complet  | � Créé
```

Requête "voyage-japon" � 301 vers "voyage-japon-2024-complet" 

**Plug Redirection :**

```elixir
# lib/portfolio_web/plugs/slug_redirect.ex
defmodule PortfolioWeb.Plugs.SlugRedirect do
  @moduledoc """
  Plug pour gérer les redirections 301 des anciens slugs.
  
  Vérifie si le slug demandé est un ancien slug, et redirige vers
  le slug canonique avec status 301 (Moved Permanently).
  """
  
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]
  
  alias Portfolio.Photography
  
  def init(opts), do: opts
  
  def call(conn, resource_type: type) do
    slug = conn.params["slug"]
    
    case Photography.find_canonical_slug(slug, type) do
      nil -> 
        # Pas de redirection
        conn
      
      canonical_slug when canonical_slug != slug ->
        # Redirection 301 vers slug canonique
        new_path = rebuild_path(conn.request_path, slug, canonical_slug)
        
        conn
        |> put_status(301)
        |> redirect(to: new_path)
        |> halt()
      
      _same_slug ->
        # Slug déj� canonique
        conn
    end
  end
  
  defp rebuild_path(path, old_slug, new_slug) do
    String.replace(path, "/#{old_slug}", "/#{new_slug}")
  end
end
```

**Utilisation Router :**

```elixir
# lib/portfolio_web/router.ex
scope "/", PortfolioWeb, host: "photo." do
  pipe_through [:photography, {PortfolioWeb.Plugs.SlugRedirect, resource_type: "album"}]
  
  live "/albums/:slug", PhotographyLive.Gallery, :show
end
```

### Slugs Photos

**Unicité par album :**

```elixir
# lib/portfolio/photography/photo.ex
schema "photos" do
  belongs_to :album, Album
  field :title, :string
  field :slug, :string
  # ...
end

def changeset(photo, attrs) do
  photo
  |> cast(attrs, [:title, :slug, ...])
  |> generate_slug_from_title()
  |> unique_constraint([:album_id, :slug], 
       name: :photos_album_id_slug_index)
end
```

**Migration index :**

```elixir
create unique_index(:photos, [:album_id, :slug])
```

**Collision photos : Hash suffix**

Si même titre dans album :

```elixir
defp generate_photo_slug(title, album_id, photo_hash \\ nil) do
  base_slug = Slug.new!(title) |> Slug.to_string()
  
  case check_photo_slug_collision(base_slug, album_id) do
    false -> base_slug
    true -> "#{base_slug}-#{String.slice(photo_hash, 0, 8)}"
  end
end
```

**Exemple :**
```
Album "Voyage Japon 2024" contient :
- "coucher-soleil" (Photo 1)
- "coucher-soleil-a3f2b8c4" (Photo 2, même titre uploadée 2�)
- "temple-kyoto"
```

**URLs photos :**
```
/albums/voyage-japon-2024/photos/coucher-soleil
/albums/voyage-japon-2024/photos/temple-kyoto
```

### Cache par Slug

**Implémentation :**

```elixir
# lib/portfolio/photography.ex
def get_album_by_slug(slug, opts \\ []) do
  skip_cache = Keyword.get(opts, :skip_cache, Application.get_env(:portfolio, :env) == :test)
  
  if skip_cache do
    AlbumRepository.get_by_slug(slug)
  else
    cache_key = {:album_by_slug, slug}
    
    case Cachex.fetch(:portfolio_cache, cache_key, fn ->
      case AlbumRepository.get_by_slug(slug) do
        nil -> {:ignore, nil}
        album -> {:commit, album, ttl: :timer.hours(1)}
      end
    end) do
      {:ok, album} -> album
      {:commit, album} -> album
      _ -> nil
    end
  end
end
```

**Invalidation :**

```elixir
def update_album(album, attrs) do
  # ...
  
  # Invalider cache slug
  Cachex.del(:portfolio_cache, {:album_by_slug, album.slug})
  
  # Si slug changé, invalider ancien et nouveau
  if Map.has_key?(attrs, :slug) do
    Cachex.del(:portfolio_cache, {:album_by_slug, attrs.slug})
  end
end
```

### Routes Publiques

**Router :**

```elixir
# lib/portfolio_web/router.ex
scope "/", PortfolioWeb, host: "photo." do
  pipe_through [:photography, {PortfolioWeb.Plugs.SlugRedirect, resource_type: "album"}]
  
  live_session :current_user,
    on_mount: [{PortfolioWeb.UserAuth, :mount_current_user}] do
    
    live "/", PhotographyLive.Index, :index
    live "/timeline", PhotographyLive.Timeline, :index
    
    # Routes basées sur slugs (renommé depuis :chapter)
    live "/albums/:slug", PhotographyLive.Gallery, :show
    live "/albums/:slug/photos/:photo_slug", PhotographyLive.PhotoShow, :show
  end
end
```

**LiveView :**

```elixir
# lib/portfolio_web/live/photography_live/gallery.ex
defmodule PortfolioWeb.PhotographyLive.Gallery do
  use PortfolioWeb, :live_view
  
  alias Portfolio.Photography
  
  def mount(%{"slug" => slug}, _session, socket) do
    case Photography.get_album_by_slug(slug, preload: [:photos]) do
      nil ->
        {:ok, 
         socket
         |> put_flash(:error, "Album non trouvé")
         |> redirect(to: ~p"/")
        }
      
      album ->
        {:ok,
         socket
         |> assign(:album, album)
         |> assign(:page_title, album.title)
        }
    end
  end
end
```

---

## Conséquences

### Positives

1. **SEO optimisé**
   - Mots-clés dans URL : Google indexe "voyage japon 2024"
   - Taux de clic amélioré : URL descriptive en SERP (Search Engine Results Page)
   - Partage réseaux sociaux : Preview URL attrayant (Twitter, Facebook)
   - Rich snippets : URLs structurées facilitent Schema.org

2. **Expérience utilisateur**
   - Lisibilité : `/albums/mariage-claire-damien` vs `/albums/550e8400...`
   - Mémorisation : URL simple � retenir et partager oralement
   - Confiance : URL professionnelle rassure utilisateur
   - Navigation : Breadcrumb clair depuis URL

3. **Stabilité URLs**
   - Redirections 301 canoniques : Anciens liens préservés
   - SEO non impacté : Google suit redirections 301
   - Favoris navigateur : Fonctionnent toujours apr�s changement slug
   - Liens externes : Sites tiers pas impactés

4. **Maintenance facilitée**
   - Correction slug possible : Typo corrigible sans casser SEO
   - Warning UI : Utilisateur conscient impact changement
   - Audit : Table `slug_redirects` = historique modifications

5. **Performance acceptable**
   - Index unique : Lookup O(log n) comme UUID
   - Cache : Hit rate > 90% (albums changent peu)
   - Génération slug : ~1ms (négligeable)

### Négatives

1. **Complexité génération (mitigée)**
   - Value Object Slug : Normalisation, translittération
   - Résolution collision : Logique suffix date
- Mitigation : Encapsulation dans Value Object + Service

2. **Gestion redirections (effort 1h)**
   - Table `slug_redirects` : Migration + schema
   - Plug redirection : Query supplémentaire si ancien slug
- Mitigation : Query rare (uniquement si ancien lien utilisé)

3. **Risque modification accidentelle (résolu)**
   - Utilisateur modifie slug sans comprendre impact
- Mitigation : Warning UI + confirmation + redirections 301

4. **Performance lookup string vs integer (négligeable)**
   - String comparison lég�rement plus lent qu'integer
- Mitigation : Index unique + cache = impact < 5ms

### Risques

1. **Collision slug malgré suffix date**
   - Probabilité : Tr�s faible (nécessite titre identique + même date + même mois + même jour)
   - Impact : Moyen (erreur création album)
- Plan contingence : Erreur utilisateur "Impossible de générer slug unique, modifier titre"

2. **Migration données existantes**
   - Probabilité : Certaine (si albums sans slugs)
   - Impact : Moyen (script migration nécessaire)
- Plan contingence : Script génération batch slugs (voir Plan d'action)

3. **Table slug_redirects croissance**
   - Probabilité : Faible (modifications slugs rares)
   - Impact : Faible (100 redirects = ~10KB)
- Plan contingence : Pruning redirections > 2 ans (script maintenance)

---

## Plan d'action

### Phase 1 : Implémentation Value Object Slug (Complétée 2025-05)

**Statut :** Complété 

**Réalisé :**
- Value Object `Slug` avec validation
- Translittération accents français
- Tests exhaustifs (accents, espaces, spéciaux)
- Intégration changeset `Album`

### Phase 2 : Résolution Collision Automatique (Q1 2026)

**Objectif :** Suffix date intelligent

**Actions :**

1. **Service SlugGenerator** (1 jour)

```elixir
# lib/portfolio/photography/services/slug_generator.ex
# Code complet fourni dans section Architecture
```

2. **Tests collision** (1 jour)

```elixir
# test/portfolio/photography/services/slug_generator_test.exs
defmodule Portfolio.Photography.Services.SlugGeneratorTest do
  use Portfolio.DataCase
  
  alias Portfolio.Photography.Services.SlugGenerator
  
  test "gén�re slug unique avec suffix année si collision" do
    insert(:album, slug: "voyage-japon", date_prise_vue: ~D[2024-05-15])
    
    {:ok, slug} = SlugGenerator.generate_unique_slug(
      "Voyage Japon", 
      ~D[2025-06-20]
    )
    
    assert slug == "voyage-japon-2025"
  end
  
  test "gén�re slug avec année-mois si collision année" do
    insert(:album, slug: "voyage-japon", date_prise_vue: ~D[2024-05-15])
    insert(:album, slug: "voyage-japon-2024", date_prise_vue: ~D[2024-03-10])
    
    {:ok, slug} = SlugGenerator.generate_unique_slug(
      "Voyage Japon",
      ~D[2024-08-20]
    )
    
    assert slug == "voyage-japon-2024-08"
  end
end
```

3. **Intégration changeset Album** (1 jour)

Modifier `generate_slug_if_new/1` pour utiliser `SlugGenerator.generate_unique_slug/2`.

**Crit�res succ�s :**
- Collision auto-résolue avec suffix date
- Tests 100% passants
- Aucune régression création album

### Phase 3 : Redirections 301 Canoniques (Q1 2026)

**Objectif :** Préserver SEO lors changement slug

**Actions :**

1. **Migration table `slug_redirects`** (30 min)

```bash
mix ecto.gen.migration create_slug_redirects
# Code migration fourni dans section Architecture
mix ecto.migrate
```

2. **Schema `SlugRedirect`** (30 min)

Code fourni dans section Architecture.

3. **Logic update slug canonique** (2 heures)

```elixir
# Intégration dans Photography.update_album/2
# Code fourni dans section Architecture
```

4. **Plug redirection** (2 heures)

```elixir
# lib/portfolio_web/plugs/slug_redirect.ex
# Code fourni dans section Architecture
```

5. **Tests redirections** (2 heures)

```elixir
# test/portfolio_web/plugs/slug_redirect_test.exs
test "redirige ancien slug vers canonique avec 301" do
  album = insert(:album, slug: "voyage-japon-2024")
  
  # Simuler changement slug
  Photography.update_album_slug(album, "voyage-japon-2024-complet")
  
  # Requête ancien slug
  conn = get(build_conn(), "/albums/voyage-japon-2024")
  
  assert redirected_to(conn, 301) == "/albums/voyage-japon-2024-complet"
end

test "g�re chaîne redirects (3 niveaux)" do
  album = insert(:album, slug: "a")
  Photography.update_album_slug(album, "b")
  Photography.update_album_slug(album, "c")
  
  # Requête slug initial
  conn = get(build_conn(), "/albums/a")
  
  # Doit rediriger directement vers slug final (pas b puis c)
  assert redirected_to(conn, 301) == "/albums/c"
end
```

**Crit�res succ�s :**
- Redirections 301 fonctionnelles
- Chaîne redirects gérée (ancien � canonique direct)
- Tests 100% passants
- Aucun impact performance (query rare)

### Phase 4 : UI Warning Modification Slug (Q1 2026)

**Objectif :** Prévenir utilisateur impact changement slug

**Actions :**

1. **Composant Alert** (1 heure)

Code fourni dans section Architecture (alert warning).

2. **Detection changement slug** (1 heure)

```elixir
# lib/portfolio_web/live/admin/album_live/form_component.ex
defp slug_manually_changed?(form) do
  original = form.data.slug
  current = Ecto.Changeset.get_change(form.source, :slug)
  
  current != nil && current != original
end

defp assign_original_slug(socket) do
  assign(socket, :original_slug, socket.assigns.album.slug)
end
```

3. **Tests UI** (1 heure)

```elixir
# test/portfolio_web/live/admin/album_live/edit_test.exs
test "affiche warning si slug modifié manuellement" do
  album = insert(:album, slug: "original-slug")
  
  {:ok, view, _html} = live(conn, ~p"/admin/albums/#{album.id}/edit")
  
  # Modifier slug
  view
  |> form("#album-form", album: %{slug: "nouveau-slug"})
  |> render_change()
  
  # Vérifier warning affiché
  assert has_element?(view, "[role=alert]", "Attention : Modification du slug détectée")
end
```

**Crit�res succ�s :**
- Warning visible si slug modifié
- Message clair et informatif
- Tests UI passants

### Phase 5 : Cache par Slug (Q1 2026)

**Objectif :** Optimiser performance routes publiques

**Actions :**

1. **Implémentation cache** (1 heure)

Code fourni dans section Architecture.

2. **Invalidation cache** (1 heure)

Intégrer dans `update_album/2`, `update_album_slug/2`.

3. **Tests cache** (2 heures)

```elixir
# test/portfolio/photography_test.exs
test "cache album par slug" do
  album = insert(:album, slug: "test-slug")
  
  # Premier appel : Miss cache
  assert Photography.get_album_by_slug("test-slug") == album
  
  # Deuxi�me appel : Hit cache (pas de query DB)
  assert_query_count(0, fn ->
    Photography.get_album_by_slug("test-slug")
  end)
end

test "invalide cache lors update album" do
  album = insert(:album, slug: "test-slug")
  
  # Warm cache
  Photography.get_album_by_slug("test-slug")
  
  # Update album
  Photography.update_album(album, %{title: "Nouveau titre"})
  
  # Cache invalidé, requête DB nécessaire
  assert_query_count(1, fn ->
    Photography.get_album_by_slug("test-slug")
  end)
end
```

**Crit�res succ�s :**
- Hit rate > 90% (monitoring)
- Invalidation correcte
- Tests passants

### Phase 6 : Migration Données Existantes (Si nécessaire)

**Objectif :** Générer slugs pour albums sans slug

**Script migration :**

```elixir
# lib/mix/tasks/generate_missing_slugs.ex
defmodule Mix.Tasks.GenerateMissingSlugs do
  use Mix.Task
  
  alias Portfolio.{Photography, Repo}
  alias Portfolio.Photography.Album
  alias Portfolio.Photography.Services.SlugGenerator
  
  @shortdoc "Gén�re les slugs manquants pour les albums existants"
  
  def run(_args) do
    Mix.Task.run("app.start")
    
    # Trouver albums sans slug
    albums_without_slug = 
      Album
      |> where([a], is_nil(a.slug) or a.slug == "")
      |> Repo.all()
    
    IO.puts("Found #{length(albums_without_slug)} albums without slug")
    
    Enum.each(albums_without_slug, fn album ->
      case SlugGenerator.generate_unique_slug(album.title, album.date_prise_vue) do
        {:ok, slug} ->
          album
          |> Ecto.Changeset.change(slug: slug)
          |> Repo.update!()
          
          IO.puts(" #{album.title} � #{slug}")
        
        {:error, reason} ->
          IO.puts(" #{album.title} � Error: #{inspect(reason)}")
      end
    end)
    
    IO.puts("\nMigration complete!")
  end
end
```

**Exécution :**

```bash
mix generate_missing_slugs
```

**Crit�res succ�s :**
- Tous albums ont slug unique
- Aucune erreur migration
- Slugs cohérents (lisibles, pas de doublons)

---

## Références

### Documentation technique

- [Phoenix Routing](https://hexdocs.pm/phoenix/routing.html)
- [Ecto Constraints](https://hexdocs.pm/ecto/Ecto.Changeset.html#unique_constraint/3)
- [Cachex](https://hexdocs.pm/cachex/Cachex.html)
- [HTTP 301 Redirect (MDN)](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/301)

### SEO Best Practices

- Google Search Central : URL Structure
- Moz : URL Best Practices (2024)
- Ahrefs : How to Create SEO-Friendly URLs

### Exemples industrie

- WordPress : Permalinks (slugs immutables post-publication)
- Medium : Slugs avec suffix hash (titre-article-a3f2b8c4)
- Ghost : Slugs canoniques avec redirections 301
- Dev.to : Slugs username + titre

### Code pertinent

- `lib/portfolio/photography/value_objects/slug.ex` : Value Object
- `lib/portfolio/photography/album.ex` : Génération slug (actuelle)
- `lib/portfolio/photography/photo.ex` : Slugs photos
- `lib/portfolio_web/router.ex` : Routes publiques

---

## Notes

### Décisions actées

1. Slugs purs (pas hybride ID + slug)
2. Résolution collision automatique (suffix date)
3. Slug immutable sauf modification manuelle
4. Redirections 301 canoniques
5. Cache par slug TTL 1h
6. Routes publiques `/albums/:slug` (renommé depuis `:chapter`)

### Compromis acceptés

1. Lookup string vs integer : Performance lég�rement inférieure acceptable (< 5ms différence, négligeable avec cache)
2. Complexité redirections : Effort 1h justifié par préservation SEO critique
3. Table slug_redirects : Overhead DB minimal (< 10KB / 100 redirects)

### Enseignements

1. **SEO critique pour portfolio**
   - Trafic organique = source principale visiteurs
   - URLs descriptives = différence majeure ranking Google
   - Redirections 301 = investissement SEO préservé

2. **Slug immutable = best practice**
   - Standard industrie (WordPress, Medium, Ghost)
   - Évite liens cassés accidentels
   - Modification volontaire seulement (warning UI)

3. **Collision rare mais � gérer**
   - Suffix date intelligent résout 99.9% cas
   - Hash suffix pour photos (volume élevé)
   - Erreur utilisateur acceptable si collision post-date

4. **Cache essentiel performance**
   - Route publique fréquente (`/albums/:slug`)
   - Hit rate > 90% attendu (albums changent peu)
   - Invalidation simple (update album)

### Prochaines révisions

- Q1 2026 : Implémentation compl�te (collision, redirections, cache)
- Post-production : Monitoring hit rate cache
- Analyse SEO : Impact slugs sur ranking Google (6 mois)
