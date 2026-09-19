import { test, expect } from '@playwright/test';

test('mobile layout reaches signal cards quickly', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'mobile-only test');
  await page.goto('/');
  const welcome = page.locator('#welcomeContinue');
  if (await welcome.isVisible().catch(() => false)) await welcome.click();
  await page.waitForTimeout(800);

  const ea = page.locator('#mt5Execution');
  const watch = page.locator('#trendWatchPanel');
  const eaBox = await ea.boundingBox();
  const watchBox = await watch.boundingBox();

  expect(eaBox?.height || 999).toBeLessThan(150);
  expect(watchBox?.height || 999).toBeLessThan(110);

  const firstCard = page.locator('.result-card').first();
  await firstCard.scrollIntoViewIfNeeded();
  await expect(firstCard).toBeVisible();
});

test('mobile compact metadata remains one horizontal strip', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'mobile-only test');
  await page.goto('/');
  const welcome = page.locator('#welcomeContinue');
  if (await welcome.isVisible().catch(() => false)) await welcome.click();

  const meta = page.locator('.compact-meta');
  await expect(meta).toBeVisible();
  const box = await meta.boundingBox();
  expect(box?.height || 999).toBeLessThan(45);
});
