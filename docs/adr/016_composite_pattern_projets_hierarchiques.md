# ADR-016: Composite Pattern pour Projets Photographiques Hiérarchiques

Statut: Accepté
Date: 2025-11-12

## Contexte

Le portfolio photographique actuel gère des albums datés représentant des événements ponctuels (mariages, voyages, shootings). Cette structure convient pour des collections temporelles mais ne répond pas au besoin de regroupements thématiques long-terme.

### Besoin Métier

**Collections thématiques illimitées** :
- Projets photographiques sans contrainte temporelle (Photo de rue, Portrait, Architecture)
- Hiérarchie de sous-projets pour organisation fine (Photo de rue > Nighthawks > Japon > Tokyo)
- Profondeur variable selon la granularité souhaitée (2 niveaux, 5 niveaux, 10 niveaux)
- Exemple concret : "Photo de rue" (racine) → "Nighthawks" (inspiration Hopper) → "Japon" (pays) → "Tokyo" (ville) → "Shinjuku" (quartier)

**Différences Album vs Projet** :
- **Album** : Date obligatoire (année ou année+mois), événement ponctuel, structure plate
- **Projet** : Date optionnelle, thématique long-terme, structure hiérarchique illimitée

**Partage de photographies** :
- Une photographie peut appartenir à un album ET un projet simultanément
- Relation N-N via tables de jointure (album_photographies, projet_photographies)
- Exemple : Photo mariage dans Album "Mariage 2024" ET Projet "Portraits"

### Besoins Fonctionnels

**Navigation hiérarchique** :
- Affichage arbre projets complet (racines avec enfants récursifs)
- Breadcrumb : chemin racine → parent → actuel
- Fil d'Ariane : "Photo de rue > Nighthawks > Japon > Tokyo"

**Publication cohérente** :
- Un projet doit être publié pour publier ses enfants
- Publication enfant déclenche publication automatique de tous parents (cascade up)
- Exemple : Publier "Tokyo" → auto-publication "Japon", "Nighthawks", "Photo de rue"

**Dépublication cohérente** :
- Dépublication parent dépublie tous enfants (cascade down)
- Pas de projet publié avec parent dépublié (règle cohérence)

**Gestion cycle de vie** :
- Déplacement projet : changement de parent ou devenir racine
- Suppression projet : bloquée si enfants existent (protection données)
- Détection cycles : impossible d'attacher projet à lui-même ou descendant

### Contraintes Techniques

**Performance** :
- Construction arbre complet pour navigation (potentiellement 100+ projets)
- Requêtes récursives coûteuses (parcours ancêtres, parcours descendants)
- Cache nécessaire (invalidation lors publication/attachement)

**Complexité** :
- Détection cycles obligatoire (validation DB + application)
- Transactions atomiques pour cascade publication/dépublication
- Calcul profondeur automatique (dénormalisation performance)

## Options Considérées

### Option 1: Composite Pattern avec Self-Reference

**Description:**
Structure récursive utilisant self-reference (parent_id) pour hiérarchie illimitée. Chaque Projet peut contenir des photographies ET des sous-projets.

**Modèle de données:**
```sql
CREATE TABLE projets (
  id UUID PRIMARY KEY,
  titre VARCHAR(255) NOT NULL,
  description TEXT NOT NULL,
  slug VARCHAR(255) UNIQUE NOT NULL,
  statut VARCHAR(30) NOT NULL, -- draft, published, unpublished
  parent_id UUID REFERENCES projets(id) ON DELETE RESTRICT,
  profondeur INTEGER NOT NULL DEFAULT 0, -- dénormalisé
  couverture_id UUID REFERENCES photographies(id),
  utilisateur_id UUID REFERENCES utilisateurs(id),
  deleted_at TIMESTAMP,
  inserted_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  
  CHECK (id != parent_id) -- Pas de cycle direct
);

CREATE INDEX idx_projets_parent ON projets(parent_id) 
  WHERE deleted_at IS NULL;
CREATE INDEX idx_projets_profondeur ON projets(profondeur) 
  WHERE deleted_at IS NULL;
```

**Interface uniforme (Aggregate):**
```elixir
defmodule Portfolio.Photography.Projet do
  defstruct [:id, :titre, :description, :slug, :statut, 
             :parent_id, :profondeur, :photographies, :sous_projets]
  
  # Un Projet peut contenir photographies (feuilles)
  def ajouter_photographie(projet, photographie_id), do: # ...
  
  # Un Projet peut contenir sous-projets (composites)
  def attacher_sous_projet(projet, sous_projet_id), do: # ...
  
  # Interface uniforme (publication)
  def peut_etre_publie?(projet), do: # ...
  def publier(projet), do: # ...
end
```

**Avantages:**
- Hiérarchie illimitée (profondeur variable selon besoin)
- Interface uniforme (Projet traite photographies et sous-projets identiquement)
- Scalabilité (ajout niveaux sans modification schéma)
- Flexibilité (déplacement projets, réorganisation arbre)
- Pattern reconnu (Gang of Four, bien documenté)

**Inconvénients:**
- Requêtes récursives coûteuses (parcours arbre sans optimisation)
- Détection cycles complexe (parcours ancêtres)
- Cache nécessaire (performance dégradée sans cache)
- Transactions complexes (cascade publication/dépublication)

**Effort estimé:** Moyen (pattern standard mais requêtes récursives)

**Risques:**
- Performance requêtes récursives [Probabilité: Moyenne, Impact: Moyen]
  - Mitigation : Cache arbre complet (10 minutes TTL), profondeur dénormalisée
- Complexité détection cycles [Probabilité: Faible, Impact: Élevé]
  - Mitigation : Trigger DB + validation application (double sécurité)
- Transactions cascade longues [Probabilité: Faible, Impact: Moyen]
  - Mitigation : Ecto.Multi, timeout 30 secondes, limitation profondeur max recommandée

---

### Option 2: Materialized Path (Chemin matérialisé)

**Description:**
Stockage du chemin complet depuis racine dans une colonne (ex: "/1/5/12/").

**Modèle de données:**
```sql
CREATE TABLE projets (
  id UUID PRIMARY KEY,
  titre VARCHAR(255) NOT NULL,
  path TEXT NOT NULL, -- Ex: "/uuid-racine/uuid-parent/uuid-actuel/"
  -- ...
);

CREATE INDEX idx_projets_path ON projets USING gin(path gin_trgm_ops);
```

**Requêtes simplifiées:**
```sql
-- Tous ancêtres
SELECT * FROM projets WHERE '/uuid-actuel/' LIKE path || '%';

-- Tous descendants
SELECT * FROM projets WHERE path LIKE '/uuid-actuel/%';
```

**Avantages:**
- Requêtes ancêtres/descendants très rapides (index GIN)
- Pas de récursion (queries simples)
- Breadcrumb trivial (parsing path)

**Inconvénients:**
- Mise à jour coûteuse (déplacement projet = UPDATE tous descendants)
- Taille colonne path augmente avec profondeur
- Complexité implémentation (parsing path, invalidation)
- Pas idiomatique PostgreSQL (pattern workaround limites DB)

**Effort estimé:** Élevé (complexité implémentation UPDATE cascade)

**Risques:**
- UPDATE cascade lent [Probabilité: Élevée, Impact: Moyen]
  - Déplacement projet avec 50 descendants = 50 UPDATEs
- Parsing path error-prone [Probabilité: Moyenne, Impact: Faible]

**Décision:** Rejeté car complexité implémentation > bénéfice performance (cache suffit pour Option 1).

---

### Option 3: Closure Table (Table de Fermeture)

**Description:**
Table dédiée stockant toutes relations ancêtre-descendant (y compris transitives).

**Modèle de données:**
```sql
CREATE TABLE projets (
  id UUID PRIMARY KEY,
  titre VARCHAR(255) NOT NULL,
  -- ...
);

CREATE TABLE projet_closure (
  ancetre_id UUID REFERENCES projets(id) ON DELETE CASCADE,
  descendant_id UUID REFERENCES projets(id) ON DELETE CASCADE,
  profondeur INTEGER NOT NULL, -- Distance ancêtre → descendant
  PRIMARY KEY (ancetre_id, descendant_id)
);

-- Auto-relation (projet est son propre ancêtre à profondeur 0)
INSERT INTO projet_closure (ancetre_id, descendant_id, profondeur)
VALUES (projet_id, projet_id, 0);
```

**Requêtes simplifiées:**
```sql
-- Tous ancêtres
SELECT p.* FROM projets p
JOIN projet_closure pc ON pc.ancetre_id = p.id
WHERE pc.descendant_id = ?;

-- Tous descendants
SELECT p.* FROM projets p
JOIN projet_closure pc ON pc.descendant_id = p.id
WHERE pc.ancetre_id = ?;
```

**Avantages:**
- Requêtes ancêtres/descendants très rapides (joins simples)
- Pas de récursion
- Profondeur stockée explicitement

**Inconvénients:**
- Table closure volumineuse (n² relations pour n projets dans un arbre)
- INSERT/UPDATE/DELETE complexes (maintenance relations transitives)
- Sur-ingénierie pour use case (< 100 projets prévus)
- Pas idiomatique (pattern rarement utilisé)

**Effort estimé:** Très élevé (maintenance closure table complexe)

**Décision:** Rejeté car over-engineering pour volumétrie attendue (< 100 projets).

---

### Option 4: Niveaux Fixes (parent_id + grandparent_id + ...)

**Description:**
Colonnes dédiées pour chaque niveau hiérarchique (parent, grand-parent, arrière-grand-parent, etc.).

**Modèle de données:**
```sql
CREATE TABLE projets (
  id UUID PRIMARY KEY,
  titre VARCHAR(255) NOT NULL,
  parent_id UUID,
  grandparent_id UUID,
  great_grandparent_id UUID,
  -- Limité à 5 niveaux max
);
```

**Avantages:**
- Requêtes simples (pas de récursion)
- Performance optimale (joins directs)

**Inconvénients:**
- Profondeur limitée (5 niveaux max)
- Non extensible (ajout niveau = migration schéma)
- Rigidité (use case nécessite hiérarchie illimitée)
- Anti-pattern (violation normalisation)

**Effort estimé:** Faible (implémentation simple)

**Décision:** Rejeté car profondeur limitée incompatible avec besoin hiérarchie illimitée.

---

## Décision

L'option choisie est: **Option 1 - Composite Pattern avec Self-Reference**

### Justification

**1. Hiérarchie Illimitée (Critique)**

Le besoin métier nécessite profondeur variable :
- Projets simples : 2 niveaux ("Photo de rue" > "Japon")
- Projets complexes : 5+ niveaux ("Photo de rue" > "Nighthawks" > "Japon" > "Tokyo" > "Shinjuku")
- Évolutivité : Ajout niveaux sans modification schéma

Options 2, 3, 4 limitent ou complexifient hiérarchie profonde.

**2. Flexibilité (Très important)**

Composite Pattern permet réorganisation arbre :
- Déplacement projet vers autre parent
- Détachement projet (devenir racine)
- Suppression projet (si aucun enfant)

Materialized Path et Closure Table complexifient ces opérations.

**3. Simplicité Implémentation (Important)**

Self-reference est pattern standard :
- Schéma simple (colonne parent_id)
- Contraintes DB naturelles (FOREIGN KEY, CHECK)
- Détection cycles via trigger (pattern connu)

Materialized Path et Closure Table nécessitent logique custom complexe.

**4. Performance Acceptable avec Cache (Souhaitable)**

Requêtes récursives coûteuses mais mitigées :
- Cache arbre complet (TTL 10 minutes)
- Profondeur dénormalisée (filtre rapide par niveau)
- Volumétrie faible (< 100 projets prévus)

Closure Table over-engineering pour volumétrie attendue.

**5. Pattern Reconnu (Souhaitable)**

Composite Pattern est Gang of Four pattern :
- Documentation abondante
- Implémentations Elixir existantes
- Maintenabilité long terme

### Implémentation Tactique

**Aggregate Projet:**

```elixir
defmodule Portfolio.Photography.Projet do
  use Ecto.Schema
  
  schema "projets" do
    field :titre, :string
    field :description, :string
    field :slug, :string
    field :statut, Ecto.Enum, values: [:draft, :published, :unpublished]
    field :profondeur, :integer, default: 0
    
    belongs_to :parent, Portfolio.Photography.Projet
    has_many :sous_projets, Portfolio.Photography.Projet, foreign_key: :parent_id
    many_to_many :photographies, Portfolio.Photography.Photographie,
      join_through: "projet_photographies"
    
    timestamps()
  end
  
  # Interface uniforme Composite
  def peut_etre_publie?(projet) do
    with true <- a_du_contenu?(projet),
         true <- photos_traitees?(projet),
         true <- parents_publies?(projet) do
      :ok
    end
  end
  
  defp a_du_contenu?(projet) do
    length(projet.photographies) >= 1 || length(projet.sous_projets) >= 1
  end
  
  defp parents_publies?(projet) do
    case projet.parent_id do
      nil -> true
      parent_id ->
        parent = Repo.get!(Projet, parent_id)
        parent.statut == :published && parents_publies?(parent)
    end
  end
end
```

**ProjetRepository (Requêtes Récursives):**

```elixir
defmodule Portfolio.Photography.ProjetRepository do
  
  def get_racines_publiees do
    from(p in Projet,
      where: is_nil(p.parent_id),
      where: p.statut == :published,
      where: is_nil(p.deleted_at),
      order_by: [asc: p.titre]
    )
    |> Repo.all()
  end
  
  def get_ancetres(projet) do
    # Récursion Elixir (pas SQL)
    case projet.parent_id do
      nil -> []
      parent_id ->
        parent = get(parent_id)
        [parent | get_ancetres(parent)]
    end
  end
  
  def attacher_a_parent(projet, nouveau_parent_id) do
    if cree_cycle?(projet.id, nouveau_parent_id) do
      {:error, :cycle_detecte}
    else
      nouveau_parent = get(nouveau_parent_id)
      nouvelle_profondeur = nouveau_parent.profondeur + 1
      
      projet
      |> Projet.changeset(%{
        parent_id: nouveau_parent_id, 
        profondeur: nouvelle_profondeur
      })
      |> Repo.update()
      |> case do
        {:ok, projet} ->
          mettre_a_jour_profondeur_enfants(projet.id, nouvelle_profondeur)
          {:ok, projet}
        error -> error
      end
    end
  end
  
  defp cree_cycle?(projet_id, nouveau_parent_id) do
    # Parcourir ancêtres du nouveau parent
    parent = get(nouveau_parent_id)
    cree_cycle_recursive?(projet_id, parent)
  end
  
  defp cree_cycle_recursive?(projet_id, nil), do: false
  defp cree_cycle_recursive?(projet_id, %{id: id}) when id == projet_id, do: true
  defp cree_cycle_recursive?(projet_id, %{parent_id: nil}), do: false
  defp cree_cycle_recursive?(projet_id, %{parent_id: parent_id}) do
    parent = get(parent_id)
    cree_cycle_recursive?(projet_id, parent)
  end
end
```

**ProjetPublicationService (Cascade Up):**

```elixir
defmodule Portfolio.Photography.Services.ProjetPublicationService do
  
  def publier(projet_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:projet, fn repo, _ ->
      {:ok, repo.get!(Projet, projet_id) |> repo.preload(:parent)}
    end)
    |> Ecto.Multi.run(:validation, fn _, %{projet: projet} ->
      Projet.peut_etre_publie?(projet)
    end)
    |> Ecto.Multi.run(:publier_parents, fn _, %{projet: projet} ->
      publier_parents_si_necessaire(projet)
    end)
    |> Ecto.Multi.update(:update_projet, fn %{projet: projet} ->
      Projet.changeset(projet, %{statut: :published})
    end)
    |> Ecto.Multi.run(:event, fn _, %{update_projet: projet} ->
      DomainEvents.publish(:projet_published, %{
        projet_id: projet.id,
        titre: projet.titre,
        slug: projet.slug,
        url_public: "/photography/projects/#{projet.slug}"
      })
      {:ok, :published}
    end)
    |> Repo.transaction()
  end
  
  defp publier_parents_si_necessaire(projet) do
    case projet.parent_id do
      nil -> {:ok, []}
      parent_id ->
        parent = Repo.get!(Projet, parent_id)
        case parent.statut do
          :published -> {:ok, []}
          _ -> publier(parent_id) # Récursion cascade
        end
    end
  end
end
```

**Trigger DB (Détection Cycles):**

```sql
CREATE OR REPLACE FUNCTION check_projet_cycle()
RETURNS TRIGGER AS $$
DECLARE
  current_id UUID;
  depth INTEGER := 0;
  max_depth INTEGER := 100;
BEGIN
  IF NEW.parent_id IS NULL THEN
    RETURN NEW;
  END IF;
  
  current_id := NEW.parent_id;
  
  WHILE current_id IS NOT NULL AND depth < max_depth LOOP
    IF current_id = NEW.id THEN
      RAISE EXCEPTION 'Cycle détecté dans hiérarchie projets';
    END IF;
    
    SELECT parent_id INTO current_id FROM projets WHERE id = current_id;
    depth := depth + 1;
  END LOOP;
  
  IF depth >= max_depth THEN
    RAISE EXCEPTION 'Hiérarchie projets trop profonde (max: %)', max_depth;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_projet_cycle_trigger 
BEFORE INSERT OR UPDATE ON projets
FOR EACH ROW EXECUTE FUNCTION check_projet_cycle();
```

**Cache Performance:**

```elixir
defmodule Portfolio.Photography.Services.ProjetHierarchyService do
  
  def construire_arbre_complet do
    case Cachex.get(:portfolio_cache, "projets_hierarchy") do
      {:ok, nil} ->
        arbre = build_tree()
        Cachex.put(:portfolio_cache, "projets_hierarchy", arbre, ttl: :timer.minutes(10))
        arbre
      {:ok, arbre} ->
        arbre
    end
  end
  
  defp build_tree do
    racines = ProjetRepository.get_racines_publiees()
    Enum.map(racines, &construire_noeud/1)
  end
  
  defp construire_noeud(projet) do
    enfants = ProjetRepository.get_enfants(projet.id)
    
    %{
      projet: projet,
      enfants: Enum.map(enfants, &construire_noeud/1)
    }
  end
end
```

**Invalidation Cache:**

```elixir
defmodule Portfolio.Photography.EventHandlers.ProjetPublishedHandler do
  use GenServer
  
  def handle_info({:projet_published, _data}, state) do
    Cachex.del(:portfolio_cache, "projets_hierarchy")
    {:noreply, state}
  end
end
```

### Trade-offs Acceptés

**Requêtes récursives** :
- Coût : Parcours arbre potentiellement coûteux (profondeur > 5)
- Mitigation : Cache arbre complet (TTL 10 minutes), profondeur dénormalisée
- Acceptable : Volumétrie faible (< 100 projets), navigation pas temps-réel

**Transactions cascade complexes** :
- Coût : Publication/dépublication peut toucher 10+ projets (arbre profond)
- Mitigation : Ecto.Multi (atomicité), timeout 30 secondes, profondeur max recommandée 10
- Acceptable : Opération administrative rare (pas critique performance)

**Détection cycles double** :
- Coût : Logique redondante (trigger DB + validation app)
- Justification : Sécurité double (trigger = dernier rempart, app = meilleur message erreur)
- Acceptable : Pas d'impact performance (validation INSERT/UPDATE uniquement)

**Profondeur dénormalisée** :
- Coût : Colonne profondeur doit être mise à jour lors déplacement (UPDATE cascade enfants)
- Justification : Performance queries (filtre par profondeur sans récursion)
- Acceptable : Déplacements rares, gain performance requêtes fréquentes (navigation)

## Conséquences

### Positives

- **Hiérarchie illimitée** : Profondeur variable selon besoin (2 niveaux à 10+ niveaux)
- **Interface uniforme** : Projet traite photographies et sous-projets identiquement (Composite Pattern)
- **Flexibilité réorganisation** : Déplacement projets, détachement, suppression (si aucun enfant)
- **Pattern reconnu** : Gang of Four, documentation abondante, maintenabilité
- **Extensibilité** : Ajout niveaux sans modification schéma
- **Cohérence publication** : Cascade up (enfant publié → parents publiés), cascade down (parent dépublié → enfants dépubliés)
- **Performance acceptable** : Cache arbre complet (10 min TTL), profondeur dénormalisée
- **Protection cycles** : Double validation (trigger DB + app), impossible d'attacher projet à descendant
- **Testabilité** : Logique récursive testable (mocking repositories)

### Négatives

- **Requêtes récursives coûteuses** : Parcours arbre sans cache peut être lent (profondeur > 5)
  - Surveillance : Monitoring temps réponse navigation projets (cible < 200ms)
  - Gestion : Cache obligatoire (TTL 10 minutes), invalidation lors publication/attachement
- **Transactions cascade longues** : Publication arbre profond peut prendre 2-3 secondes
  - Surveillance : Timeout 30 secondes, logging durée transactions
  - Gestion : Job asynchrone si profondeur > 5 (notification utilisateur "Publication en cours")
- **Complexité détection cycles** : Parcours ancêtres récursif
  - Surveillance : Tests exhaustifs (100% couverture cas cycle)
  - Gestion : Trigger DB (sécurité dernière ligne) + app (message erreur explicite)
- **UPDATE cascade profondeur** : Déplacement projet met à jour tous descendants
  - Surveillance : Monitoring UPDATE cascade (nombre projets touchés)
  - Gestion : Transaction atomique (Ecto.Multi), rollback si échec

### Neutres

- **Profondeur dénormalisée** : Colonne supplémentaire à maintenir
  - Calcul automatique (trigger DB), gain performance queries
- **Cache invalidation** : Invalidation agressive (toute modification projet)
  - Cache simple (arbre complet), pas de cache granulaire par projet
- **Double validation cycles** : Logique redondante (trigger + app)
  - Sécurité accrue, meilleur UX (message erreur explicite côté app)

## Plan d'Action

1. **Phase 1: Schéma Base de Données**
   - Migration : Table projets avec parent_id, profondeur, indexes
   - Trigger : check_projet_cycle (détection cycles)
   - Trigger : calculate_projet_depth (calcul automatique profondeur)
   - Contrainte : CHECK (id != parent_id) empêche cycle direct

2. **Phase 2: Aggregate Projet**
   - Struct Projet avec parent_id, sous_projets
   - Changeset avec validation cycle (double sécurité)
   - Méthodes : peut_etre_publie?, a_du_contenu?, parents_publies?

3. **Phase 3: ProjetRepository**
   - get_racines_publiees (projets sans parent)
   - get_enfants (sous-projets d'un projet)
   - get_ancetres (chemin racine → actuel pour breadcrumb)
   - attacher_a_parent (validation cycle, UPDATE profondeur cascade)
   - detacher_projet (devenir racine)
   - peut_etre_supprime? (vérifier aucun enfant)

4. **Phase 4: ProjetPublicationService**
   - publier (cascade up : publication automatique parents)
   - depublier (cascade down : dépublication automatique enfants)
   - Ecto.Multi pour atomicité
   - Émission Domain Events (ProjetPublié, ProjetDépublié)

5. **Phase 5: ProjetHierarchyService**
   - construire_arbre_complet (cache 10 minutes)
   - get_breadcrumb (chemin racine → actuel)
   - Invalidation cache lors ProjetPublié, ProjetAttaché

6. **Phase 6: LiveView Admin**
   - ProjetIndex : Affichage arbre (racines + enfants récursifs)
   - ProjetEdit : Formulaire avec sélection parent (dropdown racines)
   - ProjetDetails : Breadcrumb, sous-projets, photographies
   - Drag & drop réorganisation (déplacement projets)

7. **Phase 7: Tests Exhaustifs**
   - Tests cycles : Attacher projet à descendant (exception attendue)
   - Tests cascade publication : Publier enfant → parents publiés
   - Tests cascade dépublication : Dépublier parent → enfants dépubliés
   - Tests profondeur : Calcul automatique après attachement
   - Tests suppression : Blocage si enfants existent
   - Tests performance : Cache arbre (< 100ms), invalidation

**Critères de succès:**
- Hiérarchie illimitée fonctionnelle (tests profondeur 10 niveaux)
- Détection cycles : 0 cycle créé en production
- Performance navigation : < 200ms avec cache, < 1s sans cache
- Cascade publication : Atomicité garantie (Ecto.Multi)
- Tests : 100% couverture règles métier (cycles, cascade, suppression)
- Documentation : Patterns Composite documenté (docs/ddd/)

**Rollback plan:**

Si Composite Pattern inadapté :
1. Identifier pain point : Performance ? Complexité requêtes ?
2. Option A : Limiter profondeur (5 niveaux max)
   - Simplifier détection cycles
   - Réduire coût récursion
3. Option B : Migration Materialized Path
   - Requêtes ancêtres/descendants optimisées
   - Complexité UPDATE cascade acceptable si déplacements rares
4. Option C : Migration Closure Table
   - Si volumétrie explose (> 500 projets)
   - Requêtes optimales, complexité maintenance acceptable
5. Dernier recours : Supprimer hiérarchie (projets plats)
   - Tags pour organisation thématique
   - Effort : 1 semaine migration

## Références

- [Composite Pattern - Gang of Four](https://refactoring.guru/design-patterns/composite)
- [Managing Hierarchical Data in PostgreSQL](https://www.postgresql.org/docs/current/queries-with.html)
- [Recursive Queries with Ecto](https://hexdocs.pm/ecto/recursive-queries.html)
- [Materialized Path Pattern](https://www.sqlshack.com/what-is-materialized-path-in-sql-server/)
- [Closure Table Pattern](https://www.slideshare.net/billkarwin/models-for-hierarchical-data)

Documentation projet :
- docs/ddd/002_photography_context.md (Aggregate Projet)
- docs/business_rules/001_photography_rules.md (PM-009 à PM-013)
- tmp/schema_database_ddd.sql (Schéma projets)

ADRs liés :
- ADR-003 : Adoption Domain-Driven Design
- ADR-032 : Repository Pattern Data Access
- ADR-035 : Ecto.Multi Atomic Transactions

## Notes

### État Actuel (Novembre 2025)

**Implémentation:**
- 🔄 Phase 1 : Schéma DB (en cours documentation)
- ⏳ Phases 2-7 : À implémenter

**Pattern Composite choisi car:**
- Besoin hiérarchie illimitée (2 à 10+ niveaux)
- Flexibilité réorganisation (déplacement, détachement)
- Simplicité implémentation (self-reference standard)
- Performance acceptable avec cache (< 100 projets prévus)

**Alternatives rejetées:**
- Materialized Path : Complexité UPDATE cascade > bénéfice
- Closure Table : Over-engineering pour volumétrie
- Niveaux fixes : Profondeur limitée incompatible besoin

### Lessons Learned (À documenter après implémentation)

**Anticipations:**
- Cache arbre complet suffisant (TTL 10 minutes)
- Profondeur dénormalisée utile (filtre rapide par niveau)
- Double validation cycles nécessaire (trigger + app)
- Ecto.Multi critique (atomicité cascade)

**À surveiller:**
- Performance requêtes récursives (monitoring temps réponse)
- Durée transactions cascade (timeout 30 secondes suffisant ?)
- Fréquence déplacements projets (UPDATE cascade profondeur)
- Volumétrie projets (< 100 prévu, vérifier hypothèse)

**Évolutions futures:**
- Si performance problématique : Migration Materialized Path
- Si volumétrie explose : Migration Closure Table
- Si profondeur excessive : Limiter 10 niveaux max (validation app)

---

**Participants à la décision:**
- Thibault San - Développeur Solo

**Révisé par:**
- Thibault San - 2025-11-12
