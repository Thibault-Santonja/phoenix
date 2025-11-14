# Phoenix LiveView Assigns Guide - Complete Series Summary

A comprehensive two-part guide to understanding, using, and optimizing Phoenix LiveView assigns, including common pitfalls and their solutions.

---

## Part 1: A Guide to Phoenix LiveView Assigns

### Overview
Phoenix LiveView assigns are a core tool for storing, presenting, and updating data in full-stack applications. They enable client-side interactions while minimizing cross-stack complexity. This guide demystifies assigns by explaining what they are, how they work, and how to debug them effectively.

---

## Understanding LiveView Assigns

### What Are Assigns?

Assigns are variables that provide dynamic data to templates. Here's a basic example:

```elixir
defmodule MyAppWeb.StatsLive do
  use MyAppWeb, :live_view
  alias MyApp.{Accounts, Notes}

  def mount(params, session, socket) do
    {:ok, assign(socket, 
      note_count: Notes.get_note_count(),
      user_count: Accounts.get_user_count()
    )}
  end

  def render(assigns) do
    ~H"""
    Note count: <%= @note_count %>
    User count: <%= @user_count %>
    """
  end
end
```

Assigns serve multiple purposes in LiveView, building upon concepts from EEx templates, traditional Phoenix, and Phoenix Channels.

---

## Three Core Concepts of Assigns

### 1. Assigns Provide Dynamic Input

**Similar to**: React props, Vue props, Web Component attributes

Assigns act as placeholders for dynamic data passed from outside the component. This is most evident in function components:

**Phoenix LiveView:**
```elixir
defmodule MyAppWeb.MyComponents do
  def my_button(assigns = %{text: _, click: _}) do
    ~H"""
    <button class="some-class" phx-click={@click}>
      <%= @text %>
    </button>
    """
  end
end
```

**React equivalent:**
```javascript
function MyButton({ text, click }) {
  return (
    <button class="some-class" onClick={click}>
      {text}
    </button>
  );
}
```

**Usage:**
```elixir
<.my_button text="Click me!" click="some_event" />
```

For stateless function components, assigns behave exactly like props in any component library - simple input variables with no hidden complexity.

---

### 2. Assigns Manage State

**Similar to**: React state, Vue data/state

For live views and live components, assigns evolve from simple input into **long-lived state**. Components can update their assigns internally to manage their state over time.

**The LiveView Advantage: Server-Side State Management**

Unlike client-side frameworks, LiveView manages state on the server, leveraging Erlang processes for low latency at scale. This enables seamless integration of:

- Encrypted sessions
- CSRF-protected user input
- ACID-safe database transactions
- Secure API calls
- Background jobs
- PubSub systems

**Example - User Subscription Flow:**

```elixir
defmodule MyAppWeb.UserSubscriptionLive do
  use MyAppWeb, :live_view

  def handle_event("pick_subscription", params, socket) do
    # encrypted session
    %{assigns: %{current_user: user}} = socket
    
    # CSRF-protected user input
    %{"plan" => plan} = params
    
    # ACID-safe database
    subscription = Subscriptions.create_subscription(user, plan)
    
    # non-public, secure APIs
    Payments.charge_user(user, subscription)
    
    # server-only background jobs
    Mailing.send_subscription_created_email(user, subscription)
    
    {:noreply, assign(socket, subscription: subscription)}
  end
end
```

**Template rendering:**
```elixir
<%= unless @subscription do %>
  Pick your plan:
  <a href="#" phx-click="pick_subscription" phx-value-plan="basic">
    Basic ($4.99)
  </a>
  <a href="#" phx-click="pick_subscription" phx-value-plan="premium">
    Premium ($19.99)
  </a>
<% else %>
  You're currently subscribed to <%= format_plan(@subscription.plan) %> plan.
  <%= if @subscription.last_payment do %>
    You were last charged on 
    <%= DateTime.to_date(@subscription.last_payment.inserted_at) %>.
  <% end %>
<% end %>
```

This eliminates the need for:
- Complex API layers
- Client-side state managers
- Sagas or middleware
- Extensive browser-based testing

**Memory Considerations:**

Since state lives on the server, all connected users claim memory to hold their assigns during their entire session. Proper state management is crucial to keep memory usage under control.

---

### 3. Assigns Fuel Change Tracking

**Similar to**: React's useMemo, Angular's change detection, Svelte's reactivity

LiveView assigns provide automatic change tracking through HEEx (HTML+EEx), which splits templates into static and dynamic parts.

**Key Behavior:**
- Only dynamic parts that reference changed assigns are re-evaluated
- Static parts are sent once and reused
- Only actual changes take up bandwidth

**Example - Horoscope Component:**

```elixir
defmodule MyAppWeb.UserHoroscope do
  use MyAppWeb, :live_component

  def render(assigns) do
    ~H"""
    <div>
      <strong>
        Horoscope for {format_full_name(@first_name, @last_name)}
        (born on {format_date(@birthday)}):
      </strong>
      {generate_horoscope(@birthday)}
    </div>
    """
  end
end
```

**Automatic optimization:**
- `format_date(@birthday)` and `generate_horoscope(@birthday)` only run when `@birthday` changes
- `format_full_name(@first_name, @last_name)` only runs when either name changes
- No manual memoization needed!

**React equivalent with useMemo:**

```javascript
function UserHoroscope({ firstName, lastName, birthday }) {
  const fullName = useMemo(() => {
    return formatFullName(firstName, lastName);
  }, [firstName, lastName]);
  
  const formattedBirthday = useMemo(() => {
    return formatDate(birthday);
  }, [birthday]);
  
  const horoscope = useMemo(() => {
    return generateHoroscope(birthday);
  }, [birthday]);
  
  return (
    <div>
      <strong>
        Horoscope for {fullName} (born on {formattedBirthday}):
      </strong>
      {horoscope}
    </div>
  );
}
```

**Why the difference?**
- React optimizes DOM patching, assumes JS re-evaluation is cheap (client-side focus)
- LiveView optimizes server resources and bandwidth without sacrificing developer experience (server-side focus)

---

## Debugging LiveView Assigns

### Official Resources

Before debugging, consult:
- [Assigns and HEEx guide](https://hexdocs.pm/phoenix_live_view/assigns-eex.html) in LiveView docs
- [Phoenix.LiveView.Engine module docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.Engine.html) for template engine insights

### Technique 1: Caveman Debugging

**Concept:** Use timestamps to track when template sections re-render.

**Setup:** Generate a sample resource for testing:

```bash
mix phx.gen.live Notes Note notes name:string content:text
```

**Add timestamp inspection to `index.html.heex`:**

```elixir
<%= inspect({Time.utc_now(), :above_notes}) %>

<table>
  <!-- table header -->
  <tbody id="notes">
    <%= for note <- @notes do %>
      <tr id={"note-#{note.id}"}>
        <td><%= inspect(Time.utc_now()) %></td>
        <td><%= inspect({Time.utc_now(), note.name}) %></td>
        <td><%= inspect({Time.utc_now(), note.content}) %></td>
        <!-- actions cell -->
      </tr>
    <% end %>
  </tbody>
</table>
```

**Observations:**
- Creating/editing notes: `:above_notes` timestamp updates with all row timestamps
- Deleting notes: Only affected rows update

**Why?**
- `FormComponent` uses `push_redirect/2` after save → whole page reloads
- `Index` uses `assign/2,3` for deletion → only updates specific assign

**Performance fix:** Replace `push_redirect/2` with `push_patch/2` in `FormComponent`:

```elixir
defp apply_action(socket, :index, _params) do
  socket
  |> assign(:page_title, "Listing Notes")
  |> assign(:notes, list_notes())
  |> assign(:note, nil)
end
```

**Result:** Eliminates full page reloads!

---

### Technique 2: Socket Inspection

**Purpose:** See what LiveView pushes over the wire - payload size, structure, and timing.

**Steps:**
1. Open Chrome Developer Tools
2. Navigate to Network tab
3. Filter by WS (WebSocket) type
4. Select `websocket?_csrf_token=...`
5. Switch to Messages tab
6. Choose message to inspect

**Alternative:** Enable console logging in JavaScript:

```javascript
liveSocket.enableDebug()
```

**What to look for:**
- Which assigns are updating
- Payload size and structure
- Frequency of updates

**Use cases for optimization:**
- **Restructure assigns**: Break apart large or deeply nested assigns
- **Use live components**: Separate tracking contexts for different parts of the UI
- **Binary data to hooks**: Send some data to JavaScript hooks as binary via `Phoenix.Channel`

---

### Technique 3: Production Monitoring with AppSignal

For production applications with live users, use [AppSignal](https://appsignal.com/) to:
- Monitor application performance
- Track LiveView errors
- Identify bottlenecks in real-world usage

Installation is quick and provides immediate insights into LiveView behavior in production environments.

---

## Part 2: LiveView Assigns - Three Common Pitfalls and Their Solutions

### Overview
This part covers three common mistakes developers make with LiveView assigns and provides practical solutions to avoid performance issues and unexpected behavior.

---

## Pitfall 1: Evaluating All LiveView Assigns

### The Problem

As complexity grows, you may have helpers that need many assigns:

```elixir
<%= user_note(@user, @note, @theme, @locale) %>
```

It's tempting to simplify by passing all assigns:

```elixir
<%= user_note(assigns) %>
```

**Why this is bad:**
- Completely ruins change tracking
- Any assign change triggers an update
- Massive performance degradation

### The Solution

**Pass only required assigns explicitly:**

```elixir
<%= user_note(@user, @note, theme: @theme, locale: @locale) %>
```

If you have many assigns, collapse them into a keyword list to maintain clarity while preserving change tracking.

### Why This Happens

LiveView's `@socket` struct intentionally excludes other assigns to prevent this issue. However, you can still directly access `assigns`, which opens the door to this pitfall.

**Key takeaway:** Never pass the entire `assigns` map to helper functions.

---

## Pitfall 2: Re-rendering Entire Lists

### The Problem

Change tracking on nested data structures (like lists) is complex. LiveView tracks assigns that appear in `for` loops as a whole, not individually.

**Example from generated resource:**

```elixir
<table>
  <tbody id="notes">
    <%= for note <- @notes do %>
      <tr id={"note-#{note.id}"}>
        <td><%= inspect(Time.utc_now()) %></td>
        <td><%= note.name %></td>
        <td><%= note.content %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

**Behavior:**
- Creating a note → All rows re-render
- Editing a note → All rows re-render
- Deleting a note → All rows re-render

Every operation on `@notes` re-evaluates every table row and cell, regardless of which note was affected.

### The Solution: Stateful Live Components

Create a separate tracking context using live components:

**Step 1: Create a component for each note**

```elixir
defmodule MyAppWeb.NotesLive.Index.NoteRow do
  use MyAppWeb, :live_component

  def render(assigns) do
    ~H"""
    <tr id={"note-#{@note.id}"}>
      <td><%= inspect(Time.utc_now()) %></td>
      <td><%= inspect({Time.utc_now(), @note.name}) %></td>
      <td><%= inspect({Time.utc_now(), @note.content}) %></td>
      <!-- ACTIONS -->
    </tr>
    """
  end
end
```

**Step 2: Render it within the table**

```elixir
<table>
  <!-- TABLE HEADER -->
  <tbody id="notes">
    <%= for note <- @notes do %>
      <.live_component 
        module={__MODULE__.NoteRow} 
        id={"note-row-#{note.id}"}
        note={note} 
      />
    <% end %>
  </tbody>
</table>
```

**New behavior:**
- Creating a note → Only the new row renders
- Editing a note → Only changed cells in that row update
- Deleting a note → No other rows update

### Performance Notes

**Memory consideration:** Live components reside on the same process as the parent view, so they share immutable data. No significant memory overhead from copying assigns.

**Further reading:** [Optimising data-over-the-wire in Phoenix LiveView](https://thepugautomatic.com/2020/07/optimising-data-over-the-wire-in-phoenix-liveview/)

Note: This article may not reflect current behavior as LiveView evolves rapidly. Check the [Phoenix LiveView changelog](https://github.com/phoenixframework/phoenix_live_view/blob/master/CHANGELOG.md) for updates.

---

## Pitfall 3: Growing LiveView Assigns Infinitely

### The Problem

Since LiveView runs on the server, memory management is critical. You cannot allow lists to grow infinitely, such as when implementing pagination.

**Problematic implementation:**

```elixir
defmodule MyAppWeb.NotesLive do
  def render(assigns) do
    ~H"""
    <div id="notes">
      <%= for note <- @notes do %>
        <div id={"note-#{note.id}"}>
          <!-- note content -->
        </div>
      <% end %>
    </div>
    <button phx-click="load_more">Load more</button>
    """
  end

  def handle_event("load_more", _, socket) do
    next_page = socket.assigns.last_page + 1
    more_notes = Notes.list_notes(page: next_page)
    
    {:noreply, assign(socket, 
      notes: socket.assigns.notes ++ more_notes,
      last_page: next_page
    )}
  end
end
```

**Problems:**
- Memory usage grows linearly with the number of notes loaded
- Multiplied by the number of concurrent users
- Server memory can be exhausted quickly

### The Solution: Temporary Assigns with Append Updates

**Step 1: Mark assign as temporary in mount**

```elixir
def mount(params, session, socket) do
  # ... other setup
  {:ok, socket, temporary_assigns: [notes: []]}
end
```

**Step 2: Use `phx-update="append"` in template**

```elixir
def render(assigns) do
  ~H"""
  <div id="notes" phx-update="append">
    <%= for note <- @notes do %>
      <div id={"note-#{note.id}"}>
        <!-- note content -->
      </div>
    <% end %>
  </div>
  <button phx-click="load_more">Load more</button>
  """
end
```

**Step 3: Assign only new items in event handler**

```elixir
def handle_event("load_more", _, socket) do
  next_page = socket.assigns.last_page + 1
  more_notes = Notes.list_notes(page: next_page)
  
  {:noreply, assign(socket, 
    notes: more_notes,  # Only new notes, not concatenated!
    last_page: next_page
  )}
end
```

**How it works:**
- **Temporary assigns**: Reset to their default value after each render
- **`phx-update="append"`**: Tells the client to append new DOM elements instead of replacing them
- **Memory efficiency**: Server only holds the current page of notes, while client accumulates all loaded notes

**Result:** UI shows accumulated records, but server memory stays constant per user.

---

## Summary of Key Concepts

### Three Roles of Assigns

1. **Dynamic Input** (like props)
   - Pass data to components
   - Simple placeholders for external data
   - Stateless and straightforward

2. **State Management** (like React state)
   - Long-lived state in live views and components
   - Server-side state with Erlang process benefits
   - Seamless integration with databases, APIs, sessions, etc.

3. **Change Tracking** (like React useMemo)
   - Automatic optimization of re-renders
   - Only changed assigns trigger updates
   - No manual memoization needed

### Three Common Pitfalls

1. **Passing entire `assigns` map**
   - **Problem**: Breaks change tracking
   - **Solution**: Pass only required assigns explicitly

2. **Re-rendering entire lists**
   - **Problem**: All list items re-render on any change
   - **Solution**: Use stateful live components for separate tracking contexts

3. **Growing assigns infinitely**
   - **Problem**: Memory usage grows with list size × users
   - **Solution**: Use temporary assigns with `phx-update="append"`

### Debugging Techniques

1. **Caveman debugging**: Add timestamps to track re-renders
2. **Socket inspection**: Examine WebSocket payloads in browser DevTools
3. **Production monitoring**: Use AppSignal for real-world performance insights

---

## Best Practices

### Do's

✅ Pass assigns explicitly to helper functions  
✅ Use live components for list items that need independent tracking  
✅ Mark accumulating assigns as temporary  
✅ Use `phx-update="append"` for infinite scroll patterns  
✅ Debug with timestamps during development  
✅ Monitor WebSocket payloads to understand re-render behavior  
✅ Consult official docs first when troubleshooting  

### Don'ts

❌ Never pass the entire `assigns` map to helpers  
❌ Don't let lists grow infinitely in server memory  
❌ Don't forget that each user holds their own assigns in memory  
❌ Don't skip change tracking optimization for complex lists  
❌ Don't ignore payload size in production  

---

## Trade-offs and Considerations

LiveView assigns provide powerful features with minimal boilerplate, but they come with trade-offs:

**Advantages:**
- Automatic change tracking without explicit dependencies
- Server-side state management with security benefits
- Reduced client-side complexity
- No need for separate API layers
- Minimal JavaScript required

**Considerations:**
- Server memory usage scales with concurrent users
- Need to understand implicit change tracking behavior
- Requires careful list handling for performance
- Less mature ecosystem compared to established JS frameworks

---

## Additional Resources

- [Phoenix LiveView Docs - Assigns and HEEx](https://hexdocs.pm/phoenix_live_view/assigns-eex.html)
- [Phoenix.LiveView.Engine](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.Engine.html)
- [Phoenix LiveView Changelog](https://github.com/phoenixframework/phoenix_live_view/blob/master/CHANGELOG.md)
- [Optimising data-over-the-wire in Phoenix LiveView](https://thepugautomatic.com/2020/07/optimising-data-over-the-wire-in-phoenix-liveview/)
- [AppSignal for Phoenix](https://appsignal.com/)

---

## Sources

- **Part 1**: [A Guide to Phoenix LiveView Assigns](https://blog.appsignal.com/2022/06/14/a-guide-to-phoenix-liveview-assigns.html)
- **Part 2**: [LiveView Assigns: Three Common Pitfalls and Their Solutions](https://blog.appsignal.com/2022/06/28/liveview-assigns-three-common-pitfalls-and-their-solutions.html)

---

*This summary provides a complete overview of Phoenix LiveView assigns, from fundamental concepts to advanced optimization techniques, enabling developers to build performant LiveView applications while avoiding common pitfalls.*
