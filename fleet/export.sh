#!/usr/bin/env bash
# fleet/export.sh — snapshot a live OpenClaw instance into a "fleet" directory.
# Read-only with respect to the instance: it never writes under the state dir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

OUT=""
WITH_MEMORY=0

usage() {
  cat <<'EOF'
Usage: fleet/export.sh --out <fleet-dir> [--with-memory]

Snapshots the live OpenClaw instance into <fleet-dir> as "fleet as code":

  fleet.json           config extract (no auth/gateway/channels/meta, no secrets)
  channels.json        non-secret channel policy (dmPolicy/allowFrom/groupPolicy)
  agents/<id>/         each agent's workspace docs (md, skills, people, ...)
  crons.json           cron jobs reduced to the fields `cron add` accepts
  exec-approvals.json  per-agent exec allowlist (socket token stripped)
  plugins.json         non-bundled plugins, for `openclaw plugins install`
  manifest.json        version, date, hostname, agent list

Options:
  --out <dir>      destination fleet directory (created if missing)
  --with-memory    also export each workspace's memory/ dir (opt-in: memory
                   often holds personal notes you may not want in a repo)
  -h, --help       show this help

Honours OPENCLAW_STATE_DIR / OPENCLAW_CONFIG_PATH, so it can snapshot a test
instance instead of the default ~/.openclaw one.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:?--out needs a directory}"; shift 2;;
    --with-memory) WITH_MEMORY=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown argument: $1 (try --help)";;
  esac
done

[ -n "$OUT" ] || { usage >&2; die "--out is required"; }
need_cmd openclaw; need_cmd node

CONFIG="$(fleet_config_path)"
STATE="$(fleet_state_dir)"
[ -f "$CONFIG" ] || die "config not found: $CONFIG"

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
info "exporting instance"
info "  config: $(tildify "$CONFIG")"
info "  state : $(tildify "$STATE")"
info "  out   : $(tildify "$OUT")"

# ---------------------------------------------------------------------------
# 1. fleet.json + channels.json — the config extract.
# ---------------------------------------------------------------------------
# Redaction rules live in node because they need to walk the tree recursively.
# Note: we drop a key when its NAME looks like a secret *and* its value is a
# string. `skills.entries["1password"]` is a key that matches /password/i but
# holds an object ({enabled:false}) — dropping it would silently lose config,
# so the string check is what keeps that entry.
node - "$CONFIG" "$OUT" "$HOME" <<'NODE'
const fs = require('fs');
const [configPath, outDir, home] = process.argv.slice(2);
const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));

const SECRET_KEY = /key|token|secret|password|credential/i;
const isSecretLeaf = (k, v) => SECRET_KEY.test(k) && typeof v === 'string' && v.length > 0;

// Absolute paths under $HOME become "~/..." so the fleet is portable.
const detilde = (s) => (home && s.startsWith(home + '/')) ? '~' + s.slice(home.length) : s;

function clean(v, k) {
  if (typeof v === 'string') return detilde(v);
  if (Array.isArray(v)) return v.map((x) => clean(x, k));
  if (v && typeof v === 'object') {
    const out = {};
    for (const [ck, cv] of Object.entries(v)) {
      if (isSecretLeaf(ck, cv)) continue;      // drop the secret, keep siblings
      out[ck] = clean(cv, ck);
    }
    return out;
  }
  return v;
}

const fleet = {};
for (const section of ['agents','bindings','session','tools','acp','messages','skills','hooks']) {
  if (cfg[section] !== undefined) fleet[section] = clean(cfg[section], section);
}
// plugins: only the enable/config surface, never install metadata or auth.
const entries = (cfg.plugins && cfg.plugins.entries) || {};
const pe = {};
for (const [id, e] of Object.entries(entries)) {
  const kept = {};
  if (e && typeof e === 'object') {
    if ('enabled' in e) kept.enabled = e.enabled;
    if ('config' in e) kept.config = clean(e.config, 'config');
  }
  pe[id] = kept;
}
if (Object.keys(pe).length) fleet.plugins = { entries: pe };

fs.writeFileSync(outDir + '/fleet.json', JSON.stringify(fleet, null, 2) + '\n');

// channels.json: policy only. Credentials for a channel live in the state dir
// (WhatsApp pairs by QR), so nothing secret should appear here — but we still
// whitelist the fields rather than blacklisting, to be safe.
const KEEP = ['enabled','dmPolicy','allowFrom','groupPolicy','groupAllowFrom','selfChatMode'];
const channels = {};
for (const [id, ch] of Object.entries(cfg.channels || {})) {
  if (!ch || typeof ch !== 'object') continue;
  const kept = {};
  for (const f of KEEP) if (f in ch) kept[f] = clean(ch[f], f);
  if (Object.keys(kept).length) channels[id] = kept;
}
fs.writeFileSync(outDir + '/channels.json', JSON.stringify(channels, null, 2) + '\n');

const ids = ((cfg.agents && cfg.agents.list) || []).map((a) => a.id);
fs.writeFileSync(outDir + '/.agent-ids', ids.join('\n') + '\n');
console.log('config sections: ' + Object.keys(fleet).join(', '));
console.log('channels: ' + (Object.keys(channels).join(', ') || '(none)'));
NODE

AGENT_IDS=()
while IFS= read -r _id; do [ -n "$_id" ] && AGENT_IDS+=("$_id"); done < "$OUT/.agent-ids"
rm -f "$OUT/.agent-ids"

# ---------------------------------------------------------------------------
# 2. agents/<id>/ — workspace documents.
# ---------------------------------------------------------------------------
# The default workspace (agents.defaults.workspace) belongs to `main`; every
# other agent declares its own in agents.list[].workspace.
workspace_for() {
  node -e '
    const fs=require("fs");
    const cfg=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const id=process.argv[2], home=process.argv[3];
    const a=((cfg.agents&&cfg.agents.list)||[]).find(x=>x.id===id)||{};
    let w=a.workspace||(cfg.agents&&cfg.agents.defaults&&cfg.agents.defaults.workspace)||"";
    if(w.startsWith("~/")) w=home+w.slice(1);
    process.stdout.write(w);
  ' "$CONFIG" "$1" "$HOME"
}

copy_workspace() {
  local src="$1" dst="$2"
  # Include list mirrors what a human would want to re-create an agent: prose,
  # skills and scripts. Everything heavy or machine-generated is excluded, which
  # is what keeps a 145 MB workspace down to a few hundred KB.
  #
  # find runs with a relative root ("." from inside $src) on purpose: workspaces
  # normally live UNDER ~/.openclaw, so matching an absolute path against
  # '*/.openclaw/*' would exclude every single file. Relative paths make the
  # exclusions mean "inside the workspace", which is what we actually want.
  local -a find_args
  find_args=(
    . -type f
    \(
      -name '*.md'
      -o -path './skills/*' -o -path './people/*' -o -path './study/*'
      -o -path './projects/*' -o -path './bin/*'
    \)
    -not -path './.git/*' -not -path './.openclaw/*'
    -not -name '*.bak' -not -name '*.bak-*' -not -name '*.bak.*'
    -not -name 'openclaw-workspace-state.json'
    -not -path '*/media/*' -not -path '*/outputs/*' -not -path '*/node_modules/*'
    -size -1024k
  )
  [ "$WITH_MEMORY" -eq 1 ] || find_args+=( -not -path '*/memory/*' )

  local rel
  while IFS= read -r rel; do
    rel="${rel#./}"
    mkdir -p "$dst/$(dirname "$rel")"
    cp -p "$src/$rel" "$dst/$rel"
  done < <(cd "$src" && find "${find_args[@]}" 2>/dev/null | sort)

  # queue/ is exported as structure only: the messages inside are transient
  # and frequently contain conversation content.
  if [ -d "$src/queue" ]; then
    while IFS= read -r d; do
      d="${d#./}"
      mkdir -p "$dst/$d"
    done < <(cd "$src" && find ./queue -type d 2>/dev/null | sort)
  fi
}

info "exporting workspaces"
rm -rf "$OUT/agents"
declare -a SUMMARY_WS=()
for id in "${AGENT_IDS[@]}"; do
  [ -n "$id" ] || continue
  ws="$(workspace_for "$id")"
  if [ -z "$ws" ] || [ ! -d "$ws" ]; then
    warn "  $id: workspace not found ($(tildify "${ws:-unset}")) — skipped"
    continue
  fi
  mkdir -p "$OUT/agents/$id"
  copy_workspace "$ws" "$OUT/agents/$id"
  bytes=$(find "$OUT/agents/$id" -type f -exec cat {} + 2>/dev/null | wc -c | tr -d ' ')
  files=$(find "$OUT/agents/$id" -type f | wc -l | tr -d ' ')
  SUMMARY_WS+=("$(printf '  %-20s %5s files %10s bytes' "$id" "$files" "$bytes")")
done

# ---------------------------------------------------------------------------
# 3. crons.json — reduced to what `openclaw cron add` can rebuild.
# ---------------------------------------------------------------------------
info "exporting crons"
CRON_COUNT=0
if cron_raw=$(openclaw cron list --json 2>/dev/null); then
  printf '%s' "$cron_raw" | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      const i=s.indexOf("{");                       // skip CLI banner lines
      const j=i<0?{jobs:[]}:JSON.parse(s.slice(i));
      const jobs=(j.jobs||[]).map(job=>{
        const o={name:job.name,agentId:job.agentId,enabled:job.enabled!==false};
        if(job.displayName)o.displayName=job.displayName;
        if(job.description)o.description=job.description;
        const sc=job.schedule||{};
        // `cron add` takes --cron/--every/--at plus --tz; mirror whichever the
        // job actually uses so the rebuilt job is identical.
        if(sc.kind==="cron"){o.schedule={kind:"cron",expr:sc.expr};if(sc.tz)o.schedule.tz=sc.tz;
          if(sc.staggerMs!==undefined)o.schedule.staggerMs=sc.staggerMs;}
        else if(sc.kind==="every"){o.schedule={kind:"every",every:sc.every||sc.duration};}
        else if(sc.kind==="once"||sc.kind==="at"){o.schedule={kind:"at",at:sc.at||sc.when};if(sc.tz)o.schedule.tz=sc.tz;}
        else o.schedule=sc;
        if(job.sessionTarget)o.sessionTarget=job.sessionTarget;
        if(job.model)o.model=job.model;
        if(job.fallbacks)o.fallbacks=job.fallbacks;
        const p=job.payload||{};
        o.payload=p.kind==="command"
          ? {kind:"command",command:p.command,argv:p.argv,cwd:p.cwd,input:p.input}
          : {kind:"agentTurn",message:p.message};
        const d=job.delivery||{};
        if(d.mode)o.delivery={mode:d.mode,channel:d.channel,to:d.to,account:d.account};
        return o;
      });
      process.stdout.write(JSON.stringify({jobs},null,2)+"\n");
    });' > "$OUT/crons.json"
  CRON_COUNT=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).jobs.length)' "$OUT/crons.json")
else
  warn "  cron list failed (gateway down?) — writing empty crons.json"
  printf '{\n  "jobs": []\n}\n' > "$OUT/crons.json"
fi

# ---------------------------------------------------------------------------
# 4. exec-approvals.json — allowlist only.
# ---------------------------------------------------------------------------
# The live file carries socket.token (a real credential). We keep only the
# per-agent allowlist patterns, and drop the churny lastUsedAt/id fields.
# Source of truth, in order: the CLI snapshot (authoritative, and the only one
# that sees approvals migrated into SQLite), then the plain file, then the
# .migrated leftover OpenClaw renames aside after a state migration.
info "exporting exec approvals"
APPROVAL_COUNT=0
APPROVAL_SRC=""
if openclaw approvals get --json 2>/dev/null | sed -n 's/^[^{]*//p' > "$OUT/.approvals-cli" 2>/dev/null \
   && node -e '
     const fs=require("fs");
     const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
     const a=(j.file&&j.file.agents)||{};
     const n=Object.values(a).reduce((t,x)=>t+((x.allowlist||[]).length),0);
     if(!n) process.exit(1);
     fs.writeFileSync(process.argv[1],JSON.stringify(j.file));
   ' "$OUT/.approvals-cli" 2>/dev/null; then
  APPROVAL_SRC="$OUT/.approvals-cli"
elif [ -f "$STATE/exec-approvals.json" ]; then
  APPROVAL_SRC="$STATE/exec-approvals.json"
elif [ -f "$STATE/exec-approvals.json.migrated" ]; then
  # OpenClaw migrated approvals into SQLite and renamed the file aside.
  warn "  using exec-approvals.json.migrated (approvals were migrated to SQLite)"
  APPROVAL_SRC="$STATE/exec-approvals.json.migrated"
fi
rm -f "$OUT/.approvals-cli.tmp"
if [ -n "$APPROVAL_SRC" ]; then
  node -e '
    const fs=require("fs");
    const [src,dst,home,countFile]=process.argv.slice(1);
    const j=JSON.parse(fs.readFileSync(src,"utf8"));
    const detilde=s=>typeof s==="string"&&s.startsWith(home+"/")?"~"+s.slice(home.length):s;
    const agents={};let n=0;
    for(const [id,a] of Object.entries(j.agents||{})){
      const list=(a.allowlist||[]).map(e=>({pattern:detilde(typeof e==="string"?e:e.pattern)}));
      if(list.length){agents[id]={allowlist:list};n+=list.length;}
    }
    fs.writeFileSync(dst,JSON.stringify({version:j.version||1,defaults:j.defaults||{},agents},null,2)+"\n");
    fs.writeFileSync(countFile,String(n));
  ' "$APPROVAL_SRC" "$OUT/exec-approvals.json" "$HOME" "$OUT/.n"
  APPROVAL_COUNT=$(cat "$OUT/.n"); rm -f "$OUT/.n" "$OUT/.approvals-cli"
else
  printf '{\n  "version": 1,\n  "defaults": {},\n  "agents": {}\n}\n' > "$OUT/exec-approvals.json"
fi

# ---------------------------------------------------------------------------
# 5. plugins.json — the ones a fresh machine must npm-install.
# ---------------------------------------------------------------------------
# `plugins list --json` marks bundled plugins with origin=="bundled"; anything
# else was installed separately and must be reinstalled by id.
info "exporting plugins"
PLUGIN_COUNT=0
if plug_raw=$(openclaw plugins list --json 2>/dev/null); then
  printf '%s' "$plug_raw" | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      const i=s.indexOf("{");
      const j=i<0?{plugins:[]}:JSON.parse(s.slice(i));
      const plugins=(j.plugins||[])
        .filter(p=>p.origin&&p.origin!=="bundled")
        .map(p=>{
          // p.name is a display name ("WhatsApp"), not installable. The real npm
          // spec is the last node_modules segment of rootDir (@openclaw/whatsapp).
          const m=(p.rootDir||"").match(/node_modules\/(@[^/]+\/[^/]+|[^/]+)$/);
          return {id:p.id,package:m?m[1]:p.name,displayName:p.name,version:p.version,enabled:p.enabled!==false};
        })
        .sort((a,b)=>a.id.localeCompare(b.id));
      process.stdout.write(JSON.stringify({plugins},null,2)+"\n");
    });' > "$OUT/plugins.json"
  PLUGIN_COUNT=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).plugins.length)' "$OUT/plugins.json")
else
  warn "  plugins list failed (gateway down?) — writing empty plugins.json"
  printf '{\n  "plugins": []\n}\n' > "$OUT/plugins.json"
fi

# ---------------------------------------------------------------------------
# 6. manifest.json
# ---------------------------------------------------------------------------
# hostname only (no user name) — enough to tell two exports apart without
# putting an identity into the file.
OC_VERSION="$(openclaw --version 2>/dev/null | head -1 || echo unknown)"
node -e '
  const fs=require("fs");
  const [dst,ver,host,fleetVer,...ids]=process.argv.slice(1);
  fs.writeFileSync(dst,JSON.stringify({
    fleetFormat:Number(fleetVer),
    openclawVersion:ver,
    exportedAt:new Date().toISOString(),
    hostname:host,
    agents:ids,
  },null,2)+"\n");
' "$OUT/manifest.json" "$OC_VERSION" "$(hostname -s)" "$FLEET_VERSION" "${AGENT_IDS[@]}"

# ---------------------------------------------------------------------------
# 7. Summary + mandatory secret scan.
# ---------------------------------------------------------------------------
ALLOWLIST_N=$(node -e '
  const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
  console.log(Object.keys(j.agents||{}).length);' "$OUT/channels.json" 2>/dev/null || echo 0)

echo
info "summary"
printf '  openclaw     %s\n' "$OC_VERSION"
printf '  agents       %s (%s)\n' "${#AGENT_IDS[@]}" "$(IFS=,; echo "${AGENT_IDS[*]}")"
printf '  workspaces\n'
for line in "${SUMMARY_WS[@]}"; do printf '%s\n' "$line"; done
printf '  crons        %s\n' "$CRON_COUNT"
printf '  plugins      %s (non-bundled)\n' "$PLUGIN_COUNT"
printf '  allowlist    %s patterns\n' "$APPROVAL_COUNT"
printf '  memory       %s\n' "$([ "$WITH_MEMORY" -eq 1 ] && echo included || echo 'excluded (--with-memory to include)')"
echo

scan_secrets "$OUT"
ok "fleet exported to $(tildify "$OUT")"
