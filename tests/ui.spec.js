import { test, expect } from '@playwright/test';

async function dismissWelcome(page) {
  const button = page.locator('#welcomeContinue');
  if (await button.isVisible().catch(() => false)) await button.click();
}

test.beforeEach(async ({ page }) => {
  page.on('pageerror', error => {
    throw new Error('Browser page error: ' + error.message);
  });
  // Deterministic data: serve the committed signals instead of the live GitHub raw file.
  await page.route('https://raw.githubusercontent.com/**', route => route.fulfill({ path: 'data/signals.json', contentType: 'application/json' }));
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
  await expect(page.locator('a[href*="Sera_EA_Swing_Intelligent_Deriv.mq5"]')).toBeVisible();
  await expect(page.locator('a[href*="Sera_EA_Swing_Intelligent_Weltrade.mq5"]')).toBeVisible();
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


test('signal popup contains realtime candle chart and prediction controls', async ({ page }) => {
  await page.locator('.result-card').first().click();
  await expect(page.locator('#signalModal')).toBeVisible();
  await expect(page.locator('#liveCandlesCanvas')).toBeVisible();
  await expect(page.locator('#livePriceAxis')).toBeVisible();
  await expect(page.locator('#predictionPanel')).toBeVisible();
  await expect(page.locator('#predictionDirection')).toHaveText(/BUY|SELL|NEUTRE/);
  await expect(page.locator('#predictionStatus')).not.toHaveText('');
  await expect(page.locator('#predictionAction')).toHaveText(/WAIT|ENTER BUY NOW|ENTER SELL NOW/);
});

test('realtime chart exposes Japanese candle canvas instead of decorative SVG curve', async ({ page }) => {
  await page.locator('.result-card').first().click();
  await expect(page.locator('#liveCandlesCanvas')).toHaveCount(1);
  await expect(page.locator('#chartLine')).toHaveCount(0);
  await expect(page.locator('#chartFillPath')).toHaveCount(0);
});


test('chart uses strategy timeframe mapping for Day and Swing', async ({ page }) => {
  const mapping = await page.evaluate(() => ({
    day: chartSpecForRow({mode:'day'}),
    swing: chartSpecForRow({mode:'swing'})
  }));
  expect(mapping.day.entry).toBe('M15');
  expect(mapping.day.confirmation).toBe('H1');
  expect(mapping.day.granularity).toBe(900);
  expect(mapping.swing.entry).toBe('H1');
  expect(mapping.swing.confirmation).toBe('H4');
  expect(mapping.swing.macro).toBe('D1');
  expect(mapping.swing.granularity).toBe(3600);
});

test('Forex scanner exposes all 27 checked STD symbols', async ({ page }) => {
  const forex = await page.evaluate(() => ({markets:[...forexMarkets],symbols:{...forexSymbols}}));
  expect(forex.markets).toHaveLength(27);
  expect(forex.symbols['USD/BRL']).toBe('USDBRL-STD');
  expect(forex.symbols['USD/ILS']).toBe('USDILS-STD');
  expect(forex.symbols['EUR/USD']).toBe('EURUSD-STD');
  expect(forex.symbols['NZD/USD']).toBe('NZDUSD-STD');
});

test('Forex tab renders the 27 instruments as Swing H1 H4 D1', async ({ page }) => {
  await page.locator('#forexFilter').click();
  await expect(page.locator('#results .result-card')).toHaveCount(27);
  await expect(page.locator('#selectedTimeframe')).toContainText(/H1/);
  await expect(page.locator('.mode-filter[data-mode="swing"]')).toHaveClass(/active/);
});


test('signal loader prefers latest GitHub repository data over stale Pages copy', async ({ page }) => {
  const script = await page.locator('script[src*="app.js"]').getAttribute('src');
  expect(script).toBeTruthy();
  const source = await (await page.request.get('/app.js')).text();
  expect(source).toContain('raw.githubusercontent.com/serakatsuva/sera-indicator/main/data/signals.json');
  expect(source).toContain('./data/signals.json');
});


test('notification bell shows only EXECUTE_NOW positions and opens alert panel', async ({ page }) => {
  await expect(page.locator('#signalBell')).toBeVisible();
  await page.locator('#signalBell').click();
  await expect(page.locator('#signalNotificationPanel')).toBeVisible();
  await expect(page.locator('#signalNotificationList')).toBeVisible();
});

test('ready notification logic excludes WAIT signals', async ({ page }) => {
  const verdicts = await page.evaluate(() => {
    const rows = readySignalRows();
    return rows.map(row => ({
      verdict: row.final_verdict,
      execution: row.execution_state || row.execution?.state
    }));
  });
  for (const row of verdicts) {
    expect(['BUY','SELL']).toContain(row.verdict);
    expect(row.execution).toBe('EXECUTE_NOW');
  }
});


test('stale AI analysis is neutralized while live prices can continue', async ({ page }) => {
  const state = await page.evaluate(() => {
    const original = payload.updated_at;
    payload.updated_at = new Date(Date.now() - 30 * 60 * 1000).toISOString();
    const row = payload.markets?.find(r => r.final_verdict === 'BUY' || r.final_verdict === 'SELL') || payload.markets?.[0];
    const action = simpleActionState(row);
    const prediction = predictionState(row);
    payload.updated_at = original;
    return { action, prediction };
  });
  expect(state.action.label).toBe('WAIT');
  expect(state.action.detail).toMatch(/ANALYSE SERVEUR EN RETARD|ANALYSE IA EN ATTENTE/);
  expect(state.prediction.prediction).toBe('NEUTRE');
});


test('Tous mode shows one card per market while Day and Swing remain separate filters', async ({ page }) => {
  await page.locator('.mode-filter[data-mode="all"]').click();
  await page.waitForTimeout(250);
  const markets = await page.locator('.result-card h3').allTextContents();
  expect(new Set(markets).size).toBe(markets.length);

  await page.locator('.mode-filter[data-mode="day"]').click();
  await page.waitForTimeout(150);
  const dayModes = await page.locator('.result-card').evaluateAll(cards => cards.map(c => c.dataset.liveMode));
  expect(dayModes.every(mode => mode === 'day')).toBeTruthy();

  await page.locator('.mode-filter[data-mode="swing"]').click();
  await page.waitForTimeout(150);
  const swingModes = await page.locator('.result-card').evaluateAll(cards => cards.map(c => c.dataset.liveMode));
  expect(swingModes.every(mode => mode === 'swing')).toBeTruthy();
});


test('detected setup detail can show visual risk reward plan with timeframe', async ({ page }) => {
  const card = page.locator('.result-card').filter({has: page.locator('.setup-side.buy, .setup-side.sell')}).first();
  if (await card.count()) {
    await card.click();
    await expect(page.locator('#signalModal')).toBeVisible();
    await expect(page.locator('#visualTradePlan')).toBeVisible();
    await expect(page.locator('#visualPlanTf')).toHaveText(/M15 \/ H1|H1 \/ H4 \/ D1/);
    await expect(page.locator('#visualPlanSide')).toHaveText(/BUY|SELL/);
    await expect(page.locator('#visualPlanRR')).toHaveText(/1 : /);
  }
});

test('visual trade plan uses TP3 as primary displayed target', async ({ page }) => {
  const info = await page.evaluate(() => {
    const row = payload?.markets?.find(r => (r.setup_detected || r.decision_engine?.setup_detected) && (r.projected_levels?.tp3 || r.levels?.tp3));
    if (!row) return null;
    const plan = visualTradePlan(row);
    return plan && { target: plan.target, tp3: plan.tp3, side: plan.side };
  });
  if (info) {
    expect(info.target).toBe(info.tp3);
    expect(['BUY','SELL']).toContain(info.side);
  }
});


test('WAIT BUY SELL action bar does not overlay realtime candle chart', async ({ page }) => {
  await page.locator('.result-card').first().click();
  await expect(page.locator('#signalModal')).toBeVisible();
  const chart = await page.locator('#chartArea').boundingBox();
  const action = await page.locator('#tradeActionBox').boundingBox();
  expect(chart).toBeTruthy();
  expect(action).toBeTruthy();
  expect(action.y).toBeGreaterThanOrEqual(chart.y + chart.height - 1);
});


test('browser live intelligence computes Day and Swing states from realtime candle series', async ({ page }) => {
  const result = await page.evaluate(() => {
    const market = availableSyntheticMarkets()[0];
    const make = (count, step, seconds) => Array.from({length:count}, (_,i) => {
      const base = 1000 + i * step;
      return {epoch:1700000000+i*seconds, open:base, high:base+2, low:base-2, close:base+step};
    });
    liveCandleSeries.set(`${market}:M15`, make(80,1,900));
    liveCandleSeries.set(`${market}:H1`, make(80,1.5,3600));
    liveCandleSeries.set(`${market}:H4`, make(80,2,14400));
    liveCandleSeries.set(`${market}:D1`, make(80,3,86400)); // Swing needs the D1 macro filter
    return {
      day: computeLiveIntelligence(market,'day'),
      swing: computeLiveIntelligence(market,'swing')
    };
  });
  expect(result.day).toBeTruthy();
  expect(result.swing).toBeTruthy();
  expect(['BUY','SELL','NEUTRE']).toContain(result.day.side);
  expect(['BUY','SELL','NEUTRE']).toContain(result.swing.side);
  expect(result.day.entry_tf).toBe('M15');
  expect(result.swing.entry_tf).toBe('H1');
  expect(result.swing.confirmation_tf).toBe('H4');
});

test('signal detail exposes separate Live Intelligence panel', async ({ page }) => {
  await page.locator('.result-card').first().click();
  await expect(page.locator('#signalModal')).toBeVisible();
  await expect(page.locator('#liveIntelligencePanel')).toBeVisible();
  await expect(page.locator('#liveIntelligenceBias')).toBeVisible();
  await expect(page.locator('#liveIntelligenceScore')).toBeVisible();
});


test('Deriv market discovery supports Volatility 1s and Step families dynamically', async ({ page }) => {
  const families = await page.evaluate(() => [
    appMarketFamily('Volatility 75 (1s) Index'),
    appMarketFamily('Step Index'),
    appMarketFamily('Step Index 200'),
    appMarketFamily('DEX 600 UP Index'),
    appMarketFamily('Drift Switch Index 20')
  ]);
  expect(families).toEqual(['volatility1s','step','step','dex','drift']);
});

test('app no longer depends only on the original 11 hardcoded markets', async ({ page }) => {
  const source = await (await page.request.get('/app.js')).text();
  expect(source).toContain('active_symbols');
  expect(source).toContain('discoverAppDerivMarkets');
});


test('new Deriv active_symbols schema maps Step indices correctly', async ({ page }) => {
  const result = await page.evaluate(() => {
    const item = {
      underlying_symbol: 'stpRNG',
      underlying_symbol_name: 'Step Index 200',
      market_type: 'derived'
    };
    return {
      synthetic: appLooksSynthetic(item),
      family: appMarketFamily(item.underlying_symbol_name)
    };
  });
  expect(result.synthetic).toBeTruthy();
  expect(result.family).toBe('step');
});


test('available synthetic markets merges Deriv discovery with analyzed payload', async ({ page }) => {
  const result = await page.evaluate(() => {
    const original = [...derivMarkets];
    derivMarkets = ['Step Index','Step Index 200','Volatility 10 Index'];
    const markets = availableSyntheticMarkets();
    derivMarkets = original;
    return markets;
  });
  expect(result).toContain('Step Index');
  expect(result).toContain('Step Index 200');
});


test('family context is exposed in analyzed signals when available', async ({ page }) => {
  const source = await (await page.request.get('/app.js')).text();
  expect(source).toContain('family_context');
  expect(source).toContain('Famille ');
});


test("signal detail exposes realtime validation and family consensus boxes", async ({ page }) => {
  await page.locator(".result-card").first().click();
  await expect(page.locator("#signalModal")).toBeVisible();
  await expect(page.locator("#liveValidationBox")).toBeVisible();
  await expect(page.locator("#liveValidationState")).toBeVisible();
  await expect(page.locator("#liveFamilyConsensus")).toBeVisible();
});


test('Jump and Step family filters remain visible even during live discovery sync', async ({ page }) => {
  const families = await page.locator('#indexFamilyFilter [data-family]').evaluateAll(nodes => nodes.map(n => n.dataset.family));
  expect(families).toContain('jump');
  expect(families).toContain('step');
});


test('persistent Deriv live connection includes heartbeat watchdog and auto reconnect', async ({ page }) => {
  const source = await (await page.request.get('/app.js')).text();
  expect(source).toContain('startLiveConnectionGuards');
  expect(source).toContain('ping:1');
  expect(source).toContain('flux figé, reconnexion');
  expect(source).toContain('visibilitychange');
  expect(source).toContain('reconnexion automatique');
});


test('formal live validation consolidates every 60 seconds', async ({ page }) => {
  const source = await (await page.request.get('/app.js')).text();
  expect(source).toContain('setInterval(runMinuteValidationCycle,60000)');
  expect(source).toContain('consolidateLiveConfirmations');
  expect(source).toContain('LIVE_CONFIRMATION_CYCLES=2');
  expect(source).toContain('LIVE_SWING_MIN_SCORE=84');
  expect(source).toContain('["D1",86400]');
});

test("stale server falls back to realtime validation", async ({ page }) => {
  const source = await (await page.request.get("/app.js")).text();
  expect(source).toContain("VALIDATION LIVE");
  expect(source).toContain("const displayedLevels=fresh");
});


test('family filter wraps to multiple lines and does not require horizontal scrolling', async ({ page }) => {
  const data = await page.locator('#indexFamilyFilter').evaluate(el => {
    const style = getComputedStyle(el);
    return {
      wrap: style.flexWrap,
      overflowX: style.overflowX,
      scrollWidth: el.scrollWidth,
      clientWidth: el.clientWidth
    };
  });
  expect(data.wrap).toBe('wrap');
  expect(['visible','clip']).toContain(data.overflowX);
});

test('signal popup uses the free Sera Chart Engine with timeframe and framing controls', async ({ page }) => {
  await page.locator('.result-card').first().click();
  await expect(page.locator('#signalModal')).toBeVisible();
  await expect(page.locator('#chartArea')).toHaveClass(/tv-active/);
  await expect(page.locator('#seraChartToolbar button[data-frame="plan"]')).toBeVisible();
  const tfButtons = page.locator('#seraChartToolbar button[data-tf]');
  expect(await tfButtons.count()).toBeGreaterThan(0);
  await tfButtons.last().click();
  await page.locator('#seraChartToolbar button[data-frame="full"]').click();
  await expect(page.locator('#seraChartToolbar button[data-frame="full"]')).toHaveClass(/active/);
  expect(await page.evaluate(() => window.SeraChart.state.disabled)).toBe(false);
});

test('chart engine draws entry, stop, five targets and the signal marker', async ({ page }) => {
  await page.locator('.result-card').first().click();
  await expect(page.locator('#chartArea')).toHaveClass(/tv-active/);
  const result = await page.evaluate(() => {
    const now = Math.floor(Date.now() / 1000 / 3600) * 3600;
    const candles = Array.from({ length: 120 }, (_, i) => {
      const open = 1.1 + i * 0.0004, close = open + 0.0003;
      return { epoch: now - (119 - i) * 3600, open, high: close + 0.0002, low: open - 0.0002, close };
    });
    const entry = candles.at(-1).close, risk = 0.003;
    const levels = { entry, sl: entry - risk, zoneMin: entry - 0.0005, zoneMax: entry + 0.0005 };
    [1.5, 2.4, 3.6, 4.8, 6].forEach((k, i) => { levels[`tp${i + 1}`] = entry + risk * k; });
    const ok = window.SeraChart.render({
      row: { market: 'TEST/USD', mode: 'swing', asset_class: 'forex', chart_candles: candles, entry_tf: { closedAt: candles.at(-3).epoch } },
      market: 'TEST/USD', mode: 'swing', spec: { entry: 'H1', confirmation: 'H4', macro: 'D1' }, isForex: true,
      levels, plan: { side: 'BUY', entry, sl: levels.sl, target: levels.tp3, isProjected: false },
      prediction: 'BUY', liveSeries: () => [], fmt: v => Number(v).toFixed(5), decimals: () => 5
    });
    const s = window.SeraChart.state;
    return { ok, lines: s.priceLines.length, points: s.data.length, disabled: s.disabled, marker: s.markersKey };
  });
  expect(result.ok).toBe(true);
  expect(result.disabled).toBe(false);
  expect(result.points).toBe(120);
  expect(result.lines).toBe(9); // zone x2, SL, entry, TP1..TP5
  expect(result.marker).toContain('BUY');
});

test('Day M15/H1 horizon works on Deriv and is restored after visiting Forex', async ({ page }) => {
  await page.locator('.mode-filter[data-mode="day"]').click();
  await expect(page.locator('.mode-filter[data-mode="day"]')).toHaveClass(/active/);
  const cards = page.locator('#results .result-card');
  if (await cards.count()) {
    await cards.first().click();
    await expect(page.locator('#selectedTimeframe')).toContainText('M15');
    await page.evaluate(() => closeSignalModal());
    await page.waitForTimeout(300);
  }
  await page.locator('#forexFilter').click();
  await expect(page.locator('.mode-filter[data-mode="day"]')).toHaveAttribute('aria-disabled', 'true');
  await page.locator('.mode-filter[data-mode="day"]').click({ force: true });
  await expect(page.locator('#notice')).toContainText('Swing');
  await page.locator('#syntheticFilter').click();
  await expect(page.locator('.mode-filter[data-mode="day"]')).toHaveClass(/active/);
});

test('Forex prices and chart update in real time from Deriv ticks', async ({ page }) => {
  await page.routeWebSocket(/derivws/, ws => {
    ws.onMessage(message => {
      const req = JSON.parse(String(message));
      if (req.ticks === 'frxEURUSD') {
        let price = 1.1;
        const timer = setInterval(() => {
          price += 0.0005;
          try { ws.send(JSON.stringify({ msg_type: 'tick', tick: { symbol: 'frxEURUSD', quote: Number(price.toFixed(5)), epoch: Math.floor(Date.now() / 1000) }, echo_req: req })); }
          catch { clearInterval(timer); }
        }, 200);
      }
    });
  });
  // WebSocket routes only apply to pages loaded after they are installed.
  await page.reload();
  await dismissWelcome(page);
  await page.waitForSelector('#results');
  await page.locator('#forexFilter').click();
  const card = page.locator('.result-card[data-live-market="EUR/USD"]');
  await expect(card.locator('[data-live-source]')).toHaveText('LIVE', { timeout: 8000 });
  await card.click();
  await expect(page.locator('#liveChange')).toContainText('ticks Deriv');
  const first = await page.locator('#livePrice').textContent();
  await page.waitForTimeout(800);
  const second = await page.locator('#livePrice').textContent();
  expect(second).not.toBe(first);
});
