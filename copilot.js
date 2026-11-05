/*
 * Sera Copilot — panneau de lecture du marché pour la fenêtre de détail.
 *
 * - Scan du marché en 4 lignes (structure, liquidité, impulsion, momentum) calculé sur les vraies bougies live.
 * - Résumé automatique : texte généré par des règles à partir du scan (ce n'est pas un LLM).
 * - Carte de signal : reprend le plan d'app.js (entrée / TP / SL / R:R) et les 4 étapes Détection → Validation → Risque → Exécution.
 * - Performance : chiffres du BACKTEST mesuré (data/playbook-stats.json), jamais un résultat de compte réel.
 * - Bande de cotations : prix live, variation et mini-courbe des ticks déjà reçus par app.js.
 *
 * Le panneau n'envoie aucun ordre : l'exécution reste du ressort de l'EA MT5.
 * app.js appelle SeraCopilot.render(ctx) et SeraCopilot.renderTickers(ctx).
 */
(function(){
  "use strict";

  const RAW="https://raw.githubusercontent.com/serakatsuva/sera-indicator/main/data/";
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??"").replace(/[&<>'"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]));
  const fr=(v,d=1)=>Number.isFinite(Number(v))?Number(v).toLocaleString("fr-FR",{maximumFractionDigits:d}):"—";
  const MIN_CANDLES=30;
  const MIN_RR=1.5;

  let stats=null,statsLoading=false;

  // ---------- Calculs purs (testables : SeraCopilot._scan) ----------

  function emaFull(values,period){
    const k=2/(period+1);
    let v=values[0];
    for(let i=1;i<values.length;i++)v=v+k*(values[i]-v);
    return v;
  }

  function cleanCandles(candles){
    if(!Array.isArray(candles))return [];
    return candles.map(c=>({open:+c.open,high:+c.high,low:+c.low,close:+c.close}))
      .filter(c=>Object.values(c).every(Number.isFinite)&&c.high>=c.low);
  }

  function scan(candles){
    const rows=cleanCandles(candles).slice(-120);
    if(rows.length<MIN_CANDLES)return null;
    const closes=rows.map(c=>c.close),last=rows.at(-1);
    const ema20=emaFull(closes,20),ema50=emaFull(closes,Math.min(50,closes.length));

    // RSI 14 (moyennes simples, comme analyzeLiveCandles)
    const tail=closes.slice(-15);
    let gain=0,loss=0;
    for(let i=1;i<tail.length;i++){const d=tail[i]-tail[i-1];if(d>0)gain+=d;else loss-=d;}
    const rsi=loss===0?100:100-100/(1+gain/loss);

    // ATR 14
    const trs=rows.slice(-15).map((c,i,a)=>{const p=i?a[i-1].close:c.open;return Math.max(c.high-c.low,Math.abs(c.high-p),Math.abs(c.low-p));});
    const atr=trs.reduce((a,b)=>a+b,0)/Math.max(1,trs.length);

    // 1) Structure : sommets/creux comparés sur deux fenêtres
    const older=rows.slice(-18,-10),newer=rows.slice(-9,-1);
    const hh=Math.max(...newer.map(c=>c.high))>Math.max(...older.map(c=>c.high));
    const hl=Math.min(...newer.map(c=>c.low))>Math.min(...older.map(c=>c.low));
    const lh=Math.max(...newer.map(c=>c.high))<Math.max(...older.map(c=>c.high));
    const ll=Math.min(...newer.map(c=>c.low))<Math.min(...older.map(c=>c.low));
    const structure=hh&&hl?1:lh&&ll?-1:0;

    // 2) Liquidité : une des 3 dernières bougies perce le creux/sommet des 20 précédentes puis la clôture revient
    const recent=rows.slice(-3),ref=rows.slice(-23,-3);
    let sweep={dir:0,level:NaN};
    if(ref.length>=10){
      const refLow=Math.min(...ref.map(c=>c.low)),refHigh=Math.max(...ref.map(c=>c.high));
      const bull=recent.some(c=>c.low<refLow)&&last.close>refLow;
      const bear=recent.some(c=>c.high>refHigh)&&last.close<refHigh;
      if(bull&&!bear)sweep={dir:1,level:refLow};
      else if(bear&&!bull)sweep={dir:-1,level:refHigh};
    }

    // 3) Impulsion : amplitude moyenne des 3 dernières bougies rapportée à l'ATR (Deriv ne fournit pas de volume)
    const range3=recent.reduce((s,c)=>s+(c.high-c.low),0)/recent.length;
    const ratio=atr>0?range3/atr:0;
    const net=recent.at(-1).close-recent[0].open;
    const impulse=ratio>=1.2?(net>0?1:net<0?-1:0):0;

    // 4) Momentum : RSI + EMA20/EMA50 + prix vs EMA20
    const mom=(last.close>ema20&&ema20>ema50&&rsi>52)?1:(last.close<ema20&&ema20<ema50&&rsi<48)?-1:0;

    const votes=structure+sweep.dir+impulse+mom;
    const bias=votes>=2?"BUY":votes<=-2?"SELL":"NEUTRE";
    return {price:last.close,ema20,ema50,rsi,atr,ratio,structure,sweep,impulse,mom,votes,bias};
  }

  const stateOf=v=>v>0?"bull":v<0?"bear":"neutral";

  function scanRows(s,fmt){
    return [
      {key:"structure",label:"Structure de marché",state:stateOf(s.structure),
        text:s.structure>0?"Haussière HH/HL":s.structure<0?"Baissière LH/LL":"Mixte"},
      {key:"liquidity",label:"Zones de liquidité",state:stateOf(s.sweep.dir),
        text:s.sweep.dir>0?`Creux balayé ${fmt(s.sweep.level)}`:s.sweep.dir<0?`Sommet balayé ${fmt(s.sweep.level)}`:"Aucun balayage"},
      {key:"impulse",label:"Impulsion (amplitude/ATR)",state:stateOf(s.impulse),
        text:s.impulse>0?`Acheteuse ×${fr(s.ratio)}`:s.impulse<0?`Vendeuse ×${fr(s.ratio)}`:`Calme ×${fr(s.ratio)}`},
      {key:"momentum",label:"Momentum (RSI / EMA)",state:stateOf(s.mom),
        text:`${s.mom>0?"Haussier":s.mom<0?"Baissier":"Neutre"} · RSI ${fr(s.rsi,0)}`}
    ];
  }

  function overview(market,s,plan,fmt){
    const bits=[];
    bits.push(`structure ${s.structure>0?"haussière":s.structure<0?"baissière":"mixte"}`);
    bits.push(s.sweep.dir>0?`creux ${fmt(s.sweep.level)} balayé puis repris`:s.sweep.dir<0?`sommet ${fmt(s.sweep.level)} balayé puis rejeté`:"aucune liquidité balayée");
    bits.push(s.impulse!==0?`impulsion ${s.impulse>0?"acheteuse":"vendeuse"} (×${fr(s.ratio)} l'ATR)`:"impulsion faible");
    bits.push(`momentum ${s.mom>0?"haussier":s.mom<0?"baissier":"neutre"}`);
    const bias=s.bias==="BUY"?"haussier":s.bias==="SELL"?"baissier":"neutre";
    let txt=`${market} : ${bits.join(", ")}. Biais ${bias} (${s.votes>0?"+":""}${s.votes}/4).`;
    if(plan&&(plan.side==="BUY"||plan.side==="SELL")){
      txt+=s.bias!=="NEUTRE"&&s.bias!==plan.side
        ?` Attention : le scan va à l'opposé du plan ${plan.side}.`
        :` Plan ${plan.side}, objectif ${fmt(plan.target)}.`;
    }
    return txt;
  }

  // ---------- Performance mesurée (backtest) ----------

  function groupFor(market){
    const n=String(market||"").toUpperCase().replace(/\s+/g,"");
    if(n.includes("BULLMARKET")||n.includes("BEARMARKET"))return "bullbear";
    if(n.includes("BOOM")||n.includes("CRASH")||n.includes("GAINX")||n.includes("PAINX"))return "spike";
    return null;
  }

  async function loadStats(){
    if(stats||statsLoading)return;
    statsLoading=true;
    for(const url of [`./data/playbook-stats.json?t=${Date.now()}`,`${RAW}playbook-stats.json?t=${Date.now()}`]){
      try{const r=await fetch(url,{cache:"no-store"});if(r.ok){stats=await r.json();break;}}catch(e){/* source suivante */}
    }
    statsLoading=false;
    if(stats&&lastCtx)render(lastCtx);
  }

  function performanceHtml(market){
    const group=groupFor(market);
    const g=group&&(stats?.precision?.groups?.[group]?.all||stats?.groups?.[group]?.all);
    const period=stats?.period?`${stats.period.from} → ${stats.period.to}`:"";
    if(!stats)return `<p class="cp-muted">Chargement de la performance mesurée…</p>`;
    if(!g)return `<p class="cp-muted">Aucune mesure de backtest pour cet indice : aucune performance affichée.</p>`;
    return `<div class="cp-perf-grid">
      <div><small>Trades testés</small><strong>${fr(g.trades,0)}</strong></div>
      <div><small>Atteignent TP1</small><strong>${fr(g.tp1_rate)} %</strong></div>
      <div><small>Perdants</small><strong>${fr(g.losing_rate)} %</strong></div>
      <div><small>Espérance / trade</small><strong>${g.expectancy_r>=0?"+":""}${Number(g.expectancy_r).toLocaleString("fr-FR",{minimumFractionDigits:2,maximumFractionDigits:2})} R</strong></div>
    </div>
    <p class="cp-muted">Backtest ${esc(period)} · ${fr(g.positive_months,0)}/${fr(g.months,0)} mois gagnants · 1 R = le risque pris. Résultat passé, hors frais réels ni glissement : aucune garantie.</p>`;
  }

  // ---------- Rendu ----------

  let lastCtx=null;

  function ring(pct){
    const v=Math.max(0,Math.min(100,Number(pct)||0)),c=2*Math.PI*18;
    return `<svg viewBox="0 0 44 44" class="cp-ring" aria-hidden="true"><circle cx="22" cy="22" r="18" class="bg"/><circle cx="22" cy="22" r="18" class="fg" stroke-dasharray="${(c*v/100).toFixed(1)} ${c.toFixed(1)}" transform="rotate(-90 22 22)"/></svg><b>${Math.round(v)}%</b>`;
  }

  function render(ctx){
    lastCtx=ctx;
    const host=$("copilotPanel");
    if(!host||!ctx)return false;
    loadStats();
    const fmt=ctx.fmt||(v=>String(v));
    const s=scan(ctx.candles);
    const plan=ctx.plan||null;

    const scanBox=$("cpScan"),sumBox=$("cpOverview"),cardBox=$("cpSignal"),stepBox=$("cpSteps"),perfBox=$("cpPerf"),chip=$("cpBias");
    if(!s){
      chip.textContent="SYNC…";chip.className="cp-chip neutral";
      scanBox.innerHTML=`<p class="cp-muted">Bougies live en cours de chargement (30 minimum).</p>`;
      sumBox.textContent="Le scan démarre dès que l'historique est reçu.";
    }else{
      chip.textContent=s.bias==="BUY"?"BIAIS HAUSSIER":s.bias==="SELL"?"BIAIS BAISSIER":"BIAIS NEUTRE";
      chip.className=`cp-chip ${stateOf(s.bias==="BUY"?1:s.bias==="SELL"?-1:0)}`;
      scanBox.innerHTML=scanRows(s,fmt).map(r=>`<div class="cp-scan-row ${r.state}"><i></i><span>${esc(r.label)}</span><b>${esc(r.text)}</b></div>`).join("");
      sumBox.textContent=overview(ctx.market,s,plan,fmt);
    }

    if(plan&&(plan.side==="BUY"||plan.side==="SELL")){
      const long=plan.side==="BUY";
      cardBox.className=`cp-signal ${long?"buy":"sell"}`;
      cardBox.innerHTML=`<div class="cp-signal-head"><span class="cp-side">${long?"LONG":"SHORT"}</span><strong>${esc(ctx.market)}</strong><div class="cp-conf">${ring(ctx.confidence)}</div></div>
        <small class="cp-muted">${esc(plan.timeframe||"")} · ${plan.isProjected?"scénario projeté, non exécutable":"plan confirmé"} · confiance = score du moteur</small>
        <dl class="cp-levels">
          <div><dt>Entrée</dt><dd>${fmt(plan.entry)}</dd></div>
          <div><dt>Objectif (TP3)</dt><dd class="tp">${fmt(plan.target)}</dd></div>
          <div><dt>Stop</dt><dd class="sl">${fmt(plan.sl)}</dd></div>
          <div><dt>Risque : gain</dt><dd>1 : ${fr(plan.rr,2)}</dd></div>
        </dl>`;
    }else{
      cardBox.className="cp-signal wait";
      cardBox.innerHTML=`<div class="cp-signal-head"><span class="cp-side">WAIT</span><strong>${esc(ctx.market)}</strong></div><p class="cp-muted">Aucun plan valide pour l'instant : le moteur attend une entrée confirmée. Rien n'est à exécuter.</p>`;
    }

    const steps=ctx.steps||[];
    const firstOpen=steps.findIndex(x=>!x.done);
    stepBox.innerHTML=steps.map((x,i)=>`<li class="${x.done?"done":i===firstOpen?"current":""}"><i>${x.done?"✓":i+1}</i><span>${esc(x.label)}</span></li>`).join("");

    perfBox.innerHTML=performanceHtml(ctx.market);
    return true;
  }

  // ---------- Bande de cotations ----------

  function spark(points,up){
    const v=points.filter(Number.isFinite);
    if(v.length<3)return "";
    const min=Math.min(...v),max=Math.max(...v),span=max-min||1;
    const d=v.map((p,i)=>`${i?"L":"M"}${(i/(v.length-1)*60).toFixed(1)},${(16-((p-min)/span)*14-1).toFixed(1)}`).join("");
    return `<svg viewBox="0 0 60 16" class="cp-spark ${up?"up":"down"}" aria-hidden="true"><path d="${d}"/></svg>`;
  }

  function renderTickers(ctx){
    const host=$("cpTickers");
    if(!host||!ctx)return;
    const items=(ctx.items||[]).slice(0,4);
    host.hidden=!items.length;
    host.innerHTML=items.map(it=>`<button type="button" class="cp-ticker ${it.active?"active":""}" data-cp-market="${esc(it.market)}">
      <span class="cp-tk-name">${esc(it.market)}</span>
      <strong>${esc(it.price)}</strong>
      ${spark(it.spark,it.deltaPct>=0)}
      <em class="${it.deltaPct>=0?"up":"down"}">${it.deltaPct>=0?"+":""}${fr(it.deltaPct,3)} %</em>
    </button>`).join("");
  }

  document.addEventListener("click",event=>{
    const btn=event.target.closest&&event.target.closest("[data-cp-market]");
    if(!btn)return;
    const select=$("marketSelect");
    if(!select)return;
    select.value=btn.dataset.cpMarket;
    select.dispatchEvent(new Event("change",{bubbles:true}));
  });

  window.SeraCopilot={render,renderTickers,_scan:scan,_groupFor:groupFor,_overview:overview,MIN_RR};
})();
