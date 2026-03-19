# Raw Event Formats by Agent

Reference documentation showing the actual wire format of events as stored in the
database, before normalization. Useful for writing and debugging agent parsers.

## Copilot

Events are stored as individual records with explicit `event_type` strings.
Tool calls are split into start/complete pairs.

### assistant.message
```json
{
  "content": "Here's the fix for the auth bug...",
  "messageId": "msg-abc123",
  "reasoningText": "I need to look at verify_token/1...",
  "reasoningOpaque": "<base64-encrypted>",
  "outputTokens": 559,
  "toolRequests": [
    {
      "name": "bash",
      "toolCallId": "call-xyz",
      "type": "function",
      "arguments": {"command": "mix test", "description": "Run tests"},
      "intentionSummary": "Run tests"
    }
  ]
}
```

### tool.execution_start
```json
{
  "toolCallId": "call-xyz",
  "toolName": "bash",
  "arguments": {"command": "mix test", "description": "Run tests"}
}
```

### tool.execution_complete
```json
{
  "toolCallId": "call-xyz",
  "toolName": "bash",
  "success": true,
  "result": "3 tests, 0 failures",
  "error": null
}
```

### user.message
```json
{
  "content": "Fix the login bug",
  "attachments": [{"path": "lib/auth.ex", "content": "..."}]
}
```

### assistant.usage
```json
{
  "model": "claude-sonnet-4",
  "inputTokens": 15000,
  "outputTokens": 3200,
  "cacheReadTokens": 12000,
  "cacheWriteTokens": 0,
  "cost": 0.042,
  "duration": 8500,
  "initiator": "user",
  "apiCallId": "api-123"
}
```

## Claude

Events are `assistant` or `user` type with nested `message.content` arrays.
Tool calls are inline `tool_use` blocks; results are `tool_result` user messages.

### assistant (with tool use + thinking)
```json
{
  "message": {
    "content": [
      {"type": "thinking", "thinking": "I should check the auth module..."},
      {"type": "text", "text": "Let me look at the code."},
      {
        "type": "tool_use",
        "id": "toolu_abc",
        "name": "Bash",
        "input": {"command": "cat lib/auth.ex"}
      }
    ]
  },
  "type": "assistant",
  "uuid": "evt-123"
}
```

### user (tool result)
```json
{
  "message": {
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_abc",
        "content": "defmodule Auth do\n  def verify_token(token)...",
        "is_error": false
      }
    ]
  },
  "type": "user",
  "toolUseResult": {"is_error": false}
}
```

### user (regular message)
```json
{
  "message": {
    "content": "Fix the login bug"
  },
  "type": "user"
}
```

## Codex

All content in `response_item` events with a nested `payload` object.
Payload type discriminates between messages, tool calls, and results.

### response_item (assistant message)
```json
{
  "payload": {
    "role": "assistant",
    "type": "message",
    "content": [
      {"type": "output_text", "text": "I'll fix the auth bug."}
    ]
  },
  "type": "response.output_item.done",
  "timestamp": "2026-03-15T10:00:00Z"
}
```

### response_item (function call)
```json
{
  "payload": {
    "type": "function_call",
    "name": "shell_command",
    "call_id": "call_abc",
    "arguments": "{\"command\":[\"cat\",\"lib/auth.ex\"]}"
  },
  "type": "response.output_item.done"
}
```

### response_item (function result)
```json
{
  "payload": {
    "type": "function_call_output",
    "call_id": "call_abc",
    "output": "defmodule Auth do..."
  },
  "type": "response.output_item.done"
}
```

### response_item (reasoning)
```json
{
  "payload": {
    "type": "reasoning",
    "text": "Let me check the verify_token function..."
  },
  "type": "response.output_item.done"
}
```

## Gemini

Events are `gemini` or `user` type. Thinking in `thoughts` array, tool calls
in `toolCalls` array. Tool results embedded in nested `functionResponse` structure.

### gemini (with thinking + tool calls)
```json
{
  "type": "assistant",
  "content": "Here's what I found...",
  "thoughts": [
    {"subject": "Analysis", "description": "Need to check the auth module"}
  ],
  "toolCalls": [
    {
      "name": "run_shell_command",
      "id": "call-gem-1",
      "args": {"command": "cat lib/auth.ex"},
      "status": "ok",
      "output": "defmodule Auth do...",
      "result": [
        {
          "functionResponse": {
            "response": {"output": "defmodule Auth do..."}
          }
        }
      ]
    }
  ],
  "tokens": {"input": 5000, "output": 1200},
  "model": "gemini-2.5-pro"
}
```

### user
```json
{
  "type": "user",
  "content": "Fix the login bug"
}
```

## Pi

Events are `message` type with role-based dispatch. Uses Claude-style content
blocks (thinking, text, toolCall).

### message (assistant with thinking + tool call)
```json
{
  "message": {
    "role": "assistant",
    "content": [
      {"type": "thinking", "thinking": "I need to check the auth module..."},
      {"type": "text", "text": "Let me look at the code."},
      {
        "type": "toolCall",
        "id": "call-pi-1",
        "name": "bash",
        "arguments": {"command": "cat lib/auth.ex", "description": "Read auth module"}
      }
    ]
  },
  "type": "message",
  "id": "msg-1"
}
```

### message (tool result)
```json
{
  "message": {
    "role": "toolResult",
    "toolCallId": "call-pi-1",
    "toolName": "bash",
    "isError": false,
    "content": [
      {"type": "text", "text": "defmodule Auth do..."}
    ]
  },
  "type": "message"
}
```

### message (user)
```json
{
  "message": {
    "role": "user",
    "content": [
      {"type": "text", "text": "Fix the login bug"}
    ]
  },
  "type": "message"
}
```

## Summary: format differences

| Aspect | Copilot | Claude | Codex | Gemini | Pi |
|--------|---------|--------|-------|--------|-----|
| Event granularity | One event per action | One event per message (blocks inside) | One event per payload | One event per response | One event per message (blocks inside) |
| Tool call format | Separate start/complete events | Inline `tool_use` block | `function_call` payload | `toolCalls` array | Inline `toolCall` block |
| Tool result format | Separate `tool.execution_complete` | `tool_result` user message | `function_call_output` payload | Nested `functionResponse` | `toolResult` role message |
| Thinking format | Field on assistant.message | `thinking` content block | `reasoning` payload | `thoughts` array | `thinking` content block |
| Arguments format | Parsed map | Parsed map (`input`) | JSON string (needs decode) | Parsed map (`args`) | Parsed map |
