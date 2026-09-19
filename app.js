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
let qwenEngine=null;
let qwenLoading=false;
let qwenLoadedModel="";
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
const executionLabel=row=>{
  const state=row?.execution_state||row?.execution?.state||"WAIT_CONFIRMATION";
  return ({EXECUTE_NOW:"EXÉCUTER MAINTENANT",WAIT_RETRACE:"ATTENDRE RETRACEMENT",WAIT_CONFIRMATION:"ATTENDRE CONFIRMATION",BLOCKED_RISK:"BLOQUÉ RISQUE"})[state]||state;
};
const simpleActionState=row=>{
  if(!row)return{code:"WAIT",label:"WAIT",detail:"Aucun setup exploitable",side:"wait",blink:false};
  const side=setupSide(row);
  const proposal=liveEntryProposal(row);
  const execution=row?.execution_state||row?.execution?.state||"WAIT_CONFIRMATION";
  const finalSide=row?.final_verdict==="BUY"||row?.final_verdict==="SELL"?row.final_verdict:null;

  // A flashing BUY/SELL now has one meaning only: the final engine authorizes execution now.
  if(finalSide&&execution==="EXECUTE_NOW"){
    return{code:finalSide,label:finalSide,detail:"ENTRER MAINTENANT",side:finalSide.toLowerCase(),blink:true};
  }
  if(proposal?.live_state==="IN_ENTRY_ZONE"&&hasDetectedSetup(row)){
    return{code:"WAIT",label:"WAIT",detail:`PRIX DANS LA ZONE · VALIDATION ${side} EN COURS`,side:"wait",blink:false};
  }
  if(hasDetectedSetup(row)){
    return{code:"WAIT",label:"WAIT",detail:`SETUP ${side} · ATTENDRE LE SIGNAL FINAL`,side:"wait",blink:false};
  }
  return{code:"WAIT",label:"WAIT",detail:"ATTENDRE",side:"wait",blink:false};
};
const setupSide=row=>{
  const explicit=row?.setup_direction||row?.decision_engine?.detected_side;
  if(explicit==="BUY"||explicit==="SELL")return explicit;
  const e=row?.entry_tf?.side,c=row?.confirmation_tf?.side;
  return e&&e===c&&(e==="BUY"||e==="SELL")?e:"NEUTRE";
};
const hasDetectedSetup=row=>Boolean(row?.setup_detected||row?.decision_engine?.setup_detected)&&setupSide(row)!=="NEUTRE";
const modelDirectionLabel=value=>value==="BUY"?"BUY":value==="SELL"?"SELL":"NEUTRE";
const fmtEntry=n=>Number.isFinite(Number(n))?Number(n).toLocaleString("en-US",{minimumFractionDigits:3,maximumFractionDigits:3}):"—";
const signedDistance=(value,side)=>{
  const n=Number(value);
  if(!Number.isFinite(n))return"—";
  const sign=side==="SELL"?"−":"+";
  return `${sign}${Math.abs(n).toLocaleString("en-US",{minimumFractionDigits:2,maximumFractionDigits:2})} pts`;
};
const pipsLabel=value=>Number.isFinite(Number(value))?`≈ ${Math.round(Number(value)).toLocaleString("en-US")} pips/points`:"—";
const modelStatusText=result=>{
  if(!result)return"En attente";
  if(result.status==="ok")return`${modelDirectionLabel(result.direction)} · ${Math.round(Number(result.confidence)||0)}%`;
  if(result.status==="warming_up")return"Apprentissage";
  if(result.status==="low_quality")return"Qualité insuffisante";
  if(result.status==="pending")return"Prévision en attente";
  if(result.status==="not_selected")return"Non sélectionné";
  if(result.status==="unavailable")return"Indisponible";
  if(result.status==="error")return"Erreur";
  return String(result.status||"En attente");
};
const swingBadgeText=row=>{
  if(row?.mode!=="swing")return"";
  const timing=row?.timing;
  const kind=timing?.swing_class||"COURT";
  const prefix=timing?.is_confirmed?"SWING":"PROJECTION SWING";
  return `${prefix} ${kind} · ${swingDurationLabel(timing)}`;
};
const hasDerivResults=()=>payload?.ok===true&&["ai_analyzed","autonomous_analyzed","smart_local","technical_only"].includes(payload?.status)&&payload?.source_broker==="Deriv"&&Array.isArray(payload?.markets);
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
$("watchOptionsToggle")?.addEventListener("click",()=>{
  const panel=$("trendWatchOptions"),button=$("watchOptionsToggle");
  if(!panel||!button)return;
  const open=panel.hidden;
  panel.hidden=!open;
  button.setAttribute("aria-expanded",String(open));
  button.textContent=open?"Fermer":"Options";
});
$("qwenAdvisorButton")?.addEventListener("click",runQwenAdvisor);
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
  $("modelName").textContent=payload?.model||"Sera Autonomous Engine";
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
  const autonomousActive=fresh&&["autonomous_analyzed","smart_local"].includes(payload.status);
  const ossActive=fresh&&Boolean(payload?.open_source_models);
  setAiStatus(aiActive?(ossActive?"Autonome + OSS + Luna":"Autonome + Luna"):autonomousActive?(ossActive?"Autonome + OSS":"Moteur autonome actif"):fresh?"Moteur autonome : analyse":"Validation expirée",aiActive||autonomousActive?"live":fresh?"":"error");
  notice.className=`notice ${aiActive||autonomousActive?"success":"warning"}`;
  notice.textContent=aiActive
    ?`${payload.markets_count} analyses autonomes · ${payload.confirmed_signals??0} signal(aux) final(aux). Luna a audité ${payload.ai_candidates??0} candidat(s), mais la décision primaire reste locale.`
    :autonomousActive
      ?`${payload.markets_count} analyses autonomes actualisées · ${payload.confirmed_signals??0} signal(aux) final(aux). OpenAI n’est pas nécessaire pour prendre la décision.`
      :fresh
        ?`${payload.markets_count} analyses locales actualisées. Le moteur reste sur ATTENDRE quand le consensus des stratégies est insuffisant.`
        :`Validation expirée depuis ${ageLabel(payload.updated_at)}. Les anciens BUY/SELL sont neutralisés sur ATTENDRE jusqu’à une nouvelle analyse.`;
  const allowedMarkets=new Set(marketsForIndexFamily());
  const rows=payload.markets.filter(row=>allowedMarkets.has(row.market)&&(tradingMode==="all"||row.mode===tradingMode));
  rows.slice().sort(compareSignalPriority).forEach(row=>results.appendChild(resultCard(row,fresh)));
  $("visibleResultsCount")?.remove?.();
  renderSelected();
}

function signalPriority(row){
  if(row?.final_verdict==="BUY"||row?.final_verdict==="SELL")return 3;
  if(hasDetectedSetup(row))return 2;
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
  const conditions=Number(row?.decision_engine?.condition_pass_percent)||0;
  const setupType=String(row?.decision_engine?.setup_type||"GENERIC").replaceAll("_"," ");
  const detected=hasDetectedSetup(row),detectedSide=setupSide(row);
  const execState=row?.execution_state||row?.execution?.state||"WAIT_CONFIRMATION";
  const status=verdict!=="ATTENDRE"?executionLabel(row):detected?`SETUP ${detectedSide} DÉTECTÉ`:conditions>=80?"80% atteint · garde-fou en attente":"En attente";
  const timing=row.timing,bias=timing?.bias||"NEUTRE",direction=verdict!=="ATTENDRE"?verdict:detected?`Setup ${detectedSide}`:`Biais ${bias}`;
  const ensemble=row?.open_source_ai?.ensemble;
  const oss=Number(ensemble?.reliable_models??ensemble?.available_models)>0 && Number.isFinite(Number(ensemble?.consensus))
    ?`OSS ${modelDirectionLabel(ensemble.direction)} ${Math.round(Number(ensemble.consensus))}%`
    :Number(ensemble?.connected_models)>0
      ?`OSS ${ensemble.connected_models}/${ensemble.configured_models||4} connectés`
      :"OSS connexion…";
  const setupMarker=detected?`<span class="setup-side ${detectedSide.toLowerCase()}"><i></i> SETUP ${detectedSide}</span>`:"";
  const swingBadge=row.mode==="swing"?`<div class="swing-duration-badge ${String(row.timing?.swing_class||"court").toLowerCase()}">${escapeHtml(swingBadgeText(row))}</div>`:"";
  const swingDistance=row.swing_distance||(detected?row.projected_swing_distance:null);
  const pipsMini=row.mode==="swing"&&swingDistance?`<div class="swing-pips-mini">${signedDistance(swingDistance.estimated_swing_price_distance,detectedSide||verdict)} · ${pipsLabel(swingDistance.estimated_swing_pips_points)}</div>`:"";
  const action=simpleActionState(row);
  const actionChip=`<div class="trade-action-chip ${action.side} ${action.blink?"blink":""}"><i></i><strong>${escapeHtml(action.label)}</strong><span>${escapeHtml(action.detail)}</span></div>`;
  card.innerHTML=`<div class="result-top"><div><h3>${escapeHtml(row.market)}</h3><p class="symbol">${escapeHtml(row.symbol||row.market)}</p>${setupMarker}${pipsMini}</div><span class="signal ${signalClass(verdict)}">${verdict}</span></div>${actionChip}${swingBadge}<div class="compact-signal-row"><span>${row.mode==="day"?"DAY · M15/H1":"SWING · H1/H4"}</span><b>${direction}</b><strong>${confidence}%</strong></div><div class="result-timing ${detected?detectedSide.toLowerCase():signalClass(verdict)}"><span>${status}</span><b>${escapeHtml(oss)} · ${conditions}%</b></div><div class="result-bar"><i style="width:${Math.max(confidence,conditions)}%"></i></div>`;
  card.onclick=()=>{selected=row.market;selectedMode=row.mode||"swing";liveQuote=null;ensureMarketOption(row.market);$("marketSelect").value=selected;renderSelected();connectLivePrice();openSignalModal(row.market);};
  return card;
}

function renderSelected(){
  $("selectedMarket").textContent=selected;
  if(marketFamily==="forex"){
    $("verdictBadge").className="verdict-badge wait";$("verdictBadge").textContent="EN ATTENTE";
    $("decisionOrb").className="decision-orb wait";$("decisionOrb").querySelector("strong").textContent="ATTENDRE";
    $("decisionConfidence").textContent="Connexion MT5 requise";
    $("decisionSummary").textContent=`${selected} est ajouté au scanner. Son analyse H1/H4 par Sera Autonomous Engine démarrera uniquement après connexion des vraies bougies Deriv MT5.`;
    const setupBadge=$("setupDirectionBadge");
    if(setupBadge){setupBadge.className="setup-direction wait";setupBadge.innerHTML="<i></i> SETUP EN ATTENTE";}
    $("livePrice").textContent="—";$("liveChange").textContent="Deriv MT5 · attente";
    $("levels").querySelectorAll("strong").forEach(element=>element.textContent="—");
    $("timingPanel").querySelectorAll("strong").forEach(element=>element.textContent="—");
    $("timingNote").textContent="Durée, expiration et objectifs seront calculés après réception des vraies bougies MT5.";
    renderSwingPips(null);
    $("technicalGrid").innerHTML=[["Sessions","Londres / New York"],["Tendance","H1 + H4"],["Volatilité","ATR Forex"],["Actualités","Contrôle requis"]].map(([label,value])=>`<div class="metric"><small>${label}</small><strong class="no">${value}</strong></div>`).join("");
    $("checks").innerHTML='<div class="check no"><i></i><span>Flux de bougies Deriv MT5 non connecté</span></div><div class="check no"><i></i><span>Aucun signal ni pourcentage ne sera fabriqué</span></div>';
    renderOpenSourceModels(null);
    renderLiveEntry(null);
    renderTradeAction(null);
    $("signalActions").hidden=true;drawChart("wait");highlightSelected();return;
  }
  const candidates=hasDerivResults()?payload.markets.filter(item=>item.market===selected):[];
  const row=candidates.find(item=>item.mode===selectedMode)||candidates[0]||null;
  if(row?.mode)selectedMode=row.mode;
  const fresh=Boolean(row)&&resultsAreFresh();
  const verdict=fresh?row.final_verdict:"ATTENDRE",cls=signalClass(verdict);
  const detected=Boolean(row)&&hasDetectedSetup(row),detectedSide=detected?setupSide(row):"NEUTRE";
  $("verdictBadge").className=`verdict-badge ${cls}`;
  $("verdictBadge").textContent=verdict;
  const setupBadge=$("setupDirectionBadge");
  if(setupBadge){
    setupBadge.className=`setup-direction ${detected?detectedSide.toLowerCase():"wait"}`;
    setupBadge.innerHTML=detected?`<i></i> SETUP ${detectedSide}`:"<i></i> SETUP EN ATTENTE";
  }
  $("decisionOrb").className=`decision-orb ${cls}`;
  $("decisionOrb").querySelector("strong").textContent=verdict;
  $("decisionConfidence").textContent=fresh?(row.score_type==="setup_readiness"?`${row.final_confidence}% de préparation`:`${row.final_confidence}% · ${executionLabel(row)}`):"Validation requise";
  $("decisionSummary").textContent=fresh&&row?.ai_summary?row.ai_summary:`Sera attend le prochain consensus multi-stratégies pour ${selected}. Luna reste un conseiller facultatif.`;
  renderOpenSourceModels(row);
  renderLiveEntry(row);
  renderTradeAction(row);
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
  $("liveChange").textContent=liveQuote?.symbol===symbols[selected]?"Prix Deriv live":detected?`SETUP ${detectedSide} détecté`:row?`${row.technical_verdict} technique`:"Deriv · attente";
  const displayedLevels=verdict!=="ATTENDRE"&&row?.levels?row.levels:(detected?row?.projected_levels:null);
  const levelValues=displayedLevels
    ?[displayedLevels.entry,displayedLevels.sl,displayedLevels.tp1,displayedLevels.tp2,displayedLevels.tp3,displayedLevels.tp4,displayedLevels.tp5]
    :[null,null,null,null,null,null,null];
  $("levels").querySelectorAll("strong").forEach((element,index)=>element.textContent=fmt(levelValues[index]));
  renderSwingPips(row);
  const technical=row?.entry_tf||row?.h1;
  const confirmation=row?.confirmation_tf||row?.h4;
  const metrics=[[`Entrée: ${executionLabel(row)}`,row?.execution_state==="EXECUTE_NOW"],[`Score exécution ${Number(row?.execution_score)||0}% / 78%`,Number(row?.execution_score)>=78],[`Conditions ${Number(row?.decision_engine?.condition_pass_percent)||0}% / 80%`,Number(row?.decision_engine?.condition_pass_percent)>=80],["Consensus stratégies",Number(row?.decision_engine?.consensus)>=62],[`Tendance ${row?.timeframes?.[1]||"H4"}`,confirmation?.trendStrong],["Alignement TF",technical?.side&&technical?.side===confirmation?.side],["Régime directionnel",row?.intelligence?.regime==="TRENDING"],["Mémoire tendance",row?.trend_memory?.persistence&&!row?.trend_memory?.flip],["BOS / CHoCH",technical&&(technical.bos||technical.choch)],["Liquidité",technical?.sweep],["Break & Retest",technical?.retest],["Momentum RSI",technical?.momentum]];
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
    hoursLabel(timing.tp4_hours),
    hoursLabel(timing.tp5_hours),
    `${timing.expires_in_hours} h`,
    `toutes les ${timing.recheck_hours} h`
  ]:["—","—","—","—","—","—","—","—","—","—"];
  $("timingPanel").querySelectorAll("strong").forEach((element,index)=>element.textContent=timingValues[index]);
  $("timingPanel").className=`timing-panel ${cls}`;
  $("timingNote").textContent=timing?.is_confirmed
    ?row?.mode==="swing"
      ?`${swingBadgeText(row)} · ${executionLabel(row)}. ${row?.execution?.reason||"Estimation basée sur l’ATR, la persistance de tendance H1/H4 et la distance vers les objectifs."}`
      :`${executionLabel(row)}. ${row?.execution?.reason||`Le signal expire après ${timing.expires_in_hours} h sans déclenchement.`}`
    :row?.mode==="swing"
      ?`${swingBadgeText(row)} selon le biais ${timing?.bias||"actuel"}. Projection réévaluée chaque heure tant que le signal n’est pas confirmé.`
      :`Aucun trade confirmé. Horizon projeté si le biais ${timing?.bias||"actuel"} est validé; réévaluation automatique à la prochaine analyse.`;
  $("signalActions").hidden=!(fresh&&verdict!=="ATTENDRE");
  drawChart(cls);
  highlightSelected();
}

function liveEntryProposal(row){
  if(!row||!hasDetectedSetup(row))return null;
  const plan=row.setup_entry_plan;
  const levels=row.projected_levels;
  if(!plan||!levels)return null;
  const side=setupSide(row);
  const live=liveQuote?.symbol===symbols[row.market]?Number(liveQuote.price):Number(row.price);
  if(!Number.isFinite(live))return {...plan,live_price:null,live_state:plan.status};

  const inZone=live>=Number(plan.zone_min)&&live<=Number(plan.zone_max);
  let liveState=plan.status;
  let proposed=Number(plan.suggested_entry);

  if(inZone){
    proposed=live;
    liveState="IN_ENTRY_ZONE";
  }else if(side==="BUY"&&live>Number(plan.zone_max)){
    liveState="WAIT_RETRACE";
  }else if(side==="SELL"&&live<Number(plan.zone_min)){
    liveState="WAIT_RETRACE";
  }else{
    liveState="WAIT_CONFIRMATION";
  }
  return {...plan,live_price:live,proposed_entry:Number(proposed.toFixed(3)),live_state:liveState,in_zone:inZone};
}

function renderLiveEntry(row){
  const box=$("liveEntryBox"),value=$("liveEntryValue"),state=$("liveEntryState");
  if(!box||!value||!state)return;
  const proposal=liveEntryProposal(row);
  if(!proposal){
    box.hidden=true;value.textContent="—";state.textContent="En attente";return;
  }
  box.hidden=false;
  const side=setupSide(row);
  value.textContent=`${side} · ${fmtEntry(proposal.proposed_entry??proposal.suggested_entry)}`;
  const labels={IN_ENTRY_ZONE:"PRIX DANS LA ZONE",WAIT_RETRACE:"ATTENDRE RETRACEMENT",WAIT_CONFIRMATION:"ATTENDRE CONFIRMATION",WATCH_ENTRY_ZONE:"SURVEILLER LA ZONE"};
  state.textContent=`${labels[proposal.live_state]||proposal.live_state} · zone ${fmtEntry(proposal.zone_min)} – ${fmtEntry(proposal.zone_max)}`;
  box.className=`live-entry-box ${side.toLowerCase()} ${proposal.live_state==="IN_ENTRY_ZONE"?"ready":""}`;
}

function renderTradeAction(row){
  const box=$("tradeActionBox"),label=$("tradeActionLabel"),detail=$("tradeActionDetail");
  if(!box||!label||!detail)return;
  const action=simpleActionState(row);
  box.className=`trade-action-box ${action.side} ${action.blink?"blink":""}`;
  label.textContent=action.label;
  detail.textContent=action.detail;
}

function renderSwingPips(row){
  const panel=$("swingPipsPanel"),total=$("swingPipsTotal"),grid=$("swingPipsGrid");
  if(!panel||!total||!grid)return;
  if(!row||row.mode!=="swing"){
    panel.hidden=true;
    total.textContent="—";
    grid.innerHTML="";
    return;
  }
  const detected=hasDetectedSetup(row);
  const distance=row.swing_distance||(detected?row.projected_swing_distance:null);
  const side=row.final_verdict!=="ATTENDRE"?row.final_verdict:setupSide(row);
  if(!distance){
    panel.hidden=true;
    total.textContent="—";
    grid.innerHTML="";
    return;
  }
  panel.hidden=false;
  total.textContent=`${signedDistance(distance.estimated_swing_price_distance,side)} · ${pipsLabel(distance.estimated_swing_pips_points)}`;
  const targets=["tp1","tp2","tp3","tp4","tp5"];
  grid.innerHTML=targets.map(key=>{
    const item=distance[key];
    return `<div><small>${key.toUpperCase()}</small><strong>${signedDistance(item?.price_distance,side)}</strong><span>${pipsLabel(item?.pips_points)}</span></div>`;
  }).join("");
}

function renderOpenSourceModels(row){
  const host=$("modelEnsembleGrid"),summary=$("modelEnsembleSummary"),count=$("modelEnsembleCount");
  if(!host||!summary||!count)return;
  const oss=row?.open_source_ai;
  const models=oss?.models||{};
  const entries=[
    ["XGBoost",models.xgboost],
    ["LightGBM",models.lightgbm],
    ["Chronos-2",models.chronos2],
    ["TimesFM 2.5",models.timesfm25]
  ];
  host.innerHTML=entries.map(([name,result])=>{
    const direction=result?.direction||"NEUTRAL";
    const cls=direction==="BUY"?"buy":direction==="SELL"?"sell":"wait";
    return `<div class="oss-model ${cls}"><small>${escapeHtml(name)}</small><strong>${escapeHtml(modelStatusText(result))}</strong></div>`;
  }).join("");
  const ensemble=oss?.ensemble;
  const configured=Number(ensemble?.configured_models??payload?.open_source_models?.configured_models??4);
  const connected=Number(ensemble?.connected_models??0);
  const reliable=Number(ensemble?.reliable_models??ensemble?.available_models??0);
  const consensus=ensemble?.consensus;
  if(connected>0){
    if(reliable>0 && Number.isFinite(Number(consensus))){
      summary.textContent=`${modelDirectionLabel(ensemble.direction)} · ${Math.round(Number(consensus))}% consensus fiable`;
      summary.className=signalClass(ensemble.direction);
    }else{
      summary.textContent="Connectés · aucun vote fiable pour ce cycle";
      summary.className="wait";
    }
    count.textContent=`${connected}/${configured} connectés · ${reliable} fiable(s)`;
  }else{
    summary.textContent="Connexion des modèles en cours";
    count.textContent=`0/${configured} connectés`;
    summary.className="wait";
  }
  const qwenButton=$("qwenAdvisorButton"),qwenOutput=$("qwenAdvisorOutput");
  if(qwenButton){
    qwenButton.disabled=false;
    qwenButton.textContent=qwenLoadedModel?"Relancer Qwen local":"Lancer Qwen local";
  }
  if(qwenOutput){
    qwenOutput.hidden=true;
    qwenOutput.textContent="";
  }
}

function selectedSignalRow(){
  if(!hasDerivResults())return null;
  const rows=payload.markets.filter(item=>item.market===selected);
  return rows.find(item=>item.mode===selectedMode)||rows[0]||null;
}

async function runQwenAdvisor(){
  const button=$("qwenAdvisorButton"),output=$("qwenAdvisorOutput"),row=selectedSignalRow();
  if(!button||!output||!row||qwenLoading)return;
  output.hidden=false;
  if(!("gpu" in navigator)){
    output.textContent="Qwen local nécessite WebGPU. Le moteur Sera et les autres modèles continuent de fonctionner sans lui.";
    return;
  }
  qwenLoading=true;
  button.disabled=true;
  try{
    if(!qwenEngine){
      output.textContent="Chargement de Qwen3-0.6B local… Le premier chargement télécharge le modèle et peut prendre du temps.";
      const webllm=await import("https://cdn.jsdelivr.net/npm/@mlc-ai/web-llm/+esm");
      const model="Qwen3-0.6B-q4f16_1-MLC";
      qwenEngine=await webllm.CreateMLCEngine(model,{
        initProgressCallback:report=>{
          output.textContent=`Qwen local : ${report.text||"chargement…"}`;
        }
      });
      qwenLoadedModel=model;
    }
    button.textContent="Qwen analyse…";
    const compact={
      market:row.market,mode:row.mode,timeframes:row.timeframes,
      final_verdict:row.final_verdict,final_confidence:row.final_confidence,
      execution_state:row.execution_state,execution_score:row.execution_score,
      setup_type:row.decision_engine?.setup_type,
      conditions:row.decision_engine?.condition_pass_percent,
      strategy_consensus:row.decision_engine?.consensus,
      regime:row.intelligence?.regime,
      entry_tf:{side:row.entry_tf?.side,rsi:row.entry_tf?.rsi,trendQuality:row.entry_tf?.trendQuality,spikeRisk:row.entry_tf?.spikeRisk,bos:row.entry_tf?.bos,choch:row.entry_tf?.choch,sweep:row.entry_tf?.sweep,retest:row.entry_tf?.retest},
      confirmation_tf:{side:row.confirmation_tf?.side,rsi:row.confirmation_tf?.rsi,trendQuality:row.confirmation_tf?.trendQuality,spikeRisk:row.confirmation_tf?.spikeRisk},
      setup_detected:row.setup_detected,setup_direction:row.setup_direction,projected_levels:row.projected_levels,
      oss_ensemble:row.open_source_ai?.ensemble,
      model_votes:row.open_source_ai?.models
    };
    const response=await qwenEngine.chat.completions.create({
      messages:[
        {role:"system",content:"Tu es le conseiller local de Sera Indicator. Tu n'exécutes aucun trade et tu ne modifies jamais la décision du moteur. Analyse uniquement les données fournies. Réponds en français, maximum 5 lignes: accord/désaccord avec le signal, 2 confirmations majeures, principal risque, et remarque sur le timing d'entrée. Ne promets jamais un gain."},
        {role:"user",content:JSON.stringify(compact)}
      ],
      temperature:.15,
      max_tokens:220,
      extra_body:{enable_thinking:false}
    });
    output.textContent=response?.choices?.[0]?.message?.content?.trim()||"Qwen n’a pas retourné d’avis.";
  }catch(error){
    output.textContent=`Qwen local indisponible : ${error?.message||error}. Les autres moteurs restent actifs.`;
  }finally{
    qwenLoading=false;
    button.disabled=false;
    button.textContent=qwenLoadedModel?"Relancer Qwen local":"Lancer Qwen local";
  }
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
    ?`${row.final_verdict} · ${executionLabel(row)} · ${row.final_confidence}%`
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
    execution:row?.execution_state||row?.execution?.state||"WAIT_CONFIRMATION",
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
    const becameExecutable=current.execution==="EXECUTE_NOW"&&previous&&previous.execution!=="EXECUTE_NOW";
    const directionChanged=previous&&previous.verdict!==current.verdict;
    if(watched&&isSignal&&previous&&(directionChanged||becameExecutable)){
      notifyTrendSignal(row,previous.verdict);
    }
    trendWatchSnapshots[id]=current;
  }
  saveTrendWatchSnapshots();
  renderTrendWatchUi();
}

function notifyTrendSignal(row,previousVerdict){
  const text=`${row.market}: ${row.final_verdict} Swing H1/H4 à ${row.final_confidence}% · ${executionLabel(row)} (avant: ${previousVerdict||"ATTENDRE"}).`;
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
      if(message.tick?.quote){
        liveQuote={symbol,price:Number(message.tick.quote)};
        if(symbol===symbols[selected]){
          $("livePrice").textContent=fmt(liveQuote.price);
          $("liveChange").textContent="Prix Deriv live";
          setMarketStatus("Deriv : Live","live");
          const row=selectedSignalRow();
          renderLiveEntry(row);
          renderTradeAction(row);
        }
      }
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
  return [
    "SERA INDICATOR — SIGNAL DERIV CONFIRMÉ",
    `Indice : ${row.market}`,
    `Signal : ${row.final_verdict}`,
    `Confiance : ${row.final_confidence}%`,
    `État entrée : ${executionLabel(row)}`,
    `Score exécution : ${row.execution_score??0}%`,
    `Entrée : ${fmt(row.levels?.entry)}`,
    `Stop Loss : ${fmt(row.levels?.sl)}`,
    `TP1 : ${fmt(row.levels?.tp1)}`,
    `TP2 : ${fmt(row.levels?.tp2)}`,
    `TP3 : ${fmt(row.levels?.tp3)}`,
    `TP4 : ${fmt(row.levels?.tp4)}`,
    `TP5 : ${fmt(row.levels?.tp5)}`,
    `Analyse : ${new Date(payload.updated_at).toLocaleString("fr-FR")}`,
    `Consensus OSS : ${Number.isFinite(Number(row.model_ensemble_consensus))&&Number(row.model_models_available)>0?`${row.model_ensemble_direction||"NEUTRAL"} ${Math.round(Number(row.model_ensemble_consensus))}%`:"aucun vote fiable"} · ${Number(row.model_models_available)||0} vote(s) fiable(s)`,
    `Modèle : ${row.ai_tier}`,
    "",
    "Signal autonome — ≥80% des conditions pertinentes sont requises. L’EA Sera v1.50 n’exécute que si l’état est EXECUTE_NOW, applique le garde-fou open source et gère progressivement la protection des objectifs. Aucun gain garanti.",
    location.href
  ].join("\n");
}
async function copySignal(){const text=currentSignalText();if(!text)return;await navigator.clipboard.writeText(text);$("copySignal").textContent="Copié ✓";setTimeout(()=>$("copySignal").textContent="Copier le signal",1500);}
async function shareSignal(){const text=currentSignalText();if(!text)return;if(navigator.share)await navigator.share({title:"Signal Deriv — Sera Indicator",text,url:location.href});else await navigator.clipboard.writeText(text);}
function escapeHtml(value){return String(value).replace(/[&<>'"]/g,char=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[char]));}

renderIndexFamilyFilter();
fillMarketSelect();
renderTrendWatchUi();
loadSignals();
connectLivePrice();
setInterval(()=>loadSignals(false),20000);
