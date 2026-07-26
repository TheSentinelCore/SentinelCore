// lx-debug parser -- turns a Lua-style call string into a command object the
// in-game plugin can resolve against the Sylvannas SDK.
//
// Kept free of I/O and module-level state so it can be unit tested offline.

// ---------------------------------------------------------------------------
// Quote-aware scanning
//
// All bracket matching below must skip over string literals. Without this a
// lone "(" or "{" inside an argument string unbalances the scan and silently
// truncates the argument.
// ---------------------------------------------------------------------------

/** Index just past the closing quote of the literal starting at `open`. */
function skipString(str, open) {
  const quote = str[open];
  let i = open + 1;
  while (i < str.length) {
    if (str[i] === "\\") i += 2;
    else if (str[i] === quote) return i + 1;
    else i++;
  }
  return i;
}

/**
 * Index just past the bracket closing the one at `open`, skipping strings.
 * Returns str.length when the brackets never balance.
 */
function findClose(str, open) {
  let depth = 0;
  let i = open;
  while (i < str.length) {
    const ch = str[i];
    if (ch === '"' || ch === "'") {
      i = skipString(str, i);
      continue;
    }
    if (ch === "(" || ch === "{") depth++;
    else if (ch === ")" || ch === "}") {
      depth--;
      if (depth === 0) return i + 1;
    }
    i++;
  }
  return str.length;
}

/** True when `str` contains `ch` outside of any string literal. */
function hasOutsideString(str, predicate) {
  let i = 0;
  while (i < str.length) {
    const ch = str[i];
    if (ch === '"' || ch === "'") {
      i = skipString(str, i);
      continue;
    }
    if (predicate(str, i)) return true;
    i++;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------
export function parseArgs(raw) {
  const trimmed = raw.trim();
  if (!trimmed) return [];

  const args = [];
  let i = 0;
  while (i < trimmed.length) {
    while (i < trimmed.length && /[\s,]/.test(trimmed[i])) i++;
    if (i >= trimmed.length) break;

    const ch = trimmed[i];

    if (ch === '"' || ch === "'") {
      const end = skipString(trimmed, i);
      // Strip the surrounding quotes and unescape.
      const body = trimmed.substring(i + 1, end - 1);
      let out = "";
      for (let j = 0; j < body.length; j++) {
        if (body[j] === "\\" && j + 1 < body.length) {
          out += body[j + 1];
          j++;
        } else {
          out += body[j];
        }
      }
      args.push(out);
      i = end;
      continue;
    }

    if (ch === "{") {
      // Table literals are forwarded verbatim; the Lua side parses them so
      // that vec3 arguments become real vector_3 userdata.
      const end = findClose(trimmed, i);
      args.push(trimmed.substring(i, end));
      i = end;
      continue;
    }

    // Bare token: read until a top-level comma or an unmatched closer.
    let j = i;
    let depth = 0;
    while (j < trimmed.length) {
      const c = trimmed[j];
      if (c === '"' || c === "'") {
        j = skipString(trimmed, j);
        continue;
      }
      if (c === "(" || c === "{") depth++;
      else if (c === ")" || c === "}") {
        if (depth === 0) break;
        depth--;
      } else if (c === "," && depth === 0) break;
      j++;
    }

    const token = trimmed.substring(i, j).trim();
    if (token === "true") args.push(true);
    else if (token === "false") args.push(false);
    else if (token === "nil") args.push(null);
    else if (token !== "" && !isNaN(Number(token))) args.push(Number(token));
    else if (token.includes("(")) {
      // Nested call -- resolved recursively on the Lua side.
      args.push({ __eval: true, ...parseCommand(token) });
    } else args.push(token);
    i = j;
  }
  return args;
}

// ---------------------------------------------------------------------------
// Chained access: `:foo()`, `.bar`, `:baz(1)` following a call result
// ---------------------------------------------------------------------------
function parseChain(str) {
  const steps = [];
  let pos = 0;

  while (pos < str.length) {
    const delim = str[pos];
    if (delim !== "." && delim !== ":") break;
    pos++;

    let segStr = "";
    while (pos < str.length && str[pos] !== "(") {
      segStr += str[pos];
      pos++;
    }

    const isMethod = (delim + segStr).includes(":");
    const segments = segStr.split(/[.:]/);

    let stepArgs = [];
    if (pos < str.length && str[pos] === "(") {
      const end = findClose(str, pos);
      stepArgs = parseArgs(str.substring(pos + 1, end - 1));
      pos = end;
    }

    steps.push({ segments, args: stepArgs, method: isMethod });
  }

  return steps.length > 0 ? steps : undefined;
}

// ---------------------------------------------------------------------------
// Command parsing
// ---------------------------------------------------------------------------
export function parseCommand(input, id) {
  const trimmed = input.trim();

  const parenIdx = trimmed.indexOf("(");
  let pathStr, argsRaw, remainder;
  if (parenIdx === -1) {
    pathStr = trimmed;
    argsRaw = "";
    remainder = "";
  } else {
    pathStr = trimmed.substring(0, parenIdx);
    const end = findClose(trimmed, parenIdx);
    argsRaw = trimmed.substring(parenIdx + 1, end - 1);
    remainder = trimmed.substring(end);
  }

  const rootMatch = pathStr.match(/^([a-zA-Z_]\w*)/);
  const cmd = {
    path: pathStr,
    args: parseArgs(argsRaw),
    method: pathStr.includes(":"),
    root: rootMatch ? rootMatch[1] : "core",
  };
  if (id !== undefined) cmd.id = id;

  const chain = remainder.trim() ? parseChain(remainder.trim()) : undefined;
  if (chain) cmd.chain = chain;

  return cmd;
}

// ---------------------------------------------------------------------------
// Raw-Lua detection
//
// Anything that isn't a single expression has to go through loadstring on the
// game side rather than the path resolver.
// ---------------------------------------------------------------------------
export function isRawLua(command) {
  const t = command.trim();

  if (t.startsWith("(function")) return true;
  if (/^(local|do|for|if|while|repeat|return|function)\s/.test(t)) return true;

  // A statement separator outside of any string literal.
  if (hasOutsideString(t, (s, i) => s[i] === ";" && /\s*\w/.test(s.slice(i + 1)))) {
    return true;
  }

  // Assignment (but not an equality comparison).
  if (/^[a-zA-Z_]\w*\s*=[^=]/.test(t)) return true;

  return false;
}
