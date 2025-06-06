defmodule PortfolioWeb.Router do
  use PortfolioWeb, :router

  pipeline :amvcc do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PortfolioWeb.Layouts, :amvcc}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PortfolioWeb.Plugs.SetLocale
  end

  pipeline :photography do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PortfolioWeb.Layouts, :photography}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PortfolioWeb.Plugs.SetLocale
  end

  pipeline :tech do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PortfolioWeb.Layouts, :tech}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PortfolioWeb.Plugs.SetLocale
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PortfolioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PortfolioWeb.Plugs.SetLocale
  end

  pipeline :api do
    plug :accepts, ["json"]
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

    live "/", PhotographyLive.Index, :index
    live "/gallery", PhotographyLive.Gallery, :index
    live "/gallery/:chapter", PhotographyLive.Gallery, :index
    live "/timeline", PhotographyLive.Timeline, :index
    live "/timeline/:chapter", PhotographyLive.Timeline, :index
    live "/:chapter", PhotographyLive.Index, :index
  end

  scope "/", PortfolioWeb, host: "tech." do
    pipe_through :tech

    live "/", TechLive.Index, :index
    live "/blog/ci", TechLive.Blog.Ci, :index
    live "/blog/kamal", TechLive.Blog.Kamal, :index
    live "/blog/elixir", TechLive.Blog.Elixir, :index
  end

  scope "/", PortfolioWeb do
    pipe_through :browser

    live "/", Live.Index, :index
    get "/amvcc", PageController, :subdomain_redirect
    get "/photo", PageController, :subdomain_redirect
    get "/tech", PageController, :subdomain_redirect
  end

  # Other scopes may use custom stacks.
  # scope "/api", PortfolioWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:portfolio, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PortfolioWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
