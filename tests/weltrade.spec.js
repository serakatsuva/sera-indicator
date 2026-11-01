import { test, expect } from '@playwright/test';
import fs from 'fs';

const sample = JSON.parse(fs.readFileSync('tests/fixtures/weltrade-sample.json', 'utf8'));

async function serveWeltrade(page, data) {
  const handler = route => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(data()) });
  await page.route('https://raw.githubusercontent.com/**/weltrade-signals.json*', handler);
  await page.route('**/data/weltrade-signals.json*', handler);
}

async function captureSpeech(page) {
  await page.addInitScript(() => {
    window.__spoken = [];
    const fake = { speak: u => window.__spoken.push(u.text), cancel: () => {}, getVoices: () => [], addEventListener: () => {} };
    Object.defineProperty(window, 'speechSynthesis', { value: fake, configurable: true });
    window.SpeechSynthesisUtterance = function (text) { this.text = text; };
  });
}

async function open(page) {
  await page.goto('/');
  await page.evaluate(() => document.getElementById('welcomePopup')?.remove());
  await page.locator('#weltradeFilter').click();
  await expect(page.locator('#weltradeFilter')).toHaveClass(/active/);
}

test('Weltrade tab shows the analyses sent by the MT5 EA', async ({ page }) => {
  await serveWeltrade(page, () => ({ ...sample, updated_at: new Date(Date.now() - 2 * 60000).toISOString() }));
  await open(page);
  await expect(page.locator('#weltrade .wt-card')).toHaveCount(sample.markets.length);
  const signals = sample.markets.filter(m => m.verdict === 'BUY' || m.verdict === 'SELL');
  await expect(page.locator('#wtNotice')).toContainText(`${signals.length} signal(s) Weltrade en cours`);
  const first = page.locator('.wt-card', { hasText: signals[0].symbol }).first();
  await expect(first.locator('.wt-signal')).toHaveText(signals[0].verdict);
  await expect(first.locator('.wt-levels strong').first()).toHaveText(Number(signals[0].entry).toFixed(signals[0].digits));
  await page.locator('[data-wt-filter="signals"]').click();
  await expect(page.locator('#weltrade .wt-card')).toHaveCount(signals.length);
  // no horizontal scroll on any screen
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(await page.evaluate(() => window.innerWidth) + 1);
});

test('Weltrade tab explains how to connect the EA when nothing was received', async ({ page }) => {
  await page.route('https://raw.githubusercontent.com/**/weltrade-signals.json*', r => r.fulfill({ status: 404, body: 'Not Found' }));
  await page.route('**/data/weltrade-signals.json*', r => r.fulfill({ status: 404, body: 'Not Found' }));
  await open(page);
  await expect(page.locator('#wtNotice')).toContainText('Aucune analyse Weltrade reçue');
  await expect(page.locator('#wtNotice')).toContainText('PublishToApp');
  // the Weltrade synthetic families are listed while waiting for the EA
  await expect(page.locator('#wtFamilies [data-wt-family-filter="GAINX"]')).toBeVisible();
  await expect(page.locator('#weltrade .wt-card.wt-waiting').first()).toContainText('GainX');
});

test('Weltrade is a market tab next to Synthetiques and Forex', async ({ page }) => {
  await serveWeltrade(page, () => ({ ...sample, updated_at: new Date().toISOString() }));
  await page.goto('/');
  await page.evaluate(() => document.getElementById('welcomePopup')?.remove());
  await expect(page.locator('#weltrade')).toBeHidden();
  await page.locator('#weltradeFilter').click();
  await expect(page.locator('#weltrade')).toBeVisible();
  await expect(page.locator('#results')).toBeHidden();
  await expect(page.locator('#syntheticFilter')).not.toHaveClass(/active/);
  await expect(page.locator('#scanner h2')).toHaveText('Signaux Weltrade (SyntX)');
  await page.locator('[data-wt-family-filter="PAINX"]').click();
  await expect(page.locator('#weltrade .wt-card')).toHaveCount(sample.markets.filter(m => m.family === 'PAINX').length);
  await page.locator('#syntheticFilter').click();
  await expect(page.locator('#weltrade')).toBeHidden();
  await expect(page.locator('#results')).toBeVisible();
  await expect(page.locator('#syntheticFilter')).toHaveClass(/active/);
  await expect(page.locator('#weltradeFilter')).not.toHaveClass(/active/);
});

test('the #weltrade link opens the Weltrade tab directly', async ({ page }) => {
  await serveWeltrade(page, () => ({ ...sample, updated_at: new Date().toISOString() }));
  await page.goto('/#weltrade');
  await page.evaluate(() => document.getElementById('welcomePopup')?.remove());
  await expect(page.locator('#weltradeFilter')).toHaveClass(/active/);
  await expect(page.locator('#weltrade .wt-card')).toHaveCount(sample.markets.length);
});

test('old Weltrade analyses are flagged as not up to date', async ({ page }) => {
  await serveWeltrade(page, () => ({ ...sample, updated_at: new Date(Date.now() - 3 * 3600000).toISOString() }));
  await open(page);
  await expect(page.locator('#wtNotice')).toContainText('semble arrêté');
});

test('voice: read an analysis aloud and announce new Weltrade signals', async ({ page }) => {
  await captureSpeech(page);
  let current = { ...sample, updated_at: new Date().toISOString(), markets: sample.markets.map(m => ({ ...m })) };
  const target = current.markets.find(m => m.verdict === 'BUY' || m.verdict === 'SELL');
  const quiet = current.markets.find(m => m.verdict === 'ATTENDRE');
  quiet.verdict = 'ATTENDRE';
  await serveWeltrade(page, () => current);
  await open(page);
  await expect(page.locator('#weltrade .wt-card').first()).toBeVisible();

  await page.locator('#voiceToggle').click();
  await expect(page.locator('#voiceToggle')).toHaveClass(/on/);
  await page.locator(`[data-wt-speak="${target.symbol}"]`).click();
  const spoken = await page.evaluate(() => window.__spoken.join(' | '));
  expect(spoken).toContain('Lecture vocale activée');
  expect(spoken).toContain(`Weltrade. Signal Swing. ${target.symbol}.`);
  expect(spoken).toContain('Entrée');

  // a new signal appears on the next refresh -> it is announced
  current = { ...current, markets: current.markets.map(m => m.symbol === quiet.symbol ? { ...m, verdict: 'BUY', entry: 100, sl: 99, tp1: 101, tp2: 102, tp3: 103 } : m) };
  await page.evaluate(() => window.SeraWeltrade.refresh());
  await expect.poll(() => page.evaluate(() => window.__spoken.join(' | '))).toContain(`Nouveau signal. Weltrade. Signal Swing. ${quiet.symbol}. achat.`);
});
