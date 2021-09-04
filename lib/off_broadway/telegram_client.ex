defmodule OffBroadway.Telegram.TelegramClient do
  @moduledoc """
  A generic behavior to implement Telegram Client for `OffBroadway.Telegram.Producer`.
  This module defines callbacks to fetch updates from Telegram Bot Api via long polling
  """

  @callback get_updates(offset :: integer, limit :: pos_integer, opts :: [atom]) ::
              {new_offset :: pos_integer, [Broadway.Message.t()]}
end
