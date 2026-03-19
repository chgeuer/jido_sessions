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

  test "classifies shell commands" do
    turns = [
      %Turn{
        index: 0,
        user_content: "Run tests",
        tool_calls: [
          %ToolCall{
            tool: :shell,
            arguments: %Tools.Shell.Args{command: "mix test test/auth_test.exs"},
            result: %Tools.Shell.Result{output: "1 test, 0 failures"},
            success?: true
          },
          %ToolCall{
            tool: :shell,
            arguments: %Tools.Shell.Args{command: "git commit -m \"Fix auth\""},
            result: %Tools.Shell.Result{output: "[main abc1234]"},
            success?: true
          }
        ]
      }
    ]

    extracted = Extractor.extract(turns)
    commands = extracted.commands
    assert Enum.any?(commands, &(&1.command_class == "test_run"))
    assert Enum.any?(commands, &(&1.command_class == "git_commit"))
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

  test "extracts operations with kind and confidence" do
    turns = [
      %Turn{
        index: 0,
        user_content: "Search and edit",
        tool_calls: [
          %ToolCall{
            tool: :search_content,
            arguments: %Tools.Search.ContentArgs{pattern: "defmodule Auth", path: "lib/"},
            result: %Tools.Search.ContentResult{matches: "lib/auth.ex:1"},
            success?: true
          },
          %ToolCall{
            tool: :file_create,
            arguments: %Tools.File.CreateArgs{path: "lib/new.ex", content: "defmodule New do\nend"},
            success?: true
          }
        ]
      }
    ]

    extracted = Extractor.extract(turns)
    search_ops = Enum.filter(extracted.operations, &(&1.kind == :search))
    write_ops = Enum.filter(extracted.operations, &(&1.kind == :file_write))

    assert length(search_ops) == 1
    assert hd(search_ops).confidence == :structured
    assert length(write_ops) == 1
    assert hd(write_ops).action == "created"
    assert hd(write_ops).path == "lib/new.ex"
  end

  test "infers file operations from shell commands" do
    turns = [
      %Turn{
        index: 0,
        user_content: "Copy file",
        tool_calls: [
          %ToolCall{
            tool: :shell,
            arguments: %Tools.Shell.Args{command: "cat lib/auth.ex > /tmp/backup.ex"},
            success?: true
          }
        ]
      }
    ]

    extracted = Extractor.extract(turns)
    inferred_reads = Enum.filter(extracted.operations, &(&1.kind == :file_read && &1.confidence == :inferred))
    inferred_writes = Enum.filter(extracted.operations, &(&1.kind == :file_write && &1.confidence == :inferred))

    assert Enum.any?(inferred_reads, &(&1.path == "lib/auth.ex"))
    assert Enum.any?(inferred_writes, &(&1.path == "/tmp/backup.ex"))
  end

  test "extracts prompts and assistant outputs" do
    turns = [
      %Turn{
        index: 0,
        user_content: "Fix the bug",
        assistant_content: "I'll look into it",
        tool_calls: []
      },
      %Turn{
        index: 1,
        user_content: "Run the tests",
        assistant_content: "All tests pass",
        tool_calls: []
      }
    ]

    extracted = Extractor.extract(turns)
    assert length(extracted.prompts) == 2
    assert hd(extracted.prompts).text == "Fix the bug"
    assert length(extracted.assistant_outputs) == 2
    assert hd(extracted.assistant_outputs).text == "I'll look into it"
  end
end
