defmodule Portfolio.Photography.Catalog.SnapshotTest do
  use ExUnit.Case, async: true

  alias Portfolio.Photography.Catalog.Snapshot

  setup do
    dir = Path.join(System.tmp_dir!(), "catalog-snapshot-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  describe "write/3 et read/2" do
    test "relit ce qui a ete écrit", %{dir: dir} do
      payload = %{"data" => [%{"slug" => "un-album"}]}

      assert :ok = Snapshot.write(dir, {:albums, "fr"}, payload)
      assert {:ok, ^payload} = Snapshot.read(dir, {:albums, "fr"})
    end

    test "créée le répertoire au premier appel", %{dir: dir} do
      refute File.dir?(dir)

      assert :ok = Snapshot.write(dir, :themes, %{"data" => []})
      assert File.dir?(dir)
    end

    test "separe les clés", %{dir: dir} do
      assert :ok = Snapshot.write(dir, {:albums, "fr"}, %{"data" => ["fr"]})
      assert :ok = Snapshot.write(dir, {:albums, "en"}, %{"data" => ["en"]})

      assert {:ok, %{"data" => ["fr"]}} = Snapshot.read(dir, {:albums, "fr"})
      assert {:ok, %{"data" => ["en"]}} = Snapshot.read(dir, {:albums, "en"})
    end

    test "remplace l'instantané précédent", %{dir: dir} do
      assert :ok = Snapshot.write(dir, :themes, %{"data" => ["ancien"]})
      assert :ok = Snapshot.write(dir, :themes, %{"data" => ["nouveau"]})

      assert {:ok, %{"data" => ["nouveau"]}} = Snapshot.read(dir, :themes)
    end

    test "ne laisse aucun fichier temporaire derrière lui", %{dir: dir} do
      assert :ok = Snapshot.write(dir, :themes, %{"data" => []})

      assert dir |> File.ls!() |> Enum.reject(&String.ends_with?(&1, ".json")) == []
    end

    test "signale l'absence d'instantané", %{dir: dir} do
      assert :error = Snapshot.read(dir, :jamais_ecrit)
    end

    test "signale un instantané illisible plutôt que de lever", %{dir: dir} do
      assert :ok = Snapshot.write(dir, :themes, %{"data" => []})

      dir
      |> File.ls!()
      |> Enum.each(&File.write!(Path.join(dir, &1), "{ceci n'est pas du json"))

      assert :error = Snapshot.read(dir, :themes)
    end

    test "se tait quand aucun répertoire n'est configure" do
      assert :ok = Snapshot.write(nil, :themes, %{"data" => []})
      assert :error = Snapshot.read(nil, :themes)
    end

    test "signale l'échec d'écriture plutôt que de lever", %{dir: dir} do
      File.mkdir_p!(dir)
      fichier = Path.join(dir, "occupe")
      File.write!(fichier, "")

      assert {:error, _reason} = Snapshot.write(fichier, :themes, %{"data" => []})
    end
  end
end
