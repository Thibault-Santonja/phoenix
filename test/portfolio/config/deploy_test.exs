defmodule Portfolio.Config.DeployTest do
  @moduledoc """
  Verrou anti-dérive entre le budget d'infrastructure et le fichier que
  Kamal lit réellement.

  ## Le défaut que ce fichier ferme

  Le dépôt d'infrastructure (`~/Dev/thibaultsan-infra`) porte les valeurs de
  référence dans `kamal/portfolio/deploy.yml`, un fichier qui s'annonce
  lui-même comme une référence à recopier. Kamal, lui, ne lit QUE
  `config/deploy.yml` de ce dépôt. Les deux ont divergé : aucun plafond
  mémoire ni part processeur sur les deux conteneurs, la base publiée sur
  toutes les interfaces, aucun réglage PostgreSQL, pas de pilote de
  journalisation, pas de version minimale de Kamal.

  ## Ce que ce fichier vérifie, et ce qu'il ne vérifie pas

  Deux natures d'assertions cohabitent, et elles n'ont pas la même valeur :

    * les **invariants dérivés** (`describe "arithmétique du plafond"`,
      `describe "invariants de structure"`) calculent une contrainte à
      partir du fichier lui-même. Porter `max_connections` à 100 fait
      échouer le calcul du plafond sans qu'on ait rien à mettre à jour ici ;
    * les **valeurs figées** sont une copie assumée de la référence
      d'infrastructure. Leur rôle est de transformer une modification
      silencieuse de `config/deploy.yml` en échec de la porte de qualité, et
      d'obliger celui qui la fait à lire ici POURQUOI la valeur était
      celle-là avant de la changer aux deux endroits.

  Ce test ne remplace pas `kamal config`, qui seul rend l'ERB. Il le
  précède : `kamal config` omet `servers.web.options`, `minimum_version`,
  `proxy` et `service` de sa sortie (vérifié contre Kamal 2.12.0), donc il ne
  peut pas voir le plafond mémoire de l'application.

  Références d'infrastructure (dépôt `thibaultsan-infra`) :
  `docs/00-plan-directeur.md` section 2,
  `docs/budget-memoire-observabilite.md` sections 1 et 2,
  `docs/runbooks/04-kamal-socle.md` sections 2.4, 3, 5.1 et 5.3,
  `docs/runbooks/08-observabilite.md` sections 6 et 13.
  """

  use ExUnit.Case, async: true

  @deploy_path Path.expand("../../../config/deploy.yml", __DIR__)

  # Plafond mémoire du conteneur applicatif. Plan directeur section 2.
  # Un conteneur SANS limite peut prendre toute la machine ; le noyau choisit
  # alors lui-même quel processus tuer, et il choisit le plus gros,
  # c'est-à-dire un des deux sites. Avec une limite, le conteneur meurt seul
  # et redémarre : on perd un service au lieu de tous.
  @app_memory "400m"

  # Part processeur du conteneur applicatif : un demi-vCPU sur deux.
  # La plateforme photographique en prend 1,5 parce que son traitement
  # d'images sature les deux cœurs pendant une trentaine de minutes sur un
  # import de lot. Ce site-ci est un site vitrine : il n'a pas besoin de
  # davantage, et un plafond dur est ce qui garantit que les deux ne se
  # disputent pas la machine.
  @app_cpus "0.5"

  # Plafond mémoire de l'accessoire PostgreSQL. Sa cohérence avec les
  # réglages de `cmd` est recalculée plus bas, pas recopiée.
  @db_memory_mb 250

  # Surcoût des processus de service PostgreSQL (postmaster, writer, wal
  # writer, checkpointer, stats), hors tampons partagés et hors mémoire
  # privée des connexions. Même convention que
  # `services/postgres-outils/config/deploy.yml` du dépôt d'infrastructure.
  @db_service_overhead_mb 25

  setup_all do
    yaml = YamlElixir.read_from_file!(@deploy_path)

    db = dig(yaml, ["accessories", "db"])

    %{
      config: yaml,
      app_options: yaml |> dig(["servers", "web"]) |> role_options(),
      db: db || %{},
      db_settings: postgres_settings(dig(db, ["cmd"]))
    }
  end

  describe "compte de déploiement" do
    test "le compte SSH vient de la même variable que l'autre application", %{config: config} do
      # NON NÉGOCIABLE. L'état de Kamal vit dans `~/.kamal` du compte SSH, et
      # le garde-fou qui empêche `kamal remove` de supprimer le PROXY PARTAGÉ
      # compte les applications installées dans `~/.kamal/apps` du compte
      # COURANT. Deux comptes distincts le rendent aveugle : un
      # `kamal remove` lancé depuis l'autre dépôt croit la machine vide et
      # supprime le proxy. Les six noms d'hôtes de la machine tombent.
      #
      # Lire la MÊME variable dans les deux fichiers rend l'égalité vraie par
      # construction, plutôt que par vigilance. Runbook 04 section 3.
      assert dig(config, ["ssh", "user"]) == ~s(<%= ENV["KAMAL_SSH_USER"] %>)
    end

    test "refuse une version de Kamal plus ancienne que la référence", %{config: config} do
      assert config["minimum_version"] == "2.12.0"
    end

    test "l'adresse du serveur n'est écrite qu'une fois", %{config: config} do
      # L'adresse était répétée en dur à trois endroits. Une variable unique
      # supprime la classe d'erreur « on en a changé deux sur trois ».
      assert dig(config, ["servers", "web", "hosts"]) == [~s(<%= ENV["KAMAL_WEB_HOST"] %>)]
      assert dig(config, ["accessories", "db", "host"]) == ~s(<%= ENV["KAMAL_WEB_HOST"] %>)
    end
  end

  describe "construction de l'image" do
    test "la construction se fait sur le serveur, pas en émulation locale", %{config: config} do
      # L'émulation amd64 depuis un Mac Apple Silicon corrompt la mémoire du
      # BEAM pendant `mix deps.compile` (« no next heap size found » puis
      # abandon), Rosetta compris.
      assert dig(config, ["builder", "remote"]) ==
               ~s(ssh://<%= ENV["KAMAL_SSH_USER"] %>@<%= ENV["KAMAL_WEB_HOST"] %>)
    end
  end

  describe "budget du conteneur applicatif" do
    test "le plafond mémoire est celui du plan directeur", %{app_options: options} do
      assert options["memory"] == @app_memory
    end

    test "la part processeur laisse les coeurs à l'autre application", %{app_options: options} do
      assert options["cpus"] == @app_cpus
    end
  end

  describe "journalisation" do
    test "les journaux partent vers le journal système", %{config: config} do
      # Sans bloc `logging`, Kamal impose `--log-opt max-size=10m`, donc le
      # pilote `json-file` : les journaux restent dans des fichiers locaux et
      # AUCUNE ligne du site n'entre dans le collecteur. Déclaré à la racine,
      # ce bloc couvre le conteneur applicatif ET l'accessoire PostgreSQL.
      assert dig(config, ["logging", "driver"]) == "journald"
    end

    test "aucune option que le pilote journald refuse", %{config: config} do
      # `unknown log opt 'max-size' for journald log driver` : le conteneur
      # refuse de démarrer.
      refute dig(config, ["logging", "options"])
    end
  end

  describe "base PostgreSQL" do
    test "publiée sur la boucle locale uniquement", %{db: db} do
      # `port: 5432` sans adresse était traduit par Kamal en
      # `--publish 5432:5432`, lié sur TOUTES les interfaces. Docker écrit ses
      # règles de publication dans la chaîne `DOCKER` d'iptables, EN AMONT de
      # celle où vit une règle `ufw` : un pare-feu qui « ferme » le 5432 ne
      # fermait rien. La base était joignable depuis Internet, et seul le mot
      # de passe PostgreSQL protégeait les données.
      # Runbook 04 sections 5.1 et 5.3.
      assert db["port"] == "127.0.0.1:5432:5432"
    end

    test "le plafond mémoire est celui du plan directeur", %{db: db} do
      assert dig(db, ["options", "memory"]) == "#{@db_memory_mb}m"
    end

    test "les données vivent à un chemin absolu, hors du compte SSH", %{db: db} do
      assert db["directories"] == ["/var/portfolio/db:/var/lib/postgresql/data"]
    end

    test "pg_stat_statements est chargé", %{db_settings: settings} do
      assert settings["shared_preload_libraries"] == "'pg_stat_statements'"
    end

    test "le parallélisme est coupé", %{db_settings: settings} do
      assert settings["max_parallel_workers_per_gather"] == "0"
    end

    test "l'autovacuum est découplé de maintenance_work_mem", %{db_settings: settings} do
      # Piège classique : `autovacuum_work_mem` vaut -1 par défaut, ce qui
      # signifie « prendre maintenance_work_mem », et `autovacuum_max_workers`
      # vaut 3. Trois ouvriers à 64 Mo peuvent se lever d'un coup, la nuit,
      # sans qu'aucune requête utilisateur ne soit en cause.
      assert settings["autovacuum_work_mem"] == "16MB"
      assert settings["autovacuum_max_workers"] == "2"
    end
  end

  describe "arithmétique du plafond PostgreSQL" do
    # Le cœur du garde-fou. Un plafond qu'on n'a pas confronté à
    # l'arithmétique des réglages qu'il encadre est un chiffre rassurant, pas
    # une protection. Ce calcul est DÉRIVÉ du fichier : relâcher un réglage
    # sans relever le plafond fait échouer ce test sans qu'aucune valeur
    # n'ait à être mise à jour ici.

    test "le pire cas des réglages tient sous le plafond posé", %{db_settings: settings} do
      worst_case = worst_case_mb(settings)

      assert worst_case <= @db_memory_mb, """
      Le pire cas des réglages PostgreSQL (#{worst_case} Mo) dépasse le plafond
      de #{@db_memory_mb} Mo posé sur l'accessoire. Le conteneur serait tué par le
      noyau au premier pic, et le plafond déclencherait l'incident au lieu de
      le borner.

      Détail : #{inspect(memory_breakdown(settings))}

      Deux issues : resserrer les réglages de `cmd`, ou relever le plafond ET la
      ligne correspondante du tableau de `docs/budget-memoire-observabilite.md`
      du dépôt d'infrastructure. Un plafond ne réserve rien : le relever ne coûte
      pas de marge à la machine, le laisser sous l'arithmétique si.
      """
    end

    test "le plafond n'immobilise pas de marge pour rien", %{db_settings: settings} do
      worst_case = worst_case_mb(settings)

      assert worst_case >= div(@db_memory_mb, 2), """
      Le pire cas des réglages (#{worst_case} Mo) est très en-dessous du plafond
      de #{@db_memory_mb} Mo : soit les réglages sont inutilement serrés, soit le
      plafond est décoratif. Revoir les deux ensemble.
      """
    end
  end

  describe "invariants de structure" do
    test "chaque conteneur déclare un plafond mémoire", %{config: config} do
      for {name, options} <- containers_options(config) do
        assert is_binary(options["memory"]),
               "#{name} ne déclare aucun plafond mémoire : sans lui, le noyau choisit " <>
                 "lui-même sa victime quand la machine sature, et il choisit le plus gros"
      end
    end

    test "aucun accessoire ne publie de port hors de la boucle locale", %{config: config} do
      for {name, accessory} <- Map.get(config, "accessories", %{}),
          port = accessory["port"],
          not is_nil(port) do
        assert String.starts_with?(to_string(port), "127.0.0.1:"),
               "l'accessoire #{name} publie #{inspect(port)} sur toutes les interfaces"
      end
    end

    test "chaque répertoire de données est un chemin absolu", %{config: config} do
      for {name, accessory} <- Map.get(config, "accessories", %{}),
          mapping <- accessory["directories"] || [] do
        assert String.starts_with?(mapping, "/"),
               "l'accessoire #{name} monte #{inspect(mapping)} depuis un chemin relatif, " <>
                 "que Kamal résout dans le répertoire personnel du compte SSH"
      end
    end
  end

  describe "bloc proxy partagé avec la plateforme photographique" do
    # Kamal ne vérifie la cohérence des blocs `proxy.run` qu'à l'intérieur
    # d'un même fichier. Entre deux applications, aucune vérification : la
    # première qui crée le conteneur impose sa configuration, et
    # `kamal proxy boot` ne recrée jamais un conteneur existant. Une
    # divergence ne produit AUCUNE erreur, seulement un réglage qui ne
    # s'applique pas. Runbook 04 section 2.4.

    test "la version du proxy est figée", %{config: config} do
      assert dig(config, ["proxy", "run", "version"]) == "v0.9.2"
    end

    test "le journal du proxy est borné", %{config: config} do
      assert dig(config, ["proxy", "run", "log_max_size"]) == "10m"
    end
  end

  # -- Aides ---------------------------------------------------------------

  # `get_in/2` lève sur une liste : `servers.web` peut légitimement s'écrire
  # en liste d'hôtes nue. Sans ce contournement, une régression vers cette
  # forme ferait exploser `setup_all` et invaliderait tout le fichier, au lieu
  # de faire échouer la seule assertion concernée avec son message.
  defp dig(value, keys) do
    Enum.reduce(keys, value, fn
      key, map when is_map(map) -> Map.get(map, key)
      _key, _other -> nil
    end)
  end

  defp postgres_settings(nil), do: %{}

  defp postgres_settings(cmd) when is_binary(cmd) do
    ~r/-c\s+([a-z_]+)=(\S+)/
    |> Regex.scan(cmd)
    |> Map.new(fn [_, key, value] -> {key, value} end)
  end

  # Borne haute de la mémoire que les réglages autorisent : tampons partagés,
  # plus la mémoire privée de toutes les connexions ouvertes ensemble, plus
  # les ouvriers autovacuum, plus les processus de service.
  # `maintenance_work_mem` n'entre pas dans ce total : il borne une
  # maintenance lancée à la main, que la marge restante doit absorber.
  defp worst_case_mb(settings) do
    settings |> memory_breakdown() |> Map.values() |> Enum.sum()
  end

  defp memory_breakdown(settings) do
    %{
      shared_buffers_mb: size_mb(settings["shared_buffers"]),
      connections_mb: integer(settings["max_connections"]) * size_mb(settings["work_mem"]),
      autovacuum_mb:
        integer(settings["autovacuum_max_workers"]) * size_mb(settings["autovacuum_work_mem"]),
      service_overhead_mb: @db_service_overhead_mb
    }
  end

  # Tous les conteneurs du fichier : le rôle applicatif et chaque accessoire,
  # avec leur bloc `options` (vide s'il manque).
  defp containers_options(config) do
    roles =
      config
      |> Map.get("servers", %{})
      |> Map.new(fn {name, role} -> {"servers/#{name}", role_options(role)} end)

    accessories =
      config
      |> Map.get("accessories", %{})
      |> Map.new(fn {name, accessory} ->
        {"accessories/#{name}", Map.get(accessory, "options", %{})}
      end)

    Map.merge(roles, accessories)
  end

  # Un rôle peut s'écrire en liste d'hôtes nue, sans bloc `options`.
  defp role_options(role) when is_map(role), do: Map.get(role, "options") || %{}
  defp role_options(_role), do: %{}

  defp size_mb(nil), do: 0
  defp size_mb(value) when is_binary(value), do: value |> String.trim_trailing("MB") |> integer()

  defp integer(nil), do: 0
  defp integer(value) when is_binary(value), do: String.to_integer(value)
end
