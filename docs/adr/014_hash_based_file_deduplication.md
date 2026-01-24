# ADR-014 : Déduplication de Fichiers par Hash

Statut: Partiellement implémenté
Date: 2025-05

## Contexte

Le portfolio photographique stocke des images haute résolution (12MP+) avec multiples variantes (3 WebP + 1 AVIF, voir ADR-010, ADR-011, ADR-012). La gestion du stockage pose plusieurs défis :

### Besoins fonctionnels

1. Détection duplicatas : Même photo uploadée plusieurs fois (erreur utilisateur, réutilisation entre albums)
2. Économie stockage : VPS 40GB limité, chaque photo = 4-5MB original + variantes
3. Intégrité fichiers : Vérification que fichier uploadé = fichier stocké (corruption détection)
4. Réutilisation cross-album : Photo "top 2025" existe déjà dans "voyage 2024"

### Contraintes techniques

1. VPS Hetzner 40GB SSD : Saturation prévisible à 8-10k photos (sans déduplication)
2. Upload multiple : 10-20 photos/événement, risque duplicatas élevé
3. Performance : Hash calculation ne doit pas ralentir upload (< 500ms par photo)
4. Filesystem : Linux (support symlinks, hardlinks)

### Problématique

Comment détecter et éliminer les duplicatas de fichiers pour économiser le stockage, tout en maintenant l'intégrité des données et permettant la réutilisation d'images entre albums ?

---

## Options Considérées

### Option 1 : Pas de déduplication

Chaque upload crée un nouveau fichier, même si identique à un existant.

**Description :**
Structure actuelle avec UUID ou filename comme identifiant unique.

```
/uploads/photos/
  550e8400-e29b-41d4-a716-446655440000/
    original.jpg
    thumbnail.webp
    ...
  7c9e6679-7425-40de-944b-e07fc1f90ae7/
    original.jpg  ← Même fichier que ci-dessus
    thumbnail.webp
    ...
```

**Avantages :**
- Simplicité maximale (pas de logique déduplication)
- Isolation totale entre photos (suppression = delete répertoire)
- Pas de risque référence cassée
- Debuggage trivial

**Inconvénients :**
- Gaspillage stockage : Duplicatas non détectés
- Saturation VPS rapide : 40GB / 5MB = 8k photos max
- Aucune détection erreur utilisateur (upload 2× même photo)
- Coût bande passante : Upload duplicatas inutile

**Effort estimé :** Aucun (état actuel partiel)

**Risques :**
- Saturation stockage [Probabilité: Élevée, Impact: Élevé]

**Rejeté** : Incompatible contrainte stockage 40GB.

### Option 2 : Déduplication par filename

Détection duplicatas basée sur nom de fichier original.

**Description :**
Vérifier si `original_filename` existe déjà avant upload.

```elixir
def store_photo(upload) do
  existing = Repo.get_by(Photo, original_filename: upload.client_name)
  
  if existing do
    {:error, :duplicate_filename}
  else
    copy_file_and_create_photo(upload)
  end
end
```

**Avantages :**
- Simple à implémenter (query DB)
- Détection immédiate (pas de hash à calculer)

**Inconvénients :**
- Faux positifs massifs : `IMG_1234.jpg` uploadé par 10 utilisateurs différents
- Pas de détection vraie duplication : Même image renommée = non détecté
- Blocage légitime : Photo différente, même nom
- Aucune économie stockage réelle

**Effort estimé :** Faible (1 jour)

**Risques :**
- Faux positifs [Probabilité: Certaine, Impact: Élevé]
- Inefficace [Probabilité: Certaine, Impact: Élevé]

**Rejeté** : Ne détecte pas les vraies duplications de contenu.

### Option 3 : Hash SHA-256 avec déduplication (content-addressable storage) ⭐

Stockage basé sur hash du contenu, fichiers identiques = même hash = même stockage.

**Description :**
Calculer SHA-256 du fichier, utiliser hash comme identifiant de stockage.

```elixir
def store_photo(upload) do
  hash = compute_sha256(upload.path) |> String.slice(0, 16)
  
  file_ref = Repo.get(FileRef, hash)
  
  if file_ref do
    # Déduplication : Fichier existe déjà
    Repo.update!(file_ref, ref_count: file_ref.ref_count + 1)
  else
    # Nouveau fichier
    copy_file(upload.path, "/uploads/files/#{hash}/original.jpg")
    Repo.insert!(%FileRef{hash: hash, ref_count: 1})
  end
  
  create_photo(%{hash: hash, file_path: "/uploads/files/#{hash}/original.jpg"})
end
```

Structure :
```
/uploads/files/
  a3f2b8c4e7d1f6a9/        ← Hash 16 caractères
    original.jpg           ← Fichier physique unique
    thumbnail.webp
    small.webp
    medium.webp
    large.webp
  b2c8f1e4d9a7c3f6/
    original.png
    thumbnail.webp
    ...

Table file_refs :
| hash             | file_path                        | ref_count | size     |
|------------------|----------------------------------|-----------|----------|
| a3f2b8c4e7d1f6a9 | /uploads/files/a3f2b8c4.../...   | 3         | 4523041  |
| b2c8f1e4d9a7c3f6 | /uploads/files/b2c8f1e4.../...   | 1         | 3891234  |

Table photos :
| id  | album_id | hash             | title      |
|-----|----------|------------------|------------|
| 001 | voyage   | a3f2b8c4e7d1f6a9 | Coucher... |
| 002 | top-2025 | a3f2b8c4e7d1f6a9 | Sunset     | ← Même fichier
| 003 | mariage  | a3f2b8c4e7d1f6a9 | Photo 1    | ← Même fichier
| 004 | voyage   | b2c8f1e4d9a7c3f6 | Paysage    |
```

**Avantages :**
- Déduplication vraie : Même contenu = 1 seul fichier physique
- Détection automatique : Hash identique = duplicata détecté
- Économie stockage : 5-10% économisé (estimation), critique pour VPS 40GB
- Intégrité garantie : Vérification hash après copie (corruption détection)
- Réutilisation cross-album : Photo dans "voyage" réutilisable dans "top 2025" sans re-upload
- Scalabilité : 8k photos → 12k photos avec même stockage (gain 50% si 10% duplicatas)

**Inconvénients :**
- Complexité implémentation : Reference counting, cascade delete
- Performance : Calcul SHA-256 (~200-300ms pour 12MP JPEG)
- Gestion suppression : Vérifier `ref_count` avant delete fichier
- Collision SHA-256 : Probabilité faible mais non nulle (16 chars = 64 bits)

**Effort estimé :** Moyen (1 semaine implémentation + tests)

**Risques :**
- Collision hash [Probabilité: Très faible, Impact: Moyen]
- Bug reference counting [Probabilité: Moyenne, Impact: Élevé]

### Option 4 : Hardlinks (filesystem-level deduplication)

Utilisation de hardlinks POSIX pour partager inodes.

**Description :**
Créer hardlinks vers fichier original au lieu de copier.

```bash
# Premier upload
/uploads/originals/a3f2b8c4.jpg  ← Fichier physique (inode 12345)

# Deuxième upload (même contenu)
/uploads/photos/001/original.jpg → hardlink inode 12345
/uploads/photos/002/original.jpg → hardlink inode 12345
```

**Avantages :**
- Déduplication automatique filesystem
- Performance : Pas de copie fichier (ln syscall rapide)
- Transparent pour application

**Inconvénients :**
- Suppression complexe : Supprimer photo ≠ supprimer inode (besoin ref_count anyway)
- Pas de contrôle applicatif : Filesystem gère, pas l'app
- Debugging difficile : Quel hardlink supprimer ?
- Portabilité limitée : Hardlinks = même filesystem uniquement
- Risque modification : Modifier 1 hardlink = modifier tous (si ouverture en write)

**Effort estimé :** Moyen (1 semaine)

**Risques :**
- Modification accidentelle [Probabilité: Faible, Impact: Élevé]
- Complexité suppression [Probabilité: Certaine, Impact: Moyen]

**Rejeté** : Complexité similaire à Option 3 mais moins de contrôle applicatif.

### Option 5 : Symlinks (symbolic links)

Utilisation de symlinks vers fichier original centralisé.

**Description :**
Créer symlinks pointant vers `/uploads/originals/{hash}.jpg`.

```bash
/uploads/originals/a3f2b8c4.jpg  ← Fichier physique

/uploads/photos/001/original.jpg → symlink ../../../originals/a3f2b8c4.jpg
/uploads/photos/002/original.jpg → symlink ../../../originals/a3f2b8c4.jpg
```

**Avantages :**
- Déduplication visible (ls -la montre symlinks)
- Suppression simple : Supprimer symlink ≠ supprimer fichier
- Portabilité meilleure que hardlinks

**Inconvénients :**
- Reference counting obligatoire : Comment savoir si originals/a3f2b8c4.jpg encore utilisé ?
- Broken symlinks : Supprimer original = symlinks cassés
- Performance : Indirection supplémentaire (résolution symlink)
- Complexité debuggage : Suivre chaîne symlinks

**Effort estimé :** Moyen (1 semaine)

**Risques :**
- Broken symlinks [Probabilité: Moyenne, Impact: Élevé]
- Besoin ref_count anyway [Probabilité: Certaine, Impact: Moyen]

**Rejeté** : Complexité identique à Option 3 (besoin ref_count) avec overhead symlinks.

---

## Décision

L'option choisie est : **Option 3 - Hash SHA-256 avec déduplication (content-addressable storage)**

Avec **implémentation partielle actuelle** et **complétion prévue Q1 2026**.

### Critères de décision

**Alignement avec l'architecture :**
- Content-addressable storage = pattern éprouvé (Git, Docker, IPFS)
- PostgreSQL pour reference counting (ACID transactions)
- DDD : `FileRef` = Value Object, `Photo` = Entity

**Impact sur la dette technique :**
- Implémentation partielle actuelle : Hash calculé mais **pas de déduplication**
- Dette : Reference counting non implémenté
- Plan : Complétion Q1 2026 (backlog)

**Maintenabilité :**
- Logique explicite en code (vs filesystem opaque hardlinks/symlinks)
- Tests simples (mocking FileRef repository)
- Debugging facilité (table `file_refs` visible)

**Performance :**
- Hash SHA-256 : ~200-300ms pour 12MP JPEG (acceptable)
- Déduplication : Gain upload (skip si hash existe)
- Stockage : Économie 5-10% (critique VPS 40GB)

**Sécurité :**
- Intégrité fichiers : Vérification hash après copie
- Pas de risque modification accidentelle (vs hardlinks)
- Isolation albums : Permissions gérées par application, pas filesystem

**Coût/Effort :**
- Implémentation : 1 semaine (migration + logic + tests)
- Maintenance : Faible (table `file_refs` standard)
- Gain stockage : ~400MB / 1000 photos (5-10% duplicatas)

**Réversibilité :**
- Migration retour Option 1 : Copier tous fichiers depuis `/uploads/files/{hash}/` vers `/uploads/photos/{uuid}/`
- Aucune perte données (hash conservé en DB)

### Décision finale

Adoption content-addressable storage avec hash SHA-256 (16 caractères) et reference counting pour les justifications suivantes :

1. **Économie stockage critique** : VPS 40GB, 5-10% duplicatas = 400MB économisés / 1000 photos

2. **Détection automatique duplicatas** : Même photo uploadée 2× détectée immédiatement

3. **Intégrité garantie** : Hash verification après copie = corruption détection

4. **Réutilisation cross-album** : Photo "top 2025" = référence photo "voyage 2024" sans re-upload

5. **Scalabilité** : 8k photos max → 12k photos max avec même stockage (gain 50%)

---

## État Actuel vs Cible

### État actuel (2025-05)

**Implémentation partielle :**

```elixir
# lib/portfolio/photography/storage/local_storage.ex

# ✅ Hash SHA-256 calculé
defp compute_hash(file_path) do
  hash =
    File.stream!(file_path, [], 2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
      :crypto.hash_update(acc, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)  # ❌ 8 caractères (à corriger → 16)

  {:ok, hash}
end

# ❌ Pas de déduplication : Copie systématique
def store_photo(upload, _opts) do
  with {:ok, hash} <- compute_hash(upload.path),
       photo_id <- String.slice(hash, 0, 8),
       {:ok, dest_path} <- build_destination_path(photo_id, upload),
       :ok <- ensure_directory_exists(dest_path),
       :ok <- copy_file(upload.path, dest_path) do  # ← Copie toujours
    # ...
  end
end
```

**Problèmes identifiés :**

1. **Hash trop court** : 8 caractères = 32 bits = collision 1% à 77k photos
2. **Pas de déduplication** : `copy_file` exécuté même si hash existe
3. **Pas de table `file_refs`** : Aucun reference counting
4. **Structure répertoires** : `/uploads/photos/{hash}/` (à migrer vers `/uploads/files/{hash}/`)

### Architecture cible (Q1 2026)

**Complétion implémentation :**

1. **Migration base données**

```elixir
# priv/repo/migrations/XXX_create_file_refs.exs
defmodule Portfolio.Repo.Migrations.CreateFileRefs do
  use Ecto.Migration

  def change do
    create table(:file_refs, primary_key: false) do
      add :hash, :string, primary_key: true, size: 16
      add :file_path, :string, null: false
      add :ref_count, :integer, default: 1, null: false
      add :size, :bigint, null: false
      add :mime_type, :string
      
      timestamps(type: :utc_datetime)
    end
    
    create index(:file_refs, [:ref_count])
    create constraint(:file_refs, :ref_count_positive, check: "ref_count > 0")
  end
end
```

2. **Schema FileRef**

```elixir
# lib/portfolio/photography/storage/file_ref.ex
defmodule Portfolio.Photography.Storage.FileRef do
  @moduledoc """
  Value Object représentant une référence de fichier avec comptage.
  
  Un FileRef trace combien de Photos référencent un fichier physique.
  Quand ref_count atteint 0, le fichier peut être supprimé.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:hash, :string, autogenerate: false}
  
  schema "file_refs" do
    field :file_path, :string
    field :ref_count, :integer, default: 1
    field :size, :integer
    field :mime_type, :string
    
    timestamps(type: :utc_datetime)
  end
  
  def changeset(file_ref, attrs) do
    file_ref
    |> cast(attrs, [:hash, :file_path, :ref_count, :size, :mime_type])
    |> validate_required([:hash, :file_path, :ref_count, :size])
    |> validate_number(:ref_count, greater_than: 0)
    |> validate_length(:hash, is: 16)
  end
  
  def increment_ref(file_ref) do
    change(file_ref, ref_count: file_ref.ref_count + 1)
  end
  
  def decrement_ref(file_ref) do
    change(file_ref, ref_count: file_ref.ref_count - 1)
  end
end
```

3. **Logique déduplication**

```elixir
# lib/portfolio/photography/storage/local_storage.ex

def store_photo(upload, _opts) do
  with {:ok, hash} <- compute_hash(upload.path),
       {:ok, file_ref} <- get_or_create_file_ref(hash, upload),
       {:ok, metadata} <- build_photo_metadata(hash, upload, file_ref) do
    {:ok, metadata}
  end
end

defp get_or_create_file_ref(hash, upload) do
  case Repo.get(FileRef, hash) do
    nil ->
      # Nouveau fichier : Copier et créer FileRef
      create_new_file_ref(hash, upload)
    
    file_ref ->
      # Déduplication : Incrémenter ref_count
      Logger.info("File deduplication detected", hash: hash, ref_count: file_ref.ref_count)
      
      file_ref
      |> FileRef.increment_ref()
      |> Repo.update!()
      
      {:ok, file_ref}
  end
end

defp create_new_file_ref(hash, upload) do
  dest_path = "/uploads/files/#{hash}/original.#{get_extension(upload.content_type)}"
  
  with :ok <- ensure_directory_exists(dest_path),
       :ok <- copy_file(upload.path, dest_path),
       :ok <- verify_file_integrity(dest_path, hash),
       {:ok, file_stat} <- File.stat(dest_path) do
    
    file_ref = %FileRef{
      hash: hash,
      file_path: dest_path,
      ref_count: 1,
      size: file_stat.size,
      mime_type: upload.content_type
    }
    
    {:ok, Repo.insert!(file_ref)}
  end
end

defp compute_hash(file_path) do
  hash =
    File.stream!(file_path, [], 2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
      :crypto.hash_update(acc, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)  # ✅ 16 caractères (corrigé)

  {:ok, hash}
end
```

4. **Suppression avec reference counting**

```elixir
def delete_photo(photo_id) do
  photo = Repo.get!(Photo, photo_id)
  file_ref = Repo.get!(FileRef, photo.hash)
  
  Repo.transaction(fn ->
    # Supprimer photo DB
    Repo.delete!(photo)
    
    # Décrémenter ref_count
    if file_ref.ref_count == 1 do
      # Dernière référence : Supprimer fichier physique
      File.rm_rf!("/uploads/files/#{photo.hash}/")
      Repo.delete!(file_ref)
      
      Logger.info("File deleted (last reference)", hash: photo.hash)
    else
      # Encore des références : Juste décrémenter
      file_ref
      |> FileRef.decrement_ref()
      |> Repo.update!()
      
      Logger.info("Reference decremented", hash: photo.hash, remaining: file_ref.ref_count - 1)
    end
  end)
end
```

5. **Gestion collision (rare)**

```elixir
defp get_or_create_file_ref(hash, upload) do
  case Repo.get(FileRef, hash) do
    nil ->
      create_new_file_ref(hash, upload)
    
    file_ref ->
      # Vérifier que le fichier existant = même contenu (collision detection)
      existing_hash = compute_full_hash(file_ref.file_path)
      upload_hash = compute_full_hash(upload.path)
      
      if existing_hash == upload_hash do
        # Vraie déduplication
        increment_ref_count(file_ref)
      else
        # Collision SHA-256 (quasi impossible) : Fallback suffix aléatoire
        Logger.error("SHA-256 collision detected!", hash: hash)
        
        collision_hash = "#{hash}_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"
        create_new_file_ref(collision_hash, upload)
      end
  end
end

defp compute_full_hash(file_path) do
  # Hash complet 64 caractères pour vérification collision
  File.stream!(file_path, [], 2048)
  |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
  |> :crypto.hash_final()
  |> Base.encode16(case: :lower)
end
```

---

## Conséquences

### Positives

1. **Économie stockage significative**
   - Estimation : 5-10% duplicatas (erreur upload, réutilisation albums)
   - 1000 photos : 400MB économisés (5MB/photo × 10% × 1000 - overhead)
   - VPS 40GB : 8k photos → 12k photos (gain 50%)

2. **Détection automatique duplicatas**
   - Upload même photo 2× = détection immédiate
   - Feedback utilisateur : "Cette photo existe déjà"
   - Évite erreurs upload

3. **Intégrité fichiers garantie**
   - Hash verification après copie = corruption détection
   - Fichier corrompu = upload rejeté
   - Production : Aucune photo corrompue stockée

4. **Réutilisation cross-album**
   - Photo "voyage 2024" réutilisable dans "top 2025"
   - Pas de re-upload nécessaire
   - UX améliorée (sélection photos existantes)

5. **Performance upload optimisée**
   - Duplicata détecté = skip copie fichier
   - Upload 20 photos dont 5 duplicatas = économie 25% temps

### Négatives

1. **Complexité implémentation (mitigée)**
   - Table `file_refs` + logic reference counting
   - Transaction atomique suppression (photo + decrement ref_count)
   - Tests edge cases (race conditions, collision)
   - **Mitigation** : Architecture claire, tests exhaustifs, transaction ACID

2. **Performance hash calculation (acceptable)**
   - SHA-256 : ~200-300ms pour 12MP JPEG
   - Upload 20 photos : +4-6s total (acceptable vs économie stockage)
   - **Mitigation** : Hash calculation en background si nécessaire (Oban worker)

3. **Risque collision SHA-256 (très faible)**
   - 16 caractères = 64 bits = collision < 0.01% à 1M photos
   - Probabilité : Quasi nulle (2^64 = 18 quintillions possibilités)
   - **Mitigation** : Fallback suffix aléatoire si collision détectée (code fourni)

4. **Dette technique actuelle (résolu Q1 2026)**
   - Implémentation partielle : Hash calculé mais pas de déduplication
   - Code à refactorer : Migration structure répertoires
   - **Mitigation** : Plan implémentation clair (voir Plan d'action)

### Risques

1. **Bug reference counting**
   - Probabilité : Moyenne (logique concurrence complexe)
   - Impact : Élevé (fichier supprimé alors que références existent, ou inverse)
   - **Plan contingence** : 
     - Constraint DB `ref_count > 0`
     - Transaction ACID (all-or-nothing)
     - Tests exhaustifs race conditions
     - Monitoring ref_count orphelins (script maintenance)

2. **Migration données production**
   - Probabilité : Certaine (si photos existantes)
   - Impact : Moyen (temps migration, downtime)
   - **Plan contingence** :
     - Script migration idempotent
     - Backup complet avant migration
     - Migration progressive (batch par batch)
     - Rollback plan documenté

---

## Plan d'action

### Phase 1 : Correction hash 8 → 16 caractères (Avant Q1 2026)

**Problème** : Hash actuel 8 caractères = collision 1% à 77k photos.

**Action :**

```elixir
# lib/portfolio/photography/storage/local_storage.ex
defp compute_hash(file_path) do
  hash =
    File.stream!(file_path, [], 2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
      :crypto.hash_update(acc, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)  # Corrigé : 8 → 16

  {:ok, hash}
end
```

**Impact** : Pas de migration données nécessaire (photos existantes gardent hash 8 chars, nouvelles utilisent 16).

**Tests** :
- Vérifier hash 16 caractères généré
- Vérifier pas de collision test (générer 1000 hashs aléatoires)

**Critères succès** :
- Nouveaux uploads = hash 16 caractères
- Aucune régression fonctionnelle

### Phase 2 : Implémentation déduplication (Q1 2026)

**Étapes :**

1. **Créer migration `file_refs`** (1 jour)
   - Table schema (voir Architecture cible)
   - Index `ref_count` pour performance
   - Constraint `ref_count > 0`

2. **Créer schema `FileRef`** (1 jour)
   - Ecto schema avec validations
   - Fonctions `increment_ref/1`, `decrement_ref/1`
   - Tests unitaires

3. **Refactorer `LocalStorage.store_photo/2`** (2 jours)
   - Logic `get_or_create_file_ref/2`
   - Déduplication automatique
   - Tests déduplication (upload 2× même photo)

4. **Refactorer `LocalStorage.delete_photo/1`** (2 jours)
   - Transaction atomique (delete photo + decrement ref_count)
   - Suppression fichier si `ref_count == 1`
   - Tests suppression avec/sans références

5. **Migration données existantes** (1 jour)
   - Script analyse photos actuelles
   - Calcul ref_count pour chaque hash
   - Création FileRef pour chaque fichier unique
   - Migration structure `/uploads/photos/{hash}/` → `/uploads/files/{hash}/`

6. **Tests end-to-end** (1 jour)
   - Upload photo nouvelle → création FileRef
   - Upload photo duplicata → incrémentation ref_count
   - Suppression photo unique → suppression fichier
   - Suppression photo avec références → décrémentation ref_count
   - Tests race conditions (uploads concurrents)

**Critères succès :**
- Upload duplicata détecté automatiquement
- Aucune copie fichier si hash existe
- Suppression correcte avec reference counting
- Tests 100% passants
- Aucune régression fonctionnelle

### Phase 3 : Migration structure répertoires (Q1 2026)

**Objectif** : `/uploads/photos/{hash}/` → `/uploads/files/{hash}/`

**Script migration :**

```bash
#!/bin/bash
# scripts/migrate_storage_structure.sh

OLD_DIR="priv/static/uploads/photos"
NEW_DIR="priv/static/uploads/files"

mkdir -p "$NEW_DIR"

for hash_dir in "$OLD_DIR"/*; do
  hash=$(basename "$hash_dir")
  
  if [ -d "$hash_dir" ]; then
    echo "Migrating $hash..."
    
    # Créer nouveau répertoire
    mkdir -p "$NEW_DIR/$hash"
    
    # Déplacer fichiers (mv = atomic sur même filesystem)
    mv "$hash_dir"/* "$NEW_DIR/$hash/"
    
    # Supprimer ancien répertoire
    rmdir "$hash_dir"
  fi
done

echo "Migration complete!"
echo "Old directory: $OLD_DIR (should be empty)"
echo "New directory: $NEW_DIR"
```

**Tests validation** :
- Tous fichiers migrés correctement
- URLs photos fonctionnelles (update `file_path` DB)
- Variantes accessibles
- Aucune perte données

### Phase 4 : Monitoring et maintenance (Post-implémentation)

**Métriques à surveiller :**

1. **Dashboard admin** : Statistiques déduplication

```elixir
def deduplication_stats do
  total_photos = Repo.aggregate(Photo, :count)
  unique_files = Repo.aggregate(FileRef, :count)
  duplicates = total_photos - unique_files
  dedup_rate = duplicates / total_photos * 100
  
  storage_saved = duplicates * avg_photo_size()
  
  %{
    total_photos: total_photos,
    unique_files: unique_files,
    duplicates: duplicates,
    dedup_rate: "#{Float.round(dedup_rate, 2)}%",
    storage_saved_mb: div(storage_saved, 1_024_000)
  }
end
```

2. **Script maintenance** : Détection ref_count orphelins

```elixir
# lib/mix/tasks/check_file_refs.ex
defmodule Mix.Tasks.CheckFileRefs do
  use Mix.Task
  
  def run(_) do
    Mix.Task.run("app.start")
    
    # Vérifier ref_count cohérent
    FileRef
    |> Repo.all()
    |> Enum.each(fn file_ref ->
      actual_count = Repo.aggregate(
        from(p in Photo, where: p.hash == ^file_ref.hash),
        :count
      )
      
      if actual_count != file_ref.ref_count do
        IO.puts("❌ Inconsistency: #{file_ref.hash}")
        IO.puts("  Expected: #{file_ref.ref_count}, Actual: #{actual_count}")
        
        # Auto-correction
        Repo.update!(change(file_ref, ref_count: actual_count))
      end
    end)
    
    IO.puts("✅ Check complete")
  end
end
```

3. **Alerting** : Ref_count = 0 détecté (bug potentiel)

```elixir
# Constraint DB empêche ref_count = 0, mais monitoring additionnel
def check_orphan_files do
  orphans = 
    FileRef
    |> where([f], f.ref_count == 0)
    |> Repo.all()
  
  if length(orphans) > 0 do
    Logger.error("Orphan file refs detected", count: length(orphans))
    notify_admin("Orphan files detected: #{length(orphans)}")
  end
end
```

**Critères succès** :
- Dashboard admin affiche stats déduplication
- Script maintenance détecte incohérences
- Alerting configuré
- Documentation ops complète

---

## Références

### Documentation technique

- [SHA-256 (NIST)](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf)
- [Content-addressable storage (Wikipedia)](https://en.wikipedia.org/wiki/Content-addressable_storage)
- [Git internals (content-addressable)](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects)
- [Erlang :crypto module](https://www.erlang.org/doc/man/crypto.html)

### Études de collision

- Birthday paradox : Collision probability = 1 - e^(-n²/2d) où d = 2^bits
- 64 bits (16 hex chars) : Collision < 0.01% à 1M items
- 32 bits (8 hex chars) : Collision 1% à 77k items

### Code pertinent

- `lib/portfolio/photography/storage/local_storage.ex` : Implémentation actuelle (partielle)
- `lib/portfolio/photography/photo.ex` : Schema Photo avec `hash` field
- `lib/portfolio/photography/storage/file_ref.ex` : À créer (Q1 2026)
- `priv/repo/migrations/XXX_create_file_refs.exs` : À créer (Q1 2026)

---

## Notes

### Décisions actées

1. Hash SHA-256 16 caractères (correction 8 → 16)
2. Content-addressable storage avec reference counting
3. Structure répertoires `/uploads/files/{hash}/`
4. Table `file_refs` pour tracking références
5. Implémentation complète Q1 2026 (backlog)

### Compromis acceptés

1. **Performance hash calculation** : ~200-300ms acceptable vs économie stockage
2. **Complexité reference counting** : Justifiée par économie critique VPS 40GB
3. **Dette technique actuelle** : Implémentation partielle acceptable temporairement (Q1 2026 target)

### Enseignements

1. **Content-addressable storage = pattern éprouvé**
   - Git, Docker, IPFS utilisent ce pattern
   - Déduplication automatique garantie
   - Intégrité fichiers bonus

2. **Reference counting critique**
   - Filesystem hardlinks/symlinks insuffisants (besoin contrôle applicatif)
   - Transaction ACID nécessaire (suppression photo + decrement ref_count atomique)
   - Monitoring ref_count essentiel production

3. **Hash 16 caractères minimum**
   - 8 caractères = collision 1% à 77k photos (inacceptable)
   - 16 caractères = collision < 0.01% à 1M photos (acceptable)
   - Calcul SHA-256 complet pour vérification collision (rare)

4. **Migration données planifiée**
   - Script migration idempotent
   - Backup avant migration
   - Rollback plan documenté
   - Tests migration sur dataset test

### Prochaines révisions

- Q1 2026 : Implémentation complète déduplication
- Post-production : Analyse taux duplication réel
- Monitoring continu : Stats économie stockage
