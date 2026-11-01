import { test, expect } from '@playwright/test';
import fs from 'fs';

const stats = JSON.parse(fs.readFileSync('data/playbook-stats.json', 'utf8'));
const signals = {
  updated_at: new Date().toISOString(), strategy: 'Sera Drift Playbook', signals: 1,
  markets: [
    { id: 'BOOM1000:drift', market: 'Boom 1000 Index', symbol: 'BOOM1000', mode: 'drift', label: 'Boom / Crash · GainX / PainX',
      final_verdict: 'SELL', final_confidence: 77, rsi: 59.8,
      levels: { entry: 15365.0, sl: 15413.09, tp1: 15350.58, tp2: 15333.75, tp3: 15316.92, tp4: 15314.51, tp5: 15312.11 },
      measured: { tp1_rate: 77.4, expectancy_r: 0.069 } },
    { id: 'CRASH500:drift', market: 'Crash 500 Index', symbol: 'CRASH500', mode: 'drift', final_verdict: 'ATTENDRE', rsi: 52 }
  ]
};

async function open(page, sig) {
  const ok = body => route => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
  await page.route('**/playbook-signals.json*', sig ? ok(sig) : r => r.fulfill({ status: 404, body: 'nf' }));
  await page.route('**/playbook-stats.json*', ok(stats));
  await page.goto('/');
  await page.evaluate(() => document.getElementById('welcomePopup')?.remove());
  await page.locator('#playbook').scrollIntoViewIfNeeded();
}

test('measured strategy panel shows the real measured rates, not promises', async ({ page }) => {
  await open(page, signals);
  const bull = stats.groups.bullbear.all;
  await expect(page.locator('[data-pb-group="bullbear"] .pb-big')).toContainText(String(bull.tp1_rate).replace('.', ','));
  await expect(page.locator('[data-pb-group="spike"]')).toContainText('trades perdants');
  await expect(page.locator('#pbBaseline')).toContainText('Moteur Swing');
  await expect(page.locator('#pbPeriod')).toContainText(stats.period.from);
});

test('current drift signals are listed with their levels', async ({ page }) => {
  await open(page, signals);
  await expect(page.locator('#pbNotice')).toContainText('1 signal(s)');
  const card = page.locator('[data-pb-market="Boom 1000 Index"]');
  await expect(card.locator('.wt-signal')).toHaveText('SELL');
  await expect(card).toContainText('TP1 77,4');
  await expect(page.locator('[data-pb-market="Crash 500 Index"]')).toHaveCount(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(await page.evaluate(() => window.innerWidth) + 1);
});

test('no signal file yet: the panel still shows the measurements', async ({ page }) => {
  await open(page, null);
  await expect(page.locator('#pbNotice')).toContainText('en attente');
  await expect(page.locator('[data-pb-group="bullbear"]')).toBeVisible();
});
