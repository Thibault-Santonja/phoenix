# 🔥 Benchmarks Portfolio

Ce dossier contient les benchmarks de performance pour le projet Portfolio.

## Objectifs

- Établir des **baselines de performance** pour les opérations critiques
- Détecter les **régressions de performance** lors des refactorings
- Optimiser les **points chauds** identifiés
- Documenter les **performances attendues**

## Structure

```
bench/
├── README.md                           # Ce fichier
├── photography/                        # Benchmarks du contexte Photography
│   ├── photo_upload_bench.exs         # Upload de photos
│   ├── album_queries_bench.exs        # Requêtes albums
│   └── photo_reorder_bench.exs        # Réordonnancement photos
└── results/                            # Résultats HTML (gitignored)
    ├── photo_upload.html
    ├── album_queries.html
    └── photo_reorder.html
```

## Utilisation

### Lancer un benchmark spécifique

```bash
# Upload de photos
mix run bench/photography/photo_upload_bench.exs

# Requêtes albums
mix run bench/photography/album_queries_bench.exs

# Réordonnancement
mix run bench/photography/photo_reorder_bench.exs
```

### Lancer tous les benchmarks

```bash
# À la main
for f in bench/photography/*.exs; do mix run $f; done

# Ou avec un alias (à ajouter dans mix.exs)
mix bench
```

### Visualiser les résultats

Les benchmarks génèrent des rapports HTML dans `bench/results/` :

```bash
open bench/results/photo_upload.html
open bench/results/album_queries.html
open bench/results/photo_reorder.html
```

## Benchmarks Disponibles

### 1. Photo Upload (`photo_upload_bench.exs`)

**Mesure :** Performance d'upload de photos en batch

**Scénarios :**
- Upload 1 photo
- Upload 5 photos
- Upload 10 photos
- Upload 20 photos

**Target :** < 500ms pour 10 photos

**Ce qui est mesuré :**
- Temps d'exécution total
- Utilisation mémoire
- Débit (photos/seconde)

### 2. Album Queries (`album_queries_bench.exs`)

**Mesure :** Performance des requêtes d'albums

**Scénarios :**
- List all albums (no preload)
- List published albums only
- List albums with photos preload
- List published by year
- Get album by slug (no preload)
- Get album by slug (with photos)
- Count all albums
- Count published albums

**Target :** 
- List albums : < 50ms
- Get album : < 100ms

**Dataset :** 50 albums avec 5 photos chacun

### 3. Photo Reorder (`photo_reorder_bench.exs`)

**Mesure :** Performance du réordonnancement de photos

**Scénarios :**
- Reorder 10 photos
- Reorder 25 photos
- Reorder 50 photos
- Reorder 100 photos

**Inputs :**
- Albums avec 10, 25, 50, et 100 photos

**Target :** < 200ms pour 50 photos

**Ce qui est mesuré :**
- Temps de mise à jour en base
- Scalabilité selon nombre de photos

## Performance Targets

| Opération | Target | Acceptable | Critique |
|-----------|--------|------------|----------|
| Upload 10 photos | < 500ms | < 1s | > 2s |
| List albums | < 50ms | < 100ms | > 200ms |
| Get album + photos | < 100ms | < 200ms | > 500ms |
| Reorder 50 photos | < 200ms | < 400ms | > 800ms |

## Interprétation des Résultats

### IPS (Iterations Per Second)

Plus c'est élevé, mieux c'est.

- **> 1000 IPS** : Excellent (opération très rapide)
- **100-1000 IPS** : Bon (opération rapide)
- **10-100 IPS** : Acceptable (opération normale)
- **< 10 IPS** : Attention (opération lente)

### Percentiles

- **p50 (médiane)** : 50% des requêtes sont plus rapides
- **p95** : 95% des requêtes sont plus rapides (SLA typique)
- **p99** : 99% des requêtes sont plus rapides (worst case)

### Memory

Attention aux allocations excessives :
- **< 1 MB** : Excellent
- **1-10 MB** : Bon
- **> 10 MB** : Investiguer (risque de GC fréquent)

## Bonnes Pratiques

### Avant de benchmarker

1. **Fermez les applications gourmandes** (navigateurs, IDE)
2. **Utilisez des données réalistes** (taille similaire à la prod)
3. **Lancez plusieurs fois** pour éliminer les variations
4. **Warmup est important** (JIT, caches)

### Pendant le développement

1. **Benchmarker avant** le refactoring (baseline)
2. **Benchmarker après** le refactoring
3. **Comparer les résultats** (regression ?)
4. **Documenter** les optimisations

### Red Flags 🚩

- Temps qui augmente de **> 50%** : Régression sérieuse
- Utilisation mémoire qui **double** : Memory leak possible
- IPS qui **chute** drastiquement : Bottleneck introduit

## Ajout de Nouveaux Benchmarks

### Template

```elixir
# bench/context/operation_bench.exs

{:ok, _} = Application.ensure_all_started(:portfolio)

alias Portfolio.Context

IO.puts("\n🔥 Operation Benchmarks\n")
IO.puts("=" |> String.duplicate(50))
IO.puts("Description de ce qui est mesuré")
IO.puts("Target: < XXXms\n")

Benchee.run(
  %{
    "scenario 1" => fn input ->
      # Code à benchmarker
    end,
    "scenario 2" => fn input ->
      # Code à benchmarker
    end
  },
  before_scenario: fn _ ->
    # Setup par scénario
  end,
  after_scenario: fn _ ->
    # Cleanup
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.HTML, file: "bench/results/operation.html"}
  ],
  time: 5,
  memory_time: 2,
  warmup: 1
)
```

### Conseils

- **Nommer explicitement** les scénarios
- **Setup/cleanup propre** (éviter les effets de bord)
- **Mesurer une seule chose** par benchmark
- **Utiliser des inputs variés** pour tester la scalabilité
- **Documenter les targets** dans le code

## Continuous Performance Monitoring

### En CI/CD (optionnel)

```yaml
# .github/workflows/benchmarks.yml
- name: Run benchmarks
  run: mix run bench/photography/photo_upload_bench.exs
  
- name: Compare with baseline
  run: |
    # Comparer avec le commit précédent
    # Fail si régression > 50%
```

### Alerting

Si un benchmark échoue les targets de façon répétée :
1. Investiguer le code récent
2. Vérifier les N+1 queries
3. Profiler avec `:eprof` ou `:fprof`
4. Optimiser les hot paths

## Ressources

- [Benchee Documentation](https://hexdocs.pm/benchee)
- [Benchee HTML](https://hexdocs.pm/benchee_html)
- [Elixir Performance Guide](https://hexdocs.pm/elixir/main/library-guidelines.html#avoid-performance-pitfalls)

---

**Dernière mise à jour :** 2025-01-26  
**Auteur :** Portfolio Team
