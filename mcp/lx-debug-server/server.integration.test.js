// End-to-end: a real MCP client drives the server over stdio while a fake
// game plugin polls the HTTP side and posts results back. Exercises the whole
// queue -> poll -> execute -> POST /result loop without a game client.

import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const PORT = 7799; // off the default so a live bridge doesn't collide
const BASE = `http://127.0.0.1:${PORT}`;

/** Minimal stand-in for the in-game plugin: poll, evaluate, post back. */
function startFakePlugin(evaluate) {
  let running = true;
  const loop = (async () => {
    while (running) {
      let cmd;
      try {
        cmd = await (await fetch(`${BASE}/poll`)).json();
      } catch {
        await new Promise((r) => setTimeout(r, 20));
        continue;
      }
      if (!cmd.id) {
        await new Promise((r) => setTimeout(r, 10));
        continue;
      }
      const body = JSON.stringify(evaluate(cmd));
      await fetch(`${BASE}/result?id=${cmd.id}`, { method: "POST", body });
    }
  })();
  return async () => {
    running = false;
    await loop;
  };
}

async function withBridge(evaluate, fn) {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: ["server.js"],
    env: { ...process.env, LX_DEBUG_PORT: String(PORT) },
    stderr: "ignore",
  });
  const client = new Client({ name: "test", version: "1.0.0" });
  await client.connect(transport);

  // Wait for the HTTP listener to bind.
  for (let i = 0; i < 100; i++) {
    try {
      await fetch(`${BASE}/health`);
      break;
    } catch {
      await new Promise((r) => setTimeout(r, 20));
    }
  }

  const stopPlugin = startFakePlugin(evaluate);
  try {
    await fn(client);
  } finally {
    await stopPlugin();
    await client.close();
  }
}

test("game_eval round-trips a single command through the plugin", async () => {
  await withBridge(
    (cmd) => {
      assert.equal(cmd.path, "core.get_ping");
      return { ok: true, value: 42, type: "number" };
    },
    async (client) => {
      const res = await client.callTool({
        name: "game_eval",
        arguments: { command: "core.get_ping()" },
      });
      assert.equal(res.content[0].text, "[number] 42");
      assert.notEqual(res.isError, true);
    }
  );
});

test("game_eval surfaces an in-game error as isError", async () => {
  await withBridge(
    () => ({ ok: false, error: "no valid player" }),
    async (client) => {
      const res = await client.callTool({
        name: "game_eval",
        arguments: { command: "player:get_health()" },
      });
      assert.equal(res.isError, true);
      assert.match(res.content[0].text, /no valid player/);
    }
  );
});

test("game_eval routes multi-statement Lua through lua_exec", async () => {
  await withBridge(
    (cmd) => {
      assert.equal(cmd.lua_exec, true);
      assert.match(cmd.code, /^local p = /);
      return { ok: true, value: 1.5, type: "number" };
    },
    async (client) => {
      const res = await client.callTool({
        name: "game_eval",
        arguments: { command: "local p = player:get_position() return p.x" },
      });
      assert.equal(res.content[0].text, "[number] 1.5");
    }
  );
});

test("game_multi_eval batches commands into one tick", async () => {
  await withBridge(
    (cmd) => {
      assert.equal(cmd.multi, true);
      assert.equal(cmd.commands.length, 2);
      return {
        ok: true,
        type: "multi",
        results: [
          { ok: true, value: 100 },
          { ok: false, error: "no target" },
        ],
      };
    },
    async (client) => {
      const res = await client.callTool({
        name: "game_multi_eval",
        arguments: { commands: ["player:get_health()", "target:get_health()"] },
      });
      const text = res.content[0].text;
      assert.match(text, /\[1\] player:get_health\(\)\n {4}=> 100/);
      assert.match(text, /\[2\] target:get_health\(\)\n {4}=> ERROR: no target/);
    }
  );
});

test("game_eval times out with a diagnostic when nothing polls", async () => {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: ["server.js"],
    env: { ...process.env, LX_DEBUG_PORT: String(PORT + 1) },
    stderr: "ignore",
  });
  const client = new Client({ name: "test", version: "1.0.0" });
  await client.connect(transport);
  try {
    const res = await client.callTool({
      name: "game_eval",
      arguments: { command: "core.get_ping()", timeout: 300 },
    });
    assert.equal(res.isError, true);
    assert.match(res.content[0].text, /never polled/);
  } finally {
    await client.close();
  }
});

test("game_bridge_status reports plugin connectivity", async () => {
  await withBridge(
    () => ({ ok: true, value: 1, type: "number" }),
    async (client) => {
      // Force a round-trip so the plugin has demonstrably polled.
      await client.callTool({ name: "game_eval", arguments: { command: "core.get_ping()" } });

      const res = await client.callTool({ name: "game_bridge_status", arguments: {} });
      const text = res.content[0].text;
      assert.match(text, /lx-debug v3\.0\.0/);
      // The fake plugin polls but never sends /startup.
      assert.match(text, /NEVER connected/);
      assert.match(text, /last poll/);
    }
  );
});

test("game_write_data and game_read_data round-trip under the data root", async () => {
  const tmp = await import("node:fs/promises").then((fs) =>
    fs.mkdtemp((process.env.TMPDIR || "/tmp") + "/lxdata-")
  );
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: ["server.js"],
    env: { ...process.env, LX_DEBUG_PORT: String(PORT + 2), SCRIPTS_DATA_PATH: tmp },
    stderr: "ignore",
  });
  const client = new Client({ name: "test", version: "1.0.0" });
  await client.connect(transport);
  try {
    await client.callTool({
      name: "game_write_data",
      arguments: { path: "lx_debug/probe.json", content: '{"hello":1}' },
    });
    const read = await client.callTool({
      name: "game_read_data",
      arguments: { path: "lx_debug/probe.json" },
    });
    assert.equal(read.content[0].text, '{"hello":1}');

    const escaped = await client.callTool({
      name: "game_read_data",
      arguments: { path: "../../etc/passwd" },
    });
    assert.equal(escaped.isError, true);
    assert.match(escaped.content[0].text, /Path traversal denied/);
  } finally {
    await client.close();
  }
});

test("game_api_docs finds a real symbol and its signature", async () => {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: ["server.js"],
    env: { ...process.env, LX_DEBUG_PORT: String(PORT + 3) },
    stderr: "ignore",
  });
  const client = new Client({ name: "test", version: "1.0.0" });
  await client.connect(transport);
  try {
    const res = await client.callTool({
      name: "game_api_docs",
      arguments: { query: "get_power" },
    });
    const text = res.content[0].text;
    assert.match(text, /get_power\(power_type/);
    assert.match(text, /game-object\.md/);

    // The exact drift that broke v2: these must be findable / not findable.
    const buffs = await client.callTool({
      name: "game_api_docs",
      arguments: { query: "get_buffs" },
    });
    assert.match(buffs.content[0].text, /buff_name/);

    const bogus = await client.callTool({
      name: "game_api_docs",
      arguments: { query: "zzzznotarealsymbol" },
    });
    assert.match(bogus.content[0].text, /No API documentation matched/);
  } finally {
    await client.close();
  }
});
