defmodule PortfolioWeb.PhotographyLive.Index do
  import PortfolioWeb.Components.PhotographyList
  use PortfolioWeb, :live_view

  @impl true
  def mount(params, session, socket) do
    chapter = Map.get(params, "chapter", nil)
    language = Map.get(params, "hl", session["locale"])
    Gettext.put_locale(PortfolioWeb.Gettext, language)

    {
      :ok,
      socket
      |> assign(modal_chapter: chapter)
      |> assign(language: language)
    }
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("open_modal", %{"chapter" => chapter}, socket) do
    {
      :noreply,
      socket
      |> assign(:modal_chapter, chapter)
      |> push_patch(to: ~p"/?chapter=#{chapter}&hl=#{socket.assigns.language}")
    }
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {
      :noreply,
      socket
      |> assign(:modal_chapter, nil)
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

  def format_chapter_title("amvcc"), do: gettext("AMVCC")
  def format_chapter_title("china"), do: gettext("China")
  def format_chapter_title("couples"), do: gettext("Couples")
  def format_chapter_title("events"), do: gettext("Events")
  def format_chapter_title("japan"), do: gettext("Japan")
  def format_chapter_title("landscape"), do: gettext("Landscape")
  def format_chapter_title("motherhood"), do: gettext("Motherhood & Families")
  def format_chapter_title("music"), do: gettext("Concerts & Music")
  def format_chapter_title("reenactment"), do: gettext("Re-enactment")
  def format_chapter_title("street"), do: gettext("Street Photography")
  def format_chapter_title("taiwan"), do: gettext("Taiwan")
  def format_chapter_title("wedding"), do: gettext("Wedding")
  def format_chapter_title(_), do: gettext("Gallery")

  defp render_modal_content(assigns) do
    ~H"""
    <div class={[
      "bg-black opacity-80",
      "h-full p-8 md:p-16 lg:p-32",
      "space-y-8 md:space-y-16",
      "flex flex-col"
    ]}>
      <header class="flex justify-between items-center">
        <h2 class="text-2xl font-bold uppercase">{format_chapter_title(@modal_chapter)}</h2>
        <button class={["text-white text-2xl font-bold", "close-modal"]} phx-click="close_modal">
          &times;
        </button>
      </header>

      <div class="space-y-4">
        {render_modal_content(assigns, @modal_chapter)}
      </div>

      <nav class="flex">
        <button
          :if={@modal_chapter}
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
          :if={@modal_chapter}
          href={~p"/#{@modal_chapter}"}
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

  defp render_modal_content(assigns, "china") do
    ~H"""
    <p>
      {gettext(
        "China holds a deeply personal place in my life. I’ve lived there, studied there, loved there. Part of my family still resides in China, and every return is filled with emotion — echoes both old and new. This vast, multifaceted country continues to amaze me with the richness of its traditions, the strength of its contrasts, and the quiet beauty found in the gestures of daily life."
      )}
    </p>
    <p>
      {gettext(
        "Photographing in China, for me, is not about capturing exoticism or postcard scenes, but about entering—humbly—a world that feels both close and distant. I look for silences, laughter, habits, the invisible threads that weave everyday life. Morning markets, shared meals, slow walks through old neighborhoods. In alleyways and on sidewalks, I’m drawn to the quiet poetry I love in street photography — a fleeting solitude, an unexpected light, a passing glance. Each image is an attempt to preserve something honest, without noise or artifice."
      )}
    </p>
    <p>
      {gettext(
        "This is a deeply human form of photography — where you can feel the breath of a place, the presence of its people, the memory of a history. My gaze is that of someone who knows, and who is still learning — with respect, patience, and tenderness."
      )}
    </p>
    """
  end

  defp render_modal_content(assigns, "japan") do
    ~H"""
    <p>
      {gettext(
        "Like many in France, I grew up dreaming of Japan—immersed in manga, films, and the music of Joe Hisaishi, whom I hope to photograph one day. That fascination has never left me. As an adult, I wanted to go beyond the dream, to live there for several months and feel the soul and culture of the country from within."
      )}
    </p>
    <p>
      {gettext(
        "From isolated natural spots, unknown even to many locals, to the towering buildings of Tokyo and Osaka, Japan slowly reveals itself: in the light slipping between two doors, in the silence of a shrine at dusk, in the murmur of a street at night. Its culture holds a mystical gentleness, an elegance in everyday life, a grace that lingers long within you."
      )}
    </p>
    <p>
      {gettext(
        "I deeply love this country—its people, their hospitality, its complex history, and its serene resilience. I’m also profoundly inspired by its photographers, who capture fragility with overwhelming intensity. Photographing in Japan, for me, is about listening more than looking. It’s about letting the place speak and patiently tracing the silent beauty of presence."
      )}
    </p>
    """
  end

  defp render_modal_content(assigns, "taiwan") do
    ~H"""
    <p>
      {gettext(
        "Taiwan is a country I hold close to my heart. There’s a singular gentleness to life here — a subtle blend of Chinese heritage and Japanese influence, especially felt in Taipei, in the architecture, the habits, the quiet rhythm of the days. The country has preserved its traditions, its temples, and a kind of everyday spirituality. It is both ancient and modern, vibrant and serene."
      )}
    </p>
    <p>
      {gettext(
        "What I love in Taiwan are the streets — their calm energy. Beneath the arcades, people cook, knit, read, work. There’s steam, slow gestures, quiet conversations, laughter. The warm, humid climate wraps everything in a soft, diffuse light. Nature is spectacular: mountains, hot springs, rice fields, dense forests. And of course, the Oolong — this rich, fragrant tea, sipped under a tree or at a modest table, in a silence that soothes the soul."
      )}
    </p>
    <p>
      {gettext(
        "Photographing Taiwan feels like entering a parallel time. It’s a gentle, attentive observation of life unfolding — unpretentious, yet full of humanity. I find here all that I love in street photography: quiet presences, textured details, and a discreet poetry that lives between walls, faces, and landscapes. It’s a country I never finish discovering."
      )}
    </p>
    """
  end

  defp render_modal_content(assigns, "couples") do
    ~H"""
    <p>
      {gettext(
        "Photographing a couple means entering an intimate space — a space of connection, shared glances, and spontaneous gestures. It’s a work of trust and attentiveness, where the image becomes the extension of a lived moment. No stiff poses, no masks — only the authenticity of a relationship captured in its own light."
      )}
    </p>
    <p>
      {gettext(
        "I aim to create images that truly resemble the people in them. Each session is unique: a meaningful place, an improvised walk, natural light. The setting becomes a quiet accomplice — present, yet never taking center stage. My approach is documentary and sensitive, with a refined aesthetic but no artifice."
      )}
    </p>
    <p>
      {gettext(
        "I love capturing the silence between two laughs, the brush of a hand, the glance that says everything. These suspended moments speak far beyond a single photo: they tell of memory, of love, of presence. A couple is a story in motion — and my role is to preserve a faithful, simple, and precious trace of it."
      )}
    </p>
    <p>
      {gettext(
        "Couple photography, as I practice it, is rooted in real life — a walk through the woods, a shared coffee, a quiet moment in a familiar place. My approach is discreet, respectful, and deeply human. I try to capture tenderness, connection, the gestures of daily life — everything that makes a relationship unique. These are not frozen memories, but living fragments, sincere and shared."
      )}
    </p>
    """
  end

  defp render_modal_content(assigns, "motherhood") do
    ~H"""
    <p>
      {gettext(
        "Even before the first cries, there is already a story — that of a young couple, caught between wonder, joy, and quiet suspense. It unfolds in glances, in waiting, in the hands that care. Photographing this moment means capturing the ‘before’ — that blend of tenderness, momentum, and gentle intimacy."
      )}
    </p>
    <p>
      {gettext(
        "I don’t try to freeze time — I try to let it breathe. A soft light on a round belly, a tiny hand resting on a father’s beard, arms opening to hold. These raw and tender gestures are what move me — and what I strive to carry forward through my images."
      )}
    </p>
    <p>
      {gettext(
        "I go where life is — at home, in a garden, in the stillness of a slow morning or the whirlwind of a lively afternoon. There may be laughter, tears, surprises — that’s the beauty of these moments. My gaze is discreet, respectful, always seeking the simple truth of a world as it is — a beautiful mess, full of warmth and energy."
      )}
    </p>
    """
  end

  defp render_modal_content(assigns, "wedding") do
    ~H"""
    <p>
      {gettext(
        "A wedding is a whirlwind of faces, gestures, and shifting light. It’s a day that passes too quickly, where every moment deserves to be lived — and sometimes preserved. My approach is documentary, sensitive, and attentive: I don’t direct, I observe. I follow the natural rhythm of the day, the glances that connect, the laughter that bursts out, the hands that tighten when emotions overflow."
      )}
    </p>
    <p>
      {gettext(
        "I photograph the behind-the-scenes, the quiet before the big moments, the details that are often forgotten. A wrinkled dress, shoes kicked off, sunlight on a bare neck. I love that gentle tension between the intimate and the shared, between fragility and joy. My aim is not to create perfect images, but honest ones — true to you, your energy, and the bond that unites you."
      )}
    </p>
    <p>
      {gettext(
        "Every wedding is a unique story, and I slip into it as a quiet witness. I’m here to capture the truth of a moment, not to stage it. What moves me are the genuine sparks: a held-back tear, a child running under the tables, a grandfather smiling softly. All these living fragments weave together the memory of your day."
      )}
    </p>
    """
  end

  defp render_modal_content(assigns, _chapter) do
    ~H"""
    <p>No content available for this chapter yet.</p>
    """
  end
end
