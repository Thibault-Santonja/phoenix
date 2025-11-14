# ADR-044: Stratégie CDN Cloudflare

Statut: Accepté  
Date: 2025-11-11

## Contexte

Un portfolio photographique sert principalement des fichiers statiques lourds (images) à des utilisateurs géographiquement dispersés. La stratégie de distribution de ces contenus impacte directement la performance perçue, la bande passante consommée, et les coûts d'infrastructure.

### Problématique

Le portfolio Photography génère plusieurs variantes d'images par photo (thumbnail, small, medium, large, original) conformément à l'ADR-011. Ces fichiers représentent :

Caractéristiques du trafic :
- 90% du volume : Images statiques (photos)
- 10% du volume : HTML/CSS/JS dynamique
- Taille moyenne photo : 200 Ko (thumbnail) à 5 Mo (original)
- Changements rares : Publication album 1-2x/mois

Contraintes techniques :
- Stockage local : `/priv/static/uploads` (voir ADR-010)
- Déploiement mono-serveur Hetzner VPS (voir ADR-043)
- Bande passante limitée : 20 To/mois (Hetzner)
- Latence Europe : Serveur Allemagne (Nuremberg)

**Voir aussi** :
- ADR-010 (Storage Strategy) pour le stockage local des images
- ADR-011 (Image Processing) pour les variantes d'images servies via CDN
- ADR-030 (Domain Events) pour l'invalidation CDN via événements
- ADR-040 (Caching Strategy) pour la stratégie de cache complémentaire
- ADR-041 (Oban) pour l'invalidation CDN asynchrone
- ADR-043 (Deployment) pour l'infrastructure Hetzner

Contraintes opérationnelles :
- Budget très limité (quasiment aucun moyen financier)
- Simplicité : Éviter infrastructure complexe
- Cache invalidation : Nécessaire lors publication album

Sans stratégie CDN claire :
- Latence élevée pour visiteurs hors Europe (USA, Asie)
- Consommation bande passante serveur excessive
- Coûts potentiels si dépassement limite 20 To/mois
- Serveur surchargé si trafic soudain (effet viral)

## Options considérées

### Option 1: Pas de CDN (NoOp Stub)

Description:

Servir toutes les images directement depuis le serveur Hetzner sans CDN. L'implémentation actuelle utilise `Portfolio.CDN.NoOp` qui ne fait rien.

Architecture :

```
User (Paris)                  User (Tokyo)
    ↓                              ↓
    └──────────────┬───────────────┘
                   ↓
            Hetzner VPS
           (Nuremberg, DE)
                   ↓
         /priv/static/uploads
         (Local Storage)
```

Implémentation actuelle :

```elixir
# lib/portfolio/cdn/cdn.ex
@callback invalidate(paths :: [String.t()]) :: :ok | {:error, term()}

# lib/portfolio/cdn/no_op.ex
defmodule Portfolio.CDN.NoOp do
  @behaviour Portfolio.CDN
  
  def invalidate(paths) do
    Logger.debug("CDN invalidation (no-op)", paths: paths)
    :ok
  end
end

# Configuration (implicite par défaut)
# config :portfolio, :cdn_module, Portfolio.CDN.NoOp
```

Avantages :
- Simplicité maximale : Aucune configuration CDN
- Coût nul : Pas de frais additionnels
- Contrôle total : Serveur gère directement les fichiers
- Pas de propagation cache : Changements instantanés

Inconvénients :
- Latence élevée : Visiteurs loin d'Allemagne (300-500ms RTT)
- Consommation bande passante serveur : Chaque requête consomme quota 20 To/mois
- Pas de cache edge : Serveur sert chaque image à chaque visite
- Scalabilité limitée : Serveur devient bottleneck si trafic élevé
- Pas de protection DDoS : Serveur directement exposé

Effort estimé : Aucun (déjà implémenté)

Risques :
- Performance dégradée hors Europe [Probabilité: Très élevée, Impact: Moyen]
- Dépassement bande passante 20 To/mois si viral [Probabilité: Faible, Impact: Élevé]

### Option 2: Cloudflare CDN (Proxy Orange)

Description:

Activer le proxy Cloudflare (icône orange) pour router tout le trafic via les data centers Cloudflare mondiaux. Cloudflare met en cache automatiquement les ressources statiques sur ses edge locations (200+ villes).

Architecture :

```
User (Paris)           User (Tokyo)
    ↓                       ↓
Cloudflare Edge       Cloudflare Edge
(Paris, FR)           (Tokyo, JP)
    ↓                       ↓
    └────────┬──────────────┘
             ↓
      Cloudflare Core
      (Cache Miss)
             ↓
       Hetzner VPS
      (Nuremberg, DE)
             ↓
    /priv/static/uploads
```

Implémentation :

```elixir
# lib/portfolio/cdn/cloudflare.ex
defmodule Portfolio.CDN.Cloudflare do
  @behaviour Portfolio.CDN
  
  require Logger
  
  @cloudflare_api_url "https://api.cloudflare.com/client/v4"
  
  @impl true
  def invalidate(paths) do
    zone_id = Application.get_env(:portfolio, :cloudflare_zone_id)
    api_token = Application.get_env(:portfolio, :cloudflare_api_token)
    
    # Purge cache pour chemins spécifiques
    body = %{files: build_full_urls(paths)}
    headers = [
      {"Authorization", "Bearer #{api_token}"},
      {"Content-Type", "application/json"}
    ]
    
    url = "#{@cloudflare_api_url}/zones/#{zone_id}/purge_cache"
    
    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200}} ->
        Logger.info("Cloudflare cache purged", paths: paths)
        :ok
        
      {:ok, %{status: status, body: body}} ->
        Logger.error("Cloudflare purge failed", status: status, body: body)
        {:error, {:api_error, status}}
        
      {:error, reason} ->
        Logger.error("Cloudflare API request failed", reason: inspect(reason))
        {:error, reason}
    end
  end
  
  defp build_full_urls(paths) do
    base_url = Application.get_env(:portfolio, :cdn_base_url, "https://photo.thibaultsan.com")
    Enum.map(paths, &"#{base_url}#{&1}")
  end
end

# config/prod.exs
config :portfolio,
  cdn_module: Portfolio.CDN.Cloudflare,
  cloudflare_zone_id: System.get_env("CLOUDFLARE_ZONE_ID"),
  cloudflare_api_token: System.get_env("CLOUDFLARE_API_TOKEN"),
  cdn_base_url: "https://photo.thibaultsan.com"
```

Configuration Cloudflare :

1. DNS Settings :
   - Activer proxy (orange icon) pour `photo.thibaultsan.com`
   - SSL/TLS : Full (strict)

2. Caching Rules :
   - Browser TTL : 4 heures
   - Edge TTL : 7 jours
   - Cache Everything : Page Rules pour `/uploads/*`

3. Page Rules :
   ```
   URL: photo.thibaultsan.com/uploads/*
   Settings:
     - Cache Level: Cache Everything
     - Edge Cache TTL: 7 days
     - Browser Cache TTL: 4 hours
   ```

Avantages :
- Latence réduite : Edge caching dans 200+ villes (50-100ms RTT partout)
- Économie bande passante : 95%+ requêtes servies depuis edge (cache hit)
- Coût nul : Plan Cloudflare Free inclut CDN
- Protection DDoS : Incluse gratuite
- SSL automatique : Certificat Cloudflare
- Cache intelligent : Cloudflare optimise cache selon type fichier

Inconvénients :
- SSL complexifié : Certificat Cloudflare-Serveur requis (Full strict)
- Cache invalidation nécessaire : Appel API Cloudflare lors publication
- Limite purge cache : 30 requêtes/jour plan Free (largement suffisant)
- Propagation cache : 2-5 minutes pour invalidation mondiale
- Dépendance Cloudflare : Si Cloudflare down, site inaccessible

Effort estimé : Moyen (1 jour implémentation + tests)

Risques :
- Propagation cache lente [Probabilité: Moyenne, Impact: Faible]
- Limite purge dépassée si très actif [Probabilité: Très faible, Impact: Faible]

### Option 3: Cloudflare R2 Storage + CDN

Description:

Migrer le stockage photos de local vers Cloudflare R2 (S3-compatible) et servir via CDN Cloudflare. R2 offre stockage objet sans frais d'egress (sortie données gratuite).

Architecture :

```
Upload Photo            Serve Photo
    ↓                       ↓
Phoenix App           User Request
    ↓                       ↓
Store R2            Cloudflare CDN
    ↓                  (Cache Edge)
Cloudflare R2             ↓
(Object Storage)    Cloudflare R2
                      (Origin)
```

Implémentation :

```elixir
# lib/portfolio/photography/storage/r2_storage.ex
defmodule Portfolio.Photography.Storage.R2Storage do
  @behaviour Portfolio.Photography.Storage.PhotoStorage
  
  alias ExAws.S3
  
  @bucket "portfolio-photos"
  @cdn_url "https://photos-cdn.thibaultsan.com"
  
  @impl true
  def store_photo(upload, opts) do
    photo_id = generate_photo_id()
    key = "photos/#{photo_id}/original.jpg"
    
    # Upload vers R2
    upload.path
    |> S3.Upload.stream_file()
    |> S3.upload(@bucket, key)
    |> ExAws.request()
    |> case do
      {:ok, _} ->
        metadata = build_metadata(photo_id, upload, key)
        {:ok, metadata}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @impl true
  def get_photo_url(photo_id, variant) do
    # URL CDN Cloudflare
    path = "photos/#{photo_id}/#{variant}.webp"
    {:ok, "#{@cdn_url}/#{path}"}
  end
end

# Configuration
config :ex_aws,
  access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
  region: "auto"

config :ex_aws, :s3,
  scheme: "https://",
  host: "<account-id>.r2.cloudflarestorage.com",
  region: "auto"
```

Configuration Cloudflare R2 :

1. Créer bucket `portfolio-photos`
2. Créer custom domain `photos-cdn.thibaultsan.com`
3. CDN automatique (inclus gratuit)

Tarification R2 :
- Stockage : $0.015/Go/mois
- Egress (sortie) : $0 (gratuit)
- Opérations Class A (write) : $4.50/million
- Opérations Class B (read) : $0.36/million

Estimation coût mensuel :
- Stockage : 50 Go × $0.015 = $0.75/mois
- Uploads : 100 photos/mois × 5 variants = 500 writes = $0.002/mois
- Reads : Négligeable (CDN cache)
- Total : ~$1/mois

Avantages :
- Coût très faible : $1-2/mois pour 50-100 Go
- Egress gratuit : Pas de frais bande passante (vs AWS S3)
- CDN inclus : Cloudflare CDN automatique
- Scalabilité infinie : Stockage objet cloud
- Décorrélation serveur : Libère VPS du stockage photos
- Backup implicite : Redondance R2 automatique

Inconvénients :
- Migration complexe : Déplacer photos existantes local → R2
- Dépendance cloud : Vendor lock-in Cloudflare
- Coût mensuel : $1-2/mois (vs $0 local)
- Latence upload : Upload vers R2 plus lent que local
- Complexité accrue : Gestion credentials R2, SDK ExAws

Effort estimé : Élevé (3-5 jours migration + tests)

Risques :
- Migration données difficile [Probabilité: Moyenne, Impact: Moyen]
- Coûts imprévus si usage élevé [Probabilité: Faible, Impact: Faible]

### Option 4: AWS CloudFront + S3

Description:

Utiliser AWS S3 pour stockage et CloudFront comme CDN. Stack classique pour applications web.

Tarification AWS :
- S3 Stockage : $0.023/Go/mois
- S3 Egress : $0.09/Go (vers CloudFront gratuit)
- CloudFront Egress : $0.085/Go (premiers To)
- CloudFront Requêtes : $0.0075/10k requêtes

Estimation coût mensuel :
- Stockage S3 : 50 Go × $0.023 = $1.15/mois
- CloudFront Egress : 100 Go × $0.085 = $8.50/mois
- Total : ~$10/mois

Avantages :
- Écosystème AWS mature : Documentation excellente
- Intégration AWS : Lambda@Edge pour logique custom
- Performance : CloudFront réseau global

Inconvénients :
- Coût élevé : 10× plus cher que Cloudflare R2 ($10 vs $1/mois)
- Complexité AWS : IAM, buckets, distributions
- Facturation complexe : Multiples lignes (S3, CloudFront, requêtes)

Effort estimé : Élevé (3-5 jours)

Risques :
- Coûts excessifs [Probabilité: Élevée, Impact: Critique pour budget limité]

### Option 5: Fastly CDN

Description:

CDN premium utilisé par grandes entreprises (Shopify, GitHub, Stack Overflow).

Tarification Fastly :
- $50/mois minimum
- $0.12/Go egress

Avantages :
- Performance excellente : Cache instantané (Varnish)
- Purge instantané : Cache invalidation < 150ms
- Configuration avancée : VCL scripting

Inconvénients :
- Coût prohibitif : $50+/mois minimum
- Over-engineering : Features avancées inutiles pour portfolio

Effort estimé : Moyen

Risques :
- Budget insuffisant [Probabilité: Très élevée, Impact: Critique]

## Décision

L'option choisie est: Option 1 (court terme) → Option 2 (moyen terme)

### Stratégie en deux phases

Phase 1 (Actuelle) : Pas de CDN (NoOp)
- Conserver implémentation actuelle `Portfolio.CDN.NoOp`
- Aucun changement infrastructure
- Acceptable pour trafic faible initial

Phase 2 (Future) : Cloudflare CDN (Proxy Orange)
- Activer proxy Cloudflare quand nécessaire
- Implémenter `Portfolio.CDN.Cloudflare` pour purge cache
- Migration simple (activation DNS)

### Justification de la décision

Cette approche progressive permet :

1. Simplicité initiale : Éviter complexité prématurée
2. Coût nul : Pas de dépense inutile pendant phase lancement
3. Migration simple : Cloudflare déjà utilisé pour DNS (cf ADR-043)
4. Flexibilité : Activation CDN en 1 heure si besoin
5. Pragmatisme : Résoudre problème quand il se manifeste

Le déclencheur pour passer Phase 1 → Phase 2 :
- Latence > 500ms constatée par utilisateurs
- Trafic > 1000 visiteurs/jour
- Consommation bande passante > 10 To/mois

Migration R2 (Option 3) uniquement si :
- Stockage local VPS insuffisant (> 50 Go photos)
- Besoin backup cloud automatique
- Budget permet $1-2/mois additionnels

## Conséquences

### Positives

Phase 1 (NoOp) :
- Simplicité maximale : Aucune configuration CDN
- Coût nul : Pas de frais additionnels
- Contrôle total : Serveur gère directement fichiers
- Changements instantanés : Pas de propagation cache

Phase 2 (Cloudflare CDN) :
- Latence réduite : 50-100ms partout dans le monde
- Économie bande passante : 95%+ cache hit rate
- Coût nul : Plan Cloudflare Free
- Protection DDoS : Incluse gratuite

### Négatives

Phase 1 (NoOp) :
- Latence élevée hors Europe : 300-500ms RTT
- Consommation bande passante serveur : Chaque requête consomme quota
- Pas de protection DDoS : Serveur directement exposé

Phase 2 (Cloudflare CDN) :
- Cache invalidation requise : Appel API lors publication album
- Propagation cache : 2-5 minutes délai invalidation mondiale
- Complexité SSL : Configuration Full (strict) requise

### Neutres

- Flexibilité : Migration Phase 1 → Phase 2 réversible
- Coût migration : Effort 1 jour pour activer Cloudflare CDN

## Configuration Détaillée

### Phase 1: NoOp (Actuelle)

Configuration actuelle :

```elixir
# lib/portfolio/cdn/cdn.ex (déjà implémenté)
defmodule Portfolio.CDN do
  @callback invalidate(paths :: [String.t()]) :: :ok | {:error, term()}
end

# lib/portfolio/cdn/no_op.ex (déjà implémenté)
defmodule Portfolio.CDN.NoOp do
  @behaviour Portfolio.CDN
  require Logger
  
  @impl true
  def invalidate(paths) when is_list(paths) do
    Logger.debug("CDN invalidation (no-op)",
      paths: paths,
      message: "CDN not configured, skipping cache invalidation"
    )
    :ok
  end
end

# config/config.exs (implicite, pas besoin de configurer)
# config :portfolio, :cdn_module, Portfolio.CDN.NoOp
```

Utilisation actuelle :

```elixir
# lib/portfolio/photography/event_handlers/album_published_handler.ex
defp invalidate_cdn_cache(event) do
  cdn_module = Application.get_env(:portfolio, :cdn_module, Portfolio.CDN.NoOp)
  
  paths = [
    "/",
    "/albums",
    "/albums/#{event.slug}"
  ]
  
  cdn_module.invalidate(paths)
end
```

Comportement :
- Logs debug "CDN invalidation (no-op)"
- Retourne toujours `:ok`
- Aucun appel API externe

### Phase 2: Cloudflare CDN (Future)

Implémentation requise :

```elixir
# lib/portfolio/cdn/cloudflare.ex (à créer)
defmodule Portfolio.CDN.Cloudflare do
  @moduledoc """
  Cloudflare CDN cache invalidation implementation.
  
  Purges Cloudflare edge cache when albums are published or updated.
  
  ## Configuration
  
      # config/runtime.exs
      config :portfolio,
        cdn_module: Portfolio.CDN.Cloudflare,
        cloudflare_zone_id: System.get_env("CLOUDFLARE_ZONE_ID"),
        cloudflare_api_token: System.get_env("CLOUDFLARE_API_TOKEN"),
        cdn_base_url: "https://photo.thibaultsan.com"
  
  ## API Token
  
  Create a Cloudflare API Token with permissions:
  - Zone > Cache Purge > Purge
  - Zone > Zone > Read
  
  ## Rate Limits
  
  Free plan: 30 purge requests/day (sufficient for typical usage)
  """
  
  @behaviour Portfolio.CDN
  
  require Logger
  
  @cloudflare_api_url "https://api.cloudflare.com/client/v4"
  
  @impl true
  def invalidate(paths) when is_list(paths) do
    zone_id = Application.fetch_env!(:portfolio, :cloudflare_zone_id)
    api_token = Application.fetch_env!(:portfolio, :cloudflare_api_token)
    
    full_urls = build_full_urls(paths)
    
    body = %{files: full_urls}
    headers = [
      {"Authorization", "Bearer #{api_token}"},
      {"Content-Type", "application/json"}
    ]
    
    url = "#{@cloudflare_api_url}/zones/#{zone_id}/purge_cache"
    
    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: %{"success" => true}}} ->
        Logger.info("Cloudflare cache purged successfully",
          paths: paths,
          urls: full_urls
        )
        :ok
        
      {:ok, %{status: status, body: body}} ->
        Logger.error("Cloudflare purge failed",
          status: status,
          body: body,
          paths: paths
        )
        {:error, {:api_error, status, body}}
        
      {:error, reason} ->
        Logger.error("Cloudflare API request failed",
          reason: inspect(reason),
          paths: paths
        )
        {:error, reason}
    end
  end
  
  defp build_full_urls(paths) do
    base_url = Application.get_env(:portfolio, :cdn_base_url, "https://photo.thibaultsan.com")
    Enum.map(paths, fn path ->
      # Ensure path starts with /
      normalized_path = if String.starts_with?(path, "/"), do: path, else: "/#{path}"
      "#{base_url}#{normalized_path}"
    end)
  end
end
```

Configuration production :

```elixir
# config/runtime.exs
if config_env() == :prod do
  config :portfolio,
    cdn_module: Portfolio.CDN.Cloudflare,
    cloudflare_zone_id: System.get_env("CLOUDFLARE_ZONE_ID") || 
      raise("CLOUDFLARE_ZONE_ID not set"),
    cloudflare_api_token: System.get_env("CLOUDFLARE_API_TOKEN") || 
      raise("CLOUDFLARE_API_TOKEN not set"),
    cdn_base_url: "https://photo.thibaultsan.com"
end
```

Secrets Kamal :

```bash
# .kamal/secrets
CLOUDFLARE_ZONE_ID=<zone_id>
CLOUDFLARE_API_TOKEN=<api_token>
```

Configuration Cloudflare Dashboard :

1. DNS Settings :
   ```
   Type: A
   Name: photo
   Content: 157.180.70.8
   Proxy: Enabled (orange cloud)
   TTL: Auto
   ```

2. SSL/TLS Settings :
   ```
   Encryption Mode: Full (strict)
   Always Use HTTPS: On
   Minimum TLS Version: 1.2
   ```

3. Caching Configuration :
   ```
   Page Rules:
   
   URL: photo.thibaultsan.com/uploads/*
   Settings:
     - Cache Level: Cache Everything
     - Edge Cache TTL: 1 week
     - Browser Cache TTL: 4 hours
   ```

4. API Token :
   ```
   Token Name: Portfolio CDN Purge
   Permissions:
     - Zone > Cache Purge > Purge
     - Zone > Zone > Read
   Zone Resources:
     - Include > Specific zone > thibaultsan.com
   ```

### Cache Invalidation Strategy

Chemins invalidés lors publication album :

```elixir
defp invalidate_cdn_cache(event) do
  paths = [
    "/",                              # Homepage (liste albums)
    "/albums",                        # Page albums
    "/albums/#{event.slug}",          # Page album spécifique
    "/api/albums",                    # API albums (si existe)
    "/api/albums/#{event.slug}",      # API album spécifique
    "/uploads/albums/#{event.album_id}/*"  # Toutes images album (wildcard)
  ]
  
  cdn_module = Application.get_env(:portfolio, :cdn_module, Portfolio.CDN.NoOp)
  cdn_module.invalidate(paths)
end
```

Note : Wildcard purge (`*`) disponible uniquement sur plans Cloudflare payants. Plan Free nécessite URLs exactes.

Stratégie alternative plan Free :

```elixir
# Purge uniquement chemins clés (sans wildcard)
defp invalidate_cdn_cache(event) do
  paths = [
    "/",
    "/albums",
    "/albums/#{event.slug}"
  ]
  
  # Images individuelles invalidées naturellement après TTL (7 jours)
  # Acceptable car changements rares (1-2x/mois)
  
  cdn_module.invalidate(paths)
end
```

### Bug Fix: Cache Name

Bug identifié dans `album_published_handler.ex:124` :

```elixir
# INCORRECT (cache n'existe pas)
defp clear_albums_cache do
  case Cachex.clear(:albums_cache) do  # ← :albums_cache n'existe pas
    {:ok, _} -> :ok
    {:error, reason} -> :ok
  end
end

# CORRECT (cache correct + invalidation ciblée)
defp clear_albums_cache do
  # Invalidation ciblée au lieu de clear global
  Cachex.del(:portfolio_cache, {:published_albums_by_year, []})
  Cachex.del(:portfolio_cache, {:published_albums_by_year, [:photos]})
  :ok
end
```

Correction à appliquer : Utiliser `:portfolio_cache` avec invalidation ciblée (cf ADR-040).

## Plan d'action

### Phase 1: État Actuel (Priorité: AUCUNE, déjà fait)

Statut : Déjà implémenté et fonctionnel

Configuration actuelle :
- `Portfolio.CDN.NoOp` actif
- Aucune configuration requise
- Logs debug lors publication album

Action : Aucune (conserver état actuel)

### Phase 2: Implémentation Cloudflare CDN (Priorité: BASSE)

Déclencheur (au moins un critère) :
- Latence > 500ms rapportée par utilisateurs
- Trafic > 1000 visiteurs/jour
- Consommation bande passante > 10 To/mois
- Demande explicite amélioration performance

Tâches :
1. Créer API Token Cloudflare (permissions Cache Purge)
2. Récupérer Zone ID Cloudflare
3. Implémenter `Portfolio.CDN.Cloudflare`
4. Ajouter secrets Kamal (`CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_API_TOKEN`)
5. Configurer `config/runtime.exs`
6. Activer proxy Cloudflare (orange icon) pour `photo.thibaultsan.com`
7. Configurer Page Rules (Cache Everything pour `/uploads/*`)
8. Tester invalidation cache après publication album
9. Monitorer cache hit rate (Cloudflare Analytics)

Critères de succès :
- Cache hit rate > 90%
- Latence < 100ms partout dans le monde
- Invalidation cache fonctionne (< 5 minutes propagation)
- Logs Cloudflare API : Status 200

Estimation : 1 jour (implémentation + tests)

### Phase 3: Migration Cloudflare R2 (Priorité: TRÈS BASSE)

Déclencheur (tous les critères) :
- Stockage local VPS > 50 Go
- Budget permet $1-2/mois additionnels
- Besoin backup cloud automatique

Tâches :
1. Créer bucket Cloudflare R2 `portfolio-photos`
2. Configurer custom domain R2 `photos-cdn.thibaultsan.com`
3. Implémenter `Portfolio.Photography.Storage.R2Storage`
4. Migrer photos existantes local → R2 (script migration)
5. Configurer ExAws avec credentials R2
6. Tester upload/download/delete photos
7. Vérifier CDN fonctionne (R2 custom domain)
8. Monitorer coûts R2 (Dashboard Cloudflare)

Critères de succès :
- Toutes photos migrées R2
- Upload photos fonctionne
- CDN sert photos depuis R2
- Coût mensuel < $2/mois

Estimation : 3-5 jours (migration + tests)

### Phase 4: Monitoring Performance (Priorité: MOYENNE si Phase 2 activée)

Tâches :
1. Configurer Cloudflare Analytics
2. Monitorer cache hit rate (objectif > 90%)
3. Monitorer latence edge (objectif < 100ms)
4. Monitorer requests purge cache (limite 30/jour plan Free)
5. Alerting si cache hit rate < 80%

Critères de succès :
- Dashboard Analytics accessible
- Métriques collectées quotidiennement

Estimation : 0.5 jour

## Alternatives Futures

### Si Cache Hit Rate Faible (< 70%)

Causes possibles :
- TTL trop court (< 1 jour)
- Trop de query strings variables
- Headers Cache-Control incorrects

Solutions :
1. Augmenter Edge Cache TTL : 7 jours → 30 jours
2. Ignorer query strings : Page Rule "Cache Key" ignore all query strings
3. Vérifier headers Phoenix : `Plug.Static` configure `cache_control_for_vsn_requests`

### Si Dépassement Limite Purge (30/jour)

Cause : Publications très fréquentes (> 30 albums/jour = improbable)

Solutions :
1. Purge globale au lieu de purge ciblée : `Purge Everything` (1 requête vs N)
2. Upgrade Cloudflare plan : Pro ($20/mois) = purge illimité
3. Réduire chemins purgés : Purge uniquement `/albums` (pas `/`)

### Si Stockage VPS Insuffisant

Cause : > 50-80 Go photos uploadées

Solutions :
1. Migration Cloudflare R2 (Option 3)
2. Compression images aggressive : Qualité WebP 75% → 60%
3. Suppression variantes large/original : Conserver uniquement small/medium
4. Upgrade VPS : Hetzner CPX31 (160 Go SSD, €16/mois)

## Références

- [Cloudflare CDN Documentation](https://developers.cloudflare.com/cache/)
- [Cloudflare API: Purge Cache](https://developers.cloudflare.com/api/operations/zone-purge)
- [Cloudflare R2 Documentation](https://developers.cloudflare.com/r2/)
- [Cloudflare Page Rules](https://developers.cloudflare.com/rules/page-rules/)
- Code source :
  - `lib/portfolio/cdn/cdn.ex` : Behaviour CDN
  - `lib/portfolio/cdn/no_op.ex` : Implémentation NoOp (actuelle)
  - `lib/portfolio/cdn/cloudflare.ex` : Implémentation Cloudflare (à créer)
  - `lib/portfolio/photography/event_handlers/album_published_handler.ex:95` : Invalidation CDN

## Notes

### Cloudflare Free Plan Limites

Limites plan gratuit :
- Purge cache : 30 requêtes/jour
- Wildcard purge : Non disponible (Pro+ uniquement)
- Edge Cache TTL : Max 30 jours
- Page Rules : 3 règles max

Suffisant pour portfolio car :
- Publications rares : 1-2 albums/mois = 1-2 purges/mois
- Wildcard inutile : Chemins connus à l'avance
- TTL 7 jours : Acceptable pour contenu statique
- 3 Page Rules : Suffisant (1 règle `/uploads/*`)

### Cache Hit Rate Attendu

Estimation cache hit rate :

Scénario | Cache Hit Rate
---|---
Lancement initial | 60-70% (cache froid)
Après 1 semaine | 85-90% (cache chaud)
Après publication | 80-85% (cache partiel invalidé)

Objectif : > 90% long terme

### Propagation Cache Invalidation

Temps propagation purge Cloudflare :

Type Purge | Propagation Temps
---|---
Single File | < 30 secondes (généralement < 10s)
Multiple Files (< 30) | < 2 minutes
Purge Everything | < 5 minutes

Acceptable car :
- Publications rares (pas critique)
- Utilisateurs voient ancienne version max 2-5 minutes
- Cache navigateur 4h (utilisateurs récurrents voient nouvelle version après)

### Comparaison CDN Providers

Provider | Coût | Performance | Ease of Use | Verdict
---|---|---|---|---
Cloudflare | $0/mois | Excellente | Facile | Choix optimal
AWS CloudFront | $10/mois | Excellente | Complexe | Trop cher
Fastly | $50/mois | Excellente | Moyenne | Trop cher
BunnyCDN | $1/mois | Bonne | Facile | Alternative valide

Note : BunnyCDN est une alternative à Cloudflare si limite 30 purges/jour problématique (purge illimité $1/mois).

### Migration NoOp → Cloudflare

Migration simple car architecture découplée :

Étape | Action | Downtime
---|---|---
1. Implémenter Cloudflare.ex | Code local | 0
2. Déployer code | `kamal deploy` | 0 (zero-downtime)
3. Activer proxy Cloudflare | DNS change | 0 (propagation 2-5 min)
4. Configurer Page Rules | Dashboard | 0
5. Tester purge cache | Publication test | 0

Rollback simple : Désactiver proxy Cloudflare (orange → gris) = retour NoOp.

---

Date de création: 2025-11-11  
Dernière révision: 2025-11-11
