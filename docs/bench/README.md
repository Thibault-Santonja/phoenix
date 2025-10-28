# Benchmarks

Ce dossier contient les benchmarks de performance pour valider les optimisations critiques du projet.

## Structure

- `photography_bench.exs` - Benchmarks pour le module Photography
- `results/` - Rapports HTML générés (non versionnés)

## Exécution

```bash
# Exécuter tous les benchmarks
mix run docs/bench/photography_bench.exs

# Les résultats sont affichés dans le terminal
# Les rapports HTML sont générés dans docs/bench/results/
```

## Benchmarks Photography

### 1. Photo Count Optimization

Compare deux approches pour compter les photos d'un album :
- **Optimisée** : `with_photo_count` (agrégation SQL COUNT)
- **Legacy** : Précharger toutes les photos puis `length()`

**Résultat attendu** : L'approche optimisée devrait être 2-3x plus rapide et utiliser beaucoup moins de mémoire, surtout avec des albums de 100+ photos.

### 2. Reorder Optimization

Compare deux approches pour réorganiser l'ordre des photos :
- **Optimisée** : Requête SQL unique avec `CASE WHEN`
- **Legacy** : N requêtes UPDATE individuelles

**Résultat attendu** : L'approche optimisée devrait être ~N fois plus rapide (N = nombre de photos). Pour 100 photos : ~100x plus rapide.

### 3. Album Listing with Sorting

Benchmark des différentes options de tri sur la liste d'albums avec `photo_count` :
- Tri par titre
- Tri par date
- Tri par nombre de photos

**Objectif** : Vérifier que les index sont bien utilisés et que les performances restent bonnes même avec `with_photo_count`.

## Interprétation des résultats

Les benchmarks génèrent trois types de métriques :

1. **ips** (iterations per second) : Plus c'est élevé, mieux c'est
2. **average** : Temps moyen d'exécution (plus c'est bas, mieux c'est)
3. **memory** : Mémoire consommée (plus c'est bas, mieux c'est)

Les rapports HTML dans `results/` fournissent des graphiques détaillés.

## Ajout de nouveaux benchmarks

Pour ajouter un benchmark :

1. Créer un nouveau fichier `.exs` dans `docs/`
2. Suivre la structure de `photography_bench.exs`
3. Documenter ici le nouveau benchmark

## Ressources

- [Documentation Benchee](https://github.com/bencheeorg/benchee)
- [Code Review #0013](roadmap/0013_code_review.md) - Contexte des optimisations
