# PROJECT.md — what <Agent Name> is connected to

> The bridge between the agent and the real system. The agent lives in its
> workspace; the project is a *parameter* it points at, never its home.

## The project

- **Name**: <project name>
- **Repo / path**: `<~/path/to/repo or a URL>`
- **What it is**: <one or two lines>

## How work is delegated

<How the agent triggers real work: a script, an ACP call, a queue directory.
State the exact command and who is allowed to run it.>

```bash
<command>
```

## Boundaries

- The agent may: <read-only actions it can take freely>
- The agent must ask first before: <write actions>
- The agent must never: <forbidden actions>

## Where things live

| Thing | Location |
|---|---|
| Source of truth | `<path>` |
| Logs | `<path>` |
| Output | `<path>` |
