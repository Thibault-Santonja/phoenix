# Phoenix 1.7 Modal Tutorial Series Summary

A comprehensive guide to creating, implementing, and editing modals with forms in Phoenix 1.7, using the generated CoreComponents and LiveView.

---

## Part 1: Create and Open a Modal in Phoenix 1.7

### Overview
This part introduces the Phoenix 1.7 generated core components and demonstrates how to create and open a modal component on demand.

### Key Concepts

#### Generated Components
Phoenix 1.7 includes built-in Tailwind components in `CoreComponents` module:
- Pre-styled components for rapid development
- Customizable to fit specific needs
- Include modals, buttons, forms, and inputs

#### Understanding Attributes and Slots
- **Attributes (`attr`)**: Define data passed to components, can be required or have default values
- **Slots**: Space for nested HTML content
  - `:inner_block`: Special unnamed slot for content between component tags
  - Named slots: Designated with specific names (e.g., `:subtitle`, `:actions`)

#### Modal Component Structure
The modal component requires:
- An `id` attribute for targeting
- Content in the `:inner_block` slot
- Uses the `show` attribute (boolean, defaults to false)

### Implementation Steps

1. **Bootstrap the project**
   ```bash
   mix archive.install hex phx_new
   mix phx.new petacular
   ```

2. **Add a modal to the page**
   ```elixir
   <PetacularWeb.CoreComponents.modal id="create_modal">
     <h2>Add a pet.</h2>
   </PetacularWeb.CoreComponents.modal>
   ```

3. **Create a button to trigger the modal**
   ```elixir
   <PetacularWeb.CoreComponents.button 
     phx-click={PetacularWeb.CoreComponents.show_modal("create_modal")}>
     Add New Pet +
   </PetacularWeb.CoreComponents.button>
   ```

### How Modal Show/Hide Works

#### The JS Module
Phoenix LiveView's `JS` module executes JavaScript functions without writing custom JS:
- `show_modal/2`: Shows the modal with smooth animations and focuses the first element
- `hide_modal/2`: Hides the modal with reverse animations

#### Modal Interaction
- Button's `phx-click` can accept a `JS` function chain
- The modal includes a built-in close button (X) that calls `hide_modal`
- No backend event needed for basic modal opening/closing

---

## Part 2: Add a Form to a Modal in Phoenix 1.7

### Overview
This part adds a functional form to the modal to create new records (pets) and save them to the database.

### Key Concepts

#### The `to_form` Function
Phoenix 1.7 introduces `Phoenix.Component.to_form/2` which generates a `Phoenix.HTML.Form` struct from a changeset.

**Benefits of `to_form`:**
- **Indirection**: Decouples forms from changesets, allowing flexibility in data sources
- **Better change tracking**: Only changed fields re-render, not the entire form
- **Simplified syntax**: No need for `:let` attribute or reaching into changesets

**Before Phoenix 1.7:**
```elixir
<.form :let={f} for={@changeset} phx-submit="...">
  <%= Phoenix.HTML.Form.text_input(f, :my_field, 
      value: Ecto.Changeset.fetch_field!(@changeset, :my_field)) %>
</.form>
```

**After Phoenix 1.7:**
```elixir
<.form for={@create_form} phx-submit="...">
  <input type="text" 
         name={@create_form[:my_field]} 
         value={@create_form[:my_field].value} />
</.form>
```

#### Simple Form Component
The `simple_form` component expects:
- A `:for` attribute with the form struct
- An `:inner_block` slot for form inputs
- An `:actions` named slot for submit buttons

### Implementation Steps

1. **Initialize the form in mount**
   ```elixir
   def mount(_params, _session, socket) do
     default_assigns = %{
       create_form: Phoenix.Component.to_form(
         Petacular.Pet.create_changeset(%{})
       )
     }
     {:ok, assign(socket, default_assigns)}
   end
   ```

2. **Build the form in the modal**
   ```elixir
   <PetacularWeb.CoreComponents.modal id="create_modal">
     <h2>Add a pet.</h2>
     <PetacularWeb.CoreComponents.simple_form 
       for={@create_form} 
       phx-submit="create_pet">
       
       <PetacularWeb.CoreComponents.input 
         field={@create_form[:name]} 
         label="Name" />
       
       <:actions>
         <PetacularWeb.CoreComponents.button>
           Save
         </PetacularWeb.CoreComponents.button>
       </:actions>
     </PetacularWeb.CoreComponents.simple_form>
   </PetacularWeb.CoreComponents.modal>
   ```

3. **Handle form submission**
   ```elixir
   def handle_event("create_pet", %{"pet" => params}, socket) do
     case Repo.insert(Petacular.Pet.create_changeset(params)) do
       {:error, message} ->
         {:noreply, socket |> put_flash(:error, inspect(message))}
       
       {:ok, _} ->
         new_assigns = %{
           pets: Repo.all(Petacular.Pet),
           create_form: Phoenix.Component.to_form(
             Petacular.Pet.create_changeset(%{})
           )
         }
         {:noreply, assign(socket, new_assigns)}
     end
   end
   ```

### Important Gotcha: Always Use Fresh Changesets
When submitting forms, always create a fresh changeset. Never reuse the changeset from assigns, as this can cause issues with error handling. Using `to_form` helps avoid this trap since the changeset isn't directly in assigns.

### Closing the Modal After Success

#### Using `push_event`
Phoenix LiveView's `push_event/3` emits JS events from the backend that can be caught on the frontend.

1. **Push event from backend**
   ```elixir
   socket
   |> assign(new_assigns)
   |> push_event("close_modal", %{to: "#close_modal_btn_create_modal"})
   ```

2. **Create a JavaScript hook** (in `app.js`)
   ```javascript
   const ModalCloser = {
     mounted() {
       this.handleEvent("close_modal", () => {
         this.el.dispatchEvent(new Event("click", { bubbles: true }));
       });
     },
   };
   
   let liveSocket = new LiveSocket("/live", Socket, {
     hooks: { ModalCloser: ModalCloser },
   });
   ```

3. **Attach hook to close button** (in `CoreComponents`)
   ```elixir
   <button 
     id={"close_modal_btn_" <> @id}
     phx-hook="ModalCloser"
     phx-click={JS.exec("data-cancel", to: "##{@id}")}
     type="button"
     class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
     aria-label={gettext("close")}>
     <.icon name="hero-x-mark-solid" class="h-5 w-5" />
   </button>
   ```

---

## Part 3: Edit a Form in a Modal

### Overview
This final part implements an edit modal that allows updating existing records, addressing the challenges of dynamic data and form state management.

### Key Challenge
Each item needs its own changeset, but rendering a modal per row is inefficient and doesn't scale. The solution is to build the correct changeset based on the clicked item.

### Implementation Strategy

#### Using JS.push for Dynamic Data
The `JS.push` function sends events to the backend with custom parameters, enabling dynamic changeset creation.

### Working with Icons

Phoenix 1.7 includes vendored Heroicons:
- Located in `assets/vendor/heroicons/optimized/20/solid/`
- Used with the `<.icon>` component
- Format: `<.icon name="hero-cpu-chip" />`

#### Creating a Storybook Route
To preview all available icons, create a development-only route:

```elixir
# router.ex
live("/storybook", PetacularWeb.Pages.StoryBookLive, :show)
```

**Important:** Add icons to Tailwind's safelist to prevent purging:
```javascript
// tailwind.config.js
safelist: [{ pattern: /hero\-.*/ }],
```

### Edit Modal Implementation

1. **Add edit button per row**
   ```elixir
   <%= for pet <- @pets do %>
     <div class="flex">
       <button phx-click={open_edit_modal(pet.id, pet.name)}>
         <PetacularWeb.CoreComponents.icon 
           name="hero-pencil-square-solid" 
           class="mr-2" />
       </button>
       <p>Name: <span class="font-semibold"><%= pet.name %></span></p>
     </div>
   <% end %>
   ```

2. **Create the edit modal**
   ```elixir
   <PetacularWeb.CoreComponents.modal id="edit_modal">
     <h2>Edit a pet.</h2>
     <PetacularWeb.CoreComponents.simple_form 
       for={@edit_form} 
       phx-submit="edit_pet">
       
       <PetacularWeb.CoreComponents.input 
         label="Name" 
         id="edit_name"
         field={@edit_form[:name]} 
         value={@edit_form[:name].value} />
       
       <:actions>
         <PetacularWeb.CoreComponents.button>
           Save
         </PetacularWeb.CoreComponents.button>
       </:actions>
     </PetacularWeb.CoreComponents.simple_form>
   </PetacularWeb.CoreComponents.modal>
   ```

3. **Initialize edit form in mount**
   ```elixir
   def mount(_params, _session, socket) do
     default_assigns = %{
       pets: Repo.all(Petacular.Pet),
       edit_form: Phoenix.Component.to_form(
         Petacular.Pet.create_changeset(%{})
       ),
       create_form: Phoenix.Component.to_form(
         Petacular.Pet.create_changeset(%{})
       )
     }
     {:ok, assign(socket, default_assigns)}
   end
   ```

4. **Implement the open_edit_modal function**
   ```elixir
   defp open_edit_modal(pet_id, pet_name) do
     %JS{}
     |> JS.push("open_edit_modal", value: %{pet_id: pet_id})
     |> JS.set_attribute({"value", pet_name}, to: "#edit_name")
     |> JS.set_attribute({"value", pet_id}, to: "#edit_pet_id_input")
     |> PetacularWeb.CoreComponents.show_modal("edit_modal")
   end
   ```

5. **Handle the open event**
   ```elixir
   def handle_event("open_edit_modal", %{"pet_id" => id}, socket) do
     pet = Enum.find(socket.assigns.pets, &(&1.id == id))
     new_assigns = %{
       edit_form: Phoenix.Component.to_form(
         Petacular.Pet.edit_changeset(%{}, pet)
       )
     }
     {:noreply, assign(socket, new_assigns)}
   end
   ```

### Critical Bug and Solution

#### The Problem
The modal's auto-focus feature conflicts with LiveView's principle that "the client is the source of truth for focused inputs":
1. Async message sent to backend (changeset update)
2. Modal opens with JS, focusing the first input
3. Server responds with new changeset data
4. LiveView won't update focused input values

Result: The input appears empty despite the changeset having the correct value.

#### Possible Solutions Evaluated

1. **Remove auto-focus** ❌ - Breaks accessibility
2. **Focus non-input element first** ❌ - Violates accessibility guidelines
3. **Make modal opening synchronous** ❌ - Requires extra round trip, slower UX
4. **Set field value with JS** ✅ - Fast, correct value, maintains auto-focus

#### The Solution
Use `JS.set_attribute` to set the field value directly with JavaScript:

```elixir
defp open_edit_modal(pet_id, pet_name) do
  %JS{}
  |> JS.push("open_edit_modal", value: %{pet_id: pet_id})
  |> JS.set_attribute({"value", pet_name}, to: "#edit_name")
  |> PetacularWeb.CoreComponents.show_modal("edit_modal")
end
```

### Tracking the Pet ID

Use a hidden input to submit the pet ID with the form:

```elixir
<%= Phoenix.HTML.Form.hidden_input(f, :id, id: "edit_pet_id_input") %>
```

Set its value when opening the modal:
```elixir
|> JS.set_attribute({"value", pet_id}, to: "#edit_pet_id_input")
```

### Final Edit Handler

```elixir
def handle_event("edit_pet", %{"pet" => %{"id" => id} = params}, socket) do
  pet = Enum.find(socket.assigns.pets, &(&1.id == String.to_integer(id)))
  
  case Repo.update(Petacular.Pet.edit_changeset(params, pet)) do
    {:error, message} ->
      {:noreply, socket |> put_flash(:error, inspect(message))}
    
    {:ok, _} ->
      new_assigns = %{
        pets: Repo.all(Petacular.Pet),
        edit_form: Phoenix.Component.to_form(
          Petacular.Pet.create_changeset(%{})
        )
      }
      socket = socket
        |> assign(new_assigns)
        |> push_event("close_modal", %{to: "#close_modal_btn_edit_modal"})
      
      {:noreply, socket}
  end
end
```

---

## Summary of Key Takeaways

### Phoenix 1.7 Core Components
- Generated components provide a solid foundation with Tailwind styling
- Easily customizable for specific application needs
- Include modals, forms, inputs, buttons, and icons

### The JS Module
- Enables JavaScript execution without custom JS code
- Supports function chaining for complex interactions
- Methods: `show`, `hide`, `push`, `set_attribute`, `focus_first`, etc.

### Form Handling Best Practices
- Always use `to_form` for better performance and cleaner code
- Create fresh changesets on every submission
- Never reuse changesets from assigns

### Modal Patterns
- Use `phx-click` with `show_modal` for opening
- Use `push_event` with hooks for programmatic closing
- Handle dynamic data with `JS.push` and backend events

### Common Pitfalls
- Tailwind purging dynamically referenced classes (use safelist)
- Auto-focus conflicts with LiveView's client-as-source-of-truth principle
- Reusing changesets across form submissions

### JavaScript Integration
- Minimal custom JS needed with LiveView
- Hooks provide clean integration points
- `push_event` enables backend-to-frontend communication

---

## Sources

- **Part 1**: [Create and Open a Modal in Phoenix 1.7](https://blog.appsignal.com/2023/06/20/create-and-open-a-modal-in-phoenix-1-7.html)
- **Part 2**: [Add a Form to a Modal in Phoenix 1.7](https://blog.appsignal.com/2023/08/01/add-a-form-to-a-modal-in-phoenix-1-7.html)
- **Part 3**: [Phoenix 1.7 for Elixir: Edit a Form in a Modal](https://blog.appsignal.com/2023/09/12/phoenix-1-7-for-elixir-edit-a-form-in-a-modal.html)

**Companion Repository**: [https://github.com/Adzz/petacular](https://github.com/Adzz/petacular)

---

*This summary covers the complete three-part series on implementing modals with forms in Phoenix 1.7, from basic modal creation through creating and editing records with proper form handling and state management.*
