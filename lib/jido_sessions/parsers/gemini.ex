defmodule JidoSessions.Parsers.Gemini do
  @moduledoc """
  Parses raw Gemini events into canonical `Turn` structs.

  Gemini events are `gemini`/`user` type with `thoughts` array and `toolCalls` array.
  Tool results are embedded in nested `functionResponse` structures.
  """

  alias JidoSessions.{Turn, Usage}
  alias JidoSessions.Parsers.Helpers

  @skip_types ~w[session_meta info error]

  @spec parse_turns([map()]) :: [Turn.t()]
  def parse_turns(events) do
    events
    |> Enum.reject(fn e -> e.type in @skip_types end)
    |> chunk_into_turns()
    |> Enum.with_index()
    |> Enum.map(fn {turn_events, index} ->
      build_turn(turn_events, index)
    end)
  end

  defp chunk_into_turns(events) do
    {turns, current} =
      Enum.reduce(events, {[], []}, fn event, {turns, current} ->
        if event.type == "user" && current != [] do
          {turns ++ [current], [event]}
        else
          {turns, current ++ [event]}
        end
      end)

    if current != [], do: turns ++ [current], else: turns
  end

  defp build_turn(events, index) do
    user_event = Enum.find(events, &(&1.type == "user"))
    user_content = if user_event, do: user_event.data["content"]

    assistant_events = Enum.filter(events, &(&1.type in ["assistant", "gemini"]))

    {texts, reasoning_texts, tool_calls, usage} =
      Enum.reduce(assistant_events, {[], [], [], nil}, fn event,
                                                         {texts, reasoning, tools, usage} ->
        data = event.data

        reasoning =
          case data["thoughts"] do
            thoughts when is_list(thoughts) and thoughts != [] ->
              text =
                Enum.map_join(thoughts, "\n\n", fn t ->
                  subject =
                    if is_binary(t["subject"]), do: "**#{t["subject"]}**: ", else: ""

                  "#{subject}#{t["description"] || ""}"
                end)

              reasoning ++ [text]

            _ ->
              reasoning
          end

        tools =
          case data["toolCalls"] do
            calls when is_list(calls) and calls != [] ->
              new_tools =
                Enum.map(calls, fn call ->
                  name = call["name"] || call["toolName"] || "tool"
                  args = call["args"] || call["input"] || %{}
                  call_id = call["id"]
                  output = extract_tool_output(call)

                  args = if is_map(args), do: args, else: Helpers.parse_arguments(args)

                  Helpers.build_tool_call(
                    name,
                    args,
                    id: call_id,
                    result: output,
                    success?: call["status"] != "error"
                  )
                end)

              tools ++ new_tools

            _ ->
              tools
          end

        texts =
          case data["content"] do
            text when is_binary(text) and text != "" -> texts ++ [text]
            _ -> texts
          end

        usage =
          case data["tokens"] do
            tokens when is_map(tokens) ->
              %Usage{
                model: data["model"],
                input_tokens: tokens["input"] || 0,
                output_tokens: tokens["output"] || 0
              }

            _ ->
              usage
          end

        {texts, reasoning, tools, usage}
      end)

    %Turn{
      index: index,
      started_at: user_event && user_event[:timestamp],
      user_content:
        if(is_binary(user_content) && String.trim(user_content) != "", do: user_content),
      reasoning: if(reasoning_texts != [], do: Enum.join(reasoning_texts, "\n\n")),
      assistant_content: if(texts != [], do: Enum.join(texts, "\n\n")),
      tool_calls: tool_calls,
      usage: usage
    }
  end

  defp extract_tool_output(call) do
    cond do
      is_binary(call["output"]) ->
        call["output"]

      is_list(call["result"]) ->
        call["result"]
        |> Enum.flat_map(fn
          %{"functionResponse" => %{"response" => %{"output" => output}}}
          when is_binary(output) ->
            [output]

          %{"functionResponse" => %{"response" => resp}} when is_map(resp) ->
            [Jason.encode!(resp)]

          _ ->
            []
        end)
        |> Enum.join("\n")
        |> case do
          "" -> nil
          text -> text
        end

      is_map(call["result"]) ->
        Jason.encode!(call["result"])

      true ->
        nil
    end
  end
end
