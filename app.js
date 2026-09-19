const derivMarkets=[
  "Boom 300 Index","Boom 500 Index","Boom 1000 Index",
  "Crash 300 Index","Crash 500 Index","Crash 1000 Index",
  "Volatility 10 Index","Volatility 25 Index","Volatility 50 Index",
  "Volatility 75 Index","Volatility 100 Index"
];
const symbols={
  "Boom 300 Index":"BOOM300N","Boom 500 Index":"BOOM500","Boom 1000 Index":"BOOM1000",
  "Crash 300 Index":"CRASH300N","Crash 500 Index":"CRASH500","Crash 1000 Index":"CRASH1000",
  "Volatility 10 Index":"R_10","Volatility 25 Index":"R_25","Volatility 50 Index":"R_50",
  "Volatility 75 Index":"R_75","Volatility 100 Index":"R_100"
};
const forexMarkets=["EUR/USD","GBP/USD","USD/JPY","USD/CHF","USD/CAD","AUD/USD","NZD/USD"];
const forexSymbols={"EUR/USD":"EURUSD","GBP/USD":"GBPUSD","USD/JPY":"USDJPY","USD/CHF":"USDCHF","USD/CAD":"USDCAD","AUD/USD":"AUDUSD","NZD/USD":"NZDUSD"};
const $=id=>document.getElementById(id);
let payload=null;
let selected=derivMarkets[0];
let liveSocket=null;
let liveQuote=null;
let marketFamily="synthetic";
let selectedIndexFamily=localStorage.getItem("seraIndexFamily")||"all";
let tradingMode="all";
let selectedMode="day";
let trendWatchEnabled=localStorage.getItem("seraTrendWatchEnabled")==="1";
let trendWatchScope=localStorage.getItem("seraTrendWatchScope")||"selected";
let trendWatchSound=localStorage.getItem("seraTrendWatchSound")!=="0";
let trendWatchSnapshots=loadTrendWatchSnapshots();
let trendWatchLastAlert=localStorage.getItem("seraTrendWatchLastAlert")||"";
let trendWatchBannerTimer=null;
const signalModal=$("signalModal");
const welcomePopup=$("welcomePopup");
const welcomeContinue=$("welcomeContinue");
if(localStorage.getItem("seraWelcomeSeen")!=="1") document.body.classList.add("popup-open"); else { welcomePopup.classList.add("closed"); welcomePopup.setAttribute("hidden",""); }
welcomeContinue.addEventListener("click",closeWelcomePopup);
welcomePopup.addEventListener("click",event=>{if(event.target===welcomePopup)closeWelcomePopup();});
document.addEventListener("keydown",event=>{if(event.key==="Escape"&&!welcomePopup.classList.contains("closed"))closeWelcomePopup();});
function closeWelcomePopup(){
  localStorage.setItem("seraWelcomeSeen","1");
  welcomePopup.classList.add("closed");
  document.body.classList.remove("popup-open");
  setTimeout(()=>welcomePopup.setAttribute("hidden",""),230);
}


const fmt=n=>Number.isFinite(Number(n))?Number(n).toLocaleString("en-US",{minimumFractionDigits:2,maximumFractionDigits:2}):"—";
const ageMinutes=iso=>iso?(Date.now()-Date.parse(iso))/60000:Infinity;
const ageLabel=iso=>{const minutes=Math.max(0,Math.floor(ageMinutes(iso)));if(!Number.isFinite(minutes))return "—";if(minutes<1)return "à l’instant";if(minutes<60)return `${minutes} min`;const hours=Math.floor(minutes/60);if(hours<24)return `${hours} h ${minutes%60} min`;return `${Math.floor(hours/24)} j ${hours%24} h`;};
const signalClass=value=>value==="BUY"?"buy":value==="SELL"?"sell":"wait";
const hoursLabel=value=>Number.isFinite(Number(value))?`≈ ${Math.round(Number(value))} h`:"—";
const durationLabel=timing=>timing?`${timing.duration_min_hours}–${timing.duration_max_hours} h`:"—";
const swingDurationLabel=timing=>timing?.swing_days_label||durationLabel(timing);
const swingBadgeText=row=>{
  if(row?.mode!=="swing")return"";
  const timing=row?.timing;
  const kind=timing?.swing_class||"COURT";
  const prefix=timing?.is_confirmed?"SWING":"PROJECTION SWING";
  return `${prefix} ${kind} · ${swingDurationLabel(timing)}`;
};
const hasDerivResults=()=>payload?.ok===true&&["ai_analyzed","smart_local","technical_only"].includes(payload?.status)&&payload?.source_broker==="Deriv"&&Array.isArray(payload?.markets);
const resultsAreFresh=()=>hasDerivResults()&&ageMinutes(payload.updated_at)<130;

$("refreshButton").addEventListener("click",()=>loadSignals(true));
$("marketSelect").addEventListener("change",event=>{
  selected=event.target.value;
  liveQuote=null;
  renderSelected();
  if(signalModal&&!signalModal.hidden)$("signalModalTitle").textContent=selected;
  renderTrendWatchUi();
  connectLivePrice();
});
$("copySignal").addEventListener("click",copySignal);
$("shareSignal").addEventListener("click",shareSignal);
$("showMt5Setup").addEventListener("click",()=>{
  const panel=$("mt5Setup"),willOpen=panel.hidden;
  panel.hidden=!willOpen;
  $("showMt5Setup").textContent=willOpen?"Masquer l’installation":"Voir l’installation";
});
$("syntheticFilter").addEventListener("click",()=>setMarketFamily("synthetic"));
$("forexFilter").addEventListener("click",()=>setMarketFamily("forex"));
$("indexFamilyFilter")?.addEventListener("click",event=>{
  const button=event.target.closest("[data-family]");
  if(button)setIndexFamily(button.dataset.family);
});
document.querySelectorAll(".mode-filter").forEach(button=>button.addEventListener("click",()=>setTradingMode(button.dataset.mode)));
$("openHelp")?.addEventListener("click",()=>{welcomePopup.removeAttribute("hidden");welcomePopup.classList.remove("closed");document.body.classList.add("popup-open");});
$("trendWatchToggle")?.addEventListener("change",event=>{
  trendWatchEnabled=Boolean(event.target.checked);
  localStorage.setItem("seraTrendWatchEnabled",trendWatchEnabled?"1":"0");
  renderTrendWatchUi();
  if(trendWatchEnabled)evaluateTrendWatch();
});
$("trendWatchScope")?.addEventListener("change",event=>{
  trendWatchScope=event.target.value==="all"?"all":"selected";
  localStorage.setItem("seraTrendWatchScope",trendWatchScope);
  renderTrendWatchUi();
});
$("trendWatchSound")?.addEventListener("change",event=>{
  trendWatchSound=Boolean(event.target.checked);
  localStorage.setItem("seraTrendWatchSound",trendWatchSound?"1":"0");
});
$("enableBrowserAlerts")?.addEventListener("click",requestBrowserAlerts);
$("closeSignalModal")?.addEventListener("click",closeSignalModal);
$("signalModalBackdrop")?.addEventListener("click",closeSignalModal);
document.addEventListener("keydown",event=>{
  if(event.key==="Escape"&&signalModal&&!signalModal.hidden)closeSignalModal();
});

function openSignalModal(marketName){
  if(!signalModal)return;
  $("signalModalTitle").textContent=marketName||selected||"Détail de l’indice";
  signalModal.hidden=false;
  signalModal.setAttribute("aria-hidden","false");
  document.body.classList.add("signal-modal-open");
  requestAnimationFrame(()=>signalModal.classList.add("open"));
}

function closeSignalModal(){
  if(!signalModal)return;
  signalModal.classList.remove("open");
  signalModal.setAttribute("aria-hidden","true");
  document.body.classList.remove("signal-modal-open");
  setTimeout(()=>{signalModal.hidden=true;},160);
}

function setTradingMode(mode){
  tradingMode=mode;
  if(mode!=="all")selectedMode=mode;
  document.querySelectorAll(".mode-filter").forEach(button=>{const active=button.dataset.mode===mode;button.classList.toggle("active",active);button.setAttribute("aria-selected",String(active));});
  $("updateFrequency").textContent=mode==="swing"?"chaque heure":"toutes les 15 minutes";
  render();
}

function marketFamilyKey(name,row=null){
  const family=String(row?.family||"").toLowerCase();
  if(family==="boom"||/^boom\b/i.test(name))return"boom";
  if(family==="crash"||/^crash\b/i.test(name))return"crash";
  if(family==="volatility"||/^volatility\b/i.test(name))return"volatility";
  if(family==="jump"||/^jump\b/i.test(name))return"jump";
  if(family==="step"||/^step\b/i.test(name))return"step";
  if(family==="range"||/range/i.test(name))return"range";
  return"other";
}

function familyLabel(key){
  return({all:"Tous les indices",boom:"Boom",crash:"Crash",volatility:"Volatility",jump:"Jump",step:"Step",range:"Range",other:"Autres"})[key]||key;
}

function availableSyntheticMarkets(){
  const fromPayload=hasDerivResults()
    ?[...new Set(payload.markets.map(row=>row.market).filter(Boolean))]
    :derivMarkets;
  return fromPayload.length?fromPayload:derivMarkets;
}

function marketsForIndexFamily(){
  const markets=availableSyntheticMarkets();
  if(selectedIndexFamily==="all")return markets;
  return markets.filter(name=>{
    const row=hasDerivResults()?payload.markets.find(item=>item.market===name):null;
    return marketFamilyKey(name,row)===selectedIndexFamily;
  });
}

function renderIndexFamilyFilter(){
  const host=$("indexFamilyFilter"),group=$("syntheticFamilyGroup");
  if(!host||!group)return;
  group.hidden=marketFamily!=="synthetic";
  if(marketFamily!=="synthetic")return;

  const markets=availableSyntheticMarkets();
  const keys=["boom","crash","volatility","jump","step","range","other"];
  const counts=Object.fromEntries(keys.map(key=>[key,markets.filter(name=>{
    const row=hasDerivResults()?payload.markets.find(item=>item.market===name):null;
    return marketFamilyKey(name,row)===key;
  }).length]));
  const visible=["all",...keys.filter(key=>counts[key]>0)];
  if(!visible.includes(selectedIndexFamily))selectedIndexFamily="all";

  host.innerHTML=visible.map(key=>{
    const active=key===selectedIndexFamily;
    const count=key==="all"?markets.length:counts[key];
    return `<button type="button" class="index-family-button${active?" active":""}" data-family="${key}" role="tab" aria-selected="${active}"><span>${familyLabel(key)}</span><small>${count}</small></button>`;
  }).join("");
}

function setIndexFamily(family){
  selectedIndexFamily=family||"all";
  localStorage.setItem("seraIndexFamily",selectedIndexFamily);
  const markets=marketsForIndexFamily();
  if(markets.length&&!markets.includes(selected)){
    selected=markets[0];
    liveQuote=null;
  }
  fillMarketSelect();
  render();
  if(marketFamily==="synthetic")connectLivePrice();
}

function setMarketFamily(family){
  marketFamily=family;
  $("syntheticFilter").classList.toggle("active",family==="synthetic");
  $("forexFilter").classList.toggle("active",family==="forex");
  $("syntheticFilter").setAttribute("aria-selected",String(family==="synthetic"));
  $("forexFilter").setAttribute("aria-selected",String(family==="forex"));
  if(family==="synthetic"){
    const markets=marketsForIndexFamily();
    selected=markets[0]||derivMarkets[0];
  }else selected=forexMarkets[0];
  liveQuote=null;
  renderIndexFamilyFilter();
  fillMarketSelect();
  if(family==="synthetic")connectLivePrice();else if(liveSocket){liveSocket.close();liveSocket=null;}
  render();
}

function fillMarketSelect(){
  const markets=marketFamily==="synthetic"?marketsForIndexFamily():forexMarkets;
  $("marketSelect").innerHTML=markets.map(name=>`<option value="${name}">${name}</option>`).join("");
  if(markets.length&&!markets.includes(selected))selected=markets[0];
  $("marketSelect").value=selected;
}

async function loadSignals(manual=false){
  const button=$("refreshButton");
  if(manual){button.disabled=true;button.innerHTML="<span>↻</span> Actualisation…";}
  try{
    const response=await fetch(`./data/signals.json?t=${Date.now()}`,{cache:"no-store"});
    if(!response.ok)throw new Error(`HTTP ${response.status}`);
    payload=await response.json();
  }catch{
    payload={ok:false,status:"load_error",source_broker:"Deriv",note:"Impossible de charger les résultats IA."};
  }finally{
    button.disabled=false;
    button.innerHTML="<span>↻</span> Actualiser les signaux";
    render();
    evaluateTrendWatch();
  }
}

function render(){
  const notice=$("notice"),results=$("results"),fresh=resultsAreFresh();
  results.innerHTML="";
  $("updatedAt").textContent=payload?.updated_at?new Date(payload.updated_at).toLocaleString("fr-FR",{dateStyle:"short",timeStyle:"short"}):"—";
  $("dataAge").textContent=ageLabel(payload?.updated_at);
  $("sourceName").textContent=payload?.source||"Deriv WebSocket";
  $("modelName").textContent=payload?.model||"Sera Smart Engine + Luna";
  renderIndexFamilyFilter();
  renderTrendWatchUi();

  if(marketFamily==="forex"){
    setMarketStatus("Forex MT5 : connexion requise","error"); setAiStatus("OpenAI Forex : en attente","error");
    $("sourceName").textContent="Deriv MT5"; notice.className="notice warning";
    notice.textContent="Les marchés Forex sont prêts. Connectez le flux Deriv MT5 pour activer les analyses IA sans utiliser de prix fictifs.";
    renderForexCards(results); renderSelected(); return;
  }

  if(!hasDerivResults()){
    setMarketStatus("Deriv : connexion en cours","error");
    setAiStatus("OpenAI : analyse en attente","error");
    notice.className="notice warning";
    notice.textContent=payload?.note||"ATTENDRE — la première analyse Deriv H1/H4 n’est pas encore disponible.";
    renderWaitingCards(results);
    renderSelected();
    return;
  }

  setMarketStatus(fresh?"Deriv : données multi-horizon":"Deriv : données anciennes",fresh?"live":"error");
  const aiActive=fresh&&payload.status==="ai_analyzed";
  const smartLocal=fresh&&payload.status==="smart_local";
  setAiStatus(aiActive?"Luna : audit récent":smartLocal?"Smart Engine : autonome":fresh?"Smart Engine : analyse locale":"Validation expirée",aiActive||smartLocal?"live":fresh?"":"error");
  notice.className=`notice ${aiActive||smartLocal?"success":"warning"}`;
  notice.textContent=aiActive
    ?`${payload.markets_count} analyses disponibles · ${payload.ai_calls??0} appel(s) Luna · ${payload.cached_ai_validations??0} validation(s) réutilisée(s). Les signaux finaux ont passé l’audit IA.`
    :smartLocal
      ?`${payload.markets_count} analyses Smart Engine actualisées. Luna est indisponible, mais ${payload.confirmed_signals??0} setup(s) exceptionnellement solide(s) ont dépassé les seuils autonomes renforcés.`
      :fresh
        ?`${payload.markets_count} analyses Smart Engine actualisées. ${payload.technical_candidates??0} candidat(s) existent, mais aucun ne dépasse encore les seuils nécessaires pour un signal final.`
        :`Validation expirée depuis ${ageLabel(payload.updated_at)}. Les anciens BUY/SELL sont neutralisés sur ATTENDRE jusqu’à une nouvelle analyse.`;
  const allowedMarkets=new Set(marketsForIndexFamily());
  const rows=payload.markets.filter(row=>allowedMarkets.has(row.market)&&(tradingMode==="all"||row.mode===tradingMode));
  rows.slice().sort(compareSignalPriority).forEach(row=>results.appendChild(resultCard(row,fresh)));
  $("visibleResultsCount")?.remove?.();
  renderSelected();
}

function signalPriority(row){
  if(row?.final_verdict==="BUY"||row?.final_verdict==="SELL")return 2;
  if(row?.technical_verdict==="BUY"||row?.technical_verdict==="SELL")return 1;
  return 0;
}

function compareSignalPriority(a,b){
  return signalPriority(b)-signalPriority(a)
    ||(Number(b.final_confidence)||0)-(Number(a.final_confidence)||0)
    ||String(a.market||"").localeCompare(String(b.market||""),"fr");
}

function renderForexCards(container){
  forexMarkets.forEach(name=>{
    const card=document.createElement("button");
    card.className=`result-card forex-pending${name===selected?" selected":""}`;
    card.innerHTML=`<div class="result-top"><div><h3>${name}</h3><p class="symbol">${forexSymbols[name]} · H1/H4</p></div><span class="signal wait">EN ATTENTE</span></div><div class="forex-lock">Connexion MT5 requise</div><div class="result-score"><strong>—</strong><small>Analyse IA non lancée</small></div><div class="result-bar"><i style="width:0%"></i></div>`;
    card.onclick=()=>{selected=name;$("marketSelect").value=name;renderSelected();highlightSelected();openSignalModal(name);};
    container.appendChild(card);
  });
}

function renderWaitingCards(container){
  marketsForIndexFamily().forEach(name=>{
    const card=document.createElement("button");
    card.className=`result-card${name===selected?" selected":""}`;
    card.innerHTML=`<div class="result-top"><div><h3>${name}</h3><p class="symbol">${symbols[name]} · H1/H4</p></div><span class="signal wait">ATTENDRE</span></div><div class="result-timing"><span>Biais en analyse</span><b>Horizon —</b></div><div class="result-score"><strong>—</strong><small>Préparation du setup</small></div><div class="result-bar"><i style="width:0%"></i></div>`;
    card.onclick=()=>{selected=name;liveQuote=null;$("marketSelect").value=name;renderSelected();highlightSelected();connectLivePrice();openSignalModal(name);};
    container.appendChild(card);
  });
}

function resultCard(row,fresh){
  const verdict=fresh?row.final_verdict:"ATTENDRE",confidence=fresh?Number(row.final_confidence)||0:0;
  const card=document.createElement("button");
  card.className=`result-card${row.market===selected&&row.mode===selectedMode?" selected":""}`;
  const status=verdict!=="ATTENDRE"?"Confirmé":row.technical_verdict!=="ATTENDRE"?"Détecté · validation IA":"En attente";
  const timing=row.timing,bias=timing?.bias||"NEUTRE",direction=verdict!=="ATTENDRE"?verdict:`Biais ${bias}`;
  const swingBadge=row.mode==="swing"?`<div class="swing-duration-badge ${String(row.timing?.swing_class||"court").toLowerCase()}">${escapeHtml(swingBadgeText(row))}</div>`:"";
  card.innerHTML=`<div class="result-top"><div><h3>${escapeHtml(row.market)}</h3><p class="symbol">${escapeHtml(row.symbol||row.market)}</p></div><span class="signal ${signalClass(verdict)}">${verdict}</span></div>${swingBadge}<div class="compact-signal-row"><span>${row.mode==="day"?"DAY · M15/H1":"SWING · H1/H4"}</span><b>${direction}</b><strong>${confidence}%</strong></div><div class="result-timing ${signalClass(verdict)}"><span>${status}</span><b>${escapeHtml(row.intelligence?.regime||"Analyse")}</b></div><div class="result-bar"><i style="width:${confidence}%"></i></div>`;
  card.onclick=()=>{selected=row.market;selectedMode=row.mode||"swing";liveQuote=null;ensureMarketOption(row.market);$("marketSelect").value=selected;renderSelected();connectLivePrice();openSignalModal(row.market);};
  return card;
}

function renderSelected(){
  $("selectedMarket").textContent=selected;
  if(marketFamily==="forex"){
    $("verdictBadge").className="verdict-badge wait";$("verdictBadge").textContent="EN ATTENTE";
    $("decisionOrb").className="decision-orb wait";$("decisionOrb").querySelector("strong").textContent="ATTENDRE";
    $("decisionConfidence").textContent="Connexion MT5 requise";
    $("decisionSummary").textContent=`${selected} est ajouté au scanner. Son analyse H1/H4 par Sera Smart Engine + Luna démarrera uniquement après connexion des vraies bougies Deriv MT5.`;
    $("livePrice").textContent="—";$("liveChange").textContent="Deriv MT5 · attente";
    $("levels").querySelectorAll("strong").forEach(element=>element.textContent="—");
    $("timingPanel").querySelectorAll("strong").forEach(element=>element.textContent="—");
    $("timingNote").textContent="Durée, expiration et objectifs seront calculés après réception des vraies bougies MT5.";
    $("technicalGrid").innerHTML=[["Sessions","Londres / New York"],["Tendance","H1 + H4"],["Volatilité","ATR Forex"],["Actualités","Contrôle requis"]].map(([label,value])=>`<div class="metric"><small>${label}</small><strong class="no">${value}</strong></div>`).join("");
    $("checks").innerHTML='<div class="check no"><i></i><span>Flux de bougies Deriv MT5 non connecté</span></div><div class="check no"><i></i><span>Aucun signal ni pourcentage ne sera fabriqué</span></div>';
    $("signalActions").hidden=true;drawChart("wait");highlightSelected();return;
  }
  const candidates=hasDerivResults()?payload.markets.filter(item=>item.market===selected):[];
  const row=candidates.find(item=>item.mode===selectedMode)||candidates[0]||null;
  if(row?.mode)selectedMode=row.mode;
  const fresh=Boolean(row)&&resultsAreFresh();
  const verdict=fresh?row.final_verdict:"ATTENDRE",cls=signalClass(verdict);
  $("verdictBadge").className=`verdict-badge ${cls}`;
  $("verdictBadge").textContent=verdict;
  $("decisionOrb").className=`decision-orb ${cls}`;
  $("decisionOrb").querySelector("strong").textContent=verdict;
  $("decisionConfidence").textContent=fresh?(row.score_type==="setup_readiness"?`${row.final_confidence}% de préparation`:`${row.final_confidence}% de confiance`):"Validation requise";
  $("decisionSummary").textContent=fresh&&row?.ai_summary?row.ai_summary:`Sera attend une analyse Deriv multi-horizon et une validation OpenAI récente pour ${selected}.`;
  $("selectedTimeframe").textContent=row?.timeframes?.join(" + ")||"H1 + H4";
  const swingBadge=$("swingDurationBadge");
  if(swingBadge){
    if(row?.mode==="swing"&&row?.timing){
      swingBadge.hidden=false;
      swingBadge.className=`swing-detail-badge ${String(row.timing.swing_class||"court").toLowerCase()}`;
      swingBadge.textContent=swingBadgeText(row);
    }else{
      swingBadge.hidden=true;
      swingBadge.textContent="";
    }
  }
  const currentPrice=liveQuote?.symbol===symbols[selected]?liveQuote.price:row?.price;
  $("livePrice").textContent=fmt(currentPrice);
  $("liveChange").textContent=liveQuote?.symbol===symbols[selected]?"Prix Deriv live":row?`${row.technical_verdict} technique`:"Deriv · attente";
  const levelValues=verdict!=="ATTENDRE"&&row?.levels?[row.levels.entry,row.levels.sl,row.levels.tp1,row.levels.tp2,row.levels.tp3]:[null,null,null,null,null];
  $("levels").querySelectorAll("strong").forEach((element,index)=>element.textContent=fmt(levelValues[index]));
  const technical=row?.entry_tf||row?.h1;
  const confirmation=row?.confirmation_tf||row?.h4;
  const metrics=[[`Tendance ${row?.timeframes?.[1]||"H4"}`,confirmation?.trendStrong],["Alignement TF",technical?.side&&technical?.side===confirmation?.side],["Régime directionnel",row?.intelligence?.regime==="TRENDING"],["Mémoire tendance",row?.trend_memory?.persistence&&!row?.trend_memory?.flip],["BOS / CHoCH",technical&&(technical.bos||technical.choch)],["Liquidité",technical?.sweep],["Break & Retest",technical?.retest],["Momentum RSI",technical?.momentum]];
  $("technicalGrid").innerHTML=metrics.map(([label,ok])=>`<div class="metric"><small>${label}</small><strong class="${ok?"ok":"no"}">${ok?"Confirmé":"Non confirmé"}</strong></div>`).join("");
  const profile=[row?.mode==="day"?"Day trading":"Swing",row?.duration?.range||"—",row?.duration?.validity||"—",row?.duration?.reanalysis||"—"];
  $("positionProfile").querySelectorAll("strong").forEach((element,index)=>element.textContent=profile[index]);
  const confirmations=fresh?(row?.ai_confirmations||[]):[],contradictions=fresh?(row?.ai_contradictions||[]):[];
  $("checks").innerHTML=[...confirmations.map(text=>`<div class="check"><i></i><span>${escapeHtml(text)}</span></div>`),...contradictions.map(text=>`<div class="check no"><i></i><span>${escapeHtml(text)}</span></div>`)].join("")||'<div class="check no"><i></i><span>Données Deriv et analyse OpenAI récente requises</span></div>';
  const timing=row?.timing;
  const timingValues=timing?[
    timing.is_confirmed?timing.side:`Biais ${timing.bias}`,
    row?.mode==="swing"?`SWING ${timing.swing_class||timing.position_style}`:timing.position_style,
    row?.mode==="swing"?swingDurationLabel(timing):durationLabel(timing),
    hoursLabel(timing.tp1_hours),
    hoursLabel(timing.tp2_hours),
    hoursLabel(timing.tp3_hours),
    `${timing.expires_in_hours} h`,
    `toutes les ${timing.recheck_hours} h`
  ]:["—","—","—","—","—","—","—","—"];
  $("timingPanel").querySelectorAll("strong").forEach((element,index)=>element.textContent=timingValues[index]);
  $("timingPanel").className=`timing-panel ${cls}`;
  $("timingNote").textContent=timing?.is_confirmed
    ?row?.mode==="swing"
      ?`${swingBadgeText(row)}. Estimation basée sur l’ATR, la persistance de tendance H1/H4 et la distance vers les objectifs; ce n’est pas une durée garantie.`
      :`Estimation basée sur l’ATR H1, la distance vers les TP et la force H1/H4. Le signal expire après ${timing.expires_in_hours} h sans déclenchement.`
    :row?.mode==="swing"
      ?`${swingBadgeText(row)} selon le biais ${timing?.bias||"actuel"}. Projection réévaluée chaque heure tant que le signal n’est pas confirmé.`
      :`Aucun trade confirmé. Horizon projeté si le biais ${timing?.bias||"actuel"} est validé; réévaluation automatique à la prochaine analyse.`;
  $("signalActions").hidden=!(fresh&&verdict!=="ATTENDRE");
  drawChart(cls);
  highlightSelected();
}

function loadTrendWatchSnapshots(){
  try{
    const parsed=JSON.parse(localStorage.getItem("seraTrendWatchSnapshots")||"{}");
    return parsed&&typeof parsed==="object"?parsed:{};
  }catch{return {};}
}

function saveTrendWatchSnapshots(){
  localStorage.setItem("seraTrendWatchSnapshots",JSON.stringify(trendWatchSnapshots));
}

function trendWatchRows(){
  if(!hasDerivResults()||!resultsAreFresh())return[];
  const swings=payload.markets.filter(row=>row.mode==="swing");
  if(trendWatchScope==="all")return swings;
  if(marketFamily!=="synthetic")return[];
  return swings.filter(row=>row.market===selected);
}

function trendLabel(tf){
  if(!tf?.side)return"—";
  const strong=tf.trendStrong?" forte":"";
  return `${tf.side}${strong}`;
}

function renderTrendWatchUi(){
  const toggle=$("trendWatchToggle"),scope=$("trendWatchScope"),sound=$("trendWatchSound");
  if(!toggle||!scope||!sound)return;
  toggle.checked=trendWatchEnabled;
  scope.value=trendWatchScope;
  sound.checked=trendWatchSound;
  const state=$("trendWatchState"),status=$("trendWatchStatus");
  state.className=`trend-watch-state ${trendWatchEnabled?"on":"off"}`;
  status.textContent=trendWatchEnabled?"ACTIVE":"DÉSACTIVÉE";

  const row=hasDerivResults()?payload.markets.find(item=>item.market===selected&&item.mode==="swing"):null;
  $("watchTrendH1").textContent=trendLabel(row?.entry_tf);
  $("watchTrendH4").textContent=trendLabel(row?.confirmation_tf);
  const aligned=Boolean(row?.entry_tf?.side&&row?.entry_tf?.side===row?.confirmation_tf?.side);
  $("watchSetupState").textContent=row?.final_verdict&&row.final_verdict!=="ATTENDRE"
    ?`${row.final_verdict} confirmé · ${row.final_confidence}%`
    :aligned?`Biais ${row.entry_tf.side} · validation en attente`:"H1/H4 non alignés";
  $("watchLastAlert").textContent=trendWatchLastAlert||"Aucune";

  const notificationButton=$("enableBrowserAlerts");
  if(notificationButton){
    if(!("Notification" in window)){notificationButton.disabled=true;notificationButton.textContent="Notifications indisponibles";}
    else if(Notification.permission==="granted"){notificationButton.disabled=true;notificationButton.textContent="Notifications activées";}
    else if(Notification.permission==="denied"){notificationButton.disabled=true;notificationButton.textContent="Notifications bloquées";}
    else{notificationButton.disabled=false;notificationButton.textContent="Notifications navigateur";}
  }
}

async function requestBrowserAlerts(){
  if(!("Notification" in window))return;
  try{await Notification.requestPermission();}catch{}
  renderTrendWatchUi();
}

function signalSnapshot(row){
  return{
    updated_at:payload?.updated_at||"",
    verdict:row?.final_verdict||"ATTENDRE",
    confidence:Number(row?.final_confidence)||0,
    h1:row?.entry_tf?.side||"NEUTRE",
    h4:row?.confirmation_tf?.side||"NEUTRE"
  };
}

function evaluateTrendWatch(){
  if(!hasDerivResults())return;
  const allSwings=payload.markets.filter(row=>row.mode==="swing");
  const watchedIds=new Set(trendWatchRows().map(row=>row.id));
  for(const row of allSwings){
    const id=row.id||`${row.symbol}:swing`,current=signalSnapshot(row),previous=trendWatchSnapshots[id]||null;
    const watched=trendWatchEnabled&&watchedIds.has(row.id);
    const isSignal=current.verdict==="BUY"||current.verdict==="SELL";
    if(watched&&isSignal&&previous&&previous.verdict!==current.verdict){
      notifyTrendSignal(row,previous.verdict);
    }
    trendWatchSnapshots[id]=current;
  }
  saveTrendWatchSnapshots();
  renderTrendWatchUi();
}

function notifyTrendSignal(row,previousVerdict){
  const text=`${row.market}: ${row.final_verdict} Swing H1/H4 confirmé à ${row.final_confidence}% (avant: ${previousVerdict||"ATTENDRE"}).`;
  const now=new Date().toLocaleString("fr-FR",{dateStyle:"short",timeStyle:"short"});
  trendWatchLastAlert=`${now} · ${row.market} ${row.final_verdict}`;
  localStorage.setItem("seraTrendWatchLastAlert",trendWatchLastAlert);
  const banner=$("trendWatchAlert");
  if(banner){
    banner.hidden=false;
    banner.className=`trend-watch-alert ${signalClass(row.final_verdict)}`;
    banner.textContent=`ALERTE POSITION · ${text}`;
    clearTimeout(trendWatchBannerTimer);
    trendWatchBannerTimer=setTimeout(()=>{banner.hidden=true;},30000);
  }
  if(trendWatchSound)playTrendAlertSound(row.final_verdict);
  if("Notification" in window&&Notification.permission==="granted"){
    try{new Notification(`Sera Trend Watch · ${row.final_verdict}`,{body:text,tag:`sera-${row.id}`,renotify:true});}catch{}
  }
}

function playTrendAlertSound(verdict){
  try{
    const AudioCtx=window.AudioContext||window.webkitAudioContext;
    if(!AudioCtx)return;
    const ctx=new AudioCtx(),osc=ctx.createOscillator(),gain=ctx.createGain();
    osc.type="sine";osc.frequency.value=verdict==="BUY"?880:620;
    gain.gain.setValueAtTime(.0001,ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(.12,ctx.currentTime+.02);
    gain.gain.exponentialRampToValueAtTime(.0001,ctx.currentTime+.32);
    osc.connect(gain);gain.connect(ctx.destination);osc.start();osc.stop(ctx.currentTime+.34);
    osc.addEventListener("ended",()=>ctx.close());
  }catch{}
}

function connectLivePrice(){
  if(liveSocket){liveSocket.close();liveSocket=null;}
  if(marketFamily!=="synthetic")return;
  const symbol=symbols[selected];
  if(!symbol)return;
  try{
    const socket=new WebSocket("wss://api.derivws.com/trading/v1/options/ws/public");
    liveSocket=socket;
    socket.addEventListener("open",()=>socket.send(JSON.stringify({ticks:symbol,subscribe:1,req_id:900})));
    socket.addEventListener("message",event=>{
      const message=JSON.parse(event.data);
      if(message.error){setMarketStatus("Deriv : flux interrompu","error");return;}
      if(message.tick?.quote){liveQuote={symbol,price:Number(message.tick.quote)};if(symbol===symbols[selected]){$("livePrice").textContent=fmt(liveQuote.price);$("liveChange").textContent="Prix Deriv live";setMarketStatus("Deriv : Live","live");}}
    });
    socket.addEventListener("error",()=>setMarketStatus("Deriv : flux indisponible","error"));
  }catch{setMarketStatus("Deriv : flux indisponible","error");}
}

function ensureMarketOption(name){
  if([...$("marketSelect").options].some(option=>option.value===name))return;
  const option=document.createElement("option");option.value=name;option.textContent=name;$("marketSelect").appendChild(option);
}
function highlightSelected(){document.querySelectorAll(".result-card").forEach(card=>card.classList.toggle("selected",card.querySelector("h3")?.textContent===selected));}
function drawChart(cls){
  const paths={buy:"M0 190 C80 176 120 194 190 148 S330 175 420 102 S560 132 650 72 S790 95 900 34",sell:"M0 40 C90 33 118 76 200 61 S332 118 425 102 S565 178 650 146 S790 213 900 202",wait:"M0 132 C110 118 180 145 270 126 S450 142 540 122 S720 139 900 124"};
  const path=paths[cls]||paths.wait,line=$("chartLine"),fill=$("chartFillPath");
  line.setAttribute("d",path);fill.setAttribute("d",`${path} L900 250 L0 250 Z`);line.setAttribute("stroke",cls==="sell"?"#ff6b84":cls==="buy"?"#38e8bb":"#ffd166");
}
function setMarketStatus(text,state){$("marketStatus").textContent="";$("marketStatus").append(document.createElement("i"),document.createTextNode(text));$("marketStatus").className=`status-pill ${state}`;}
function setAiStatus(text,state){$("aiStatus").textContent="";$("aiStatus").append(document.createElement("i"),document.createTextNode(text));$("aiStatus").className=`status-pill ${state}`;}
function currentSignalText(){
  const row=hasDerivResults()?payload.markets.find(item=>item.market===selected&&item.mode===selectedMode):null;
  if(!row||!resultsAreFresh()||row.final_verdict==="ATTENDRE")return"";
  return ["SERA INDICATOR — SIGNAL DERIV CONFIRMÉ",`Indice : ${row.market}`,`Signal : ${row.final_verdict}`,`Confiance : ${row.final_confidence}%`,`Entrée : ${fmt(row.levels?.entry)}`,`Stop Loss : ${fmt(row.levels?.sl)}`,`TP1 : ${fmt(row.levels?.tp1)}`,`TP2 : ${fmt(row.levels?.tp2)}`,`TP3 : ${fmt(row.levels?.tp3)}`,`Analyse : ${new Date(payload.updated_at).toLocaleString("fr-FR")}`,`Modèle : ${row.ai_tier}`,"","Signal d’aide à la décision — l’EA Sera v1.20 peut exécuter automatiquement sur le compte MT5 réel connecté. Aucun gain garanti.",location.href].join("\n");
}
async function copySignal(){const text=currentSignalText();if(!text)return;await navigator.clipboard.writeText(text);$("copySignal").textContent="Copié ✓";setTimeout(()=>$("copySignal").textContent="Copier le signal",1500);}
async function shareSignal(){const text=currentSignalText();if(!text)return;if(navigator.share)await navigator.share({title:"Signal Deriv — Sera Indicator",text,url:location.href});else await navigator.clipboard.writeText(text);}
function escapeHtml(value){return String(value).replace(/[&<>'"]/g,char=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[char]));}

renderIndexFamilyFilter();
fillMarketSelect();
renderTrendWatchUi();
loadSignals();
connectLivePrice();
setInterval(()=>loadSignals(false),60000);
