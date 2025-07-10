# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Portfolio.Repo.insert!(%Portfolio.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`)
# so that if something goes wrong, you'll see the error immediately.

alias Portfolio.Repo
alias Portfolio.Auth.User

# Créer l'utilisateur admin initial (vous !)
admin_email = System.get_env("ADMIN_EMAIL") || "thibault.santonja@pm.me"

case Repo.get_by(User, email: admin_email) do
  nil ->
    %User{}
    |> User.registration_changeset(%{
      email: admin_email,
      name: "Admin",
      role: "admin"
    })
    |> Repo.insert!()
    |> then(fn user ->
      IO.puts("✓ Utilisateur admin créé: #{user.email}")
    end)

  user ->
    IO.puts("✓ Utilisateur admin existe déjà: #{user.email}")
end
