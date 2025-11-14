# 001 - Règles Métier Photography Context

Date: 2025-11-12

Ce document détaille les règles métier du Photography Context. Pour une vue d'ensemble, consulter docs/ddd/002_photography_context.md.

## PM-001 : Unicité Empreinte Photographie

**Catégorie** : Invariant technique

**Description** : Chaque photographie possède une empreinte SHA256 unique calculée depuis le fichier binaire. Cette empreinte permet la détection des doublons.

**Règle** : Une seule photographie peut exister par valeur d'empreinte.

**Implémentation** :
- Calcul SHA256 lors upload
- Index unique sur colonne empreinte (base de données)
- Validation avant insert

**Comportement doublon** :
- Si empreinte existe déjà → Réutiliser photographie existante
- Créer uniquement association album_photographies ou projet_photographies
- Éviter duplication fichiers stockage

**Exemple** :
```
Upload photo1.jpg dans Album A → Empreinte abc123... → Création Photographie
Upload photo2.jpg dans Album B → Empreinte abc123... (identique)
  → Pas de nouvelle Photographie
  → Association album B ← Photographie existante
```

## PM-002 : Partage Photographies N-N

**Catégorie** : Règle structure

**Description** : Une photographie peut appartenir simultanément à plusieurs albums et plusieurs projets.

**Règle** : Relation Many-to-Many via tables de jointure.

**Tables** :
- album_photographies (album_id, photographie_id, position)
- projet_photographies (projet_id, photographie_id, position)

**Conséquences** :
- Suppression album ne supprime pas photographie (juste déréférence)
- Suppression photographie requiert aucune référence

**Cas usage** :
- Photo mariage dans Album "Mariage 2024" ET Projet "Portraits"
- Photo voyage dans Album "Japon 2024" ET Projet "Street Photography"

## PM-003 : Contrainte Suppression Photographie

**Catégorie** : Invariant métier

**Description** : Protection contre perte données. Une photographie ne peut être supprimée si des albums ou projets y font référence.

**Règle** : Suppression bloquée si COUNT(références) > 0.

**Validation** :
```
SELECT COUNT(*) FROM album_photographies WHERE photographie_id = ?
+ SELECT COUNT(*) FROM projet_photographies WHERE photographie_id = ?
Si total > 0 → Exception levée
```

**Message erreur** : "Impossible de supprimer photographie: X références actives (Y albums, Z projets)"

**Workflow suppression** :
1. Retirer photographie de tous albums/projets
2. Attendre nettoyage automatique photos orphelines (job hebdomadaire)
3. OU suppression manuelle une fois orpheline

## PM-004 : Soft Delete 7 Jours

**Catégorie** : Règle protection données

**Description** : Protection contre suppressions accidentelles avec période de récupération de 7 jours.

**Règle** : Soft delete → Hard delete différé.

**Processus** :
1. Demande suppression → UPDATE deleted_at = NOW()
2. Photographie masquée (queries WHERE deleted_at IS NULL)
3. Job Oban programmé +7 jours (HardDeletePhotographieWorker)
4. Après 7 jours → DELETE physique + suppression fichiers

**Restauration** :
- Possible manuellement pendant 7 jours via UPDATE deleted_at = NULL
- Interface admin pour restauration

**Cleanup automatique** :
- Job hebdomadaire : Suppression photographies deleted_at < NOW() - 7 jours
- Suppression variantes (fichiers AVIF)

## PM-005 : Règle Publication Album

**Catégorie** : Invariant métier

**Description** : Conditions obligatoires pour publier un album.

**Conditions** :
1. Minimum 1 photographie associée
2. Titre présent (3-255 caractères)
3. Description présente (7-8191 caractères)
4. Date présente (année ou année+mois, format validé)
5. Slug unique généré depuis titre
6. Toutes photographies en état completed

**Validation** :
```
COUNT(album_photographies WHERE album_id = ?) >= 1
titre IS NOT NULL AND length(titre) BETWEEN 3 AND 255
description IS NOT NULL AND length(description) BETWEEN 7 AND 8191
date_album IS NOT NULL AND date_album ~ '^\\d{4}(-\\d{2})?$'
slug IS NOT NULL AND NOT EXISTS(SELECT 1 FROM albums WHERE slug = ? AND id != ?)
ALL(photographies.etat_traitement = completed)
```

**Si conditions non remplies** :
- Cas photos en processing → statut pending_publication
- Job Oban vérifie périodiquement (toutes les minutes)
- Publication automatique dès que toutes photos completed

**Si validation échoue** :
- Exception levée avec message explicite
- Statut reste draft

## PM-006 : Recommandation Quantité Album

**Catégorie** : Recommandation (non bloquant)

**Description** : Un album de qualité contient généralement entre 5 et 30 photographies.

**Règle** : Validation warning uniquement (pas d'erreur).

**Comportement** :
- < 5 photos → Warning "Album contient peu de photos (X). Recommandé: 5-30."
- > 30 photos → Warning "Album contient beaucoup de photos (X). Recommandé: 5-30."
- Publication autorisée malgré warning

**Objectif** : Guider qualité éditoriale sans contrainte technique.

## PM-007 : Ordre Photographies Album

**Catégorie** : Règle affichage

**Description** : Ordre d'affichage des photographies dans un album.

**Règle par défaut** : Chronologique (date_prise ou date_upload si date_prise NULL).

**Override manuel** : Colonne position dans album_photographies.

**Comportement** :
- Création association → position = MAX(position) + 1 (ajout fin)
- Réorganisation manuelle → UPDATE position selon nouvel ordre
- Affichage : ORDER BY position ASC (si défini), sinon date_prise ASC

**Interface** : Drag & drop dans admin pour réorganisation.

## PM-008 : Couverture Album

**Catégorie** : Règle affichage

**Description** : Photographie représentant visuellement l'album.

**Règle par défaut** : Première photographie de l'album (ORDER BY position ASC LIMIT 1).

**Override manuel** : Sélection photographie spécifique via couverture_id.

**Contrainte** : Couverture doit appartenir à l'album.

**Validation** :
```
EXISTS(
  SELECT 1 FROM album_photographies 
  WHERE album_id = ? AND photographie_id = ?
)
```

**Affichage** : Variante "large" (1920px) utilisée pour vignette galerie.

## PM-009 : Règle Publication Projet

**Catégorie** : Invariant métier

**Description** : Conditions obligatoires pour publier un projet.

**Conditions** :
1. (Minimum 1 photographie OU minimum 1 sous-projet)
2. Titre présent (3-255 caractères)
3. Description présente (7-8191 caractères)
4. Slug unique généré depuis titre
5. Si photos : toutes en état completed
6. Tous parents publiés

**Validation** :
```
(COUNT(projet_photographies) >= 1 OR COUNT(sous_projets) >= 1)
AND titre IS NOT NULL AND length(titre) BETWEEN 3 AND 255
AND description IS NOT NULL AND length(description) BETWEEN 7 AND 8191
AND slug IS NOT NULL AND NOT EXISTS(SELECT 1 FROM projets WHERE slug = ? AND id != ?)
AND ALL(photographies.etat_traitement = completed)
AND ALL(parents.statut = published)
```

**Cascade parents** :
- Si parent non publié → Publication automatique parent (récursif jusqu'à racine)
- Émission événement ProjetPublié pour chaque parent publié
- Transaction atomique : échec rollback toute la cascade

## PM-010 : Hiérarchie Projet Illimitée

**Catégorie** : Règle structure

**Description** : Les projets supportent une hiérarchie d'arbre illimitée en profondeur.

**Règle** : Self-reference via parent_id, profondeur calculée automatiquement.

**Contraintes** :
- Pas de cycle (projet ne peut être son propre parent)
- Détection cycle : trigger base de données + validation application
- Profondeur max recommandée : 10 niveaux (lisibilité)

**Calcul profondeur** :
```
Si parent_id = NULL → profondeur = 0 (racine)
Sinon → profondeur = parent.profondeur + 1
```

**Validation cycle** :
- Parcourir ancêtres jusqu'à racine
- Si projet.id trouvé → Exception "Cycle détecté"

## PM-011 : Contrainte Suppression Projet

**Catégorie** : Invariant métier

**Description** : Un projet ne peut être supprimé si des sous-projets existent.

**Règle** : Suppression bloquée si COUNT(sous_projets) > 0.

**Validation** :
```
SELECT COUNT(*) FROM projets WHERE parent_id = ? AND deleted_at IS NULL
Si count > 0 → Exception levée
```

**Message erreur** : "Impossible de supprimer projet: X sous-projets existent"

**Workflow suppression** :
1. Supprimer tous sous-projets (récursif, feuilles vers racine)
2. Supprimer projet racine
3. OU détacher sous-projets (les rendre racines) puis supprimer parent

## PM-012 : Publication Cascade Parents

**Catégorie** : Règle métier complexe

**Description** : Publication d'un projet entraîne publication automatique de tous ses parents.

**Règle** : Récursion vers racine, publication chaque ancêtre non publié.

**Algorithme** :
```
publier_projet(projet):
  Si projet.parent_id NOT NULL:
    parent = get_projet(projet.parent_id)
    Si parent.statut != published:
      publier_projet(parent)  # Récursion
  
  projet.statut = published
  émettre ProjetPublié
```

**Exemple** :
```
Arbre: Racine (draft) > Branche (draft) > Feuille (draft)
Action: Publier Feuille
Résultat:
  1. Publier Racine (cascade up)
  2. Publier Branche (cascade up)
  3. Publier Feuille
```

**Transaction** : Toute la cascade dans une transaction atomique (Ecto.Multi).

## PM-013 : Dépublication Cascade Enfants

**Catégorie** : Règle cohérence

**Description** : Dépublication d'un projet entraîne dépublication automatique de tous ses enfants.

**Règle** : Récursion vers feuilles, dépublication chaque descendant.

**Algorithme** :
```
dépublier_projet(projet):
  enfants = get_projets(parent_id = projet.id)
  Pour chaque enfant:
    Si enfant.statut = published:
      dépublier_projet(enfant)  # Récursion
  
  projet.statut = unpublished
  émettre ProjetDépublié
```

**Justification** : Cohérence hiérarchie (pas de projet publié avec parent dépublié).

**Exemple** :
```
Arbre: Racine (published) > Branche (published) > Feuille (published)
Action: Dépublier Racine
Résultat:
  1. Dépublier Feuille (cascade down)
  2. Dépublier Branche (cascade down)
  3. Dépublier Racine
```

## PM-014 : Génération Slug Album

**Catégorie** : Règle technique

**Description** : Slug unique généré automatiquement depuis le titre de l'album.

**Règle** : Normalisation titre → slug unique avec suffixe numérique si collision.

**Processus génération** :
1. Convertir titre en minuscules
2. Remplacer caractères accentués (é → e, à → a, etc.)
3. Remplacer caractères non alphanumériques par tirets
4. Supprimer tirets multiples consécutifs
5. Supprimer tirets début/fin

**Exemple** :
```
"Mon Album 2024!" → "mon-album-2024"
"Été à la Mer" → "ete-a-la-mer"
"Tokyo   Street" → "tokyo-street"
```

**Gestion collision** :
```
SELECT COUNT(*) FROM albums WHERE slug = ?
Si count > 0 → Ajouter suffixe -2, -3, etc.

Exemple:
  "mon-album-2024" existe → "mon-album-2024-2"
  "mon-album-2024-2" existe → "mon-album-2024-3"
```

**Validation** : Slug doit être unique (index unique base de données).

## PM-015 : Génération Slug Projet

**Catégorie** : Règle technique

**Description** : Slug unique généré automatiquement depuis le titre du projet.

**Règle** : Identique à PM-014 (génération slug album).

**Processus** : Même normalisation et gestion collision.

**Particularité hiérarchie** : Slug projet indépendant de sa position dans l'arbre.

**Exemple** :
```
Projet racine "Portraits" → slug "portraits"
Sous-projet "Portraits" (sous "2024") → slug "portraits-2" (collision)
```

## PM-016 : États Traitement Photographie

**Catégorie** : Règle technique

**Description** : Machine à états pour le traitement asynchrone des variantes d'images.

**États** :
- pending : Photo uploadée, traitement non démarré
- processing : Génération variantes en cours
- completed : Toutes variantes générées avec succès
- failed : Échec génération après retries

**Transitions** :
```
pending → processing (job ImageVariantWorker démarre)
processing → completed (succès génération 3 variantes)
processing → failed (échec après 3 tentatives)
failed → processing (retry manuel possible)
```

**Règle publication** : Album/Projet publication bloquée si photos pas en état completed.

**Validation état** :
```
SELECT COUNT(*) FROM photographies
JOIN album_photographies ON photographies.id = album_photographies.photographie_id
WHERE album_id = ? AND etat_traitement != 'completed'

Si count > 0 → Statut pending_publication (voir PM-005)
```

**Durée traitement moyenne** : 5-30 secondes par photo selon taille.

## PM-017 : Génération Variantes Images

**Catégorie** : Règle technique

**Description** : Traitement asynchrone génération variantes WebP et AVIF depuis image originale.

**Variantes générées** : Voir PM-032 pour formats et qualités détaillés.
- thumbnail (400px) : WebP qualité 75
- medium (1200px) : WebP qualité 80  
- large (1920px) : AVIF qualité 90
- original : AVIF qualité 95

**Processus** :
1. Upload photo originale → Stockage LocalStorage ou S3
2. Calcul empreinte SHA256
3. INSERT photographie (etat_traitement = pending)
4. Job Oban ImageVariantWorker enqueued
5. Job génère 4 variantes (2 WebP + 2 AVIF) via Vix
6. Stockage variantes (chemin: photos/{empreinte}/{taille}.{webp|avif})
7. UPDATE etat_traitement = completed

**Échec traitement** :
- Retry automatique (max 5 tentatives, backoff exponentiel) - PM-029
- Si 5 échecs → etat_traitement = failed
- Notification admin (log erreur)

**Cas particulier** : Si format entrée non supporté par Vix → failed immédiatement.

**Référence** : PM-032 pour détails formats et stockage.

## PM-018 : Validation Format Fichier Upload

**Catégorie** : Règle sécurité

**Description** : Validation stricte format et taille fichiers uploadés.

**Formats acceptés** :
- JPEG (image/jpeg)
- PNG (image/png)
- AVIF (image/avif)
- WebP (image/webp)

**Validation double** :
1. Extension fichier (.jpg, .jpeg, .png, .avif, .webp)
2. Magic bytes (vérification type MIME réel)

**Taille maximum** : 50 MB par fichier.

**Processus validation** :
```
1. Vérifier extension fichier
2. Lire premiers bytes fichier
3. Vérifier magic bytes correspond type MIME
4. Vérifier taille < 50 MB
```

**Magic bytes** :
- JPEG : FF D8 FF
- PNG : 89 50 4E 47
- WebP : 52 49 46 46 ... 57 45 42 50

**Erreurs** :
- Extension invalide → "Format non supporté. Formats acceptés: JPEG, PNG, AVIF, WebP"
- Magic bytes mismatch → "Fichier corrompu ou type incorrect"
- Taille > 50 MB → "Fichier trop volumineux. Taille max: 50 MB"

**Sécurité** : Protection contre upload fichiers malveillants déguisés.

## PM-019 : Cleanup Photos Orphelines

**Catégorie** : Règle maintenance

**Description** : Suppression automatique photographies sans références actives.

**Règle** : Job hebdomadaire détecte et soft delete photos orphelines.

**Définition orpheline** :
```
SELECT id FROM photographies
WHERE deleted_at IS NULL
AND id NOT IN (SELECT photographie_id FROM album_photographies)
AND id NOT IN (SELECT photographie_id FROM projet_photographies)
```

**Processus** :
1. Job CleanupOrphanPhotosWorker (cron: weekly, dimanche 3h)
2. Détection photos orphelines
3. Soft delete (UPDATE deleted_at = NOW())
4. Après 7 jours → hard delete automatique (PM-004)

**Justification** : Éviter accumulation fichiers inutilisés (coût stockage).

**Exception** : Photos uploadées < 24h non considérées orphelines (délai association).

## PM-020 : Validation Titre Album/Projet

**Catégorie** : Validation Value Object

**Description** : Contraintes sur le titre des albums et projets.

**Règle** :
- Longueur : 3-255 caractères
- Trimmed (espaces début/fin supprimés)
- Non vide après trim

**Validation** :
```
titre_trimmed = String.trim(titre)
length(titre_trimmed) >= 3 AND length(titre_trimmed) <= 255
```

**Erreurs** :
- < 3 caractères → "Titre trop court (minimum 3 caractères)"
- > 255 caractères → "Titre trop long (maximum 255 caractères)"
- Vide après trim → "Titre requis"

**Normalisation** : Trim automatique avant validation et stockage.

## PM-021 : Validation Description Album/Projet

**Catégorie** : Validation Value Object

**Description** : Contraintes sur la description des albums et projets.

**Règle** :
- Longueur : 7-8191 caractères
- Trimmed (espaces début/fin supprimés)
- Format : Markdown supporté

**Validation** :
```
description_trimmed = String.trim(description)
length(description_trimmed) >= 7 AND length(description_trimmed) <= 8191
```

**Erreurs** :
- < 7 caractères → "Description trop courte (minimum 7 caractères)"
- > 8191 caractères → "Description trop longue (maximum 8191 caractères)"

**Affichage** : Description convertie Markdown → HTML lors affichage public.

**Sécurité** : Sanitization HTML pour éviter XSS (bibliothèque Earmark).

## PM-022 : Format Date Album

**Catégorie** : Validation Value Object

**Description** : Format date album flexible (année seule ou année+mois).

**Formats acceptés** :
- Année seule : "2024"
- Année + mois : "2024-06"

**Validation regex** :
```
^\\d{4}(-\\d{2})?$

Exemples valides:
  - "2024"
  - "2024-01"
  - "2024-12"

Exemples invalides:
  - "24" (année incomplète)
  - "2024-13" (mois invalide)
  - "2024-6" (mois non zero-padded)
  - "2024-06-15" (jour non supporté)
```

**Validation mois** : Si mois présent, vérifier 01-12.

**Affichage** :
- "2024" → "2024"
- "2024-06" → "Juin 2024" (locale fr/en selon utilisateur)

**Tri chronologique** : Ordre DESC par défaut (plus récents en premier).

## PM-023 : Publication Différée Album/Projet

**Catégorie** : Règle fonctionnelle

**Description** : Programmation publication automatique à date future.

**Règle** : Si date_publication future → statut scheduled.

**États** :
- draft : Brouillon
- scheduled : Programmé (date future)
- published : Publié
- unpublished : Dépublié

**Processus** :
1. Création album/projet (statut draft)
2. Programmation date_publication future
3. Validation règles publication (PM-005 ou PM-009)
4. UPDATE statut = scheduled, date_publication = ?
5. Job Oban PublishScheduledContentWorker (cron: hourly)
6. Job détecte contenus WHERE statut = scheduled AND date_publication <= NOW()
7. Publication automatique (validation règles métier)
8. UPDATE statut = published

**Annulation programmation** :
- UPDATE date_publication = NULL, statut = draft

**Validation date** : date_publication doit être dans le futur (> NOW()).

## PM-024 : Cache Invalidation Projet

**Catégorie** : Règle performance

**Description** : Invalidation cache lors modifications hiérarchie projets.

**Règle** : Modifications projet invalident cache arbre complet et breadcrumb.

**Clés cache** :
- projet:{id}:arbre : Arbre complet (parents + enfants)
- projet:{id}:breadcrumb : Fil d'Ariane
- projets:racines : Liste projets racines publiés

**Opérations déclenchant invalidation** :
- Création projet
- Modification parent_id (déplacement)
- Publication/dépublication projet
- Suppression projet
- Ajout/retrait sous-projet

**Processus** :
```
# Invalider projet modifié
Cachex.del(:portfolio_cache, "projet:#{projet_id}:arbre")
Cachex.del(:portfolio_cache, "projet:#{projet_id}:breadcrumb")

# Invalider tous ancêtres (cascade up)
ancetres = ProjetHierarchyService.get_ancetres(projet_id)
Pour chaque ancetre:
  Cachex.del(:portfolio_cache, "projet:#{ancetre.id}:arbre")
  Cachex.del(:portfolio_cache, "projet:#{ancetre.id}:breadcrumb")

# Invalider liste racines si projet racine
Si parent_id IS NULL:
  Cachex.del(:portfolio_cache, "projets:racines")
```

**TTL cache** : 1 heure par défaut (invalidation proactive prioritaire).

## PM-025 : Suppression Cascade Photos Orphelines

**Catégorie** : Règle métier

**Description** : Suppression album entraîne soft delete photos uniquement si orphelines.

**Règle** : Lors suppression album, supprimer photos SEULEMENT si aucune autre référence.

**Processus suppression album** :
```
1. Soft delete album (UPDATE deleted_at = NOW())
2. Pour chaque photo associée :
   a. Compter références actives :
      SELECT COUNT(*) FROM (
        SELECT photographie_id FROM album_photographies 
        WHERE photographie_id = ? AND album_id IN (SELECT id FROM albums WHERE deleted_at IS NULL)
        UNION
        SELECT photographie_id FROM projet_photographies 
        WHERE photographie_id = ? AND projet_id IN (SELECT id FROM projets WHERE deleted_at IS NULL)
      )
   b. Si count = 0 → Soft delete photo (orpheline)
   c. Si count > 0 → Conserver photo (références actives)
3. Job CleanupOrphanPhotosWorker vérifie périodiquement (PM-019)
```

**Justification** :
- Protection données partagées (photo dans multiple albums/projets)
- Nettoyage automatique différé (via PM-019)
- Cohérence avec PM-002 (partage N-N)

**Exemple** :
```
Photo A dans Album1 et Projet1
Suppression Album1 → Photo A conservée (référence Projet1)

Photo B uniquement dans Album2
Suppression Album2 → Photo B soft deleted (orpheline)
```

## PM-026 : Published_at Défini Automatiquement

**Catégorie** : Règle technique

**Description** : Date publication définie automatiquement lors publication (pas boolean).

**Règle** : Colonne published_at (DateTime nullable), NULL = non publié, valeur = publié.

**Processus publication** :
```
# Publication
UPDATE albums SET published_at = NOW() WHERE id = ?

# Dépublication
UPDATE albums SET published_at = NULL WHERE id = ?

# Vérification statut
SELECT * FROM albums WHERE published_at IS NOT NULL  -- Publiés
SELECT * FROM albums WHERE published_at IS NULL      -- Non publiés
```

**Avantages** :
- Traçabilité : Date exacte première publication
- Pas de colonne status séparée (simplification)
- Tri chronologique publications (ORDER BY published_at DESC)

**Validation publication** : Toutes règles PM-005 doivent être validées avant SET published_at.

**Historique** : Première publication seulement (pas de mise à jour si republication).

## PM-027 : Préservation Ratio Aspect

**Catégorie** : Règle technique

**Description** : Redimensionnement préserve ratio aspect original (pas de déformation).

**Règle** : Largeur maximum respectée, hauteur calculée proportionnellement.

**Algorithme redimensionnement** :
```
# Variante thumbnail (400px max)
Si largeur_originale > 400:
  nouvelle_largeur = 400
  nouvelle_hauteur = (hauteur_originale * 400) / largeur_originale
Sinon:
  Conserver dimensions originales

# Idem pour medium (1200px) et large (1920px)
```

**Pas de crop** : Image complète préservée, pas de recadrage.

**Orientation** : Portrait et paysage gérés automatiquement.

**Exemple** :
```
Original : 3000×2000 (ratio 3:2)
Thumbnail : 400×267 (ratio 3:2 préservé)
Medium : 1200×800 (ratio 3:2 préservé)
Large : 1920×1280 (ratio 3:2 préservé)
```

**Implémentation** : Vix.Operation.resize avec option preserve_aspect_ratio.

## PM-028 : Extraction Métadonnées EXIF

**Catégorie** : Règle technique

**Description** : Extraction métadonnées EXIF lors upload pour informations photographiques.

**Métadonnées extraites** :
- Appareil (camera_make, camera_model)
- Paramètres prise de vue (iso, aperture, shutter_speed, focal_length)
- Date prise de vue (date_prise)
- Géolocalisation (latitude, longitude) si présente

**Stockage** : Colonne metadata (JSONB) dans table photographies.

**Exemple** :
```json
{
  "camera_make": "Canon",
  "camera_model": "EOS R5",
  "iso": 800,
  "aperture": "f/2.8",
  "shutter_speed": "1/500",
  "focal_length": "85mm",
  "date_prise": "2024-06-15T14:30:00Z",
  "latitude": 48.8566,
  "longitude": 2.3522
}
```

**Processus** :
1. Upload photo originale
2. Lecture EXIF via Vix ou Exiftool
3. Extraction champs pertinents
4. Stockage metadata JSONB
5. Utilisation affichage galerie (info photo)

**Nullable** : Métadonnées optionnelles (certains formats ne contiennent pas EXIF).

**Référence** : ADR existante sur extraction EXIF.

## PM-029 : Timeout Traitement Variante

**Catégorie** : Règle technique

**Description** : Timeout maximum 60 secondes par variante pour éviter blocage worker.

**Règle** : Génération variante limitée à 60 secondes, échec si dépassement.

**Configuration Oban** :
```elixir
def perform(%Job{args: %{"photo_id" => photo_id}}) do
  # Timeout global worker : 180s (3 variantes × 60s)
  :ok
end

# config/config.exs
config :portfolio, Oban,
  queues: [image_processing: [limit: 3, timeout: 180_000]]
```

**Timeout par variante** :
```elixir
Task.async(fn ->
  :timer.tc(fn -> generer_variante(photo, :thumbnail) end)
end)
|> Task.await(60_000)  # 60 secondes max
```

**Comportement timeout** :
- Si timeout atteint → Exception TimeoutError
- Retry automatique (PM-017, max 5 tentatives)
- Si 5 timeouts → etat_traitement = failed

**Justification** :
- Éviter worker bloqué indéfiniment
- Libérer ressources pour autres jobs
- Photos très volumineuses (>50 MB) peuvent prendre temps

## PM-030 : Concurrency Maximum Images

**Catégorie** : Règle performance

**Description** : Maximum 3 images traitées simultanément pour éviter surcharge CPU.

**Règle** : Queue Oban image_processing limitée à 3 workers concurrents.

**Configuration Oban** :
```elixir
# config/config.exs
config :portfolio, Oban,
  queues: [
    default: 10,
    image_processing: [limit: 3],  # Max 3 workers
    mailers: 5
  ]
```

**Justification** :
- Traitement images très CPU-intensif (compression AVIF)
- Éviter saturation serveur
- Permettre autres opérations (web requests, emails)

**Comportement** :
- 10 photos uploadées → 3 traitées en parallèle, 7 en attente
- Worker libéré → photo suivante queue démarrée
- Ordre : FIFO (first in, first out)

**Monitoring** : Telemetry Oban pour surveiller longueur queue.

## PM-031 : Types Albums

**Catégorie** : Règle métier

**Description** : Albums catégorisés par type (enum strict).

**Types autorisés** :
- personal : Albums personnels
- professional : Travail professionnel
- project : Projets spécifiques

**Règle** : Type obligatoire lors création album, modifiable.

**Validation** :
```elixir
@valid_types [:personal, :professional, :project]

def changeset(album, attrs) do
  album
  |> cast(attrs, [:type, ...])
  |> validate_required([:type])
  |> validate_inclusion(:type, @valid_types)
end
```

**Affichage** : Filtrage galerie par type.

**Défaut** : Type personal si non spécifié.

## PM-032 : Formats Variantes WebP et AVIF

**Catégorie** : Règle technique

**Description** : Génération variantes optimisées selon usage (légèreté vs qualité).

**Formats et qualités** :
- thumbnail (400px) : WebP qualité 75 (légèreté)
- medium (1200px) : WebP qualité 80 (légèreté)
- large (1920px) : AVIF qualité 90 (qualité)
- original : AVIF qualité 95 (qualité maximale)

**Justification** :
- WebP : Support universel, compression rapide, léger (miniatures)
- AVIF : Compression supérieure, qualité maximale (grandes images)
- Balance performance (chargement rapide miniatures) / qualité (zoom grandes images)

**Stockage** :
```
photos/{empreinte}/thumbnail.webp
photos/{empreinte}/medium.webp
photos/{empreinte}/large.avif
photos/{empreinte}/original.avif
```

**Fallback navigateur** :
```html
<picture>
  <source srcset="/photos/{hash}/large.avif" type="image/avif">
  <source srcset="/photos/{hash}/large.webp" type="image/webp">
  <img src="/photos/{hash}/large.jpg" alt="...">
</picture>
```

**Mise à jour PM-017** : Cette règle remplace PM-017 (3 AVIF) par WebP + AVIF.

## Documents Liés

- Photography Context : docs/ddd/002_photography_context.md
- Vue d'ensemble : docs/ddd/001_vue_ensemble.md
- Event Storming : tmp/event_storming_complet.md
