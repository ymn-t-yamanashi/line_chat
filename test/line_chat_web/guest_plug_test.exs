defmodule LineChatWeb.GuestPlugTest do
  @moduledoc """
  `LineChatWeb.GuestPlug` assigns one guest identity per browser session and
  keeps it across requests, so a LiveView reconnect sees the same viewer.
  """

  use LineChatWeb.ConnCase, async: false

  alias LineChat.Chat
  alias LineChat.Chat.{Room, Store}
  alias LineChatWeb.GuestPlug

  @guest_prefix "ゲスト "

  defp with_session(conn, session \\ %{}) do
    Plug.Test.init_test_session(conn, session)
  end

  defp guest_id(conn) do
    Plug.Conn.get_session(conn, GuestPlug.session_key())
  end

  defp guests do
    Store.list_users()
    |> Enum.filter(fn user -> String.starts_with?(user.name, @guest_prefix) end)
  end

  defp room_names(summaries) do
    summaries |> Enum.map(fn summary -> summary.room.name end) |> Enum.sort()
  end

  describe "configuration" do
    test "init ignores options", _ctx do
      assert GuestPlug.init(nil) == nil
      assert GuestPlug.init([]) == nil
      assert GuestPlug.init(some: "thing") == nil
    end

    test "exposes the session key", _ctx do
      assert GuestPlug.session_key() == "line_chat_guest_id"
    end
  end

  describe "guest_session/1" do
    test "is nil for a fetched session without a guest", %{conn: conn} do
      assert GuestPlug.guest_session(with_session(conn)) == nil
    end

    test "is nil when the stored value is not a binary", %{conn: conn} do
      conn = with_session(conn, %{GuestPlug.session_key() => 42})

      assert GuestPlug.guest_session(conn) == nil
    end

    test "reads a stored guest id", %{conn: conn} do
      {:ok, user} = Chat.create_guest_user()
      conn = with_session(conn, %{GuestPlug.session_key() => user.id})

      assert GuestPlug.guest_session(conn) == user.id
    end

    test "needs a fetched session", %{conn: conn} do
      assert_raise ArgumentError, fn -> GuestPlug.guest_session(conn) end
    end
  end

  describe "call/2" do
    test "creates a guest and stores its id", %{conn: conn} do
      conn = GuestPlug.call(with_session(conn), GuestPlug.init(nil))
      id = guest_id(conn)

      assert is_binary(id)
      {:ok, user} = Chat.fetch_user(id)
      assert String.starts_with?(user.name, @guest_prefix)
      assert conn.state == :unset
    end

    test "joins the new guest to every room", %{conn: conn} do
      conn = GuestPlug.call(with_session(conn), nil)
      id = guest_id(conn)
      seeded = Store.list_rooms() |> Enum.map(fn room -> room.name end) |> Enum.sort()

      assert Chat.list_rooms(id) |> room_names() == seeded

      assert Store.list_rooms()
             |> Enum.filter(fn room -> Room.member?(room, id) end)
             |> Enum.map(fn room -> room.name end)
             |> Enum.sort() == seeded
    end

    test "reuses a stored guest without creating another user", %{conn: conn} do
      {:ok, existing} = Chat.create_guest_user()
      conn = with_session(conn, %{GuestPlug.session_key() => existing.id})
      before = Store.list_users()

      called = GuestPlug.call(conn, nil)

      assert called == conn
      assert guest_id(called) == existing.id
      assert Store.list_users() == before
    end

    test "replaces a stored value that is not a guest id", %{conn: conn} do
      conn = with_session(conn, %{GuestPlug.session_key() => 42})
      {:ok, user} = Chat.fetch_user(guest_id(GuestPlug.call(conn, nil)))

      assert String.starts_with?(user.name, @guest_prefix)
    end

    test "gives sessions without a guest different identities", %{conn: conn} do
      first = guest_id(GuestPlug.call(with_session(conn), nil))
      second = guest_id(GuestPlug.call(with_session(conn), nil))

      assert first != second
      assert guests() |> length() == 2
    end
  end

  describe "through the browser pipeline" do
    test "GET / assigns a guest the page then shows", %{conn: conn} do
      response = get(conn, ~p"/")
      [guest] = guests()

      assert response.status == 200
      assert response.resp_body =~ guest.name
      assert guest_id(response) == guest.id
      assert Enum.at(Chat.list_rooms(guest.id), 0).room.name == "チーム開発"
    end

    test "a request carrying the same session keeps that guest", %{conn: conn} do
      first = get(conn, ~p"/")
      id = guest_id(first)
      before = guests()

      repeat =
        build_conn()
        |> with_session(first.private[:plug_session])
        |> get(~p"/")

      assert guest_id(repeat) == id
      assert guests() == before
      assert repeat.resp_body =~ Chat.fetch_user(id) |> elem(1) |> Map.fetch!(:name)
    end

    test "a fresh session gets a fresh guest", %{conn: conn} do
      first = guest_id(get(conn, ~p"/"))
      second = guest_id(get(build_conn(), ~p"/"))

      assert first != second
      assert guests() |> length() == 2
    end
  end
end
