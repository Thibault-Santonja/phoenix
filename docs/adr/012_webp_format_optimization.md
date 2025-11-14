# ADR-012 : Optimisation Format WebP

Statut: Accepté
Date: 2025-05

## Contexte

Le portfolio photographique génère 4 variantes d'images pour affichage responsive. Le choix du format de compression impacte directement trois aspects critiques :

### Enjeux performance

1. Poids des fichiers : Impact temps de chargement (mobile 3G/4G)
2. Qualité visuelle : Standard professionnel pour portfolio photographique
3. Compatibilité navigateurs : Accessibilité du portfolio

### Contraintes techniques

1. VPS Hetzner 4,51€/mois : Stockage limité (40GB SSD)
2. Génération via libvips (Vix) : Support WebP, JPEG, PNG, AVIF
3. Traitement asynchrone : Temps de génération acceptable (< 10s par photo)
4. Pas de CDN : Serveur statique depuis VPS (pas de transformation à la demande)

### Public cible (par priorité)

1. Photographes professionnels (pairs, collaborateurs)
2. Clients photographie (majoritairement professionnels)
3. Grand public intéressé par l'art photographique
4. Recruteurs techniques
5. Reste du trafic web

### Problématique

Quel format d'image adopter pour optimiser le compromis poids/qualité/compatibilité dans un contexte de portfolio photographique professionnel avec contraintes de stockage ?

---

## Options Considérées

### Option 1 : JPEG (Standard historique)

Format de référence pour la photographie numérique depuis 30 ans.

**Avantages :**
- Compatibilité universelle (100% navigateurs, tous OS)
- Qualité photographique éprouvée (lossy optimisé pour photos)
- Outils matures (preview, édition, analyse)
- Aucun fallback nécessaire
- Familiarité développeurs et utilisateurs

**Inconvénients :**
- Compression sous-optimale (25-35% moins efficace que WebP)
- Poids fichiers élevé (impact stockage et bande passante)
- Pas de support transparence (non critique pour photos)
- Technologie datée (1992)

**Estimation stockage :**
- 1000 photos × 4 variantes = 4000 fichiers
- Poids moyen JPEG Q85 : thumbnail 50KB, small 150KB, medium 300KB, large 800KB
- Total : (50 + 150 + 300 + 800) × 1000 = 1.3GB

**Effort estimé :** Faible (configuration par défaut libvips)

**Risques :**
- Saturation stockage rapide [Probabilité: Élevée, Impact: Moyen]

### Option 2 : PNG (Sans perte)

Format lossless avec compression.

**Avantages :**
- Qualité maximale (aucune perte)
- Support transparence
- Compatibilité universelle

**Inconvénients :**
- Poids fichiers 3-5x supérieur à JPEG (inacceptable)
- Pas adapté à la photographie (conçu pour graphiques)
- Temps de génération élevé

**Rejeté immédiatement :** Poids prohibitif pour portfolio photo.

### Option 3 : WebP (Google 2010) ⭐

Format moderne optimisé pour le web, basé sur codec VP8.

**Avantages :**
- Compression 25-35% meilleure que JPEG à qualité équivalente
- Support lossy et lossless
- Support transparence (non utilisé ici)
- Génération rapide avec libvips
- Maturité technique (13 ans d'existence)
- Support navigateurs excellent (94.4% selon caniuse.com, données 2025-11)

**Inconvénients :**
- Pas de support Safari < 14 (macOS Big Sur 2020, iOS 14 2020)
- Pas de support anciens Android < 4.2 (2012)
- Artefacts possibles sur textures fines à qualité élevée
- Outils desktop moins répandus (preview, édition)

**Estimation stockage :**
- Même scénario 1000 photos × 4 variantes
- Réduction 30% vs JPEG : thumbnail 35KB, small 105KB, medium 210KB, large 560KB
- Total : (35 + 105 + 210 + 560) × 1000 = 910MB

**Économie :** 390MB (30%) vs JPEG pour 1000 photos

**Effort estimé :** Faible (support natif libvips)

**Risques :**
- Qualité insuffisante grandes images [Probabilité: Moyenne, Impact: Moyen]
- Incompatibilité navigateurs anciens [Probabilité: Faible, Impact: Faible]

### Option 4 : AVIF (Alliance for Open Media 2019)

Format très récent basé sur codec AV1, successeur de WebP.

**Avantages :**
- Compression 30-40% meilleure que WebP (50-60% vs JPEG)
- Qualité perceptuelle supérieure (meilleur pour photographie)
- Support HDR et profondeur couleur élevée
- Standard ouvert (pas de brevets)
- Support navigateurs moderne excellent (93.3% selon caniuse.com)

**Inconvénients :**
- Temps de génération 3-5x plus lent que WebP (effort CPU élevé)
- Pas de support Safari < 16 (macOS Ventura 2022, iOS 16 2022)
- Format très récent (adoption outils limitée)
- Complexité configuration (nombreux paramètres)

**Estimation stockage :**
- Réduction 50% vs JPEG : thumbnail 25KB, small 75KB, medium 150KB, large 400KB
- Total : (25 + 75 + 150 + 400) × 1000 = 650MB

**Économie :** 650MB (50%) vs JPEG pour 1000 photos

**Effort estimé :** Moyen (configuration effort/qualité à optimiser)

**Risques :**
- Temps génération prohibitif [Probabilité: Moyenne, Impact: Élevé]
- Adoption trop précoce (Safari 16 septembre 2022) [Probabilité: Faible, Impact: Faible]

### Option 5 : Stratégie hybride avec `<picture>`

Utilisation de l'élément HTML `<picture>` pour servir plusieurs formats.

```html
<picture>
  <source type="image/avif" srcset="photo.avif">
  <source type="image/webp" srcset="photo.webp">
  <img src="photo.jpg" alt="Fallback">
</picture>
```

**Avantages :**
- Compatibilité universelle (fallback JPEG)
- Optimisation maximale (AVIF/WebP pour navigateurs récents)
- Graceful degradation

**Inconvénients :**
- Stockage multiplié par nombre de formats (×2 ou ×3)
- Complexité génération (plusieurs formats par variante)
- Complexité code templates
- Temps de génération cumulé
- Bande passante serveur (plusieurs requêtes par image)

**Rejeté :** Complexité et coût stockage disproportionnés pour gain marginal.

---

## Décision

L'option choisie est : **Option 3 - WebP pour toutes les variantes (état initial 2025-05)**

**Évolution implémentée (2025-11)** : Stratégie hybride WebP + AVIF
- 3 variantes WebP légères (400px, 768px, 1280px)
- 1 variante AVIF qualité maximale (1920px)
- Voir PM-032 pour détails formats

### Critères de décision

**Alignement avec l'architecture :**
- Intégration native libvips (Vix) via suffix notation `[Q=85,effort=4,strip]`
- Génération rapide compatible objectif < 10s par photo
- Pas de modification infrastructure (CDN, serveur transformation)

**Impact sur la dette technique :**
- Configuration variantes hardcodée dans `image_processor.ex` et `image_helpers.ex`
- Risque de désynchronisation (violation DRY)
- Nécessite refactoring centralisé dans configuration application

**Maintenabilité :**
- Code simple (pas de logique multi-format)
- Tests visuels nécessaires (vérification qualité)
- Migration future AVIF facilitée (changement configuration uniquement)

**Performance :**
- Génération : 3-5s pour 4 variantes WebP (12MP)
- Stockage : Réduction 30% vs JPEG (390MB économisés / 1000 photos)
- Chargement : Réduction 30% bande passante (impact mobile significatif)

**Sécurité :**
- Stripping métadonnées EXIF (confidentialité GPS)
- Aucun risque spécifique au format WebP

**Coût/Effort :**
- Implémentation : Faible (configuration libvips triviale)
- Stockage : Réduction 30% = retarde saturation 40GB VPS
- Temps développement : 1 jour (implémentation + tests)

**Réversibilité :**
- Migration JPEG : Triviale (changement format dans configuration)
- Migration AVIF : Simple (support natif libvips)
- Régénération variantes : Script Mix task (1-2h pour 1000 photos)

### Décision finale

Adoption WebP pour toutes les variantes (thumbnail, small, medium, large) avec les justifications suivantes :

1. **Compromis optimal actuel** : Meilleure compression que JPEG (30%) avec qualité acceptable, génération rapide, compatibilité excellente (94.4%)

2. **Public cible compatible** : Photographes pros et clients utilisent navigateurs récents (Chrome, Firefox, Safari 14+), perte < 6% trafic acceptable

3. **Contrainte stockage** : 390MB économisés / 1000 photos = critique pour VPS 40GB

4. **Transition AVIF planifiée** : Migration variant `large` uniquement vers AVIF Q1 2026 pour qualité maximale (stratégie hybride)

---

## Conséquences

### Positives

1. **Stockage optimisé**
   - Réduction 30% poids vs JPEG (390MB / 1000 photos)
   - Retarde saturation VPS 40GB
   - Coût hébergement maîtrisé (pas de migration stockage cloud)

2. **Performance chargement**
   - Réduction 30% bande passante
   - Impact mobile significatif (3G/4G)
   - Temps chargement page amélioré (Core Web Vitals)

3. **Génération rapide**
   - 3-5s pour 4 variantes (12MP)
   - Compatible workflow upload asynchrone Oban
   - Pas de timeout risque

4. **Compatibilité suffisante**
   - 94.4% navigateurs supportés (caniuse.com 2025-11)
   - Safari 14+ (septembre 2020) : 5 ans de recul
   - Public cible (photographes, clients pros) utilise navigateurs récents

5. **Qualité acceptable**
   - WebP Q75-85 suffisant pour variantes thumbnail/small/medium
   - Artefacts minimaux sur petites/moyennes tailles
   - Migration AVIF prévue pour variant `large` (qualité maximale)

### Négatives

1. **Incompatibilité navigateurs anciens (géré et accepté)**
   - Safari < 14 (macOS < Big Sur 2020, iOS < 14 2020) : pas d'affichage images
   - Android < 4.2 (2012) : négligeable
   - Internet Explorer : non supporté (fin de vie 2022)
   - **Mitigation** : Aucune (public cible compatible, perte < 6% acceptable)

2. **Qualité WebP limitée grandes images (résolu Q1 2026)**
   - Artefacts possibles sur textures fines à résolution 1920px
   - WebP Q85 sous-optimal pour portfolio professionnel haute résolution
   - **Mitigation** : Migration variant `large` vers AVIF Q95 (Q1 2026)

3. **Configuration variantes dupliquée (à corriger)**
   - Hardcodée dans `image_processor.ex` (génération) et `image_helpers.ex` (affichage)
   - Risque désynchronisation si modification tailles variantes
   - Violation principe DRY
   - **Mitigation** : Refactoring centralisation configuration (voir Plan d'action)

4. **Absence fallback `<picture>` (accepté)**
   - Pas de dégradation gracieuse vers JPEG
   - Navigateurs incompatibles : aucune image affichée
   - **Mitigation** : Aucune (complexité disproportionnée, public cible compatible)

### Neutres

1. **Outils desktop limités**
   - Prévisualisation WebP moins répandue que JPEG (Finder macOS, Windows Explorer)
   - Impact faible (développement uniquement, pas utilisateurs finaux)

2. **Standard Google**
   - Format contrôlé par Google (pas fully open comme AVIF)
   - Impact nul (adoption large, pérennité assurée)

---

## Plan d'action

### Phase 1 : Refactoring Configuration (Avant Q1 2026)

**Problème identifié :** Configuration variantes dupliquée dans `image_processor.ex` et `image_helpers.ex`.

**Solution :** Centralisation dans configuration application avec module partagé.

**Implémentation :**

```elixir
# config/config.exs
config :portfolio, :image_variants, [
  thumbnail: [width: 320, quality: 75, format: :webp, effort: 2],
  small: [width: 640, quality: 80, format: :webp, effort: 3],
  medium: [width: 1024, quality: 85, format: :webp, effort: 4],
  large: [width: 1920, quality: 85, format: :webp, effort: 4]
]

# lib/portfolio/image_config.ex (nouveau module)
defmodule Portfolio.ImageConfig do
  @moduledoc """
  Centralized configuration for image variants.
  
  Provides a single source of truth for variant dimensions, quality settings,
  and format choices to avoid duplication between ImageProcessor and ImageHelpers.
  """
  
  @doc """
  Returns the configured image variants.
  
  ## Examples
  
      iex> ImageConfig.variants()
      %{
        thumbnail: [width: 320, quality: 75, format: :webp, effort: 2],
        small: [width: 640, quality: 80, format: :webp, effort: 3],
        medium: [width: 1024, quality: 85, format: :webp, effort: 4],
        large: [width: 1920, quality: 85, format: :webp, effort: 4]
      }
  """
  @spec variants() :: %{atom() => Keyword.t()}
  def variants do
    Application.get_env(:portfolio, :image_variants, default_variants())
    |> Enum.into(%{})
  end
  
  @doc """
  Returns the width for a specific variant.
  
  ## Examples
  
      iex> ImageConfig.variant_width(:thumbnail)
      320
  """
  @spec variant_width(atom()) :: pos_integer() | nil
  def variant_width(variant_name) do
    variants()
    |> Map.get(variant_name)
    |> Kernel.||([])
    |> Keyword.get(:width)
  end
  
  @doc """
  Returns a map of variant names (as strings) to their widths.
  Used by ImageHelpers for srcset generation.
  
  ## Examples
  
      iex> ImageConfig.variant_widths()
      %{"thumbnail" => 320, "small" => 640, "medium" => 1024, "large" => 1920}
  """
  @spec variant_widths() :: %{String.t() => pos_integer()}
  def variant_widths do
    variants()
    |> Enum.into(%{}, fn {name, config} ->
      {to_string(name), Keyword.fetch!(config, :width)}
    end)
  end
  
  defp default_variants do
    [
      thumbnail: [width: 320, quality: 75, format: :webp, effort: 2],
      small: [width: 640, quality: 80, format: :webp, effort: 3],
      medium: [width: 1024, quality: 85, format: :webp, effort: 4],
      large: [width: 1920, quality: 85, format: :webp, effort: 4]
    ]
  end
end
```

**Modifications ImageProcessor :**

```elixir
# lib/portfolio/image_processor.ex
defmodule Portfolio.ImageProcessor do
  alias Portfolio.ImageConfig
  
  # Supprimer default_variants/0, utiliser ImageConfig.variants/0
  defp variants, do: ImageConfig.variants()
  
  # Reste du code inchangé
end
```

**Modifications ImageHelpers :**

```elixir
# lib/portfolio_web/image_helpers.ex
defmodule PortfolioWeb.ImageHelpers do
  alias Portfolio.ImageConfig
  
  def image_srcset(%Photo{variants: variants}) when is_map(variants) do
    variant_widths = ImageConfig.variant_widths()
    
    variants
    |> Enum.filter(fn {name, _url} -> Map.has_key?(variant_widths, name) end)
    |> Enum.sort_by(fn {name, _url} -> variant_widths[name] end)
    |> Enum.map_join(", ", fn {name, url} ->
      width = variant_widths[name]
      "#{url} #{width}w"
    end)
  end
  
  # Reste du code inchangé
end
```

**Tests :**

```elixir
# test/portfolio/image_config_test.exs
defmodule Portfolio.ImageConfigTest do
  use ExUnit.Case, async: true
  
  alias Portfolio.ImageConfig
  
  test "variants/0 returns configured variants" do
    variants = ImageConfig.variants()
    assert is_map(variants)
    assert Map.has_key?(variants, :thumbnail)
    assert Map.has_key?(variants, :large)
  end
  
  test "variant_width/1 returns width for variant" do
    assert ImageConfig.variant_width(:thumbnail) == 320
    assert ImageConfig.variant_width(:large) == 1920
  end
  
  test "variant_widths/0 returns string-keyed map" do
    widths = ImageConfig.variant_widths()
    assert widths["thumbnail"] == 320
    assert widths["large"] == 1920
  end
end
```

**Critères de succès :**
- Tests unitaires `ImageConfig` passent
- Tests existants `ImageProcessor` et `ImageHelpers` passent sans modification
- Aucune régression visuelle sur affichage images
- Configuration centralisée en un seul endroit

**Effort estimé :** 2-3 heures (création module + refactoring + tests)

### Phase 2 : Migration AVIF variant large (Q1 2026)

**Objectif :** Améliorer qualité variant `large` (1920px) avec format AVIF.

**Étapes :**

1. **Tests visuels comparatifs (1 semaine)**
   
   Script de génération grille comparaison :
   
   ```elixir
   # scripts/compare_formats.exs
   
   test_photos = [
     "landscape_12mp.jpg",   # Paysage
     "portrait_12mp.jpg",    # Portrait
     "texture_12mp.jpg"      # Texture fine
   ]
   
   formats = [:webp, :avif]
   qualities = [80, 85, 90, 95]
   efforts = [4, 6]
   
   for photo <- test_photos,
       fmt <- formats,
       q <- qualities,
       e <- efforts do
     output = "tmp/tests/#{Path.basename(photo, ".jpg")}_#{fmt}_q#{q}_e#{e}.#{fmt}"
     Portfolio.ImageProcessor.generate_single_variant(photo, output, fmt, q, e)
     
     # Mesures
     size = File.stat!(output).size
     IO.puts("#{output}: #{div(size, 1024)}KB")
   end
   ```
   
   Analyse :
   - Comparaison visuelle côte à côte (zoom 100%, 200%)
   - Mesure poids fichiers (ratio compression)
   - Mesure temps génération (effort 4 vs 6)
   - Décision : AVIF Q95 effort 6 (qualité max, temps acceptable)

2. **Mise à jour configuration (15 min)**
   
   ```elixir
   # config/config.exs
   config :portfolio, :image_variants, [
     thumbnail: [width: 320, quality: 75, format: :webp, effort: 2],
     small: [width: 640, quality: 80, format: :webp, effort: 3],
     medium: [width: 1024, quality: 85, format: :webp, effort: 4],
     large: [width: 1920, quality: 95, format: :avif, effort: 6]  # Changement ici
   ]
   ```

3. **Adaptation code génération (2 heures)**
   
   Support multi-format dans `ImageProcessor` :
   
   ```elixir
   defp generate_variant(image, variant_name, config, output_base_path) do
     width = Keyword.fetch!(config, :width)
     quality = Keyword.fetch!(config, :quality)
     format = Keyword.get(config, :format, :webp)
     effort = Keyword.get(config, :effort, 4)
     
     extension = case format do
       :webp -> "webp"
       :avif -> "avif"
       :jpeg -> "jpg"
     end
     
     output_path = Path.join(output_base_path, "#{variant_name}.#{extension}")
     
     # Génération avec format dynamique
     with {:ok, resized} <- resize_image(image, width),
          :ok <- save_image(resized, output_path, format, quality, effort) do
       {:ok, output_path}
     end
   end
   
   defp save_image(image, output_path, :webp, quality, effort) do
     suffix = "[Q=#{quality},effort=#{effort},strip]"
     Image.write_to_file(image, output_path <> suffix)
   end
   
   defp save_image(image, output_path, :avif, quality, effort) do
     suffix = "[Q=#{quality},effort=#{effort},strip]"
     Image.write_to_file(image, output_path <> suffix)
   end
   ```

4. **Régénération variantes existantes (8-10 heures pour 1000 photos)**
   
   Script Mix task :
   
   ```elixir
   # lib/mix/tasks/regenerate_large_variants.ex
   defmodule Mix.Tasks.RegenerateLargeVariants do
     use Mix.Task
     
     @shortdoc "Regenerate large variants in AVIF format"
     
     def run(_args) do
       Mix.Task.run("app.start")
       
       Portfolio.Photography.list_all_photos()
       |> Enum.each(fn photo ->
         Portfolio.Photography.regenerate_variant(photo, :large)
         IO.write(".")
       end)
       
       IO.puts("\nDone!")
     end
   end
   ```
   
   Exécution :
   ```bash
   mix regenerate_large_variants
   # Progression : 1000 photos × 5-8s (effort 6) = 8-10h
   # Lancer en background, monitoring logs
   ```

5. **Tests régression (1 jour)**
   - Affichage correct variantes AVIF dans galerie
   - Srcset correct (extension .avif pour variant large)
   - Fallback medium.webp si large.avif indisponible
   - Tests navigateurs (Chrome, Firefox, Safari 16+)

**Critères de succès :**
- Qualité visuelle large améliorée (validation photographe)
- Compression AVIF > 30% vs WebP (mesure poids)
- Temps génération < 10s par photo (effort 6 acceptable)
- Aucune régression affichage navigateurs compatibles

**Rollback plan :**
Si AVIF problématique (temps génération > 15s, artefacts, bugs libvips) :
1. Revenir configuration WebP large Q85 effort 4
2. Régénérer variantes large (mix task)
3. Différer migration AVIF (Q2 2026)

### Phase 3 : Monitoring et optimisation (Post-migration AVIF)

**Métriques à surveiller :**
- Temps génération moyen par photo (dashboard admin)
- Poids moyen variantes (évolution stockage)
- Taux erreur génération AVIF (logs Oban)
- Feedback photographes sur qualité

**Optimisations futures possibles :**
- Tests AVIF pour toutes variantes (si temps génération acceptable)
- Ajustement qualités par type photo (paysage vs portrait)
- Cache variantes fréquemment consultées (CDN futur)

---

## Références

### Documentation technique

- [WebP (Google)](https://developers.google.com/speed/webp)
- [AVIF (Alliance for Open Media)](https://aomediacodec.github.io/av1-avif/)
- [Vix libvips format support](https://hexdocs.pm/vix/Vix.Vips.Image.html#write_to_file/2)
- [Can I Use WebP](https://caniuse.com/webp) - 94.4% (2025-11)
- [Can I Use AVIF](https://caniuse.com/avif) - 93.3% (2025-11)

### Benchmarks et études

- Google WebP study (2010) : 25-35% compression vs JPEG
- Netflix AVIF study (2020) : 30-40% compression vs WebP
- Jake Archibald "AVIF has landed" (2020) : Tests visuels comparatifs

### Code pertinent

- `lib/portfolio/image_processor.ex` : Génération variantes WebP
- `lib/portfolio_web/image_helpers.ex` : Affichage responsive srcset
- `config/config.exs` : Configuration variantes (après refactoring)
- `lib/portfolio/image_config.ex` : Module centralisé (à créer)

---

## Notes

### Décisions actées

1. WebP pour toutes variantes (état actuel 2025-05)
2. Pas de fallback `<picture>` (complexité disproportionnée)
3. Migration AVIF variant large uniquement (Q1 2026)
4. Refactoring configuration centralisée (avant migration AVIF)

### Compromis acceptés

1. Incompatibilité Safari < 14 (< 6% trafic, public cible compatible)
2. Qualité WebP Q85 sous-optimale large (résolu Q1 2026 avec AVIF)
3. Configuration dupliquée temporaire (résolu Phase 1 refactoring)

### Enseignements

1. **Format moderne critique pour stockage**
   - 30% économie WebP vs JPEG = 390MB / 1000 photos
   - VPS 40GB : 130 photos JPEG = saturation, vs 170 photos WebP
   - WebP repousse nécessité migration cloud storage (coût)

2. **Stratégie hybride optimale**
   - WebP excellent pour petites/moyennes variantes (génération rapide, qualité suffisante)
   - AVIF nécessaire pour large (qualité professionnelle, temps génération acceptable)
   - Éviter multiplication formats (complexité, stockage)

3. **Compatibilité 94% suffisante**
   - Public cible (photographes, clients pros) utilise navigateurs récents
   - Safari 14+ (2020) : 5 ans de recul, adoption largement complète
   - Perte < 6% trafic acceptable (anciens devices, veille technologique)

4. **Configuration centralisée critique**
   - DRY violation initialement acceptée (POC rapide)
   - Refactoring nécessaire avant évolutions (migration AVIF)
   - Module `ImageConfig` = source unique vérité

### Prochaines révisions

- Post-migration AVIF (Q2 2026) : Retour expérience qualité/performance
- Après 1 an production (Q2 2026) : Analyse stockage réel, évaluation saturation
- Monitoring continu : Feedback photographes sur qualité rendu
