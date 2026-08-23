#!/usr/bin/env bash
# fleet/bootstrap.sh — apply a fleet directory to an OpenClaw instance.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

FLEET=""; STATE_DIR=""; CONFIG_PATH=""
SKIP_PLUGINS=0; DRY_RUN=0; CRONS_FILE=0

usage() {
  cat <<'EOF'
Usage: fleet/bootstrap.sh --fleet <fleet-dir> [options]

Applies a fleet export (see export.sh) to an OpenClaw instance: config, agent
workspaces, plugins, crons and the exec allowlist.

Options:
  --fleet <dir>        fleet directory to apply (required)
  --state-dir <dir>    target state dir   (else $OPENCLAW_STATE_DIR, else ~/.openclaw)
  --config <path>      target config file (else $OPENCLAW_CONFIG_PATH, else <state>/openclaw.json)
  --skip-plugins       do not install plugins from plugins.json
  --crons-file         write the cron store directly instead of using the CLI.
                       TEST INSTANCES ONLY: `openclaw cron add` needs a live
                       gateway, so this is the offline escape hatch.
  --dry-run            print what would happen; write no config, workspace,
                       cron or allowlist changes. (The openclaw CLI still
                       initialises its own SQLite state file when invoked.)
  -h, --help           show this help

Safety: this script refuses to touch ~/.openclaw unless you point --state-dir
at it explicitly, and it never restarts a gateway.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --fleet) FLEET="${2:?--fleet needs a directory}"; shift 2;;
    --state-dir) STATE_DIR="${2:?}"; shift 2;;
    --config) CONFIG_PATH="${2:?}"; shift 2;;
    --skip-plugins) SKIP_PLUGINS=1; shift;;
    --crons-file) CRONS_FILE=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown argument: $1 (try --help)";;
  esac
done

[ -n "$FLEET" ] || { usage >&2; die "--fleet is required"; }
FLEET="$(cd "$FLEET" 2>/dev/null && pwd)" || die "fleet dir not found"
[ -f "$FLEET/fleet.json" ] || die "not a fleet dir (no fleet.json): $FLEET"

STATE="${STATE_DIR:-$(fleet_state_dir)}"
CONFIG="${CONFIG_PATH:-${OPENCLAW_CONFIG_PATH:-$STATE/openclaw.json}}"
export OPENCLAW_STATE_DIR="$STATE" OPENCLAW_CONFIG_PATH="$CONFIG"

run() { if [ "$DRY_RUN" -eq 1 ]; then printf '   would run: %s\n' "$*"; else "$@"; fi; }

info "applying fleet"
info "  fleet : $(tildify "$FLEET")"
info "  state : $(tildify "$STATE")"
info "  config: $(tildify "$CONFIG")"
[ "$DRY_RUN" -eq 1 ] && warn "dry-run: nothing will be written"

# ---------------------------------------------------------------------------
# 1. Dependencies.
# ---------------------------------------------------------------------------
info "checking dependencies"
need_cmd openclaw; need_cmd node
ok "  openclaw $(openclaw --version 2>/dev/null | head -1)"
command -v claude >/dev/null 2>&1 && ok "  claude present" || warn "  claude not found (ACP agents that use it will fail)"

# docker is only required when some agent asks for a sandbox.
if node -e '
  const fs=require("fs");
  const f=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
  const list=(f.agents&&f.agents.list)||[];
  const d=(f.agents&&f.agents.defaults&&f.agents.defaults.sandbox&&f.agents.defaults.sandbox.mode)?1:0;
  process.exit(list.some(a=>a&&a.sandbox&&a.sandbox.mode)||d?0:1);
' "$FLEET/fleet.json"; then
  command -v docker >/dev/null 2>&1 && ok "  docker present (an agent declares sandbox.mode)" \
    || warn "  an agent declares sandbox.mode but docker is missing — that agent will not start"
else
  ok "  docker not needed (no agent declares sandbox.mode)"
fi

# ---------------------------------------------------------------------------
# 2. Plugins.
# ---------------------------------------------------------------------------
if [ "$SKIP_PLUGINS" -eq 1 ]; then
  info "skipping plugins (--skip-plugins)"
elif [ -f "$FLEET/plugins.json" ]; then
  info "installing plugins"
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    info "  $pkg"
    run openclaw plugins install "$pkg" || warn "  install failed: $pkg"
  done < <(node -e '
    const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    for(const p of j.plugins||[]) if(p.package) console.log(p.package);
  ' "$FLEET/plugins.json")
fi

# ---------------------------------------------------------------------------
# 3. Config.
# ---------------------------------------------------------------------------
# `config set --batch-file` takes a JSON array of {path,value} ops and validates
# the whole write, which beats hand-editing openclaw.json (repo rule 4).
info "applying config"
if [ ! -f "$CONFIG" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    info "  config missing — would create a minimal valid one"
  else
    info "  config missing — creating a minimal valid one"
    mkdir -p "$(dirname "$CONFIG")"
    printf '{}\n' > "$CONFIG"
  fi
fi

BATCH="$(mktemp)"; trap 'rm -f "$BATCH"' EXIT
# Each top-level section becomes one set op. "~/" is expanded back to the real
# home dir here — the fleet stores it portable, the instance needs it absolute.
node -e '
  const fs=require("fs");
  const [fleetFile,chFile,batchFile,home,targetState]=process.argv.slice(1);
  const f=JSON.parse(fs.readFileSync(fleetFile,"utf8"));
  const defaultState=home+"/.openclaw";
  // Re-root state-dir paths onto the target state dir, so a test instance never
  // ends up configured to use the production instance\u0027s workspaces.
  const reroot=(s)=>{
    if(targetState&&targetState!==defaultState&&s.startsWith(defaultState+"/"))
      return targetState+s.slice(defaultState.length);
    return s;
  };
  const retilde=(v)=>{
    if(typeof v==="string") return reroot(v.startsWith("~/")?home+v.slice(1):v);
    if(Array.isArray(v)) return v.map(retilde);
    if(v&&typeof v==="object"){const o={};for(const[k,x]of Object.entries(v))o[k]=retilde(x);return o;}
    return v;
  };
  const ops=[];
  for(const [k,v] of Object.entries(f)) ops.push({path:k,value:retilde(v)});
  // channels.json is applied per-field so we never clobber the live channel
  // credentials that live alongside these policy fields in the target config.
  if(fs.existsSync(chFile)){
    const ch=JSON.parse(fs.readFileSync(chFile,"utf8"));
    for(const [id,conf] of Object.entries(ch))
      for(const [field,val] of Object.entries(conf))
        ops.push({path:`channels.${id}.${field}`,value:retilde(val)});
  }
  fs.writeFileSync(batchFile,JSON.stringify(ops,null,2));
  console.log("  "+ops.length+" config operations");
' "$FLEET/fleet.json" "$FLEET/channels.json" "$BATCH" "$HOME" "$STATE"

if [ "$DRY_RUN" -eq 1 ]; then
  run openclaw config set --batch-file "$BATCH" --dry-run
  openclaw config set --batch-file "$BATCH" --dry-run >/dev/null 2>&1 \
    && ok "  batch validates" || warn "  batch validation reported problems"
else
  openclaw config set --batch-file "$BATCH" >/dev/null || die "config set failed"
  ok "  config written"
  openclaw config validate >/dev/null 2>&1 && ok "  config validates" || warn "  config validate reported problems"
fi

# ---------------------------------------------------------------------------
# 4. Workspaces.
# ---------------------------------------------------------------------------
info "copying workspaces"
# Workspaces are stored as absolute paths (~/.openclaw/agents/<id>/workspace).
# When the target state dir is NOT the one the fleet came from, those paths
# still point at the ORIGINAL instance — copying there would silently overwrite
# a live production workspace. So we re-root any workspace that sits under a
# state dir into the target state dir, and refuse to write outside it.
DEFAULT_STATE="$HOME/.openclaw"
if [ -d "$FLEET/agents" ]; then
  for adir in "$FLEET"/agents/*/; do
    [ -d "$adir" ] || continue
    id="$(basename "$adir")"
    ws="$(node -e '
      const fs=require("fs");
      const [cfgPath,id,home]=process.argv.slice(1);
      let cfg={};try{cfg=JSON.parse(fs.readFileSync(cfgPath,"utf8"));}catch(e){}
      const a=((cfg.agents&&cfg.agents.list)||[]).find(x=>x.id===id)||{};
      let w=a.workspace||(cfg.agents&&cfg.agents.defaults&&cfg.agents.defaults.workspace)||"";
      if(w.startsWith("~/")) w=home+w.slice(1);
      process.stdout.write(w);
    ' "$CONFIG" "$id" "$HOME")"
    if [ -z "$ws" ]; then warn "  $id: no workspace configured — skipped"; continue; fi

    # Re-root: <old-state>/rest  ->  <target-state>/rest
    case "$ws" in
      "$STATE"/*) ;;                                   # already in the target
      "$DEFAULT_STATE"/*) ws="$STATE/${ws#"$DEFAULT_STATE"/}";;
    esac

    # Hard stop: never write a workspace outside the target state dir.
    case "$ws" in
      "$STATE"/*) ;;
      *) warn "  $id: workspace $(tildify "$ws") is outside the target state dir — skipped"
         continue;;
    esac

    info "  $id -> $(tildify "$ws")"
    if [ "$DRY_RUN" -eq 0 ]; then
      mkdir -p "$ws"
      # -R copies the tree; existing files are overwritten, extra files in the
      # target are left alone (this is additive, not a mirror).
      (cd "$adir" && cp -R . "$ws/")
    fi
  done
fi

# ---------------------------------------------------------------------------
# 5. Crons.
# ---------------------------------------------------------------------------
# `openclaw cron add` talks to the Gateway, so it only works when one is
# running. --crons-file is the offline path for test instances.
info "recreating crons"
CRON_N=$(node -e 'try{console.log((JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).jobs||[]).length)}catch(e){console.log(0)}' "$FLEET/crons.json")
if [ "$CRON_N" -eq 0 ]; then
  ok "  no crons to create"
elif [ "$CRONS_FILE" -eq 1 ]; then
  warn "  writing cron store directly (--crons-file) — test instances only"
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$STATE/cron"
    node -e '
      const fs=require("fs");
      const [src,dst]=process.argv.slice(1);
      const jobs=(JSON.parse(fs.readFileSync(src,"utf8")).jobs||[]).map((j,i)=>({
        id:"fleet-"+String(i+1).padStart(4,"0"),
        name:j.name,displayName:j.displayName,description:j.description,
        enabled:j.enabled!==false,agentId:j.agentId,
        schedule:j.schedule,sessionTarget:j.sessionTarget||"isolated",
        payload:j.payload,delivery:j.delivery,
        createdAtMs:Date.now(),updatedAtMs:Date.now(),
      }));
      fs.writeFileSync(dst,JSON.stringify({version:1,jobs},null,2)+"\n");
    ' "$FLEET/crons.json" "$STATE/cron/jobs.json"
    ok "  wrote $CRON_N jobs to $(tildify "$STATE/cron/jobs.json")"
  fi
else
  # Build one `cron add` per job, mapping the export back onto real CLI flags.
  CRON_FAILED=0
  # NUL-delimited: cron messages routinely contain newlines, which would
  # otherwise split one job into several bogus commands.
  while IFS= read -r -d '' line; do
    [ -n "$line" ] || continue
    if [ "$DRY_RUN" -eq 1 ]; then printf '   would run: openclaw cron add %s\n' "$line"
    else
      # `cron add` blocks forever without a gateway, so bound it.
      set +e
      eval "with_timeout 20 openclaw cron add $line" >/dev/null 2>&1
      rc=$?
      set -e
      if [ "$rc" -eq 0 ]; then ok "  created: $(printf '%s' "$line" | sed -n 's/.*--name \([^ ]*\).*/\1/p')"
      elif [ "$rc" -eq 124 ]; then
        warn "  timed out — no gateway is listening. Start one, or re-run with --crons-file"
        CRON_FAILED=1
      else warn "  cron add failed (rc=$rc)"; CRON_FAILED=1; fi
    fi
  done < <(node -e '
    const fs=require("fs");
    const q=s=>"\047"+String(s).replace(/\047/g,"\047\\\047\047")+"\047";
    const jobs=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).jobs||[];
    for(const j of jobs){
      const a=[];
      a.push("--name",q(j.name));
      if(j.agentId)a.push("--agent",q(j.agentId));
      const s=j.schedule||{};
      if(s.kind==="cron"){a.push("--cron",q(s.expr));if(s.tz)a.push("--tz",q(s.tz));}
      else if(s.kind==="every")a.push("--every",q(s.every));
      else if(s.kind==="at"){a.push("--at",q(s.at));if(s.tz)a.push("--tz",q(s.tz));}
      if(j.sessionTarget)a.push("--session",q(j.sessionTarget));
      if(j.model)a.push("--model",q(j.model));
      if(j.description)a.push("--description",q(j.description));
      if(j.displayName)a.push("--display-name",q(j.displayName));
      const p=j.payload||{};
      if(p.kind==="command"&&p.command){a.push("--command",q(p.command));if(p.cwd)a.push("--command-cwd",q(p.cwd));}
      else if(p.message)a.push("--message",q(p.message));
      const d=j.delivery||{};
      if(d.mode==="announce"){a.push("--announce");if(d.channel)a.push("--channel",q(d.channel));}
      if(j.enabled===false)a.push("--disabled");
      process.stdout.write(a.join(" ")+"\0");
    }
  ' "$FLEET/crons.json")
  [ "${CRON_FAILED:-0}" -eq 0 ] || warn "  some crons were not created — see above"
fi

# ---------------------------------------------------------------------------
# 6. Exec allowlist.
# ---------------------------------------------------------------------------
info "applying exec allowlist"
if [ -f "$FLEET/exec-approvals.json" ]; then
  applied=0
  while IFS=$'\t' read -r agent pattern; do
    [ -n "$agent" ] || continue
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '   would run: openclaw approvals allowlist add --agent %s %s\n' "$agent" "$pattern"
    else
      # The CLI prefers a live gateway; fall back to writing the store so an
      # offline bootstrap still ends up with the right allowlist.
      if with_timeout 15 openclaw approvals allowlist add --agent "$agent" "$pattern" >/dev/null 2>&1; then
        applied=$((applied+1))
      else
        warn "  CLI failed for $agent — will write the store directly"
        applied=-1; break
      fi
    fi
  done < <(node -e '
    const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    const home=process.argv[2];
    for(const [id,a] of Object.entries(j.agents||{}))
      for(const e of a.allowlist||[]){
        let p=typeof e==="string"?e:e.pattern;
        if(p&&p.startsWith("~/"))p=home+p.slice(1);
        console.log(id+"\t"+p);
      }
  ' "$FLEET/exec-approvals.json" "$HOME")

  if [ "$DRY_RUN" -eq 0 ] && [ "$applied" -eq -1 ]; then
    node -e '
      const fs=require("fs");
      const [src,dst,home]=process.argv.slice(1);
      const f=JSON.parse(fs.readFileSync(src,"utf8"));
      let cur={version:1,defaults:{},agents:{}};
      try{cur=JSON.parse(fs.readFileSync(dst,"utf8"));}catch(e){}
      cur.agents=cur.agents||{};
      for(const [id,a] of Object.entries(f.agents||{})){
        const list=(a.allowlist||[]).map(e=>({pattern:(typeof e==="string"?e:e.pattern).replace(/^~\//,home+"/")}));
        cur.agents[id]=cur.agents[id]||{allowlist:[]};
        const seen=new Set((cur.agents[id].allowlist||[]).map(x=>x.pattern));
        for(const item of list) if(!seen.has(item.pattern)) cur.agents[id].allowlist.push(item);
      }
      fs.writeFileSync(dst,JSON.stringify(cur,null,2)+"\n");
    ' "$FLEET/exec-approvals.json" "$STATE/exec-approvals.json" "$HOME"
    ok "  wrote allowlist to $(tildify "$STATE/exec-approvals.json")"
  elif [ "$DRY_RUN" -eq 0 ]; then
    ok "  $applied allowlist patterns applied"
  fi
fi

# ---------------------------------------------------------------------------
# 7. Manual steps.
# ---------------------------------------------------------------------------
echo
if [ -f "$HERE/CHECKLIST.md" ]; then
  cat "$HERE/CHECKLIST.md"
else
  warn "CHECKLIST.md not found next to bootstrap.sh"
fi
echo
ok "bootstrap finished — the manual steps above are NOT optional"
