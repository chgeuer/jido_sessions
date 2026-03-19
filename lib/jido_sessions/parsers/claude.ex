defmodule JidoSessions.Parsers.Claude do
  @moduledoc """
  Parses raw Claude Code events into canonical `Turn` structs.

  Claude events are `assistant`/`user` with nested `message.content` arrays.
  Tool calls are inline `tool_use` blocks; results are `tool_result` user messages.
  """

  alias JidoSessions.Turn
  alias JidoSessions.Parsers.Helpers

  @skip_types ~w[file-history-snapshot progress queue-operation summary system custom-title]

  @spec parse_turns([map()]) :: [Turn.t()]
  def parse_turns(events) do
    tool_results = index_tool_results(events)

    events
    |> Enum.reject(fn e -> e.type in @skip_types end)
    |> chunk_into_turns()
    |> Enum.with_index()
    |> Enum.map(fn {turn_events, index} ->
      build_turn(turn_events, index, tool_results)
    end)
  end

  defp index_tool_results(events) do
    events
    |> Enum.filter(&(&1.type == "user"))
    |> Enum.flat_map(fn e ->
      content = get_in(e.data, ["message", "content"])

      if is_list(content) do
        content
        |> Enum.filter(&(is_map(&1) && &1["type"] == "tool_result"))
        |> Enum.map(fn block ->
          result_text = extract_text_content(block["content"])
          is_error = block["is_error"] == true

          {block["tool_use_id"], %{
            "result" => result_text,
            "success" => !is_error,
            "error" => if(is_error, do: result_text)
          }}
        end)
      else
        []
      end
    end)
    |> Map.new()
  end

  defp chunk_into_turns(events) do
    {turns, current} =
      Enum.reduce(events, {[], []}, fn event, {turns, current} ->
        content = get_in(event.data, ["message", "content"])

        is_tool_result =
          is_list(content) &&
            Enum.any?(content, &(is_map(&1) && &1["type"] == "tool_result"))

        if event.type == "user" && !is_tool_result && current != [] do
          {turns ++ [current], [event]}
        else
          {turns, current ++ [event]}
        end
      end)

    if current != [], do: turns ++ [current], else: turns
  end

  defp build_turn(events, index, tool_results) do
    user_event =
      Enum.find(events, fn e ->
        e.type == "user" &&
          !(get_in(e.data, ["message", "content"]) |> is_list() &&
              get_in(e.data, ["message", "content"])
              |> Enum.any?(&(is_map(&1) && &1["type"] == "tool_result")))
      end)

    user_content =
      if user_event do
        content = get_in(user_event.data, ["message", "content"])
        extract_text_content(content)
      end

    assistant_events = Enum.filter(events, &(&1.type == "assistant"))

    {texts, reasoning_texts, tool_calls} =
      Enum.reduce(assistant_events, {[], [], []}, fn event, {texts, reasoning, tools} ->
        content = get_in(event.data, ["message", "content"])

        if is_list(content) do
          Enum.reduce(content, {texts, reasoning, tools}, fn block, {t, r, tc} ->
            case block do
              %{"type" => "text", "text" => text} when is_binary(text) and text != "" ->
                {t ++ [text], r, tc}

              %{"type" => "thinking", "thinking" => thinking}
              when is_binary(thinking) and thinking != "" ->
                {t, r ++ [thinking], tc}

              %{"type" => "tool_use", "id" => id, "name" => name, "input" => input} ->
                result_data = Map.get(tool_results, id)
                args = Helpers.parse_arguments(input)

                tool_call =
                  Helpers.build_tool_call(
                    name,
                    args,
                    id: id,
                    result: result_data && result_data["result"],
                    success?: result_data && result_data["success"]
                  )

                {t, r, tc ++ [tool_call]}

              _ ->
                {t, r, tc}
            end
          end)
        else
          {texts, reasoning, tools}
        end
      end)

    %Turn{
      index: index,
      started_at: user_event && user_event[:timestamp],
      user_content: user_content,
      reasoning: if(reasoning_texts != [], do: Enum.join(reasoning_texts, "\n\n")),
      assistant_content: if(texts != [], do: Enum.join(texts, "\n\n")),
      tool_calls: tool_calls
    }
  end

  defp extract_text_content(content) when is_binary(content), do: content

  defp extract_text_content(content) when is_list(content) do
    content
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => t} when is_binary(t) -> [t]
      %{"text" => t} when is_binary(t) -> [t]
      _ -> []
    end)
    |> Enum.join("\n")
    |> then(fn t -> if String.trim(t) != "", do: t end)
  end

  defp extract_text_content(_), do: nil
end
