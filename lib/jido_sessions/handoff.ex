defmodule JidoSessions.Handoff do
  @moduledoc """
  Generates session handoff documents for agent-to-agent takeover.

  Reads session data from a SessionStore, extracts the conversation structure
  into prompts/operations, and renders a markdown document.
  """

  alias JidoSessions.Handoff.Extractor

  @doc """
  Generates a handoff markdown document for the given session.
  """
  @spec generate(module(), term(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate(store_mod, store, session_id) do
    with {:ok, session} <- store_mod.get_session(store, session_id) do
      events = store_mod.get_events(store, session_id)
      turns = JidoSessions.parse_turns(events, session.agent)
      artifacts = store_mod.get_artifacts(store, session_id)
      checkpoints = store_mod.get_checkpoints(store, session_id)
      todos = store_mod.get_todos(store, session_id)

      extracted = Extractor.extract(turns)

      markdown =
        render_markdown(session, turns, extracted, %{
          artifacts: artifacts,
          checkpoints: checkpoints,
          todos: todos
        })

      {:ok, markdown}
    end
  end

  @doc """
  Renders the handoff as markdown.
  """
  def render_markdown(session, turns, extracted, context) do
    [
      render_header(session),
      render_summary(session, turns, extracted),
      render_outstanding_work(context.todos),
      render_files_touched(extracted),
      render_commands_executed(extracted),
      render_transcript(turns),
      render_checkpoints(context.checkpoints),
      render_continuation_notes(extracted, context.todos)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp render_header(session) do
    """
    ---
    session_id: #{session.id}
    agent: #{session.agent}
    model: #{session.model || "unknown"}
    cwd: #{session.cwd || "unknown"}
    branch: #{session.branch || "unknown"}
    started_at: #{format_dt(session.started_at)}
    ---

    # Session Handoff: #{session.title || session.id}\
    """
    |> String.trim()
  end

  defp render_summary(session, turns, extracted) do
    tool_count = extracted.operations |> length()
    turn_count = length(turns)

    """
    ## Summary

    #{session.summary || "No summary available."}

    - **Turns**: #{turn_count}
    - **Tool calls**: #{tool_count}
    - **Files read**: #{length(extracted.files_read)}
    - **Files written**: #{length(extracted.files_written)}
    - **Commands executed**: #{length(extracted.commands)}\
    """
    |> String.trim()
  end

  defp render_outstanding_work([]), do: nil

  defp render_outstanding_work(todos) do
    pending = Enum.filter(todos, &(&1.status in [:pending, :in_progress]))

    if pending == [] do
      nil
    else
      items =
        Enum.map_join(pending, "\n", fn todo ->
          status = if todo.status == :in_progress, do: "🔄", else: "⬚"
          desc = if todo.description, do: " — #{todo.description}", else: ""
          "- #{status} **#{todo.title}**#{desc}"
        end)

      "## Outstanding Work\n\n#{items}"
    end
  end

  defp render_files_touched(extracted) do
    read = extracted.files_read |> Enum.uniq() |> Enum.sort()
    written = extracted.files_written |> Enum.uniq() |> Enum.sort()

    sections = []

    sections =
      if written != [] do
        items = Enum.map_join(written, "\n", &"- `#{&1}`")
        sections ++ ["### Files Written\n\n#{items}"]
      else
        sections
      end

    sections =
      if read != [] do
        items = Enum.map_join(Enum.take(read, 30), "\n", &"- `#{&1}`")
        suffix = if length(read) > 30, do: "\n- ... and #{length(read) - 30} more", else: ""
        sections ++ ["### Files Read\n\n#{items}#{suffix}"]
      else
        sections
      end

    if sections == [], do: nil, else: "## Files\n\n" <> Enum.join(sections, "\n\n")
  end

  defp render_commands_executed(extracted) do
    if extracted.commands == [] do
      nil
    else
      items =
        extracted.commands
        |> Enum.take(20)
        |> Enum.map_join("\n\n", fn cmd ->
          output =
            if cmd.output && String.length(cmd.output) > 200 do
              String.slice(cmd.output, 0, 200) <> "…"
            else
              cmd.output
            end

          if output do
            "```\n$ #{cmd.command}\n#{output}\n```"
          else
            "```\n$ #{cmd.command}\n```"
          end
        end)

      "## Commands Executed\n\n#{items}"
    end
  end

  defp render_transcript(turns) do
    if turns == [] do
      nil
    else
      items =
        turns
        |> Enum.map(fn turn ->
          parts = []

          parts =
            if turn.user_content do
              parts ++ ["**User**: #{truncate(turn.user_content, 500)}"]
            else
              parts
            end

          parts =
            if turn.assistant_content do
              parts ++ ["**Assistant**: #{truncate(turn.assistant_content, 500)}"]
            else
              parts
            end

          parts =
            if turn.tool_calls != [] do
              tool_summary =
                turn.tool_calls
                |> Enum.map(&"  - `#{&1.tool}` #{if &1.success?, do: "✅", else: "❌"}")
                |> Enum.join("\n")

              parts ++ ["**Tools**:\n#{tool_summary}"]
            else
              parts
            end

          Enum.join(parts, "\n\n")
        end)
        |> Enum.join("\n\n---\n\n")

      "## Transcript\n\n#{items}"
    end
  end

  defp render_checkpoints([]), do: nil

  defp render_checkpoints(checkpoints) do
    items =
      checkpoints
      |> Enum.sort_by(& &1.number)
      |> Enum.map_join("\n", fn cp ->
        "- **##{cp.number}** #{cp.title}"
      end)

    "## Checkpoints\n\n#{items}"
  end

  defp render_continuation_notes(extracted, todos) do
    pending_todos = Enum.filter(todos, &(&1.status in [:pending, :in_progress]))

    notes = []

    notes =
      if extracted.last_user_goal do
        notes ++ ["- **Last user goal**: #{truncate(extracted.last_user_goal, 200)}"]
      else
        notes
      end

    notes =
      if pending_todos != [] do
        notes ++ ["- **Open todos**: #{length(pending_todos)}"]
      else
        notes
      end

    notes =
      if extracted.incomplete_tools > 0 do
        notes ++ ["- **Incomplete tool calls**: #{extracted.incomplete_tools}"]
      else
        notes
      end

    if notes == [], do: nil, else: "## Continuation Notes\n\n" <> Enum.join(notes, "\n")
  end

  defp format_dt(nil), do: "unknown"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

  defp truncate(text, max) when byte_size(text) > max, do: String.slice(text, 0, max) <> "…"
  defp truncate(text, _max), do: text
end
