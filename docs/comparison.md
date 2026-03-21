# Coding Agent Harness Comparison

> Analysis of data fidelity across Copilot, Claude, Codex, and Gemini — both from
> live runtime streaming (via jido_harness adapters) and from post-hoc session
> file parsing (via jido_sessions).

## Overview

Each coding agent (GitHub Copilot, Anthropic Claude Code, OpenAI Codex, Google Gemini CLI)
exposes a different level of detail through its streaming API and its on-disk session files.
This document catalogs what data is available from each source and where gaps exist.

The **Copilot (copilot_local)** adapter serves as the gold standard — it streams events
natively in a rich format that includes every aspect of the agent's operation. The
harness adapters for Claude, Codex, and Gemini normalize their provider-specific events
into the same vocabulary.

---

## Canonical Event Vocabulary

The rendering pipeline expects events in "copilot format" — string-typed event names
with standardized data payloads:

| Event Type | Purpose | Key Data Fields |
|---|---|---|
| `user.message` | User prompt | `content` |
| `assistant.turn_start` | Turn boundary (start) | `turnId` |
| `assistant.reasoning` | Thinking/reasoning block | `content` (accumulated text) |
| `assistant.message` | Assistant text output | `content`, `chunkContent`, `reasoningText`, `toolRequests` |
| `tool.execution_start` | Tool invocation | `toolName`, `arguments`, `toolCallId` |
| `tool.execution_complete` | Tool result | `toolCallId`, `result`, `success`, `error` |
| `assistant.usage` | Token accounting | `inputTokens`, `outputTokens`, `model`, `cost`, `duration` |
| `assistant.turn_end` | Turn boundary (end) | `turnId` |
| `session.idle` | Session completed | — |
| `session.error` | Session failed | `message` |

---

## Runtime Streaming Comparison

### What each adapter emits during a live run

| Event | Copilot | Claude | Codex | Gemini |
|---|---|---|---|---|
| **User prompt** | ✅ Native `user.message` | ✅ Injected by HarnessBridge | ✅ Injected by HarnessBridge | ✅ `:user_message` from SDK |
| **Turn start** | ✅ Native `assistant.turn_start` | ❌ Not emitted | ✅ `:codex_turn_started` | ❌ Single-turn CLI |
| **Reasoning/thinking** | ✅ Native `assistant.reasoning` | ✅ `:thinking_delta` from partial messages | ✅ `:thinking_delta` from `ReasoningDelta` / `ItemCompleted{Reasoning}` (app-server transport only) | ❌ CLI SDK doesn't expose |
| **Assistant text** | ✅ Native `assistant.message` with `chunkContent` for streaming | ✅ `:output_text_delta` / `:output_text_final` | ✅ `:output_text_delta` / `:output_text_final` + `ItemCompleted{AgentMessage}` | ✅ `:output_text_delta` / `:output_text_final` |
| **Tool call start** | ✅ Native with `toolName`, `arguments`, `toolCallId` | ✅ `:tool_call` from `tool_use` content blocks | ✅ `:tool_call` from `ToolCallRequested` (app-server) or `ItemCompleted{CommandExecution}` (exec) | ✅ `:tool_call` from `ToolUseEvent` |
| **Tool call result** | ✅ Native with `result.content`, `toolCallId` | ✅ `:tool_result` from `:user` message `tool_result` blocks | ✅ `:tool_result` from `ToolCallCompleted` (app-server) or `ItemCompleted{CommandExecution}` (exec) | ✅ `:tool_result` from `ToolResultEvent` |
| **Usage/tokens** | ✅ Native `assistant.usage` with `inputTokens`, `outputTokens`, `model`, `cost`, `duration` | ✅ `:usage` from `message_start` (input_tokens), `message_delta` (output_tokens), Result (cost) | ✅ `:usage` from `TurnCompleted.usage` (exec) or `ThreadTokenUsageUpdated` (app-server) | ✅ `:usage` from `ResultEvent.stats` |
| **Turn end** | ✅ Native `assistant.turn_end` | ✅ `:turn_end` from `message_stop` stream event | ❌ `TurnCompleted` maps to session end | ❌ Single-turn CLI |
| **Session end** | ✅ Native `session.idle` | ✅ `:session_completed` | ✅ `:session_completed` from `TurnCompleted` | ✅ `:session_completed` / `:session_failed` from `ResultEvent` |

### Tool name vocabulary

Each provider uses different names for equivalent operations. The `Jido.ToolRenderers`
registry canonicalizes them for rendering:

| Operation | Copilot | Claude Code | Codex | Gemini CLI |
|---|---|---|---|---|
| Run shell command | `bash` | `Bash` | `exec_command` (exec) / tool name (app-server) | `run_shell_command` |
| Read file | `view` | `Read` | — (uses shell) | `read_file` |
| Write file | `create` | `Write` | — (uses shell + patches) | `write_file` |
| Edit file | `edit` | `Edit` | — (uses `file_patch`) | `edit_file` |
| Search content | `grep` | `Grep` | — (uses shell) | `grep_search` |
| Search files | `glob` | `Glob` | — (uses shell) | `list_directory` |
| Report intent | `report_intent` | — | — | — |
| SQL query | `sql` | — | — | — |
| Web search | — | — | — | `web_search` |

---

## Session File Comparison

### Storage locations

| Provider | Session Directory | Format |
|---|---|---|
| **Copilot** | `~/.copilot/session-state/<uuid>/events.jsonl` | JSONL with native copilot events |
| **Claude** | `~/.claude-<email>/projects/<project-hash>/<uuid>.jsonl` | JSONL with Anthropic API messages |
| **Codex** | `~/.codex/sessions/<year>/<month>/<day>/rollout-<timestamp>-<uuid>.jsonl` | JSONL with `response_item` and `event_msg` records |
| **Gemini** | `~/.gemini/tmp/<uuid>.jsonl` | JSONL with Gemini API messages |

### What jido_sessions extracts from session files

The `JidoSessions.Parsers.*` modules parse session files into canonical `Turn` structs.
Each Turn contains:

| Field | Copilot | Claude | Codex | Gemini |
|---|---|---|---|---|
| **User content** | ❌ Not in session file parser | ✅ From `user` messages | ✅ From `response_item{role: "user"}` | ✅ From user entries |
| **Reasoning/thinking** | ❌ Not extracted by Turn parser (present in raw events as `assistant.reasoning`) | ✅ From `thinking` content blocks | ❌ Empty in exec JSONL (`response_item{type: "reasoning"}` has `text: nil`) | ✅ From `thoughts` entries |
| **Assistant text** | ✅ From `assistant.message` content | ✅ From `text` content blocks | ✅ From `response_item{role: "assistant", type: "message"}` | ✅ From `content` field |
| **Tool calls** | ✅ From `tool.execution_start` + `tool.execution_complete` | ✅ From `tool_use` + `tool_result` content blocks | ✅ From `response_item{type: "function_call"}` + `function_call_output` | ✅ From `toolCalls` entries |
| **Tool results** | ✅ Matched by `toolCallId` | ✅ Matched by `tool_use_id` | ✅ Matched by `call_id` | ✅ Inline in `toolCalls` |
| **Usage/tokens** | ❌ Not extracted by Turn parser (present in raw events as `assistant.usage`) | ❌ Not in session file | ❌ Available in `event_msg{type: "token_count"}` but not parsed | ✅ From `usage` entries: `{model, input_tokens, output_tokens}` |

---

## Transport Differences

### Codex: Exec vs App-Server

Codex has two transport modes that produce fundamentally different event streams:

| Aspect | Exec Transport | App-Server Transport |
|---|---|---|
| **How it runs** | `codex exec --json` CLI subprocess | WebSocket to Codex App Server |
| **Event granularity** | `item.started` / `item.completed` with full items | Individual `ToolCallRequested`, `ToolCallCompleted`, `ReasoningDelta` events |
| **Reasoning** | `ItemCompleted{Reasoning}` but often empty text in exec JSONL | `ReasoningDelta` with incremental text |
| **Tool calls** | `ItemCompleted{CommandExecution}` with command + aggregated_output + exit_code | `ToolCallRequested` with name + arguments, then `ToolCallCompleted` with output |
| **Usage** | `TurnCompleted.usage` at end of turn | `ThreadTokenUsageUpdated` with live deltas |
| **Streaming** | Coarse (items appear when complete) | Fine-grained (character-by-character deltas) |

### Claude: Partial Messages

With `include_partial_messages: true`, Claude sends back partial `:assistant` messages
as thinking and tool_use blocks accumulate. This means:

- Thinking arrives as many small fragments in successive partial messages
- Tool_use blocks appear in partial messages before tool execution
- Tool results come back in `:user` messages with `tool_result` content blocks
- `message_start` / `message_delta` / `message_stop` SSE events carry usage data and turn boundaries

### Gemini: Single-Turn CLI

The Gemini CLI (`gemini`) operates in single-turn mode per invocation. There are no
turn boundaries because each CLI call is one complete turn. Multi-turn requires session
resume via the jido_gemini adapter.

---

## Gap Summary and Mitigation

### Gaps that are fixed in the adapter layer

These were addressed by changes to `jido_claude`, `jido_codex`, `jido_gemini` mappers
and the `HarnessEventNormalizer`:

- Claude: Missing `tool.execution_complete` → Fixed by processing `:user` message `tool_result` blocks
- Claude: Missing usage data → Fixed by extracting from `message_start`/`message_delta`/`Result`
- Claude: Missing turn boundaries → Fixed by mapping `message_stop` to `:turn_end`
- Codex: Missing tool events (exec transport) → Fixed by handling `ItemCompleted{CommandExecution}`
- Codex: Missing usage → Fixed by extracting from `TurnCompleted.usage`
- Gemini: Missing usage → Fixed by extracting from `ResultEvent.stats`
- Gemini: Missing user prompt → Fixed by emitting `:user_message` from `MessageEvent{role: "user"}`
- All harness: Missing user prompt → Fixed by `HarnessBridge.emit_user_prompt` before stream

### Gaps that require post-import from session files

These cannot be fixed at the adapter level because the provider's streaming API
doesn't expose the data:

| Gap | Provider | Mitigation |
|---|---|---|
| **Reasoning text** | Codex (exec transport) | Post-import from JSONL if/when Codex exec includes reasoning text |
| **Reasoning text** | Gemini | Post-import from `~/.gemini/tmp/*.jsonl` via `JidoSessions.AgentParsers.Gemini` |
| **Fine-grained tool events** | Codex (exec transport) | Consider using app-server transport for richer streaming |
| **Copilot reasoning in Turns** | Copilot | Extend `JidoSessions.Parsers.Copilot` to extract `assistant.reasoning` events into Turn.reasoning |
| **Copilot usage in Turns** | Copilot | Extend `JidoSessions.Parsers.Copilot` to extract `assistant.usage` events into Turn.usage |

### Gaps that are provider limitations

These represent fundamental differences in what the providers expose:

| Gap | Provider | Status |
|---|---|---|
| Turn boundaries | Gemini | Single-turn CLI — not applicable |
| Turn boundaries | Codex (exec) | TurnCompleted maps to session end, not internal turn |
| Reasoning streaming | Gemini CLI | Provider does not stream thinking — only available in session files |
| Cost data | Codex, Gemini | Providers don't expose per-request cost (Copilot and Claude do) |

---

## Architecture Notes

### Event Flow: Copilot (Native)

```
copilot_lv WebSocket → SessionEvent structs → CopilotLocal adapter
  → event map with type="tool.execution_start" etc.
  → on_event callback → HeartbeatRunEvent DB storage
  → EventProcessor.process → EventStream.build_events(:copilot) → Rich renderer
```

### Event Flow: Harness Adapters (Claude, Codex, Gemini)

```
Provider SDK → Mapper (jido_claude/codex/gemini)
  → Jido.Harness.Event structs with :tool_call, :thinking_delta, etc.
  → HarnessBridge.consume_event_stream
    → HarnessEventNormalizer.normalize → copilot-format event map
    → buffer_or_emit (accumulates text/reasoning chunks)
    → on_event callback → HeartbeatRunEvent DB storage
  → EventProcessor.process
    → normalize_event (translate raw types for legacy events)
    → deduplicate/filter/accumulate
    → synthesize missing completions
    → EventStream.build_events(:copilot) → Rich renderer
```

### Post-Import Flow (jido_sessions)

```
Local session JSONL files → AgentParser.parse_session
  → parsed_session with events list
  → JidoSessions.parse_turns → [Turn] structs
  → (Future: convert Turns back to copilot-format events for re-import)
```
