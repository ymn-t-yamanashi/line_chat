defmodule LineChatWeb.ChatComponents do
  @moduledoc """
  Presentational pieces of the chat UI: room rows, message bubbles, day
  separators and flash messages. These components read assigns only — they
  never touch `LineChat.Chat.Store`, so they render identically in tests.
  """

  use Phoenix.Component

  alias LineChat.Chat.{Room, RoomSummary, User}

  @default_avatar_color "#06c755"

  @doc """
  Renders a coloured avatar tile with the first character of the user name.
  """
  def avatar(assigns) do
    ~H"""
    <span class="avatar" style={"background-color: #{avatar_color(@user)}"}>
      {avatar_char(@user)}
    </span>
    """
  end

  @doc """
  Renders one transcript entry: avatar, author, body, clock label, read state
  and — for the viewer's own messages — a redact button.
  """
  def bubble(assigns) do
    assigns =
      assigns
      |> assign_new(:self, fn -> false end)
      |> assign_new(:read_state, fn -> nil end)
      |> assign_new(:time, fn -> "" end)

    ~H"""
    <div class="message-row">
      <.avatar user={@author} />
      <div class={bubble_class(@self)}>
        <p class="bubble-author">{@author.name}</p>
        <p :if={!@message.redacted} class="bubble-body">{@message.body}</p>
        <p :if={@message.redacted} class="redacted-note">メッセージを取り消しました</p>
        <div class="bubble-meta">
          <span class="bubble-time">{@time}</span>
          <span :if={@self && @read_state} class="read-state">{read_label(@read_state)}</span>
        </div>
        <button
          :if={@self && !@message.redacted}
          type="button"
          class="redact-button"
          phx-click="redact"
          phx-value-message={@message.id}
        >
          取り消す
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders the day divider shown above a group of messages.
  """
  def day_separator(assigns) do
    ~H"""
    <div class="day-separator">{@label}</div>
    """
  end

  @doc """
  Renders a room row in the home list. The delete button sits outside the link
  so clicking it never navigates into the room.
  """
  def room_row(assigns) do
    assigns = assign_new(assigns, :typing_names, fn -> [] end)

    ~H"""
    <li class="room-row">
      <a class="room-row-link" href={@href}>
        <span class="room-avatar">{room_glyph(@summary)}</span>
        <span class="room-text">
          <span class="room-name">{@summary.room.name}</span>
          <span class="room-preview">{RoomSummary.preview(@summary)}</span>
          <span :if={typing_label(@typing_names)} class="typing">{typing_label(@typing_names)}</span>
        </span>
        <span :if={@summary.unread_count > 0} class="unread-badge">{@summary.unread_count}</span>
      </a>
      <button
        type="button"
        class="delete-room"
        phx-click="delete_room"
        phx-value-room={@summary.room.id}
      >
        削除
      </button>
    </li>
    """
  end

  @doc """
  A comma-separated typing hint, or `nil` when nobody is typing.
  """
  def typing_label([]), do: nil

  def typing_label(names) do
    Enum.map_join(names, "、", fn name -> "#{name}が入力中…" end)
  end

  @doc """
  Renders every flash key the LiveView currently holds.
  """
  def flash_group(assigns) do
    ~H"""
    <div id="flash_group">
      <.flash kind={:info} title="通知" flash={@flash} />
      <.flash kind={:error} title="エラー" flash={@flash} />
    </div>
    """
  end

  @doc false
  def flash(assigns) do
    assigns = assign_new(assigns, :title, fn -> nil end)

    ~H"""
    <div
      :if={Phoenix.Flash.get(@flash, @kind)}
      class={"flash flash--#{@kind}"}
      phx-click="lv:clear-flash"
      phx-value-key={@kind}
    >
      <p :if={@title} class="flash-title">{@title}</p>
      {Phoenix.Flash.get(@flash, @kind)}
    </div>
    """
  end

  @doc false
  def bubble_class(true), do: "bubble bubble--self"
  def bubble_class(_self), do: "bubble"

  @doc false
  def avatar_color(%User{color: color}) when is_binary(color), do: color
  def avatar_color(_user), do: @default_avatar_color

  @doc false
  def avatar_char(%User{name: name}), do: User.avatar_char(name)

  defp read_label(:read), do: "既読"
  defp read_label(_unread), do: "未読"

  defp room_glyph(%RoomSummary{room: %Room{name: ""}}), do: "G"
  defp room_glyph(%RoomSummary{room: %Room{name: name}}), do: String.first(name)
end
