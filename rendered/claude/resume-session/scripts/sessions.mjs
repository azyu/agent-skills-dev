#!/usr/bin/env node
// resume-session: deterministic Claude Code transcript scanner / extractor.
// Zero external deps (node:fs / node:readline / node:path / node:os only).
//
// Modes:
//   list [keyword] [--limit N] [--scan N] [--keep-current]
//       Rank past sessions of the CURRENT project. Excludes the active
//       session (newest mtime) unless --keep-current. Prints a compact,
//       machine-readable candidate list (one absolute path per row).
//   extract <session-file.jsonl | sessionId> [--with-thinking]
//       Stream one session and print a condensed, ordered transcript
//       (user prompts + assistant text + one-line tool calls + errors +
//       changed-file footer). Designed to be read by a summarizing subagent.
//
// Target dir: ~/.claude/projects/<escaped-cwd>/  where escaped-cwd is the
// project root path with every non-alphanumeric char replaced by '-'.

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import readline from "node:readline";

// tool_use input keys to surface (first match wins) as the one-line arg.
const TOOL_KEYS = [
  "file_path",
  "path",
  "notebook_path",
  "command",
  "pattern",
  "query",
  "url",
  "description",
  "prompt",
];
// tool_use names that mutate files -> collected into the changed-files footer.
const EDIT_TOOLS = new Set([
  "Edit",
  "Write",
  "MultiEdit",
  "NotebookEdit",
  "create_file",
  "edit_file",
  "write_file",
]);
const TEXT_CAP = 8000; // per-block safety cap; rarely hit, keeps output bounded.

function projectsDir() {
  const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const escaped = root.replace(/[^a-zA-Z0-9]/g, "-");
  return path.join(os.homedir(), ".claude", "projects", escaped);
}

function fmtAge(ms) {
  const diff = Date.now() - ms;
  const m = Math.round(diff / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.round(m / 60);
  if (h < 48) return `${h}h ago`;
  return `${Math.round(h / 24)}d ago`;
}

function fmtSize(b) {
  if (b < 1024) return `${b}B`;
  if (b < 1048576) return `${Math.round(b / 1024)}KB`;
  return `${(b / 1048576).toFixed(1)}MB`;
}

function escRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// tool_result.content may be a string or an array of text blocks.
function asText(content) {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((b) => (typeof b === "string" ? b : (b?.text ?? "")))
      .join("\n");
  }
  return "";
}

// ai-title value location is not fully documented; probe likely fields.
function aiTitleOf(line) {
  const cands = [
    line.title,
    line.aiTitle,
    line.summary,
    typeof line.message === "string" ? line.message : line.message?.content,
    line.content,
  ];
  for (const c of cands) if (typeof c === "string" && c.trim()) return c.trim();
  return null;
}

function toolArg(input) {
  if (!input || typeof input !== "object") return "";
  for (const k of TOOL_KEYS) if (input[k] != null) return String(input[k]);
  return "";
}

function oneLine(s, n) {
  return s.replace(/\s+/g, " ").trim().slice(0, n);
}

// Strip slash-command / system wrapper blocks so the title falls back to the
// first MEANINGFUL human prompt (sessions started via /command otherwise show
// "<local-command-caveat>Caveat..." as their title).
function cleanPrompt(t) {
  return t
    .replace(/<local-command-[^>]*>[\s\S]*?<\/local-command-[^>]*>/g, " ")
    .replace(/<command-[^>]*>[\s\S]*?<\/command-[^>]*>/g, " ")
    .replace(/<command-[^>]*\/>/g, " ")
    .replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, " ")
    .trim();
}

function isMeaningful(t) {
  const c = cleanPrompt(t);
  return c.length > 0 && !c.startsWith("<");
}

async function* lines(file) {
  const rl = readline.createInterface({
    input: fs.createReadStream(file),
    crlfDelay: Infinity,
  });
  for await (const line of rl) {
    if (!line.trim()) continue;
    try {
      yield JSON.parse(line);
    } catch {
      // skip malformed lines
    }
  }
}

async function scanMeta(file, keyword) {
  const kw = keyword ? keyword.toLowerCase() : null;
  const re = kw ? new RegExp(escRe(kw), "g") : null;
  let title = null;
  let firstUserRaw = null;
  let firstUserClean = null;
  let branch = null;
  let firstTs = null;
  let lastTs = null;
  let userCount = 0;
  let asstCount = 0;
  let matches = 0;

  for await (const o of lines(file)) {
    if (o.timestamp) {
      if (!firstTs) firstTs = o.timestamp;
      lastTs = o.timestamp;
    }
    if (!branch && o.gitBranch) branch = o.gitBranch;
    if (!title && o.type === "ai-title") title = aiTitleOf(o);

    if (o.type === "user" && typeof o.message?.content === "string") {
      userCount++;
      const t = o.message.content;
      if (!firstUserRaw) firstUserRaw = t;
      if (!firstUserClean && isMeaningful(t)) firstUserClean = cleanPrompt(t);
      if (re) matches += (t.toLowerCase().match(re) || []).length;
    } else if (o.type === "assistant" && Array.isArray(o.message?.content)) {
      asstCount++;
      if (re) {
        for (const b of o.message.content) {
          if (b?.type === "text" && b.text)
            matches += (b.text.toLowerCase().match(re) || []).length;
        }
      }
    }
  }

  let fallback = firstUserClean;
  if (!fallback && firstUserRaw) {
    // user messages existed but were all command/system boilerplate
    fallback = cleanPrompt(firstUserRaw) || "(command-only session)";
  }
  return {
    title: title || fallback || "(untitled)",
    branch: branch || "?",
    firstTs,
    lastTs,
    userCount,
    asstCount,
    matches,
  };
}

async function cmdList(args) {
  const keyword = args.positionals[0] || null;
  const limit = args.limit ?? 10;
  const scan = args.scan ?? 30;
  const dir = projectsDir();

  if (!fs.existsSync(dir)) {
    console.error(`No transcript directory for this project:\n  ${dir}`);
    process.exit(2);
  }

  let files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".jsonl"))
    .map((f) => {
      const p = path.join(dir, f);
      const st = fs.statSync(p);
      return { p, f, mtime: st.mtimeMs, size: st.size };
    })
    .sort((a, b) => b.mtime - a.mtime);

  if (!files.length) {
    console.error(`No session files (.jsonl) found: ${dir}`);
    process.exit(2);
  }

  let dropped = null;
  if (!args.keepCurrent) {
    dropped = files[0]; // newest == currently active session (being appended)
    files = files.slice(1);
  }
  if (!files.length) {
    console.error("No past sessions other than the current active one.");
    process.exit(2);
  }

  const scanned = files.slice(0, scan);
  const rows = [];
  for (const f of scanned) {
    rows.push({ ...f, ...(await scanMeta(f.p, keyword)) });
  }

  let ranked;
  if (keyword) {
    ranked = rows
      .filter((r) => r.matches > 0)
      .sort((a, b) => b.matches - a.matches || b.mtime - a.mtime);
  } else {
    ranked = rows; // already mtime DESC
  }

  console.log(`session dir : ${dir}`);
  if (dropped)
    console.log(
      `excluded    : current session [${fmtAge(dropped.mtime)}] ${dropped.f}`,
    );
  if (scanned.length < files.length) {
    console.log(
      `scanned     : most recent ${scanned.length} of ${files.length} (widen with --scan N)`,
    );
  }
  if (keyword) console.log(`keyword     : "${keyword}"`);
  console.log("");

  const top = ranked.slice(0, limit);
  if (!top.length) {
    console.log(
      keyword
        ? `No sessions match '${keyword}'. Try again without a keyword.`
        : "No sessions to show.",
    );
    return;
  }

  top.forEach((r, i) => {
    const m = keyword ? ` · matches=${r.matches}` : "";
    console.log(
      `[${i + 1}] ${fmtAge(r.mtime)} · "${oneLine(r.title, 70)}" · branch=${r.branch} · ${r.userCount}u/${r.asstCount}a · ${fmtSize(r.size)}${m}`,
    );
    console.log(`    ${r.p}`);
  });
}

async function cmdExtract(args) {
  const ref = args.positionals[0];
  if (!ref) {
    console.error(
      "usage: sessions.mjs extract <session-file.jsonl | sessionId>",
    );
    process.exit(2);
  }

  let p = ref;
  if (!fs.existsSync(p)) {
    const cand = path.join(
      projectsDir(),
      ref.endsWith(".jsonl") ? ref : `${ref}.jsonl`,
    );
    if (fs.existsSync(cand)) p = cand;
    else {
      console.error(`File not found: ${ref}`);
      process.exit(2);
    }
  }

  const out = [];
  const changed = new Set();
  let title = null;
  let firstUserClean = null;
  let sessionId = null;
  let branch = null;
  let firstTs = null;
  let lastTs = null;
  let userCount = 0;
  let asstCount = 0;

  for await (const o of lines(p)) {
    if (o.sessionId && !sessionId) sessionId = o.sessionId;
    if (o.timestamp) {
      if (!firstTs) firstTs = o.timestamp;
      lastTs = o.timestamp;
    }
    if (!branch && o.gitBranch) branch = o.gitBranch;
    if (o.type === "ai-title" && !title) title = aiTitleOf(o);

    if (o.type === "user" && typeof o.message?.content === "string") {
      userCount++;
      if (!firstUserClean && isMeaningful(o.message.content)) {
        firstUserClean = cleanPrompt(o.message.content);
      }
      out.push(`[USER] ${o.message.content.trim()}`);
    } else if (o.type === "user" && Array.isArray(o.message?.content)) {
      for (const b of o.message.content) {
        if (b?.type === "tool_result" && b.is_error === true) {
          const t = oneLine(asText(b.content), 200);
          if (t) out.push(`[ERROR] ${t}`);
        }
      }
    } else if (
      o.type === "assistant" &&
      typeof o.message?.content === "string"
    ) {
      asstCount++;
      out.push(`[ASSISTANT] ${o.message.content.trim().slice(0, TEXT_CAP)}`);
    } else if (o.type === "assistant" && Array.isArray(o.message?.content)) {
      asstCount++;
      for (const b of o.message.content) {
        if (b?.type === "text" && b.text?.trim()) {
          let t = b.text.trim();
          if (t.length > TEXT_CAP) t = `${t.slice(0, TEXT_CAP)} …[truncated]`;
          out.push(`[ASSISTANT] ${t}`);
        } else if (
          b?.type === "thinking" &&
          args.withThinking &&
          b.thinking?.trim()
        ) {
          let t = b.thinking.trim();
          if (t.length > TEXT_CAP) t = `${t.slice(0, TEXT_CAP)} …[truncated]`;
          out.push(`[THINKING] ${t}`);
        } else if (b?.type === "tool_use") {
          const arg = oneLine(toolArg(b.input), 120);
          out.push(`[TOOL] ${b.name}${arg ? `(${arg})` : ""}`);
          if (EDIT_TOOLS.has(b.name)) {
            const fp =
              b.input?.file_path || b.input?.path || b.input?.notebook_path;
            if (fp) changed.add(String(fp));
          }
        }
      }
    }
  }

  const header = [
    "# SESSION SUMMARY SOURCE (condensed transcript)",
    `title:   ${title || (firstUserClean ? oneLine(firstUserClean, 80) : "(untitled)")}`,
    `session: ${sessionId || path.basename(p, ".jsonl")}`,
    `branch:  ${branch || "?"}`,
    `time:    ${firstTs && lastTs ? `${firstTs} -> ${lastTs}` : "?"}`,
    `counts:  ${userCount} user / ${asstCount} assistant turns`,
    `file:    ${p}`,
    "",
    "---",
    "",
  ].join("\n");

  process.stdout.write(header);
  process.stdout.write(out.join("\n\n"));
  if (changed.size) {
    process.stdout.write(
      `\n\n---\nCHANGED FILES (${changed.size}):\n${[...changed]
        .sort()
        .map((f) => `  ${f}`)
        .join("\n")}\n`,
    );
  } else {
    process.stdout.write(
      "\n\n---\nCHANGED FILES: (none detected via Edit/Write tool calls)\n",
    );
  }
}

function parseArgs(argv) {
  const positionals = [];
  let limit;
  let scan;
  let keepCurrent = false;
  let withThinking = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--limit") limit = parseInt(argv[++i], 10);
    else if (a === "--scan") scan = parseInt(argv[++i], 10);
    else if (a === "--keep-current") keepCurrent = true;
    else if (a === "--with-thinking") withThinking = true;
    else positionals.push(a);
  }
  return { positionals, limit, scan, keepCurrent, withThinking };
}

const [, , mode, ...rest] = process.argv;
const args = parseArgs(rest);

if (mode === "list") {
  await cmdList(args);
} else if (mode === "extract") {
  await cmdExtract(args);
} else {
  console.error(`resume-session sessions.mjs
usage:
  node sessions.mjs list [keyword] [--limit N] [--scan N] [--keep-current]
  node sessions.mjs extract <session-file.jsonl | sessionId> [--with-thinking]`);
  process.exit(2);
}
