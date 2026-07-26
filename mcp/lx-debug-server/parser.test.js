import test from "node:test";
import assert from "node:assert/strict";
import { parseCommand, parseArgs, isRawLua } from "./parser.js";

// ---------------------------------------------------------------------------
// parseArgs
// ---------------------------------------------------------------------------
test("parseArgs: empty", () => {
  assert.deepEqual(parseArgs(""), []);
  assert.deepEqual(parseArgs("   "), []);
});

test("parseArgs: scalars", () => {
  assert.deepEqual(parseArgs("1, 2.5, -3"), [1, 2.5, -3]);
  assert.deepEqual(parseArgs("true, false, nil"), [true, false, null]);
});

test("parseArgs: quoted strings keep separators verbatim", () => {
  assert.deepEqual(parseArgs('"a,b"'), ["a,b"]);
  assert.deepEqual(parseArgs("'x y'"), ["x y"]);
  assert.deepEqual(parseArgs('"say \\"hi\\""'), ['say "hi"']);
});

test("parseArgs: bare identifiers pass through as strings", () => {
  assert.deepEqual(parseArgs("player, core.input"), ["player", "core.input"]);
});

test("parseArgs: table literal is kept raw for the Lua side", () => {
  assert.deepEqual(parseArgs("{x=1,y=2,z=3}"), ["{x=1,y=2,z=3}"]);
});

test("parseArgs: nested call becomes an __eval sub-command", () => {
  const [arg] = parseArgs("core.object_manager.get_local_player()");
  assert.equal(arg.__eval, true);
  assert.equal(arg.path, "core.object_manager.get_local_player");
  assert.equal(arg.root, "core");
});

// ---------------------------------------------------------------------------
// parseCommand
// ---------------------------------------------------------------------------
test("parseCommand: no-arg function", () => {
  const cmd = parseCommand("core.get_ping()", "cmd_1");
  assert.equal(cmd.id, "cmd_1");
  assert.equal(cmd.path, "core.get_ping");
  assert.equal(cmd.root, "core");
  assert.equal(cmd.method, false);
  assert.deepEqual(cmd.args, []);
});

test("parseCommand: method call sets method=true", () => {
  const cmd = parseCommand("player:get_health()", "cmd_2");
  assert.equal(cmd.method, true);
  assert.equal(cmd.root, "player");
});

test("parseCommand: bare path with no parens", () => {
  const cmd = parseCommand("dbg", "cmd_3");
  assert.equal(cmd.path, "dbg");
  assert.deepEqual(cmd.args, []);
});

test("parseCommand: chained method call", () => {
  const cmd = parseCommand("player:get_position():dist_to(target)", "cmd_4");
  assert.equal(cmd.path, "player:get_position");
  assert.equal(cmd.chain.length, 1);
  assert.deepEqual(cmd.chain[0].segments, ["dist_to"]);
  assert.equal(cmd.chain[0].method, true);
  assert.deepEqual(cmd.chain[0].args, ["target"]);
});

// Regression: paren counting used to ignore quotes, so a lone "(" inside a
// string literal unbalanced the scan and truncated the argument.
test("parseCommand: unbalanced paren inside a string literal", () => {
  const cmd = parseCommand('dbg.log_search("(")', "cmd_5");
  assert.equal(cmd.path, "dbg.log_search");
  assert.deepEqual(cmd.args, ["("]);
});

test("parseCommand: unbalanced brace inside a string literal", () => {
  const cmd = parseCommand('dbg.log_search("{")', "cmd_6");
  assert.deepEqual(cmd.args, ["{"]);
});

test("parseCommand: balanced parens inside a string literal", () => {
  const cmd = parseCommand('dbg.log_search("(NAV)")', "cmd_7");
  assert.deepEqual(cmd.args, ["(NAV)"]);
});

test("parseCommand: vec3 table literal argument", () => {
  const cmd = parseCommand("dbg.nav_move_to({x=1,y=2,z=3})", "cmd_8");
  assert.deepEqual(cmd.args, ["{x=1,y=2,z=3}"]);
});

// ---------------------------------------------------------------------------
// isRawLua
// ---------------------------------------------------------------------------
test("isRawLua: plain SDK calls are not raw Lua", () => {
  assert.equal(isRawLua("core.get_ping()"), false);
  assert.equal(isRawLua("player:get_health()"), false);
  assert.equal(isRawLua("dbg.nearby(30, 'hostile')"), false);
});

test("isRawLua: statements and blocks are raw Lua", () => {
  assert.equal(isRawLua("local x = 1 return x"), true);
  assert.equal(isRawLua("for i=1,10 do end"), true);
  assert.equal(isRawLua("return player:get_health()"), true);
  assert.equal(isRawLua("(function() return 1 end)()"), true);
  assert.equal(isRawLua("x = 1"), true);
});

// Regression: a semicolon inside a string argument used to be read as a
// statement separator, routing an ordinary call down the loadstring path.
test("isRawLua: semicolon inside a string literal is not a statement break", () => {
  assert.equal(isRawLua('dbg.log_search("a; b")'), false);
});

test("isRawLua: equality comparison is not an assignment", () => {
  assert.equal(isRawLua("x == 1"), false);
});
