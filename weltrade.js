// Sera Indicator — onglet Weltrade.
// Weltrade ne publie pas ses prix : c'est l'EA "Sera EA Swing Intelligent Weltrade" (v2.20+) qui envoie
// ses analyses MT5 dans data/weltrade-signals.json (PublishToApp + GitHubToken). Cette page les affiche.
(function(){
  "use strict";
  const RAW="https://raw.githubusercontent.com/serakatsuva/sera-indicator/main/data/weltrade-signals.json";
  const LOCAL="./data/weltrade-signals.json";
  const STALE_MINUTES=20;
  let data=null;
  let filter="all";
  let knownSignals=null;          // id|sens deja vus (annonces vocales)
  let timer=null;

  const $=id=>document.getElementById(id);
  const esc=v=>String(v??"").replace(/[&<>'"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]));
  const isSignal=m=>m&&(m.verdict==="BUY"||m.verdict==="SELL");
  const ageMinutes=iso=>{const t=Date.parse(iso||"");return Number.isFinite(t)?Math.max(0,Math.round((Date.now()-t)/60000)):null;};
  const price=(v,d)=>{const n=Number(v);return Number.isFinite(n)&&n>0?n.toFixed(Number.isFinite(Number(d))?Number(d):3):"—";};
  const sideClass=s=>s==="BUY"?"buy":s==="SELL"?"sell":"wait";
  const sideWord=s=>s==="BUY"?"BUY":s==="SELL"?"SELL":"—";
  const ageText=m=>m===null?"—":m<1?"à l’instant":m<60?`il y a ${m} min`:`il y a ${Math.floor(m/60)} h ${String(m%60).padStart(2,"0")}`;

  async function load(){
    for(const url of [`${RAW}?t=${Date.now()}`,`${LOCAL}?t=${Date.now()}`]){
      try{
        const r=await fetch(url,{cache:"no-store"});
        if(!r.ok)continue;
        const j=await r.json();
        if(j&&Array.isArray(j.markets))return j;
      }catch(e){/* source suivante */}
    }
    return null;
  }

  function sparkline(closes,cls){
    const v=(closes||[]).map(Number).filter(Number.isFinite);
    if(v.length<2)return "";
    const w=140,h=34,min=Math.min(...v),max=Math.max(...v),span=max-min||1;
    const pts=v.map((p,i)=>`${(i/(v.length-1)*w).toFixed(1)},${(h-2-(p-min)/span*(h-4)).toFixed(1)}`).join(" ");
    return `<svg class="wt-spark ${cls}" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" aria-hidden="true"><polyline points="${pts}"/></svg>`;
  }

  function tfChip(label,side){
    return `<span class="wt-tf ${sideClass(side)}">${label} <b>${esc(sideWord(side))}</b></span>`;
  }

  function card(m){
    const sig=isSignal(m),cls=sig?sideClass(m.verdict):"wait";
    const since=sig&&m.since?ageMinutes(m.since):null;
    const levels=sig?`<div class="wt-levels">
        <div><small>Entrée</small><strong>${price(m.entry,m.digits)}</strong></div>
        <div class="danger"><small>SL</small><strong>${price(m.sl,m.digits)}</strong></div>
        <div><small>TP1</small><strong>${price(m.tp1,m.digits)}</strong></div>
        <div><small>TP2</small><strong>${price(m.tp2,m.digits)}</strong></div>
        <div><small>TP3</small><strong>${price(m.tp3,m.digits)}</strong></div>
      </div>`:"";
    const direction=sig?m.verdict:(m.bias&&m.bias!=="NEUTRE"?`Biais ${m.bias}`:"Neutre");
    const progress=Math.max(0,Math.min(100,Math.min(Number(m.score)/84*100,Number(m.conditions)/80*100)));
    return `<article class="wt-card ${cls}" data-wt-symbol="${esc(m.symbol)}">
      <div class="wt-top">
        <div><h3>${esc(m.symbol)}</h3><p>${esc(m.family||"SyntX")} · SWING H1/H4/D1</p></div>
        <span class="wt-signal ${cls}">${esc(sig?m.verdict:"ATTENDRE")}</span>
      </div>
      <div class="wt-row"><span>${esc(direction)}</span><b>${esc(m.state||"")}</b><strong>${Math.round(Number(m.confidence)||0)}%</strong></div>
      <div class="wt-tfs">${tfChip("H1",m.h1)}${tfChip("H4",m.h4)}${tfChip("D1",m.d1)}</div>
      ${sparkline(m.closes,cls)}
      ${levels}
      <div class="wt-meta"><span>Score ${Math.round(Number(m.score)||0)}/84</span><span>Conditions ${Math.round(Number(m.conditions)||0)}%</span><span>Consensus ${Math.round(Number(m.consensus)||0)}%</span>${since!==null?`<span>Signal ${esc(ageText(since))}</span>`:""}</div>
      <div class="wt-bar"><i style="width:${progress.toFixed(0)}%"></i></div>
      ${m.decision?`<p class="wt-decision">${esc(m.decision)}</p>`:""}
      <button class="wt-speak" type="button" data-wt-speak="${esc(m.symbol)}">🔊 Lire l’analyse</button>
    </article>`;
  }

  function speechFor(m){
    const v=window.SeraVoice;
    if(!v)return "";
    if(isSignal(m))return v.signalText({broker:"Weltrade",market:m.symbol,mode:"swing",verdict:m.verdict,confidence:m.confidence,entry:m.entry,sl:m.sl,tp1:m.tp1,tp2:m.tp2,tp3:m.tp3});
    return `Weltrade. ${m.symbol}. Pas de signal pour le moment. Score ${Math.round(Number(m.score)||0)} sur 84, conditions ${Math.round(Number(m.conditions)||0)} pour cent. ${m.decision||""}`;
  }

  function guide(){
    return `<details class="wt-guide"><summary>Comment remplir cet onglet</summary><ol>
      <li>Installer <b>Sera EA Swing Intelligent Weltrade v2.20</b> (ou plus récent) sur un graphique de votre compte Weltrade.</li>
      <li>Créer une clé GitHub <i>fine-grained</i> : accès au seul dépôt <code>serakatsuva/sera-indicator</code>, permission <b>Contents : Read and write</b>.</li>
      <li>Dans les paramètres de l’EA : <code>PublishToApp = true</code> et coller la clé dans <code>GitHubToken</code>.</li>
      <li>MT5 → Outils → Options → Expert Advisors → WebRequest : ajouter <code>https://api.github.com</code>.</li>
      <li>L’EA envoie ses analyses toutes les 5 minutes tant que MT5 est ouvert.</li>
    </ol></details>`;
  }

  function render(){
    const notice=$("wtNotice"),results=$("wtResults"),meta=$("wtMeta");
    if(!notice||!results)return;
    if(!data){
      notice.className="notice warning";
      notice.innerHTML=`Aucune analyse Weltrade reçue pour l’instant : l’EA Weltrade doit les envoyer depuis MT5.${guide()}`;
      results.innerHTML="";
      if(meta)meta.innerHTML="";
      return;
    }
    const age=ageMinutes(data.updated_at);
    const markets=[...data.markets].sort((a,b)=>(isSignal(b)-isSignal(a))||((Number(b.score)||0)-(Number(a.score)||0)));
    const signals=markets.filter(isSignal);
    const shown=filter==="signals"?signals:markets;
    if(meta)meta.innerHTML=`<span>Envoi EA <b>${esc(ageText(age))}</b></span><span>Indices <b>${markets.length}</b></span><span>Signaux <b>${signals.length}</b></span><span>Compte <b>${esc(data.account||"—")}</b></span><span><b>${esc(data.source||"Sera EA Weltrade")} ${esc(data.version||"")}</b></span>`;
    if(age!==null&&age>STALE_MINUTES){
      notice.className="notice warning";
      notice.innerHTML=`Dernières analyses reçues ${esc(ageText(age))} : MT5 ou l’EA Weltrade semble arrêté. Les données ci-dessous ne sont plus à jour.${guide()}`;
    }else{
      notice.className="notice success";
      notice.textContent=signals.length?`${signals.length} signal(s) Weltrade en cours · analyses MT5 envoyées ${ageText(age)}.`:`Aucun signal Weltrade en cours · ${markets.length} indices analysés ${ageText(age)}.`;
    }
    results.innerHTML=shown.length?shown.map(card).join(""):`<p class="wt-empty">Aucun signal BUY/SELL pour le moment.</p>`;
  }

  function announceNew(){
    if(!data)return;
    const now=new Set(data.markets.filter(isSignal).map(m=>`${m.symbol}|${m.verdict}`));
    if(knownSignals&&window.SeraVoice&&window.SeraVoice.isOn()){
      const fresh=data.markets.filter(m=>isSignal(m)&&!knownSignals.has(`${m.symbol}|${m.verdict}`));
      if(fresh.length)window.SeraVoice.announce(fresh.map(m=>({broker:"Weltrade",market:m.symbol,mode:"swing",verdict:m.verdict,confidence:m.confidence,entry:m.entry,sl:m.sl,tp1:m.tp1,tp2:m.tp2,tp3:m.tp3})));
    }
    knownSignals=now;
  }

  async function refresh(){
    const fresh=await load();
    if(fresh)data=fresh;
    render();
    announceNew();
  }

  function bind(){
    document.querySelectorAll("[data-wt-filter]").forEach(btn=>btn.addEventListener("click",()=>{
      filter=btn.dataset.wtFilter;
      document.querySelectorAll("[data-wt-filter]").forEach(b=>{const on=b===btn;b.classList.toggle("active",on);b.setAttribute("aria-selected",on?"true":"false");});
      render();
    }));
    $("wtResults")?.addEventListener("click",event=>{
      const btn=event.target.closest("[data-wt-speak]");
      if(!btn||!data)return;
      const m=data.markets.find(x=>x.symbol===btn.dataset.wtSpeak);
      if(m&&window.SeraVoice)window.SeraVoice.speak(speechFor(m),true);
    });
    $("wtRefresh")?.addEventListener("click",refresh);
  }

  window.SeraWeltrade={
    signals:()=>data?data.markets.filter(isSignal).map(m=>({broker:"Weltrade",market:m.symbol,mode:"swing",verdict:m.verdict,confidence:m.confidence,entry:m.entry,sl:m.sl,tp1:m.tp1,tp2:m.tp2,tp3:m.tp3})):[],
    refresh
  };

  function start(){
    if(!$("weltrade"))return;
    bind();
    refresh();
    timer=setInterval(refresh,60000);
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start);else start();
})();
