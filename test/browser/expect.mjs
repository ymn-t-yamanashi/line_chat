// Tiny web-first assertion helpers for the browser suite. The repo depends on
// the plain `playwright` package, which has no `expect`, so these poll the
// locator APIs (`count()` / `allTextContents()`) instead of relying on the
// runner-provided web-first matchers. Both APIs resolve without waiting, which
// keeps the polling loop cheap while a LiveView patch is in flight.

import assert from 'node:assert/strict';

export const DEFAULT_TIMEOUT_MS = Number(process.env.LINE_CHAT_BROWSER_EXPECT_MS ?? 5_000);

/** Collapse whitespace the way Playwright's `toHaveText` does. */
function normalize(text) {
  return text.replace(/\s+/g, ' ').trim();
}

function matches(expected, actual) {
  if (expected instanceof RegExp) {
    return expected.test(actual);
  }
  return actual === expected;
}

function contains(expected, actual) {
  if (expected instanceof RegExp) {
    return expected.test(actual);
  }
  return actual.includes(expected);
}

function describe(expected) {
  return expected instanceof RegExp ? String(expected) : JSON.stringify(expected);
}

async function until(probe, timeout, label, observe) {
  const deadline = Date.now() + timeout;
  let last;
  let error;

  while (Date.now() < deadline) {
    try {
      last = await probe();
      // A probe reports "not yet" as `undefined`; legitimate falsy values such
      // as a count of 0 or an empty input value must still satisfy the matcher.
      if (last !== undefined) return last;
    } catch (err) {
      error = err;
    }
    await sleep(120);
  }

  const detail = error ? `${error.message}` : `last value ${JSON.stringify(last)}`;
  const seen = observe ? await observe().catch(() => 'nothing observed') : '';
  throw new Error(`timed out after ${timeout}ms waiting for ${label}: ${detail}${seen ? ` (${seen})` : ''}`);
}

/** Assert exactly one element matches `expected` once whitespace is collapsed. */
export async function expectText(locator, expected, timeout = DEFAULT_TIMEOUT_MS) {
  let observed = 'nothing observed';
  await until(
    async () => {
      const texts = (await locator.allTextContents()).map(normalize);
      observed = `${texts.length} text(s) ${JSON.stringify(texts)}`;
      return texts.length === 1 && matches(expected, texts[0]) ? texts[0] : undefined;
    },
    timeout,
    `text ${describe(expected)} at ${locator}`,
    () => observed,
  );
}

/** Assert exactly one element whose collapsed text contains `expected`. */
export async function expectTextContains(locator, expected, timeout = DEFAULT_TIMEOUT_MS) {
  let observed = 'nothing observed';
  await until(
    async () => {
      const texts = (await locator.allTextContents()).map(normalize);
      observed = `${texts.length} text(s) ${JSON.stringify(texts)}`;
      return texts.length === 1 && contains(expected, texts[0]) ? texts[0] : undefined;
    },
    timeout,
    `text containing ${describe(expected)} at ${locator}`,
    () => observed,
  );
}

/** Assert every element is gone (`0`) or present (`n`) without waiting. */
export async function expectCount(locator, expected, timeout = DEFAULT_TIMEOUT_MS) {
  let observed = 'nothing observed';
  await until(
    async () => {
      const count = await locator.count();
      observed = `count ${count}`;
      return count === expected ? expected : undefined;
    },
    timeout,
    `count ${expected} at ${locator}`,
    () => observed,
  );
}

export async function expectAttribute(locator, name, expected, timeout = DEFAULT_TIMEOUT_MS) {
  let observed = 'nothing observed';
  const value = await until(
    async () => {
      const attribute = await locator.getAttribute(name, { timeout: 300 });
      observed = `${name}=${JSON.stringify(attribute)}`;
      return attribute !== null && matches(expected, attribute) ? attribute : undefined;
    },
    timeout,
    `attribute ${name} ${describe(expected)} at ${locator}`,
    () => observed,
  );
  return value;
}

export async function expectInputValue(locator, expected, timeout = DEFAULT_TIMEOUT_MS) {
  let observed = 'nothing observed';
  return until(
    async () => {
      const value = await locator.inputValue({ timeout: 300 });
      observed = `value ${JSON.stringify(value)}`;
      return matches(expected, value) ? value : undefined;
    },
    timeout,
    `value ${describe(expected)} at ${locator}`,
    () => observed,
  );
}

export async function expectUrl(page, expected, timeout = DEFAULT_TIMEOUT_MS) {
  let observed = 'nothing observed';
  return until(
    async () => {
      const url = page.url();
      observed = `url ${JSON.stringify(url)}`;
      return matches(expected, url) ? url : undefined;
    },
    timeout,
    `url ${describe(expected)}`,
    () => observed,
  );
}

/** Assert a condition that is already true, e.g. a parsed JSON body. */
export function equals(actual, expected, message) {
  assert.equal(actual, expected, message);
}

export function deepEquals(actual, expected, message) {
  assert.deepEqual(actual, expected, message);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export { sleep };
