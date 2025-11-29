defmodule PortfolioWeb.Router do
  @moduledoc """
  Phoenix router for the Portfolio application.

  Defines pipelines for different subdomains (photography, tech, amvcc)
  and routes for public pages, authentication, and admin dashboard.
  """

  use PortfolioWeb, :router

  pipeline :amvcc do
    plug :accepts, ["html"]
    plug :fetch_session
    plug PortfolioWeb.Plugs.CSPNonce
    plug :fetch_live_flash
    plug :put_root_layout, html: {PortfolioWeb.Layouts, :amvcc}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PortfolioWeb.Plugs.SetLocale
  end

  pipeline :photography do
    plug :accepts, ["html"]
    plug :fetch_session
    plug PortfolioWeb.Plugs.CSPNonce
    plug :fetch_live_flash
    plug :put_root_layout, html: {PortfolioWeb.Layouts, :photography}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PortfolioWeb.Plugs.SetLocale
  end

  pipeline :tech do
    plug :accepts, ["html"]
    plug :fetch_session
    plug PortfolioWeb.Plugs.CSPNonce
    plug :fetch_live_flash
    plug :put_root_layout, html: {PortfolioWeb.Layouts, :tech}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PortfolioWeb.Plugs.SetLocale
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug PortfolioWeb.Plugs.CSPNonce
    plug :fetch_live_flash
    plug :put_root_layout, html: {PortfolioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PortfolioWeb.Plugs.SetLocale
    plug PortfolioWeb.Plugs.RequireAuth, :fetch_current_user
  end

  # Pipeline pour les pages d'authentification (login, register)
  # Redirige vers /admin si l'utilisateur est déjà connecté
  pipeline :auth_pages do
    plug :accepts, ["html"]
    plug :fetch_session
    plug PortfolioWeb.Plugs.CSPNonce
    plug :fetch_live_flash
    plug :put_root_layout, html: {PortfolioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PortfolioWeb.Plugs.SetLocale
    plug PortfolioWeb.Plugs.RequireAuth, :fetch_current_user
    plug PortfolioWeb.Plugs.RequireAuth, :redirect_if_user_is_authenticated
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :xml do
    plug :accepts, ["xml"]
  end

  # Pipeline pour l'interface admin avec authentification (pour les controllers)
  pipeline :require_authenticated_admin do
    plug :accepts, ["html"]
    plug :fetch_session
    plug PortfolioWeb.Plugs.CSPNonce
    plug :fetch_live_flash
    plug :put_root_layout, html: {PortfolioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PortfolioWeb.Plugs.RequireAuth, :fetch_current_user
    plug PortfolioWeb.Plugs.RequireAuth, :require_authenticated_user
    plug PortfolioWeb.Plugs.RequireAuth, :require_admin_role
  end

  # Pipeline pour les LiveViews admin (l'auth est gérée par on_mount)
  pipeline :admin_live do
    plug :accepts, ["html"]
    plug :fetch_session
    plug PortfolioWeb.Plugs.CSPNonce
    plug :fetch_live_flash
    plug :put_root_layout, html: {PortfolioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Health check endpoints (no authentication required)
  scope "/", PortfolioWeb do
    pipe_through :api

    get "/health", HealthController, :index
    get "/health/ready", HealthController, :ready
  end

  # CSP violation report endpoint
  scope "/api", PortfolioWeb do
    pipe_through :api

    post "/csp-report", CSPReportController, :report
  end

  scope "/", PortfolioWeb, host: "amvcc." do
    pipe_through :amvcc

    live "/", AmvccLive.Index, :index
    live "/blog", AmvccLive.Blog, :index
    live "/blog/vetements", AmvccLive.Blog.Clothes, :index
    live "/blog/chaussures", AmvccLive.Blog.Shoes, :index
  end

  scope "/", PortfolioWeb, host: "photo." do
    pipe_through :photography

    # Pages publiques avec utilisateur optionnel
    live_session :current_user,
      on_mount: [{PortfolioWeb.UserAuth, :mount_current_user}] do
      live "/", PhotographyLive.Index, :index
      live "/gallery", PhotographyLive.Gallery, :index
      live "/gallery/:chapter", PhotographyLive.Gallery, :index
      live "/timeline", PhotographyLive.Timeline, :index
      live "/timeline/:chapter", PhotographyLive.Timeline, :index
      live "/:chapter", PhotographyLive.Index, :index
    end
  end

  scope "/", PortfolioWeb, host: "tech." do
    pipe_through :tech

    live "/", TechLive.Index, :index
    live "/blog/ci", TechLive.Blog.Ci, :index
    live "/blog/kamal", TechLive.Blog.Kamal, :index
    live "/blog/elixir", TechLive.Blog.Elixir, :index
  end

  # Routes d'authentification
  scope "/", PortfolioWeb do
    pipe_through :auth_pages

    live_session :redirect_if_authenticated,
      on_mount: [{PortfolioWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/login", AuthLive.Login, :index
    end
  end

  # Routes d'authentification (sans LiveView)
  scope "/", PortfolioWeb do
    pipe_through :browser

    # Nouvelle méthode sécurisée (POST) - Landing page + vérification
    get "/auth/magic/:token", AuthController, :magic_link_landing
    post "/auth/verify", AuthController, :verify_magic_link_post

    # Ancienne méthode (GET direct) - conservée pour rétrocompatibilité
    get "/auth/verify/:token", AuthController, :verify_magic_link

    delete "/logout", AuthController, :logout
  end

  # Interface Admin (protégée par authentification)
  scope "/admin", PortfolioWeb.Admin, as: :admin do
    pipe_through :admin_live

    live_session :require_authenticated_admin,
      on_mount: [{PortfolioWeb.UserAuth, :ensure_authenticated}] do
      # Tableau de bord
      live "/", DashboardLive.Index, :index

      # Gestion des albums
      live "/albums", AlbumLive.Index, :index
      live "/albums/new", AlbumLive.New, :new
      live "/albums/:id/edit", AlbumLive.Edit, :edit

      # Gestion des photos
      live "/photos", PhotoLive.Index, :index

      # Gestion des utilisateurs
      live "/users", UserLive.Index, :index

      # Gestion du profil utilisateur
      live "/profile", ProfileLive.Edit, :edit

      # Gestion de la whitelist IP
      live "/ip-whitelist", IPWhitelistLive.Index, :index
      live "/ip-whitelist/new", IPWhitelistLive.Index, :new
      live "/ip-whitelist/:id/edit", IPWhitelistLive.Index, :edit
    end
  end

  # LiveDashboard (protégé par authentification admin en production)
  import Phoenix.LiveDashboard.Router

  scope "/admin" do
    pipe_through :require_authenticated_admin

    live_dashboard "/metrics",
      metrics: PortfolioWeb.Telemetry,
      ecto_repos: [Portfolio.Repo]
  end

  scope "/", PortfolioWeb do
    pipe_through :browser

    live "/", Live.Index, :index
    get "/amvcc", PageController, :subdomain_redirect
    get "/photo", PageController, :subdomain_redirect
    get "/tech", PageController, :subdomain_redirect
  end

  # SEO endpoints
  scope "/", PortfolioWeb do
    pipe_through :xml

    get "/sitemap.xml", SitemapController, :index
    get "/image-sitemap.xml", ImageSitemapController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", PortfolioWeb do
  #   pipe_through :api
  # end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:portfolio, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
