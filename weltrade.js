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
  let family="all";
  // Familles d'indices Weltrade (SyntX) reconnues par l'EA ; les noms exacts viennent du compte MT5.
  const FAMILIES=[["GAINX","GainX"],["PAINX","PainX"],["FXVOL","FX Vol"],["SFXVOL","SFX Vol"],["FLIPX","FlipX"],["SWITCHX","SwitchX"],
                  ["BREAKX","BreakX"],["TRENDX","TrendX"],["PLUSX","PlusX"],["FIBOX","FiboX"],["QUADX","QuadX"]];
  // Les 41 indices du compte Weltrade (liste des symboles MT5 du propriétaire).
  const CATALOG=["FX Vol 20","FX Vol 40","FX Vol 60","FX Vol 80","FX Vol 99","SFX Vol 20","SFX Vol 40","SFX Vol 60","SFX Vol 80","SFX Vol 99",
    "GainX 400","GainX 600","GainX 800","GainX 999","GainX 1200","MAX GainX 1000","MAX GainX 2000",
    "PainX 400","PainX 600","PainX 800","PainX 999","PainX 1200","MAX PainX 1000","MAX PainX 2000",
    "FlipX 1","FlipX 2","FlipX 3","FlipX 4","FlipX 5","SwitchX 600","SwitchX 1200","SwitchX 1800",
    "BreakX 600","BreakX 1200","BreakX 1800","TrendX 600","TrendX 1200","TrendX 1800","PlusX 1","FiboX","QuadX"];
  // Meme regle que SyntXFamily() dans l'EA.
  function familyOf(name){
    const s=String(name||"").toUpperCase().replace(/[ _]/g,"");
    for(const k of ["SFXVOL","FXVOL","PAINX","GAINX","FLIPX","SWITCHX","BREAKX","TRENDX","PLUSX","FIBOX","QUADX"])if(s.includes(k))return k;
    return "";
  }
  const norm=n=>String(n||"").toUpperCase().replace(/[ _]/g,"");
  const familyLabel=k=>(FAMILIES.find(f=>f[0]===k)||[k,k||"SyntX"])[1];

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
        <div><h3>${esc(m.symbol)}</h3><p>${esc(familyLabel(m.family))} · SWING H1/H4/D1</p></div>
        <span class="wt-signal ${cls}">${esc(sig?m.verdict:"ATTENDRE")}</span>
      </div>
      <div class="wt-row"><span>${esc(direction)}</span><b>${esc(m.state||"")}</b><strong>${Math.round(Number(m.confidence)||0)}%</strong></div>
      <div class="wt-tfs">${tfChip("H1",m.h1)}${tfChip("H4",m.h4)}${tfChip("D1",m.d1)}</div>
      ${sparkline(m.closes,cls)}
      ${levels}
      <div class="wt-meta"><span>Score ${Math.round(Number(m.score)||0)}/84</span><span>Conditions ${Math.round(Number(m.conditions)||0)}%</span><span>Consensus ${Math.round(Number(m.consensus)||0)}%</span>${since!==null?`<span>Signal ${esc(ageText(since))}</span>`:""}${m.traded===false?`<span title="Famille non tradée par l’EA (réglages Trade…)">Analyse seule</span>`:""}</div>
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
      <li>Installer <b>Sera EA Swing Intelligent Weltrade v2.40</b> (ou plus récent) sur un graphique de votre compte Weltrade.</li>
      <li>Créer une clé GitHub <i>fine-grained</i> : accès au seul dépôt <code>serakatsuva/sera-indicator</code>, permission <b>Contents : Read and write</b>.</li>
      <li>Dans les paramètres de l’EA : <code>PublishToApp = true</code> et coller la clé dans <code>GitHubToken</code>.</li>
      <li>MT5 → Outils → Options → Expert Advisors → WebRequest : ajouter <code>https://api.github.com</code>.</li>
      <li>L’EA envoie ses analyses toutes les 5 minutes tant que MT5 est ouvert.</li>
    </ol></details>`;
  }

  function waitingCard(m){
    return `<article class="wt-card wt-waiting" data-wt-symbol="${esc(m.symbol)}">
      <div class="wt-top"><div><h3>${esc(m.symbol)}</h3><p>${esc(familyLabel(m.family))} · SWING H1/H4/D1</p></div><span class="wt-signal wait">EN ATTENTE</span></div>
      <p class="wt-decision">En attente de l’analyse de l’EA Weltrade (MT5).</p>
    </article>`;
  }

  // Indices analyses par l'EA + indices du compte pas encore recus (cartes "en attente").
  function allMarkets(){
    const got=data?data.markets.map(m=>({...m,family:m.family||familyOf(m.symbol)})):[];
    const seen=new Set(got.map(m=>norm(m.symbol)));
    const waiting=CATALOG.filter(n=>!seen.has(norm(n))).map(n=>({symbol:n,family:familyOf(n),waiting:true}));
    return got.concat(waiting);
  }

  function renderFamilies(markets){
    const host=$("wtFamilies");
    if(!host)return;
    const counts={};
    markets.forEach(m=>{counts[m.family]=(counts[m.family]||0)+1;});
    const keys=markets.length?FAMILIES.map(f=>f[0]).filter(k=>counts[k]).concat(Object.keys(counts).filter(k=>!FAMILIES.some(f=>f[0]===k))):FAMILIES.map(f=>f[0]);
    if(family!=="all"&&!keys.includes(family))family="all";
    const btn=(k,label,n)=>`<button type="button" class="index-family-button${family===k?" active":""}" data-wt-family-filter="${esc(k)}" role="tab" aria-selected="${family===k}"><span>${esc(label)}</span>${n===null?"":`<small>${n}</small>`}</button>`;
    host.innerHTML=btn("all","Toutes",markets.length?markets.length:null)+keys.map(k=>btn(k,familyLabel(k),markets.length?counts[k]:null)).join("");
  }

  function render(){
    const notice=$("wtNotice"),results=$("wtResults"),meta=$("wtMeta");
    if(!notice||!results)return;
    if(!data){
      notice.className="notice warning";
      notice.innerHTML=`Aucune analyse Weltrade reçue pour l’instant : l’EA Weltrade doit les envoyer depuis MT5.${guide()}`;
      const list=allMarkets();
      renderFamilies(list);
      results.innerHTML=list.filter(m=>family==="all"||m.family===family).map(waitingCard).join("");
      if(meta)meta.innerHTML="";
      return;
    }
    const age=ageMinutes(data.updated_at);
    const all=allMarkets().sort((a,b)=>(!!a.waiting-!!b.waiting)||(isSignal(b)-isSignal(a))||((Number(b.score)||0)-(Number(a.score)||0)));
    const markets=all.filter(m=>!m.waiting);
    const signals=markets.filter(isSignal);
    renderFamilies(all);
    const inFamily=all.filter(m=>family==="all"||m.family===family);
    const shown=filter==="signals"?inFamily.filter(isSignal):inFamily;
    if(meta)meta.innerHTML=`<span>Envoi EA <b>${esc(ageText(age))}</b></span><span>Indices <b>${markets.length}/${all.length}</b></span><span>Signaux <b>${signals.length}</b></span><span>Compte <b>${esc(data.account||"—")}</b></span><span><b>${esc(data.source||"Sera EA Weltrade")} ${esc(data.version||"")}</b></span>`;
    if(age!==null&&age>STALE_MINUTES){
      notice.className="notice warning";
      notice.innerHTML=`Dernières analyses reçues ${esc(ageText(age))} : MT5 ou l’EA Weltrade semble arrêté. Les données ci-dessous ne sont plus à jour.${guide()}`;
    }else{
      notice.className="notice success";
      notice.textContent=signals.length?`${signals.length} signal(s) Weltrade en cours · analyses MT5 envoyées ${ageText(age)}.`:`Aucun signal Weltrade en cours · ${markets.length} indices analysés ${ageText(age)}.`;
    }
    results.innerHTML=shown.length?shown.map(m=>m.waiting?waitingCard(m):card(m)).join(""):`<p class="wt-empty">Aucun signal BUY/SELL pour le moment.</p>`;
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
    $("wtFamilies")?.addEventListener("click",event=>{
      const b=event.target.closest("[data-wt-family-filter]");
      if(!b)return;
      family=b.dataset.wtFamilyFilter;
      render();
    });
    // Onglet "Weltrade · SyntX" dans le choix du marché (à côté de Synthétiques et Forex).
    $("weltradeFilter")?.addEventListener("click",()=>setMode(true,true));
    ["syntheticFilter","forexFilter"].forEach(id=>$(id)?.addEventListener("click",()=>setMode(false,false)));
    document.querySelectorAll('a[href="#weltrade"]').forEach(a=>a.addEventListener("click",event=>{event.preventDefault();setMode(true,true);}));
  }

  let savedTitle=null,savedActive=[];
  function setMode(on,scroll){
    const body=document.body,btn=$("weltradeFilter"),title=document.querySelector("#scanner .scanner-heading h2");
    if(on===body.classList.contains("wt-mode")){ if(on&&scroll)$("scanner")?.scrollIntoView({behavior:"smooth",block:"start"}); return; }
    body.classList.toggle("wt-mode",on);
    btn?.classList.toggle("active",on);
    btn?.setAttribute("aria-selected",on?"true":"false");
    const others=["syntheticFilter","forexFilter"].map($).filter(Boolean);
    if(on){
      savedActive=others.filter(b=>b.classList.contains("active"));
      others.forEach(b=>{b.classList.remove("active");b.setAttribute("aria-selected","false");});
      if(title){savedTitle=title.textContent;title.textContent="Signaux Weltrade (SyntX)";}
      if(scroll)$("scanner")?.scrollIntoView({behavior:"smooth",block:"start"});
      try{history.replaceState(null,"","#weltrade");}catch(e){/* ignore */}
      refresh();
    }else{
      if(title&&savedTitle!==null)title.textContent=savedTitle;
      if(!others.some(b=>b.classList.contains("active")))savedActive.forEach(b=>{b.classList.add("active");b.setAttribute("aria-selected","true");});
      if(location.hash==="#weltrade"){try{history.replaceState(null,"",location.pathname+location.search);}catch(e){/* ignore */}}
    }
  }

  window.SeraWeltrade={
    open:()=>setMode(true,true),
    signals:()=>data?data.markets.filter(isSignal).map(m=>({broker:"Weltrade",market:m.symbol,mode:"swing",verdict:m.verdict,confidence:m.confidence,entry:m.entry,sl:m.sl,tp1:m.tp1,tp2:m.tp2,tp3:m.tp3})):[],
    refresh
  };

  function start(){
    if(!$("weltrade"))return;
    bind();
    refresh();
    if(location.hash==="#weltrade")setMode(true,true);
    timer=setInterval(refresh,60000);
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start);else start();
})();
