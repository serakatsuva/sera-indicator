// Sera Indicator — onglet Crypto (Swing H1/H4/D1). Bougies publiques Deriv (WebSocket), analyse dans le navigateur avec crypto-engine.js.
// Repli : data/crypto-signals.json (script serveur scripts/update-crypto.mjs) si le WebSocket est indisponible.
(function(){
  "use strict";
  const WS_URL="wss://api.derivws.com/trading/v1/options/ws/public?app_id=1089";
  const FALLBACK=[["cryBTCUSD","BTC/USD"],["cryETHUSD","ETH/USD"],["cryLTCUSD","LTC/USD"],["cryXRPUSD","XRP/USD"],["cryBNBUSD","BNB/USD"],["crySOLUSD","SOL/USD"],["cryADAUSD","ADA/USD"],["cryDOGUSD","DOGE/USD"]];
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??"").replace(/[&<>'"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]));
  const BINANCE_API="https://data-api.binance.vision/api/v3/klines";
  const BINANCE_PAIRS=["BTC","ETH","BNB","SOL","XRP","ADA","DOGE","AVAX","LINK","LTC","DOT","TRX"].map(c=>[c+"USDT",c+"/USDT"]);
  let source="deriv";
  try{source=localStorage.getItem("seraCryptoSource")==="binance"?"binance":"deriv";}catch(e){}
  let rows=[],onlySignals=false,strict=true,busy=false,timer=null,savedActive=[];
  try{onlySignals=localStorage.getItem("seraCryptoOnly")==="1";}catch(e){}

  function wsCall(ws,payload,id){
    return new Promise((resolve,reject)=>{
      const t=setTimeout(()=>{ws.removeEventListener("message",on);reject(new Error("timeout"));},15000);
      function on(ev){let m;try{m=JSON.parse(ev.data);}catch(e){return;}if(m.req_id!==id)return;clearTimeout(t);ws.removeEventListener("message",on);m.error?reject(new Error(m.error.message)):resolve(m);}
      ws.addEventListener("message",on);ws.send(JSON.stringify(Object.assign({req_id:id},payload)));
    });
  }
  const toCandles=m=>(m.candles||[]).map(c=>({time:c.epoch,open:+c.open,high:+c.high,low:+c.low,close:+c.close}));
  async function fetchAll(){
    const ws=new WebSocket(WS_URL);
    await new Promise((res,rej)=>{ws.onopen=res;ws.onerror=()=>rej(new Error("ws"));setTimeout(()=>rej(new Error("ws timeout")),12000);});
    let id=1,list=FALLBACK;
    try{
      const a=await wsCall(ws,{active_symbols:"brief",product_type:"basic"},id++);
      const found=(a.active_symbols||[]).filter(s=>s.market==="cryptocurrency"&&/^cry/i.test(s.symbol)).map(s=>[s.symbol,s.display_name||s.symbol]);
      if(found.length)list=found;
    }catch(e){/* liste de repli */}
    const out=[];
    for(const [symbol,name] of list){
      try{
        const get=async(g,count)=>toCandles(await wsCall(ws,{ticks_history:symbol,style:"candles",granularity:g,count,end:"latest"},id++));
        const [h1,h4,d1]=[await get(3600,500),await get(14400,300),await get(86400,200)];
        const s=window.SeraCryptoEngine.analyze(h1,h4,d1,{strict});
        out.push(Object.assign({symbol,name,price:h1.length?h1[h1.length-1].close:null},s));
      }catch(e){out.push({symbol,name,verdict:"ATTENDRE",side:"NEUTRE",score:0,reason:"Données indisponibles",tf:{h1:0,h4:0,d1:0}});}
    }
    try{ws.close();}catch(e){}
    return out;
  }
  async function fetchBinance(){
    const get=async(symbol,interval,limit)=>{
      const r=await fetch(`${BINANCE_API}?symbol=${symbol}&interval=${interval}&limit=${limit}`,{cache:"no-store"});
      if(!r.ok)throw new Error("binance "+r.status);
      return (await r.json()).map(k=>({time:Math.floor(k[0]/1000),open:+k[1],high:+k[2],low:+k[3],close:+k[4],volume:+k[5]}));
    };
    const out=[];let failed=0;
    await Promise.all(BINANCE_PAIRS.map(async([symbol,name])=>{
      try{
        const [h1,h4,d1]=await Promise.all([get(symbol,"1h",500),get(symbol,"4h",300),get(symbol,"1d",200)]);
        out.push(Object.assign({symbol,name,price:h1.length?h1[h1.length-1].close:null},window.SeraCryptoEngine.analyze(h1,h4,d1,{strict})));
      }catch(e){failed++;}
    }));
    if(!out.length)throw new Error("binance indisponible");
    return BINANCE_PAIRS.map(p=>out.find(o=>o.symbol===p[0])).filter(Boolean);
  }
  async function fetchServer(){
    try{const r=await fetch(`./data/${source==="binance"?"binance":"crypto"}-signals.json?t=${Date.now()}`,{cache:"no-store"});if(!r.ok)return null;const j=await r.json();return Array.isArray(j.markets)?j.markets:null;}catch(e){return null;}
  }
  const fmt=v=>{const n=Number(v);if(!Number.isFinite(n))return "—";return n>=100?n.toFixed(2):n>=1?n.toFixed(4):n.toFixed(6);};
  const dot=d=>`<i class="cr-dot ${d>0?"up":d<0?"down":""}">${d>0?"▲":d<0?"▼":"•"}</i>`;
  function detailHtml(m){
    const lines=m.detail?.lines;
    if(!lines||!lines.length)return "";
    return `<details class="cr-detail"><summary>Analyse détaillée</summary><ul>${lines.map(l=>`<li>${esc(l)}</li>`).join("")}</ul></details>`;
  }
  function card(m){
    const cls=m.verdict==="BUY"?"buy":m.verdict==="SELL"?"sell":"wait";
    const levels=m.verdict==="ATTENDRE"?"":`<dl class="cr-levels"><div><dt>Entrée</dt><dd>${fmt(m.entry)}</dd></div><div><dt>Stop</dt><dd class="sl">${fmt(m.sl)}</dd></div><div><dt>TP1 · 1R</dt><dd class="tp">${fmt(m.tp1)}</dd></div><div><dt>TP2 · 2R</dt><dd class="tp">${fmt(m.tp2)}</dd></div><div><dt>TP3 · 3R</dt><dd class="tp">${fmt(m.tp3)}</dd></div></dl>`;
    return `<article class="cr-card ${cls}"><div class="cr-top"><div><h3>${esc(m.name)}</h3><small>${esc(m.symbol)} · ${fmt(m.price)}</small></div><span class="cr-chip ${cls}">${m.verdict==="ATTENDRE"?"ATTENDRE":esc(m.verdict)}</span></div>
      <div class="cr-tf"><span>H1 ${dot(m.tf?.h1)}</span><span>H4 ${dot(m.tf?.h4)}</span><span>D1 ${dot(m.tf?.d1)}</span>${m.verdict!=="ATTENDRE"?`<b title="Score moteur, non calibré">${m.score}</b>`:""}</div>
      <p class="cr-reason">${esc(m.reason||"")}</p>${levels}${detailHtml(m)}</article>`;
  }
  function render(note){
    const box=$("crResults");if(!box)return;
    let list=rows.slice().sort((a,b)=>(b.verdict!=="ATTENDRE")-(a.verdict!=="ATTENDRE")||(b.score||0)-(a.score||0));
    if(onlySignals)list=list.filter(m=>m.verdict!=="ATTENDRE");
    box.innerHTML=list.length?list.map(card).join(""):`<p class="cr-empty">${onlySignals?"Aucun swing crypto ne remplit toutes les conditions pour l'instant. C'est normal en mode strict : attendre vaut mieux que forcer.":"Aucune donnée."}</p>`;
    const n=rows.filter(m=>m.verdict!=="ATTENDRE").length;
    if($("crNotice")){$("crNotice").className="notice "+(rows.length?"success":"warning");$("crNotice").textContent=note||(`${rows.length} cryptos ${source==="binance"?"Binance":"Deriv"} analysées · ${n} swing(s) valide(s) · règle ${strict?"stricte (H1, H4 et D1 alignés)":"souple (H4 et D1 alignés)"}.`);}
    $("crOnly")?.classList.toggle("active",onlySignals);$("crOnly")?.setAttribute("aria-pressed",String(onlySignals));
  }
  async function refresh(){
    if(busy||!window.SeraCryptoEngine)return;busy=true;
    if($("crNotice")){$("crNotice").className="notice loading";$("crNotice").textContent="Analyse des cryptos en cours…";}
    try{rows=source==="binance"?await fetchBinance():await fetchAll();render();}
    catch(e){
      const srv=await fetchServer();
      if(srv){rows=srv;render("Flux direct indisponible : dernière analyse serveur affichée.");}
      else render("Crypto indisponible pour l'instant (flux "+(source==="binance"?"Binance":"Deriv")+" injoignable).");
    }
    busy=false;
  }
  function setMode(on){
    const body=document.body;
    if(on===body.classList.contains("cr-mode"))return;
    if(on&&body.classList.contains("wt-mode"))$("syntheticFilter")?.click();
    const others=["syntheticFilter","forexFilter","weltradeFilter"].map($).filter(Boolean);
    body.classList.toggle("cr-mode",on);
    $("cryptoFilter")?.classList.toggle("active",on);$("cryptoFilter")?.setAttribute("aria-selected",String(on));
    if(on){savedActive=others.filter(b=>b.classList.contains("active"));others.forEach(b=>{b.classList.remove("active");b.setAttribute("aria-selected","false");});
      $("crypto")?.scrollIntoView({behavior:"smooth",block:"start"});refresh();timer=timer||setInterval(()=>{if(document.body.classList.contains("cr-mode"))refresh();},300000);}
    else if(!others.some(b=>b.classList.contains("active")))savedActive.forEach(b=>{b.classList.add("active");b.setAttribute("aria-selected","true");});
  }
  function start(){
    if(!$("crypto"))return;
    $("cryptoFilter")?.addEventListener("click",()=>setMode(true));
    ["syntheticFilter","forexFilter","weltradeFilter"].forEach(id=>$(id)?.addEventListener("click",()=>{if(document.body.classList.contains("cr-mode"))setMode(false);},true));
    $("crOnly")?.addEventListener("click",()=>{onlySignals=!onlySignals;try{localStorage.setItem("seraCryptoOnly",onlySignals?"1":"0");}catch(e){}render();});
    $("crStrict")?.addEventListener("click",()=>{strict=!strict;$("crStrict").textContent=strict?"Règle stricte":"Règle souple";$("crStrict").setAttribute("aria-pressed",String(strict));refresh();});
    $("crRefresh")?.addEventListener("click",refresh);
    document.querySelectorAll("[data-cr-source]").forEach(b=>{
      const sync=()=>{const on=b.dataset.crSource===source;b.classList.toggle("active",on);b.setAttribute("aria-pressed",String(on));};
      sync();
      b.addEventListener("click",()=>{source=b.dataset.crSource;try{localStorage.setItem("seraCryptoSource",source);}catch(e){}
        document.querySelectorAll("[data-cr-source]").forEach(x=>{const on=x.dataset.crSource===source;x.classList.toggle("active",on);x.setAttribute("aria-pressed",String(on));});
        rows=[];refresh();});
    });
    if(location.hash==="#crypto")setMode(true);
  }
  window.SeraCrypto={open:()=>setMode(true),refresh};
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start);else start();
})();
