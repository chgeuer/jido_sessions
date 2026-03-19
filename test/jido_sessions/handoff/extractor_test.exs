defmodule JidoSessions.Handoff.ExtractorTest do
  use ExUnit.Case, async: true

  alias JidoSessions.{Turn, ToolCall}
  alias JidoSessions.Tools
  alias JidoSessions.Handoff.Extractor

  test "extracts files read and written" do
    turns = [
      %Turn{
        index: 0,
        user_content: "Fix the bug",
        tool_calls: [
          %ToolCall{
            tool: :file_read,
            arguments: %Tools.File.ReadArgs{path: "lib/auth.ex"},
            result: %Tools.File.ReadResult{content: "code"},
            success?: true
          },
          %ToolCall{
            tool: :file_edit,
            arguments: %Tools.File.EditArgs{path: "lib/auth.ex", old_text: "a", new_text: "b"},
            result: %Tools.File.WriteResult{},
            success?: true
          }
        ]
      }
    ]

    extracted = Extractor.extract(turns)
    assert "lib/auth.ex" in extracted.files_read
    assert "lib/auth.ex" in extracted.files_written
  end

  test "extracts shell commands" do
    turns = [
      %Turn{
        index: 0,
        user_content: "Run tests",
        tool_calls: [
          %ToolCall{
            tool: :shell,
            arguments: %Tools.Shell.Args{command: "mix test"},
            result: %Tools.Shell.Result{output: "3 tests, 0 failures", exit_status: 0},
            success?: true
          }
        ]
      }
    ]

    extracted = Extractor.extract(turns)
    assert length(extracted.commands) == 1
    assert hd(extracted.commands).command == "mix test"
  end

  test "tracks last user goal" do
    turns = [
      %Turn{index: 0, user_content: "First request", tool_calls: []},
      %Turn{index: 1, user_content: "Second request", tool_calls: []}
    ]

    extracted = Extractor.extract(turns)
    assert extracted.last_user_goal == "Second request"
  end

  test "counts incomplete tools" do
    turns = [
      %Turn{
        index: 0,
        user_content: "Do stuff",
        tool_calls: [
          %ToolCall{tool: :shell, arguments: %Tools.Shell.Args{command: "ls"}, success?: true},
          %ToolCall{tool: :shell, arguments: %Tools.Shell.Args{command: "cat"}, success?: nil}
        ]
      }
    ]

    extracted = Extractor.extract(turns)
    assert extracted.incomplete_tools == 1
  end
end
