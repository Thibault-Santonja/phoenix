# Data Validation in Elixir and Phoenix - Complete Series Summary

A comprehensive two-part guide to validating data at boundaries in Elixir applications, covering pattern matching, guards, Ecto changesets, and NimbleOptions for robust data handling.

---

## Part 1: Validate Data in a Phoenix Application for Elixir

### Overview
This guide explores how to prevent bad data from entering your Elixir system by validating data at boundaries using native Elixir techniques like pattern matching and guards.

---

## The Importance of Rejecting Bad Data

### Why Validation Matters

Bad data must be dealt with immediately, or it will spread throughout your system and degrade other data. Given the difficulty and time required to fix data issues, preventing bad data from entering your system is essential.

**Official Elixir guidance:**

> [...] when you don't validate the values at the boundary, the internals of your library are never quite sure which kind of values they are working with.

This applies not just to libraries, but to any Elixir code.

### Key Principles

**Always validate at the boundary:**
- When receiving multiple options
- When working with external data
- Convert untrusted data to structured data immediately

**Examples:**
- GenServer started with options → validate when server starts
- Database/socket returns map of strings → validate and convert to struct/atom map
- External API data → validate before processing

---

## Understanding Boundaries

### What Is a Boundary?

A boundary exists wherever your functions accept unknown or unsafe data that will later be processed based on assumptions about that data.

### Common Boundaries in Applications

#### 1. Web Layer → Business Logic
**Example:** Phoenix Controllers to Contexts

- JSON parameters parsed into maps with string keys
- Clients can send any data: incorrect keys, invalid values, extra fields
- Solution: Process untrusted data in one location (typically a Phoenix Context)
- Convert to well-known shape with validated content
- Domain logic can then trust the data without re-verification

#### 2. GenServers
Data sent to GenServers needs validation before being processed into state changes.

#### 3. Web Requests
Data flows from HTTP requests through domain logic to database tables.

#### 4. Console Input
Command-line arguments need processing before use in CLI applications.

#### 5. Bounded Contexts
Data has different meanings in different contexts:
- A `Customer` might have a billing address
- A `User` might have a username
- Both refer to the same person but in different contexts

**Takeaway:** Boundaries are everywhere, making these validation techniques universally applicable.

---

## Validation Techniques Using Pattern Matching and Guards

### 1. Case Clauses

Case clauses explicitly list the data you agree to handle, communicating intent clearly.

**Example:**

```elixir
case Account.setup(...) do
  {:ok, %Account{suspended: true}} -> 
    # Handle suspended account
    
  {:ok, %Account{initialized: true}} -> 
    # Handle initialized account
    
  {:error, ...} -> 
    # Handle error
end
```

**Benefits:**
- Clearly communicates expected outcomes
- Pattern order matters: `suspended` supersedes `initialized`
- No catch-all clause means unexpected values cause crashes
- **Let it crash philosophy**: Better to crash and restart cleanly than propagate dirty data

**Why no catch-all?**
- Any other return value is unexpected and considered a bug
- If you knew how to handle it, it would have its own case clause
- OTP system can restart the process from a clean "known good" state

---

### 2. Pattern Matching in Function Heads

Pattern matching in function heads ensures data conforms to expectations and communicates intent.

**Example 1: Struct matching**

```elixir
defp suspend(%Account{} = account)
```

**Example 2: Attribute matching**

```elixir
defp suspend(%{suspended: _} = account)
```

**Key Differences:**

| Approach | Intent | Safety |
|----------|--------|--------|
| `%Account{}` | Explicitly expects `Account` struct | ✅ Type-safe, can be used in functions expecting `Account` |
| `%{suspended: _}` | Relies on attribute presence | ⚠️ Unsafe - nothing prevents passing `%User{}` with `suspended` field |

**Recommendation:** Always prefer struct matching for type safety.

---

### 3. Balancing Clarity vs. Convenience

**Anti-pattern: Over-matching in function heads**

```elixir
def handle_call(:checkout, %{workers: [h | t], monitors: monitors}) do
  # ...
end

def handle_call(:checkout, %{workers: [], idle_overflow: [h | t]}) do
  # ...
end

def handle_call(:checkout, %{workers: [], idle_overflow: [], 
                             overflow: overflow, overflow_max: max, 
                             worker_sup: sup, spec: spec, 
                             monitors: monitors}) when overflow < max do
  # ...
end

def handle_call(:checkout, %{workers: [], idle_overflow: [], 
                             overflow: overflow, overflow_max: max, 
                             waiting: waiting}) do
  # ...
end
```

**Problem:** Hard to see which matches differentiate function heads vs. which are for convenience.

**Better approach: Match only what differentiates, bind in body**

```elixir
def handle_call(:checkout, %{workers: [_|_]} = state) do
  %{monitors: monitors} = state
  # ...
end

def handle_call(:checkout, %{workers: [], idle_overflow: [_|_]}) do
  # ...
end

def handle_call(:checkout, %{workers: [], idle_overflow: [], 
                             overflow: overflow, 
                             overflow_max: max} = state) when overflow < max do
  %{worker_sup: sup, spec: spec, monitors: monitors} = state
  # ...
end

def handle_call(:checkout, state) do
  %{workers: [], idle_overflow: [], overflow: overflow, 
    overflow_max: max, waiting: waiting} = state
  # ...
end
```

**Benefits:**
- More obvious what differentiates each function clause
- Bindings for later use are in function body
- More resilient to reordering or refactoring

---

### José Valim's Rule

> If the key is necessary when matching the pattern, keep it in the pattern, otherwise, move it to the body.

**Example:**

```elixir
def some_fun(%{field1: :value} = struct) do
  %{field2: value2, field3: value3} = struct
  # ...
end
```

---

### 4. Defensive Matching

Sometimes it's beneficial to be overly explicit for resilience:

```elixir
def handle_call(:checkout, %{workers: [], idle_overflow: [], ...})
```

Even if an earlier clause would match, explicitly matching empty lists makes the code:
- More resilient to clause reordering
- Clearer about expected context
- Less prone to bugs during refactoring

---

### 5. Guard Clauses

Guard clauses tighten the definition of "valid data" to make code safer by design.

**Basic guards:**

```elixir
def annotate(%Account{} = account, annotation) when is_binary(annotation)
```

**Guards in case statements:**

```elixir
case account do
  %Account{payment_method: payment_method} when not is_nil(payment_method) ->
    # Process payment
end
```

**Guards work with:**
- `case` statements
- `with` statements
- `cond` statements
- Function heads

---

### 6. Custom Guards

Custom guards communicate intent clearly and prevent bad data while improving code expressiveness.

**Step 1: Define guard in separate module**

```elixir
defmodule Account.Guards do
  defguard is_suspended(account) 
    when is_struct(account, Account) and account.suspended
end
```

**Important:** Custom guards must be defined in a separate module from where they're used.

**Step 2: Import and use**

```elixir
import Account.Guards

case fetch_account(...) do
  %Account{} = account when is_suspended(account) ->
    # Handle suspended account
  # ...
end
```

**Benefits:**
- Highly expressive code
- Reusable validation logic
- Clear intent
- Type safety combined with custom business logic

---

## Summary of Part 1

### Key Takeaways

1. **Validate at boundaries** - Process untrusted data once at entry points
2. **Use pattern matching** - Leverage case clauses to explicitly handle expected cases
3. **Match in function heads** - Use struct matching for type safety
4. **Keep heads clean** - Match only what differentiates, bind rest in body
5. **Use guard clauses** - Tighten valid data definitions
6. **Create custom guards** - Improve expressiveness for domain-specific validations
7. **Let it crash** - Don't handle unexpected data, let OTP restart cleanly

### When to Use Each Technique

| Technique | Use Case |
|-----------|----------|
| Case clauses | Explicitly listing expected outcomes |
| Function head matching | Type safety and intent communication |
| Guard clauses | Tightening valid data constraints |
| Custom guards | Reusable domain-specific validations |

---

## Part 2: Validating Data Using Ecto and NimbleOptions

### Overview
This part explores how Ecto and NimbleOptions libraries can assist with data validation, even when not interacting with databases.

---

## Using Ecto for Validation

Ecto provides powerful validation capabilities that can be leveraged for data validation even without database interaction.

### Schemaless Changesets

Schemaless changesets are Ecto changesets not tied to database tables, providing a convenient way to create validated data structures.

**Benefits:**
- Prevent bad data from entering structs
- Useful for untrusted input (API requests, public APIs)
- Convert plain maps to validated structs
- Other module functions can accept structs (indicating vetted data)

**Implementation:**

```elixir
# in the Account module
defstruct [:name, suspended: false]

def from_params(%{} = params) do
  data = %{}
  types = %{name: :string, suspended: :boolean}
  
  changeset = 
    {data, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:name])
    |> Ecto.Changeset.validate_length(:name, min: 3)
  
  case Ecto.Changeset.apply_action(changeset, :insert) do
    {:ok, data} -> 
      {:ok, struct(__MODULE__, data)}
    {:error, _} = error -> 
      error
  end
end
```

**Usage:**

```elixir
Account.from_params(%{name: "ACME", suspended: false})
```

**Key features:**
- `types` map defines expected fields and types
- `cast/3` converts and filters parameters
- Validation functions ensure data quality
- `apply_action/2` finalizes the changeset
- Returns `{:ok, struct}` or `{:error, changeset}`

---

### Why apply_action with :insert?

The `:insert` action is important for Phoenix forms.

**Phoenix form error rendering:**
- Forms inspect the action to determine if errors should be displayed
- No action set = no errors rendered
- Useful for empty forms (don't berate users before they've made mistakes)
- Setting `:insert` or `:update` action enables error display

**For Phoenix forms:**

```elixir
case Ecto.Changeset.apply_action(changeset, :insert) do
  {:ok, data} -> {:ok, struct(__MODULE__, data)}
  {:error, _} = error -> error
end
```

The error tuple can be used directly in Phoenix forms to display validation errors.

**If not using Phoenix forms:**
You can skip `apply_action` and just work with the changeset directly.

---

### Dynamic Types

Since `types` is just a map, it can be passed as an argument for runtime flexibility:

```elixir
def from_params(%{} = params, types) do
  # Use provided types instead of hardcoded ones
end
```

---

### Embedded Schemas

If you already have a struct and want Ecto validation, use embedded schemas instead of basic structs.

**Trade-offs:**

| Feature | Schemaless Changeset | Embedded Schema |
|---------|---------------------|----------------|
| Requires struct | No | Yes |
| Type flexibility | Dynamic (runtime) | Static (compile-time) |
| Convenience | Less | More |
| Flexibility | More | Less |

**Implementation:**

```elixir
# in the Account module
@primary_key false
embedded_schema do
  field :name, :string
  field :suspended, :boolean
end

def from_params(%{} = params) do
  changeset = 
    %__MODULE__{}
    |> Ecto.Changeset.cast(params, [:name, :suspended])
    |> Ecto.Changeset.validate_required([:name])
    |> Ecto.Changeset.validate_length(:name, min: 3)
  
  case Ecto.Changeset.apply_action(changeset, :insert) do
    {:ok, data} -> {:ok, data}
    {:error, _} = error -> error
  end
end
```

**Key differences:**
- Schema defined with `embedded_schema` macro
- Fields and types declared at compile-time
- `@primary_key false` since no database backing
- Slightly more convenient usage
- Types cannot vary at runtime

---

### When to Use Each Approach

**Use schemaless changesets when:**
- You don't have an existing struct
- Types need to be dynamic
- Maximum flexibility is required
- Working with ad-hoc validation scenarios

**Use embedded schemas when:**
- You have an existing struct
- Types are known at compile-time
- Convenience is preferred
- Working with consistent data structures

**Further reading:** [Ecto's Data mapping and validation guide](https://hexdocs.pm/ecto/data-mapping-and-validation.html)

---

## Validating Options with NimbleOptions

Many Elixir functions accept keyword lists as options (especially OTP modules like GenServers). NimbleOptions provides a lightweight, declarative way to validate these options.

### The Problem: Manual Validation

**Scenario:** Email function with template and configuration options

**Naive implementation:**

```elixir
def email(%Account{} = account, opts) when is_list(opts) do
  template = Keyword.fetch!(opts, :template)
  values = Keyword.get(opts, :values, [])
  account_url = Keyword.get(values, :landing_url)
  signature = Keyword.get(values, :signature, "Yours truly,\nACME.com")
  
  # email generation and sending goes here
  :ok
end
```

**Problems:**
- Crashes on missing required options (bad UX)
- No validation of option values
- No type checking
- Error handling is caller's problem

---

### Improved Manual Validation

```elixir
def email(%Account{} = account, opts) when is_list(opts) do
  with template when template in ~w(personal corporate)a <- 
         Keyword.get(opts, :template) do
    values = Keyword.get(opts, :values, [])
    landing_url = 
      Keyword.get(values, :landing_url, 
                  URI.parse("https://www.example.com/sign_in"))
    signature = 
      Keyword.get(values, :signature, "Yours truly,\nACME.com")
    
    # email generation and sending goes here
    :ok
  else
    nil -> 
      {:error, :missing_template}
    other when is_atom(other) -> 
      {:error, :invalid_template_value}
    _ -> 
      {:error, :invalid_template_type}
  end
end
```

**Problems:**
- Doesn't scale with number of options
- Hard to see permitted options at a glance
- Repetitive code
- Difficult to understand expected types

---

## NimbleOptions Library

NimbleOptions is a lightweight library for validating keyword lists with clear schemas.

### Basic Implementation

**Define schema:**

```elixir
@email_opts_schema [
  template: [
    required: true,
    type: {:in, ~w(personal corporate)a}
  ],
  values: [
    type: :keyword_list,
    default: [],
    keys: [
      landing_url: [
        type: {:struct, URI},
        default: URI.parse("https://www.example.com/sign_in")
      ],
      signature: [
        type: :string,
        default: "Yours truly,\nACME.com"
      ]
    ]
  ]
]
```

**Use in function:**

```elixir
def email(%Account{} = account, opts) when is_list(opts) do
  with {:ok, validated_options} <- 
         NimbleOptions.validate(opts, @email_opts_schema) do
    template = Keyword.fetch!(validated_options, :template)
    landing_url = validated_options[:values][:landing_url]
    signature = validated_options[:values][:signature]
    
    # email generation and sending goes here
    {:ok, validated_options}
  end
end
```

**Important:** Set `default: []` for nested keyword lists to enable cascading defaults.

---

### NimbleOptions in Action

**Valid calls:**

```elixir
# With defaults
iex> email(an_account, template: :personal)
{:ok, [
  template: :personal,
  values: [
    signature: "Yours truly,\nACME.com",
    landing_url: %URI{
      scheme: "https",
      host: "www.example.com",
      path: "/sign_in",
      port: 443
    }
  ]
]}

# With overrides
iex> email(an_account, 
           template: :personal, 
           values: [signature: "With love,\nBob"])
{:ok, [
  template: :personal,
  values: [
    signature: "With love,\nBob",
    landing_url: %URI{...}
  ]
]}
```

**Invalid value:**

```elixir
iex> email(an_account, template: :boom)
{:error, %NimbleOptions.ValidationError{
  key: :template,
  message: "invalid value for :template option: expected one of [:personal, :corporate], got: :boom"
}}
```

**Typo detection:**

```elixir
iex> email(an_account, 
           template: :personal, 
           values: [singature: "With love,\nBob"])
{:error, %NimbleOptions.ValidationError{
  key: [:singature],
  keys_path: [:values],
  message: "unknown options [:singature], valid options are: [:landing_url, :signature]"
}}
```

---

## Advanced NimbleOptions Features

### 1. Accepting Multiple Types

**Problem:** Requiring `URI` struct is inconvenient - users prefer strings.

**Solution: OR types**

```elixir
landing_url: [
  type: {:or, [{:struct, URI}, :string]},
  default: URI.parse("https://www.example.com/sign_in")
]
```

**Result:**

```elixir
iex> email(an_account, 
           template: :personal, 
           values: [landing_url: "https://my.app"])
{:ok, [
  template: :personal,
  values: [
    signature: "Yours truly,\nACME.com",
    landing_url: "https://my.app"
  ]
]}
```

**Remaining issues:**
1. Code must handle both string and URI types
2. Strings don't indicate validation (not clear if valid URI)

---

### 2. Custom Type Parsers

**Solution:** Use `:custom` type with parser function

```elixir
landing_url: [
  type: {:or, [
    {:struct, URI}, 
    {:custom, URI, :new, []}
  ]},
  default: URI.parse("https://www.example.com/sign_in")
]
```

**How it works:**
- `:custom` type expects `{module, function, args}` tuple
- Function must return `{:ok, value}` or `{:error, message}`
- `URI.new/1` already conforms to this interface
- Strings are parsed into `URI` structs automatically

**Result:**

```elixir
iex> email(an_account, 
           template: :personal, 
           values: [landing_url: "https://my.app"])
{:ok, [
  template: :personal,
  values: [
    signature: "Yours truly,\nACME.com",
    landing_url: %URI{
      scheme: "https",
      host: "my.app",
      port: 443
    }
  ]
]}
```

**Benefits:**
- Convenient string input
- Standardized `URI` struct output post-validation
- Type safety maintained
- Built-in validation (invalid URIs return errors)

---

## NimbleOptions Schema Features

### Available Types

| Type | Description | Example |
|------|-------------|---------|
| `:string` | String values | `"hello"` |
| `:atom` | Atom values | `:ok` |
| `:integer` | Integer values | `42` |
| `:boolean` | Boolean values | `true` |
| `:keyword_list` | Keyword lists | `[a: 1, b: 2]` |
| `{:in, list}` | Value must be in list | `{:in, [:a, :b]}` |
| `{:struct, module}` | Struct of type | `{:struct, URI}` |
| `{:or, types}` | One of multiple types | `{:or, [:string, :atom]}` |
| `{:custom, m, f, a}` | Custom parser | `{:custom, URI, :new, []}` |

### Schema Options

| Option | Purpose |
|--------|---------|
| `required: true` | Field must be provided |
| `type: ...` | Expected type |
| `default: value` | Default value if not provided |
| `keys: [...]` | Nested schema for keyword lists |
| `doc: "..."` | Documentation string |

---

## Summary of Part 2

### Key Takeaways

**Ecto for Validation:**
1. **Schemaless changesets** - Flexible validation without database
2. **Embedded schemas** - Convenient validation with structs
3. **apply_action** - Enable error display in Phoenix forms
4. Use even when not persisting data

**NimbleOptions for Options:**
1. **Declarative schemas** - Clear, readable option definitions
2. **Automatic validation** - Type checking, required fields, defaults
3. **Error messages** - Helpful validation errors
4. **Type flexibility** - OR types, custom parsers
5. **Cascading defaults** - Nested option defaults

### When to Use Each Tool

| Tool | Use Case |
|------|----------|
| Pattern matching | Local validation, function heads |
| Guards | Simple type/value constraints |
| Custom guards | Reusable domain validations |
| Schemaless changesets | Flexible data validation, API inputs |
| Embedded schemas | Struct validation, consistent shapes |
| NimbleOptions | Keyword list options, configuration |

---

## Complete Validation Strategy

### Layer 1: Function Boundaries (Pattern Matching & Guards)
```elixir
def process(%Account{} = account, opts) when is_list(opts)
```

### Layer 2: Complex Options (NimbleOptions)
```elixir
{:ok, validated} <- NimbleOptions.validate(opts, @schema)
```

### Layer 3: Data Structures (Ecto)
```elixir
{:ok, struct} <- Account.from_params(params)
```

### Combined Example

```elixir
defmodule MyApp.Accounts do
  @email_schema [
    template: [required: true, type: {:in, [:personal, :corporate]}],
    # ... more options
  ]
  
  def email(%Account{} = account, opts) when is_list(opts) do
    with {:ok, validated} <- NimbleOptions.validate(opts, @email_schema),
         {:ok, email_params} <- build_email_params(account, validated),
         :ok <- send_email(email_params) do
      {:ok, :sent}
    end
  end
  
  defp build_email_params(account, opts) do
    # Use validated options safely
  end
end
```

---

## Best Practices Summary

### Do's

✅ Validate at boundaries immediately  
✅ Use pattern matching for type safety  
✅ Create custom guards for domain logic  
✅ Use Ecto for complex data validation  
✅ Use NimbleOptions for keyword list options  
✅ Let processes crash on unexpected data  
✅ Return `{:ok, value}` or `{:error, reason}` from validation  
✅ Provide helpful error messages  
✅ Use schemas to document expected data  

### Don'ts

❌ Don't pass invalid data through your system  
❌ Don't handle every possible error case  
❌ Don't mix validation and business logic  
❌ Don't repeat validation in multiple places  
❌ Don't assume data is valid without checking  
❌ Don't create catch-all clauses for unknown data  
❌ Don't ignore validation errors  

---

## Benefits of This Approach

1. **Early failure** - Catch problems at boundaries
2. **Clear contracts** - Function signatures communicate expectations
3. **Better errors** - Helpful validation messages
4. **Self-documenting** - Schemas and patterns document expected data
5. **Reduced bugs** - Invalid data never enters system
6. **Easier debugging** - Know exactly where validation happens
7. **Maintainable** - Centralized validation logic
8. **Resilient** - Let it crash philosophy with OTP

---

## Additional Resources

- [Elixir Library Guidelines - Avoid Working with Invalid Data](https://hexdocs.pm/elixir/library-guidelines.html#avoid-working-with-invalid-data)
- [Ecto Changeset Documentation](https://hexdocs.pm/ecto/Ecto.Changeset.html)
- [Ecto Schemaless Changesets](https://hexdocs.pm/ecto/Ecto.Changeset.html#module-schemaless-changesets)
- [Ecto Data Mapping and Validation Guide](https://hexdocs.pm/ecto/data-mapping-and-validation.html)
- [NimbleOptions Documentation](https://hexdocs.pm/nimble_options/NimbleOptions.html)
- [Phoenix Contexts](https://hexdocs.pm/phoenix/contexts.html)
- [Phoenix HTML Forms](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html)

---

## Sources

- **Part 1**: [Validate Data in a Phoenix Application for Elixir](https://blog.appsignal.com/2023/10/10/validate-data-in-a-phoenix-application-for-elixir.html)
- **Part 2**: [Validating Data in Elixir: Using Ecto and NimbleOptions](https://blog.appsignal.com/2023/11/07/validating-data-in-elixir-using-ecto-and-nimbleoptions.html)

---

*This comprehensive guide provides a complete toolkit for validating data in Elixir applications, from basic pattern matching to advanced library usage, ensuring robust and maintainable code that rejects invalid data at every boundary.*
