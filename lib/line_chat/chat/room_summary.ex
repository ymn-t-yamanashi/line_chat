defmodule LineChat.Chat.RoomSummary do
  @moduledoc """
  Room row data for the home screen: last message preview, unread count and
  who is currently typing.
  """

  alias LineChat.Chat.{Message, Room, RoomSummary}

  @preview_length 28

  defstruct [:room, :viewer_id, :last_message, :unread_count, typing_user_ids: []]

  @type t :: %__MODULE__{
          room: Room.t(),
          viewer_id: String.t(),
          last_message: Message.t() | nil,
          unread_count: non_neg_integer(),
          typing_user_ids: [String.t()]
        }

  @doc """
  Builds a summary row for `viewer_id`.
  """
  def new(room, viewer_id, last_message, unread_count, typing_user_ids \\ []) do
    %__MODULE__{
      room: room,
      viewer_id: viewer_id,
      last_message: last_message,
      unread_count: unread_count,
      typing_user_ids: typing_user_ids
    }
  end

  @doc """
  The one-line preview shown under a room name, LINE style.
  """
  def preview(%RoomSummary{last_message: nil}), do: "メッセージはまだありません"

  def preview(%RoomSummary{last_message: %Message{redacted: true}}),
    do: "メッセージを取り消しました"

  def preview(%RoomSummary{last_message: %Message{body: body}}), do: truncate(body)

  @doc """
  The timestamp of the newest activity in the room, used for sorting.
  """
  def last_activity(%RoomSummary{last_message: %Message{inserted_at: at}}), do: at
  def last_activity(%RoomSummary{room: %Room{created_at: at}}), do: at || DateTime.utc_now()

  defp truncate(body) do
    if String.length(body) > @preview_length do
      String.slice(body, 0, @preview_length) <> "…"
    else
      body
    end
  end
end
