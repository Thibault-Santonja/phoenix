# Test Data Generation in Elixir: A Three-Part Series

A comprehensive guide to test factories, fixtures, and data generation strategies for Elixir applications.

---

## Table of Contents

1. [Part 1: An Introduction to Test Factories and Fixtures](#part-1-an-introduction-to-test-factories-and-fixtures)
2. [Part 2: Generating Data Functions in Your Elixir App](#part-2-generating-data-functions-in-your-elixir-app)
3. [Part 3: Test Data Libraries for Elixir](#part-3-test-data-libraries-for-elixir)

---

## Part 1: An Introduction to Test Factories and Fixtures

**Source:** [AppSignal Blog - February 28, 2023](https://blog.appsignal.com/2023/02/28/an-introduction-to-test-factories-and-fixtures-for-elixir.html)

### What are Test Factories in Elixir?

Test factories are functions for generating data, commonly used in the `:test` environment. They're inspired by the factory method pattern, which allows a caller to create objects without knowing the specific module or class of the data that will be created.

Popular libraries like ExMachina enable developers to create complex data structures with minimal input:

```elixir
iex> user = ExMachina.insert(:user)
%User{
  id: "usr_xlkt"
  name: "Abilidebob"
  accounts: %Account{
    id: "acc_xktt"
    # ...
  }
  # ...
}
```

### Why Use Test Factories?

Test factories offer several benefits for long-term test suite maintainability:

- **Learnability** - Factories document what data structures can look like in production
- **Reusability** - Data examples can be reused across many different tests
- **Productivity** - Developers can invoke complex data examples by typing a few characters
- **Changeability** - Tests relying on central factories always have up-to-date examples

### Test Fixtures in Elixir

A fixture is data prepared before running a test. Factories generate test data on demand, while fixtures complement this by preparing the testing environment. There are two main types:

#### Inline Test Fixtures

The simplest approach involves directly inserting data within tests:

```elixir
test "creates an author profile" do
  user = MyApp.Repo.insert!(%User{id: "usr_123", name: "Abilidebob"})
  # rest of the test code
end
```

#### Implicit Test Fixtures

Using `ExUnit.CaseTemplate`, you can create fixtures shared across multiple tests:

```elixir
# test/support/data_case.ex
defmodule MyApp.DataCase do
  use ExUnit.CaseTemplate
  
  setup _context do
    user = %User{id: "usr_123", name: "Abilidebob"}
    %{user: MyApp.Repo.insert!(user)}
  end
end
```

Tests can then access this data through the test context:

```elixir
defmodule MyApp.MyTest do
  use MyApp.DataCase
  
  test "hello world", %{user: user} do
    # use the user here
  end
end
```

### The Problem: Bypassing Application Rules

The biggest issue with test factories is that they bypass your application's rules. Consider this example:

```elixir
# Production code
def create_author_profile(user) do
  author_profile = build_author_profile(user)
  user = Ecto.Changeset.change(user, %{is_author: true})
  
  Multi.new()
  |> Multi.update(:user, user)
  |> Multi.insert(:author_profile, author_profile)
  |> Repo.transaction()
end

# Factory code - duplicating business logic!
def author_factory do
  %Author{
    name: "Mr. DeBob",
    user: build(:user, is_author: true)  # Rule duplication!
  }
end
```

This duplication can lead to:

- Extra maintenance overhead
- Misleading developers with invalid data
- Unnecessarily defensive code

---

## Part 2: Generating Data Functions in Your Elixir App

**Source:** [AppSignal Blog - March 21, 2023](https://blog.appsignal.com/2023/03/21/generating-data-functions-in-your-elixir-app.html)

### Creating Data With Your App's Public APIs

The solution to factories bypassing application rules is to use your application code to generate test data. This ensures generated data stays consistent with your application's rules.

### Understanding the Test Pyramid

Before implementing data generation, consider your testing strategy. Different layers require different approaches:

- **Interface/Integration Layer** - Slowest, tests entire system working together
- **Context/Service Layer** - Tests business logic modules
- **Unit Layer** - Fastest, tests individual functions

Your test pyramid strategy determines what type of data generation functions you'll need.

### Creating Helpers for Context-Level Tests

First, configure Mix to compile test support files:

```elixir
# mix.exs
elixirc_paths: (
  case Mix.env() do
    :test -> ["lib", "test/support"]
    _ -> ["lib"]
  end
)
```

Then create helper functions that wrap your application's core API:

```elixir
# test/support/helpers.ex
defmodule MyApp.Helpers do
  def create_user(opts \\ []) do
    username = Keyword.get(opts, :username, "test_user")
    password = Keyword.get(opts, :password, "p4ssw0rd")
    {:ok, user} = MyApp.Accounts.signup_user(username, password)
  end
  
  def create_author(opts \\ []) do
    user = Keyword.get_lazy(opts, :user, &create_user/0)
    {:ok, author} = MyApp.Profiles.create_author_profile(user)
  end
end
```

Usage in tests:

```elixir
# test/news/news_test.exs
alias MyApp.Helpers

test "creates new post with given contents" do
  author = Helpers.create_author()
  assert {:ok, post} = News.create_post("My first post!", author)
end
```

### Data Examples in Struct Modules

For in-memory tests or external API data, create example functions directly in your data definition modules:

```elixir
# github/repo.ex
defmodule GitHub.Repo do
  defstruct [
    :id, :name, :full_name, :description,
    :owner_id, :owner_url, :private, :html_url, :url
  ]
  
  def example(attributes \\ []) do
    struct!(
      %GitHub.Repo{
        id: 1296269,
        name: "Hello-World",
        full_name: "octocat/Hello-World",
        description: "This your first repo!",
        owner_id: 1,
        owner_url: "https://api.github.com/users/octocat",
        private: false,
        html_url: "https://github.com/octocat/Hello-World",
        url: "https://api.github.com/repos/octocat/Hello-World"
      },
      attributes
    )
  end
end
```

This approach provides:

- **Executable documentation** - Shows real data examples
- **Easy customization** - Override specific attributes for tests
- **No extra files** - Examples live with the data definition

Usage:

```elixir
test "renders anchor tag to the repository" do
  repo = GitHub.Repo.example(html_url: "http://test.com")
  assert hyperlink_tag(repo) =~ "<a href=\"http://test.com\""
end
```

---

## Part 3: Test Data Libraries for Elixir

**Source:** [AppSignal Blog - April 25, 2023](https://blog.appsignal.com/2023/04/25/test-data-libraries-for-elixir.html)

### Why Use Test Data Libraries?

While Elixir's built-in features are sufficient for simple helpers, existing libraries provide convenience and battle-tested features without requiring you to build everything from scratch.

### ExMachina

The most popular factory library in the Elixir ecosystem, created by Thoughtbot.

**Key Features:**

- Atom-based factory invocation
- Powerful `sequence` function for unique values
- Multiple build strategies (`build`, `insert`, `build_list`, etc.)
- Extensible with custom strategies

**Example:**

```elixir
defmodule MyApp.Factory do
  use ExMachina
  
  def github_repo_factory do
    repo_name = sequence(:github_repo_name, &"repo-#{&1}")
    
    %GitHub.Repo{
      id: 1296269,
      name: repo_name,
      full_name: "octocat/#{repo_name}",
      description: "This your first repo!",
      owner_id: 1,
      owner_url: "https://api.github.com/users/octocat",
      private: false,
      html_url: "https://github.com/octocat/#{repo_name}",
      url: "https://api.github.com/repos/octocat/#{repo_name}"
    }
  end
end

# Usage
MyApp.Factory.build_list(3, :github_repo)
```

**Pros:**
- Well-established and actively maintained
- Widely used in the community
- Rich feature set

**Cons:**
- Can be harder to navigate factory definitions with atom-based dispatch
- Large factory modules may need to be broken down

### ExZample

A flexible factory library designed to work with example functions defined in struct modules.

**Key Features:**

- Works with or without explicitly defined examples
- Supports both direct struct calls and atom-based factories
- More flexible organization options

**Example with struct module:**

```elixir
# github/repo.ex
def example do
  repo_name = sequence(:github_repo_name)
  
  %GitHub.Repo{
    id: 1296269,
    name: repo_name,
    full_name: "octocat/#{repo_name}",
    # ...
  }
end

# Usage
ExZample.build_list(3, GitHub.Repo)
```

**Example with DSL:**

```elixir
defmodule MyApp.Factory do
  use ExZample.DSL
  
  factory :github_repo do
    example do
      repo_name = sequence(:github_repo_name)
      %GitHub.Repo{
        name: repo_name,
        # ...
      }
    end
  end
  
  def_sequence :github_repo_name, return: &"repo-#{&1}"
end

# Usage
ExZample.build_list(3, :github_repo)
```

**Pros:**
- Flexible - use only the features you need
- Examples can live in struct modules
- Supports both direct and atom-based invocation

**Cons:**
- Less mature than ExMachina
- Smaller community

### Faker

Generates realistic-looking fake data across many domains.

**Example:**

```elixir
Faker.start()

Faker.Internet.slug()
#=> "sit_et"

Faker.Internet.slug()
#=> "deleniti-consequatur"
```

**Available Data Types:**
- IP addresses
- Emails
- URLs
- Physical addresses
- Names
- And much more (even Pokémon names!)

**Use Cases:**
- Enriching test data with realistic values
- Reducing test dependency on specific hardcoded values
- Creating diverse test scenarios

**Note:** Random generation may occasionally cause duplicate values, potentially leading to flaky tests in rare situations.

### StreamData

Generates infinite streams of random raw data, primarily designed for property-based testing.

**Example:**

```elixir
# Generate alphanumeric strings
Enum.take(StreamData.string(:alphanumeric), 3)
#=> ["AcT", "9Ac", "TxY"]

# Filter for specific criteria
StreamData.string(:alphanumeric)
|> Enum.filter(&(String.length(&1) >= 5 and String.length(&1) <= 10))
|> Enum.take(1)
#=> ["hygT78ch"]
```

**Use Cases:**
- Property-based testing
- Generating diverse test inputs
- Testing edge cases with random data

---

## Recommendations and Best Practices

### Suggested Approach

1. **Use your application's functions first** - Create wrappers around your core API with convenient defaults for testing
2. **Create example functions** - When your app doesn't control data accuracy, define `example` functions in struct modules
3. **Add randomness** - Use Faker or StreamData to enrich test data and reduce dependency on specific values
4. **Consider factory libraries** - If the above isn't sufficient, embrace ExMachina or ExZample for more convenience

### General Guidelines

- **Prefer inline fixtures** over implicit ones for better maintainability
- **Keep factories close to application rules** - Use your app's public API when possible
- **Document with examples** - Example functions serve as executable documentation
- **Be mindful of test speed** - Balance convenience with performance
- **Avoid over-sharing fixtures** - Can lead to test coupling and slower suites

### When to Use Each Approach

| Approach | Best For | Trade-offs |
|----------|----------|------------|
| **Helper functions with app API** | Context-level tests | Slower but validates business rules |
| **Example functions in structs** | Unit tests, external APIs | Fast but may not validate full rules |
| **ExMachina/ExZample** | Complex data needs | Convenient but adds abstraction |
| **Faker** | Realistic diverse data | Random, may cause rare flaky tests |
| **StreamData** | Property-based testing | Great for edge cases, less readable |

---

## Conclusion

Test data generation in Elixir offers multiple approaches, each with distinct trade-offs. The key is finding the right balance for your project between convenience, maintainability, and alignment with your application's business rules.

Start simple with your application's own functions, add example functions for documentation and speed, and only adopt factory libraries when the complexity justifies the abstraction. This lean approach helps you understand exactly what you need and keeps your test suite maintainable in the long run.

---

## Additional Resources

- [ExMachina Documentation](https://hex.pm/packages/ex_machina)
- [ExZample GitHub](https://github.com/ulissesalmeida/ex_zample)
- [Faker Documentation](https://github.com/elixirs/faker)
- [StreamData Documentation](https://hexdocs.pm/stream_data/StreamData.html)
- [Ecto Testing Guide](https://hexdocs.pm/ecto/test-factories.html)
- [Towards Maintainable Elixir: Testing by Saša Jurić](https://medium.com/very-big-things/towards-maintainable-elixir-testing-b32ac0604b99)

---

*This document synthesizes a three-part series published on the AppSignal Blog between February and April 2023.*
