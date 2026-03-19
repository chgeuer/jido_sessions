# Agent Tool Capability Matrix

Cross-agent comparison of tool capabilities based on SDK source code inspection
(March 2026). Sources: jido_ghcopilot, claude_agent_sdk, codex_sdk, gemini_cli_sdk,
jido_pi SDKs.

## Data sources

| Agent | Source of truth | Sessions in DB | Events in DB |
|-------|----------------|----------------|--------------|
| Copilot | `jido_ghcopilot` SDK, direct tool definitions | 3634 | 1,011,011 |
| Claude | `claude_agent_sdk`, `ClaudeAgentSDK.Tool` macro | 611 | 42,171 |
| Codex | `codex_sdk`, `Codex.Tools.*` modules | 40 | 36,096 |
| Gemini | `gemini_cli_sdk` (thin wrapper — tools defined in Google's binary) | 39 | 384 |
| Pi | `jido_pi` (runs via Copilot CLI, inherits its tools) | 11 | 1,865 |

## Tool name mapping

Each agent uses different names for equivalent operations. The "Canonical" column
is what `jido_sessions` normalizes to.

### Shell execution

| Canonical | Copilot | Claude | Codex | Gemini | Pi |
|-----------|---------|--------|-------|--------|-----|
| `shell` | `bash` | `Bash` | `shell_command` | `run_shell_command` | `bash` |
| `shell_read` | `read_bash` | `BashOutput` | — | — | `read_bash` |
| `shell_write` | `write_bash` | — | `write_stdin` | — | `write_bash` |
| `shell_stop` | `stop_bash` | `KillShell` | — | — | `stop_bash` |
| `shell_list` | `list_bash` | — | — | — | `list_bash` |

### File operations

| Canonical | Copilot | Claude | Codex | Gemini | Pi |
|-----------|---------|--------|-------|--------|-----|
| `file_read` | `view`, `show_file` | `Read` | *(via shell `cat`)* | `read_file` | `read`, `view` |
| `file_create` | `create` | `Write` | *(via `apply_patch`)* | `write_file` | `write`, `create` |
| `file_edit` | `edit` | `Edit`, `MultiEdit` | *(via `apply_patch`)* | `replace` | `edit`, `multiedit` |
| `file_patch` | `apply_patch` | `ApplyPatch` | `apply_patch` | — | `apply_patch` |

Note: Codex uses `apply_patch` for all file mutations (create, edit, delete) and
reads files via `shell_command` (`cat`). It has no separate file read tool.

### Search

| Canonical | Copilot | Claude | Codex | Gemini | Pi |
|-----------|---------|--------|-------|--------|-----|
| `search_content` | `grep`, `rg` | `Grep` | `file_search` | `search_file_content` | `grep`, `rg` |
| `search_files` | `glob` | `Glob` | `file_search` | `list_directory`, `glob` | `glob`, `ls` |

Note: Codex's `file_search` combines both content and file pattern search into one
tool with `pattern` (glob) and `content` (regex) parameters.

### User interaction

| Canonical | Copilot | Claude | Codex | Gemini | Pi |
|-----------|---------|--------|-------|--------|-----|
| `ask_user` | `ask_user` | `AskUserQuestion` | `request_user_input` | ❌ | `ask_user` |

Gemini CLI does not expose a native ask_user tool. All other agents support
interactive user prompting with question + optional choices.

### Thinking / reasoning

| Canonical | Copilot | Claude | Codex | Gemini | Pi |
|-----------|---------|--------|-------|--------|-----|
| `reasoning` | `reasoningText` field on `assistant.message` | `thinking` content block | `reasoning` payload type | `thoughts` array on response | `thinking` content block |

Not a tool call — this is a content block type within assistant responses.

### Sub-agents / tasks

| Canonical | Copilot | Claude | Codex | Gemini | Pi |
|-----------|---------|--------|-------|--------|-----|
| `task_create` | `task` | `Task`, `TaskCreate` | — | — | `task` |
| `task_read` | `read_agent` | `TaskOutput` | — | — | `read_agent` |
| `task_list` | `list_agents` | `TaskList` | — | — | `list_agents` |

### Web

| Canonical | Copilot | Claude | Codex | Gemini | Pi |
|-----------|---------|--------|-------|--------|-----|
| `web_search` | `web_search` | `WebSearch` | `web_search` | `google_web_search` | `web_search` |
| `web_fetch` | `web_fetch` | `WebFetch` | — | — | `web_fetch` |

### Planning & metadata

| Canonical | Copilot | Claude | Codex | Gemini | Pi |
|-----------|---------|--------|-------|--------|-----|
| `intent` | `report_intent` | `ReportIntent` | `update_plan` | — | `report_intent` |
| `todo_update` | `update_todo` | `TodoWrite`, `UpdateTodo` | — | `write_todos` | `update_todo` |
| `sql` | `sql` | `Sql` | — | — | `sql` |
| `memory` | `store_memory` | — | — | — | `store_memory` |
| `skill` | `skill` | `Skill` | — | — | `skill` |

### External integrations

| Canonical | Copilot | Claude | Codex | Gemini | Pi |
|-----------|---------|--------|-------|--------|-----|
| `github_api` | `github-mcp-server-*` | — | — | — | `github-mcp-server-*` |
| `image_view` | — | — | `view_image` | — | — |

## Conversation event types

Beyond tool calls, each agent has these conversation-level event types:

| Concept | Copilot | Claude | Codex | Gemini | Pi |
|---------|---------|--------|-------|--------|-----|
| User message | `user.message` | `user` (role) | `turn_context` / `response_item` (role=user) | `user` (type) | `message` (role=user) |
| Assistant text | `assistant.message` | `assistant` (role, text block) | `response_item` (role=assistant, output_text) | `gemini` (content field) | `message` (role=assistant, text block) |
| Turn start | `assistant.turn_start` | *(implicit)* | *(implicit)* | *(implicit)* | *(implicit)* |
| Turn end | `assistant.turn_end` | *(implicit)* | *(implicit)* | *(implicit)* | *(implicit)* |
| Usage/tokens | `assistant.usage` | *(not in events)* | `event_msg` (token_count) | `tokens` field on response | *(not in events)* |
| Abort | `abort` | *(not observed)* | *(not observed)* | *(not observed)* | *(not observed)* |
| Error | `session.error` | *(not observed)* | *(not observed)* | `error` (type) | *(not observed)* |

## Session lifecycle events

These are internal bookkeeping, not rendered in the conversation view:

| Event | Copilot | Claude | Codex | Gemini | Pi |
|-------|---------|--------|-------|--------|-----|
| Session start | `session.start` | *(implicit)* | `session_meta` | `session_meta` | `session` |
| Session stop | `session.shutdown` | *(implicit)* | *(implicit)* | *(implicit)* | *(implicit)* |
| Model change | `session.model_change` | *(not observed)* | *(not observed)* | *(not observed)* | `model_change` |
| Compaction | `session.compaction_start/complete` | *(not applicable)* | `compacted` | *(not observed)* | *(not observed)* |
| Context truncation | `session.truncation` | *(not observed)* | *(not observed)* | *(not observed)* | *(not observed)* |

## Agent architecture notes

### Copilot (GitHub Copilot CLI)
- Most mature event stream — explicit typed events for everything
- Tool calls split into `tool.execution_start` + `tool.execution_complete` pairs
- Has `hook.start`/`hook.end` for lifecycle hooks
- Supports `subagent.started`/`subagent.completed`/`subagent.failed`
- `reasoningText` is a field on `assistant.message`, not a separate event

### Claude (Claude Code CLI)
- Events are `assistant` / `user` with nested `content` blocks
- Tool calls are `tool_use` content blocks with results as `tool_result` user messages
- Thinking is a `thinking` content block type alongside `text` and `tool_use`
- File snapshots stored as `file-history-snapshot` events
- Has `progress` events for streaming tool output

### Codex (OpenAI Codex CLI)
- All content in `response_item` events with nested `payload`
- Payload has `role` (user/assistant) and `type` (message/function_call/reasoning)
- Tool calls and results are separate `function_call` / `function_call_output` payloads
- User input via `request_user_input` protocol (not a standard tool call)
- File ops exclusively through `apply_patch` (unified patch format)

### Gemini (Google Gemini CLI)
- SDK is a thin wrapper around the `gemini` binary
- Tool definitions live in Google's binary, not in the SDK source
- Events have `thoughts` array for reasoning, `toolCalls` array for tools
- Tool results embedded in `functionResponse` nested structure
- Fewest sessions in DB (39), smallest event count (384)

### Pi (Custom agent via Copilot CLI)
- Runs through the Copilot CLI infrastructure, inherits its tool set
- Events are `message` type with role-based dispatch (user/assistant/toolResult)
- Content blocks use Claude-style format: `thinking`, `text`, `toolCall`
- Has `model_change` and `thinking_level_change` lifecycle events
- Fewest sessions (11) but architecture is well understood from source
