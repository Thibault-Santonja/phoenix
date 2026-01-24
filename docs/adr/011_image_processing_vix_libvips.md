# ADR-011 : Traitement d'Images avec Vix/libvips

Statut: Accepté
Date: 2025-05

## Contexte

Le portfolio photographique doit afficher des images haute résolution (12MP+) tout en garantissant des temps de chargement acceptables sur mobile et desktop. Les contraintes sont multiples :

### Besoins fonctionnels

1. Génération automatique de variantes pour affichage responsive
2. Compression optimale (balance qualité/poids)
3. Support des métadonnées EXIF (date, GPS, équipement photo)
4. Traitement asynchrone pour ne pas bloquer l'upload

### Contraintes techniques

1. VPS Hetzner à 4,51€/mois (2 CPU, 4Go RAM)
2. Budget limité (pas de services cloud de traitement d'images)
3. Pas de dépendance Node.js/npm (stack 100% Elixir)
4. Intégration avec Oban pour jobs asynchrones

### Problématique

Comment traiter efficacement des images haute résolution dans un environnement contraint en ressources, tout en maintenant une qualité professionnelle pour un portfolio photographique ?

---

## Options Considérées

### Option 1 : ImageMagick via Mogrify

Bibliothèque de référence pour le traitement d'images, wrapper Elixir `mogrify` disponible.

**Avantages :**
- Très mature et documenté
- Familiarité du développeur avec ImageMagick
- Large support de formats
- Communauté active

**Inconvénients :**
- Performance sous-optimale (fork de processus pour chaque opération)
- Consommation mémoire élevée (charge image entière en RAM)
- Temps de traitement 2-3x plus lent que libvips
- Pas optimisé pour traitement par lot

**Benchmark indicatif :**
- Image 12MP (4000x3000) : ~8-12s pour 4 variantes
- Mémoire : ~150-200MB peak par image

### Option 2 : Sharp (Node.js) via Port

Bibliothèque Node.js haute performance basée sur libvips.

**Avantages :**
- Performance excellente (basé sur libvips)
- API ergonomique
- Très utilisé (npm)

**Inconvénients :**
- Dépendance Node.js/npm (contraire à philosophie stack 100% Elixir)
- Communication via Port (overhead sérialisation)
- Complexité déploiement (gestion versions Node)
- Maintenance double stack

**Rejeté** : Dépendance Node.js inacceptable.

### Option 3 : Vix (libvips) ⭐

Wrapper Elixir pour libvips via NIFs (Native Implemented Functions).

**Avantages :**
- Performance optimale (libvips = référence C)
- Streaming pipeline (pas de chargement complet en RAM)
- Consommation mémoire réduite (~50MB vs 150MB ImageMagick)
- Traitement 2-3x plus rapide qu'ImageMagick
- 100% Elixir ecosystem
- Installation simple (precompiled binaries via Mix)

**Inconvénients :**
- Documentation moins riche qu'ImageMagick
- Communauté Elixir plus petite
- Première expérience du développeur avec libvips

**Benchmark mesuré :**
- Image 12MP (4000x3000) : 3-5s pour 3 variantes WebP + 1 AVIF
- Mémoire : ~50MB peak par image
- CPU : 100% pendant traitement (acceptable pour job async)
- AVIF génération : ~1.5x plus lente que WebP (compression supérieure)

---

## Décision

**Adoption de Vix (libvips) comme moteur de traitement d'images.**

### Configuration technique

#### Variantes générées

```elixir
@variants %{
  thumbnail: %{width: 400, quality: 75, format: :webp},   # Cards, previews (Tailwind xs/sm)
  medium: %{width: 768, quality: 80, format: :webp},       # Tablets (Tailwind md)
  large_webp: %{width: 1280, quality: 85, format: :webp}, # Desktop (Tailwind lg/xl)
  large_avif: %{width: 1920, quality: 90, format: :avif}   # Fullscreen original compressé
}
```

**Rationale tailles :**
- Alignement avec breakpoints Tailwind CSS (400/768/1280/1920)
- 3 variantes WebP légères pour chargement rapide
- 1 variante AVIF haute qualité pour affichage plein écran
- AVIF : Compression supérieure (~30% vs WebP) pour image originale

**Rationale qualités :**
- Thumbnail/Small : qualité réduite acceptable (petite taille affichage)
- Medium/Large : qualité élevée pour portfolio professionnel
- Balance poids/qualité (WebP très efficace à Q80-85)

#### Format de sortie

**Actuel :** WebP pour toutes variantes

**Justification WebP :**
- Compression 25-35% meilleure que JPEG à qualité équivalente
- Support navigateurs modernes suffisant (Safari 14+, ignorance compatibilité anciens navigateurs)
- Codec moderne adapté au web

**Évolution prévue (Q1 2026) :**
```elixir
# Variante large uniquement : AVIF pour qualité maximale
@variants %{
  thumbnail: %{width: 320, quality: 75, format: :webp, effort: 2},
  small: %{width: 640, quality: 80, format: :webp, effort: 3},
  medium: %{width: 1024, quality: 85, format: :webp, effort: 4},
  large: %{width: 1920, quality: 95, format: :avif, effort: 6}
}
```

**Justification évolution :**
- AVIF : meilleure qualité perceptuelle pour grandes images (supérieur à WebP et JPEG)
- WebP peut produire artefacts sur textures fines (critique pour portfolio photo)
- Qualité augmentée à 95 pour variant large (standard industrie portfolio)
- AVIF offre compression supérieure à JPEG (30-40%) avec qualité équivalente
- Support navigateurs suffisant (93.3% selon caniuse.com, Safari 16+ 2022)
- Effort gradué par taille (2-3-4-6) pour optimiser temps/qualité

#### Algorithme de redimensionnement

```elixir
Vix.Vips.Operation.resize(img, scale,
  kernel: :VIPS_KERNEL_LANCZOS3
)
```

**Lanczos3 :** Compromis optimal qualité/performance pour photographie.

#### Gestion métadonnées EXIF

**Actuel :**
```elixir
Vix.Vips.Operation.strip(img)  # Suppression totale
```

**Problème identifié :** Perte d'informations précieuses (date, GPS, équipement).

**Évolution prévue (Q1 2026) :**
```elixir
# 1. Extraction EXIF vers base de données
defmodule Portfolio.Photography.ValueObjects.ExifData do
  @type t :: %__MODULE__{
    captured_at: DateTime.t() | nil,
    camera: String.t() | nil,
    lens: String.t() | nil,
    iso: integer() | nil,
    aperture: String.t() | nil,
    focal_length: String.t() | nil,
    gps_latitude: float() | nil,
    gps_longitude: float() | nil
  }
end

# 2. Puis stripping des fichiers générés
Vix.Vips.Operation.strip(img)
```

**Bénéfices :**
- Confidentialité : GPS non exposé dans fichiers publics
- Fonctionnalité : Timeline chronologique via `captured_at`
- Professionnalisme : Affichage équipement photo (crédibilité)
- SEO : Métadonnées structurées pour moteurs de recherche

#### Configuration Oban

```elixir
# config/runtime.exs
config :portfolio, Oban,
  queues: [
    default: [limit: 10],
    image_processing: [limit: 2]  # Limitation concurrence
  ]
```

**Justification `limit: 2` :**

Calcul ressources VPS (2 CPU, 4Go RAM) :
- 1 image en traitement : ~50MB RAM, 1 CPU à 100% pendant 3-5s
- 2 images simultanées : ~100MB RAM, 2 CPU à 100%
- Marge sécurité pour PostgreSQL (~300MB) + Phoenix (~200MB) + OS (~500MB)
- Total : 100MB + 1000MB = 1100MB / 4096MB = 27% RAM utilisée

**Risque identifié :** Images > 12MP (RAW 24MP+) peuvent consommer 200-300MB.

**Mitigation :**
- Validation taille fichier en amont (max 50MB upload)
- Monitoring mémoire Oban workers
- Fallback : réduction `limit: 1` si OOM détecté

---

## Conséquences

### Positives

1. **Performance**
   - Traitement 2-3x plus rapide qu'ImageMagick
   - Temps upload+processing acceptable (< 10s pour 12MP)
   - Scalabilité : 2 images // = throughput 24 images/minute

2. **Ressources**
   - Consommation mémoire réduite (50MB vs 150MB)
   - Compatible VPS économique (4,51€/mois)
   - Pas de coût cloud externe (AWS Lambda, Cloudinary)

3. **Qualité**
   - Lanczos3 : qualité professionnelle
   - WebP : poids optimisés (chargement rapide mobile)
   - Évolution JPEG/AVIF large : qualité maximale portfolio

4. **Maintenance**
   - Stack 100% Elixir (pas de Node.js)
   - Vix bien maintenu (dernière version 0.26)
   - Installation simple (precompiled binaries)

### Négatives

1. **Absence de tests de charge**
   - Pas de mesure performance réelle VPS (pas encore en production)
   - Risque inconnu : comportement sous charge (10+ uploads simultanés)
   - **Mitigation prévue :** Environnement Docker mimant VPS (preprod)

2. **Courbe d'apprentissage**
   - Première expérience libvips pour développeur
   - Documentation moins abondante qu'ImageMagick
   - **Impact faible :** Pas de difficultés rencontrées à ce jour

3. **Choix formats/qualités empiriques**
   - Tailles variantes "hasardeuses" (non basées sur breakpoints Tailwind)
   - Qualités choisies par compromis (pas de tests visuels systématiques)
   - **Amélioration future :** Alignement Tailwind (400, 768, 1280, 1920)

4. **Métadonnées perdues**
   - Stripping total EXIF actuellement
   - Perte date/GPS/équipement (fonctionnalités manquées)
   - **Résolu :** Extraction DB prévue Q1 2025

### Risques

1. **Dépassement mémoire VPS**
   - Probabilité : Faible (mitigation `limit: 2`)
   - Impact : Élevé (crash worker, OOM killer)
   - **Plan contingence :** Monitoring + réduction `limit: 1`

2. **Qualité WebP insuffisante**
   - Probabilité : Moyenne (artefacts possibles grandes images)
   - Impact : Moyen (perception qualité portfolio)
   - **Plan contingence :** Migration AVIF variant large (Q1 2026)

---

## Plan d'Évolution

### Phase 1 : Tests et Mesures (Avant production)

```bash
# Environnement Docker VPS-like
docker run --cpus=2 --memory=4g portfolio:preprod

# Benchmark charge
mix run scripts/benchmark_image_processing.exs
# - 1 image : temps, mémoire
# - 10 images // : comportement queue Oban
# - 100 images : détection bottlenecks
```

**Critères validation :**
- Temps moyen < 5s par image (12MP)
- Mémoire peak < 1GB (total système)
- Aucun timeout Oban (défaut 15min)

### Phase 2 : Optimisation Formats (Q1 2026)

1. **Tests visuels comparatifs**
   ```elixir
   # Générer grille comparaison
   formats = [:webp, :avif]
   qualities = [80, 85, 90, 95]
   efforts = [4, 6]

   for fmt <- formats, q <- qualities, e <- efforts do
     generate_variant(source, "#{fmt}_q#{q}_e#{e}", fmt, q, e)
   end
   ```

2. **Décision format variant large**
   - Comparaison visuelle côte à côte
   - Mesure poids fichiers
   - Mesure temps traitement (effort 6 vs 4)
   - Choix : AVIF Q95 effort 6

3. **Migration**
   ```elixir
   # Régénération variantes large existantes
   Portfolio.Photography.regenerate_variants(:large, format: :avif, quality: 95, effort: 6)
   ```

### Phase 3 : Extraction EXIF (Q1 2026)

1. **Ajout Value Object**
   ```elixir
   # lib/portfolio/photography/value_objects/exif_data.ex
   defmodule Portfolio.Photography.ValueObjects.ExifData do
     defstruct [:captured_at, :camera, :lens, :iso, :aperture,
                :focal_length, :gps_latitude, :gps_longitude]

     @spec extract_from_file(String.t()) :: {:ok, t()} | {:error, term()}
     def extract_from_file(path) do
       # Vix.Vips.Image.get_fields/1 pour lire EXIF
     end
   end
   ```

2. **Migration base données**
   ```elixir
   # priv/repo/migrations/XXX_add_exif_to_photos.exs
   alter table(:photos) do
     add :captured_at, :utc_datetime
     add :camera, :string
     add :lens, :string
     add :iso, :integer
     add :aperture, :string
     add :focal_length, :string
     add :gps_latitude, :float
     add :gps_longitude, :float
   end

   create index(:photos, [:captured_at])
   create index(:photos, [:camera])
   ```

3. **Intégration pipeline traitement**
   ```elixir
   # Avant stripping
   with {:ok, exif} <- ExifData.extract_from_file(source_path),
        {:ok, photo} <- Photos.update_exif(photo, exif),
        {:ok, img} <- Vix.Vips.Image.new_from_file(source_path) do
     # Puis strip et génération variantes
   end
   ```

4. **Nouvelles fonctionnalités**
   - Timeline chronologique par date de prise
   - Filtrage par équipement (camera, lens)
   - Affichage carte (GPS) en mode admin
   - Métadonnées structurées (Schema.org PhotoObject)

### Phase 4 : Optimisation Tailles (Q2 2026)

**Alignement Tailwind breakpoints :**
```elixir
@variants %{
  thumbnail: %{width: 400, quality: 75, format: :webp, effort: 2},   # Cards
  small: %{width: 768, quality: 80, format: :webp, effort: 3},       # sm: 640, md: 768
  medium: %{width: 1280, quality: 85, format: :webp, effort: 4},     # xl: 1280
  large: %{width: 1920, quality: 95, format: :avif, effort: 6}       # FHD
}
```

**Impact attendu :**
- Réduction 10-15% poids total (meilleure granularité)
- Amélioration UX responsive (tailles optimales par breakpoint)

---

## Alternatives Futures

### Si contraintes changent (croissance, budget)

1. **Service cloud (Cloudinary, imgix)**
   - Déclencheur : > 10k photos ou > 1000 visiteurs/jour
   - Coût : ~50-100€/mois
   - Bénéfice : CDN intégré, transformations à la demande

2. **Serverless (AWS Lambda + Sharp)**
   - Déclencheur : Pics de charge imprévisibles
   - Coût : Pay-per-use (~10-30€/mois)
   - Bénéfice : Auto-scaling

3. **GPU (NVIDIA libvips)**
   - Déclencheur : > 100 photos/jour uploadées
   - Coût : VPS GPU (~30€/mois)
   - Bénéfice : Traitement 5-10x plus rapide

**Décision actuelle :** Aucune migration prévue (coût/besoin inadéquat).

---

## Références

### Documentation

- [Vix (Elixir wrapper)](https://hexdocs.pm/vix/)
- [libvips (C library)](https://www.libvips.org/API/current/)
- [Benchmark libvips vs ImageMagick](https://github.com/libvips/libvips/wiki/Speed-and-memory-use)

### Benchmarks tiers

- libvips : 3-5x plus rapide qu'ImageMagick (selon opérations)
- WebP : 25-35% compression vs JPEG (Google)
- AVIF : 30-40% compression vs JPEG (Netflix study)

### Code pertinent

- `lib/portfolio/image_processor.ex` : Module principal traitement
- `lib/portfolio/workers/image_variant_worker.ex` : Worker Oban
- `test/portfolio/image_processor_test.exs` : Tests unitaires

---

## Notes

### Décisions en suspens

1. **Format variant large** : Migration AVIF (tests Q1 2026)
2. **Tailles variantes** : Alignement Tailwind (Q2 2026)
3. **Monitoring** : Alertes mémoire Oban (avant production)

### Enseignements

1. **Performance mesurée insuffisante**
   - Benchmarks théoriques ≠ réalité production
   - Nécessité environnement preprod Docker

2. **Métadonnées sous-estimées**
   - EXIF = opportunité fonctionnelle (timeline, équipement)
   - Extraction DB = bonne pratique (confidentialité + features)

3. **Formats images en évolution**
   - AVIF supérieur à WebP et JPEG pour qualité photographique
   - Stratégie hybride (WebP petites/moyennes, AVIF large) optimale
   - Support navigateurs suffisant (93.3%) pour adoption progressive

### Prochaines révisions

- Retour expérience charge réelle
- Migration format large AVIF + extraction EXIF
- Optimisation tailles variantes
