defmodule PortfolioWeb.PhotographyLive.Timeline do
  @moduledoc """
  LiveView module rendering the photography timeline page.

  This component displays a chronological archive of photo albums grouped by year,
  with a smooth scroll-based interaction that highlights the current year in the
  background as users navigate through the content.

  Key features:
  - Dynamic display of albums by year.
  - Year highlight transitions on scroll using IntersectionObserver.
  - Translated album titles and descriptions using Gettext.
  - Responsive design with Tailwind CSS grid layout.
  - Enhanced visual experience with custom CSS and animations.
  - Lightweight JavaScript hook (`YearTrigger`) for animated year switching.
  """

  use PortfolioWeb, :live_view

  @data %{
    2023 => [
      %{
        type: "couples",
        date: "2023-12-09",
        title: "Alexandre & Anne",
        description:
          gettext("A soft winter light, a strong bond, and shared laughter among ancient stones."),
        photography: "/images/photography/gallery/2023-12-09_couples.webp",
        url: nil,
        reference_link: nil
      },
      %{
        type: "amvcc",
        date: "2023-12-17",
        title: gettext("Sewing workshop"),
        description:
          gettext(
            "A moment suspended in the workshop: ancient gestures, taut threads, concentrated silence, interspersed with bursts of laughter"
          ),
        photography: "/images/photography/gallery/2023-12-17_amvcc.webp",
        url: nil,
        reference_link:
          "https://www.amvcc.com/spectacles-animations/la-troupe-medievale-la-seigneurie-de-coucy/"
      },
      %{
        type: "wedding",
        date: "2023-12-23",
        title: "Amel & Flo",
        description:
          gettext(
            "A warm winter wedding, an intimate celebration where every glance felt like a promise."
          ),
        photography: "/images/photography/gallery/2023-12-23_wedding.webp",
        url: nil,
        reference_link: nil
      }
    ],
    2024 => [
      %{
        type: "couples",
        date: "2024-01-27",
        title: "Alexandre & Anne",
        description:
          gettext(
            "A tender kiss under Geneva’s night lights, glowing softly beneath an artful play of illumination."
          ),
        photography: "/images/photography/gallery/2024-01-27_couples.webp",
        url: nil,
        reference_link: nil
      },
      # %{
      #   type: "wedding",
      #   date: "2024-03-23",
      #   title: "Claire & Damien",
      #   description:
      #     gettext(
      #       "A wedding filled with grace, joy, and depth. Glances met and smiled; the gentle spring breeze only made hearts warmer."
      #     ),
      #   photography: "/images/photography/gallery/2024-03-23_wedding.webp",
      #   url: nil
      # },
      %{
        type: "music",
        date: "2024-03-24",
        title: "Orchestre de Gisors",
        description:
          gettext(
            "Beneath ancient vaults, the orchestra brought the walls to life. Strings, woodwinds, and brass in conversation — emotion hanging in the air."
          ),
        photography: "/images/photography/gallery/2024-03-24_music.webp",
        url: nil,
        reference_link: nil
      },
      %{
        type: "music",
        date: "2024-03-26",
        title: "Des caravelles & des batailles",
        description:
          gettext(
            "A vibrant university troupe: imaginary battles, sung epics, and bursts of humor. A breath of fresh theatrical air."
          ),
        photography: "/images/photography/gallery/2024-03-26_music.webp",
        url: nil,
        reference_link: nil
      },
      %{
        type: "amvcc",
        date: "2024-04-26",
        title: "Chantiers AMVCC x REMPART à Coucy le Château",
        description:
          gettext(
            "Stone restoration by calloused hands, shared effort under Coucy’s skies. Evenings filled with laughter and the scent of warm meals — unforgettable days of work and kinship."
          ),
        photography: "/images/photography/gallery/2024-04-26_amvcc.webp",
        url: nil,
        reference_link: "https://www.amvcc.com/chantiers-benevoles/"
      },
      %{
        type: "reenactment",
        date: "2024-05-04",
        title: "Seigneuriales de Coucy 2024",
        description:
          gettext(
            "The Seigneuriales of Coucy (AMVCC) bring the medieval city to life for a weekend. I joined as a reenactor with the Seigneurie de Coucy. Dancing, feasting, lively exchanges between groups from all over France, and quiet moments by the fire — a timeless escape."
          ),
        photography: "/images/photography/gallery/2024-05-04_reenactment.webp",
        url: nil,
        reference_link: "https://www.amvcc.com/spectacles-animations/les-seigneuriales-de-coucy/"
      },
      %{
        type: "wedding",
        date: "2024-05-18",
        title: "Anaïs & Jean-Michel",
        description:
          gettext(
            "A heartfelt wedding in Coucy, from the intimate charm of the local church to a joyful priest and a family filled with warmth. Anaïs and Jean-Michel’s love, their radiant son, and the tender presence of loved ones made for a day full of life and grace — and perfect moments to photograph."
          ),
        photography: "/images/photography/gallery/2024-05-18_wedding.webp",
        url: nil,
        reference_link: nil
      },
      %{
        type: "music",
        date: "2024-06-07",
        title: "Minuit avant la nuit 2024",
        description:
          gettext(
            "The Minuit avant la Nuit festival in Amiens, set in the lush Saint-Pierre park, offered a warm and laid-back atmosphere. 2024’s edition was a true joy — especially photographing L’Impératrice, a French pop band I truly love."
          ),
        photography: "/images/photography/music.webp",
        url: nil,
        reference_link: "https://minuitavantlanuit.fr/"
      },
      %{
        type: "amvcc",
        date: "2024-07",
        title: "Coucy à la Merveille 2024",
        description:
          gettext(
            "New edition of Coucy à la Merveille — a grand historical show blending theatre, light, and emotion to bring Coucy’s history to life. This year leaned less into fantasy, but remained breathtaking thanks to a passionate team: from performers to costume designers, technicians to writers."
          ),
        photography: "/images/photography/gallery/2024-07-26_amvcc.webp",
        url: nil,
        reference_link: "https://www.amvcc.com/spectacles-animations/coucy-a-la-merveille/"
      },
      %{
        type: "reenactment",
        date: "2024-08-02",
        title: "Musée de la bataille de Crecy en Ponthieu",
        description:
          gettext(
            "At the museum of the Battle of Crécy (1346), run by passionate enthusiasts, hosted our reenactment of life and combat in that era — especially honoring the Sir of Coucy who fell in the battle. A vibrant, human, and meaningful day of history brought to life."
          ),
        photography: "/images/photography/gallery/2024-08-02_reenactment.webp",
        url: nil,
        reference_link: "https://www.crecylabataille.com/"
      },
      %{
        type: "reenactment",
        date: "2024-08-10",
        title: "Pont-Croix 1358",
        description:
          gettext(
            "Pont-Croix 1358 is a medieval reenactment project in Brittany, recreating a 14th-century village. Over two weekends, we contributed to building the site and bringing it to life. One of the weekends brought together many reenactment groups, sharing knowledge and passion in a vibrant atmosphere. During the Perseid meteor shower — unusually enhanced by a solar storm — the night sky glowed with purple hues. A magical blend of history and the stars."
          ),
        photography: "/images/photography/gallery/2024-08-10_reenactment.webp",
        url: nil,
        reference_link: "https://pont-croix1358.bzh/"
      },
      %{
        type: "reenactment",
        date: "2024-09-08",
        title: "Médiévales de Laon 2024",
        description:
          gettext(
            "The Médiévales de Laon are a lively event celebrating the medieval heritage of Laon, in northern France, with musicians, craftsmen, living camps, and shows. We were there with the Seigneurie de Coucy, portraying 14th-century life. Despite moments of heavy rain, the atmosphere remained joyful, warm, and uplifted by the smiles of the public."
          ),
        photography: "/images/photography/gallery/2024-09-08_reenactment.webp",
        url: nil,
        reference_link: nil
      },
      %{
        type: "wedding",
        date: "2024-09-18",
        title: "Shang XiaoYang & Lu WenTian",
        description:
          gettext(
            "A wedding in China, filled with elegance, grace, and affection. Chinese traditions intertwined with tender family glances, gentle gestures, and shy yet heartfelt smiles. XiaoYang and WenTian lit up the day with their quiet warmth and deep bond. I wholeheartedly wish them joy and love in their life together!"
          ),
        photography: "/images/photography/wedding.webp",
        url: nil,
        reference_link: nil
      }
    ],
    2025 => [
      %{
        type: "reenactment",
        date: "2025-04-26",
        title: "Seigneuriales 2025",
        description:
          gettext(
            "The Seigneuriales of Coucy (AMVCC) are held each year at the fortress of Coucy-le-Château, organized by the AMVCC. They gather reenactors and visitors around shows, crafts, and medieval life. The 2025 edition was blessed with sunny weather and record attendance. Birds of prey added a spectacular aerial touch to this immersive historical weekend."
          ),
        photography: "/images/photography/reenactment.webp",
        url: nil,
        reference_link: "https://www.amvcc.com/spectacles-animations/les-seigneuriales-de-coucy/"
      },
      %{
        type: "music",
        date: "2025-06-15",
        title: "Minuit avant la Nuit 2025",
        description:
          gettext(
            "Beneath the old trees of Saint-Pierre park, time slowed down. Soft light drifted over faces, carried by the voices of Miki, Philippe Katerine, Kompromat, and Kavinsky. For this 2025 edition, I rediscovered what makes Minuit avant la Nuit so special — that rare blend of warmth, collective energy, and music that transcends genres to reach something deeper.Photographing this moment meant chasing the fleeting — the smiles in the crowd, an artist’s silhouette in the stage lights, the birth of a memory still taking shape."
          ),
        photography: "/images/photography/gallery/2025-06-14_Minuit_avant_la_Nuit.webp",
        url: "/gallery/20250614_MALN",
        reference_link: "https://minuitavantlanuit.fr/"
      },
      %{
        type: "reenactment",
        date: "2025-06-21",
        title: gettext("Bringing the Donjon de Bours to life"),
        description:
          gettext(
            "There are places that seem to carry with them the breath of time. The Donjon de Bours is one such place. During a weekend of historical re-enactment, the stones took on a new voice. The costumes, the ancient gestures, the smells of fire, cooking and wool recreated a bygone world, both familiar and distant. Photographing this moment is more than simply bearing witness: it's accompanying a place as it comes to life, capturing the echo of the past in the eyes of today. Each image is a fragile memory, a door ajar on what we once were, on what, perhaps, still resonates within us."
          ),
        photography:
          "/images/photography/gallery/20250621_Bours/2025-06-21_Donjon_de_Bours_4753_250621115330.webp",
        url: "/gallery/20250621_Bours",
        reference_link:
          "https://www.arraspaysdartois.com/le-donjon-de-bours-joyau-architectural-medieval-en-hauts-de-france/"
      }
    ]
  }

  @impl true
  def mount(_, session, socket) do
    Gettext.put_locale(PortfolioWeb.Gettext, session["locale"])

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {:noreply, push_event(socket, "change_locale", %{"locale" => locale})}
  end

  defp apply_action(socket, :index, %{"chapter" => chapter}) do
    data = filter_data(@data, chapter)

    socket
    |> assign(:chapter, chapter)
    |> assign(:data, data)
    |> assign(years: data |> Map.keys() |> Enum.sort(:desc))
    |> assign(:page_title, build_title(chapter))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:chapter, nil)
    |> assign(:data, @data)
    |> assign(years: @data |> Map.keys() |> Enum.sort(:desc))
    |> assign(:page_title, gettext("Photographies timeline gallery"))
  end

  defp build_title(chapter) do
    gettext("Photographies gallery - ") <> String.capitalize(chapter)
  end

  defp filter_data(data, chapter) do
    data
    |> Enum.map(fn {k, v} -> {k, Enum.filter(v, &(&1.type == chapter))} end)
    |> Enum.filter(fn {_k, v} -> not Enum.empty?(v) end)
    |> Map.new()
  end
end
