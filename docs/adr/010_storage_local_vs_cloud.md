# ADR-010: Choix du Stockage Local vs Cloud

Statut: Accepté
Date: 2025-09

## Contexte

Le portfolio photographique nécessite un système de stockage pour les images uploadées et leurs variantes générées (thumbnail, small, medium, large). Le choix du backend de stockage impacte directement les coûts, la performance, la complexité opérationnelle et la souveraineté des données.

### Besoins Fonctionnels

**Stockage images** :
- Photos originales : JPEG, PNG (1-2 Mo par fichier)
- Variantes générées : 3 WebP (400px, 768px, 1280px) + 1 AVIF (1920px original compressé)
- Métadonnées : EXIF, dimensions, hash (stockées en DB PostgreSQL, pas dans fichiers)

**Opérations** :
- **Upload** : Stockage original + génération variantes asynchrone (Oban)
- **Read** : Serving photos via URLs publiques (galerie, timeline)
- **Delete** : Suppression photo + toutes variantes
- **Deduplication** : Même photo uploadée 2 fois = même stockage (hash-based)

### Volumétrie et Projections

**Actuel (Développement)** :
- 27 MB stockés
- Quelques albums de test

**Projections** :
```
Photos/an : 25 albums × 12 photos = 300 photos
Taille moyenne par photo :
  - Original : 1.5 Mo (JPEG/PNG non compressé)
  - 3 WebP légères : 200 KB + 300 KB + 400 KB = 900 KB
  - 1 AVIF qualité : 800 KB
  - Total : 1.5 Mo + 0.9 Mo + 0.8 Mo = 3.2 Mo/photo

Année 1 : 300 photos × 3.2 Mo = 960 Mo (~1 Go)
Année 5 : 5 Go
Année 10 : 10 Go

Cas croissance (activité pro) :
Année 1 : 50 albums × 30 photos × 3.2 Mo = 4.8 Go (~5 Go)
Année 5 : 24 Go
Année 10 : 48 Go
```

**Trafic attendu** :
- **Actuel** : 100-1000 visites/mois
- **Visiteurs** : 80% France, 8% Belgique, 7% Suisse, 2% Allemagne, 3% autre
- **Géographie** : Majoritairement Europe Ouest
- **Pics** : Max 1000 visiteurs simultanés improbable

### Contraintes

**1. Coût (Prioritaire)** :
- Projet non rémunérateur, budget minimal
- Ordre de priorité : **coût > simplicité > contrôle > souveraineté**
- Trade-off acceptable : €1/mois supplémentaire si gain significatif tranquillité

**2. Souveraineté des données** :
- Préférence UE (France idéal) ou Suisse
- RGPD compliance critique (photos personnelles/clients futurs)
- Éviter US providers (CLOUD Act, Patriot Act)

**3. Simplicité opérationnelle** :
- Déploiement = point faible identifié
- Préférence solutions simples, peu de configuration
- Éviter over-engineering

**4. Performance** :
- Latence acceptable (visiteurs Europe Ouest majoritairement)
- Bande passante Hetzner VPS : 20 TB/mois (largement suffisant)

### Infrastructure Actuelle

**VPS Hetzner CX23** :
- 2 vCPU Intel/AMD
- 4 GB RAM
- 40 GB SSD storage
- 20 TB bandwidth/mois
- €2.99/mois
- Localisation : Allemagne (RGPD compliant)

**Monitoring stockage** :
- Limite déclencheur migration : **30 GB** (75% capacité VPS)
- Alerte préventive : **20 GB** (50% capacité)
- Dashboard admin : Affichage usage stockage temps réel

### Architecture Ports & Adapters

Le système utilise le pattern **Ports & Adapters** (Hexagonal Architecture) pour abstraire le stockage :

```
┌─────────────────────────────────────────────────────────┐
│                   Domain Layer                          │
│                                                         │
│   Photography Context                                   │
│   ├── Album (Aggregate)                                 │
│   ├── Photo (Aggregate)                                 │
│   └── Services (PhotoUploadService, etc.)               │
│                                                         │
└──────────────────┬──────────────────────────────────────┘
                   │
                   │ Uses
                   ▼
┌─────────────────────────────────────────────────────────┐
│                   Port (Interface)                      │
│                                                         │
│   @behaviour PhotoStorage                               │
│   ├── store_photo(upload, opts)                        │
│   ├── delete_photo(photo_id)                           │
│   ├── get_photo_url(photo_id, variant)                 │
│   ├── generate_variants(photo_id)                      │
│   └── get_storage_usage()                              │
│                                                         │
└──────────────────┬──────────────────────────────────────┘
                   │
                   │ Implemented by
                   ▼
┌─────────────────────────────────────────────────────────┐
│              Adapters (Infrastructure)                  │
│                                                         │
│   ┌──────────────────┐  ┌──────────────────┐          │
│   │  LocalStorage    │  │ CloudflareR2     │  (futur) │
│   │  (Actuel)        │  │ Storage          │          │
│   └──────────────────┘  └──────────────────┘          │
│                                                         │
│   ┌──────────────────┐  ┌──────────────────┐          │
│   │  HetznerStorage  │  │ MockStorage      │          │
│   │  Box (futur)     │  │ (Tests)          │          │
│   └──────────────────┘  └──────────────────┘          │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Avantages architecture** :
- **Migration transparente** : Changer adapter sans toucher domaine
- **Testabilité** : MockStorage pour tests unitaires sans I/O
- **Dual-write** : Écrire simultanément local + cloud pendant migration
- **Flexibilité** : Adapter par environnement (dev = local, prod = cloud)

**Configuration runtime** :
```elixir
# config/config.exs
config :portfolio, :photo_storage_adapter,
  Portfolio.Photography.Storage.LocalStorage

# Migration future (changement config uniquement)
config :portfolio, :photo_storage_adapter,
  Portfolio.Photography.Storage.HetznerStorageBox

# Code métier inchangé
adapter = Application.get_env(:portfolio, :photo_storage_adapter)
{:ok, metadata} = adapter.store_photo(upload)
```

## Options Considérées

### Option 1: LocalStorage (Filesystem VPS)

**Description:**
Stockage photos directement sur le filesystem du VPS Hetzner dans `priv/static/uploads/`.

**Architecture hash-based** :
```
priv/static/uploads/photos/
  a3f2b8c4f1e9d2a7/           # Hash SHA256 (16 premiers caractères)
    original.jpg              # Extension préservée
    thumbnail.webp
    small.webp
    medium.webp
    large.webp
  f1e9d2a7c8b3e4f5/
    original.png
    thumbnail.webp
    ...
```

**Content-Addressable Storage** :
- Hash SHA256 du fichier = identifiant unique
- **Déduplication automatique** : Même photo uploadée 2x = même hash = même stockage
- **Intégrité** : Vérification hash après stockage garantit intégrité
- **Short URLs futur** : Hash utilisable pour URLs courtes (`/p/a3f2b8c4`)

**Choix 16 caractères (64 bits)** :
- SHA256 = 256 bits = 64 caractères hexa
- 16 caractères = 64 bits = 18.4 quintillions combinaisons
- Probabilité collision :
  - 10k photos : < 0.000001%
  - 100k photos : < 0.00001%
  - 1M photos : < 0.01%
- Choix conservateur vs 8 caractères initial (32 bits, collision 1% à 100k photos)

**Serving photos** :
```elixir
# Phoenix static plug
plug Plug.Static,
  at: "/uploads",
  from: {:portfolio, "priv/static/uploads"},
  cache_control_for_etags: "public, max-age=31536000, immutable"
```

**Cache-Control** :
- Photos immutables (hash-based) : `max-age=31536000` (1 an)
- Cloudflare CDN (proxy orange activé) : Cache automatique global
- Pas besoin invalidation manuelle (URLs changent si photo change)

**Avantages:**
- **Coût minimal** : Inclus dans €2.99/mois VPS (pas de coût additionnel)
- **Simplicité maximale** : Pas de service externe, pas de credentials, pas d'API
- **Latence locale** : Accès disque < 1ms, pas de latence réseau
- **Contrôle total** : Fichiers accessibles directement, debug facile
- **Déploiement trivial** : `priv/static/uploads/` déployé avec app
- **Déduplication gratuite** : Hash-based storage automatique
- **Intégrité garantie** : Vérification hash après stockage

**Inconvénients:**
- **Stockage limité** : 40 GB VPS partagé (app, DB, logs, photos)
- **Single point of failure** : VPS crash = photos inaccessibles (mitigation : backups)
- **Pas de CDN global natif** : Latence géographique hors Europe (mitigation : Cloudflare CDN gratuit)
- **Scaling limité** : Stockage fini, migration nécessaire si > 30 GB
- **Backup manuel** : Scripts custom nécessaires (vs backup automatique cloud)

**Effort estimé:** Très faible (implémentation actuelle)

**Risques:**
- VPS disque plein bloque application [Probabilité: Faible, Impact: Élevé]
  - Mitigation : Monitoring stockage, alerte 20 GB, limite 30 GB
- VPS crash perte photos [Probabilité: Très faible, Impact: Critique]
  - Mitigation : Backups quotidiens Hetzner Storage Box

---

### Option 2: Cloudflare R2

**Description:**
Object storage S3-compatible de Cloudflare, optimisé pour CDN avec zéro frais egress.

**Tarification** :
```
Storage : $0.015/GB/mois
Class A operations (writes) : $4.50/million
Class B operations (reads) : $0.36/million
Egress : $0 (gratuit, principal avantage vs S3)
```

**Calcul coûts 5 ans** :
```
Stockage : 4 GB × $0.015 = $0.06/mois = $0.72/an = $3.60/5ans
Uploads : 1500 photos × $0.0000045 = $0.007/5ans
Reads : 100k lectures/an × $0.00000036 = $0.036/an = $0.18/5ans
Total 5 ans : ~$4
```

**Avantages:**
- **Coût egress zéro** : Bande passante gratuite (vs AWS S3 $0.09/GB)
- **CDN global intégré** : Edge caching automatique mondial
- **Évolutivité illimitée** : Pas de limite stockage (vs 40 GB VPS)
- **Disponibilité haute** : SLA 99.9%, redondance multi-datacenter
- **S3-compatible** : API standard, ExAws library Elixir mature
- **Intégration Cloudflare** : DNS déjà géré, configuration unifiée
- **Backup automatique** : Versioning, lifecycle policies possibles

**Inconvénients:**
- **Coût > 0** : ~$1/an (vs gratuit LocalStorage), faible mais non nul
- **Complexité accrue** : Credentials, bucket config, ExAws dependency
- **Latence API** : Chaque opération = requête HTTPS (vs accès disque local)
- **Dépendance externe** : Service US (Cloudflare Inc.), data centers UE disponibles mais entreprise US
- **Souveraineté limitée** : CLOUD Act applicable (entreprise US)
- **Over-engineering** : Features (versioning, lifecycle) inutilisées pour volumétrie actuelle

**Effort estimé:** Moyen (ExAws setup, migration données, tests)

**Décision:** Rejeté pour volumétrie actuelle, viable si stockage > 30 GB.

---

### Option 3: Hetzner Storage Box

**Description:**
Stockage réseau Hetzner via Samba/SFTP/WebDAV, backup-oriented mais utilisable pour assets.

**Tarification** :
```
100 GB : €3.26/mois = €39/an
1 TB : €6.53/mois = €78/an
```

**Calcul coûts 5 ans** :
```
100 GB (largement suffisant) : €39/an × 5 = €195/5ans
```

**Avantages:**
- **Souveraineté UE** : Hetzner Allemagne, RGPD strict, pas CLOUD Act
- **Déjà payé** : Storage Box 100 GB utilisé pour backups DB (coût partagé)
- **Intégration Hetzner** : Même provider VPS, réseau interne rapide
- **Snapshots automatiques** : 7 daily snapshots inclus (disaster recovery)
- **Accès multiple** : SFTP, Samba, WebDAV, rsync
- **Simplicité** : Mount Samba = filesystem transparent

**Inconvénients:**
- **Coût élevé** : €195/5ans vs $4/5ans Cloudflare R2
- **Pas de CDN** : Serving direct depuis Storage Box (latence, bande passante)
- **Latence réseau** : Montage Samba = latence réseau (vs disque local)
- **Complexité mount** : FUSE Samba, gestion déconnexions, retry logic
- **Pas optimisé serving** : Backup-oriented, pas CDN-oriented

**Effort estimé:** Moyen à élevé (Samba mount, gestion déconnexions)

**Décision:** Rejeté pour serving photos (backup-oriented), mais excellent pour backups photos.

---

### Option 4: AWS S3

**Description:**
Object storage référence du marché, hautement évolutif et intégré.

**Tarification** :
```
Storage (Standard) : $0.023/GB/mois
PUT requests : $0.005/1000
GET requests : $0.0004/1000
Egress : $0.09/GB (hors free tier 100 GB/mois)
```

**Calcul coûts 5 ans** :
```
Stockage : 4 GB × $0.023 = $0.092/mois = $5.52/5ans
Egress : 1 GB/mois × 12 × 5 × $0.09 = $54/5ans (si > free tier)
Total : ~$60/5ans
```

**Avantages:**
- **Maturité maximale** : Service le plus mature, features exhaustives
- **Écosystème riche** : Intégrations, outils, documentation abondante
- **Performance** : Latence faible, throughput élevé
- **Disponibilité** : SLA 99.99%, durabilité 99.999999999%

**Inconvénients:**
- **Coût egress élevé** : $0.09/GB bande passante (vs $0 R2)
- **Complexité** : IAM, bucket policies, regions, classes de stockage
- **Souveraineté** : US company, CLOUD Act, data centers UE disponibles mais juridiction US
- **Over-engineering** : Features vastement sous-utilisées
- **Vendor lock-in** : Écosystème AWS tentant (Lambda, CloudFront, etc.)

**Effort estimé:** Élevé (AWS IAM, ExAws config, gestion credentials)

**Décision:** Rejeté en raison coût egress, complexité, souveraineté US.

---

### Option 5: DigitalOcean Spaces

**Description:**
Object storage S3-compatible avec CDN intégré (via DigitalOcean CDN).

**Tarification** :
```
$5/mois flat : 250 GB storage + 1 TB bandwidth
Au-delà : $0.02/GB storage, $0.01/GB bandwidth
```

**Calcul coûts 5 ans** :
```
$5/mois × 12 × 5 = $300/5ans
```

**Avantages:**
- **Flat rate prévisible** : $5/mois tout inclus (vs usage-based)
- **CDN intégré** : DigitalOcean CDN automatique
- **S3-compatible** : ExAws fonctionne directement
- **Simplicité** : Config plus simple qu'AWS

**Inconvénients:**
- **Coût fixe élevé** : $300/5ans vs $4/5ans R2 pour faible utilisation
- **Surpaiement** : 250 GB inclus mais 4 GB utilisés (rapport 1:62)
- **Souveraineté** : US company, data centers UE disponibles mais juridiction US

**Effort estimé:** Moyen (similaire R2)

**Décision:** Rejeté en raison coût fixe élevé pour faible volumétrie.

---

### Option 6: Backblaze B2

**Description:**
Object storage le moins cher du marché, S3-compatible.

**Tarification** :
```
Storage : $0.005/GB/mois
Downloads : $0.01/GB (gratuit si via Cloudflare CDN)
API calls : $0.004/10k
```

**Calcul coûts 5 ans** :
```
Stockage : 4 GB × $0.005 = $0.02/mois = $1.20/5ans
Bandwidth (via Cloudflare) : $0
Total : ~$1.20/5ans
```

**Avantages:**
- **Coût le plus bas** : Storage 3x moins cher qu'AWS, egress gratuit via Cloudflare
- **Cloudflare Bandwidth Alliance** : Egress gratuit si CDN Cloudflare
- **S3-compatible** : ExAws compatible

**Inconvénients:**
- **Fiabilité perçue** : Moins mature qu'AWS/Cloudflare
- **Souveraineté** : US company, data centers US uniquement
- **Latence** : Data centers US (latence accrue vs R2 edge)
- **Configuration complexe** : Backblaze + Cloudflare CDN setup

**Effort estimé:** Élevé (Backblaze + Cloudflare CDN integration)

**Décision:** Rejeté en raison souveraineté US, latence, complexité config.

---

## Décision

L'option choisie est: **Option 1 - LocalStorage (Filesystem VPS)**

### Justification

La décision est basée sur les critères suivants :

**1. Coût (Prioritaire)**

LocalStorage = **€0 additionnel** (inclus dans €2.99/mois VPS)

Comparaison 5 ans :
```
LocalStorage : €0 additionnel
Cloudflare R2 : $4 (~€4)
Hetzner Storage Box : €195
Backblaze B2 : $1.20 (~€1.20)
DigitalOcean Spaces : $300 (~€285)
AWS S3 : $60 (~€57)
```

Pour volumétrie actuelle (< 5 GB sur 5 ans), **coût additionnel injustifié**.

**2. Simplicité Opérationnelle (Très important)**

LocalStorage = **configuration minimale** :
- Pas de credentials externes
- Pas d'API à intégrer
- Pas de dependency ExAws
- Debug trivial (fichiers accessibles directement)

Déploiement = point faible identifié → Simplicité maximale prioritaire.

**3. Volumétrie Actuelle et Projections (Important)**

Volumétrie actuelle : **27 MB**
Projections 5 ans : **5 GB** (conservateur), **24 GB** (croissance pro)

Stockage VPS : **40 GB** total, limite photos **30 GB**

**Marge confortable** : 30 GB limite vs 5-24 GB projeté = facteur 1.25x à 6x

Migration déclenchée si stockage > 30 GB (monitoring dashboard admin).

**4. Performance et Latence (Souhaitable)**

**Latence actuelle** :
- Accès disque local : < 1ms
- Cloudflare CDN activé (proxy orange) : Cache global automatique
- Visiteurs 95% Europe Ouest : Latence CDN Paris/Amsterdam/Frankfurt < 50ms

**Bande passante** :
- VPS Hetzner : 20 TB/mois inclus
- Trafic projeté : 1 GB/mois (100 visites × 10 photos × 1 MB)
- Marge : 20,000x (largement suffisant)

Performance actuelle = **largement acceptable** sans cloud.

**5. Souveraineté des Données (Souhaitable)**

LocalStorage + Hetzner VPS :
- **Hetzner Allemagne** : RGPD strict, UE, pas CLOUD Act
- **Souveraineté maximale** : Fichiers sous contrôle total
- **RGPD compliance** : Critical pour photos personnelles/clients

Cloud US (AWS, Cloudflare, Backblaze) = juridiction US, CLOUD Act applicable.

**6. Architecture Ports & Adapters (Fondamental)**

Behaviour `PhotoStorage` permet **migration future sans friction** :

```elixir
# Aujourd'hui
config :portfolio, :photo_storage_adapter,
  Portfolio.Photography.Storage.LocalStorage

# Demain (si stockage > 30 GB)
config :portfolio, :photo_storage_adapter,
  Portfolio.Photography.Storage.HetznerStorageBox

# Code métier inchangé (zero refactoring)
adapter = Application.get_env(:portfolio, :photo_storage_adapter)
{:ok, metadata} = adapter.store_photo(upload)
```

**Stratégie migration progressive** (dual-write) :
```elixir
# Phase migration
def store_photo(upload, opts) do
  # Écriture locale (backward compatibility)
  {:ok, local_metadata} = LocalStorage.store_photo(upload, opts)

  # Écriture cloud (nouveau stockage)
  Task.async(fn -> CloudStorage.store_photo(upload, opts) end)

  {:ok, local_metadata}
end
```

Abstraction garantit **flexibilité long terme** sans dette technique.

### Implémentation

**Structure stockage hash-based** :

```
priv/static/uploads/photos/
  a3f2b8c4f1e9d2a7/           # SHA256 hash (16 caractères)
    original.jpg
    thumbnail.webp            # 320px width
    small.webp                # 800px width
    medium.webp               # 1200px width
    large.webp                # 1920px width
```

**Algorithme stockage** :
```elixir
def store_photo(upload, _opts) do
  # 1. Hash SHA256 du fichier
  {:ok, hash} = compute_hash(upload.path)

  # 2. Photo ID = 16 premiers caractères hash
  photo_id = String.slice(hash, 0, 16)

  # 3. Destination path
  dest_path = "priv/static/uploads/photos/#{photo_id}/original.#{ext}"

  # 4. Copie fichier
  :ok = copy_file(upload.path, dest_path)

  # 5. Vérification intégrité (hash post-copie)
  :ok = verify_file_integrity(dest_path, hash)

  # 6. Métadonnées
  {:ok, %PhotoMetadata{
    photo_id: photo_id,
    hash: hash,
    storage_path: "/uploads/photos/#{photo_id}/original.#{ext}",
    # ...
  }}
end
```

**Déduplication automatique** :
- Même photo uploadée 2x → Même hash → Même `photo_id`
- Fichier déjà existant : Skip copy, return metadata existante
- Économie stockage, pas de duplicatas

**Cache-Control headers** :
```elixir
# config/prod.exs
plug Plug.Static,
  at: "/uploads",
  from: {:portfolio, "priv/static/uploads"},
  cache_control_for_etags: "public, max-age=31536000, immutable"
```

Photos immutables (hash-based) = cache agressif (1 an) safe.

**Cloudflare CDN** :
- Proxy orange activé (gratuit)
- Cache automatique assets statiques
- Edge locations : Paris, Amsterdam, Frankfurt (Europe Ouest)
- Pas besoin invalidation manuelle (URLs immutables)

**Monitoring stockage** :

```elixir
# Dashboard Admin
def mount(_params, _session, socket) do
  storage_usage = PhotoStorage.get_storage_usage()  # Bytes
  storage_limit = 30 * 1024 * 1024 * 1024            # 30 GB
  storage_percent = storage_usage / storage_limit * 100

  socket = assign(socket,
    storage_usage: format_bytes(storage_usage),
    storage_percent: Float.round(storage_percent, 1),
    storage_alert: storage_percent > 66  # Alerte à 66%
  )

  {:ok, socket}
end
```

**Alertes** :
- 66% (20 GB) : Warning "Envisager migration cloud"
- 75% (30 GB) : Critical "Migration obligatoire"

**Backup photos** :

**Stratégie 3-2-1** :
- **3 copies** : Production VPS + Backup local + Backup remote
- **2 médias** : SSD VPS + HDD Storage Box
- **1 offsite** : Hetzner Storage Box datacenter différent

**Script backup** :
```bash
#!/bin/bash
# /usr/local/bin/backup_portfolio.sh

DATE=$(date +\%Y\%m\%d)

# Backup DB
pg_dump -Fc portfolio_prod > /backups/db_$DATE.dump

# Backup Photos (tar.gz compression ~70% reduction)
tar -czf /backups/photos_$DATE.tar.gz \
  /var/www/portfolio/priv/static/uploads

# Sync to Hetzner Storage Box
rclone sync /backups hetzner:portfolio-backups

# Rotation
find /backups -name "db_*.dump" -mtime +7 -delete        # 7 daily
find /backups -name "photos_*.tar.gz" -mtime +7 -delete  # 7 daily

# Weekly backups (dimanche)
if [ $(date +\%u) -eq 7 ]; then
  cp /backups/db_$DATE.dump /backups/weekly/
  cp /backups/photos_$DATE.tar.gz /backups/weekly/
  find /backups/weekly -mtime +28 -delete  # 4 weekly
fi
```

**Cron** :
```cron
0 3 * * * /usr/local/bin/backup_portfolio.sh
```

**Coût** : €3.26/mois Storage Box 100 GB (déjà payé pour backups DB, espace partagé).

**Test restore mensuel** :
```bash
# Cron 1er du mois
0 4 1 * * /usr/local/bin/test_restore.sh

# test_restore.sh
# 1. Download latest backup
# 2. Restore to test DB
# 3. Extract photos to temp dir
# 4. Verify integrity (sample hashes)
# 5. Cleanup
# 6. Report success/failure
```

### Trade-offs Acceptés

**Stockage limité (40 GB VPS)** :
- Migration nécessaire si > 30 GB
- Acceptable : Volumétrie projetée 4-20 GB sur 5 ans, marge confortable
- Monitoring dashboard : Alertes préventives 20 GB, critiques 30 GB

**Single point of failure (VPS)** :
- VPS crash = photos inaccessibles temporairement
- Acceptable : Backups quotidiens Hetzner Storage Box, restore < 1h
- Disponibilité non-critique (portfolio personnel, pas e-commerce)

**Pas de CDN global natif** :
- Latence géographique hors Europe (Asie, Amérique)
- Acceptable : 95% visiteurs Europe Ouest, Cloudflare CDN activé (edge caching)
- Trade-off latence < 100ms (acceptable pour photos portfolio)

**Backup manuel** :
- Scripts custom vs backup automatique cloud (S3 versioning)
- Acceptable : Scripts robustes, test restore mensuel, coût €0 vs €X/mois cloud

**Évolutivité limitée** :
- Scaling vertical limité (max VPS Hetzner ~200 GB)
- Acceptable : Migration cloud prévue si volumétrie > 30 GB
- Architecture Ports & Adapters garantit migration sans friction

## Conséquences

### Positives

- **Coût optimal** : €0 additionnel, inclus dans VPS €2.99/mois
- **Simplicité maximale** : Pas de service externe, configuration minimale
- **Performance locale** : Latence disque < 1ms, Cloudflare CDN global gratuit
- **Contrôle total** : Fichiers accessibles directement, debug facile
- **Souveraineté UE** : Hetzner Allemagne, RGPD strict, pas CLOUD Act
- **Déduplication automatique** : Hash-based storage, économie stockage
- **Intégrité garantie** : Vérification hash post-stockage
- **Architecture flexible** : Ports & Adapters permet migration future sans refactoring
- **Testabilité** : MockStorage pour tests unitaires sans I/O

### Négatives

- **Stockage limité** : 30 GB maximum photos (75% VPS 40 GB)
  - Surveillance : Monitoring dashboard, alertes 20 GB (66%), 30 GB (75%)
  - Gestion : Migration cloud si dépassement, architecture prête
- **Single point of failure** : VPS crash = photos inaccessibles
  - Mitigation : Backups quotidiens Storage Box, restore < 1h
  - Acceptable : Disponibilité non-critique portfolio personnel
- **Backup manuel** : Scripts custom vs automatique cloud
  - Mitigation : Scripts robustes, cron quotidien, test restore mensuel
  - Risque : Oubli test restore (mitigation : alerte automatique si échec)
- **Scaling limité** : Croissance > 30 GB nécessite migration
  - Planification : Migration Hetzner Storage Box ou Cloudflare R2 selon volumétrie
  - Architecture : Ports & Adapters garantit transition douce

### Neutres

- **CDN global** : Cloudflare gratuit vs CDN natif cloud (R2, S3+CloudFront)
  - Trade-off : Performance Europe Ouest excellente, Asie/Amérique acceptable
- **Latence géographique** : VPS Allemagne, latence hors Europe
  - Acceptable : 95% visiteurs Europe Ouest, latence < 100ms
- **Cloudflare dépendance** : CDN gratuit mais vendor lock-in
  - Mitigation : Migration CDN facile (Fastly, CloudFlare alternatives)

## Plan d'Action

1. **Phase 1: Implémentation LocalStorage** ✅
   - Behaviour PhotoStorage défini
   - LocalStorage adapter implémenté
   - Hash-based storage (SHA256, 16 caractères)
   - Déduplication automatique
   - Vérification intégrité

2. **Phase 2: Serving & CDN** ✅
   - Plug.Static configuration
   - Cache-Control headers (1 an, immutable)
   - Cloudflare CDN activé (proxy orange)

3. **Phase 3: Backups Photos** (Urgent - Priorité 1)
   - Script backup quotidien (DB + Photos)
   - Sync Hetzner Storage Box
   - Rotation 7 daily + 4 weekly + 3 monthly
   - Test restore mensuel automatisé
   - Documentation procédure recovery

4. **Phase 4: Monitoring Stockage** (En cours)
   - Dashboard admin : Affichage usage temps réel
   - Alertes : 20 GB (warning), 30 GB (critical)
   - Logs monitoring : Croissance stockage mensuelle

5. **Phase 5: Optimisations** (Futur, si nécessaire)
   - Compression WebP aggressive (qualité 80 vs 85)
   - Cleanup photos orphelines (non référencées DB)
   - Analyse déduplication (photos identiques clients)

6. **Phase 6: Migration Cloud** (Si stockage > 30 GB)
   - Option A : Hetzner Storage Box (souveraineté UE, €3.26/mois déjà payé)
   - Option B : Cloudflare R2 (coût minimal $0.015/GB/mois, CDN intégré)
   - Dual-write LocalStorage + Cloud (migration progressive)
   - Sync existant local → cloud (rsync, rclone)
   - Switch config adapter
   - Cleanup local après validation

**Critères de succès:**
- ✅ LocalStorage fonctionnel (store, delete, get_url, variants)
- ✅ Hash-based storage (16 caractères SHA256)
- ✅ Cloudflare CDN activé
- 🔄 Backups quotidiens photos (urgent)
- 🔄 Monitoring stockage dashboard
- 🔄 Test restore mensuel automatisé
- ⏳ Migration cloud si > 30 GB

**Rollback plan:**

Si LocalStorage pose problème (peu probable) :
1. Identifier pain point : Stockage plein ? Performance ? Disponibilité ?
2. Solutions graduelles :
   - Stockage plein → Migration cloud immédiate (Hetzner Storage Box ou R2)
   - Performance → Analyse slow queries, cache optimization
   - Disponibilité → Redondance VPS (coût élevé, peu probable)
3. Migration cloud urgente :
   - Dual-write LocalStorage + Cloud (2-4 semaines transition)
   - Sync existant → cloud (rclone)
   - Switch adapter config
   - Validation tests
   - Cleanup local

## Références

- [Cloudflare R2 Pricing](https://www.cloudflare.com/products/r2/)
- [Hetzner Storage Box](https://www.hetzner.com/storage/storage-box)
- [AWS S3 Pricing](https://aws.amazon.com/s3/pricing/)
- [Backblaze B2 Cloudflare Bandwidth Alliance](https://www.backblaze.com/b2/solutions/content-delivery.html)
- [Phoenix Plug.Static Documentation](https://hexdocs.pm/plug/Plug.Static.html)

Documentation projet connexe :
- `docs/architecture/infrastructure_components.md` (Composants infrastructure)
- `docs/operations/backup_restore_procedures.md` (Guide backups PostgreSQL + Photos)
- `lib/portfolio/photography/storage/photo_storage.ex` (Behaviour PhotoStorage)
- `lib/portfolio/photography/storage/local_storage.ex` (Implémentation LocalStorage)

## Notes

### Incohérences Identifiées

**Hash 8 caractères initial (corrigé)** :
- Version initiale : 8 caractères (32 bits)
- Probabilité collision : 1% à 100k photos (inacceptable)
- Correction : **16 caractères** (64 bits)
- Probabilité collision : < 0.01% à 1M photos (acceptable)

**Migration recommandée** :
Aucune migration nécessaire si changement avant production. Si production existante avec 8 caractères :
```elixir
# Migration script
def migrate_short_hashes do
  photos = Repo.all(Photo)

  Enum.each(photos, fn photo ->
    # Recalculer hash complet
    full_hash = compute_hash(photo.original_path)
    new_photo_id = String.slice(full_hash, 0, 16)

    # Renommer directory
    old_dir = "priv/static/uploads/photos/#{photo.photo_id}"
    new_dir = "priv/static/uploads/photos/#{new_photo_id}"
    File.rename(old_dir, new_dir)

    # Update DB
    Repo.update(change(photo, photo_id: new_photo_id))
  end)
end
```

### Optimisations Futures

**Compression WebP agressive** :
Actuel : Qualité 85 (balance qualité/taille)
Futur : Qualité 80 si stockage critique (gain ~15% taille, perte qualité minime)

**Cleanup photos orphelines** :
Script mensuel : Détecter fichiers `priv/static/uploads/` non référencés en DB, proposer suppression.

**Lazy deletion** :
Au lieu de supprimer photos immédiatement, marquer `deleted_at`, cleanup après 30j (recovery possible si erreur).

### Lessons Learned

**Behaviour Pattern validé** :
Architecture Ports & Adapters excellente décision :
- Testabilité : MockStorage simplifie tests unitaires
- Flexibilité : Migration cloud future sans refactoring
- Clarté : Interface claire, implémentations multiples possibles

**Hash-based storage efficace** :
Déduplication automatique fonctionne bien en pratique :
- Client upload même photo 2x → Hash identique → Économie stockage
- Intégrité garantie : Vérification hash post-copie détecte corruptions

**Cloudflare CDN gratuit sous-estimé** :
Cloudflare proxy orange (gratuit) fournit CDN global sans coût additionnel :
- Cache automatique assets statiques
- Edge locations mondiale
- Performance Europe Ouest excellente (< 50ms latency)

**Backup photos critique** :
Photos = contenu irremplaçable, backup quotidien **non négociable** :
- Script backup DB + Photos unifié
- Test restore mensuel obligatoire (backup inutile si restore échoue)
- Coût €0 (Storage Box déjà payé)

---

**Participants à la décision:**
- Thibault San - Développeur Solo

**Révisé par:**
- Thibault San - 2025-11-10
