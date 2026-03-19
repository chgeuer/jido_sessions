defmodule JidoSessions.Parsers.Pi do
  @moduledoc """
  Parses raw Pi events into canonical `Turn` structs.

  Pi events are `message` type with role-based dispatch (user/assistant/toolResult).
  Content blocks use Claude-style format: thinking, text, toolCall.
  """

  alias JidoSessions.Turn
  alias JidoSessions.Parsers.Helpers

  @skip_types ~w[session model_change thinking_level_change]

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
    |> Enum.filter(fn e ->
      e.type == "message" && get_in(e.data, ["message", "role"]) == "toolResult"
    end)
    |> Map.new(fn e ->
      msg = e.data["message"]
      call_id = msg["toolCallId"]
      content = msg["content"] || []
      is_error = msg["isError"] == true

      result_text =
        content
        |> Enum.flat_map(fn
          %{"type" => "text", "text" => t} when is_binary(t) -> [t]
          _ -> []
        end)
        |> Enum.join("\n")

      {call_id,
       %{
         "result" => result_text,
         "success" => !is_error,
         "error" => if(is_error, do: result_text)
       }}
    end)
  end

  defp chunk_into_turns(events) do
    {turns, current} =
      Enum.reduce(events, {[], []}, fn event, {turns, current} ->
        role = get_in(event.data, ["message", "role"])

        if role == "user" && current != [] do
          {turns ++ [current], [event]}
        else
          {turns, current ++ [event]}
        end
      end)

    if current != [], do: turns ++ [current], else: turns
  end

  defp build_turn(events, index, tool_results) do
    {user_text, texts, reasoning_texts, tool_calls} =
      Enum.reduce(events, {nil, [], [], []}, fn event, {user, texts, reasoning, tools} ->
        if event.type != "message" do
          {user, texts, reasoning, tools}
        else
          role = get_in(event.data, ["message", "role"])
          content = get_in(event.data, ["message", "content"]) || []

          case role do
            "user" ->
              text =
                content
                |> Enum.flat_map(fn
                  %{"type" => "text", "text" => t} when is_binary(t) -> [t]
                  _ -> []
                end)
                |> Enum.join("\n")

              {if(String.trim(text) != "", do: text, else: user), texts, reasoning, tools}

            "assistant" ->
              Enum.reduce(content, {user, texts, reasoning, tools}, fn block,
                                                                       {u, t, r, tc} ->
                case block do
                  %{"type" => "thinking", "thinking" => thinking}
                  when is_binary(thinking) and thinking != "" ->
                    {u, t, r ++ [thinking], tc}

                  %{"type" => "text", "text" => text}
                  when is_binary(text) and text != "" ->
                    {u, t ++ [text], r, tc}

                  %{"type" => "toolCall", "name" => name, "id" => id} = call ->
                    args = Helpers.parse_arguments(call["arguments"] || %{})
                    result_data = Map.get(tool_results, id)

                    tool_call =
                      Helpers.build_tool_call(
                        name,
                        args,
                        id: id,
                        result: result_data && result_data["result"],
                        success?: result_data && result_data["success"]
                      )

                    {u, t, r, tc ++ [tool_call]}

                  _ ->
                    {u, t, r, tc}
                end
              end)

            _ ->
              {user, texts, reasoning, tools}
          end
        end
      end)

    %Turn{
      index: index,
      user_content: user_text,
      reasoning: if(reasoning_texts != [], do: Enum.join(reasoning_texts, "\n\n")),
      assistant_content: if(texts != [], do: Enum.join(texts, "\n\n")),
      tool_calls: tool_calls
    }
  end
end
