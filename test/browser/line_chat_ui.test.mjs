// Browser suite for the LINE-style chat UI: a real dev server plus real
// Chromium, so LiveView websocket pushes, cookies and guest identities are
// exercised end to end. Kept as a single file because `node --test` runs files
// concurrently, while every guest shares the one in-memory chat store.

import { after, before, describe, test } from 'node:test';
import { chromium } from 'playwright';
import { BASE_URL, startServer } from './server.mjs';
import {
  deepEquals,
  equals,
  expectAttribute,
  expectCount,
  expectInputValue,
  expectText,
  expectTextContains,
  expectUrl,
  sleep,
} from './expect.mjs';

const SEEDED = [
  { name: 'チーム開発', glyph: 'チ', preview: 'レビューお願いね', unread: '3' },
  { name: '週末の飲み会', glyph: '週', preview: '幹事任せるね', unread: '2' },
  { name: '家族', glyph: '家', preview: 'ただいま', unread: '1' },
];

// The Chromium bundled in this container segfaults on startup (exit 139), so
// the suite drives the system Chrome binary. Override with
// LINE_CHAT_BROWSER_CHANNEL=bundled (or another Playwright channel name).
const BROWSER_CHANNEL = process.env.LINE_CHAT_BROWSER_CHANNEL ?? 'chrome';

let server;
let browser;
const contexts = [];

/**
 * A fresh browser context is a fresh guest: no cookie, so `GuestPlug` assigns a
 * new identity that `Chat.create_guest_user` joins to every room.
 */
async function newContext() {
  const context = await browser.newContext();
  contexts.push(context);
  return context;
}

/** Run `run` in a throwaway guest session, closing it afterwards. */
async function withSession(run) {
  const context = await newContext();
  try {
    const page = await context.newPage();
    return await run(page, context);
  } finally {
    const index = contexts.indexOf(context);
    if (index >= 0) contexts.splice(index, 1);
    await context.close().catch(() => {});
  }
}

/** Create a room from the home screen and follow the `push_navigate` result. */
async function openRoom(page, name) {
  await page.goto(`${BASE_URL}/`);
  await page.fill('#room_name', name);
  await page.click('form.room-form button.primary-button');
  return expectUrl(page, /\/rooms\/room-\d+$/);
}

async function sendMessage(page, body) {
  await page.fill('#body', body);
  await page.click('form.send-form button.primary-button');
}

function roomRow(page, name) {
  return page.locator('.room-row').filter({ has: page.locator('.room-name', { hasText: name }) });
}

async function api(path) {
  const response = await fetch(`${BASE_URL}${path}`);
  return { status: response.status, body: await response.text() };
}

describe('LINE-style chat UI in a real browser', () => {
  before(async () => {
    try {
      server = await startServer();
      const launchOptions = { args: ['--no-sandbox', '--disable-dev-shm-usage'] };
      if (BROWSER_CHANNEL && BROWSER_CHANNEL !== 'bundled') {
        launchOptions.channel = BROWSER_CHANNEL;
      }
      browser = await chromium.launch(launchOptions);
    } catch (error) {
      // `node --test` only reports "failed running before hook", so name the cause.
      console.error(`browser setup failed: ${error?.stack ?? error}`);
      throw error;
    }
  });

  after(async () => {
    for (const context of contexts) {
      await context.close().catch(() => {});
    }
    await browser?.close();
    await server?.stop();
  });

  test('health endpoint reports the seeded store', async () => {
    const { status, body } = await api('/api/health');
    equals(status, 200);
    const payload = JSON.parse(body);
    equals(payload.status, 'ok');
    equals(payload.rooms, SEEDED.length);
  });

  test('read-only room API lists the seeded rooms', async () => {
    const { status, body } = await api('/api/rooms');
    equals(status, 200);

    const rooms = JSON.parse(body).rooms;
    equals(rooms.length, SEEDED.length);
    deepEquals(
      rooms.map((room) => room.name),
      ['家族', '週末の飲み会', 'チーム開発'],
    );

    for (const room of rooms) {
      equals(typeof room.id, 'string');
      equals(room.member_ids.length > 0, true);
      equals(Number.isNaN(Date.parse(room.created_at)), false);
    }
  });

  test('read-only transcript API labels authors and times', async () => {
    const rooms = JSON.parse((await api('/api/rooms')).body).rooms;
    const room = rooms.find((entry) => entry.name === 'チーム開発');
    const { status, body } = await api(`/api/rooms/${room.id}/messages`);
    equals(status, 200);

    const payload = JSON.parse(body);
    deepEquals(payload.room.id, room.id);
    equals(payload.messages.length, 3);
    deepEquals(
      payload.messages.map((message) => message.body),
      ['おはよう!', '仕様を確認しました', 'レビューお願いね'],
    );
    deepEquals(
      payload.messages.map((message) => message.author_name),
      ['アリス', 'ボブ', 'アリス'],
    );

    for (const message of payload.messages) {
      equals(message.room_id, room.id);
      equals(message.redacted, false);
      equals(Number.isNaN(Date.parse(message.inserted_at)), false);
      equals(/^\d{2}:\d{2}$/.test(message.time_label), true);
    }
  });

  test('room API answers 404 for a room that does not exist', async () => {
    const missing = await api('/api/rooms/room-does-not-exist/messages');
    equals(missing.status, 404);
    deepEquals(JSON.parse(missing.body), { errors: { detail: 'Room not found' } });
  });

  test('home lists the seeded rooms with LINE-style rows', async () => {
    await withSession(async (page) => {
      await page.goto(`${BASE_URL}/`);

      await expectText(page.locator('h1.screen-title'), 'ルーム一覧');
      await expectText(page.locator('.screen-header .avatar'), 'ゲ');
      await expectText(page.locator('p.viewer-note'), /^ゲスト \d+$/);
      await expectCount(page.locator('.room-row'), SEEDED.length);

      const rows = page.locator('.room-row');
      for (let index = 0; index < SEEDED.length; index += 1) {
        const row = rows.nth(index);
        const expected = SEEDED[index];
        await expectText(row.locator('.room-name'), expected.name);
        await expectText(row.locator('.room-avatar'), expected.glyph);
        await expectText(row.locator('.room-preview'), expected.preview);
        await expectText(row.locator('.unread-badge'), expected.unread);

        await expectAttribute(row.locator('.room-row-link'), 'href', /^\/rooms\/room-\d+$/);
        await expectCount(row.locator('button.delete-room'), 1);
      }

      await expectCount(page.locator('a.back-link'), 0);
      await expectCount(page.locator('.empty-note'), 0);
    });
  });

  test('blank room names are rejected and a created room opens empty', async () => {
    await withSession(async (page) => {
      await page.goto(`${BASE_URL}/`);
      await page.fill('#room_name', '');
      await page.click('form.room-form button.primary-button');
      await expectTextContains(page.locator('.flash--error'), 'ルーム名を入力してください');
      await expectCount(page.locator('.room-row'), SEEDED.length);

      const roomUrl = await openRoom(page, 'ブラウザ作成テスト');
      equals(roomUrl, `${BASE_URL}/rooms/${roomUrl.split('/').pop()}`);

      await expectText(page.locator('h1.screen-title'), 'ブラウザ作成テスト');
      await expectText(page.locator('p.viewer-note'), /^ゲスト \d+・\d+人$/);
      await expectAttribute(page.locator('a.back-link'), 'href', '/');
      await expectInputValue(page.locator('form.rename-form #room_name'), 'ブラウザ作成テスト');
      await expectText(page.locator('.transcript .empty-note'), 'メッセージはまだありません');

      await page.goto(`${BASE_URL}/`);
      const row = roomRow(page, 'ブラウザ作成テスト');
      await expectText(row.locator('.room-preview'), 'メッセージはまだありません');
      await expectText(row.locator('.room-avatar'), 'ブ');
      await expectCount(row.locator('.unread-badge'), 0);
    });
  });

  test('sending, read state, redaction and body validation in a room', async () => {
    await withSession(async (page) => {
      const roomUrl = await openRoom(page, 'ブラウザ送信テスト');
      await page.goto(roomUrl);

      await sendMessage(page, '');
      await expectTextContains(page.locator('.flash--error'), 'メッセージを入力してください');
      await expectCount(page.locator('.message-row'), 0);

      await sendMessage(page, 'あ'.repeat(501));
      await expectTextContains(page.locator('.flash--error'), 'メッセージが長すぎます（最大 500 文字）');
      await expectCount(page.locator('.message-row'), 0);

      await sendMessage(page, 'こんにちは');

      await expectCount(page.locator('.message-row'), 1);
      await expectCount(page.locator('.transcript .empty-note'), 0);
      await expectText(page.locator('.day-separator'), '今日');
      await expectCount(page.locator('.bubble--self'), 1);
      await expectText(page.locator('.bubble--self .bubble-author'), /^ゲスト \d+$/);
      await expectText(page.locator('.bubble--self .bubble-body'), 'こんにちは');
      await expectText(page.locator('.bubble--self .bubble-time'), /^\d{2}:\d{2}$/);
      await expectText(page.locator('.bubble--self .read-state'), '未読');

      await page.click('.bubble--self .redact-button');
      await expectText(page.locator('.bubble--self .redacted-note'), 'メッセージを取り消しました');
      await expectCount(page.locator('.bubble--self .bubble-body'), 0);
      await expectCount(page.locator('.redact-button'), 0);

      await page.goto(`${BASE_URL}/`);
      await expectText(
        roomRow(page, 'ブラウザ送信テスト').locator('.room-preview'),
        'メッセージを取り消しました',
      );
    });
  });

  test('renaming a room updates the title, the form and the home list', async () => {
    await withSession(async (page) => {
      const roomUrl = await openRoom(page, 'ブラウザ改名テスト');
      await page.goto(roomUrl);

      await page.fill('#room_name', '   ');
      await page.click('form.rename-form button.ghost-button');
      await expectTextContains(page.locator('.flash--error'), 'ルーム名を入力してください');
      await expectText(page.locator('h1.screen-title'), 'ブラウザ改名テスト');

      await page.fill('#room_name', 'ブラウザ改名後のルーム');
      await page.click('form.rename-form button.ghost-button');
      await expectTextContains(page.locator('.flash--info'), 'ルーム名を変更しました');
      await expectText(page.locator('h1.screen-title'), 'ブラウザ改名後のルーム');
      await expectInputValue(page.locator('form.rename-form #room_name'), 'ブラウザ改名後のルーム');

      await page.goto(roomUrl);
      await expectText(page.locator('h1.screen-title'), 'ブラウザ改名後のルーム');

      await page.goto(`${BASE_URL}/`);
      await expectText(
        roomRow(page, 'ブラウザ改名後のルーム').locator('.room-name'),
        'ブラウザ改名後のルーム',
      );
      await expectCount(roomRow(page, 'ブラウザ改名テスト'), 0);
    });
  });

  test('another guest reading the room flips the sender read receipt live', async () => {
    // The sender's view has to stay attached for the `read_marked` push to reach
    // it, so this guest keeps its context open instead of using `withSession`.
    const sender = await newContext();
    const senderPage = await sender.newPage();
    const roomUrl = await openRoom(senderPage, 'ブラウザ既読テスト');

    await senderPage.goto(roomUrl);
    await sendMessage(senderPage, '既読になってね');
    await expectText(senderPage.locator('.bubble--self .read-state'), '未読');

    // Opening the room calls Chat.mark_read, which broadcasts read_marked.
    await withSession(async (readerPage) => {
      await readerPage.goto(`${BASE_URL}/`);
      await expectText(roomRow(readerPage, 'ブラウザ既読テスト').locator('.unread-badge'), '1');

      await readerPage.goto(roomUrl);
      await expectTextContains(
        readerPage.locator('.bubble:not(.bubble--self) .bubble-body'),
        '既読になってね',
      );
    });

    await expectText(senderPage.locator('.bubble--self .read-state'), '既読', 10_000);

    // A third guest has never read the room, so its badge is still waiting.
    await withSession(async (freshPage) => {
      await freshPage.goto(`${BASE_URL}/`);
      await expectText(roomRow(freshPage, 'ブラウザ既読テスト').locator('.unread-badge'), '1');
    });
  });

  test('typing in another guest session hints live and expires', async () => {
    const roomUrl = await withSession(async (page) => openRoom(page, 'ブラウザタイピングテスト'));

    const typer = await newContext();
    const typerPage = await typer.newPage();
    await typerPage.goto(roomUrl);

    await withSession(async (watchPage) => {
      await watchPage.goto(roomUrl);
      await expectCount(watchPage.locator('p.typing'), 0);

      await typerPage.fill('#body', '書き込み中');
      await expectTextContains(watchPage.locator('p.typing'), '入力中');

      // RoomLive re-arms its refresh timer on every transcript event, and the
      // store's 4s typing TTL lapses before that timer fires, so the room view
      // drops the hint on its own timer without any further broadcast.
      await sleep(4_500);
      await expectCount(watchPage.locator('p.typing'), 0, 10_000);

      // HomeLive has no expiry timer, so a stale hint survives until some other
      // event rebuilds the rows.
      await watchPage.goto(`${BASE_URL}/`);
      await typerPage.fill('#body', 'まだ書き込み中');
      const row = roomRow(watchPage, 'ブラウザタイピングテスト');
      await expectTextContains(
        row.locator('.typing'),
        '入力中',
      );
      await sleep(4_500);
      await expectTextContains(row.locator('.typing'), '入力中');

      // The send form fires phx-change before phx-submit, so sending re-arms the
      // typing state and the message_created broadcast rebuilds the row while the
      // hint is still fresh.
      await sendMessage(typerPage, 'タイピング後のメッセージ');
      await expectTextContains(row.locator('.typing'), '入力中');
      await expectText(
        row.locator('.room-preview'),
        'タイピング後のメッセージ',
      );

      // Only an event that arrives after the TTL drops the hint. Opening the room
      // in a fresh guest session marks it read, broadcasting read_marked.
      await sleep(4_500);
      await withSession(async (readerPage) => {
        await readerPage.goto(roomUrl);
      });
      await expectCount(row.locator('.typing'), 0, 10_000);
      await expectText(row.locator('.room-preview'), 'タイピング後のメッセージ');

      await watchPage.goto(roomUrl);
      await expectCount(watchPage.locator('p.typing'), 0, 10_000);
      await expectText(pageOfMessage(watchPage), 'タイピング後のメッセージ');
    });
  });

  function pageOfMessage(page) {
    return page.locator('.bubble:not(.bubble--self) .bubble-body');
  }

  test('deleting a room clears the list and redirects the open room view', async () => {
    // This guest stays attached on the room page so it receives room_deleted.
    const survivor = await newContext();
    const survivorPage = await survivor.newPage();
    const roomUrl = await openRoom(survivorPage, 'ブラウザ削除テスト');

    await survivorPage.goto(roomUrl);
    await sendMessage(survivorPage, 'このルームは消える');
    await expectCount(survivorPage.locator('.message-row'), 1);

    await withSession(async (page) => {
      await page.goto(`${BASE_URL}/`);
      await expectCount(roomRow(page, 'ブラウザ削除テスト'), 1);
      await roomRow(page, 'ブラウザ削除テスト').locator('button.delete-room').click();
      await expectCount(roomRow(page, 'ブラウザ削除テスト'), 0);
      await expectCount(roomRow(page, 'チーム開発'), 1);
    });

    await expectTextContains(survivorPage.locator('.flash--error'), 'ルームが削除されました');
    await expectUrl(survivorPage, `${BASE_URL}/`);
    await expectText(survivorPage.locator('h1.screen-title'), 'ルーム一覧');
    await expectCount(roomRow(survivorPage, 'ブラウザ削除テスト'), 0);

    await withSession(async (page) => {
      await page.goto(roomUrl);
      await expectUrl(page, `${BASE_URL}/`);
      await expectTextContains(page.locator('.flash--error'), 'ルームが見つかりません');
    });
  });

  test('unknown rooms redirect home with a flash', async () => {
    await withSession(async (page) => {
      await page.goto(`${BASE_URL}/rooms/room-not-a-room`);
      await expectUrl(page, `${BASE_URL}/`);
      await expectTextContains(page.locator('.flash--error'), 'ルームが見つかりません');
      await expectText(page.locator('h1.screen-title'), 'ルーム一覧');
    });
  });

  test('the back link returns to the room list', async () => {
    await withSession(async (page) => {
      const roomUrl = await openRoom(page, 'ブラウザ戻るテスト');
      await page.goto(roomUrl);
      await page.click('a.back-link');
      await expectUrl(page, `${BASE_URL}/`);
      await expectText(page.locator('h1.screen-title'), 'ルーム一覧');
      await expectCount(roomRow(page, 'ブラウザ戻るテスト'), 1);
    });
  });
});
