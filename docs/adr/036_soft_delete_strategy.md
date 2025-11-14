# ADR-036: Soft Delete Strategy

Statut: Accepté
Date: 2025-11-12

## Contexte

Le portfolio gère des contenus photographiques précieux (photographies, albums, projets) avec traitement asynchrone coûteux (conversion AVIF, génération variantes). La suppression accidentelle de contenus représente un risque métier significatif.

### Risques Identifiés

**Suppression accidentelle** :
- Clic involontaire bouton supprimer
- Erreur manipulation (sélection multiple accidentelle)
- Confusion entre dépublication et suppression
- Pas de confirmation suffisante (un seul clic)

**Coût récupération** :
- Photographie : Fichier original perdu, re-upload + re-traitement (2-5 minutes par photo)
- Album : 10-50 photos perdues, reconstruction manuelle associations
- Projet : Arbre hiérarchique perdu, réorganisation complète nécessaire
- Métadonnées EXIF : Extraction coûteuse (appel Vix/libvips)

**Impact utilisateur** :
- Portfolio personnel : Perte contenu irréversible si pas de backup externe
- Perte temps : Re-création albums, re-upload photos, re-configuration projets
- Frustration : Erreur humaine facilement évitable avec période de grâce

### Besoins Métier

**Protection données** :
- Période de grâce avant suppression définitive
- Possibilité annuler suppression accidentelle
- Transparence utilisateur (contenu masqué mais récupérable)

**Gestion cycle de vie** :
- Photographies orphelines (aucune référence album/projet) doivent être nettoyées automatiquement
- Albums/projets dépubliés puis supprimés doivent libérer espace
- Cleanup automatique (pas de maintenance manuelle)

**Audit trail** :
- Historique suppressions (qui, quand, quoi)
- Récupération statistiques (taux suppressions accidentelles)
- Conformité RGPD (droit à l'effacement = suppression définitive après délai)

### Contraintes Techniques

**Performance queries** :
- Filtre `WHERE deleted_at IS NULL` doit être rapide (indexes)
- Pas d'impact queries existantes (ajout filtre transparent)

**Stockage** :
- Fichiers supprimés soft conservés 7 jours (espace disque)
- Cleanup automatique fichiers orphelins

**Jobs asynchrones** :
- Oban workers pour hard delete différé
- Programmation fiable (délai exact 7 jours)
- Gestion échecs (retry si suppression fichier échoue)

## Options Considérées

### Option 1: Soft Delete avec deleted_at (Timestamp)

**Description:**
Ajout colonne `deleted_at` (timestamp nullable) sur tables critiques. Suppression = UPDATE deleted_at = NOW(). Hard delete différé via job Oban après 7 jours.

**Implémentation:**
```sql
ALTER TABLE photographies ADD COLUMN deleted_at TIMESTAMP;
ALTER TABLE albums ADD COLUMN deleted_at TIMESTAMP;
ALTER TABLE projets ADD COLUMN deleted_at TIMESTAMP;

CREATE INDEX idx_photographies_deleted ON photographies(deleted_at) 
  WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_albums_deleted ON albums(deleted_at) 
  WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_projets_deleted ON projets(deleted_at) 
  WHERE deleted_at IS NOT NULL;

-- Queries filtrées
SELECT * FROM photographies WHERE deleted_at IS NULL;
```

**Soft delete:**
```elixir
def soft_delete(photographie) do
  photographie
  |> Ecto.Changeset.change(%{deleted_at: DateTime.utc_now()})
  |> Repo.update()
  |> case do
    {:ok, photo} ->
      # Programmer hard delete +7 jours
      %{photographie_id: photo.id}
      |> HardDeletePhotographieWorker.new(schedule_in: {7, :days})
      |> Oban.insert()
      {:ok, photo}
    error -> error
  end
end
```

**Hard delete (Oban worker):**
```elixir
defmodule HardDeletePhotographieWorker do
  use Oban.Worker, queue: :cleanup, max_attempts: 3
  
  def perform(%Oban.Job{args: %{"photographie_id" => id}}) do
    photographie = Repo.get!(Photographie, id)
    
    if DateTime.compare(DateTime.utc_now(), 
                        DateTime.add(photographie.deleted_at, 7 * 24 * 3600)) == :gt do
      # Supprimer fichiers (variantes)
      delete_files(photographie)
      
      # Supprimer enregistrement DB
      Repo.delete(photographie)
      
      :ok
    else
      {:error, :too_early}
    end
  end
end
```

**Avantages:**
- Simplicité implémentation (colonne + index + filtre)
- Restauration facile (UPDATE deleted_at = NULL)
- Historique suppressions (queries WHERE deleted_at IS NOT NULL)
- Cleanup automatique (Oban workers)
- Transparent pour application (queries ajoutent juste filtre)
- Standard industrie (pattern reconnu)

**Inconvénients:**
- Queries impactées (ajout filtre WHERE sur toutes queries)
- Indexes supplémentaires (espace disque)
- Risque oubli filtre (query retourne données supprimées)
- Cleanup manuel initial (migration données existantes)

**Effort estimé:** Moyen (migration + refactor queries + workers)

**Risques:**
- Oubli filtre WHERE deleted_at IS NULL [Probabilité: Moyenne, Impact: Moyen]
  - Mitigation : Scope Ecto par défaut, tests exhaustifs
- Accumulation données soft deleted [Probabilité: Faible, Impact: Faible]
  - Mitigation : Job hebdomadaire cleanup > 7 jours, monitoring volumétrie

---

### Option 2: Soft Delete avec is_deleted (Boolean)

**Description:**
Colonne `is_deleted` (boolean, default false). Suppression = UPDATE is_deleted = TRUE.

**Implémentation:**
```sql
ALTER TABLE photographies ADD COLUMN is_deleted BOOLEAN DEFAULT FALSE;
ALTER TABLE photographies ADD COLUMN deleted_at TIMESTAMP;

-- Queries filtrées
SELECT * FROM photographies WHERE is_deleted = FALSE;
```

**Avantages:**
- Boolean simple (pas de confusion timestamp NULL vs présent)
- Index partial efficace (WHERE is_deleted = TRUE)

**Inconvénients:**
- Deux colonnes nécessaires (is_deleted + deleted_at pour calcul délai)
- Redondance (boolean déduit de deleted_at IS NOT NULL)
- Pas standard industrie (timestamp plus courant)

**Effort estimé:** Moyen (similaire Option 1 + gestion 2 colonnes)

**Décision:** Rejeté car redondance et moins standard que timestamp seul.

---

### Option 3: Table Historique Séparée (deleted_items)

**Description:**
Table dédiée `deleted_items` stockant enregistrements supprimés. Suppression = INSERT dans deleted_items + DELETE original.

**Implémentation:**
```sql
CREATE TABLE deleted_items (
  id UUID PRIMARY KEY,
  table_name VARCHAR(50),
  record_id UUID,
  data JSONB, -- Enregistrement complet sérialisé
  deleted_at TIMESTAMP,
  deleted_by UUID
);
```

**Avantages:**
- Queries normales non impactées (pas de filtre WHERE)
- Séparation claire données actives/supprimées
- Historique centralisé (audit trail)

**Inconvénients:**
- Complexité restauration (désérialiser JSONB, ré-insérer avec contraintes)
- Sérialisation/désérialisation coûteuse
- Perte typage (JSONB = map libre)
- Relations complexes (foreign keys perdues)
- Over-engineering pour use case

**Effort estimé:** Élevé (sérialisation, restauration complexe)

**Décision:** Rejeté car complexité restauration et over-engineering.

---

### Option 4: Versioning avec Event Sourcing

**Description:**
Stockage événements (PhotoSupprimée, AlbumSupprimé) plutôt que modification état. Reconstruction état via replay événements.

**Avantages:**
- Historique complet (audit trail exhaustif)
- Time travel (état à n'importe quel moment)
- Événements immuables

**Inconvénients:**
- Complexité très élevée (infrastructure event store)
- Performance queries (reconstruction état coûteuse)
- Over-engineering extrême pour use case
- Pas de besoin time travel identifié

**Effort estimé:** Très élevé (réécriture architecture complète)

**Décision:** Rejeté car over-engineering massif, pas de besoin justifiant complexité.

---

### Option 5: Backup DB + Suppression Immédiate

**Description:**
Suppression immédiate (DELETE) + backup DB quotidien. Récupération via restauration backup si erreur.

**Avantages:**
- Simplicité maximale (pas de soft delete)
- Pas d'impact queries (pas de filtre WHERE)

**Inconvénients:**
- Récupération complexe (restauration DB partielle)
- Granularité grossière (backup quotidien = perte max 24h)
- Pas self-service (nécessite intervention admin système)
- Perte données entre backups (photos uploadées dans journée)

**Effort estimé:** Faible (aucun changement application)

**Décision:** Rejeté car récupération complexe et perte données possibles.

---

## Décision

L'option choisie est: **Option 1 - Soft Delete avec deleted_at (Timestamp)**

### Justification

**1. Protection Données (Critique)**

Période de grâce 7 jours permet annuler suppressions accidentelles :
- Erreur détectée immédiatement → restauration simple (UPDATE deleted_at = NULL)
- Erreur détectée 3 jours après → contenu toujours récupérable
- Délai 7 jours équilibre récupération vs espace disque

Backup DB insuffisant (restauration complexe, granularité journée).

**2. Simplicité Implémentation (Très important)**

Pattern standard industrie :
- Colonne timestamp nullable
- Index partial (WHERE deleted_at IS NOT NULL)
- Filtre WHERE deleted_at IS NULL sur queries
- Oban workers pour cleanup automatique

Table historique et Event Sourcing over-engineering pour use case.

**3. Restauration Facile (Important)**

UPDATE deleted_at = NULL restaure instantanément :
- Pas de désérialisation JSONB
- Pas de reconstruction état
- Pas de replay événements
- Relations intactes (foreign keys préservées)

**4. Audit Trail (Souhaitable)**

Colonne deleted_at fournit historique basique :
- Qui : utilisateur_id (via audit logs séparés)
- Quand : deleted_at timestamp
- Quoi : record avec deleted_at IS NOT NULL

Événements métier `PhotoSuppriméeSoft`, `AlbumSuppriméSoft` pour analytics.

**5. Performance Acceptable (Souhaitable)**

Impact queries minime :
- Index partial sur deleted_at IS NOT NULL (taille réduite)
- Filtre WHERE deleted_at IS NULL rapide (index standard)
- Volumétrie soft deleted faible (cleanup 7 jours)

### Implémentation Tactique

**Migration Base de Données:**

```sql
-- Ajout colonnes
ALTER TABLE photographies ADD COLUMN deleted_at TIMESTAMP;
ALTER TABLE albums ADD COLUMN deleted_at TIMESTAMP;
ALTER TABLE projets ADD COLUMN deleted_at TIMESTAMP;

-- Indexes partiels (performance)
CREATE INDEX idx_photographies_deleted ON photographies(deleted_at) 
  WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_albums_deleted ON albums(deleted_at) 
  WHERE deleted_at IS NOT NULL;
CREATE INDEX idx_projets_deleted ON projets(deleted_at) 
  WHERE deleted_at IS NOT NULL;

-- Trigger empêcher suppression photographie référencée
CREATE OR REPLACE FUNCTION check_photographie_references()
RETURNS TRIGGER AS $$
DECLARE
  album_count INTEGER;
  projet_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO album_count 
    FROM album_photographies WHERE photographie_id = OLD.id;
  
  SELECT COUNT(*) INTO projet_count
    FROM projet_photographies WHERE photographie_id = OLD.id;
  
  IF album_count > 0 OR projet_count > 0 THEN
    RAISE EXCEPTION 'Impossible de supprimer photographie: % références actives (% albums, % projets)',
      album_count + projet_count, album_count, projet_count;
  END IF;
  
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_photographie_references_trigger 
BEFORE DELETE ON photographies
FOR EACH ROW EXECUTE FUNCTION check_photographie_references();
```

**Repositories (Soft Delete):**

```elixir
defmodule Portfolio.Photography.PhotographieRepository do
  
  # Scope par défaut : seulement non supprimés
  defp base_query do
    from(p in Photographie, where: is_nil(p.deleted_at))
  end
  
  def list(opts \\ []) do
    base_query()
    |> apply_filters(opts)
    |> Repo.all()
  end
  
  def get(id) do
    base_query()
    |> Repo.get(id)
  end
  
  # Soft delete
  def soft_delete(photographie) do
    with {:ok, _} <- verify_no_references(photographie),
         changeset <- Ecto.Changeset.change(photographie, %{deleted_at: DateTime.utc_now()}),
         {:ok, photo} <- Repo.update(changeset),
         {:ok, _job} <- schedule_hard_delete(photo) do
      
      DomainEvents.publish(:photographie_supprimee_soft, %{
        photographie_id: photo.id,
        date_suppression_definitive: DateTime.add(photo.deleted_at, 7 * 24 * 3600)
      })
      
      {:ok, photo}
    end
  end
  
  defp verify_no_references(photographie) do
    album_count = Repo.aggregate(
      from(ap in "album_photographies", where: ap.photographie_id == ^photographie.id),
      :count
    )
    
    projet_count = Repo.aggregate(
      from(pp in "projet_photographies", where: pp.photographie_id == ^photographie.id),
      :count
    )
    
    if album_count + projet_count > 0 do
      {:error, "Photographie référencée par #{album_count} albums et #{projet_count} projets"}
    else
      {:ok, :no_references}
    end
  end
  
  defp schedule_hard_delete(photographie) do
    %{photographie_id: photographie.id}
    |> Portfolio.Workers.HardDeletePhotographieWorker.new(schedule_in: {7, :days})
    |> Oban.insert()
  end
  
  # Restauration
  def restore(photographie_id) do
    photographie = Repo.get!(Photographie, photographie_id) # Sans filtre deleted_at
    
    photographie
    |> Ecto.Changeset.change(%{deleted_at: nil})
    |> Repo.update()
    |> case do
      {:ok, photo} ->
        # Annuler job hard delete
        cancel_hard_delete_job(photo.id)
        {:ok, photo}
      error -> error
    end
  end
  
  defp cancel_hard_delete_job(photographie_id) do
    # Oban.cancel_job (recherche job par args)
    Oban.cancel_all_jobs(
      Oban,
      worker: "Portfolio.Workers.HardDeletePhotographieWorker",
      args: %{"photographie_id" => photographie_id},
      state: [:scheduled, :available]
    )
  end
  
  # Listing soft deleted (admin)
  def list_soft_deleted do
    from(p in Photographie,
      where: not is_nil(p.deleted_at),
      order_by: [desc: p.deleted_at]
    )
    |> Repo.all()
  end
  
  # Hard delete (appelé par worker)
  def hard_delete(photographie) do
    # Supprimer fichiers variantes
    delete_files(photographie)
    
    # Supprimer enregistrement DB
    Repo.delete(photographie)
    
    DomainEvents.publish(:photographie_supprimee_hard, %{
      photographie_id: photographie.id,
      fichiers_supprimes: extract_file_urls(photographie)
    })
  end
  
  defp delete_files(photographie) do
    photographie
    |> Repo.preload(:variantes)
    |> Map.get(:variantes)
    |> Enum.each(fn variante ->
      Storage.delete(variante.url)
    end)
  end
end
```

**Oban Workers (Cleanup Automatique):**

```elixir
defmodule Portfolio.Workers.HardDeletePhotographieWorker do
  use Oban.Worker, queue: :cleanup, max_attempts: 3
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photographie_id" => id}}) do
    photographie = Repo.get(Photographie, id) # Sans filtre deleted_at
    
    case photographie do
      nil ->
        # Déjà supprimé ou restauré
        :ok
        
      %{deleted_at: nil} ->
        # Restauré entre temps
        :ok
        
      %{deleted_at: deleted_at} = photo ->
        # Vérifier délai 7 jours écoulé
        if DateTime.compare(DateTime.utc_now(), 
                            DateTime.add(deleted_at, 7 * 24 * 3600)) == :gt do
          PhotographieRepository.hard_delete(photo)
          :ok
        else
          {:error, :too_early}
        end
    end
  end
end

defmodule Portfolio.Workers.HardDeleteAlbumWorker do
  use Oban.Worker, queue: :cleanup, max_attempts: 3
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"album_id" => id}}) do
    album = Repo.get(Album, id)
    
    case album do
      nil -> :ok
      %{deleted_at: nil} -> :ok
      %{deleted_at: deleted_at} = album ->
        if DateTime.compare(DateTime.utc_now(), 
                            DateTime.add(deleted_at, 7 * 24 * 3600)) == :gt do
          # Vérifier photographies orphelines
          check_orphan_photos(album)
          
          AlbumRepository.hard_delete(album)
          :ok
        else
          {:error, :too_early}
        end
    end
  end
  
  defp check_orphan_photos(album) do
    album
    |> Repo.preload(:photographies)
    |> Map.get(:photographies)
    |> Enum.each(fn photo ->
      # Si photo n'a plus aucune référence → soft delete
      if orphaned?(photo.id) do
        PhotographieRepository.soft_delete(photo)
      end
    end)
  end
  
  defp orphaned?(photo_id) do
    album_count = Repo.aggregate(
      from(ap in "album_photographies", where: ap.photographie_id == ^photo_id),
      :count
    )
    
    projet_count = Repo.aggregate(
      from(pp in "projet_photographies", where: pp.photographie_id == ^photo_id),
      :count
    )
    
    album_count + projet_count == 0
  end
end

# Job hebdomadaire : Cleanup photos orphelines soft deleted > 7 jours
defmodule Portfolio.Workers.CleanupOrphanPhotosWorker do
  use Oban.Worker, queue: :cleanup
  
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    limit_date = DateTime.add(DateTime.utc_now(), -7 * 24 * 3600)
    
    from(p in Photographie,
      where: not is_nil(p.deleted_at),
      where: p.deleted_at <= ^limit_date
    )
    |> Repo.all()
    |> Enum.each(fn photo ->
      if orphaned?(photo.id) do
        PhotographieRepository.hard_delete(photo)
      end
    end)
    
    :ok
  end
end
```

**Configuration Oban (Cron Jobs):**

```elixir
config :portfolio, Oban,
  repo: Portfolio.Repo,
  queues: [default: 10, cleanup: 5],
  crontab: [
    # Cleanup photos orphelines : tous les dimanches à 3h
    {"0 3 * * 0", Portfolio.Workers.CleanupOrphanPhotosWorker}
  ]
```

**LiveView Admin (Restauration):**

```elixir
defmodule PortfolioWeb.Admin.DeletedItemsLive do
  use PortfolioWeb, :live_view
  
  def mount(_params, _session, socket) do
    deleted_photos = PhotographieRepository.list_soft_deleted()
    deleted_albums = AlbumRepository.list_soft_deleted()
    deleted_projets = ProjetRepository.list_soft_deleted()
    
    {:ok, assign(socket, 
      deleted_photos: deleted_photos,
      deleted_albums: deleted_albums,
      deleted_projets: deleted_projets
    )}
  end
  
  def handle_event("restore_photo", %{"id" => id}, socket) do
    case PhotographieRepository.restore(id) do
      {:ok, _photo} ->
        {:noreply, put_flash(socket, :info, "Photographie restaurée")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Erreur: #{reason}")}
    end
  end
end
```

### Trade-offs Acceptés

**Impact queries** :
- Coût : Ajout filtre WHERE deleted_at IS NULL sur toutes queries
- Mitigation : Scope Ecto par défaut (base_query), index partial
- Acceptable : Impact performance négligeable (< 1ms par query)

**Risque oubli filtre** :
- Coût : Query retourne données supprimées (bug affichage)
- Mitigation : Tests exhaustifs, scope par défaut, code review
- Acceptable : Bug visible immédiatement (tests détectent)

**Espace disque** :
- Coût : Données soft deleted conservées 7 jours
- Estimation : Max 50 photos/semaine supprimées = 350 photos (3.5 GB avec variantes)
- Acceptable : Négligeable vs capacité disque serveur (50+ GB disponibles)

**Complexité cleanup** :
- Coût : Jobs Oban pour hard delete, gestion échecs, retry
- Mitigation : Oban robuste (retry automatique, dead letter queue)
- Acceptable : Infrastructure Oban déjà présente (traitement images)

## Conséquences

### Positives

- **Protection suppressions accidentelles** : Période grâce 7 jours, restauration simple
- **Restauration facile** : UPDATE deleted_at = NULL, pas de désérialisation
- **Audit trail** : Historique suppressions (deleted_at, événements métier)
- **Cleanup automatique** : Oban workers, pas de maintenance manuelle
- **Pattern standard** : Industrie-proven, documentation abondante
- **Performance acceptable** : Index partial, filtre WHERE rapide
- **Transparence queries** : Scope Ecto masque complexité
- **Relations intactes** : Foreign keys préservées (restauration cohérente)
- **Flexibilité** : Interface admin pour restauration self-service

### Négatives

- **Impact queries** : Ajout filtre WHERE deleted_at IS NULL obligatoire
  - Surveillance : Tests exhaustifs (détection oubli filtre)
  - Gestion : Scope Ecto par défaut (base_query)
- **Espace disque** : Données soft deleted conservées 7 jours
  - Surveillance : Monitoring volumétrie soft deleted (alerte si > 10 GB)
  - Gestion : Cleanup hebdomadaire, réduction délai si nécessaire (3 jours)
- **Complexité Oban** : Workers hard delete, gestion jobs delayed
  - Surveillance : Dashboard Oban (jobs failed, retry)
  - Gestion : Dead letter queue (investigation échecs)
- **Double suppression** : Soft delete puis hard delete (deux étapes)
  - Acceptable : Séparation nécessaire (période grâce vs cleanup définitif)

### Neutres

- **Colonne supplémentaire** : deleted_at dans chaque table critique
  - Coût minime (8 bytes par row)
- **Trigger détection références** : Empêche suppression photographie référencée
  - Sécurité accrue (protection intégrité données)
- **Jobs Oban delayed** : Programmation 7 jours à l'avance
  - Fiabilité Oban validée (traitement images asynchrone)

## Plan d'Action

1. **Phase 1: Migration Base de Données**
   - Ajout colonnes deleted_at (photographies, albums, projets)
   - Création indexes partiels (WHERE deleted_at IS NOT NULL)
   - Trigger check_photographie_references (protection intégrité)

2. **Phase 2: Refactoring Repositories**
   - Scope base_query avec filtre WHERE deleted_at IS NULL
   - Méthode soft_delete (UPDATE + schedule Oban job)
   - Méthode restore (UPDATE deleted_at = NULL + cancel job)
   - Méthode hard_delete (supprimer fichiers + DB)
   - Méthode list_soft_deleted (admin)

3. **Phase 3: Oban Workers**
   - HardDeletePhotographieWorker (delayed 7 jours)
   - HardDeleteAlbumWorker (delayed 7 jours)
   - HardDeleteProjetWorker (delayed 7 jours)
   - CleanupOrphanPhotosWorker (cron hebdomadaire)

4. **Phase 4: Domain Events**
   - PhotographieSuppriméeSoft (analytics)
   - PhotographieSuppriméeHard (analytics)
   - AlbumSuppriméSoft, AlbumSuppriméHard
   - ProjetSuppriméSoft, ProjetSuppriméHard

5. **Phase 5: Interface Admin**
   - LiveView DeletedItemsLive (listing soft deleted)
   - Bouton "Restaurer" par item
   - Affichage date suppression définitive (countdown)
   - Confirmation restauration

6. **Phase 6: Tests Exhaustifs**
   - Tests soft delete (UPDATE deleted_at)
   - Tests hard delete (suppression fichiers + DB)
   - Tests restauration (annulation job Oban)
   - Tests cleanup orphelines (job hebdomadaire)
   - Tests oubli filtre WHERE deleted_at (détection bugs)
   - Tests performance (queries avec deleted_at IS NULL)

7. **Phase 7: Monitoring**
   - Dashboard Oban (jobs hard delete scheduled/completed)
   - Métriques volumétrie soft deleted (alerte > 10 GB)
   - Analytics taux restauration (suppressions accidentelles)

**Critères de succès:**
- 0 perte données après implémentation (récupération 100%)
- Restauration < 5 secondes (UPDATE + cancel job)
- Cleanup automatique fiable (0 intervention manuelle)
- Performance queries stable (< 1ms impact filtre deleted_at)
- Tests : 100% couverture soft delete / hard delete / restauration
- Monitoring : Dashboard Oban fonctionnel

**Rollback plan:**

Si soft delete inadapté :
1. Identifier pain point : Performance ? Complexité ? Bugs oubli filtre ?
2. Option A : Réduire délai (3 jours au lieu de 7)
   - Réduire espace disque utilisé
   - Garder protection suppressions accidentelles
3. Option B : Supprimer soft delete photographies
   - Garder soft delete albums/projets (impact utilisateur plus fort)
   - Photographies récupérables via backup DB quotidien
4. Option C : Backup DB + suppression immédiate
   - Supprimer toute logique soft delete
   - Récupération via restauration backup (granularité jour)
5. Effort rollback : 1-2 semaines (suppression colonnes, refactor queries)

## Références

- [Soft Deletes Pattern](https://en.wikipedia.org/wiki/Soft_delete)
- [Rails Paranoia Gem](https://github.com/rubysherpas/paranoia) (inspiration pattern)
- [Ecto Soft Delete](https://github.com/ecto/ecto_soft_delete) (librairie alternative)
- [Oban Scheduled Jobs](https://hexdocs.pm/oban/Oban.html#new/2-schedule_in)

Documentation projet :
- docs/ddd/002_photography_context.md (PM-004 : Soft Delete 7 jours)
- docs/business_rules/001_photography_rules.md (Règles suppression)

ADRs liés :
- ADR-041 : Oban Background Jobs
- ADR-032 : Repository Pattern Data Access
- ADR-035 : Ecto.Multi Atomic Transactions

## Notes

### État Actuel (Novembre 2025)

**Implémentation:**
- 🔄 Phase 1 : Migration DB (en cours documentation)
- ⏳ Phases 2-7 : À implémenter

**Soft delete choisi car:**
- Protection suppressions accidentelles (période grâce 7 jours)
- Pattern standard industrie (simplicité, maintenabilité)
- Restauration facile (UPDATE deleted_at = NULL)
- Cleanup automatique (Oban workers)

**Alternatives rejetées:**
- Boolean is_deleted : Redondance avec deleted_at
- Table historique : Complexité restauration
- Event Sourcing : Over-engineering extrême
- Backup DB seul : Récupération complexe, granularité jour

### Évolutions Futures

**Délai configurable:**
- Admin peut choisir délai (3, 7, 14, 30 jours)
- Cas usage : Photos importantes (30 jours), brouillons (3 jours)

**Soft delete utilisateurs:**
- Étendre pattern à table utilisateurs (RGPD)
- Anonymisation données avant hard delete

**Audit trail enrichi:**
- Colonne deleted_by_id (qui a supprimé)
- Table audit_log (historique complet suppressions)

**Interface utilisateur:**
- "Corbeille" dans navigation (listing soft deleted)
- Restauration self-service (pas besoin admin)
- Notification email 2 jours avant hard delete

---

**Participants à la décision:**
- Thibault San - Développeur Solo

**Révisé par:**
- Thibault San - 2025-11-12
