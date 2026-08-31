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
let tradingMode="all";
let selectedMode="day";
const welcomePopup=$("welcomePopup");
const welcomeContinue=$("welcomeContinue");
document.body.classList.add("popup-open");
welcomeContinue.addEventListener("click",closeWelcomePopup);
welcomePopup.addEventListener("click",event=>{if(event.target===welcomePopup)closeWelcomePopup();});
document.addEventListener("keydown",event=>{if(event.key==="Escape"&&!welcomePopup.classList.contains("closed"))closeWelcomePopup();});
function closeWelcomePopup(){
  welcomePopup.classList.add("closed");
  document.body.classList.remove("popup-open");
  setTimeout(()=>welcomePopup.setAttribute("hidden",""),230);
}


const fmt=n=>Number.isFinite(Number(n))?Number(n).toLocaleString("en-US",{minimumFractionDigits:2,maximumFractionDigits:2}):"—";
const ageMinutes=iso=>iso?(Date.now()-Date.parse(iso))/60000:Infinity;
const signalClass=value=>value==="BUY"?"buy":value==="SELL"?"sell":"wait";
const hoursLabel=value=>Number.isFinite(Number(value))?`≈ ${Math.round(Number(value))} h`:"—";
const durationLabel=timing=>timing?`${timing.duration_min_hours}–${timing.duration_max_hours} h`:"—";
const hasDerivResults=()=>payload?.ok===true&&payload?.status==="ai_analyzed"&&payload?.source_broker==="Deriv"&&Array.isArray(payload?.markets);
const resultsAreFresh=()=>hasDerivResults()&&ageMinutes(payload.updated_at)<130;

$("refreshButton").addEventListener("click",()=>loadSignals(true));
$("marketSelect").addEventListener("change",event=>{
  selected=event.target.value;
  liveQuote=null;
  renderSelected();
  connectLivePrice();
});
$("copySignal").addEventListener("click",copySignal);
$("shareSignal").addEventListener("click",shareSignal);
$("syntheticFilter").addEventListener("click",()=>setMarketFamily("synthetic"));
$("forexFilter").addEventListener("click",()=>setMarketFamily("forex"));
document.querySelectorAll(".mode-filter").forEach(button=>button.addEventListener("click",()=>setTradingMode(button.dataset.mode)));

function setTradingMode(mode){
  tradingMode=mode;
  if(mode!=="all")selectedMode=mode;
  document.querySelectorAll(".mode-filter").forEach(button=>{const active=button.dataset.mode===mode;button.classList.toggle("active",active);button.setAttribute("aria-selected",String(active));});
  $("updateFrequency").textContent=mode==="swing"?"chaque heure":"toutes les 15 minutes";
  render();
}

function setMarketFamily(family){
  marketFamily=family;
  $("syntheticFilter").classList.toggle("active",family==="synthetic");
  $("forexFilter").classList.toggle("active",family==="forex");
  $("syntheticFilter").setAttribute("aria-selected",String(family==="synthetic"));
  $("forexFilter").setAttribute("aria-selected",String(family==="forex"));
  selected=(family==="synthetic"?derivMarkets:forexMarkets)[0];
  liveQuote=null; fillMarketSelect();
  if(family==="synthetic")connectLivePrice();else if(liveSocket){liveSocket.close();liveSocket=null;}
  render();
}

function fillMarketSelect(){
  const markets=marketFamily==="synthetic"?derivMarkets:forexMarkets;
  $("marketSelect").innerHTML=markets.map(name=>`<option value="${name}">${name}</option>`).join("");
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
  }
}

function render(){
  const notice=$("notice"),results=$("results"),fresh=resultsAreFresh();
  results.innerHTML="";
  $("updatedAt").textContent=payload?.updated_at?new Date(payload.updated_at).toLocaleString("fr-FR",{dateStyle:"short",timeStyle:"short"}):"—";
  $("sourceName").textContent=payload?.source||"Deriv WebSocket";
  $("modelName").textContent=payload?.model||"Luna + Sol";

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
  setAiStatus(fresh?"OpenAI : actif":"OpenAI : validation expirée",fresh?"live":"error");
  notice.className=`notice ${fresh?"success":"warning"}`;
  notice.textContent=fresh
    ?`${payload.markets_count} indices Deriv analysés. BUY/SELL exige l’accord du moteur technique et d’OpenAI; l’exécution reste entièrement manuelle.`
    :"La validation IA est trop ancienne. Tous les verdicts restent sur ATTENDRE jusqu’à la prochaine analyse automatique.";
  const rows=payload.markets.filter(row=>tradingMode==="all"||row.mode===tradingMode);
  rows.slice().sort(compareSignalPriority).forEach(row=>results.appendChild(resultCard(row,fresh)));
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
    card.onclick=()=>{selected=name;$("marketSelect").value=name;renderSelected();highlightSelected();document.querySelector(".analysis-grid").scrollIntoView({behavior:"smooth",block:"start"});};
    container.appendChild(card);
  });
}

function renderWaitingCards(container){
  derivMarkets.forEach(name=>{
    const card=document.createElement("button");
    card.className=`result-card${name===selected?" selected":""}`;
    card.innerHTML=`<div class="result-top"><div><h3>${name}</h3><p class="symbol">${symbols[name]} · H1/H4</p></div><span class="signal wait">ATTENDRE</span></div><div class="result-timing"><span>Biais en analyse</span><b>Horizon —</b></div><div class="result-score"><strong>—</strong><small>Préparation du setup</small></div><div class="result-bar"><i style="width:0%"></i></div>`;
    card.onclick=()=>{selected=name;liveQuote=null;$("marketSelect").value=name;renderSelected();highlightSelected();connectLivePrice();};
    container.appendChild(card);
  });
}

function resultCard(row,fresh){
  const verdict=fresh?row.final_verdict:"ATTENDRE",confidence=fresh?Number(row.final_confidence)||0:0;
  const card=document.createElement("button");
  card.className=`result-card${row.market===selected&&row.mode===selectedMode?" selected":""}`;
  const status=verdict!=="ATTENDRE"?"Confirmé":row.technical_verdict!=="ATTENDRE"?"Détecté · validation IA":"En attente";
  const timing=row.timing,bias=timing?.bias||"NEUTRE",direction=verdict!=="ATTENDRE"?verdict:`Biais ${bias}`;
  card.innerHTML=`<div class="result-top"><div><h3>${escapeHtml(row.market)}</h3><p class="symbol">${escapeHtml(row.symbol||row.market)} · ${escapeHtml(row.timeframes?.join("/")||"H1/H4")}</p></div><span class="signal ${signalClass(verdict)}">${verdict}</span></div><div class="card-profile"><span>${row.mode==="day"?"DAY TRADING":"SWING"}</span><span>${escapeHtml(row.duration?.range||durationLabel(timing))}</span></div><div class="result-timing ${signalClass(verdict)}"><span>${direction}</span><b>${status}</b></div><div class="result-score"><strong>${confidence}%</strong><small>${row.score_type==="setup_readiness"?"Préparation du setup":escapeHtml(row.ai_tier||"Confiance du signal")}</small></div><div class="result-bar"><i style="width:${confidence}%"></i></div>`;
  card.onclick=()=>{selected=row.market;selectedMode=row.mode||"swing";liveQuote=null;ensureMarketOption(row.market);$("marketSelect").value=selected;renderSelected();connectLivePrice();document.querySelector(".analysis-grid").scrollIntoView({behavior:"smooth",block:"start"});};
  return card;
}

function renderSelected(){
  $("selectedMarket").textContent=selected;
  if(marketFamily==="forex"){
    $("verdictBadge").className="verdict-badge wait";$("verdictBadge").textContent="EN ATTENTE";
    $("decisionOrb").className="decision-orb wait";$("decisionOrb").querySelector("strong").textContent="ATTENDRE";
    $("decisionConfidence").textContent="Connexion MT5 requise";
    $("decisionSummary").textContent=`${selected} est ajouté au scanner. Son analyse H1/H4 par Luna et Sol démarrera uniquement après connexion des vraies bougies Deriv MT5.`;
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
  const currentPrice=liveQuote?.symbol===symbols[selected]?liveQuote.price:row?.price;
  $("livePrice").textContent=fmt(currentPrice);
  $("liveChange").textContent=liveQuote?.symbol===symbols[selected]?"Prix Deriv live":row?`${row.technical_verdict} technique`:"Deriv · attente";
  const levelValues=verdict!=="ATTENDRE"&&row?.levels?[row.levels.entry,row.levels.sl,row.levels.tp1,row.levels.tp2,row.levels.tp3]:[null,null,null,null,null];
  $("levels").querySelectorAll("strong").forEach((element,index)=>element.textContent=fmt(levelValues[index]));
  const technical=row?.entry_tf||row?.h1;
  const confirmation=row?.confirmation_tf||row?.h4;
  const metrics=[[`Tendance ${row?.timeframes?.[1]||"H4"}`,confirmation?.trendStrong],["Alignement TF",technical?.side&&technical?.side===confirmation?.side],["BOS / CHoCH",technical&&(technical.bos||technical.choch)],["Liquidité",technical?.sweep],["Order Block",technical?.orderBlock],["Fair Value Gap",technical?.fvg],["Break & Retest",technical?.retest],["Momentum RSI",technical?.momentum]];
  $("technicalGrid").innerHTML=metrics.map(([label,ok])=>`<div class="metric"><small>${label}</small><strong class="${ok?"ok":"no"}">${ok?"Confirmé":"Non confirmé"}</strong></div>`).join("");
  const profile=[row?.mode==="day"?"Day trading":"Swing",row?.duration?.range||"—",row?.duration?.validity||"—",row?.duration?.reanalysis||"—"];
  $("positionProfile").querySelectorAll("strong").forEach((element,index)=>element.textContent=profile[index]);
  const confirmations=fresh?(row?.ai_confirmations||[]):[],contradictions=fresh?(row?.ai_contradictions||[]):[];
  $("checks").innerHTML=[...confirmations.map(text=>`<div class="check"><i></i><span>${escapeHtml(text)}</span></div>`),...contradictions.map(text=>`<div class="check no"><i></i><span>${escapeHtml(text)}</span></div>`)].join("")||'<div class="check no"><i></i><span>Données Deriv et analyse OpenAI récente requises</span></div>';
  const timing=row?.timing;
  const timingValues=timing?[
    timing.is_confirmed?timing.side:`Biais ${timing.bias}`,
    timing.position_style,
    durationLabel(timing),
    hoursLabel(timing.tp1_hours),
    hoursLabel(timing.tp2_hours),
    hoursLabel(timing.tp3_hours),
    `${timing.expires_in_hours} h`,
    `toutes les ${timing.recheck_hours} h`
  ]:["—","—","—","—","—","—","—","—"];
  $("timingPanel").querySelectorAll("strong").forEach((element,index)=>element.textContent=timingValues[index]);
  $("timingPanel").className=`timing-panel ${cls}`;
  $("timingNote").textContent=timing?.is_confirmed
    ?`Estimation basée sur l’ATR H1, la distance vers les TP et la force H1/H4. Le signal expire après ${timing.expires_in_hours} h sans déclenchement.`
    :`Aucun trade confirmé. Horizon projeté si le biais ${timing?.bias||"actuel"} est validé; réévaluation automatique à la prochaine analyse.`;
  $("signalActions").hidden=!(fresh&&verdict!=="ATTENDRE");
  drawChart(cls);
  highlightSelected();
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
  return ["SERA INDICATOR — SIGNAL DERIV CONFIRMÉ",`Indice : ${row.market}`,`Signal : ${row.final_verdict}`,`Confiance : ${row.final_confidence}%`,`Entrée : ${fmt(row.levels?.entry)}`,`Stop Loss : ${fmt(row.levels?.sl)}`,`TP1 : ${fmt(row.levels?.tp1)}`,`TP2 : ${fmt(row.levels?.tp2)}`,`TP3 : ${fmt(row.levels?.tp3)}`,`Analyse : ${new Date(payload.updated_at).toLocaleString("fr-FR")}`,`Modèle : ${row.ai_tier}`,"","Signal uniquement — exécution manuelle sur Deriv. Aucun gain garanti.",location.href].join("\n");
}
async function copySignal(){const text=currentSignalText();if(!text)return;await navigator.clipboard.writeText(text);$("copySignal").textContent="Copié ✓";setTimeout(()=>$("copySignal").textContent="Copier le signal",1500);}
async function shareSignal(){const text=currentSignalText();if(!text)return;if(navigator.share)await navigator.share({title:"Signal Deriv — Sera Indicator",text,url:location.href});else await navigator.clipboard.writeText(text);}
function escapeHtml(value){return String(value).replace(/[&<>'"]/g,char=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[char]));}

fillMarketSelect();
loadSignals();
connectLivePrice();
setInterval(()=>loadSignals(false),60000);
