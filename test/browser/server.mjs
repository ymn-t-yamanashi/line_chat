// Harness for the browser suite: boots a real Phoenix dev server on a clean
// port and waits until it answers, then tears the whole process tree down.
// This file is not a `*.test.mjs` glob match, so `node --test` treats it as a
// plain helper.

import { spawn } from 'node:child_process';
import { closeSync, openSync, readdirSync, readFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

export const PORT = Number(process.env.LINE_CHAT_BROWSER_PORT ?? 4000);
export const BASE_URL = `http://127.0.0.1:${PORT}`;
const HEALTH_URL = `${BASE_URL}/api/health`;
const START_TIMEOUT_MS = Number(process.env.LINE_CHAT_BROWSER_TIMEOUT_MS ?? 90_000);
const STOP_TIMEOUT_MS = Number(process.env.LINE_CHAT_BROWSER_STOP_TIMEOUT_MS ?? 8_000);

// Server output goes to a file instead of pipes: pipes kept open by the parent
// would pin the `node --test` process after the suite finishes, and Phoenix
// children (beam, the esbuild watcher) inherit the descriptors anyway.
const LOG_FILE = path.join(os.tmpdir(), `line_chat_browser_server_${PORT}.log`);

async function healthStatus() {
  try {
    const response = await fetch(HEALTH_URL, { signal: AbortSignal.timeout(2_000) });
    return response.status;
  } catch {
    return 0;
  }
}

function tailLogs(limit = 4_000) {
  try {
    const text = readFileSync(LOG_FILE, 'utf8');
    return text.slice(Math.max(0, text.length - limit));
  } catch {
    return '(no server log)';
  }
}

function directChildren(pid) {
  const children = [];
  for (const entry of readdirSync('/proc').filter((name) => /^\d+$/.test(name))) {
    let stat;
    try {
      stat = readFileSync(`/proc/${entry}/stat`, 'utf8');
    } catch {
      continue;
    }
    // The comm field can contain spaces and parentheses, so parse from the last one.
    const fields = stat.slice(stat.lastIndexOf(')') + 1).trim().split(/\s+/);
    if (Number(fields[1]) === pid) children.push(Number(entry));
  }
  return children;
}

/** The whole process tree rooted at `rootPid`, including detached grandchildren. */
function descendantPids(rootPid) {
  const found = new Set([rootPid]);
  const queue = [rootPid];
  while (queue.length > 0) {
    for (const child of directChildren(queue.shift())) {
      if (!found.has(child)) {
        found.add(child);
        queue.push(child);
      }
    }
  }
  return [...found];
}

function killQuiet(pid, signal) {
  try {
    process.kill(pid, signal);
    return true;
  } catch {
    return false;
  }
}

function alive(pid) {
  return killQuiet(pid, 0);
}

/** Boots `mix phx.server` in a fresh process group and resolves once healthy. */
export async function startServer() {
  const occupied = await healthStatus();
  if (occupied === 200) {
    throw new Error(
      `a server already answers ${HEALTH_URL} on port ${PORT}; stop it before running the browser suite`,
    );
  }

  const descriptor = openSync(LOG_FILE, 'w');
  const child = spawn('mix', ['phx.server'], {
    cwd: repoRoot,
    env: { ...process.env, MIX_ENV: 'dev' },
    detached: true,
    stdio: ['ignore', descriptor, descriptor],
  });
  closeSync(descriptor);

  let exited = null;
  child.on('exit', (code, signal) => {
    exited = { code, signal };
  });

  const deadline = Date.now() + START_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (exited) {
      throw new Error(`server exited before becoming healthy: ${JSON.stringify(exited)}\n${tailLogs()}`);
    }
    if (await healthStatus() === 200) {
      return { url: BASE_URL, logFile: LOG_FILE, stop: () => stop(child) };
    }
    await sleep(500);
  }

  await stop(child);
  throw new Error(`server never became healthy within ${START_TIMEOUT_MS}ms\n${tailLogs()}`);
}

async function stop(child) {
  const tree = descendantPids(child.pid);

  // Phoenix spawns beam and the asset watcher in their own process groups, so a
  // single group signal is not enough: every descendant is signalled directly.
  killQuiet(-child.pid, 'SIGTERM');
  for (const pid of tree) killQuiet(pid, 'SIGTERM');

  await sleep(1_000);
  for (const pid of tree.filter(alive)) {
    killQuiet(pid, 'SIGKILL');
  }
  killQuiet(-child.pid, 'SIGKILL');

  const deadline = Date.now() + STOP_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (await healthStatus() !== 200) return;
    await sleep(200);
  }

  throw new Error(`port ${PORT} still answers after tearing down ${tree.join(', ')}\n${tailLogs()}`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
