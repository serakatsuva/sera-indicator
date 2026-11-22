// Sera Indicator — page « Positions » : uniquement les anticipations APA (price action) et MSNR (OCL + SNR).
// Lit data/positions-signals.json. Anticipations, pas des ordres : la fiabilité vient de mesures (data/msnr-stats.json).
(function(){
  "use strict";
  const RAW="https://raw.githubusercontent.com/serakatsuva/sera-indicator/main/data/";
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??"").replace(/[&<>'"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]));
  const num=v=>{const n=Number(v);return Number.isFinite(n)?n:null;};
  const price=v=>{const n=num(v);if(n===null)return "—";return n.toLocaleString("fr-FR",{maximumFractionDigits:Math.abs(n)>=1000?2:Math.abs(n)>=10?3:5});};
  const STATUS={IN_ZONE:"Dans la zone",WAIT_RETEST:"Attendre le retest",ARMED:"Armée (déclencheur)"};
  const state={data:null,market:"",method:"",side:"",style:"",phase:"",rel:"edge"};
  let registry=[];

  async function load(){
    for(const url of [`${RAW}positions-signals.json?t=${Date.now()}`,`./data/positions-signals.json?t=${Date.now()}`]){
      try{const r=await fetch(url,{cache:"no-store"});if(r.ok)return await r.json();}catch(e){/* source suivante */}
    }
    return null;
  }

  // Même logique que scripts/position-phase.mjs
  function phaseOf(p,px){
    const n=num(px);if(n===null)return "UPCOMING";
    const d=p.side==="BUY"?1:-1,risk=Math.abs(p.entry-p.sl);
    if(!(risk>0))return "PASSED";
    if((n-p.sl)*d<=0||(n-p.tp1)*d>=0)return "PASSED";
    const zmin=num(p.zone_min)??p.entry,zmax=num(p.zone_max)??p.entry,tol=num(p.zone_tol)||0;
    if(n>=zmin-tol&&n<=zmax+tol)return "NOW";
    const dist=Math.abs(n-p.entry)/risk;
    if(p.order==="STOP"){
      if((n-p.entry)*d<0)return dist<=1.5?"PREP":"UPCOMING";
      return dist<=0.3?"NOW":"PASSED";
    }
    const onTarget=p.side==="BUY"?n>zmax+tol:n<zmin-tol;
    if(!onTarget)return "PASSED";
    return dist<=1.5?"PREP":"UPCOMING";
  }
  // Prix en direct (ticks Deriv) — remplace le prix publié dès qu'un tick arrive.
  const WS_URL="wss://api.derivws.com/trading/v1/options/ws/public?app_id=1089";
  const livePrice=new Map(),listeners=new Set();
  let liveWs=null,liveSymbols=[],liveRetry=0,liveDirty=false;
  const priceOf=m=>livePrice.has(m.symbol)?livePrice.get(m.symbol):m.price;
  function startLive(symbols){
    const list=[...new Set(symbols)].sort();
    if(liveWs&&list.join()===liveSymbols.join())return;
    liveSymbols=list;
    if(liveWs){try{liveWs.close();}catch(e){}liveWs=null;}
    if(!list.length)return;
    let ws;try{ws=new WebSocket(WS_URL);}catch(e){return;}
    liveWs=ws;
    ws.addEventListener("open",()=>{liveRetry=0;list.forEach(s=>ws.send(JSON.stringify({ticks:s,subscribe:1}))); setLiveBadge(true);});
    ws.addEventListener("message",ev=>{
      let msg;try{msg=JSON.parse(ev.data);}catch(e){return;}
      const t=msg.tick;if(!t||!t.symbol)return;
      const q=Number(t.quote);if(!Number.isFinite(q))return;
      livePrice.set(t.symbol,q);liveDirty=true;
      listeners.forEach(fn=>{try{fn(t.symbol,q,Number(t.epoch));}catch(e){}});
    });
    const retry=()=>{if(liveWs!==ws)return;liveWs=null;setLiveBadge(false);liveRetry=Math.min(liveRetry+1,6);setTimeout(()=>startLive(liveSymbols.slice()),1000*2**liveRetry);};
    ws.addEventListener("close",retry);ws.addEventListener("error",()=>{try{ws.close();}catch(e){}});
  }
  function setLiveBadge(on){const b=$("posLive");if(b){b.textContent=on?"● Prix en direct":"○ Prix publié (connexion…)";b.className="pos-live "+(on?"on":"off");}}
  window.SeraLive={get:s=>livePrice.get(s),subscribe:fn=>{listeners.add(fn);return()=>listeners.delete(fn);}};

  const REL_LABEL={EDGE:"Avantage mesuré",PARTIAL:"Avantage sur 2 mois seulement",NEUTRAL:"Sans avantage net",NEGATIVE:"Perdant sur l’historique",UNMEASURED:"Non mesuré"};
  const REL_ORDER={EDGE:0,PARTIAL:1,NEUTRAL:2,UNMEASURED:3,NEGATIVE:4};
  const relOf=p=>p.reliability||"UNMEASURED";
  const PHASE_LABEL={NOW:"Entrer maintenant",PREP:"En préparation",UPCOMING:"À venir"};
  const PHASE_ORDER={NOW:0,PREP:1,UPCOMING:2};

  function live(p,px){
    const n=num(px);if(n===null)return "";
    const d=p.side==="BUY"?1:-1;
    if((n-p.sl)*d<=0)return "invalidée (SL touché)";
    if((n-p.tp1)*d>=0)return "objectif TP1 déjà atteint";
    const zmin=num(p.zone_min)??p.entry,zmax=num(p.zone_max)??p.entry,tol=num(p.zone_tol)||0;
    if(n>=zmin-tol&&n<=zmax+tol)return "prix dans la zone d’entrée";
    const dist=Math.abs(n-p.entry)/Math.abs(p.entry-p.sl);
    return `prix à ${dist.toLocaleString("fr-FR",{maximumFractionDigits:1})} R de l’entrée`;
  }

  function relBlock(p){
    const rel=relOf(p),mm=p.measured;
    const line=mm?`Mesuré sur un an : TP1 atteint ${String(mm.tp1_rate).replace(".",",")} % (équilibre ${String(mm.breakeven_rate).replace(".",",")} %), ${mm.exp_r>=0?"+":""}${String(mm.exp_r).replace(".",",")} R par trade`:(p.method==="APA"?"Price action : pas encore mesuré":"Pas assez de recul pour mesurer");
    return `<div class="pos-rel ${esc(rel)}"><b>${esc(REL_LABEL[rel])}</b><small>${esc(line)}</small></div>`;
  }

  function card(m,p,idx,phase){
    const cls=p.side==="BUY"?"buy":"sell";
    const q=Math.max(0,Math.min(95,Number(p.quality)||0));
    const tags=[p.aligned?"aligné sur la structure":"contre / hors structure",p.liquidity_swept?"liquidité prise":"",p.ocl_double?"OCL double":""].filter(Boolean);
    return `<article class="wt-card ${cls} pos-card" data-pos-market="${esc(m.market)}">
      <div class="wt-top"><div><h3>${esc(m.market)}</h3><p>${esc(p.setup)} · ${esc(p.tf)}</p></div><span class="wt-signal ${cls}">${esc(p.side)}</span></div>
      <div class="pos-phase ${esc(phase)}">${esc(PHASE_LABEL[phase]||"")}</div> <span class="pos-px">Prix ${price(priceOf(m))}</span>
      ${relBlock(p)}
      <div class="wt-levels">
        <div><small>${esc(p.order==="STOP"?"Entrée (stop)":"Entrée (limite)")}</small><strong>${price(p.entry)}</strong></div>
        <div class="danger"><small>SL</small><strong>${price(p.sl)}</strong></div>
        <div><small>TP1</small><strong>${price(p.tp1)}</strong></div>
        <div><small>TP2</small><strong>${price(p.tp2)}</strong></div>
      </div>
      <div class="wt-meta"><span>${esc(STATUS[p.status]||p.status)}</span><span>R:R ${esc(p.rr1)} / ${esc(p.rr2)}</span><span>${esc(p.method)}</span></div>
      <p class="pos-note">${esc(tags.join(" · "))}${live(p,priceOf(m))?` — ${esc(live(p,priceOf(m)))}`:""}</p>
      <button type="button" class="pos-btn" data-pos-open="${idx}">📈 Voir le graphique</button>
    </article>`;
  }

  function render(){
    const list=$("posList"),note=$("posNotice"),sel=$("posMarket");
    if(!list)return;
    const d=state.data;
    if(!d){if(note){note.className="notice error";note.textContent="Positions indisponibles pour le moment.";}return;}
    const markets=d.markets||[];
    if(sel&&sel.options.length<=1)for(const m of markets){const o=document.createElement("option");o.value=m.market;o.textContent=m.market;sel.appendChild(o);}
    const items=[];
    for(const m of markets){
      if(state.market&&m.market!==state.market)continue;
      for(const p of m.positions){
        if(state.method&&p.method!==state.method)continue;
        if(state.side&&p.side!==state.side)continue;
        if(state.style&&p.mode!==state.style)continue;
        const rel=relOf(p);
        if(state.rel==="edge"&&rel!=="EDGE"&&rel!=="PARTIAL")continue;
        const phase=phaseOf(p,priceOf(m));
        if(phase==="PASSED")continue;
        if(state.phase&&phase!==state.phase)continue;
        items.push({m,p,phase});
      }
    }
    items.sort((a,b)=>PHASE_ORDER[a.phase]-PHASE_ORDER[b.phase]||REL_ORDER[relOf(a.p)]-REL_ORDER[relOf(b.p)]||b.p.quality-a.p.quality);
    registry=items;
    list.innerHTML=items.length?items.map((x,i)=>card(x.m,x.p,i,x.phase)).join(""):`<p class="wt-empty">Aucune position anticipée avec ces filtres.</p>`;
    if(note){note.className="notice";note.textContent=`${items.length} position(s) affichée(s) · mise à jour ${d.updated_at?new Date(d.updated_at).toLocaleString("fr-FR"):"—"} · ${d.disclaimer||""}`;}
  }

  function bind(){
    const list=$("posList");
    if(list)list.addEventListener("click",e=>{
      const b=e.target.closest("[data-pos-open]");if(!b)return;
      const it=registry[Number(b.dataset.posOpen)];
      if(it&&window.SeraPositionChart)window.SeraPositionChart.open(it.m,it.p);
    });
    for(const [id,key] of [["posMarket","market"],["posMethod","method"],["posSide","side"],["posStyle","style"],["posPhase","phase"],["posRel","rel"]]){
      const el=$(id);if(el)el.addEventListener("change",()=>{state[key]=el.value;render();});
    }
  }

  function setView(view,updateHash){
    const pos=view==="positions";
    document.body.classList.toggle("view-positions",pos);
    for(const b of document.querySelectorAll(".view-tab")){
      const on=b.dataset.view===view;b.classList.toggle("active",on);b.setAttribute("aria-selected",String(on));
    }
    if(updateHash)history.replaceState(null,"",pos?"#positions":location.pathname+location.search);
    window.scrollTo(0,0);
  }

  async function init(){
    if(!$("positions"))return;
    for(const b of document.querySelectorAll(".view-tab"))b.addEventListener("click",()=>setView(b.dataset.view,true));
    window.addEventListener("hashchange",()=>{if(location.hash==="#positions")setView("positions",false);});
    // Ouverture par défaut sur Positions, sauf si l'URL demande explicitement une autre section.
    if(!location.hash||location.hash==="#positions")setView("positions",false);
    bind();
    state.data=await load();
    render();
    startLive((state.data?.markets||[]).map(m=>m.symbol));
    setInterval(()=>{if(liveDirty&&!document.hidden){liveDirty=false;render();}},5000);
    setInterval(async()=>{const d=await load();if(d){state.data=d;render();startLive(d.markets.map(m=>m.symbol));}},120000);
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",init);else init();
})();
