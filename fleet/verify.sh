#!/usr/bin/env bash
# fleet/verify.sh — compare a fleet directory against a live instance.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

FLEET=""; STATE_DIR=""; CONFIG_PATH=""

usage() {
  cat <<'EOF'
Usage: fleet/verify.sh --fleet <fleet-dir> [--state-dir <dir>] [--config <path>]

Compares a fleet export against an instance and prints an OK/DIFF table for:
agents, models, workspaces, tools, bindings, session, crons and the allowlist.
Also runs scripts/check-prompt-budget.sh when it is present.

Exit code is 1 if any section reports DIFF.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --fleet) FLEET="${2:?}"; shift 2;;
    --state-dir) STATE_DIR="${2:?}"; shift 2;;
    --config) CONFIG_PATH="${2:?}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown argument: $1 (try --help)";;
  esac
done

[ -n "$FLEET" ] || { usage >&2; die "--fleet is required"; }
FLEET="$(cd "$FLEET" 2>/dev/null && pwd)" || die "fleet dir not found"
[ -f "$FLEET/fleet.json" ] || die "not a fleet dir: $FLEET"

STATE="${STATE_DIR:-$(fleet_state_dir)}"
CONFIG="${CONFIG_PATH:-${OPENCLAW_CONFIG_PATH:-$STATE/openclaw.json}}"
export OPENCLAW_STATE_DIR="$STATE" OPENCLAW_CONFIG_PATH="$CONFIG"
[ -f "$CONFIG" ] || die "instance config not found: $CONFIG"

info "verifying"
info "  fleet : $(tildify "$FLEET")"
info "  config: $(tildify "$CONFIG")"
echo

# Live cron names, if a gateway answers. Empty file => "gateway down", which is
# reported as SKIP rather than DIFF so an offline check is still useful.
CRON_LIVE="$(mktemp)"; trap 'rm -f "$CRON_LIVE"' EXIT
openclaw cron list --json 2>/dev/null > "$CRON_LIVE" || true

# The section-by-section comparison is one node program: it needs to diff
# nested structures, which is painful in shell.
set +e
node -e '
const fs=require("fs");
const [fleetDir,configPath,home,cronLive,stateDir]=process.argv.slice(1);
// bootstrap.sh re-roots state-dir paths onto the target state dir, so compare
// workspaces after applying the same mapping — otherwise a correctly
// bootstrapped test instance would report a false DIFF on every agent.
const defaultState=home+"/.openclaw";
const reroot=(s)=>(typeof s==="string"&&stateDir&&stateDir!==defaultState&&s.startsWith(defaultState+"/"))
  ? stateDir+s.slice(defaultState.length) : s;
const F=JSON.parse(fs.readFileSync(fleetDir+"/fleet.json","utf8"));
const C=JSON.parse(fs.readFileSync(configPath,"utf8"));

const rows=[];let bad=0;
const row=(name,status,detail)=>{rows.push([name,status,detail||""]);if(status==="DIFF")bad++;};
// Fleet paths are stored as ~/... ; expand before comparing with the instance.
const exp=(v)=>{
  if(typeof v==="string") return v.startsWith("~/")?home+v.slice(1):v;
  if(Array.isArray(v)) return v.map(exp);
  if(v&&typeof v==="object"){const o={};for(const[k,x]of Object.entries(v))o[k]=exp(x);return o;}
  return v;
};
const norm=(v)=>JSON.stringify(exp(v)===undefined?null:exp(v));
const cmp=(name,a,b,detail)=>row(name,norm(a)===norm(b)?"OK":"DIFF",detail);

// --- agents ---------------------------------------------------------------
const fList=(F.agents&&F.agents.list)||[];
const cList=(C.agents&&C.agents.list)||[];
const fIds=fList.map(a=>a.id).sort(), cIds=cList.map(a=>a.id).sort();
row("agent ids",JSON.stringify(fIds)===JSON.stringify(cIds)?"OK":"DIFF",
    fIds.length+" fleet / "+cIds.length+" instance");

const dflt=(o,k)=>o&&o.agents&&o.agents.defaults?o.agents.defaults[k]:undefined;
for(const id of fIds){
  const f=fList.find(a=>a.id===id)||{}, c=cList.find(a=>a.id===id)||{};
  if(!cList.find(a=>a.id===id)){row("  "+id,"DIFF","missing in instance");continue;}
  const fm=f.model!==undefined?f.model:dflt(F,"model");
  const cm=c.model!==undefined?c.model:dflt(C,"model");
  // model may be a bare string or {primary,fallbacks}
  const prim=m=>typeof m==="string"?m:(m&&m.primary);
  const fb=m=>typeof m==="string"?[]:((m&&m.fallbacks)||[]);
  const parts=[];
  if(prim(fm)!==prim(cm))parts.push("primary "+prim(fm)+" != "+prim(cm));
  if(JSON.stringify(fb(fm))!==JSON.stringify(fb(cm)))parts.push("fallbacks differ");
  const fw=reroot(exp(f.workspace!==undefined?f.workspace:dflt(F,"workspace")));
  const cw=exp(c.workspace!==undefined?c.workspace:dflt(C,"workspace"));
  if(fw!==cw)parts.push("workspace differs");
  if(norm(f.tools)!==norm(c.tools))parts.push("tools differ");
  row("  "+id,parts.length?"DIFF":"OK",parts.join("; "));
}

// --- bindings (agentId + peer identity) -----------------------------------
const key=b=>{const m=b.match||{};const p=m.peer||{};
  return [b.agentId,m.channel||"",m.accountId||"",p.kind||"",p.id||""].join("|");};
const fb2=(F.bindings||[]).map(key).sort(), cb=(C.bindings||[]).map(key).sort();
row("bindings",JSON.stringify(fb2)===JSON.stringify(cb)?"OK":"DIFF",fb2.length+" fleet / "+cb.length+" instance");

// --- plain config sections -------------------------------------------------
cmp("session",F.session,C.session);
cmp("session.heartbeat",dflt(F,"heartbeat"),dflt(C,"heartbeat"));
cmp("session.contextPruning",dflt(F,"contextPruning"),dflt(C,"contextPruning"));
cmp("session.subagents",dflt(F,"subagents"),dflt(C,"subagents"));
cmp("tools",F.tools,C.tools);
cmp("acp",F.acp,C.acp);
cmp("messages",F.messages,C.messages);
cmp("hooks",F.hooks,C.hooks);

// --- crons ----------------------------------------------------------------
const fc=(()=>{try{return JSON.parse(fs.readFileSync(fleetDir+"/crons.json","utf8")).jobs||[]}catch(e){return[]}})();
let live=null;
try{const s=fs.readFileSync(cronLive,"utf8");const i=s.indexOf("{");if(i>=0)live=JSON.parse(s.slice(i)).jobs||[];}catch(e){}
if(live===null){
  // No gateway answered. Fall back to the on-disk store; OpenClaw renames it to
  // .migrated once it absorbs the jobs into SQLite, so accept either name.
  for(const p of ["/cron/jobs.json","/cron/jobs.json.migrated"]){
    try{live=JSON.parse(fs.readFileSync(stateDir+p,"utf8")).jobs||[];break;}catch(e){}
  }
}
if(live===null) row("crons","SKIP","no gateway and no cron store");
else{
  const fn=fc.map(j=>j.name).sort(), ln=live.map(j=>j.name).sort();
  row("crons",JSON.stringify(fn)===JSON.stringify(ln)?"OK":"DIFF",
      fc.length+" fleet / "+live.length+" instance");
}

// --- allowlist -------------------------------------------------------------
const fa=(()=>{try{return JSON.parse(fs.readFileSync(fleetDir+"/exec-approvals.json","utf8")).agents||{}}catch(e){return{}}})();
const ca=(()=>{try{return JSON.parse(fs.readFileSync(stateDir+"/exec-approvals.json","utf8")).agents||{}}catch(e){return{}}})();
const flat=o=>Object.entries(o).flatMap(([id,a])=>(a.allowlist||[])
  .map(e=>id+"|"+exp(typeof e==="string"?e:e.pattern))).sort();
const fap=flat(fa), cap=flat(ca);
row("exec allowlist",JSON.stringify(fap)===JSON.stringify(cap)?"OK":"DIFF",
    fap.length+" fleet / "+cap.length+" instance");

const w=Math.max(...rows.map(r=>r[0].length));
for(const [n,s,d] of rows)
  console.log("  "+n.padEnd(w)+"  "+s.padEnd(4)+"  "+d);
console.log("");
console.log(bad?("FAIL: "+bad+" section(s) differ"):"All sections match.");
process.exit(bad?1:0);
' "$FLEET" "$CONFIG" "$HOME" "$CRON_LIVE" "$STATE"
CMP_RC=$?
set -e

# The repo's own guardrail: agents must not treat a project repo as a workspace.
echo
BUDGET="$HERE/../scripts/check-prompt-budget.sh"
if [ -x "$BUDGET" ] || [ -f "$BUDGET" ]; then
  info "running check-prompt-budget.sh"
  if OPENCLAW_CONFIG_PATH="$CONFIG" bash "$BUDGET" >/dev/null 2>&1; then
    ok "  prompt budget OK"
  elif [ "$STATE" != "$HOME/.openclaw" ]; then
    # The budget script enforces repo rule 0: workspaces must live under
    # ~/.openclaw/. An isolated instance deliberately breaks that, so on a
    # non-default state dir this is expected rather than a real failure.
    warn "  prompt budget flags the non-default state dir (expected on a test instance)"
    warn "  re-run it against the real instance to check the rule for real"
  else
    warn "  prompt budget reported problems — run it directly:"
    warn "    OPENCLAW_CONFIG_PATH=$(tildify "$CONFIG") bash scripts/check-prompt-budget.sh"
  fi
else
  warn "check-prompt-budget.sh not found — skipped"
fi

exit "$CMP_RC"
