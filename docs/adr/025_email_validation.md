# ADR-025: Validation des Adresses Email

Statut: Accepté
Date: 2025-09

## Contexte

La validation des adresses email est un probl�me déceptivement complexe. Une adresse email semble simple (`user@domain.com`), mais le standard RFC 5322 autorise des formats surprenants comme `"very.(),:;<>[]\"..strange"@example.com` ou `admin@[IPv6:2001:db8::1]`.

### Les défis de la validation email

1. Complexité du standard RFC 5322 : La spec compl�te fait des dizaines de pages
2. Emails internationaux : Caract�res accentués, domaines non-ASCII (IDN)
3. Normalisation : `User@Example.COM` vs `user@example.com` (même adresse ?)
4. Unicité : Un utilisateur = un email unique
5. Domaines jetables : tempmail.com, guerrillamail.com (spam, abus)
6. Validation existentielle : Le domaine a-t-il des serveurs mail (MX records) ?
7. Providers spéciaux : Gmail ignore les points (`test.user@gmail.com` == `testuser@gmail.com`)

### Approches possibles

1. Regex simple : `~r/@/` (accepte presque tout, peu sécurisé)
2. Regex RFC 5322 : Validation stricte mais complexe
3. Biblioth�que externe : `email_checker`, `burnex` (emails jetables)
4. Value Object DDD : Encapsulation du concept métier "Email"
5. Validation async DNS : Vérifier l'existence du domaine
6. Confirmation par email : L'utilisateur prouve l'acc�s (gold standard)

Pour ce portfolio, le choix initial s'est porté sur une **validation RFC 5322 via regex** avec **normalisation lowercase**. Cependant, une **duplication de code** a été identifiée (3 implémentations du même regex), nécessitant une refonte architecturale.

## Décision

Le syst�me utilise une validation RFC 5322 avec normalisation (trim + lowercase) et stockage en base de données CITEXT (case-insensitive). La validation est actuellement dupliquée en 3 endroits, une migration vers un Value Object Email centralisé est fortement recommandée.

### Architecture actuelle (avec probl�mes)

#### 1. Duplication du code de validation

**Probl�me identifié** : Le regex RFC 5322 est dupliqué en 3 endroits :

##### Location 1 : User schema (user.ex ligne 19)

```elixir
@email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

defp validate_email(changeset) do
  changeset
  |> validate_format(:email, @email_regex, message: "doit être une adresse email valide")
  |> validate_length(:email, max: 160)  #  Trop restrictif (RFC = 254)
  |> update_change(:email, &String.downcase/1)
  |> unsafe_validate_unique(:email, Portfolio.Repo)
  |> unique_constraint(:email)
end
```

##### Location 2 : Value Object Email (email.ex ligne 40)

```elixir
@email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

@max_length 254  #  Correct (RFC)

def new(str) when is_binary(str) do
  normalized = str |> String.trim() |> String.downcase()  #  Trim + downcase

  cond do
    String.length(normalized) > @max_length -> {:error, :too_long}
    Regex.match?(@email_regex, normalized) -> {:ok, %__MODULE__{value: normalized}}
    true -> {:error, :invalid_email}
  end
end
```

##### Location 3 : Login LiveView (login.ex ligne 83) - CORRIGÉ

```elixir
# Avant (validation laxiste)
validate_format(:email, ~r/@/, message: "L'email doit être valide")

# Apr�s correction (même regex que User)
validate_format(:email, @email_regex, message: "L'email doit être valide")
```

**Conséquence** :
-  Maintenance difficile (modifier en 3 endroits)
-  Risque d'incohérence (regex différents, max_length différents)
-  Violation DRY (Don't Repeat Yourself)

#### 2. Validation en couches

Le syst�me actuel applique la validation � plusieurs niveaux :

##### Frontend LiveView (validation UX)

```elixir
# login.ex - Validation instantanée (phx-change)
def handle_event("validate", %{"email_form" => params}, socket) do
  changeset = email_changeset(params) |> Map.put(:action, :validate)
  {:noreply, assign(socket, :form, to_form(changeset))}
end
```

Affiche les erreurs en temps réel pendant la saisie.

##### Backend Schema (validation métier)

```elixir
# user.ex - Validation compl�te avant insertion
def registration_changeset(user, attrs) do
  user
  |> cast(attrs, [:email, :name])
  |> validate_required([:email])
  |> validate_email()  # Regex + length + normalisation + unicité
  |> put_change(:role, :user)
end
```

Garantit l'intégrité des données.

##### Base de données (contraintes)

```sql
-- Migration ligne 10
add(:email, :citext, null: false)

-- Migration ligne 17
create(unique_index(:users, [:email]))
```

Protection ultime contre les doublons (race conditions).

**Avantage** : défense en profondeur (chaque couche rattrape les erreurs de la précédente).

**Inconvénient** : duplication de logique (regex dupliqué).

#### 3. Type CITEXT PostgreSQL

**Découverte importante** : La colonne email utilise le type `CITEXT` (case-insensitive text).

Qu'est-ce que CITEXT ?

CITEXT est une extension PostgreSQL qui stocke du texte insensible � la casse :

```sql
-- Extension activée (migration ligne 5)
CREATE EXTENSION IF NOT EXISTS citext

-- Comparaisons case-insensitive natives
SELECT * FROM users WHERE email = 'User@Example.COM';
-- Retourne : user@example.com (si existant)

-- Index unique case-insensitive automatique
-- 'test@gmail.com' et 'Test@Gmail.COM' sont considérés identiques
```

**Avantages** :
-  Unicité case-insensitive native (pas de doublons `test@` vs `Test@`)
-  Performance (index optimisé)
-  Simplicité (pas besoin de LOWER() dans les queries)

**Impact sur le code Elixir** :

Le `String.downcase/1` dans le changeset est **redondant** mais **recommandé** :
- CITEXT g�re la case-insensitivity en DB
- Mais `downcase` garantit une cohérence applicative (toujours stocker en lowercase)
- Évite les surprises (affichage `Test@` vs `test@`)

**Décision** : garder `String.downcase/1` pour cohérence.

#### 4. Double validation d'unicité

Le syst�me effectue deux validations d'unicité :

##### unsafe_validate_unique (ligne 130)

```elixir
|> unsafe_validate_unique(:email, Portfolio.Repo)
```

**Fonctionnement** :
1. Query DB : `SELECT 1 FROM users WHERE email = ?` (avant insert)
2. Si existe : ajoute erreur au changeset
3. Si absent : continue

**Avantages** :
-  Feedback rapide (évite un insert inutile)
-  Erreur côté changeset (utilisateur peut corriger)

**Inconvénients** :
- UNSAFE : race condition possible
  ```
  Temps | User A              | User B
  --------|---------------------|---------------------
  T1      | Check "test@" � OK  |
  T2      |                     | Check "test@" � OK
  T3      | INSERT "test@" �  |
  T4      |                     | INSERT "test@" �  (constraint)
  ```
-  Pas atomique

Pourquoi "unsafe" ? Entre le SELECT et l'INSERT, une autre transaction peut insérer le même email.

##### unique_constraint (ligne 131)

```elixir
|> unique_constraint(:email)
```

**Fonctionnement** :
1. Insert en DB : `INSERT INTO users ...`
2. Si constraint violated : Postgres retourne erreur
3. Ecto transforme en erreur changeset

**Avantages** :
- SAFE : atomique, pas de race condition
-  Garantie absolue (protection DB)

**Inconvénients** :
-  Insert requis (plus coûteux si échec)

Pourquoi les deux ?

**Réponse** : Défense en profondeur (layered security) :

```
1. unsafe_validate_unique : Filtre 99% des cas (rapide)
   � (échec)
2. Retour erreur � User corrige � Retry
   � (succ�s)
3. INSERT en DB
   � (race condition rare)
4. unique_constraint : Rattrape le 1% restant
   �
5. Cohérence garantie
```

**Recommandation** : **Garder les deux** (bonne pratique Ecto).

#### 5. Normalisation de l'email

Deux formes de normalisation sont appliquées :

##### Lowercase (case normalization)

```elixir
# User.ex ligne 129
|> update_change(:email, &String.downcase/1)

# Value Object ligne 65
normalized = str |> String.downcase()
```

**Exemple** : `User@Example.COM` � `user@example.com`

Pourquoi ? Emails sont case-insensitive selon RFC (mais pas tous les providers le respectent).

##### Trim whitespace (space normalization)

```elixir
# Value Object ligne 65 (présent)
normalized = str |> String.trim() |> String.downcase()

# User.ex (ABSENT) 
# Probl�me : " user@example.com " passe la validation
```

**Exemple** : `" test@example.com "` � `"test@example.com"`

Pourquoi important ? Utilisateur peut copier-coller avec espaces accidentels.

**Probl�me identifié** : `String.trim()` absent dans `User.validate_email/1`.

**Recommandation** : Ajouter trim partout.

### Architecture recommandée (solution)

Pour résoudre la duplication et centraliser la validation, migrer vers une architecture Value Object + Ecto Type custom.

#### 1. Value Object Email (source de vérité unique)

```elixir
# lib/portfolio/auth/value_objects/email.ex
defmodule Portfolio.Auth.ValueObjects.Email do
  @moduledoc """
  Value Object représentant une adresse email valide.

  Invariants garantis :
  - Format RFC 5322 (simplifié)
  - Longueur �� 254 caract�res
  - Normalisé (trim + lowercase)
  - Immutable
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}

  # RFC 5322 simplifié
  @email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  # RFC 5322 : 64 (local) + @ + 189 (domain) = 254 max
  @max_length 254

  @doc """
  Crée un Email � partir d'une chaîne.

  ## Exemples

      iex> Email.new("user@example.com")
      {:ok, %Email{value: "user@example.com"}}

      iex> Email.new("  User@EXAMPLE.COM  ")
      {:ok, %Email{value: "user@example.com"}}

      iex> Email.new("invalid")
      {:error, :invalid_email}
  """
  @spec new(String.t()) :: {:ok, t()} | {:error, :invalid_email | :too_long}
  def new(str) when is_binary(str) do
    normalized = str |> String.trim() |> String.downcase()

    cond do
      String.length(normalized) > @max_length ->
        {:error, :too_long}

      Regex.match?(@email_regex, normalized) ->
        {:ok, %__MODULE__{value: normalized}}

      true ->
        {:error, :invalid_email}
    end
  end

  @doc """
  Crée un Email, l�ve une exception si invalide.

  Utile pour les tests ou quand l'email est garanti valide.
  """
  @spec new!(String.t()) :: t()
  def new!(str) do
    case new(str) do
      {:ok, email} -> email
      {:error, reason} -> raise ArgumentError, "Invalid email: #{reason}"
    end
  end

  @doc """
  Retourne l'email comme string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{value: value}), do: value

  @doc """
  Extrait le domaine de l'email.

  ## Exemples

      iex> email = Email.new!("user@example.com")
      iex> Email.domain(email)
      "example.com"
  """
  @spec domain(t()) :: String.t()
  def domain(%__MODULE__{value: value}) do
    value |> String.split("@") |> List.last()
  end

  @doc """
  Extrait la partie locale (avant @) de l'email.
  """
  @spec local_part(t()) :: String.t()
  def local_part(%__MODULE__{value: value}) do
    value |> String.split("@") |> List.first()
  end
end
```

#### 2. Ecto Type custom (bridge)

```elixir
# lib/portfolio/auth/ecto/email_type.ex
defmodule Portfolio.Auth.Ecto.EmailType do
  @moduledoc """
  Ecto Type custom pour le Value Object Email.

  Permet d'utiliser Email comme type de champ dans les schemas Ecto.
  """

  use Ecto.Type

  alias Portfolio.Auth.ValueObjects.Email

  @impl true
  def type, do: :string

  @impl true
  def cast(value) when is_binary(value) do
    case Email.new(value) do
      {:ok, email} -> {:ok, email}
      {:error, _} -> :error
    end
  end

  def cast(%Email{} = email), do: {:ok, email}
  def cast(_), do: :error

  @impl true
  def load(value) when is_binary(value) do
    # Depuis la DB, on assume que l'email est valide
    {:ok, Email.new!(value)}
  end

  @impl true
  def dump(%Email{value: value}), do: {:ok, value}
  def dump(_), do: :error

  @impl true
  def equal?(email1, email2), do: email1.value == email2.value
end
```

#### 3. Schema User simplifié

```elixir
# lib/portfolio/auth/user.ex
defmodule Portfolio.Auth.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolio.Auth.Ecto.EmailType

  schema "users" do
    field :email, EmailType  # � Type custom !
    field :name, :string
    field :role, Ecto.Enum, values: [:admin, :user], default: :user

    has_many :magic_links, MagicLink
    has_many :user_sessions, UserSession

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :role])
    |> validate_required([:email, :role])
    # Plus besoin de validate_email/1 privée !
    # La validation est gérée par EmailType.cast/1
    |> validate_inclusion(:role, [:admin, :user])
    |> unsafe_validate_unique(:email, Portfolio.Repo)
    |> unique_constraint(:email)
  end
end
```

**Avantages de cette architecture** :

1.  Single Source of Truth : Une seule définition de validation (Email Value Object)
2.  DRY : Plus de duplication de regex
3.  Testabilité : Tests isolés du Value Object
4.  Encapsulation : Logique métier dans le Value Object (domain, local_part)
5.  Type safety : Le compilateur garantit que `user.email` est un Email valide
6.  Évolutivité : Facile d'ajouter des r�gles (DNS, disposable, etc.)

#### 4. Utilisation dans le code

```elixir
# Création d'un user
user_params = %{email: "New.User@Example.COM", name: "John"}
changeset = User.registration_changeset(%User{}, user_params)

# Le cast transforme automatiquement la string en Email Value Object
# "New.User@Example.COM" � Email{value: "new.user@example.com"}

# Acc�s � l'email
user.email.value            # "new.user@example.com"
Email.domain(user.email)    # "example.com"
Email.local_part(user.email) # "new.user"

# Comparaison
user.email.value == "new.user@example.com"  # true
```

### Validation avancée (futures améliorations)

#### 1. Validation DNS MX record

Vérifier que le domaine poss�de des serveurs mail (MX records) :

```elixir
defmodule Portfolio.Auth.EmailValidator do
  @moduledoc """
  Validations avancées pour les emails.
  """

  @doc """
  Vérifie que le domaine email a des enregistrements MX.

  ## Exemples

      iex> EmailValidator.domain_has_mx?("gmail.com")
      true

      iex> EmailValidator.domain_has_mx?("invalid-domain-123456.com")
      false
  """
  @spec domain_has_mx?(String.t()) :: boolean()
  def domain_has_mx?(domain) do
    case :inet_res.lookup(String.to_charlist(domain), :in, :mx) do
      [] -> false
      _mx_records -> true
    end
  rescue
    _ -> false
  end

  @doc """
  Valide l'email avec check DNS MX.

  Usage dans changeset:

      |> validate_change(:email, fn :email, email_value_object ->
        domain = Email.domain(email_value_object)

        if EmailValidator.domain_has_mx?(domain) do
          []
        else
          [email: "domaine email invalide ou inexistant"]
        end
      end)
  """
end
```

**Attention** :
-  Query DNS lente (100-500ms)
-  Peut échouer (timeout, DNS temporairement down)
-  Faux positifs (domaines configurés mais MX temporairement off)

**Recommandations** :
- Faire en async (pas bloquer l'UI)
- Skip en dev/test (pas de connexion internet requise)
- Optionnel (ne pas bloquer l'inscription si échec DNS)

```elixir
# Configuration
config :portfolio, :email_validation,
  check_mx_records: System.get_env("ENV") == "prod"

# Usage conditionnel
if Application.get_env(:portfolio, :email_validation)[:check_mx_records] do
  |> validate_mx_record()
end
```

#### 2. Emails internationaux (IDN)

Support des domaines internationaux (ex: `test@münchen.de`) :

```elixir
# mix.exs
{:idna, "~> 6.1"}

# Dans Email Value Object
defp normalize_idn(email) do
  [local, domain] = String.split(email, "@")

  # Encode domain to ASCII (punycode)
  encoded_domain =
    domain
    |> String.to_charlist()
    |> :idna.to_ascii()
    |> to_string()

  "#{local}@#{encoded_domain}"
rescue
  _ -> email  # Si échec encoding, garder original
end

# test@münchen.de � test@xn--mnchen-3ya.de
```

**Standards** :
- RFC 5890 : Internationalized Domain Names in Applications (IDNA)
- Punycode : encodage ASCII des caract�res non-ASCII

**Exemple concret** :

```
Entrée user : café@münchen.de
              � normalize_idn
Stocké en DB : café@xn--mnchen-3ya.de
              � Affichage
Montré user : café@münchen.de (decode punycode)
```

#### 3. Emails jetables (disposable)

Bloquer les domaines d'emails temporaires :

```elixir
defmodule Portfolio.Auth.DisposableEmailChecker do
  @moduledoc """
  Détecte les emails jetables/temporaires.
  """

  # Liste noire (� maintenir ou utiliser API externe)
  @disposable_domains [
    "tempmail.com",
    "guerrillamail.com",
    "10minutemail.com",
    "mailinator.com",
    "throwaway.email"
    # ... 1000+ domaines
  ]

  @doc """
  Vérifie si le domaine est jetable.
  """
  @spec disposable?(String.t()) :: boolean()
  def disposable?(domain) do
    domain in @disposable_domains
  end

  @doc """
  Alternative : utiliser une API externe.

  Services:
  - kickbox.com (payant, 99.9% précis)
  - emaillistverify.com
  - API GitHub : https://github.com/disposable-email-domains/disposable-email-domains
  """
  @spec check_via_api(String.t()) :: {:ok, boolean()} | {:error, term()}
  def check_via_api(domain) do
    # HTTP request vers API externe
    # Implementé avec Req ou Finch
  end
end
```

**Maintenance** : Les listes de domaines jetables évoluent constamment. Solutions :
1. Maintenir manuellement (effort continu)
2. Utiliser une biblioth�que Elixir (`burnex`)
3. Utiliser une API externe (coût, latence)

**Contexte actuel** : Non nécessaire (inscriptions fermées en production).

#### 4. Normalisation Gmail

Gmail ignore les points dans la partie locale et tout apr�s `+` :

```elixir
defp normalize_gmail(email) do
  case String.split(email, "@") do
    [local, "gmail.com"] ->
      # Supprimer les points
      cleaned = String.replace(local, ".", "")

      # Supprimer tout apr�s +
      base = String.split(cleaned, "+") |> List.first()

      "#{base}@gmail.com"

    _ ->
      email
  end
end

# Exemples de normalisation Gmail
test.user+spam@gmail.com  � testuser@gmail.com
t.e.s.t@gmail.com         � test@gmail.com
test+newsletter@gmail.com � test@gmail.com
```

**Cas d'usage** : Empêcher qu'un utilisateur crée 10 comptes avec variations Gmail.

**Attention** :
-  Spécifique Gmail (ne pas appliquer aux autres providers)
-  Peut frustrer les utilisateurs légitimes (utilisent `+tag` pour filtrer)
-  Trade-off UX vs sécurité

**Recommandation** : Priorité basse (nice-to-have si abus constatés).

## Alternatives considérées

### Biblioth�ques externes

#### Option 1 : email_checker

```elixir
# mix.exs
{:email_checker, "~> 0.2"}

# Usage
EmailChecker.valid?("user@example.com")
# {:ok, %EmailChecker.Check{...}}
```

**Avantages** :
-  Validation RFC compl�te
-  Check DNS MX intégré
-  Détection emails jetables
-  Bien testé

**Inconvénients** :
-  Dépendance externe (maintenance, mises � jour)
-  Moins de contrôle sur la logique
-  Overhead (fonctionnalités inutilisées)

**Décision** : Rejeté pour l'instant (Value Object suffit).

#### Option 2 : burnex (emails jetables)

```elixir
{:burnex, "~> 3.1"}

Burnex.is_burner?("test@tempmail.com")
# true
```

**Avantages** :
-  Liste domaines jetables maintenue
-  Simple d'usage

**Inconvénients** :
-  Dépendance externe
-  Non nécessaire actuellement (inscriptions fermées)

**Décision** : Rejeté pour l'instant (YAGNI).

### Validation par confirmation email

**Approche** : Envoyer un email de confirmation avec lien d'activation.

**Avantages** :
-  Prouve l'acc�s � l'email (gold standard)
-  Détecte les typos (user@gmial.com au lieu de gmail.com)
-  Filtre les emails invalides/jetables naturellement

**Inconvénients** :
-  UX friction (étape supplémentaire)
-  Emails peuvent être en spam
-  Utilisateurs abandonnent le processus

**Contexte actuel** : Magic link fait déj� office de vérification implicite !

**Raisonnement** :
1. User demande magic link � email envoyé
2. User clique sur magic link � prouve l'acc�s � l'email
3. User connecté � email vérifié implicitement

**Décision** : Pas de confirmation séparée nécessaire (magic link suffit).

### Type CITEXT vs LOWER() index

**Alternative** : Utiliser `:string` avec index `LOWER(email)`.

```sql
-- Alternative � CITEXT
CREATE UNIQUE INDEX users_email_lower_idx ON users (LOWER(email));

-- Query
SELECT * FROM users WHERE LOWER(email) = LOWER('User@Example.COM');
```

**Avantages** :
-  Pas besoin d'extension PostgreSQL
-  Fonctionne sur toutes les DB

**Inconvénients** :
-  Plus verbeux (LOWER() partout)
-  Performances lég�rement moins bonnes
-  Oubli facile (query sans LOWER())

**Décision** : CITEXT est meilleur (déj� utilisé ).

## Probl�mes identifiés et recommandations

### 1. Duplication de code (CRITIQUE)

**Probl�me** : Regex RFC 5322 dupliqué 3 fois (User.ex, ValueObjects.Email, Login.ex).

**Impact** :
-  Maintenance difficile
-  Risque d'incohérence
-  Violation DRY

**Solution** : Migrer vers Ecto Type custom + Value Object.

**Priorité** : **Critique** (dette technique importante).

### 2. Longueur maximale incohérente

**Probl�me** :
- User.ex : `max: 160` (trop restrictif)
- ValueObjects.Email : `max: 254` (correct selon RFC)

**Impact** : Emails légitimes de 160-254 caract�res rejetés.

**Solution** : Harmoniser � 254 partout.

**Priorité** : **Haute** (bug potentiel).

### 3. Trim absent dans User schema

**Probl�me** : `String.trim()` appliqué dans Value Object mais pas dans `User.validate_email/1`.

**Impact** : Email avec espaces ` user@example.com ` passe la validation User mais échoue Value Object (incohérence).

**Solution** : Ajouter trim dans `User.validate_email/1`.

```elixir
|> update_change(:email, fn email ->
  email |> String.trim() |> String.downcase()
end)
```

**Priorité** : **Moyenne** (edge case rare mais annoying).

### 4. Value Object Email inutilisé

**Observation** : Value Object Email existe mais n'est utilisé nulle part dans le code.

**Impact** : Code mort, confusion.

**Solution** : Soit utiliser (recommandé), soit supprimer.

**Priorité** : **Haute** (clarifier l'architecture).

### 5. Pas de tests Value Object

**Observation** : Aucun test trouvé pour `Portfolio.Auth.ValueObjects.Email`.

**Impact** : Pas de garantie que la validation fonctionne.

**Solution** : Ajouter suite de tests compl�te.

```elixir
# test/portfolio/auth/value_objects/email_test.exs
defmodule Portfolio.Auth.ValueObjects.EmailTest do
  use ExUnit.Case, async: true

  alias Portfolio.Auth.ValueObjects.Email

  describe "new/1" do
    test "accepts valid email" do
      assert {:ok, %Email{value: "test@example.com"}} =
        Email.new("test@example.com")
    end

    test "normalizes to lowercase" do
      assert {:ok, %Email{value: "test@example.com"}} =
        Email.new("Test@EXAMPLE.COM")
    end

    test "trims whitespace" do
      assert {:ok, %Email{value: "test@example.com"}} =
        Email.new("  test@example.com  ")
    end

    test "rejects email without @" do
      assert {:error, :invalid_email} = Email.new("invalid")
    end

    test "rejects email too long" do
      long_email = String.duplicate("a", 250) <> "@example.com"
      assert {:error, :too_long} = Email.new(long_email)
    end

    test "accepts special characters" do
      assert {:ok, _} = Email.new("user+tag@example.com")
      assert {:ok, _} = Email.new("user.name@example.com")
    end
  end

  describe "domain/1" do
    test "extracts domain" do
      email = Email.new!("user@example.com")
      assert Email.domain(email) == "example.com"
    end
  end

  describe "local_part/1" do
    test "extracts local part" do
      email = Email.new!("user@example.com")
      assert Email.local_part(email) == "user"
    end
  end
end
```

**Priorité** : **Haute** (qualité).

### 6. Emails internationaux non supportés

**Observation** : Regex RFC 5322 ne supporte pas les caract�res accentués dans le domaine.

**Impact** : Emails comme `test@münchen.de` rejetés.

**Solution** : Ajouter support IDN (biblioth�que `:idna`).

**Priorité** : **Moyenne** (nice-to-have, pas critique).

### 7. Validation DNS non implémentée

**Observation** : Pas de vérification que le domaine email existe (MX records).

**Impact** : Emails avec domaines inexistants acceptés (`test@nonexistent12345.com`).

**Solution** : Ajouter validation DNS async optionnelle.

**Priorité** : **Basse** (nice-to-have, pas critique pour portfolio).

## Conséquences

### Positives

- Validation RFC 5322 robuste (format correct)
- Type CITEXT pour unicité case-insensitive
- Double validation unicité (unsafe + constraint)
- Normalisation lowercase appliquée
- Value Object Email existe (préparation future)
- Magic link fait office de vérification implicite

### Négatives

- Duplication de code critique (3 regex identiques)
- Longueur max incohérente (160 vs 254)
- Value Object Email inutilisé (code mort)
- Trim manquant dans User schema
- Pas de tests Value Object
- Emails internationaux non supportés
- Validation DNS non implémentée

### Neutres

- CITEXT rend downcase redondant (mais gardé pour cohérence)
- Pas de blocage emails jetables (non nécessaire actuellement)
- Pas de normalisation Gmail (nice-to-have)

## Améliorations futures

### Court terme (priorité critique)
1. Migrer vers Ecto Type custom + Value Object
2. Harmoniser max_length � 254 partout
3. Ajouter String.trim dans User.validate_email
4. Supprimer duplication de regex

### Moyen terme (priorité haute)
1. Ajouter tests complets Value Object Email
2. Vérifier normalisation appliquée partout
3. Support emails internationaux (IDN)
4. Améliorer messages d'erreur

### Long terme (nice-to-have)
1. Validation DNS MX record (async, optionnel)
2. Blocage emails jetables (si abus constatés)
3. Normalisation Gmail (si abus constatés)

## Références

### Standards
- RFC 5322 (Internet Message Format) : https://www.rfc-editor.org/rfc/rfc5322
- RFC 5890 (IDNA) : https://www.rfc-editor.org/rfc/rfc5890
- RFC 6531 (SMTP UTF8) : https://www.rfc-editor.org/rfc/rfc6531

### Documentation PostgreSQL
- CITEXT extension : https://www.postgresql.org/docs/current/citext.html
- Constraints : https://www.postgresql.org/docs/current/ddl-constraints.html

### Biblioth�ques Elixir
- email_checker : https://hex.pm/packages/email_checker
- burnex : https://hex.pm/packages/burnex
- idna : https://hex.pm/packages/idna

### Articles
- Email Validation Best Practices : https://www.rfc-editor.org/rfc/rfc3696#section-3
- OWASP Input Validation : https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html

### Fichiers concernés
- `lib/portfolio/auth/user.ex` (validation actuelle)
- `lib/portfolio/auth/value_objects/email.ex` (Value Object inutilisé)
- `lib/portfolio_web/live/auth_live/login.ex` (validation frontend)
- `priv/repo/migrations/20250918132032_create_users_auth_tables.exs` (CITEXT, index unique)
