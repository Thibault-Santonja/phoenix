defmodule PortfolioWeb.PhotographyLive.Index do
  use PortfolioWeb, :live_view

  @impl true
  def mount(params, session, socket) do
    section = Map.get(params, "section", nil)
    language = Map.get(params, "hl", session["locale"])
    Gettext.put_locale(PortfolioWeb.Gettext, language)

    {
      :ok,
      socket
      |> assign(modal_section: section)
      |> assign(language: language)
    }
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("open_modal", %{"section" => section}, socket) do
    {
      :noreply,
      socket
      |> assign(:modal_section, section)
      |> push_patch(to: ~p"/?section=#{section}&hl=#{socket.assigns.language}")
    }
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {
      :noreply,
      socket
      |> assign(:modal_section, nil)
      |> push_patch(to: ~p"/?hl=#{socket.assigns.language}")
    }
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {
      :noreply,
      push_event(socket, "change_locale", %{"locale" => locale})
    }
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, gettext("Thibault San Photography"))
  end

  def format_section_title("amvcc"), do: gettext("AMVCC")
  def format_section_title("china"), do: gettext("China")
  def format_section_title("couples"), do: gettext("Couples")
  def format_section_title("events"), do: gettext("Events")
  def format_section_title("japan"), do: gettext("Japan")
  def format_section_title("landscape"), do: gettext("Landscape")
  def format_section_title("motherhood"), do: gettext("Motherhood")
  def format_section_title("music"), do: gettext("Concerts & Music")
  def format_section_title("reenactment"), do: gettext("Re-enactment")
  def format_section_title("street"), do: gettext("Street Photography")
  def format_section_title("taiwan"), do: gettext("Taiwan")
  def format_section_title("wedding"), do: gettext("Wedding")
  def format_section_title(_), do: gettext("Gallery")

  def section_image(nil), do: ""
  def section_image(""), do: ""
  def section_image(name), do: "/images/photography/#{name}.webp"

  defp render_modal_content(assigns) do
    ~H"""
    <div class={[
      "bg-black opacity-80",
      "h-full p-8 md:p-16 lg:p-32",
      "space-y-8 md:space-y-16",
      "flex flex-col"
    ]}>
      <header class="flex justify-between items-center">
        <h2 class="text-2xl font-bold uppercase">{format_section_title(@modal_section)}</h2>
        <button class={["text-white text-2xl font-bold", "close-modal"]} phx-click="close_modal">
          &times;
        </button>
      </header>

      <div class="space-y-4">
        {render_modal_content(assigns, @modal_section)}
      </div>

      <nav class="flex">
        <button
          :if={@modal_section}
          class={[
            "close-modal",
            "grow-0",
            "block mt-8 mx-auto",
            "group hover:scale-110 duration-300",
            "py-3 px-5"
          ]}
          phx-click="close_modal"
        >
          {gettext("Close")}
          <.icon
            name="hero-x-circle-solid"
            class={[
              "ml-2 h-5 w-5",
              "group-hover:rotate-[1.57rad] duration-500 ease-out"
            ]}
          />
        </button>

        <a
          :if={@modal_section}
          href={~p"/#{@modal_section}"}
          class={[
            "grow-0",
            "block mt-8 mx-auto",
            "group hover:scale-110 duration-300",
            "py-2 px-4",
            "border-amvcc-base-300 rounded-lg border-2"
          ]}
        >
          {gettext("Show more")}
          <.icon
            name="hero-arrow-right-circle-solid"
            class={[
              "ml-2 h-5 w-5",
              "group-hover:rotate-[6.283rad] duration-500 ease-out"
            ]}
          />
        </a>
      </nav>
    </div>
    """
  end

  defp render_modal_content(assigns, "amvcc") do
    ~H"""
    <p>
      {gettext(
        "AMVCC (Association pour la Mise en Valeur du Château de Coucy) brings together passionate volunteers who work year-round to preserve, animate, and share the cultural heritage of Coucy castle. As a photographer, secretary, and active member, I contribute both behind the scenes and on the ground — where commitment meets creativity."
      )}
    </p>

    <p>
      {gettext(
        "My photographic journey with AMVCC is deeply human : from capturing the energy of public events like the Seigneuriales with the joy of a family discovering medieval crafts, to documenting large-scale initiatives such as castle restoration workshops in collaboration with REMPART, or the silent focus before the major show : Coucy à la Merveille — a grand outdoor spectacle that combines medieval drama, music, and scenography on a fantastic and epic scale. Each image becomes a fragment of shared memory and lived heritage and reflects a unique facet of the association’s efforts to bring medieval history to life and promote Coucy's heritage."
      )}
    </p>

    <p>
      {gettext(
        "Beyond the events, my lens seeks the gestures of dedication — the early morning preparations, the camaraderie around a fire, the quiet pride in historical transmission. These fleeting moments, often invisible to the public, are the beating heart of the association. They embody a spirit of generosity, intergenerational exchange, and resilience."
      )}
    </p>

    <p>
      {gettext(
        "My visual work aims to support AMVCC’s mission by creating a lasting record of its cultural initiatives. These images are not just archives — they are storytelling tools that celebrate the dedication of volunteers, artisans, and performers, and help share the living heritage of Coucy with a wider audience."
      )}
    </p>
    """
  end

  defp render_modal_content(assigns, "landscape") do
    ~H"""
    <p>
      {gettext(
        "My landscape photography is deeply connected to my approach to street photography — both seek to capture the relationship between people and their environments. But in nature, the dialogue shifts. It becomes quieter, older, and more elemental."
      )}
    </p>

    <p>
      {gettext(
        "I feel a strong, personal bond with the natural world — a place of both wonder and worry. As I witness climate change, biodiversity loss, and the growing scars of human activity, my photography becomes a form of quiet testimony. A way to say: this existed, this was beautiful, this matters."
      )}
    </p>

    <p>
      {gettext(
        "We often think of humanity as separate from nature, but we are part of it. I try to explore this tension — how we inhabit the land, how we shape it, and how, in return, it shapes us. Even in the most remote places, there are traces of our passage — paths, fences, forgotten ruins. My photography seeks to make these echoes visible."
      )}
    </p>

    <p>
      {gettext(
        "At the same time, I’m drawn to the strength and majesty of the earth itself — mountains that command silence, forests that pulse with life, skies that stretch far beyond us. These landscapes are not just scenery; they are alive, ancient, and essential. They remind us of scale, of time, of fragility and force."
      )}
    </p>

    <p>
      {gettext(
        "Through composition and light, I try to reveal the quiet power of nature — and our place within it. Not as rulers, not as outsiders, but as part of a larger story. My landscape work is about presence, memory, and respect. A way to reconnect with the world we too often overlook."
      )}
    </p>
    """
  end

  defp render_modal_content(assigns, "music") do
    ~H"""
    <p>
      {gettext(
        "Music has always been at the heart of my life. I began playing guitar as a child, and this early connection to sound and rhythm continues to shape how I perceive the world — and how I capture it through photography."
      )}
    </p>

    <p>
      {gettext(
        "As a concert photographer, I seek to convey the energy, emotion, and atmosphere of live music. From international acts like Hans Zimmer’s band, to national stars like Zaho de Sagazan, Eddy de Pretto, and L’Impératrice, or more eclectic and vibrant acts like Charlotte Adigéry & Boris Pupul or A2H, each performance is a living story that I try to preserve through images."
      )}
    </p>

    <p>
      {gettext(
        "I have a particular love for small outdoor festivals — places where music meets nature, where the atmosphere is laid-back and genuine, and where human connection takes centre stage. These moments, charged with light, dust, sound and laughter, offer an ideal canvas for documentary and my artistic work."
      )}
    </p>

    <p>
      {gettext(
        "My photography is more than event coverage — it's a personal way to explore and share the emotional power of music. I aim to capture the invisible thread between artist and audience, the tension before the drop, the intimacy of a verse whispered under the stars."
      )}
    </p>

    <p>
      {gettext(
        "As a music photographer, I still have dreams to fulfill. I hope one day to photograph Joe Hisaishi, whose compositions have deeply moved me, and Metallica, a band I have followed with passion since my youth. These are more than musical icons to me — they represent moments of life, inspiration, and enduring emotion."
      )}
    </p>
    """
  end

  defp render_modal_content(assigns, "reenactment") do
    ~H"""
    <p>
      {gettext(
        "Historical reenactment is the art of bringing the past to life — through costume, gesture, objects, and immersive scenes, grounded in careful historical research. It’s a vivid and engaging way to explore medieval life."
      )}
    </p>

    <p>
      {gettext(
        "I document this world through photography. I focus on reenactment and medieval-inspired imagery, capturing authentic scenes with an artistic eye — bringing them to life through vivid images that evoke the fabric of a 14th-century garment, the tension of a militia drill, or the stillness of a camp at dawn."
      )}
    </p>

    <p>
      {gettext(
        "My main collaboration is with La Seigneurie de Coucy (my reenactment company), but I have also work with other inspiring reenactment groups such as Pont-Croix 1358, Gentes Comitis, Aeterna and more. These encounters enrich my photographic work, offering a tapestry of unique faces, gestures, and moments. Each project becomes a shared journey — where historical rigour meets artistic vision, and where the past finds new light through the lens."
      )}
    </p>

    <p>
      {gettext(
        "Through this lens, I seek to create more than documentation — I strive to craft visual narratives with real artistic value. My photography brings history to life in ways that resonate emotionally and aesthetically. These images can support reenactment groups, medieval festivals, or even cosplay communities looking for a cinematic, historically grounded aesthetic."
      )}
    </p>
    """
  end

  defp render_modal_content(assigns, "street") do
    ~H"""
    <p>
      {gettext(
        "As a street photographer, I’m drawn to the evolving life of cities — the interplay between architecture, infrastructure, and the quiet rhythm of human presence. My camera becomes a way to observe, feel, and preserve these fragile moments of everyday life."
      )}
    </p>

    <p>
      {gettext(
        "I often find beauty in the layered textures of urban history — an old house patched and repurposed over time, tangled cables tracing decades of adaptation, or a passerby moving through it all, unaware of the silent stories in the walls around them."
      )}
    </p>

    <p>
      {gettext(
        "There is a deep humanity in the way people inhabit cities. I aim to capture this — not just the dramatic or spectacular, but the subtle poetry of a glance, a posture, a window left open. These details reveal the soul of a place and the quiet resilience of life."
      )}
    </p>

    <p>
      {gettext(
        "A recurring theme in my work is solitude — not as loneliness, but as presence. I often photograph solitary figures integrated into wide scenes, at the border between street and landscape photography. It might be a person quietly immersed in their thoughts, a couple lost in the calm of nature, or someone standing still amid the blurry noise of a bustling city. These moments of solitude carry a certain poetry. Sometimes they evoke serenity, sometimes melancholy — but always a kind of truth."
      )}
    </p>

    <p>
      {gettext(
        "Street photography, for me, is a way to witness time, humanity, and space converging. Each image is a silent dialogue — between place and person, solitude and movement, memory and moment."
      )}
    </p>
    """
  end

  defp render_modal_content(assigns, _section) do
    ~H"""
    <p>No content available for this section yet.</p>
    """
  end
end
