defmodule LineChatWeb.Router do
  use LineChatWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    # Assigns a guest identity to the session before any LiveView reads it
    plug LineChatWeb.GuestPlug
    plug :put_root_layout, html: {LineChatWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LineChatWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/rooms/:room_id", RoomLive
  end

  scope "/api", LineChatWeb do
    pipe_through :api

    get "/health", HealthController, :index
    get "/rooms", ApiController, :rooms
    get "/rooms/:room_id/messages", ApiController, :messages
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:line_chat, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LineChatWeb.Telemetry
    end
  end
end
