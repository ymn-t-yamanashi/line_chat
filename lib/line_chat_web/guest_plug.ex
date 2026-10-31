defmodule LineChatWeb.GuestPlug do
  @moduledoc """
  Gives every browser session a guest identity, the way LINE assigns an account
  to a device. The id is stored in the cookie session so both the initial GET
  and the LiveView websocket reconnect resolve the same viewer.
  """

  import Plug.Conn

  alias LineChat.Chat

  @session_key "line_chat_guest_id"

  def init(_opts), do: nil

  def call(conn, _opts) do
    case guest_session(conn) do
      nil -> create_guest(conn)
      _guest_id -> conn
    end
  end

  @doc """
  The session key holding the guest id.
  """
  def session_key, do: @session_key

  @doc """
  The guest id already stored on this connection, or `nil`.
  """
  def guest_session(conn) do
    case get_session(conn, @session_key) do
      guest_id when is_binary(guest_id) -> guest_id
      _stored -> nil
    end
  end

  defp create_guest(conn) do
    {:ok, user} = Chat.create_guest_user()
    put_session(conn, @session_key, user.id)
  end
end
