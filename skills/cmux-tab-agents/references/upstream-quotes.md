# Upstream quotes

Verbatim text from `superpowers:subagent-driven-development` and related upstream skills, referenced in SKILL.md.

## Why subagents

> You delegate tasks to specialized agents with isolated context. By precisely crafting their instructions and context, you ensure they stay focused and succeed at their task. They should never inherit your session's context or history — you construct exactly what they need. This also preserves your own context for coordination work.
>
> **Core principle:** Fresh subagent per task + two-stage review (spec then quality) = high quality, fast iteration.

**Source:** `superpowers:subagent-driven-development` v5.0.7

## Status handling

Implementer tab-agents report one of four statuses in their result file. Handle each:

- **`DONE`** — Proceed to spec compliance review.
- **`DONE_WITH_CONCERNS`** — The implementer completed the work but flagged doubts. Read the concerns before proceeding. If the concerns are about correctness or scope, address them before review. If they're observations (e.g., "this file is getting large"), note them and proceed to review.
- **`NEEDS_CONTEXT`** — The implementer needs information that wasn't provided. Provide the missing context and re-dispatch.
- **`BLOCKED`** — The implementer cannot complete the task. Assess the blocker:
  1. If it's a context problem, provide more context and re-dispatch with the same model.
  2. If the task requires more reasoning, re-dispatch with a more capable model.
  3. If the task is too large, break it into smaller pieces.
  4. If the plan itself is wrong, escalate to the human.

**Never** ignore an escalation or force the same model to retry without changes. If the implementer said it's stuck, something needs to change.

**Source:** `superpowers:subagent-driven-development` v5.0.7
