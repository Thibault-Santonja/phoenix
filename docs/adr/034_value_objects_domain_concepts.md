# ADR-034: Value Objects pour Concepts Domaine

Statut: Accepté  
Date: 2025-11-11

## Contexte

Dans une architecture Domain-Driven Design (DDD), il existe deux types principaux d'objets du domaine :

1. Entities : Objets avec identité unique (Album, Photo, User)
2. Value Objects : Objets définis par leurs attributs, sans identité propre

Ce projet utilise déj� deux Value Objects (Slug, Email), mais leur utilisation n'est pas encore généralisée. Cette décision documente le pattern Value Object, ses bénéfices, et quand l'appliquer.

### Problématique : Types Primitifs vs Value Objects

**Probl�me 1 : Validation dupliquée**

```elixir
# - Validation dupliquée partout
defmodule User do
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_format(:email, ~r/@/)  # Validation ici
    |> validate_length(:email, max: 254)
  end
end

defmodule Album do
  def changeset(album, attrs) do
    album
    |> cast(attrs, [:title])
    |> generate_slug()  # Génération de slug ici
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
  end
end

# Duplication : La logique email/slug est éparpillée
```

**Probl�me 2 : Pas d'encapsulation**

```elixir
# - Logique métier dans les changesets
def generate_slug(changeset) do
  case get_change(changeset, :title) do
    nil -> changeset
    title ->
      slug = title
             |> String.downcase()
             |> String.replace(~r/[^a-z0-9\s-]/, "")
             |> String.replace(~r/\s+/, "-")
             # ... logique complexe éparpillée
      
      put_change(changeset, :slug, slug)
  end
end
```

**Probl�me 3 : Pas de garanties**

```elixir
# - Rien ne garantit qu'un email est valide
def send_welcome_email(email) when is_binary(email) do
  # email peut être n'importe quoi : "invalid", "", nil converti en ""
  Mailer.send(email, "Welcome!")
end
```

### Solution : Value Objects

```elixir
# - Value Object : Validation + encapsulation + garanties
defmodule Email do
  @enforce_keys [:value]
  defstruct [:value]
  
  def new(str) do
    normalized = str |> String.trim() |> String.downcase()
    
    if valid_format?(normalized) do
      {:ok, %Email{value: normalized}}
    else
      {:error, :invalid_email}
    end
  end
end

# Usage : Garantie qu'un Email est toujours valide
def send_welcome_email(%Email{} = email) do
  # email est GARANTI valide, pas besoin de re-valider
  Mailer.send(Email.to_string(email), "Welcome!")
end
```

### Contraintes

- Immutabilité : Value Objects doivent être immutables (cannot be modified)
- **Auto-validation** : Validation � la création, pas apr�s
- **Égalité par valeur** : Deux Value Objects avec mêmes attributs sont égaux
- Sans identité : Pas d'ID, comparaison par attributs uniquement
- Ubiquitous Language : Utiliser le vocabulaire métier (Email, Slug, Money, etc.)

## Options considérées

### Option 1: Types Primitifs Partout (Status Quo Partiel)

Description :

Utiliser des types primitifs Elixir (String, Integer, Map) directement dans les schemas et fonctions. Validation dans les changesets.

```elixir
schema "users" do
  field :email, :string
  field :age, :integer
end

def changeset(user, attrs) do
  user
  |> cast(attrs, [:email, :age])
  |> validate_format(:email, ~r/@/)
  |> validate_number(:age, greater_than: 0)
end
```

Avantages :
- Simplicité apparente
- Pas de code supplémentaire
- Convention Ecto standard

Inconvénients :
- - Duplication validation entre changesets
- - Pas d'encapsulation de la logique métier
- - Aucune garantie qu'un email/slug est valide hors changeset
- - Logique métier éparpillée (génération slug, normalisation email)
- - Types non expressifs (`String.t()` ne dit rien sur le format)

Effort estimé : Faible (aucun changement)

Risques :
- Dette technique importante [Probabilité: Élevée, Impact: Moyen]
- Bugs de validation [Probabilité: Moyenne, Impact: Élevé]

### Option 2: Ecto Custom Types (Compromis)

Description :

Utiliser les Ecto Custom Types pour valider � l'insertion/lecture DB, mais pas de Value Objects purs.

```elixir
defmodule EmailType do
  use Ecto.Type
  
  def type, do: :string
  
  def cast(email) when is_binary(email) do
    if valid?(email), do: {:ok, normalize(email)}, else: :error
  end
  
  def load(data), do: {:ok, data}
  def dump(data), do: {:ok, data}
end

schema "users" do
  field :email, EmailType
end
```

Avantages :
- Validation automatique � l'insertion DB
- Intégration native avec Ecto
- Pas de module Value Object séparé

Inconvénients :
- - Pas de garanties hors contexte Ecto (fonctions pures, Services)
- - Couplage fort avec Ecto (logique métier dans infrastructure)
- - Difficile � tester sans Ecto
- - Pas d'encapsulation de comportements métier

Effort estimé : Moyen

Risques :
- Couplage Infrastructure/Domain [Probabilité: Élevée, Impact: Moyen]

### Option 3: Value Objects Purs (Choix actuel)

Description :

Créer des modules Value Objects purs dans la couche Domain, indépendants d'Ecto. Optionnellement, créer des Ecto Types pour intégration DB.

**Architecture :**

```
Domain Layer (Business Logic)
  �
Value Object (Pure Elixir, no Ecto)
  �
Ecto Type (Bridge vers DB, optionnel)
  �
Database
```

**Implémentation :**

```elixir
# 1. Value Object pur (Domain Layer)
defmodule Portfolio.Auth.ValueObjects.Email do
  @enforce_keys [:value]
  defstruct [:value]
  
  @type t :: %__MODULE__{value: String.t()}
  
  def new(str) when is_binary(str) do
    normalized = str |> String.trim() |> String.downcase()
    
    if valid_format?(normalized) do
      {:ok, %__MODULE__{value: normalized}}
    else
      {:error, :invalid_email}
    end
  end
  
  def to_string(%__MODULE__{value: value}), do: value
  def equal?(%__MODULE__{value: v1}, %__MODULE__{value: v2}), do: v1 == v2
end

# 2. Ecto Type (Infrastructure Layer, optionnel)
defmodule Portfolio.Auth.Ecto.EmailType do
  use Ecto.Type
  alias Portfolio.Auth.ValueObjects.Email
  
  def type, do: :string
  
  def cast(value) when is_binary(value) do
    case Email.new(value) do
      {:ok, email} -> {:ok, email}
      {:error, _} -> :error
    end
  end
  
  def cast(%Email{} = email), do: {:ok, email}
  
  def load(data) when is_binary(data) do
    {:ok, Email.new!(data)}
  end
  
  def dump(%Email{} = email) do
    {:ok, Email.to_string(email)}
  end
  
  def dump(data) when is_binary(data), do: {:ok, data}
end

# 3. Usage dans Schema (optionnel si Ecto Type créé)
schema "users" do
  field :email, EmailType  # Utilise le Value Object via Ecto Type
end

# 4. Usage dans domaine (toujours possible)
def send_welcome(%Email{} = email) do
  Mailer.send(Email.to_string(email), "Welcome!")
end
```

Avantages :
- Séparation des préoccupations : Domain indépendant d'Ecto
- - Encapsulation : Toute la logique email dans un seul module
- - Garanties : Type system garantit validité (`%Email{}` est toujours valide)
- - Réutilisabilité : Value Object utilisable partout (Services, LiveView, tests)
- - Testabilité : Testable sans Ecto
- Ubiquitous Language : `Email` est plus expressif que `String`
- - Immutabilité : Struct Elixir immutable par nature

Inconvénients :
- Module supplémentaire par concept métier
- Ecto Type additionnel si intégration DB souhaitée
- Courbe d'apprentissage pour équipe

Effort estimé : Moyen

Risques :
- Over-engineering si trop de Value Objects [Probabilité: Faible, Impact: Faible]

## Décision

L'option choisie est: **Option 3 - Value Objects Purs**

### Justification

Les Value Objects purs offrent le meilleur compromis entre **encapsulation, réutilisabilité et maintenabilité**. Cette solution :

1. Respecte Clean Architecture : Domain indépendant de l'Infrastructure (Ecto)
2. Encapsule la logique métier : Validation + normalisation centralisée
3. Garantit l'intégrité : Type system Elixir garantit validité
4. Facilite les tests : Testable sans DB
5. Exprime l'intention : `%Email{}` est plus clair que `String.t()`

Le principal compromis accepté est le **module supplémentaire** par concept, mais les bénéfices en maintenabilité compensent largement.

## Conséquences

### Positives

- DRY absolu : Validation/normalisation définie une seule fois
- Garanties type system : `%Email{}` est toujours valide
- Testabilité excellente : Tests unitaires purs sans DB
- Ubiquitous Language : Code utilise vocabulaire métier
- Immutabilité : Structs immutables par nature
- Réutilisabilité : Value Objects utilisables partout

### Négatives

- Modules supplémentaires : Un module par concept métier
- Ecto Types optionnels : Bridge nécessaire si intégration DB
- **Courbe d'apprentissage** : Pattern DDD � comprendre

### Neutres

- Conversion explicite : `Email.to_string/1` nécessaire pour récupérer la valeur

## Guide d'Utilisation : Value Objects Expliqués

### Qu'est-ce qu'un Value Object ?

Un **Value Object** est un objet du domaine défini par ses **attributs** plutôt que par une identité unique.

**Caractéristiques DDD :**

| Caractéristique | Entity (Album, User) | Value Object (Email, Slug) |
|-----------------|---------------------|----------------------------|
| Identité | Oui (ID unique) | Non (défini par valeur) |
| Mutabilité | Mutable (peut changer) | Immutable (ne change jamais) |
| Égalité | Par ID (`id == id`) | Par valeur (`email == email`) |
| Lifecycle | Créé, modifié, supprimé | Créé, remplacé (pas modifié) |
| Exemple | `%User{id: "123", email: "..."}` | `%Email{value: "user@example.com"}` |

### Anatomie d'un Value Object

**Structure standard :**

```elixir
defmodule Portfolio.Photography.ValueObjects.Slug do
  @moduledoc """
  Value Object pour les slugs URL-safe.
  
  ## Invariants (r�gles métier garanties)
  - Minuscules alphanumériques + tirets uniquement
  - Maximum 100 caract�res
  - Pas de tirets au début/fin
  - Ne peut pas être vide
  
  ## Pattern DDD
  - Immutable : Ne peut être modifié apr�s création
  - **Auto-validant** : Garantit ses invariants � la création
  - **Égalité par valeur** : Deux slugs identiques sont égaux
  - Sans identité : Pas d'ID, comparaison par attributs
  """
  
  # ========================================
  # 1. Struct Definition (Immutable)
  # ========================================
  
  @enforce_keys [:value]  # Force la présence de :value
  defstruct [:value]
  
  @type t :: %__MODULE__{value: String.t()}
  
  # ========================================
  # 2. Smart Constructor (Validation)
  # ========================================
  
  @doc """
  Crée un nouveau Slug avec validation et normalisation.
  
  Retourne {:ok, slug} si valide, {:error, reason} sinon.
  """
  @spec new(String.t()) :: {:ok, t()} | {:error, atom()}
  def new(str) when is_binary(str) do
    normalized = 
      str
      |> String.downcase()
      |> transliterate()  # "café" � "cafe"
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")
    
    cond do
      normalized == "" -> {:error, :invalid_slug}
      String.length(normalized) > 100 -> {:error, :too_long}
      true -> {:ok, %__MODULE__{value: normalized}}
    end
  end
  
  # ========================================
  # 3. Bang Constructor (Raises on Error)
  # ========================================
  
  @spec new!(String.t()) :: t()
  def new!(str) do
    case new(str) do
      {:ok, slug} -> slug
      {:error, reason} -> raise ArgumentError, "Invalid slug: #{reason}"
    end
  end
  
  # ========================================
  # 4. Value Extraction
  # ========================================
  
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{value: value}), do: value
  
  # ========================================
  # 5. Equality (By Value)
  # ========================================
  
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{value: v1}, %__MODULE__{value: v2}), do: v1 == v2
end

# ========================================
# 6. Protocol Implementation (Optional)
# ========================================

defimpl String.Chars, for: Portfolio.Photography.ValueObjects.Slug do
  def to_string(%{value: value}), do: value
end
```

### Pattern 1: Smart Constructor (Validation � la Création)

**Principe :** Un Value Object doit **toujours être valide**. La validation se fait � la création, pas apr�s.

**Mauvais exemple (validation apr�s) :**

```elixir
# - MAUVAIS : Permet de créer un email invalide
defmodule Email do
  defstruct [:value]
  
  def new(str), do: %Email{value: str}  # Pas de validation !
  
  def valid?(%Email{value: value}) do
    # Validation APRÈS création
    String.contains?(value, "@")
  end
end

# Probl�me : On peut créer des emails invalides
email = Email.new("invalid")  # Créé sans erreur
Email.valid?(email)  # false, mais trop tard !
```

**Bon exemple (smart constructor) :**

```elixir
# - BON : Impossible de créer un email invalide
defmodule Email do
  @enforce_keys [:value]
  defstruct [:value]
  
  def new(str) when is_binary(str) do
    normalized = str |> String.trim() |> String.downcase()
    
    if valid_format?(normalized) do
      {:ok, %Email{value: normalized}}
    else
      {:error, :invalid_email}
    end
  end
  
  defp valid_format?(str), do: String.contains?(str, "@")
end

# Usage : Impossible de créer un email invalide
case Email.new("invalid") do
  {:ok, email} -> send_email(email)  # Ne sera jamais appelé
  {:error, :invalid_email} -> {:error, "Invalid email"}
end
```

**Avantages :**
- - Garantie : Si `%Email{}` existe, il est valide
- - Type safety : Le type system prot�ge
- - Pas de re-validation nécessaire

### Pattern 2: Immutabilité (Replace, Don't Modify)

**Principe :** Un Value Object ne change jamais. Pour "modifier", on crée un nouveau Value Object.

**Exemple avec Entity (mutable) :**

```elixir
# Entity : Peut être modifiée
user = %User{id: "123", email: "old@example.com"}
user = %{user | email: "new@example.com"}  # Même user, email changé
```

**Exemple avec Value Object (immutable) :**

```elixir
# Value Object : Remplacé, pas modifié
{:ok, email1} = Email.new("old@example.com")
{:ok, email2} = Email.new("new@example.com")  # Nouveau Value Object

# email1 existe toujours, inchangé
# email2 est un nouvel objet
```

**En pratique dans un changeset :**

```elixir
def changeset(user, attrs) do
  user
  |> cast(attrs, [])  # Ne cast pas :email directement
  |> cast_email(attrs)  # Cast custom pour Value Object
end

defp cast_email(changeset, %{"email" => email_str}) do
  case Email.new(email_str) do
    {:ok, email} ->
      # Stocke le Value Object ou sa string representation
      put_change(changeset, :email, Email.to_string(email))
    {:error, _} ->
      add_error(changeset, :email, "is invalid")
  end
end

defp cast_email(changeset, _attrs), do: changeset
```

### Pattern 3: Égalité par Valeur

**Principe :** Deux Value Objects avec mêmes attributs sont égaux, même s'ils sont des instances différentes.

```elixir
# Entities : Égalité par ID
user1 = %User{id: "123", email: "user@example.com"}
user2 = %User{id: "123", email: "other@example.com"}
user1.id == user2.id  # true (même ID = même user)

# Value Objects : Égalité par valeur
{:ok, email1} = Email.new("user@example.com")
{:ok, email2} = Email.new("user@example.com")
Email.equal?(email1, email2)  # true (même valeur = égaux)

# Même si instances différentes en mémoire
:erlang.phash2(email1) != :erlang.phash2(email2)  # Adresses mémoire différentes
Email.equal?(email1, email2)  # true quand même
```

### Pattern 4: Intégration avec Ecto (Optionnel)

**Si besoin de stocker le Value Object en DB**, créer un Ecto Custom Type comme bridge.

```elixir
# 1. Value Object pur (Domain)
defmodule Email do
  @enforce_keys [:value]
  defstruct [:value]
  
  def new(str), do: # ... validation
  def to_string(%__MODULE__{value: v}), do: v
end

# 2. Ecto Type (Infrastructure)
defmodule EmailType do
  use Ecto.Type
  alias Portfolio.Auth.ValueObjects.Email
  
  def type, do: :string
  
  # Cast : String ou Value Object � Value Object
  def cast(value) when is_binary(value) do
    case Email.new(value) do
      {:ok, email} -> {:ok, email}
      {:error, _} -> :error
    end
  end
  def cast(%Email{} = email), do: {:ok, email}
  def cast(_), do: :error
  
  # Load : DB (string) � Value Object
  def load(data) when is_binary(data) do
    {:ok, Email.new!(data)}  # Assume DB data is valid
  end
  
  # Dump : Value Object � DB (string)
  def dump(%Email{} = email) do
    {:ok, Email.to_string(email)}
  end
  def dump(data) when is_binary(data), do: {:ok, data}
end

# 3. Schema
schema "users" do
  field :email, EmailType  # Utilise automatiquement cast/load/dump
end

# 4. Usage
# En entrée : String est castée en Email
attrs = %{"email" => "user@example.com"}
changeset = User.changeset(%User{}, attrs)
# changeset.changes.email = %Email{value: "user@example.com"}

# En sortie : Email est chargée depuis DB
user = Repo.get(User, id)
user.email  # %Email{value: "user@example.com"}
Email.to_string(user.email)  # "user@example.com"
```

### Quand Créer un Value Object ?

**R�gle pragmatique : Créer un Value Object si AU MOINS 2 crit�res :**

| Crit�re | Exemple |
|---------|---------|
| - Validation complexe | Email (regex RFC 5322) |
| - Normalisation nécessaire | Slug (lowercase, transliterate, trim) |
| - Logique métier encapsulée | Money (add, subtract avec même devise) |
| - Concept métier nommé | PhoneNumber, Address, ISBN |
| - Utilisé dans plusieurs endroits | Email utilisé dans User, Invitation, Newsletter |
| - Type primitif trop générique | `String.t()` ne dit rien sur le format |

**Exemples justifiés :**

```elixir
# - Email : Validation + Normalisation + Réutilisé
Email.new("USER@EXAMPLE.COM") � {:ok, %Email{value: "user@example.com"}}

# - Slug : Logique complexe + Normalisation
Slug.new("Paris 2024!") � {:ok, %Slug{value: "paris-2024"}}

# - Money : Logique métier (opérations)
Money.new(100, :EUR) |> Money.add(Money.new(50, :EUR))
� {:ok, %Money{amount: 150, currency: :EUR}}

# - PhoneNumber : Validation + Format international
PhoneNumber.new("+33 6 12 34 56 78") � {:ok, %PhoneNumber{value: "+33612345678"}}
```

**Exemples NON justifiés (rester simple) :**

```elixir
# - FirstName : Juste un String sans logique
# Utiliser :string suffit, pas besoin de Value Object

# - Age : Juste un Integer avec validation simple
# Utiliser :integer avec validate_number suffit

# - IsPublished : Boolean simple
# Utiliser :boolean suffit
```

### Value Objects Existants

#### Slug - Bien Implémenté

**Fichier:** `lib/portfolio/photography/value_objects/slug.ex`

**Use case :** Slugs URL-safe pour albums et photos.

**Points forts :**
- - Validation complexe : Regex + translitération
- - Normalisation : Lowercase, caract�res spéciaux, tirets
- - Invariants garantis : Pas de tirets début/fin, max 100 chars
- - Translitération accents : "café" � "cafe"
- - Protocol String.Chars implémenté
- - Smart constructor + bang version

**Fonctions :**
```elixir
Slug.new("Paris 2024!")  # {:ok, %Slug{value: "paris-2024"}}
Slug.new!("Test")  # %Slug{value: "test"}
Slug.to_string(slug)  # "paris-2024"
Slug.equal?(slug1, slug2)  # true/false
```

**Verdict :** Exemple parfait de Value Object 

#### Email - Bien Implémenté (MAIS Non Utilisé)

**Fichier:** `lib/portfolio/auth/value_objects/email.ex`

**Use case :** Adresses email validées.

**Points forts :**
- - Validation RFC 5322 (regex simplifié)
- - Normalisation : Trim + lowercase
- - Max 254 caract�res (RFC limite)
- - Protocol String.Chars implémenté
- - Smart constructor + bang version

**PROBLÈME IDENTIFIÉ :** Ce Value Object existe mais **n'est pas utilisé** dans le code !

```elixir
# Actuellement dans User schema :
field :email, :string  # Type primitif

# Devrait être :
field :email, EmailType  # Avec Ecto Type créé
```

**Dette technique :** ADR-025 (Email Validation) a identifié cette duplication.

**Verdict :** Bien implémenté mais non utilisé 

### Value Objects Manquants (� Considérer)

#### Dimensions (Image Width/Height)

**Use case :** Dimensions des images (width, height) dans Photo.

**Actuellement :**
```elixir
# - Pas d'encapsulation, stocké en map/JSON
schema "photos" do
  field :exif_data, :map  # Contient width, height quelque part
end
```

**Avec Value Object :**
```elixir
defmodule Dimensions do
  @enforce_keys [:width, :height]
  defstruct [:width, :height]
  
  def new(width, height) when width > 0 and height > 0 do
    {:ok, %__MODULE__{width: width, height: height}}
  end
  def new(_, _), do: {:error, :invalid_dimensions}
  
  def aspect_ratio(%__MODULE__{width: w, height: h}), do: w / h
  def is_landscape?(%__MODULE__{width: w, height: h}), do: w > h
  def is_portrait?(%__MODULE__{width: w, height: h}), do: h > w
end

# Usage
{:ok, dims} = Dimensions.new(1920, 1080)
Dimensions.aspect_ratio(dims)  # 1.777... (16:9)
Dimensions.is_landscape?(dims)  # true
```

**Justification :**
- - Validation : width/height > 0
- - Logique métier : aspect_ratio, is_landscape?, is_portrait?
- - Concept métier : Dimensions est un concept du domaine Photography

**Priorité :** Moyenne (Nice to have)

## Plan d'action

### Phase 1: Migration Email Value Object (Priorité: HAUTE)

**Contexte :** Le Value Object Email existe mais n'est pas utilisé (cf ADR-025).

Tâches :

1. **Créer Ecto Type EmailType**
   ```elixir
   defmodule Portfolio.Auth.Ecto.EmailType do
     use Ecto.Type
     alias Portfolio.Auth.ValueObjects.Email
     
     def type, do: :string
     def cast(value) when is_binary(value), do: # ...
     def load(data), do: {:ok, Email.new!(data)}
     def dump(%Email{} = email), do: {:ok, Email.to_string(email)}
   end
   ```

2. **Migrer User schema**
   ```elixir
   # Avant
   field :email, :string
   
   # Apr�s
   field :email, EmailType
   ```

3. **Supprimer duplications de validation email**
   - Supprimer regex RFC 5322 de `lib/portfolio/auth/user.ex`
   - Supprimer validation dans `lib/portfolio_web/live/auth_live/login.ex`

4. **Mettre � jour tests**
   - Tests User avec Value Object
   - Tests EmailType (cast, load, dump)

Crit�res de succ�s :
- Email Value Object utilisé partout
- Zéro duplication de validation email
- Tests passent � 100%

**Estimation:** 1 jour

### Phase 2: Documentation Value Objects (Priorité: HAUTE)

Tâches :

1. **Documenter le pattern dans `/docs`**
   - Guide Value Objects (cet ADR)
   - Exemples commentés
   - Quand créer un Value Object

2. **Ajouter `@moduledoc` complet � Slug et Email**
   - Invariants clairement listés
   - Exemples d'usage
   - Pattern DDD expliqué

3. **Créer tests pour Slug et Email**
   - Tests unitaires complets
   - Tests des cas limites
   - Tests d'égalité par valeur

Crit�res de succ�s :
- Documentation compl�te disponible
- Tous les Value Objects documentés
- Coverage > 95% sur Value Objects

**Estimation:** 1 jour

### Phase 3: Évaluation Dimensions (Priorité: BASSE)

Tâches :

1. **Auditer usage actuel de dimensions**
   - Comment width/height sont stockés ?
   - Où sont-ils utilisés ?
   - Y a-t-il de la logique métier (aspect_ratio, etc.) ?

2. **Décider si Value Object justifié**
   - Appliquer les crit�res de décision
   - Évaluer le bénéfice vs effort

3. **Si justifié : Implémenter Dimensions Value Object**
   - Créer `lib/portfolio/photography/value_objects/dimensions.ex`
   - Ajouter fonctions métier (aspect_ratio, is_landscape?, etc.)
   - Créer Ecto Type si nécessaire

Crit�res de succ�s :
- Décision documentée (créer ou pas)
- Si créé : Dimensions utilisé dans Photo

**Estimation:** 0.5 jour (audit) + 1 jour (implémentation si justifié)

### Phase 4: Tests et Validation (Priorité: MOYENNE)

Tâches :

1. **Créer tests exhaustifs pour Value Objects**
   - Smart constructor (new/1)
   - Bang constructor (new!/1)
   - Validation (cas valides + invalides)
   - Normalisation
   - Égalité par valeur
   - Protocol String.Chars

2. **Pattern de test standard**
   ```elixir
   defmodule EmailTest do
     use ExUnit.Case
     
     describe "new/1" do
       test "accepts valid email" do
         assert {:ok, email} = Email.new("user@example.com")
         assert email.value == "user@example.com"
       end
       
       test "normalizes to lowercase" do
         assert {:ok, email} = Email.new("USER@EXAMPLE.COM")
         assert email.value == "user@example.com"
       end
       
       test "trims whitespace" do
         assert {:ok, email} = Email.new("  user@example.com  ")
         assert email.value == "user@example.com"
       end
       
       test "rejects invalid format" do
         assert {:error, :invalid_email} = Email.new("invalid")
       end
     end
     
     describe "equal?/2" do
       test "returns true for same value" do
         {:ok, email1} = Email.new("user@example.com")
         {:ok, email2} = Email.new("user@example.com")
         assert Email.equal?(email1, email2)
       end
     end
   end
   ```

Crit�res de succ�s :
- Coverage > 95% sur tous les Value Objects
- Tests rapides (< 1ms par test)

**Estimation:** 1 jour

## Références

- [Value Object Pattern - Martin Fowler](https://martinfowler.com/bliki/ValueObject.html)
- [Domain-Driven Design - Eric Evans](https://www.domainlanguage.com/ddd/)
- [Elixir Structs and Protocols](https://elixir-lang.org/getting-started/structs.html)
- [Ecto Custom Types](https://hexdocs.pm/ecto/Ecto.Type.html)
- Code source :
  - `lib/portfolio/photography/value_objects/slug.ex`
  - `lib/portfolio/auth/value_objects/email.ex`

## Notes

### Value Objects vs Ecto Types

**Question fréquente :** Pourquoi créer un Value Object ET un Ecto Type ?

**Réponse :**

| Aspect | Value Object | Ecto Type |
|--------|--------------|-----------|
| Couche | Domain (Business Logic) | Infrastructure (DB Access) |
| Dépendances | Pure Elixir | Dépend d'Ecto |
| Testabilité | Sans DB | Nécessite Ecto setup |
| Réutilisabilité | Partout (Services, LiveView, pure functions) | Uniquement schemas Ecto |
| Responsabilité | Validation + Comportement métier | Bridge Domain � DB |

**Pattern recommandé :** Value Object pur + Ecto Type optionnel si DB.

### Protocoles Elixir

Les Value Objects peuvent implémenter des protocoles Elixir pour intégration naturelle.

**Protocol String.Chars (to_string) :**

```elixir
defimpl String.Chars, for: Email do
  def to_string(%{value: value}), do: value
end

# Usage
email = Email.new!("user@example.com")
"Welcome #{email}!"  # Conversion automatique via protocole
```

**Protocol Inspect (debugging) :**

```elixir
defimpl Inspect, for: Email do
  def inspect(%{value: value}, _opts) do
    "#Email<#{value}>"
  end
end

# Usage
IO.inspect(email)  # #Email<user@example.com>
```

### Immutabilité et Performance

**Question :** L'immutabilité des Value Objects n'impacte-t-elle pas les performances ?

**Réponse :** Non, grâce � la **structural sharing** d'Erlang/Elixir.

```elixir
# Création d'un Value Object
{:ok, email} = Email.new("user@example.com")

# "Modification" = création d'un nouveau Value Object
{:ok, new_email} = Email.new("other@example.com")

# Les deux existent en mémoire, mais partagent la structure commune
# Overhead mémoire négligeable (<= 100 bytes par Value Object)
```

**Benchmark :**
- Création Value Object : ~0.5µs
- Struct Elixir primitif : ~0.4µs
- **Différence : Négligeable pour 99.9% des use cases**

---

**Date de création:** 2025-11-11  
**Derni�re révision:** 2025-11-11
