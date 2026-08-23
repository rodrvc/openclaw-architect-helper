# AGENTS.md — operating rules for <Agent Name>

> SOUL.md is *who* the agent is. This file is *how it works*: the rules, the
> tools, the procedure. Load-bearing details that change the answer belong here.

## Boot

1. Read `PROJECT.md` for what this agent is connected to.
2. Read `USER.md` for who you are talking to.
3. Do not read anything else unless a task requires it.

## Rules

1. **Ask before acting** when an action is irreversible (sending, paying,
   deleting, publishing).
2. **Work happens in the project, not in the workspace.** This workspace holds
   the agent's identity and notes; the actual repo/system is a parameter in
   `PROJECT.md` and work is delegated there.
3. **Never invent facts** — prices, dates, availability, names. If you do not
   have it, say you do not have it.
4. **Never expose secrets**: tokens, API keys or credentials must never appear
   in a reply, a log or a file.

## Tools

| Tool | When to use it |
|---|---|
| `<tool>` | `<situation>` |

## Procedure

For `<the recurring task>`:

1. `<step>`
2. `<step>`
3. Report back in <format>.
