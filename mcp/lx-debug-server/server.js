#!/usr/bin/env node
// lx-debug-server v3 -- MCP + HTTP bridge for in-game Lua execution.
//
// MCP talks to the client over stdio; the game plugin polls this process over
// HTTP on 127.0.0.1:7778.
//
// v3: results come back in a POST body (no shared-disk requirement), the
// command parser is a separately tested module, and result files written by
// older plugin builds are cleaned up after they are read.

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import { parseCommand, isRawLua } from "./parser.js";

const HERE = path.dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const VERSION = "3.0.0";
const HTTP_PORT = Number(process.env.LX_DEBUG_PORT || 7778);
const SCRIPTS_DATA = process.env.SCRIPTS_DATA_PATH || "F:\\ProjectSylvanas\\scripts_data";
const SCRIPTS_LOG = process.env.SCRIPTS_LOG_PATH || "F:\\ProjectSylvanas\\scripts_log";
const MAX_RESULT_SIZE = 50000; // cap MCP result text to prevent client overflow
const MAX_PENDING = 200;       // drop oldest commands if the game never polls

// The API reference is checked into this repo. Searching it beats hand-wrapping
// ~750 SDK functions: it is always as current as the crawled docs, and it is
// what stops a caller inventing a method that does not exist.
const DOCS_PATH = process.env.SYLVANNAS_DOCS_PATH
  || path.resolve(HERE, "..", "..", "docs", "SylvannasAPI");

// ---------------------------------------------------------------------------
// Command queue & pending results
// ---------------------------------------------------------------------------
let cmdCounter = 0;
const pendingQueue = [];       // commands waiting to be polled by game
const waitingResults = {};     // id -> { resolve, timer, command }

let totalCommands = 0;
let totalErrors = 0;
let totalDropped = 0;
let lastCommandTime = null;
let lastPollTime = null;

// ---------------------------------------------------------------------------
// Plugin startup tracking
// ---------------------------------------------------------------------------
let lastStartup = null;        // { version, build, time }
let startupWaiters = [];       // [ { resolve, timer } ]

// ---------------------------------------------------------------------------
// Path safety
//
// startsWith() alone is not enough: "/data" is a prefix of "/data-evil". The
// resolved path must sit on a separator boundary inside the base directory.
// ---------------------------------------------------------------------------
function resolveInside(basePath, relativePath) {
  const base = path.resolve(basePath);
  const target = path.resolve(base, relativePath);
  if (target !== base && !target.startsWith(base + path.sep)) {
    throw new Error("Path traversal denied");
  }
  return target;
}

function readFileSafe(basePath, relativePath, lines) {
  const content = fs.readFileSync(resolveInside(basePath, relativePath), "utf-8");
  if (lines && lines > 0) {
    return content.split("\n").slice(-lines).join("\n");
  }
  return content;
}

// ---------------------------------------------------------------------------
// Result delivery
// ---------------------------------------------------------------------------
function deliverResult(id, content) {
  const waiter = waitingResults[id];
  if (!waiter) return false;
  clearTimeout(waiter.timer);
  waiter.resolve(content);
  delete waitingResults[id];
  return true;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 5_000_000) {
        reject(new Error("request body too large"));
        req.destroy();
      }
    });
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });
}

// ---------------------------------------------------------------------------
// HTTP server (game-facing)
// ---------------------------------------------------------------------------
const httpServer = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${HTTP_PORT}`);
  res.setHeader("Content-Type", "application/json");

  if (url.pathname === "/poll") {
    lastPollTime = new Date().toISOString();
    const cmd = pendingQueue.shift();
    res.end(JSON.stringify(cmd || { id: "" }));
    return;
  }

  if (url.pathname === "/result") {
    const id = url.searchParams.get("id");
    if (!id) {
      res.statusCode = 400;
      res.end(JSON.stringify({ error: "missing id" }));
      return;
    }

    // Preferred path: the plugin POSTs the result JSON directly, so the
    // server needs no access to the game's scripts_data directory.
    if (req.method === "POST") {
      try {
        const body = await readBody(req);
        deliverResult(id, body);
        res.end(JSON.stringify({ ok: true }));
      } catch (err) {
        res.statusCode = 400;
        res.end(JSON.stringify({ error: err.message }));
      }
      return;
    }

    // Compatibility path: older plugin builds write a file and send its name.
    const file = url.searchParams.get("file");
    if (!file) {
      res.statusCode = 400;
      res.end(JSON.stringify({ error: "missing file (GET) or POST body" }));
      return;
    }
    try {
      const filePath = resolveInside(SCRIPTS_DATA, file.replace(/\//g, path.sep));
      const content = fs.readFileSync(filePath, "utf-8");
      deliverResult(id, content);
      // Result files are single-use; leaving them behind grows scripts_data
      // without bound.
      try { fs.unlinkSync(filePath); } catch { /* best effort */ }
      res.end(JSON.stringify({ ok: true }));
    } catch (err) {
      res.statusCode = 500;
      res.end(JSON.stringify({ error: "failed to read result file: " + err.message }));
    }
    return;
  }

  if (url.pathname === "/startup") {
    const version = url.searchParams.get("version") || "unknown";
    const build = url.searchParams.get("build") || "unknown";
    lastStartup = { version, build, time: new Date().toISOString() };
    process.stderr.write(`[lx-debug] Game plugin connected: v${version} build=${build}\n`);

    for (const waiter of startupWaiters) {
      clearTimeout(waiter.timer);
      waiter.resolve(lastStartup);
    }
    startupWaiters = [];

    res.end(JSON.stringify({ ok: true }));
    return;
  }

  if (url.pathname === "/health") {
    res.end(JSON.stringify(bridgeStatus()));
    return;
  }

  res.statusCode = 404;
  res.end(JSON.stringify({ error: "not found" }));
});

function bridgeStatus() {
  return {
    status: "ok",
    server_version: VERSION,
    port: HTTP_PORT,
    pending: pendingQueue.length,
    waiting: Object.keys(waitingResults).length,
    totalCommands,
    totalErrors,
    totalDropped,
    lastCommandTime,
    lastPollTime,
    lastStartup,
  };
}

httpServer.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    process.stderr.write(`[lx-debug] FATAL: port ${HTTP_PORT} already in use. Kill the other instance first.\n`);
    process.exit(1);
  }
  throw err;
});

httpServer.listen(HTTP_PORT, "127.0.0.1", () => {
  process.stderr.write(`[lx-debug] HTTP server listening on http://127.0.0.1:${HTTP_PORT}\n`);
});

// ---------------------------------------------------------------------------
// Queue helpers
// ---------------------------------------------------------------------------
function enqueue(cmd) {
  if (pendingQueue.length >= MAX_PENDING) {
    pendingQueue.shift();
    totalDropped++;
  }
  pendingQueue.push(cmd);
}

function queueAndWait(command, timeoutMs = 10000) {
  totalCommands++;
  lastCommandTime = new Date().toISOString();

  const id = "cmd_" + ++cmdCounter;
  const cmd = isRawLua(command)
    ? { id, lua_exec: true, code: command }
    : parseCommand(command, id);

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      delete waitingResults[id];
      totalErrors++;
      reject(new Error(
        `Timeout after ${timeoutMs}ms waiting for game to execute: ${command}. ` +
        (lastPollTime
          ? `Last plugin poll was ${lastPollTime}.`
          : `The plugin has never polled -- is the game running with LxDebug loaded?`)
      ));
    }, timeoutMs);

    waitingResults[id] = { resolve, timer, command };
    enqueue(cmd);
  });
}

function queueMultiAndWait(commands, timeoutMs = 15000) {
  const id = "multi_" + ++cmdCounter;
  totalCommands += commands.length;
  lastCommandTime = new Date().toISOString();

  // Sub-commands share the batch id; raw-Lua entries keep going through
  // loadstring on the game side.
  const subCmds = commands.map((cmdStr) =>
    isRawLua(cmdStr) ? { lua_exec: true, code: cmdStr } : parseCommand(cmdStr)
  );

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      delete waitingResults[id];
      totalErrors++;
      reject(new Error(`Timeout after ${timeoutMs}ms waiting for batch execution (${commands.length} commands)`));
    }, timeoutMs);

    waitingResults[id] = { resolve, timer, command: `multi(${commands.length})` };
    enqueue({ id, multi: true, commands: subCmds });
  });
}

// ---------------------------------------------------------------------------
// Result formatting
// ---------------------------------------------------------------------------
function cap(text) {
  return text.length > MAX_RESULT_SIZE
    ? text.substring(0, MAX_RESULT_SIZE) + `\n... (truncated, total ${text.length} chars)`
    : text;
}

function formatResult(raw) {
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { text: cap(raw), isError: false };
  }

  if (parsed.ok === false) {
    return { text: `Error: ${parsed.error}`, isError: true };
  }

  const valueStr = typeof parsed.value === "object"
    ? JSON.stringify(parsed.value, null, 2)
    : String(parsed.value);

  let text = parsed.type ? `[${parsed.type}] ${valueStr}` : valueStr;
  if (parsed.count !== undefined && parsed.shown !== undefined) {
    text += `\n(showing ${parsed.shown} of ${parsed.count} total)`;
  }
  return { text: cap(text), isError: false };
}

// ---------------------------------------------------------------------------
// MCP server
// ---------------------------------------------------------------------------
const mcp = new McpServer({ name: "lx-debug", version: VERSION });

mcp.tool(
  "game_eval",
  "Execute an SDK call in the running game and return the result. Any Sylvannas SDK path " +
  "reachable by table traversal works -- there is no per-function whitelist. " +
  "Roots: core, player, target, pet, nav, dbg, izi. " +
  "Examples: core.get_ping(), player:get_health(), player:get_position(), " +
  "core.quests.get_num_quest_log_entries(), core.spell_book.get_spell_cooldown(12345). " +
  "Multi-statement Lua is also accepted and runs through loadstring, e.g. " +
  "'local p = player:get_position() return p.x'. " +
  "Questing helpers: dbg.quest_log(), dbg.quest_status(id), dbg.quest_objectives(id), " +
  "dbg.gossip(), dbg.accept_quest(id), dbg.turn_in_quest(id), dbg.abandon_quest(id). " +
  "Guide-addon helpers -- the addon's OWN parse of a guide, which the offline importer " +
  "cannot reach: dbg.guides() (which addons are loaded -- call this first, every " +
  "core.addons namespace exists whether or not the addon does), dbg.rxp() (RestedXP " +
  "step + goals + stickies + waypoints in one call), dbg.rxp_step(), dbg.rxp_waypoints(), " +
  "dbg.rxp_objectives(id), dbg.zygor(), dbg.questie(id?). NOTE: these are a CURSOR on the " +
  "addon's current position, not a queryable corpus -- there is no call that returns every " +
  "step of a guide, and waypoints are normalized 0-1 per map_id with no Z. " +
  "State helpers: dbg.help(), dbg.player_info(), dbg.target_info(), dbg.auras(unit), " +
  "dbg.bag_scan(), dbg.nearby(range, filter), dbg.inspect(path), dbg.log_tail(n). " +
  "TRANSPORT LIMITS: double quotes and backslash escapes in `command` corrupt the payload " +
  "-- use single-quoted Lua strings and avoid escape sequences.",
  {
    command: z.string().describe("Lua-style call, e.g. 'core.get_ping()' or 'player:get_health()'"),
    timeout: z.number().optional().describe("Timeout in ms (default 10000)"),
  },
  async ({ command, timeout }) => {
    try {
      const raw = await queueAndWait(command, timeout || 10000);
      const { text, isError } = formatResult(raw);
      return { content: [{ type: "text", text }], isError };
    } catch (err) {
      totalErrors++;
      return {
        content: [{ type: "text", text: `Error executing '${command}': ${err.message}` }],
        isError: true,
      };
    }
  }
);

mcp.tool(
  "game_multi_eval",
  "Execute multiple SDK calls in a single game tick and return all results. " +
  "Preferred over repeated game_eval when you need a consistent snapshot -- every command " +
  "observes the same frame, and you pay one round-trip instead of N. " +
  "Example: ['player:get_health()', 'player:get_position()', 'dbg.quest_log()']",
  {
    commands: z.array(z.string()).describe("Array of Lua-style calls to execute"),
    timeout: z.number().optional().describe("Timeout in ms (default 15000)"),
  },
  async ({ commands, timeout }) => {
    if (!commands || commands.length === 0) {
      return { content: [{ type: "text", text: "Error: empty commands array" }], isError: true };
    }

    try {
      const raw = await queueMultiAndWait(commands, timeout || 15000);
      let parsed;
      try {
        parsed = JSON.parse(raw);
      } catch {
        return { content: [{ type: "text", text: cap(raw) }] };
      }

      if (parsed.ok === false) {
        return { content: [{ type: "text", text: `Error: ${parsed.error}` }], isError: true };
      }

      const lines = (parsed.results || []).map((r, i) => {
        const cmd = commands[i] || `command[${i}]`;
        if (!r.ok) return `[${i + 1}] ${cmd}\n    => ERROR: ${r.error}`;
        const valueStr = typeof r.value === "object"
          ? JSON.stringify(r.value, null, 2)
          : String(r.value);
        return `[${i + 1}] ${cmd}\n    => ${valueStr}`;
      });

      return { content: [{ type: "text", text: cap(lines.join("\n\n")) }] };
    } catch (err) {
      totalErrors++;
      return {
        content: [{ type: "text", text: `Error executing batch (${commands.length} commands): ${err.message}` }],
        isError: true,
      };
    }
  }
);

mcp.tool(
  "game_bridge_status",
  "Report bridge health without touching the game: server version, whether the plugin has " +
  "ever connected, when it last polled, and queue depth. Check this FIRST when game_eval " +
  "times out -- it distinguishes 'game not running' from 'command failed'.",
  {},
  async () => {
    const s = bridgeStatus();
    const connected = s.lastStartup
      ? `plugin v${s.lastStartup.version} build=${s.lastStartup.build} (connected ${s.lastStartup.time})`
      : "plugin has NEVER connected -- is the game running with LxDebug loaded?";
    const polling = s.lastPollTime ? `last poll ${s.lastPollTime}` : "no polls received";
    return {
      content: [{
        type: "text",
        text: `lx-debug v${s.server_version} on port ${s.port}\n${connected}\n${polling}\n` +
              `queue: ${s.pending} pending, ${s.waiting} awaiting result\n` +
              `totals: ${s.totalCommands} commands, ${s.totalErrors} errors, ${s.totalDropped} dropped`,
      }],
    };
  }
);

// ---------------------------------------------------------------------------
// API reference search
// ---------------------------------------------------------------------------
let docSectionCache = null;

/** Split every doc file into `### heading` sections, once, lazily. */
function loadDocSections() {
  if (docSectionCache) return docSectionCache;

  const sections = [];
  const walk = (dir) => {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith(".md")) {
        const rel = path.relative(DOCS_PATH, full);
        const text = fs.readFileSync(full, "utf-8");
        // Keep the file preamble as its own section so overview prose is
        // searchable alongside the per-function entries.
        const parts = text.split(/^###\s+/m);
        sections.push({ file: rel, heading: "(overview)", body: parts[0] });
        for (const part of parts.slice(1)) {
          const nl = part.indexOf("\n");
          sections.push({
            file: rel,
            heading: (nl === -1 ? part : part.slice(0, nl)).replace(/`/g, "").trim(),
            body: nl === -1 ? "" : part.slice(nl + 1),
          });
        }
      }
    }
  };
  walk(DOCS_PATH);
  docSectionCache = sections;
  return sections;
}

function searchDocs(query, limit) {
  const terms = query.toLowerCase().split(/[^a-z0-9_]+/).filter(Boolean);
  if (terms.length === 0) return [];

  const scored = [];
  for (const s of loadDocSections()) {
    const heading = s.heading.toLowerCase();
    const body = s.body.toLowerCase();
    let score = 0;
    for (const t of terms) {
      // A heading hit is what the caller almost always wants -- weight it well
      // above an incidental mention in prose.
      if (heading === t) score += 100;
      else if (heading.includes(t)) score += 20;
      if (body.includes(t)) score += 1;
    }
    if (score > 0) scored.push({ ...s, score });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, limit);
}

mcp.tool(
  "game_api_docs",
  "Search the Sylvannas API reference for exact signatures BEFORE calling game_eval. " +
  "Covers the whole SDK (~750 entries across core, game_object, quests, spellbook, input, " +
  "object_manager, navigation, events, enums, geometry, ...). " +
  "Use this whenever you are unsure a method exists or what arguments it takes -- the SDK " +
  "fails silently on unknown methods, so a guessed name returns empty data rather than an " +
  "error. Examples: 'get_power', 'quest log objectives', 'how do I read buffs', 'power_type enum'.",
  {
    query: z.string().describe("Symbol name or natural-language question, e.g. 'get_buffs' or 'power type enum'"),
    limit: z.number().optional().describe("Max sections to return (default 5)"),
  },
  async ({ query, limit }) => {
    try {
      const hits = searchDocs(query, limit || 5);
      if (hits.length === 0) {
        return {
          content: [{
            type: "text",
            text: `No API documentation matched '${query}'.\n` +
                  `If the symbol truly does not exist, do NOT call it -- the SDK returns nil ` +
                  `rather than erroring, which shows up as empty data.\n` +
                  `Docs root: ${DOCS_PATH}`,
          }],
        };
      }
      const text = hits
        .map((h) => `### ${h.heading}\n(${h.file})\n\n${h.body.trim()}`)
        .join("\n\n---\n\n");
      return { content: [{ type: "text", text: cap(text) }] };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Error searching API docs: ${err.message}` }],
        isError: true,
      };
    }
  }
);

mcp.tool(
  "game_read_log",
  "Read the last N lines of a log file in scripts_log/. Direct disk read, no game round-trip. " +
  "For LxDebug's own structured log use game_read_data with 'lx_debug/lx_debug.log'.",
  {
    filename: z.string().describe("Log filename, e.g. 'lx_tbc_hunter.log'"),
    lines: z.number().optional().describe("Number of lines from the end (default: all)"),
  },
  async ({ filename, lines }) => {
    try {
      const content = readFileSafe(SCRIPTS_LOG, filename, lines);
      return { content: [{ type: "text", text: cap(content || "(empty)") }] };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Error reading log '${filename}': ${err.message}` }],
        isError: true,
      };
    }
  }
);

mcp.tool(
  "game_read_data",
  "Read a file from scripts_data/. Direct disk read, no game round-trip. " +
  "Common paths: 'lx_debug/lx_debug.log', 'lx_debug/async_result.json', " +
  "'lx_debug/bag_scan.json', 'lx_debug/nearby.json', 'lx_debug/quest_log.json'.",
  {
    path: z.string().describe("Relative path under scripts_data/"),
  },
  async ({ path: filePath }) => {
    try {
      const content = readFileSafe(SCRIPTS_DATA, filePath);
      return { content: [{ type: "text", text: cap(content || "(empty)") }] };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Error reading data '${filePath}': ${err.message}` }],
        isError: true,
      };
    }
  }
);

mcp.tool(
  "game_write_data",
  "Write a file to scripts_data/. Direct disk write, no game round-trip. " +
  "Useful for handing a compiled runtime profile or test fixture to the game. " +
  "Creates parent directories as needed.",
  {
    path: z.string().describe("Relative path under scripts_data/"),
    content: z.string().describe("File content to write"),
  },
  async ({ path: filePath, content }) => {
    try {
      const safePath = resolveInside(SCRIPTS_DATA, filePath);
      fs.mkdirSync(path.dirname(safePath), { recursive: true });
      fs.writeFileSync(safePath, content, "utf-8");
      return { content: [{ type: "text", text: `Written ${content.length} bytes to ${filePath}` }] };
    } catch (err) {
      return {
        content: [{ type: "text", text: `Error writing '${filePath}': ${err.message}` }],
        isError: true,
      };
    }
  }
);

mcp.tool(
  "game_wait_reload",
  "Wait for the in-game LxDebug plugin to (re)load and report its version. " +
  "Use AFTER telling the user to reload the plugin. Returns plugin version and build.",
  {
    timeout: z.number().optional().describe("Timeout in ms (default 30000)"),
    wait_fresh: z.boolean().optional().describe("If true, always wait for a NEW startup ping (default true)"),
  },
  async ({ timeout, wait_fresh }) => {
    const timeoutMs = timeout || 30000;
    const fresh = wait_fresh !== false;

    if (!fresh && lastStartup) {
      return {
        content: [{ type: "text", text: `Plugin already connected: v${lastStartup.version} build=${lastStartup.build} at ${lastStartup.time}` }],
      };
    }

    try {
      const info = await new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          startupWaiters = startupWaiters.filter((w) => w.resolve !== resolve);
          reject(new Error(`Timeout after ${timeoutMs}ms waiting for plugin reload. Is the game running?`));
        }, timeoutMs);
        startupWaiters.push({ resolve, timer });
      });
      return {
        content: [{ type: "text", text: `Plugin reloaded: v${info.version} build=${info.build} at ${info.time}` }],
      };
    } catch (err) {
      return { content: [{ type: "text", text: `Error: ${err.message}` }], isError: true };
    }
  }
);

// ---------------------------------------------------------------------------
// Start MCP transport
// ---------------------------------------------------------------------------
const transport = new StdioServerTransport();
await mcp.connect(transport);
process.stderr.write(`[lx-debug] MCP server v${VERSION} connected via stdio\n`);
