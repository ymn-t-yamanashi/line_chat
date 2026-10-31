defmodule LineChat.Chat.Time do
  @moduledoc """
  Display-time helpers. Messages are stored as UTC `DateTime`s; the UI shows
  them in a fixed offset (Japan Standard Time by default) so that LINE-style
  day separators and clock labels are stable and testable without a tz db.
  """

  @weekdays ["月", "火", "水", "木", "金", "土", "日"]

  @doc """
  The configured offset from UTC, in seconds.
  """
  def utc_offset do
    Application.get_env(:line_chat, :utc_offset, 9 * 3600)
  end

  @doc """
  Shifts a UTC timestamp into the display timezone.
  """
  def to_local(%DateTime{} = utc) do
    DateTime.add(utc, utc_offset(), :second)
  end

  @doc """
  The calendar date in the display timezone.
  """
  def local_date(%DateTime{} = utc), do: to_local(utc) |> DateTime.to_date()

  @doc """
  A `HH:MM` clock label, zero padded, in the display timezone.
  """
  def time_label(%DateTime{} = utc) do
    local = to_local(utc)
    pad_two(local.hour) <> ":" <> pad_two(local.minute)
  end

  @doc """
  A day separator label for `date`, relative to `today`.

  Recent days read 今日 / 昨日 / 一昨日; anything older reads `M月D日 ( weekday )`,
  prefixed with the year when it is not `today`'s year.
  """
  def date_label(%Date{} = date, %Date{} = today) do
    cond do
      date == today -> "今日"
      date == Date.add(today, -1) -> "昨日"
      date == Date.add(today, -2) -> "一昨日"
      true -> dated_label(date, today.year)
    end
  end

  @doc """
  The Japanese weekday name for a date.
  """
  def weekday_label(%Date{} = date), do: Enum.at(@weekdays, Date.day_of_week(date) - 1)

  @doc """
  True when two timestamps fall on the same display-timezone date.
  """
  def same_day?(left, right) do
    local_date(left) == local_date(right)
  end

  defp dated_label(%Date{} = date, today_year) do
    year_prefix =
      if date.year == today_year do
        ""
      else
        to_string(date.year) <> "年"
      end

    year_prefix <> "#{date.month}月#{date.day}日 (#{weekday_label(date)})"
  end

  defp pad_two(number) do
    number |> to_string() |> String.pad_leading(2, "0")
  end
end
