# ADR-070 : Stratégie et Architecture Frontend

**Statut** : Accepté  
**Date** : 2025-11-14  
**Décideurs** : Équipe technique  
**Contexte technique** : Phoenix LiveView 1.0+, Elixir 1.18+

---

## Contexte

Le projet Portfolio nécessite une architecture frontend moderne capable de gérer :

1. **Des interfaces riches et interactives** (galeries photos, timeline, drag & drop)
2. **Des performances optimales** (chargement rapide, animations fluides)
3. **Une expérience utilisateur haut de gamme** (animations, transitions, feedback immédiat)
4. **Un code maintenable** avec séparation claire des responsabilités
5. **Une scalabilité** pour supporter des milliers d'images et albums

Le choix technologique doit équilibrer **simplicité**, **performance** et **maintenabilité**.

---

## Décision

Adopter une architecture frontend **hybride Phoenix LiveView + JavaScript minimal** avec les principes suivants :

### 001. Architecture Server-Side First

**Phoenix LiveView comme fondation** :
- Le state management reste côté serveur (Elixir)
- Les LiveViews gèrent la logique métier et les mises à jour du DOM
- Les LiveComponents pour la réutilisabilité (formulaires, modals)
- Communication bidirectionnelle via WebSocket (PubSub)

**Avantages** :
- Moins de JavaScript à écrire et maintenir
- State partagé automatiquement (pas de synchronisation client-serveur)
- Sécurité renforcée (validation serveur, pas d'API REST exposée)
- SEO-friendly (rendu serveur initial)
- Temps de développement réduit

### 002. JavaScript Hooks pour les Interactions Avancées

**Principe** : Utiliser des Phoenix Hooks pour les fonctionnalités nécessitant du JavaScript natif.

**Types de hooks implémentés** :

#### A. Hooks d'Animation (`AnimateGallery`, `AnimateThis`, `YearTrigger`)
```javascript
export const AnimateGallery = {
  mounted() {
    const images = utils.$(".gallery__image");
    images.forEach(($image) => {
      animate($image, {
        opacity: [0, 1],
        translateY: [100, 0],
        ease: "out(3)",
        duration: 2000,
        delay: i * 120,
        autoplay: onScroll({ target: $image })
      });
    });
  }
};
```

**Usage** :
```heex
<div id="gallery" phx-hook="AnimateGallery">
  <!-- contenu -->
</div>
```

#### B. Hooks d'Interaction Navigateur (`InfiniteScroll`, `ParallaxHero`)
```javascript
export const InfiniteScroll = {
  mounted() {
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && !this.pending) {
          this.pending = true;
          this.pushEvent("load_more", {}, () => {
            this.pending = false;
          });
        }
      },
      { rootMargin: "1200px", threshold: 0 }
    );
    this.observer.observe(this.el);
  }
};
```

#### C. Hooks de Bibliothèque Tierce (`PhotoSortable`)
```javascript
export const PhotoSortable = {
  mounted() {
    this.sortable = Sortable.create(this.el, {
      animation: 150,
      draggable: ".sortable-item",
      onEnd: (evt) => {
        const photoIds = Array.from(
          this.el.querySelectorAll("[data-photo-id]")
        ).map((el) => el.dataset.photoId);
        this.pushEvent("reorder_photos", { photo_ids: photoIds });
      }
    });
  }
};
```

### 003. Patterns de Communication LiveView-JavaScript

#### Push Events (LiveView → JavaScript)
```elixir
# Dans le LiveView
def handle_event("trigger_animation", _params, socket) do
  {:noreply, push_event(socket, "animate", %{duration: 500})}
end
```

```javascript
// Dans le Hook
mounted() {
  this.handleEvent("animate", ({duration}) => {
    animate(this.el, {opacity: [0, 1], duration});
  });
}
```

#### Push to Server (JavaScript → LiveView)
```javascript
// Dans le Hook
this.pushEvent("load_more", {page: 2}, (reply) => {
  console.log("Server replied:", reply);
});
```

```elixir
# Dans le LiveView
def handle_event("load_more", %{"page" => page}, socket) do
  items = fetch_items(page)
  {:reply, %{status: "ok"}, assign(socket, items: items)}
end
```

### 004. Gestion des Animations avec Anime.js

**Bibliothèque choisie** : [Anime.js](https://animejs.com/)

**Raisons** :
- Légère (~9KB gzippé)
- API élégante et fonctionnelle
- Support des timelines complexes
- Performance natives (utilise requestAnimationFrame)
- Timeline et stagger intégrés

**Patterns d'animation** :

#### A. Scroll-triggered animations
```javascript
animate($image, {
  opacity: [0, 1],
  translateY: [100, 0],
  autoplay: onScroll({
    target: $image,
    container: container
  })
});
```

#### B. IntersectionObserver pour performance
```javascript
const observer = new IntersectionObserver(
  ([entry]) => {
    if (entry.isIntersecting) {
      animate(entry.target, {...});
    }
  },
  { threshold: 0.2 }
);
```

#### C. Stagger pour listes
```javascript
animate(".gallery__image", {
  opacity: [0, 1],
  delay: stagger(120) // 120ms entre chaque élément
});
```

### 005. Stratégie de Styling avec Tailwind CSS

**Approche** : Utility-first avec Tailwind CSS v4

**Principes** :

#### A. Classes utilitaires en priorité
```heex
<div class="flex items-center gap-4 p-6 bg-white rounded-lg shadow-md
            hover:shadow-lg transition-shadow duration-300">
  <!-- contenu -->
</div>
```

#### B. Transitions CSS natives pour micro-interactions
```heex
<button class="px-4 py-2 bg-blue-600 hover:bg-blue-700 
               transform hover:scale-105 transition-all duration-200">
  Cliquer
</button>
```

#### C. Animations complexes via JavaScript/Anime.js
```javascript
// Pour des animations multi-étapes ou conditionnelles
animate(element, {
  scale: [
    { to: 1.1, ease: "inOut(3)", duration: 200 },
    { to: 1, ease: createSpring({ stiffness: 300 }) }
  ],
  loop: true
});
```

### 006. Patterns de Chargement de Données

#### A. Initial Load (SSR)
```elixir
def mount(_params, _session, socket) do
  # Données chargées côté serveur lors du mount initial
  albums = Photography.list_albums(limit: 20)
  {:ok, assign(socket, albums: albums, page: 1)}
end
```

#### B. Pagination Infinie (Lazy Loading)
```elixir
def handle_event("load_more", _, socket) do
  if socket.assigns.has_more do
    next_page = socket.assigns.page + 1
    new_albums = Photography.list_albums(
      offset: (next_page - 1) * 20,
      limit: 20
    )
    {:noreply, 
     socket
     |> assign(page: next_page)
     |> stream(:albums, new_albums)}
  else
    {:noreply, socket}
  end
end
```

#### C. LiveView Streams pour collections
```heex
<ul id="albums-list" phx-update="stream">
  <li :for={{dom_id, album} <- @streams.albums} id={dom_id}>
    <!-- contenu album -->
  </li>
</ul>
```

**Avantages** :
- DOM minimal (pas de re-render de toute la liste)
- Mémoire optimisée (LiveView ne garde que les IDs)
- Append performant (pas de diff sur éléments existants)

### 007. Gestion de l'État (State Management)

**Principe** : State géré côté serveur (LiveView assigns)

#### A. État local au LiveView
```elixir
socket
|> assign(:page, 1)
|> assign(:albums_loaded, 0)
|> assign(:has_more, true)
|> assign(:reordering, false)
```

#### B. État partagé via PubSub
```elixir
# Dans un service
Phoenix.PubSub.broadcast(
  Portfolio.PubSub,
  "albums",
  {:album_published, album_id}
)

# Dans le LiveView
def handle_info({:album_published, album_id}, socket) do
  # Réagir à l'événement
  {:noreply, update_album(socket, album_id)}
end
```

#### C. État client éphémère (JS uniquement)
```javascript
// Pour des états UI temporaires (hover, focus, animations)
export const GalleryModal = {
  mounted() {
    this.isOpen = false; // État JS local
  }
};
```

### 008. Optimisations de Performance

#### A. Debouncing sur recherche
```elixir
def handle_event("search", %{"query" => query}, socket) do
  Process.send_after(self(), {:perform_search, query}, 300)
  {:noreply, socket}
end

def handle_info({:perform_search, query}, socket) do
  results = search(query)
  {:noreply, assign(socket, results: results)}
end
```

#### B. Intersection Observer pour lazy loading
```javascript
const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        loadImage(entry.target);
        observer.unobserve(entry.target);
      }
    });
  },
  { rootMargin: "200px" } // Précharge 200px avant
);
```

#### C. Passive event listeners
```javascript
window.addEventListener("scroll", handleScroll, { passive: true });
```

#### D. Cleanup dans destroyed()
```javascript
destroyed() {
  if (this.observer) {
    this.observer.disconnect();
  }
  if (this.interval) {
    clearInterval(this.interval);
  }
}
```

### 009. Patterns d'Accessibilité

#### A. Focus management
```javascript
export const Modal = {
  mounted() {
    this.previousFocus = document.activeElement;
    this.el.querySelector('button').focus();
  },
  destroyed() {
    this.previousFocus?.focus();
  }
};
```

#### B. Keyboard navigation
```javascript
window.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    this.pushEvent("close_modal", {});
  }
});
```

#### C. ARIA attributes dynamiques
```heex
<button 
  aria-expanded={@open}
  aria-controls="dropdown-menu">
  Menu
</button>
```

### 010. Organisation du Code JavaScript

**Structure des fichiers** :

```
assets/js/
├── app.js              # Point d'entrée, config LiveSocket
├── hooks.js            # Tous les Phoenix Hooks
└── vendor/
    ├── topbar.js       # Progress bar
    ├── floating.js     # Tooltips/Popovers
    └── mishka_components.js
```

**Pattern d'export** :
```javascript
// hooks.js
export const MyHook = {
  mounted() { ... },
  updated() { ... },
  destroyed() { ... }
};

// app.js
import { MyHook } from "./hooks";
const Hooks = { MyHook };
let liveSocket = new LiveSocket("/live", Socket, { hooks: Hooks });
```

---

## Conséquences

### Positives

1. **Simplicité** : Moins de code JavaScript complexe à maintenir
2. **Performance** : WebSocket + state serveur = latence minimale
3. **Sécurité** : Validation serveur, pas d'API REST exposée
4. **SEO** : Rendu serveur initial complet
5. **Maintenabilité** : Code Elixir typé et testé pour la logique métier
6. **DX** : Hot-reload LiveView + JS, debugging simple
7. **Animations fluides** : Anime.js pour UX premium
8. **Scalabilité** : Streams et pagination infinie pour grandes collections

### Négatives

1. **WebSocket requis** : Ne fonctionne pas si WS bloqué (fallback long-polling)
2. **Latence réseau** : Chaque interaction serveur = round-trip (mais <50ms en pratique)
3. **Courbe d'apprentissage** : Phoenix Hooks moins connus que React/Vue
4. **Limites offline** : Nécessite connexion (PWA possible mais complexe)

### Neutres

1. **Taille JS modeste** : ~50KB total (LiveView client + Anime.js + hooks)
2. **Pas de SPA** : Navigation serveur (mais instantanée avec LiveView)
3. **État serveur** : Consomme mémoire serveur (mais Elixir très efficient)

---

## Métriques de Succès

### Performance
- **FCP** (First Contentful Paint) : <1.5s
- **TTI** (Time to Interactive) : <2.5s
- **Taille JS** : <100KB (actuellement ~50KB)
- **Animations** : 60 FPS constant

### Qualité Code
- **Hooks réutilisables** : >80% des interactions via hooks génériques
- **Tests** : Couverture >80% (ExUnit pour LiveView, pas de tests JS pour hooks simples)
- **Pas de warnings** : Zero Credo issues, zero console.error en production

### Expérience Utilisateur
- **Smooth scroll** : Toutes les navigations fluides
- **Feedback immédiat** : Toutes les actions <100ms de feedback visuel
- **Accessibilité** : Keyboard navigation complète, ARIA sur éléments interactifs

---

## Exemples de Mise en Œuvre

### Cas 1 : Galerie Photo avec Infinite Scroll

**LiveView** (timeline.ex) :
```elixir
def mount(_params, _session, socket) do
  albums = Photography.list_albums(limit: 20)
  
  {:ok,
   socket
   |> assign(page: 1, has_more: true, albums_loaded: 20)
   |> stream(:albums, albums)}
end

def handle_event("load_more", _, socket) do
  next_page = socket.assigns.page + 1
  new_albums = Photography.list_albums(
    offset: (next_page - 1) * 20,
    limit: 21  # +1 pour détecter has_more
  )
  
  {to_show, has_more} = 
    if length(new_albums) > 20 do
      {Enum.take(new_albums, 20), true}
    else
      {new_albums, false}
    end
  
  {:noreply,
   socket
   |> assign(page: next_page, has_more: has_more)
   |> stream(:albums, to_show)}
end
```

**Template** (timeline.html.heex) :
```heex
<ul id="albums-list" phx-update="stream">
  <li :for={{dom_id, album} <- @streams.albums} 
      id={dom_id}
      phx-hook="YearTrigger"
      data-year={album.date_prise_vue.year}>
    <!-- album content -->
  </li>
</ul>

<div :if={@has_more} 
     id="infinite-scroll-marker" 
     phx-hook="InfiniteScroll" />
```

**Hook** (hooks.js) :
```javascript
export const InfiniteScroll = {
  mounted() {
    this.pending = false;
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && !this.pending) {
          this.pending = true;
          this.pushEvent("load_more", {}, () => {
            this.pending = false;
          });
        }
      },
      { rootMargin: "1200px", threshold: 0 }
    );
    this.observer.observe(this.el);
  },
  destroyed() {
    this.observer?.disconnect();
  }
};
```

### Cas 2 : Drag & Drop Photos

**LiveView** :
```elixir
def handle_event("reorder_photos", %{"photo_ids" => ids}, socket) do
  Photography.reorder_photos(socket.assigns.album.id, ids)
  {:noreply, put_flash(socket, :info, "Ordre mis à jour")}
end
```

**Hook** :
```javascript
export const PhotoSortable = {
  mounted() {
    this.sortable = Sortable.create(this.el, {
      animation: 150,
      onEnd: (evt) => {
        const photoIds = Array.from(
          this.el.querySelectorAll("[data-photo-id]")
        ).map(el => el.dataset.photoId);
        this.pushEvent("reorder_photos", { photo_ids: photoIds });
      }
    });
  }
};
```

### Cas 3 : Animation Year Display

**Hook avec state partagé** :
```javascript
export const YearTrigger = {
  mounted() {
    // État global partagé entre toutes les instances du hook
    if (window.__yearObserverInitialized) return;
    window.__yearObserverInitialized = true;
    
    const yearEl = document.getElementById("timeline-year");
    let currentYear = 2024;
    
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter(e => e.isIntersecting)
          .sort((a, b) => 
            Math.abs(a.boundingClientRect.top) - 
            Math.abs(b.boundingClientRect.top)
          );
        
        const topEntry = visible[0];
        if (!topEntry) return;
        
        const newYear = parseInt(topEntry.target.dataset.year);
        if (newYear !== currentYear) {
          animateYearChange(yearEl, currentYear, newYear);
          currentYear = newYear;
        }
      },
      { rootMargin: "-20% 0px -80% 0px" }
    );
    
    document.querySelectorAll("[data-year]")
      .forEach(el => observer.observe(el));
  }
};
```

---

## Alternatives Considérées

### Option 1 : React/Vue SPA + API REST

**Avantages** :
- Écosystème riche (composants, outils)
- Offline-first possible (Service Workers)
- Familier pour devs frontend

**Inconvénients** :
- Duplication logique client/serveur
- API REST à sécuriser et documenter
- Bundle JS massif (React ~40KB + Router + State)
- SEO complexe (SSR/SSG requis)
- Synchronisation state difficile

**Rejeté** : Complexité disproportionnée pour le besoin

### Option 2 : HTMX + Hyperscript

**Avantages** :
- Minimaliste (~14KB)
- Pas de build step
- HTML-first

**Inconvénients** :
- Animations limitées (CSS uniquement)
- Pas de WebSocket natif
- Polling pour temps réel
- Moins mature que LiveView

**Rejeté** : Animations complexes difficiles, pas de temps réel natif

### Option 3 : Phoenix LiveView pur (sans JS)

**Avantages** :
- Zero JavaScript à maintenir
- Tout géré côté serveur

**Inconvénients** :
- Animations limitées (CSS seulement)
- Pas de drag & drop natif
- IntersectionObserver impossible
- UX moins premium

**Rejeté** : Ne permet pas le niveau d'UX souhaité

---

## Références

- [Phoenix LiveView Documentation](https://hexdocs.pm/phoenix_live_view/)
- [Phoenix Hooks Guide](https://hexdocs.pm/phoenix_live_view/js-interop.html#client-hooks-via-phx-hook)
- [Anime.js Documentation](https://animejs.com/documentation/)
- [Tailwind CSS v4](https://tailwindcss.com/docs)
- [ADR-071: Infinite Scroll Timeline](./071_infinite_scroll_timeline_pagination.md)
- [Web.dev Performance](https://web.dev/performance/)
- [ARIA Authoring Practices](https://www.w3.org/WAI/ARIA/apg/)

---

## Évolution Future

### Court terme (3-6 mois)

1. **PWA Support** : Ajouter Service Worker pour offline basique
2. **Optimistic UI** : Mise à jour UI avant confirmation serveur
3. **Shared Hooks Library** : Extraire hooks réutilisables en package
4. **Performance Monitoring** : Intégrer Web Vitals tracking

### Moyen terme (6-12 mois)

1. **Image Optimization** : Lazy load avancé avec blur placeholder
2. **A11y Audit** : Audit complet accessibilité avec axe-core
3. **E2E Tests** : Tests Wallaby pour parcours critiques
4. **Bundle Optimization** : Tree-shaking Anime.js (utiliser que modules nécessaires)

### Long terme (12+ mois)

1. **Mobile App** : LiveView Native pour iOS/Android
2. **Offline-First** : State sync avancé avec conflict resolution
3. **Real-time Collaboration** : Édition collaborative albums/photos
4. **Advanced Animations** : Physics-based animations avec Spring API
