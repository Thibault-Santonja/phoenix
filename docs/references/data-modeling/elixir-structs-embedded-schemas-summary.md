# Structs and Embedded Schemas in Elixir: Beyond Maps

A comprehensive guide to understanding Elixir structs and Ecto embedded schemas, their inner workings, and practical use cases beyond database interactions.

---

## Overview

This guide explores structs and Ecto schemas in depth, covering their implementation details, capabilities, and practical applications. While most developers use structs regularly and know about Ecto schemas in database contexts, embedded schemas offer powerful features for validation, API design, and form handling without requiring database backing.

---

## Part 1: Understanding Structs

### What Is a Struct?

**Conceptually:**
- The closest thing Elixir has to a class (visually)
- Functionally: a named map with enhanced features
- Use when you need stricter guarantees than plain maps provide

**Under the hood:**
- Tagged maps with a special `__struct__` key identifying the module
- Enhanced maps with compile-time validation and default values
- Provides compile-time guarantees and runtime safety

---

## How Structs Work Behind the Scenes

### Basic Struct Definition

```elixir
defmodule User do
  defstruct [:name, :email, :age]
end
```

### The `defstruct` Macro

The `defstruct` macro (from `Kernel.Utils`) enhances maps by:

1. **Preventing duplicate definitions** - Can't call `defstruct` twice in the same module
2. **Key validation** - Ensures only specific keys are accessed
3. **Optional key enforcement** - Can require certain keys to be present
4. **Compile-time guarantees** - Validates struct fields during compilation

---

### Struct vs Map Comparison

**Plain map:**
```elixir
map_user = %{name: "John", email: "john@example.com", age: 30}
```

**Struct:**
```elixir
user = %User{name: "John", email: "john@example.com", age: 30}
```

### The Hidden `__struct__` Field

Every struct has an automatically added `__struct__` field:

```elixir
iex> Map.keys(user)
[:name, :__struct__, :email, :age]

iex> user.__struct__
User
```

This field helps Elixir distinguish between regular maps and structs.

---

## Key Features of Structs

### 1. Strict Keys (Compile-Time Validation)

**Valid usage:**
```elixir
%User{name: "John", email: "john@example.com"}
```

**Invalid usage (compile-time error):**
```elixir
%User{name: "John", foo: "value"}
# ** (KeyError) key :foo not found expanding struct: User.__struct__/1
```

**Key insights:**
- Structs provide compile-time guarantees about valid keys
- Invalid keys are caught during compilation, not runtime
- Prevents typos and accidental key additions

---

### 2. Access Behavior Differences

**Dot notation (works the same for maps and structs):**

```elixir
user.foo
# ** (KeyError) key :foo not found in: %User{...}

map_user.foo
# ** (KeyError) key :foo not found in: %{...}
```

**Bracket notation (different behavior):**

```elixir
map_user[:foo]
# nil

user[:foo]
# ** (UndefinedFunctionError) function User.fetch/2 is undefined
# (User does not implement the Access behavior)
```

**Why the difference?**
- Structs don't implement the `Access` protocol
- Bracket notation fails because `Access` is not available
- This is by design - use dot notation for structs

---

### 3. Pattern Matching

**Matching on non-existent keys:**

```elixir
%{foo: foo} = user
# ** (MatchError) no match of right hand side value

%{foo: foo} = map_user
# ** (MatchError) no match of right hand side value
```

Both fail the same way, but structs provide additional pattern matching capabilities (covered later).

---

### 4. Required Keys with `@enforce_keys`

**Definition:**
```elixir
defmodule User do
  @enforce_keys [:email]
  defstruct name: nil, email: nil, age: nil
end
```

**Valid usage:**
```elixir
user = %User{email: "john@example.com"}
user = %User{email: "john@example.com", age: 25}
user = %User{email: "john@example.com", name: "John"}
user = %User{email: "john@example.com", name: "John", age: 25}
```

**Invalid usage:**
```elixir
user = %User{age: 30}
# ** (ArgumentError) the following keys must also be given when building 
# struct User: [:email]
```

**Use cases:**
- Enforce critical fields that must always be present
- Prevent creation of incomplete data structures
- Document required fields in code

---

### 5. Default Values

**Definition:**
```elixir
defmodule User do
  defstruct [name: nil, email: nil, age: 20]
end
```

**Usage:**
```elixir
%User{}
# %User{name: nil, email: nil, age: 20}
```

**Applications:**
- Configuration options
- Sensible defaults for optional fields
- Foundation for Ecto schemas

---

### 6. Enhanced Pattern Matching in Function Clauses

Structs enable powerful pattern matching beyond what maps offer.

**Basic pattern matching:**
```elixir
def process_user(%User{age: age}) when age >= 18 do
  "Adult user"
end

def process_user(%User{age: age}) when age < 18 do
  "Minor user"
end

def process_user(%User{name: name, email: email}) do
  "User #{name} with email #{email}"
end
```

**Key benefits:**
- Compiler statically verifies field names
- Catches typos and invalid keys at compile time
- Must match exact struct type, not just any map with similar keys

**Type enforcement:**
```elixir
# This function ONLY accepts %User{} structs
# Not random maps, not other structs - specifically User
def process_user(%User{name: name}) do
  # ...
end
```

---

### Advanced Pattern Matching

**Multiple struct types:**
```elixir
def process_user(%m{name: name} = user) when m in [User, PowerUser] do
  "User #{name} is a #{m}"
end
```

This accepts both `%User{}` and `%PowerUser{}` structs.

**Any struct (but not maps):**
```elixir
def process_user(%_{name: name} = user) do
  "User #{name}"
end
```

The `%_{}` syntax matches any struct but excludes regular maps.

**Invalid patterns (compile-time error):**
```elixir
def process_user(%User{foo: foo}), do: nil
# ** (CompileError) key :foo not found in struct User
```

---

### 7. Dialyzer Type Specifications

**Pattern for type-safe structs:**

```elixir
defmodule User do
  defstruct [:name, :email, :age]
  
  @type t :: %__MODULE__{
    name: String.t() | nil,
    email: String.t() | nil,
    age: non_neg_integer() | nil
  }
end

@spec create_user(String.t(), String.t(), non_neg_integer()) :: User.t()
def create_user(name, email, age) do
  %User{name: name, email: email, age: age}
end
```

**Benefits:**
- Static analysis catches type mismatches
- Better tooling support
- Self-documenting code

**Future outlook:**
- Native Elixir types are evolving
- Dialyzer typespecs may eventually be replaced
- For now, this pattern remains useful

---

## Summary: Why Use Structs?

### Advantages Over Plain Maps

| Feature | Plain Map | Struct |
|---------|-----------|--------|
| **Compile-time validation** | ❌ | ✅ Keys validated at compile time |
| **Enforced keys** | ❌ | ✅ Can require fields |
| **Default values** | ❌ | ✅ Built-in defaults |
| **Pattern matching** | Basic | ✅ Enhanced with type checking |
| **Static analysis** | Limited | ✅ Better Dialyzer support |
| **Self-documenting** | ❌ | ✅ Clear data contracts |
| **Access protocol** | ✅ | ❌ Must use dot notation |

### Trade-offs

**Pros:**
- More powerful and safer than maps
- Compile-time guarantees
- Better tooling and editor support
- Self-documenting code
- Type safety

**Cons:**
- Slightly more boilerplate
- No `Access` protocol support
- Less flexible than maps

---

## Part 2: Embedded Schemas

### What Is an Embedded Schema?

**Two types of Ecto schemas:**

1. **Regular schemas** - Backed by database tables/views
2. **Embedded schemas** - Not directly associated with database tables

**Original purpose:**
- Power `jsonb` columns in databases
- Use with `embeds_one`, `embeds_many`, etc.

**Modern usage:**
With the split of `ecto` and `ecto_sql`, embedded schemas are now used for much more than database operations.

---

## How Embedded Schemas Work

### Basic Definition

```elixir
defmodule Address do
  use Ecto.Schema
  
  embedded_schema do
    field :street, :string
    field :city, :string
    field :postal_code, :string
    field :country, :string, default: "US"
  end
end
```

This creates a struct with Ecto's schema capabilities layered on top.

---

### Behind the Scenes: The `use Ecto.Schema` Macro

**Step 1: Register accumulating module attributes**

Module attributes are named values that store data within a module:

```elixir
defmodule MyModule do
  @foo "bar"
  def get_foo, do: @foo
  
  @foo "baz"
  def get_foo_also, do: @foo
end
```

Normally, reassigning replaces the value:
- `get_foo()` → `"bar"`
- `get_foo_also()` → `"baz"`

**Accumulating attributes:**
```elixir
Module.register_attribute(__MODULE__, :foo, accumulate: true)
```

Now values append to a list instead of replacing:
- `get_foo_also()` → `["bar", "baz"]`

**Ecto registers 11 accumulating attributes:**
- Fields
- Associations
- Primary keys
- And more...

These store the complete schema definition for later use.

---

### The `embedded_schema` Macro

**Equivalent definitions:**

```elixir
# Using embedded_schema
embedded_schema do
  # ...
end

# Using schema with nil source (exactly the same!)
schema nil do
  # ...
end
```

The only difference: `embedded_schema` explicitly sets source to `nil`.

---

### What Happens During Schema Definition

**Step-by-step process:**

1. **Inject helpers** - Import functions like `field`, `embeds_one`, etc.

2. **Run block code** - Calls to helpers populate accumulating attributes with schema info

3. **Generate struct fields** - Call `Ecto.Schema.__schema__/1` to extract field definitions

4. **Define struct** - Call `defstruct` with the field list

5. **Add Ecto functions** - Define `__changeset__/0` and `__schema__/1` functions
   - `__changeset__` enables changeset usage
   - `__schema__` provides introspection for queries

**Result for our Address example:**

```elixir
defstruct [street: nil, city: nil, postal_code: nil, country: "US"]
```

Plus the special Ecto functions for changeset and query support.

**Note:** `@enforce_keys` is not set automatically, but you can add it manually before `embedded_schema`.

---

## Changesets and Validation

### Basic Changeset Implementation

```elixir
defmodule Address do
  use Ecto.Schema
  import Ecto.Changeset
  
  embedded_schema do
    field :street, :string
    field :city, :string
    field :postal_code, :string
    field :country, :string, default: "US"
  end
  
  def changeset(address, attrs) do
    address
    |> cast(attrs, [:street, :city, :postal_code, :country])
    |> validate_required([:street, :city, :postal_code])
    |> validate_format(:postal_code, ~r/^\d{5}(-\d{4})?$/)
  end
end
```

**Features:**
- Type enforcement
- Format validation
- Required field checks
- Invalid marking when rules fail

**Key insight:** Originally designed for databases, but embedded schemas don't need backing tables, enabling broader use cases.

---

## Practical Use Cases

### 1. API Input Prevalidation (Command Pattern)

Embedded schemas with changesets provide efficient API input parsing and sanitization.

**Implementation:**

```elixir
defmodule CreateUserCommand do
  use Ecto.Schema
  import Ecto.Changeset
  
  embedded_schema do
    field :name, :string
    field :email, :string
    field :age, :integer
  end
  
  def changeset(params) do
    %__MODULE__{}
    |> cast(params, [:name, :email, :age])
    |> validate_required([:name, :email])
    |> validate_format(:email, ~r/@/)
    |> validate_number(:age, greater_than: 0)
  end
  
  def validate(params) do
    case changeset(params) do
      %Changeset{valid?: true} = changeset ->
        {:ok, Changeset.apply_changes(changeset)}
      
      %Changeset{valid?: false} = changeset ->
        {:error, changeset}
    end
  end
end
```

**Controller usage:**

```elixir
defmodule UserController do
  def create(conn, %{"user" => user_params}) do
    with {:ok, command} <- CreateUserCommand.validate(user_params) do
      UserService.create_user(command)
      send_resp(conn, 200)
    end
    # FallbackController handles error response
  end
end
```

---

### Benefits of the Command Pattern

**Fast, cheap validation without database:**
- Email format validation
- Required field checks
- Type validation (string, integer, etc.)
- Range checks (age between 18-30)
- Any constraint that doesn't need database access

**Separates concerns:**

| Validation Type | Where | Cost |
|----------------|-------|------|
| Format/type checks | Command (embedded schema) | Cheap ⚡ |
| Uniqueness checks | Service (database) | Expensive 💾 |
| Foreign key validation | Service (database) | Expensive 💾 |
| Complex business rules | Service (database) | Expensive 💾 |

**Fail-fast approach:**
- Reject invalid requests immediately
- Avoid wasting resources on invalid data
- All cheap validations at once before expensive checks

**Reusability:**
- Valid changeset → Use `Changeset.apply_changes/1` to get struct
- Pass struct to business logic
- Same command works in API, LiveView, admin dashboard, etc.
- Two simpler things instead of one complex thing

---

### 2. Powering Forms in LiveView

LiveView forms use `%Form{}` structs (wrappers around changesets), and embedded schemas are perfect for this.

**Key insight:** Schemas powering changesets don't need database backing.

**Mount function:**

```elixir
def mount(_params, _session, socket) do
  changeset = CreateUserCommand.changeset(%{})
  {:ok, assign(socket, changeset: changeset)}
end
```

**Form rendering:**

```elixir
def user_form(assigns) do
  ~H"""
  <.form 
    for={to_form(@changeset)} 
    :let={f} 
    phx-change="validate" 
    phx-submit="create">
    
    <.input type="text" field={f[:name]} />
    <.input type="email" field={f[:email]} />
    <.input type="number" field={f[:age]} />
  </.form>
  """
end
```

---

### Event Handlers

**Validation on change:**

```elixir
def handle_event("validate", %{"user" => params}, socket) do
  changeset = 
    params
    |> CreateUserCommand.changeset()
    |> Map.put(:action, :validate)  # Makes errors visible
  
  {:noreply, assign(socket, changeset: changeset)}
end
```

**Form submission:**

```elixir
def handle_event("create", %{"user" => params}, socket) do
  case CreateUserCommand.validate(params) do
    {:ok, command} ->
      # Expect success - form properly set up, prevalidation passed
      # If it fails, let it crash (Elixir style!)
      {:ok, user} = UserService.create_user(command)
      {:noreply, put_flash(socket, :info, "User created!")}
    
    {:error, changeset} ->
      changeset = Map.put(changeset, :action, :validate)
      {:noreply, assign(socket, changeset: changeset)}
  end
end
```

---

### Code Reuse Benefits

**Shared validation logic:**
- API endpoints use `CreateUserCommand`
- LiveView forms use `CreateUserCommand`
- Admin dashboards use `CreateUserCommand`
- ~66% code reuse across interfaces

**Flexibility:**
- If command doesn't fit, create custom embedded schema in LiveView
- Or use schemaless changesets
- Schemaless changesets need name: `to_form(changeset, as: :my_name)`

---

### Important: Making Errors Visible

**The `:action` field requirement:**

Validation errors aren't visible until `changeset.action` is non-nil.

**Why?**
- Empty forms shouldn't show errors (user hasn't made mistakes yet)
- Phoenix forms check `:action` to decide whether to display errors
- `Repo.insert/update` automatically set `:action` to `:insert`/`:update`
- Embedded schemas never call `Repo`, so action stays `nil`

**Solution:**
Manually set action using `Map.put(changeset, :action, :validate)`:

```elixir
changeset = 
  params
  |> CreateUserCommand.changeset()
  |> Map.put(:action, :validate)
```

Without this, your form won't show validation errors!

---

## Alternative Approaches and Cautions

### The `typed_struct` Package

**Purpose:** Eliminate boilerplate by auto-generating type specs

```elixir
defmodule User do
  use TypedStruct
  
  typedstruct do
    field :name, String.t()
    field :email, String.t()
    field :age, non_neg_integer()
  end
end
```

**Equivalent to:**
- Defining struct with `defstruct`
- Enforcing all keys
- Declaring `User.t()` type

**Concerns:**
- ⚠️ Not receiving updates recently
- ⚠️ Long-term maintenance questionable
- ⚠️ Usefulness decreasing with native Elixir types

---

### The `domo` Package

**Purpose:** Build on typed structs with utility functions

**Features:**
- Generates `new/1` and `new!/1` functions
- Additional validation helpers

**Real-world experience (from V7):**

**Pros:**
- ✅ Proven useful in production

**Cons:**
- ❌ Significant compilation time overhead
- ❌ Regular compilation deadlocks
- ⚠️ Team considering removal

**Recommendation:** Use with caution, evaluate impact on build times.

---

## The Future: Native Elixir Types

### Current State

The Elixir type system is growing:
- More compiler inference
- Catching more bugs automatically
- Background improvements are free

**Dialyzer status:**
- Still useful
- Improvements don't conflict
- Type system may reveal where to improve specs

---

### What's Coming

**Native type specifications:**
- Will likely replace Dialyzer typespecs
- Should be easy migration path
- Not available yet

**Strategy:**
- Continue using Dialyzer typespecs for now
- Lean into things that benefit from type system
- Best of both worlds approach

---

## Complete Comparison Table

| Feature | Plain Map | Struct | Embedded Schema |
|---------|-----------|--------|-----------------|
| **Compile-time key validation** | ❌ | ✅ | ✅ |
| **Required keys** | ❌ | ✅ | Manual with `@enforce_keys` |
| **Default values** | ❌ | ✅ | ✅ |
| **Type validation** | ❌ | Manual | ✅ Built-in with changesets |
| **Format validation** | ❌ | Manual | ✅ Built-in with changesets |
| **Database backing** | N/A | N/A | Optional |
| **Form integration** | ❌ | ❌ | ✅ Via changesets |
| **Dialyzer types** | ❌ | ✅ Manual | ✅ Manual |
| **Pattern matching** | Basic | ✅ Enhanced | ✅ Enhanced |
| **Access protocol** | ✅ | ❌ | ❌ |
| **Changeset support** | ❌ | ❌ | ✅ Native |
| **Learning curve** | Low | Low | Medium |
| **Boilerplate** | None | Low | Medium |

---

## Decision Guide: Which to Use?

### Use Plain Maps When:
- ✅ Maximum flexibility needed
- ✅ Dynamic keys required
- ✅ Simple, temporary data structures
- ✅ Performance critical (minimal overhead)

### Use Structs When:
- ✅ Fixed set of fields known at compile time
- ✅ Type safety important
- ✅ No validation logic needed
- ✅ Better pattern matching desired
- ✅ Self-documenting code preferred

### Use Embedded Schemas When:
- ✅ Complex validation rules needed
- ✅ Form integration required (LiveView/Phoenix)
- ✅ API input validation needed
- ✅ Changesets beneficial
- ✅ Code reuse across interfaces
- ✅ "Command" pattern appropriate
- ✅ Database-style validation without database

---

## Best Practices

### For Structs

**Do:**
- ✅ Use for domain models with fixed structure
- ✅ Define `t()` type for Dialyzer
- ✅ Use `@enforce_keys` for critical fields
- ✅ Leverage pattern matching in function heads
- ✅ Document expected values in types

**Don't:**
- ❌ Try to use `Access` protocol (`struct[:key]`)
- ❌ Define same struct twice in module
- ❌ Match on undefined keys in patterns
- ❌ Use when dynamic fields needed

---

### For Embedded Schemas

**Do:**
- ✅ Use for API input validation (command pattern)
- ✅ Share between API and LiveView
- ✅ Set `:action` manually for error visibility
- ✅ Separate cheap validation from expensive
- ✅ Use `apply_changes/1` to get validated struct
- ✅ Create specific schemas per use case

**Don't:**
- ❌ Mix validation and business logic
- ❌ Forget to set changeset action for forms
- ❌ Perform database checks in command validation
- ❌ Reuse database-backed schemas for commands
- ❌ Skip `validate/1` wrapper function

---

### Command Pattern Best Practices

**Structure:**

```elixir
defmodule MyCommand do
  use Ecto.Schema
  import Ecto.Changeset
  
  embedded_schema do
    # fields
  end
  
  def changeset(params) do
    # validation rules
  end
  
  def validate(params) do
    case changeset(params) do
      %{valid?: true} = cs -> {:ok, apply_changes(cs)}
      %{valid?: false} = cs -> {:error, cs}
    end
  end
end
```

**Naming convention:**
- Use `*Command` suffix for API/form commands
- Clear intent: "this commands the system to do something"

---

## Summary

### Key Takeaways

**Structs:**
1. Enhanced maps with compile-time guarantees
2. Stricter, safer, more powerful than plain maps
3. Minimal overhead for significant benefits
4. Use for fixed data structures

**Embedded Schemas:**
1. Structs + Ecto validation power
2. Don't require database backing
3. Perfect for API validation and forms
4. Enable code reuse across interfaces
5. Command pattern for clean architecture

**General Principles:**
- Choose the right tool for the job
- Plain maps → flexibility
- Structs → safety and clarity
- Embedded schemas → validation and forms
- Let compile-time checks catch bugs
- Validate at boundaries

---

## Real-World Application Architecture

**Typical flow with embedded schemas:**

```
1. API Request
   ↓
2. Command Validation (embedded schema)
   ├─ Invalid? → Return 400 error
   └─ Valid? → Continue
      ↓
3. Business Logic (service)
   ├─ Database validations
   ├─ Complex rules
   └─ Side effects
      ↓
4. Response
```

**Benefits:**
- Fast failure on invalid input
- No wasted database queries
- Clean separation of concerns
- Reusable validation logic
- Better error messages

---

## Additional Resources

- [Elixir Kernel.Utils defstruct](https://github.com/elixir-lang/elixir/blob/v1.18.4/lib/elixir/lib/kernel/utils.ex#L103)
- [Ecto Schema Documentation](https://hexdocs.pm/ecto/Ecto.Schema.html)
- [Ecto Changeset Documentation](https://hexdocs.pm/ecto/Ecto.Changeset.html)
- [Phoenix LiveView Form Bindings](https://hexdocs.pm/phoenix_live_view/form-bindings.html)
- [Ecto Schemaless Changesets](https://hexdocs.pm/ecto/Ecto.Changeset.html#module-schemaless-changesets)
- [typed_struct package](https://hex.pm/packages/typed_struct)
- [domo package](https://hexdocs.pm/domo/Domo.html)

---

## Source

**Article**: [Structs and Embedded Schemas in Elixir: Beyond Maps](https://blog.appsignal.com/2025/09/09/structs-and-embedded-schemas-in-elixir-beyond-maps.html)

---

*This comprehensive guide provides deep understanding of Elixir structs and embedded schemas, from implementation details to practical patterns for building robust, maintainable applications with strong validation and clean architecture.*
