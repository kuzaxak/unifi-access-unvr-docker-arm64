#!/usr/bin/env bash

set -euo pipefail

service_js="/usr/share/unifi-core/app/service.js"
node_bin="$(command -v node18 || command -v node)"

# Core 4.1.140's DBus-backed service watcher crashes in this container because
# dbus-next throws when a systemd property call races a closed stream. The
# rollback controller only needs coarse app state, so initialize service state
# through systemctl and keep the Node process alive while startup awaits.
"$node_bin" - "$service_js" <<'NODE'
const fs = require("fs");

const serviceJs = process.argv[2];
let source = fs.readFileSync(serviceJs, "utf8");

const watcherStart =
  'async init(){let t=this.#l;try{let r=await t.getProxyObject("org.freedesktop.systemd1",this.#p);';
const watcherEnd = "async destroy(){";
const watcherReplacement =
  'async init(){try{let{stdout:t}=await Xr("systemctl",["is-active",`${this.#r}.service`]);this.#e=t.trim(),this.#t=""}catch{this.#e="inactive",this.#t=""}this.#i?.();}';

const watcherStartIdx = source.indexOf(watcherStart);
if (watcherStartIdx === -1) {
  throw new Error("Core 4.x systemd watcher start marker did not match");
}

const watcherEndIdx = source.indexOf(watcherEnd, watcherStartIdx);
if (watcherEndIdx === -1) {
  throw new Error("Core 4.x systemd watcher end marker did not match");
}

source =
  source.slice(0, watcherStartIdx) +
  watcherReplacement +
  source.slice(watcherEndIdx);

const consoleGroupDefaults =
  'HH=()=>ge().controllers.reduce((e,t)=>({...e,[t.name]:{owned:!1,required:!!t.required,supported:!0}}),{})';
const consoleGroupReplacement =
  'HH=()=>ge().controllers.reduce((e,t)=>({...e,[t.name]:{owned:t.name==="access",required:t.name==="protect"?!1:!!t.required,supported:!0}}),{})';
if (!source.includes(consoleGroupDefaults)) {
  throw new Error("Core 4.x console group default marker did not match");
}

source = source.replace(consoleGroupDefaults, consoleGroupReplacement);

const startupAwait =
  "try{await Wxe();}catch(e){console.error(e),process.exit(1);}";
const startupAwaitIdx = source.lastIndexOf(startupAwait);
if (startupAwaitIdx === -1) {
  throw new Error("Core 4.x startup await marker did not match");
}

source =
  source.slice(0, startupAwaitIdx) +
  "setInterval(()=>{},2147483647);" +
  source.slice(startupAwaitIdx);

fs.writeFileSync(serviceJs, source);
NODE
