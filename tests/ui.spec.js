import { test, expect } from '@playwright/test';

async function dismissWelcome(page) {
  const button = page.locator('#welcomeContinue');
  if (await button.isVisible().catch(() => false)) await button.click();
}

test.beforeEach(async ({ page }) => {
  page.on('pageerror', error => {
    throw new Error('Browser page error: ' + error.message);
  });
  await page.goto('/');
  await dismissWelcome(page);
  await page.waitForSelector('#results');
  await page.waitForTimeout(1200);
});

test('core UI loads without duplicate IDs or broken main controls', async ({ page }) => {
  const duplicates = await page.evaluate(() => {
    const ids = [...document.querySelectorAll('[id]')].map(el => el.id);
    return ids.filter((id, i) => ids.indexOf(id) !== i);
  });
  expect(duplicates).toEqual([]);

  await expect(page.locator('#refreshButton')).toBeVisible();
  await expect(page.locator('#results')).toBeVisible();
  await expect(page.locator('#trendWatchPanel')).toBeVisible();
  await expect(page.locator('#mt5Execution')).toBeVisible();

  const cards = page.locator('.result-card');
  expect(await cards.count()).toBeGreaterThan(0);
});

test('compact Trend Watch options open and close correctly', async ({ page }) => {
  const options = page.locator('#trendWatchOptions');
  const toggle = page.locator('#watchOptionsToggle');
  await expect(options).toBeHidden();
  await toggle.click();
  await expect(options).toBeVisible();
  await toggle.click();
  await expect(options).toBeHidden();
});

test('result cards expose only clear BUY SELL WAIT action language', async ({ page }) => {
  const chips = page.locator('.trade-action-chip');
  expect(await chips.count()).toBeGreaterThan(0);
  const texts = await chips.allTextContents();
  for (const text of texts) {
    expect(/BUY|SELL|WAIT/.test(text)).toBeTruthy();
  }
});

test('opening a signal shows entry levels and action state', async ({ page }) => {
  const firstCard = page.locator('.result-card').first();
  await firstCard.click();
  await expect(page.locator('#signalModal')).toBeVisible();
  await expect(page.locator('#tradeActionBox')).toBeVisible();
  await expect(page.locator('#levels')).toBeVisible();

  const levelCount = await page.locator('#levels strong').count();
  expect(levelCount).toBe(7);
});

test('EA links remain available in compact bar', async ({ page }) => {
  const download = page.locator('a[href*="Sera_Swing_Executor.mq5"]');
  await expect(download).toBeVisible();
  await expect(page.locator('#showMt5Setup')).toBeVisible();
});

test('no horizontal page overflow', async ({ page }) => {
  const dims = await page.evaluate(() => ({
    innerWidth: window.innerWidth,
    scrollWidth: document.documentElement.scrollWidth
  }));
  expect(dims.scrollWidth).toBeLessThanOrEqual(dims.innerWidth + 2);
});


test('BUY or SELL action never flashes while final signal is WAIT', async ({ page }) => {
  const actionable = page.locator('.trade-action-chip.buy, .trade-action-chip.sell');
  const count = await actionable.count();
  for (let i = 0; i < count; i++) {
    const chip = actionable.nth(i);
    const card = chip.locator('xpath=ancestor::button[contains(@class,"result-card")]');
    await expect(card.locator('.signal.buy, .signal.sell')).toHaveCount(1);
    await expect(chip).toHaveClass(/blink/);
  }
});

test('card action and modal action stay identical after click', async ({ page }) => {
  const cards = page.locator('.result-card');
  const count = await cards.count();
  for (let i = 0; i < Math.min(count, 6); i++) {
    const card = cards.nth(i);
    const chip = card.locator('.trade-action-chip');
    if (!(await chip.count())) continue;
    const cardAction = (await chip.locator('strong').textContent())?.trim();
    await card.click();
    await expect(page.locator('#signalModal')).toBeVisible();
    const modalAction = (await page.locator('#tradeActionLabel').textContent())?.trim();
    expect(modalAction).toBe(cardAction);
    await page.locator('#closeSignalModal').click();
    await expect(page.locator('#signalModal')).toBeHidden();
  }
});
