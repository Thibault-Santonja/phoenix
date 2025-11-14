# ADR-017 : ImageProcessing Bounded Context

Statut: Accepté
Date: 2025-11-15

## Contexte

Le projet Portfolio implémente une architecture DDD (Domain-Driven Design) avec des bounded contexts clairement séparés. Initialement, le traitement d'images était intégré dans le contexte Photography, mais l'évolution du projet a révélé plusieurs problèmes architecturaux.

### Situation initiale

**Avant :** Le module `Portfolio.ImageProcessor` était un module utilitaire dans le contexte Photography :

```
lib/portfolio/
  photography/
    image_processor.ex  # Traitement d'images
    photo.ex            # Entité Photo
    album.ex            # Entité Album
```

**Problèmes identifiés :**

1. **Violation SRP (Single Responsibility Principle)**
   - Photography gère à la fois les albums/photos ET le traitement d'images
   - Deux responsabilités distinctes dans un seul contexte

2. **Couplage fort**
   - ImageProcessor directement couplé aux schemas Ecto (Photo)
   - Difficile de réutiliser le traitement d'images hors contexte Photography
   - Tests nécessitent toute l'infrastructure Photography

3. **Évolutivité limitée**
   - Impossible d'ajouter du traitement d'images pour d'autres entités (User avatar, Album cover)
   - Logique métier du traitement noyée dans Photography

4. **Manque de séparation des préoccupations**
   - Configuration de variants (tailles, formats) mélangée avec logique métier Photography
   - Workers Oban (ImageVariantWorker) dans Photography alors que c'est du traitement générique

### Besoins

1. **Isolation du traitement d'images** : Séparer le domaine "traitement" du domaine "photography"
2. **Réutilisabilité** : Pouvoir traiter des images pour Photos, Albums, Users, etc.
3. **Configuration centralisée** : Gestion unifiée des variants (tailles, formats, qualité)
4. **Testabilité** : Tester le traitement d'images sans dépendances Photography
5. **Extensibilité** : Ajouter facilement de nouveaux types d'images à traiter

### Contraintes

- Maintenir compatibilité avec l'existant (Photos déjà en production)
- Pas de breaking changes dans l'API publique
- Performance : pas de régression sur génération de variants
- Respect des principes Clean Architecture et DDD

---

## Options Considérées

### Option 1 : Garder ImageProcessor dans Photography

Conserver l'architecture actuelle avec quelques améliorations.

**Avantages :**
- Pas de refactoring
- Familiarité avec le code existant
- Pas de migration à gérer

**Inconvénients :**
- Violation continue de SRP
- Dette technique s'accumule
- Impossible de réutiliser pour autres contextes
- Couplage Photography ↔ ImageProcessor permanent

**Rejeté** : Ne résout aucun des problèmes identifiés.

### Option 2 : Module utilitaire partagé (lib/portfolio/image_utils.ex)

Créer un module utilitaire générique hors des contextes.

```elixir
lib/portfolio/
  image_utils.ex  # Module utilitaire
  photography/
  auth/
```

**Avantages :**
- Simple à mettre en place
- Réutilisable par tous les contextes
- Pas de complexité architecturale

**Inconvénients :**
- Pas de bounded context (violation DDD)
- Module "fourre-tout" risque de grossir
- Pas de logique métier propre (juste des fonctions utilitaires)
- Configuration dispersée
- Pas d'isolation testable

**Rejeté** : Ne respecte pas les principes DDD du projet.

### Option 3 : ImageProcessing Bounded Context ⭐

Créer un bounded context dédié au traitement d'images.

**Architecture :**

```
lib/portfolio/
  image_processing/              # Bounded Context
    image_config.ex              # Configuration centralisée
    image_processor.ex           # Core domain logic
    services/
      variant_generation_service.ex
    workers/
      image_variant_worker.ex
      exif_extraction_worker.ex
  photography/                   # Bounded Context
    photo.ex
    album.ex
    services/
      photo_upload_service.ex    # Orchestre ImageProcessing
```

**Principes :**

1. **Bounded Context séparé** : ImageProcessing a son propre domaine
2. **Configuration centralisée** : `ImageConfig` définit tous les variants
3. **API publique claire** : `ImageProcessing.generate_variants/3`
4. **Communication via Services** : Photography appelle ImageProcessing, pas de couplage direct
5. **Workers isolés** : ImageVariantWorker dans ImageProcessing (pas Photography)

**Avantages :**
- ✅ Respect SRP : Chaque contexte a une responsabilité unique
- ✅ Réutilisabilité : Tout contexte peut utiliser ImageProcessing
- ✅ Configuration centralisée : `ImageConfig` unique source de vérité
- ✅ Testabilité : Tests ImageProcessing sans dépendances externes
- ✅ Évolutivité : Ajouter processing pour User, Album sans modifier Photography
- ✅ Respect DDD : Bounded context clairement défini
- ✅ Isolation : Photography ne connaît pas les détails du traitement

**Inconvénients :**
- Refactoring initial nécessaire (migration du code existant)
- Plus de fichiers (nouvelle structure)
- Courbe d'apprentissage (comprendre la séparation)

**Effort estimé :** Moyen (1-2 jours)

---

## Décision

L'option choisie est : **Option 3 - ImageProcessing Bounded Context**

### Justification

**Critères de décision :**

1. **Alignement DDD** : Excellente séparation des bounded contexts
2. **Maintenabilité** : Chaque contexte a une responsabilité claire
3. **Réutilisabilité** : ImageProcessing utilisable par Photography, Auth, futur contexte Portfolio
4. **Testabilité** : Tests isolés sans dépendances inter-contextes
5. **Évolutivité** : Facile d'ajouter de nouveaux types d'images à traiter
6. **Pragmatisme** : Refactoring raisonnable avec bénéfices clairs

**Architecture finale :**

```
Portfolio.ImageProcessing (Bounded Context)
├── ImageConfig                    # Configuration variants
├── ImageProcessor                 # Core domain logic (Vix/libvips)
├── Services
│   └── VariantGenerationService   # Orchestration génération
└── Workers
    ├── ImageVariantWorker         # Job Oban génération
    └── ExifExtractionWorker       # Job Oban extraction EXIF

Portfolio.Photography (Bounded Context)
├── Photo                          # Entité
├── Album                          # Entité
└── Services
    └── PhotoUploadService         # Appelle ImageProcessing.generate_variants/3
```

**API Publique ImageProcessing :**

```elixir
defmodule Portfolio.ImageProcessing do
  @moduledoc """
  Bounded Context pour le traitement d'images.

  API publique pour générer des variants d'images (resize, format, compression).
  """

  @doc """
  Génère les variants d'une image.

  ## Paramètres

  - `source_path` - Chemin de l'image source
  - `entity_type` - Type d'entité (:photo, :album_cover, :user_avatar)
  - `entity_id` - ID de l'entité

  ## Retour

  - `{:ok, variants}` - Liste des variants générés
  - `{:error, reason}` - Erreur de traitement

  ## Exemples

      iex> ImageProcessing.generate_variants("/path/to/image.jpg", :photo, photo_id)
      {:ok, [
        %{name: "thumb", path: "/storage/photos/.../thumb.webp", width: 400, height: 300},
        %{name: "medium", path: "/storage/photos/.../medium.webp", width: 1200, height: 900}
      ]}
  """
  @spec generate_variants(String.t(), atom(), binary()) ::
          {:ok, [map()]} | {:error, atom()}
  def generate_variants(source_path, entity_type, entity_id)
end
```

### Communication entre contextes

**Photography → ImageProcessing :**

```elixir
# Dans PhotoUploadService (Photography)
defmodule Portfolio.Photography.Services.PhotoUploadService do
  alias Portfolio.ImageProcessing

  def upload_photo(attrs) do
    with {:ok, photo} <- create_photo(attrs),
         :ok <- store_original(photo),
         {:ok, _job} <- schedule_variant_generation(photo) do
      {:ok, photo}
    end
  end

  defp schedule_variant_generation(photo) do
    # Appel asynchrone via Oban
    %{
      source_path: photo.original_path,
      entity_type: :photo,
      entity_id: photo.id
    }
    |> Portfolio.ImageProcessing.Workers.ImageVariantWorker.new()
    |> Oban.insert()
  end
end
```

**Pas de couplage inverse :** ImageProcessing ne connaît PAS Photography.

---

## Conséquences

### Positives

- **Séparation des responsabilités** : Photography gère les albums/photos, ImageProcessing gère le traitement
- **Réutilisabilité maximale** : ImageProcessing utilisable pour Photos, Albums, Users, etc.
- **Configuration centralisée** : `ImageConfig` définit tous les variants (thumb, medium, large, original)
- **Testabilité excellente** : Tests ImageProcessing isolés, pas de dépendances Photography
- **Évolutivité** : Ajouter traitement pour User avatar = juste appeler `ImageProcessing.generate_variants/3`
- **Respect DDD** : Bounded contexts clairement définis avec API publique
- **Performance** : Pas de régression (même implémentation Vix/libvips)
- **Maintenance facilitée** : Bug dans traitement = chercher dans ImageProcessing uniquement

### Négatives

- **Refactoring initial** : Migration du code existant (ImageProcessor, Workers)
- **Plus de fichiers** : Structure plus complexe avec nouveau contexte
- **Courbe d'apprentissage** : Développeurs doivent comprendre la séparation des contextes
- **Navigation** : Code traitement séparé de Photography (mais organisation logique compense)

### Neutres

- **Pas de breaking changes** : API Photography inchangée pour les clients
- **Migration transparente** : Photos existantes continuent de fonctionner
- **Communication asynchrone** : Utilisation d'Oban Workers (déjà existant)

---

## Implémentation

### Étape 1 : Créer le Bounded Context

```bash
mkdir -p lib/portfolio/image_processing/{services,workers}
```

### Étape 2 : Migrer ImageConfig

```elixir
# lib/portfolio/image_config.ex → lib/portfolio/image_processing/image_config.ex
defmodule Portfolio.ImageProcessing.ImageConfig do
  @moduledoc """
  Configuration centralisée des variants d'images.
  """

  @variants %{
    photo: [
      %{name: "thumb", width: 400, height: 300, format: :webp, quality: 85},
      %{name: "medium", width: 1200, height: 900, format: :webp, quality: 90},
      %{name: "large", width: 2400, height: 1800, format: :webp, quality: 95},
      %{name: "original", format: :webp, quality: 100}
    ],
    album_cover: [
      %{name: "thumb", width: 600, height: 400, format: :webp, quality: 85},
      %{name: "cover", width: 1920, height: 1080, format: :webp, quality: 90}
    ]
  }

  def get_variants(entity_type), do: Map.get(@variants, entity_type, [])
end
```

### Étape 3 : Migrer ImageProcessor

```elixir
# lib/portfolio/image_processor.ex → lib/portfolio/image_processing/image_processor.ex
defmodule Portfolio.ImageProcessing.ImageProcessor do
  @moduledoc """
  Core domain logic pour le traitement d'images avec Vix/libvips.
  """

  alias Vix.Vips.Image
  alias Vix.Vips.Operation

  # Implémentation inchangée (Vix/libvips)
end
```

### Étape 4 : Créer API Publique

```elixir
# lib/portfolio/image_processing.ex
defmodule Portfolio.ImageProcessing do
  @moduledoc """
  Bounded Context pour le traitement d'images.
  """

  alias Portfolio.ImageProcessing.Services.VariantGenerationService

  defdelegate generate_variants(source_path, entity_type, entity_id),
    to: VariantGenerationService
end
```

### Étape 5 : Migrer Workers

```bash
# Déplacer dans ImageProcessing
mv lib/portfolio/workers/image_variant_worker.ex \
   lib/portfolio/image_processing/workers/
mv lib/portfolio/workers/exif_extraction_worker.ex \
   lib/portfolio/image_processing/workers/
```

### Étape 6 : Adapter Photography

```elixir
# lib/portfolio/photography/services/photo_upload_service.ex
defmodule Portfolio.Photography.Services.PhotoUploadService do
  # Remplacer appels directs ImageProcessor
  # Par appels via API publique ImageProcessing
  alias Portfolio.ImageProcessing

  defp schedule_variant_generation(photo) do
    %{
      source_path: photo.original_path,
      entity_type: :photo,
      entity_id: photo.id
    }
    |> Portfolio.ImageProcessing.Workers.ImageVariantWorker.new()
    |> Oban.insert()
  end
end
```

### Étape 7 : Mettre à jour les tests

```bash
# Déplacer tests dans nouveau contexte
mv test/portfolio/image_processor_test.exs \
   test/portfolio/image_processing/image_processor_test.exs
mv test/portfolio/workers/image_variant_worker_test.exs \
   test/portfolio/image_processing/workers/image_variant_worker_test.exs
```

---

## Migration des Photos Existantes

**Bonne nouvelle :** Pas de migration de données nécessaire !

**Raison :** Les variants existants restent valides. Les Photos en production continuent de fonctionner sans modification.

**Futur :** Prochains uploads utiliseront automatiquement le nouveau contexte ImageProcessing.

---

## Évolutions Futures

### Court terme

1. ✅ Bounded Context créé et opérationnel
2. ✅ Migration du code existant
3. ✅ Tests adaptés et passants

### Moyen terme

1. **Support User avatars** : Ajouter variants pour avatars utilisateurs
   ```elixir
   ImageConfig.get_variants(:user_avatar)
   # => [%{name: "thumb", width: 150, height: 150}, ...]
   ```

2. **Support Album covers** : Générer covers pour albums
   ```elixir
   ImageProcessing.generate_variants(cover_path, :album_cover, album.id)
   ```

3. **Optimisations** : Ajout de formats AVIF si support navigateurs augmente

### Long terme

1. **Image analysis** : Détection de visages, objets (ML/AI)
2. **Smart cropping** : Crop intelligent basé sur détection de sujets
3. **Watermarking** : Ajout de watermarks configurables
4. **Batch processing** : Retraitement en masse de Photos existantes

---

## Références

- ADR-011 : Traitement d'Images avec Vix/libvips (choix technologique)
- ADR-003 : Domain-Driven Design Adoption (principes DDD)
- ADR-031 : Service Layer Complex Workflows (architecture Services)
- ADR-041 : Oban Background Jobs (workers asynchrones)

**Fichiers concernés :**
- `lib/portfolio/image_processing/` (nouveau bounded context)
- `lib/portfolio/image_processing/image_config.ex`
- `lib/portfolio/image_processing/image_processor.ex`
- `lib/portfolio/image_processing/services/variant_generation_service.ex`
- `lib/portfolio/image_processing/workers/image_variant_worker.ex`
- `lib/portfolio/image_processing/workers/exif_extraction_worker.ex`
- `lib/portfolio/photography/services/photo_upload_service.ex` (adapté)
- `test/portfolio/image_processing/` (tests migrés)

**Documentation DDD :**
- `docs/ddd/image_processing.md` (à créer - documentation stratégique du BC)
