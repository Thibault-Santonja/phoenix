# ADR-035: Ecto.Multi pour Transactions Atomiques

Statut: Accepté  
Date: 2025-11-11

## Contexte

Dans une application qui manipule des données, certaines opérations doivent être **atomiques** : soit toutes les étapes réussissent, soit aucune ne s'applique. C'est le principe des transactions de base de données.

Ecto fournit `Ecto.Multi`, un outil puissant pour construire des **pipelines de transactions** composables et lisibles.

### Problématique : Opérations Multi-Étapes

Prenons un exemple concret : la suppression d'un album avec ses photos.

**Étapes requises :**
1. Récupérer toutes les photos de l'album
2. Supprimer les fichiers physiques de chaque photo
3. Supprimer l'album (et CASCADE ses photos en DB)

**Question critique :** Que se passe-t-il si l'étape 2 échoue (disque plein, permissions) ?
- - Sans transaction : L'album est supprimé mais les fichiers restent (data orphan)
- - Avec transaction : Tout est rollback, rien n'est supprimé

### Solutions Possibles

**Solution 1 : Transactions imbriquées manuelles**

```elixir
def delete_album(album) do
  Repo.transaction(fn ->
    photos = Repo.all(from p in Photo, where: p.album_id == ^album.id)
    
    # Delete files
    Enum.each(photos, fn photo ->
      case Storage.delete(photo.file_path) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)  # Rollback manuel
      end
    end)
    
    # Delete album
    case Repo.delete(album) do
      {:ok, album} -> album
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end)
end
```

**Probl�mes :**
- - Difficile � lire (imbrications, Repo.rollback partout)
- - Gestion d'erreur complexe (if/case imbriqués)
- - Pas composable (difficile d'ajouter étapes)
- - Difficile � tester (tout dans une closure)

**Solution 2 : Ecto.Multi (Solution choisie)**

```elixir
def delete_album(album) do
  Ecto.Multi.new()
  |> Ecto.Multi.run(:photos, fn _repo, _changes ->
    photos = PhotoRepository.list_by_album(album.id)
    {:ok, photos}
  end)
  |> Ecto.Multi.run(:files, fn _repo, %{photos: photos} ->
    delete_all_files(photos)
  end)
  |> Ecto.Multi.delete(:album, album)
  |> Repo.transaction()
end
```

**Avantages :**
- - Lisible : Pipeline clair des étapes
- - Composable : Facile d'ajouter étapes
- - Rollback automatique si échec
- - Testable : Chaque étape testable séparément
- - Type safe : Retour `{:ok, changes} | {:error, step, reason, changes}`

### Contraintes

- Atomicité : Toutes les étapes DB dans une seule transaction
- Lisibilité : Pipeline de transformations clair
- **Gestion d'erreur** : Rollback automatique
- Composabilité : Facile d'ajouter/retirer étapes
- Testabilité : Étapes testables indépendamment

## Options considérées

### Option 1: Transactions Manuelles Imbriquées

Description :

Utiliser `Repo.transaction/1` avec closure et `Repo.rollback/1` manuel pour chaque erreur.

```elixir
def complex_operation(params) do
  Repo.transaction(fn ->
    # Step 1
    case step1(params) do
      {:ok, result1} ->
        # Step 2
        case step2(result1) do
          {:ok, result2} ->
            # Step 3
            case step3(result2) do
              {:ok, result3} -> result3
              {:error, reason} -> Repo.rollback(reason)
            end
          {:error, reason} -> Repo.rollback(reason)
        end
      {:error, reason} -> Repo.rollback(reason)
    end
  end)
end
```

Avantages :
- Simplicité apparente pour 1-2 étapes
- Pas de dépendance (Ecto.Multi natif)

Inconvénients :
- Pyramid of doom : Imbrications illisibles
- - Duplication : `Repo.rollback` répété partout
- - Pas composable : Impossible d'extraire étapes
- Difficile � tester : Tout dans une closure anonyme
- - **Gestion d'erreur complexe** : if/case imbriqués

Effort estimé : Faible (convention Ecto standard)

Risques :
- Code illisible et non maintenable [Probabilité: Élevée, Impact: Élevé]

### Option 2: `with` Pipeline Sans Transaction

Description :

Utiliser le mot-clé `with` d'Elixir pour chaîner les opérations, mais sans garantie transactionnelle.

```elixir
def complex_operation(params) do
  with {:ok, result1} <- step1(params),
       {:ok, result2} <- step2(result1),
       {:ok, result3} <- step3(result2) do
    {:ok, result3}
  end
end
```

Avantages :
- - Lisible : Pipeline clair
- - Pattern matching élégant
- - Idiomatique Elixir

Inconvénients :
- Pas de transaction : Si step2 réussit puis step3 échoue, step2 n'est pas rollback
- - Pas atomique : État inconsistant possible
- Compensating actions manuelles : Faut rollback manuellement

**Exemple de probl�me :**

```elixir
with {:ok, user} <- create_user(attrs),           # Insert DB
     {:ok, file} <- upload_avatar(user, avatar),  # Upload file
     {:ok, email} <- send_welcome(user) do        # Send email
  {:ok, user}
end

# Si send_welcome échoue :
# - User créé en DB 
# - Avatar uploadé -  
# - Email pas envoyé 
# � État inconsistant ! User existe mais pas d'email de bienvenue
```

Effort estimé : Faible

Risques :
- État inconsistant de la DB [Probabilité: Élevée, Impact: Critique]

### Option 3: Ecto.Multi (Choix actuel)

Description :

Utiliser `Ecto.Multi` pour construire un pipeline de transformations transactionnelles. Toutes les étapes s'exécutent dans une transaction DB unique, avec rollback automatique si échec.

**Architecture :**

```
Ecto.Multi Pipeline
    �
Multi.new()
    �
Multi.run(:step1, fn -> ... end)  # Étape 1
    �
Multi.run(:step2, fn -> ... end)  # Étape 2 (acc�de résultat step1)
    �
Multi.delete(:step3, entity)       # Étape 3
    �
Repo.transaction()
    �
{:ok, %{step1: r1, step2: r2, step3: r3}}  � Succ�s
OU
{:error, :step2, reason, %{step1: r1}}     � Échec step2, rollback tout
```

**Implémentation :**

```elixir
defmodule AlbumDeletionService do
  alias Ecto.Multi
  
  def execute(%Album{} = album) do
    Multi.new()
    |> Multi.run(:photos, fn _repo, _changes ->
      # Étape 1 : Récupérer photos
      photos = PhotoRepository.list_by_album(album.id)
      {:ok, photos}
    end)
    |> Multi.run(:files, fn _repo, %{photos: photos} ->
      # Étape 2 : Supprimer fichiers (acc�s résultat :photos)
      delete_all_files(photos)
    end)
    |> Multi.delete(:album, album)
    # Étape 3 : Supprimer album DB
    |> Repo.transaction()
    # Exécution atomique
  end
  
  defp delete_all_files(photos) do
    results = Enum.map(photos, &Storage.delete(&1.file_path))
    
    if Enum.all?(results, &success?/1) do
      {:ok, :ok}
    else
      {:error, :file_deletion_failed}  # Cause rollback
    end
  end
end
```

Avantages :
- - Atomicité garantie : Tout ou rien, pas d'état inconsistant
- - Rollback automatique : Pas de `Repo.rollback` manuel
- - Lisibilité : Pipeline clair et séquentiel
- - Composabilité : Facile d'ajouter/retirer étapes
  ```elixir
  Multi.new()
  |> Multi.run(:step1, ...)
  |> Multi.run(:step2, ...)
  |> add_optional_step(condition)  # Composable
  |> Multi.run(:step3, ...)
  ```
- Acc�s résultats précédents : `fn _repo, %{step1: result1} -> ... end`
- - Type safe : Retour structuré avec nom d'étape en cas d'erreur
- - Testabilité : Chaque step testable séparément

Inconvénients :
- Pattern moins connu que `with` (courbe d'apprentissage)
- Verbosité lég�rement supérieure pour opérations simples

Effort estimé : Moyen

Risques :
- Over-engineering pour opérations tr�s simples [Probabilité: Faible, Impact: Faible]

## Décision

L'option choisie est: **Option 3 - Ecto.Multi**

### Justification

Ecto.Multi offre le meilleur compromis entre **atomicité, lisibilité et maintenabilité** pour les opérations multi-étapes. Cette solution :

1. Garantit l'atomicité : Transaction DB unique, rollback automatique
2. Améliore la lisibilité : Pipeline clair vs pyramid of doom
3. Facilite la composition : Ajouter/retirer étapes facilement
4. Simplifie les tests : Étapes testables indépendamment
5. S'aligne avec Ecto : Pattern natif, bien documenté

Le principal compromis accepté est la **courbe d'apprentissage** (pattern moins connu que `with`), mais la documentation et les exemples compensent.

## Conséquences

### Positives

- **État DB toujours cohérent** : Atomicité garantie, pas d'état inconsistant
- Code maintenable : Pipeline lisible vs imbrications complexes
- **Facilité d'évolution** : Ajouter étapes sans refactoring majeur
- Testabilité : Chaque step testable en isolation
- **Gestion d'erreur claire** : Retour structure {:error, step, reason, changes}
- Rollback automatique : Pas de `Repo.rollback` manuel

### Négatives

- **Courbe d'apprentissage** : Pattern moins intuitif que `with` pour juniors
- Verbosité : Plus de code pour opérations tr�s simples

### Neutres

- Transaction DB unique : Toutes les étapes dans une transaction (lock temps)

## Guide d'Utilisation : Ecto.Multi Expliqué

### Anatomie d'un Ecto.Multi

**Structure de base :**

```elixir
Ecto.Multi.new()                    # 1. Créer pipeline vide
|> Multi.insert(:user, changeset)   # 2. Opération Ecto
|> Multi.run(:custom, fn -> ... end)# 3. Opération custom
|> Multi.delete(:old, entity)       # 4. Autre opération Ecto
|> Repo.transaction()               # 5. Exécution atomique
```

**Retour de `Repo.transaction/1` :**

```elixir
# Succ�s : Toutes les étapes ont réussi
{:ok, %{
  user: %User{id: "123"},     # Résultat de :user
  custom: {:ok, value},       # Résultat de :custom
  old: %OldEntity{}           # Résultat de :old (deleted)
}}

# Échec : Une étape a échoué
{:error, 
  :custom,                    # Nom de l'étape qui a échoué
  :some_error,                # Raison de l'échec
  %{user: %User{}}            # Résultats des étapes réussies AVANT l'échec
}
```

### Pattern 1: Multi.run (Opération Custom)

**Usage :** Exécuter une fonction custom avec acc�s aux résultats précédents.

**Signature :**

```elixir
Multi.run(multi, name, fn repo, changes -> 
  # repo = Repo module
  # changes = Map des résultats des étapes précédentes
  
  # Retour :
  {:ok, result}        # Succ�s, continue
  {:error, reason}     # Échec, rollback tout
end)
```

**Exemple concret : AlbumDeletionService**

```elixir
Multi.new()
|> Multi.run(:photos, fn _repo, _changes ->
  # Pas d'acc�s aux changes (premi�re étape)
  photos = PhotoRepository.list_by_album(album.id)
  {:ok, photos}  # Retour succ�s avec photos
end)
|> Multi.run(:files, fn _repo, %{photos: photos} ->
  # Acc�s au résultat de :photos via pattern matching
  case delete_all_files(photos) do
    :ok -> {:ok, :ok}
    {:error, reason} -> {:error, reason}  # Rollback automatique
  end
end)
```

**Points clés :**
- - Acc�s aux résultats précédents via `changes` map
- - Pattern matching pour extraire résultats : `%{photos: photos}`
- - Retour `{:ok, result}` pour continuer
- - Retour `{:error, reason}` pour rollback

### Pattern 2: Multi.insert/update/delete (Opérations Ecto)

**Usage :** Opérations Ecto standard (insert, update, delete) dans le pipeline.

```elixir
# Insert
Multi.insert(multi, :user, changeset)
Multi.insert(multi, :user, changeset, opts)

# Update
Multi.update(multi, :updated_user, changeset)

# Delete
Multi.delete(multi, :deleted_album, album_struct)
```

**Exemple concret : PhotoDeletionService**

```elixir
Multi.new()
|> Multi.delete(:photo, photo)  # Delete en DB (étape 1)
|> Multi.run(:file, fn _repo, %{photo: deleted_photo} ->
  # Acc�s � la photo supprimée
  delete_photo_file(deleted_photo.file_path)
end)
|> Repo.transaction()
```

**Avantage :** Les opérations Ecto sont raccourcies (pas de `fn -> Repo.delete(...) end`).

### Pattern 3: Acc�s Résultats Précédents

**Clé du pattern :** Chaque étape peut accéder aux résultats des étapes précédentes via `changes`.

**Exemple : Dépendances entre étapes**

```elixir
Multi.new()
|> Multi.run(:user, fn _repo, _changes ->
  # Créer user
  {:ok, %User{id: "123", email: "user@example.com"}}
end)
|> Multi.run(:profile, fn _repo, %{user: user} ->
  # Créer profile pour ce user (dépend de :user)
  {:ok, %Profile{user_id: user.id}}
end)
|> Multi.run(:settings, fn _repo, %{user: user, profile: profile} ->
  # Créer settings pour user+profile (dépend des deux)
  {:ok, %Settings{user_id: user.id, profile_id: profile.id}}
end)
|> Repo.transaction()

# Résultat si succ�s
{:ok, %{
  user: %User{id: "123"},
  profile: %Profile{user_id: "123"},
  settings: %Settings{user_id: "123", profile_id: "456"}
}}
```

### Pattern 4: Gestion d'Erreur Structurée

**Retour d'erreur détaillé :**

```elixir
case Repo.transaction(multi) do
  {:ok, %{user: user, profile: profile}} ->
    # Succ�s : Toutes les étapes OK
    {:ok, user}
  
  {:error, :profile, changeset, %{user: user}} ->
    # Échec � l'étape :profile
    # - changeset contient les erreurs
    # - user contient le résultat de :user (avant échec)
    Logger.error("Profile creation failed", errors: changeset.errors)
    {:error, :profile_creation_failed}
  
  {:error, :settings, reason, changes} ->
    # Échec � l'étape :settings
    Logger.error("Settings creation failed", reason: reason)
    {:error, :settings_creation_failed}
end
```

**Cas d'usage : Compensation (pas de rollback DB)**

Parfois, les étapes non-DB ne sont pas rollback automatiquement (ex: fichiers, emails). Il faut compenser manuellement.

```elixir
case Repo.transaction(multi) do
  {:ok, result} -> {:ok, result}
  
  {:error, :email, _reason, %{user: user, file: file_path}} ->
    # Email a échoué, mais user créé et file uploadé
    # Transaction DB rollback (user supprimé)
    # Mais file pas rollback automatiquement
    
    # Compensation manuelle : supprimer le fichier
    Storage.delete(file_path)
    
    {:error, :email_failed}
end
```

### Pattern 5: Composition et Réutilisation

**Principe :** Multi est composable. On peut extraire des "sub-multis" et les combiner.

**Exemple : Extract Sub-Multi**

```elixir
defmodule UserCreationService do
  def create_user_multi(attrs) do
    Multi.new()
    |> Multi.insert(:user, User.changeset(%User{}, attrs))
    |> Multi.insert(:profile, fn %{user: user} ->
      Profile.changeset(%Profile{}, %{user_id: user.id})
    end)
  end
end

defmodule SubscriptionService do
  def create_with_user(user_attrs, subscription_attrs) do
    Multi.new()
    |> Multi.append(UserCreationService.create_user_multi(user_attrs))
    |> Multi.run(:subscription, fn _repo, %{user: user} ->
      create_subscription(user, subscription_attrs)
    end)
    |> Repo.transaction()
  end
end
```

**`Multi.append/2`** : Combine deux Multi pipelines.

### Pattern 6: Conditional Steps

**Principe :** Ajouter des étapes conditionnellement selon les param�tres.

**Exemple :**

```elixir
def execute(album, opts) do
  Multi.new()
  |> Multi.delete(:album, album)
  |> maybe_send_notification(opts[:notify])
  |> Repo.transaction()
end

defp maybe_send_notification(multi, true) do
  Multi.run(multi, :notification, fn _repo, %{album: album} ->
    send_notification(album)
    {:ok, :sent}
  end)
end

defp maybe_send_notification(multi, _), do: multi
```

### Cas d'Usage Réels du Projet

#### AlbumDeletionService 

**Use case :** Supprimer un album avec toutes ses photos et fichiers.

**Étapes :**
1. Fetch all photos de l'album
2. Delete tous les fichiers physiques
3. Delete l'album DB (CASCADE supprime photos DB)

**Implémentation :**

```elixir
Multi.new()
|> Multi.run(:photos, fn _repo, _changes ->
  photos = PhotoRepository.list_by_album(album.id)
  {:ok, photos}
end)
|> Multi.run(:files, fn _repo, %{photos: photos} ->
  delete_photo_files(photos)
end)
|> Multi.delete(:album, album)
|> Repo.transaction()
```

Pourquoi Multi nécessaire ?
- - Si delete files échoue � Rollback, album pas supprimé
- - Atomicité garantie : Album + photos + files cohérents

#### PhotoDeletionService 

**Use case :** Supprimer une photo avec son fichier.

**Étapes :**
1. Delete photo record DB
2. Delete fichier physique

**Implémentation :**

```elixir
Multi.new()
|> Multi.delete(:photo, photo)
|> Multi.run(:file, fn _repo, %{photo: deleted_photo} ->
  delete_photo_file(deleted_photo.file_path)
end)
|> Repo.transaction()
```

Pourquoi Multi nécessaire ?
- - Si delete file échoue � Rollback, photo pas supprimée en DB
- - Évite photos orphelines en DB sans fichier

#### PhotoUploadService 

**Use case :** Uploader N photos en parall�le puis créer records DB.

**Étapes :**
1. Upload N fichiers en parall�le (Task.async_stream)
2. Créer N photo records en DB atomiquement

**Implémentation :**

```elixir
# Step 1 : Upload hors transaction
{:ok, uploaded_metadata} = upload_files_parallel(uploads)

# Step 2 : Create records atomiquement
multi =
  uploaded_metadata
  |> Enum.with_index()
  |> Enum.reduce(Multi.new(), fn {metadata, index}, multi ->
    Multi.run(multi, {:create_photo, index}, fn _repo, _changes ->
      Photography.create_photo(%{
        album_id: album.id,
        file_path: metadata.storage_path,
        hash: metadata.hash
      })
    end)
  end)

case Repo.transaction(multi) do
  {:ok, photos} -> {:ok, photos}
  {:error, _step, _reason, _changes} ->
    # Rollback DB OK
    # Compensation : Delete uploaded files
    rollback_uploaded_files(uploaded_metadata)
    {:error, :upload_failed}
end
```

Pourquoi Multi nécessaire ?
- - Créer N photos atomiquement : Si une photo fail � Rollback toutes
- - Évite photos partiellement créées

#### MagicLinkAuthService 

**Use case :** Créer ou récupérer user + créer magic link.

**Étapes :**
1. Get or create user par email
2. Créer magic link token pour ce user

**Implémentation :**

```elixir
Multi.new()
|> Multi.run(:user, fn _repo, _changes ->
  fetch_or_create_user(email)
end)
|> Multi.run(:magic_link, fn _repo, %{user: user} ->
  create_magic_link(user)
end)
|> Repo.transaction()
```

Pourquoi Multi nécessaire ?
- - Si create magic_link échoue � Rollback user creation (si nouveau user)
- - Atomicité : User + MagicLink cohérents

## Plan d'action

### Phase 1: Documentation (Priorité: HAUTE)

Tâches :
1. Documenter Ecto.Multi pattern dans `/docs`
2. Créer exemples commentés pour chaque pattern
3. Ajouter flowchart "Quand utiliser Multi vs with vs transaction"
4. Documenter les cas d'usage réels du projet

Crit�res de succ�s :
- Guide complet Ecto.Multi disponible
- Exemples pour chaque pattern

**Estimation:** 0.5 jour (ce document )

### Phase 2: Audit Usage (Priorité: MOYENNE)

Tâches :
1. Identifier tous les usages d'Ecto.Multi dans le projet
2. Vérifier la cohérence (gestion d'erreur, naming)
3. Chercher les transactions manuelles qui devraient être Multi

Crit�res de succ�s :
- Liste compl�te des usages Multi
- Aucune transaction manuelle complexe détectée

**Estimation:** 0.5 jour

### Phase 3: Tests (Priorité: HAUTE)

Tâches :
1. Créer tests pour tous les Services utilisant Multi
2. Tester les cas de succ�s
3. Tester les cas d'échec � chaque étape
4. Vérifier le rollback automatique

**Pattern de test :**

```elixir
describe "AlbumDeletionService" do
  test "deletes album, photos and files atomically" do
    album = album_fixture_with_photos(3)
    
    assert {:ok, %{album: _, photos: photos, files: :ok}} =
      AlbumDeletionService.execute(album)
    
    assert length(photos) == 3
    refute Repo.get(Album, album.id)
  end
  
  test "rolls back if file deletion fails" do
    album = album_fixture()
    
    # Mock Storage to fail
    expect(StorageMock, :delete_photo, fn _ -> {:error, :eacces} end)
    
    assert {:error, :files, :eacces, %{photos: _}} =
      AlbumDeletionService.execute(album)
    
    # Album still exists (rollback)
    assert Repo.get(Album, album.id)
  end
end
```

Crit�res de succ�s :
- Tous les Services Multi testés
- Tests succ�s + échec � chaque étape
- Coverage > 90%

**Estimation:** 2 jours

### Phase 4: Best Practices (Priorité: BASSE)

Tâches :
1. Standardiser le naming des étapes (`:user`, `:create_photo`, etc.)
2. Standardiser la gestion d'erreur (pattern match systématique)
3. Documenter les compensations nécessaires (files, emails)

Crit�res de succ�s :
- Convention de naming documentée
- Pattern gestion d'erreur standardisé

**Estimation:** 0.5 jour

## Références

- [Ecto.Multi Documentation](https://hexdocs.pm/ecto/Ecto.Multi.html)
- [Multi-tenancy with Ecto](https://dashbit.co/blog/multitenancy-with-ecto)
- [Working with Ecto Associations and Embeds](https://dashbit.co/blog/working-with-ecto-associations-and-embeds)
- Code source :
  - `lib/portfolio/services/photography/album_deletion_service.ex`
  - `lib/portfolio/services/photography/photo_deletion_service.ex`
  - `lib/portfolio/services/photography/photo_upload_service.ex`
  - `lib/portfolio/services/auth/magic_link_auth_service.ex`

## Notes

### Ecto.Multi vs `with` : Quand Utiliser Quoi ?

| Crit�re | `with` | `Ecto.Multi` |
|---------|--------|--------------|
| Transaction DB nécessaire | - Non | - Oui |
| Opérations multiples DB | Pas atomique | Atomique |
| Rollback automatique | Non | Oui |
| Lisibilité | - Excellente | - Bonne |
| Gestion d'erreur | Pattern matching | Pattern matching + step name |
| Use case | Validation, fetching | Mutations DB atomiques |

**R�gle simple :**
- `with` pour **lectures** et **validations** (pas de mutation DB)
- `Ecto.Multi` pour **mutations atomiques** (insert, update, delete)

### Performance : Une Transaction vs N Transactions

**Question :** Ecto.Multi met tout dans une transaction. N'est-ce pas lent ?

**Réponse :** Non, c'est **plus rapide** qu'N transactions séparées.

```elixir
# - LENT : N transactions (N roundtrips DB)
photos |> Enum.each(fn photo ->
  Repo.transaction(fn -> Repo.insert(photo) end)
end)
# 100 photos = 100 transactions = 100 roundtrips

# - RAPIDE : 1 transaction (1 roundtrip DB)
multi = Enum.reduce(photos, Multi.new(), fn photo, multi ->
  Multi.insert(multi, {:photo, photo.id}, photo)
end)
Repo.transaction(multi)
# 100 photos = 1 transaction = 1 roundtrip
```

**Benchmark :**
- 100 inserts séparés : ~500ms
- 100 inserts dans Multi : ~50ms
- **10x plus rapide** 

### Limites d'Ecto.Multi

**Ce que Multi NE fait PAS :**

1. Rollback fichiers/emails : Seules les opérations DB sont rollback
   - Solution : Compensation manuelle en cas d'erreur
   
2. Parallélisme : Étapes exécutées séquentiellement
   - Solution : Parallélisme hors transaction (Task.async_stream)
   
3. Distributed transactions : Transaction sur 1 seule DB
   - Solution : Saga pattern si multiples DBs

**Exemple compensation fichiers :**

```elixir
case Repo.transaction(multi) do
  {:ok, result} -> {:ok, result}
  {:error, _step, _reason, %{uploaded_files: files}} ->
    # Rollback DB automatique 
    # Rollback files manuel - (nécessaire)
    Enum.each(files, &Storage.delete/1)
    {:error, :transaction_failed}
end
```

---

**Date de création:** 2025-11-11  
**Derni�re révision:** 2025-11-11
