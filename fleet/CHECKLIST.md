# Manual steps after `bootstrap.sh`

A fleet export carries **configuration**, never **credentials**. The steps below
are the ones no script can do for you: each opens a browser, a QR code or a TTY.
Until they are done the instance is configured but not yet working.

## 1. Turn the old gateway off FIRST

> **A WhatsApp number can only be linked to one instance at a time.**
> Logging in from the new machine kicks the old one off — and if the old gateway
> is still running, the two will fight over the session and both end up flapping.

```bash
openclaw daemon stop      # on the OLD machine, before step 4
```

## 2. Model providers

Codex / OpenAI (OAuth, opens a browser):

```bash
openclaw models auth login --provider openai
```

Google / Gemini (paste an API key):

```bash
openclaw models auth paste-api-key --provider google
```

Check what ended up registered:

```bash
openclaw models auth list
```

## 3. Claude Code (only if an agent uses the ACP backend)

```bash
claude auth login       # separate from OpenClaw's own auth
```

The fleet's `acp.allowedAgents` lists which agents need this.

## 4. WhatsApp (QR pairing)

```bash
openclaw channels login --channel whatsapp
```

Scan the QR with the phone that owns the number. Then confirm:

```bash
openclaw channels status        # expect: whatsapp connected
```

## 5. Start the gateway and verify

```bash
openclaw gateway run            # or: openclaw daemon start
fleet/verify.sh --fleet <fleet-dir>
```

`verify.sh` should report OK on every row. Anything marked DIFF means the
instance and the fleet disagree — fix it before trusting the migration.

## 6. Things that intentionally do NOT travel

| Not exported | Why | What to do |
|---|---|---|
| OAuth tokens / API keys | secrets never go in a repo | steps 2–3 |
| WhatsApp session | tied to one device pairing | step 4 |
| `memory/` | personal notes, opt-in only | re-run export with `--with-memory` |
| `media/`, `outputs/` | large, regenerable | nothing |
| Conversation history | not configuration | nothing |
| Docker images | environment, not config | `docker pull` for sandboxed agents |
