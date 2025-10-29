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

# Bootstrap de l'utilisateur admin initial
# ADMIN_EMAIL peut être défini via variable d'environnement en production
admin_email = System.get_env("ADMIN_EMAIL") || "thibault.santonja@pm.me"

case Repo.get_by(User, email: admin_email) do
  nil ->
    %User{}
    |> User.bootstrap_admin_changeset(%{
      email: admin_email,
      name: "Thibault Santonja",
      role: :admin
    })
    |> Repo.insert!()
    |> then(fn user ->
      IO.puts("✓ Utilisateur admin créé: #{user.email}")
    end)

  user ->
    # Si l'utilisateur existe mais n'est pas admin, le promouvoir
    if user.role != :admin do
      user
      |> User.admin_changeset(%{role: :admin})
      |> Repo.update!()
      |> then(fn updated_user ->
        IO.puts("✓ Utilisateur #{updated_user.email} promu en admin")
      end)
    else
      IO.puts("✓ Utilisateur admin existe déjà: #{user.email}")
    end
end
