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
const $=id=>document.getElementById(id);
let payload=null;
let selected=derivMarkets[0];
let liveSocket=null;
let liveQuote=null;

const fmt=n=>Number.isFinite(Number(n))?Number(n).toLocaleString("en-US",{minimumFractionDigits:2,maximumFractionDigits:2}):"—";
const ageMinutes=iso=>iso?(Date.now()-Date.parse(iso))/60000:Infinity;
const signalClass=value=>value==="BUY"?"buy":value==="SELL"?"sell":"wait";
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

function fillMarketSelect(){
  $("marketSelect").innerHTML=derivMarkets.map(name=>`<option value="${name}">${name}</option>`).join("");
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

  if(!hasDerivResults()){
    setMarketStatus("Deriv : connexion en cours","error");
    setAiStatus("OpenAI : analyse en attente","error");
    notice.className="notice warning";
    notice.textContent=payload?.note||"ATTENDRE — la première analyse Deriv H1/H4 n’est pas encore disponible.";
    renderWaitingCards(results);
    renderSelected();
    return;
  }

  setMarketStatus(fresh?"Deriv : données H1/H4":"Deriv : données anciennes",fresh?"live":"error");
  setAiStatus(fresh?"OpenAI : actif":"OpenAI : validation expirée",fresh?"live":"error");
  notice.className=`notice ${fresh?"success":"warning"}`;
  notice.textContent=fresh
    ?`${payload.markets_count} indices Deriv analysés. BUY/SELL exige l’accord du moteur technique et d’OpenAI; l’exécution reste entièrement manuelle.`
    :"La validation IA est trop ancienne. Tous les verdicts restent sur ATTENDRE jusqu’à la prochaine analyse automatique.";
  payload.markets.slice().sort((a,b)=>(b.final_confidence||0)-(a.final_confidence||0)).forEach(row=>results.appendChild(resultCard(row,fresh)));
  renderSelected();
}

function renderWaitingCards(container){
  derivMarkets.forEach(name=>{
    const card=document.createElement("button");
    card.className=`result-card${name===selected?" selected":""}`;
    card.innerHTML=`<div class="result-top"><div><h3>${name}</h3><p class="symbol">${symbols[name]} · H1/H4</p></div><span class="signal wait">ATTENDRE</span></div><div class="result-score"><strong>—</strong><small>Confiance IA</small></div><div class="result-bar"><i style="width:0%"></i></div>`;
    card.onclick=()=>{selected=name;liveQuote=null;$("marketSelect").value=name;renderSelected();highlightSelected();connectLivePrice();};
    container.appendChild(card);
  });
}

function resultCard(row,fresh){
  const verdict=fresh?row.final_verdict:"ATTENDRE",confidence=fresh?Number(row.final_confidence)||0:0;
  const card=document.createElement("button");
  card.className=`result-card${row.market===selected?" selected":""}`;
  card.innerHTML=`<div class="result-top"><div><h3>${escapeHtml(row.market)}</h3><p class="symbol">${escapeHtml(row.symbol||row.market)} · H1/H4</p></div><span class="signal ${signalClass(verdict)}">${verdict}</span></div><div class="result-score"><strong>${confidence}%</strong><small>${escapeHtml(row.ai_tier||"OpenAI")}</small></div><div class="result-bar"><i style="width:${confidence}%"></i></div>`;
  card.onclick=()=>{selected=row.market;liveQuote=null;ensureMarketOption(row.market);$("marketSelect").value=selected;renderSelected();connectLivePrice();document.querySelector(".analysis-grid").scrollIntoView({behavior:"smooth",block:"start"});};
  return card;
}

function renderSelected(){
  $("selectedMarket").textContent=selected;
  const row=hasDerivResults()?payload.markets.find(item=>item.market===selected):null;
  const fresh=Boolean(row)&&resultsAreFresh();
  const verdict=fresh?row.final_verdict:"ATTENDRE",cls=signalClass(verdict);
  $("verdictBadge").className=`verdict-badge ${cls}`;
  $("verdictBadge").textContent=verdict;
  $("decisionOrb").className=`decision-orb ${cls}`;
  $("decisionOrb").querySelector("strong").textContent=verdict;
  $("decisionConfidence").textContent=fresh?`${row.final_confidence}% de confiance`:"Validation requise";
  $("decisionSummary").textContent=fresh&&row?.ai_summary?row.ai_summary:`Sera attend une analyse Deriv H1/H4 et une validation OpenAI récente pour ${selected}.`;
  const currentPrice=liveQuote?.symbol===symbols[selected]?liveQuote.price:row?.price;
  $("livePrice").textContent=fmt(currentPrice);
  $("liveChange").textContent=liveQuote?.symbol===symbols[selected]?"Prix Deriv live":row?`${row.technical_verdict} technique`:"Deriv · attente";
  const levelValues=verdict!=="ATTENDRE"&&row?.levels?[row.levels.entry,row.levels.sl,row.levels.tp1,row.levels.tp2,row.levels.tp3]:[null,null,null,null,null];
  $("levels").querySelectorAll("strong").forEach((element,index)=>element.textContent=fmt(levelValues[index]));
  const technical=row?.h1;
  const metrics=[["Tendance H4",row?.h4?.trendStrong],["H1 ↔ H4",row?.h1?.side&&row?.h1?.side===row?.h4?.side],["BOS / CHoCH",technical&&(technical.bos||technical.choch)],["Liquidité",technical?.sweep],["Order Block",technical?.orderBlock],["Fair Value Gap",technical?.fvg],["Break & Retest",technical?.retest],["Momentum RSI",technical?.momentum]];
  $("technicalGrid").innerHTML=metrics.map(([label,ok])=>`<div class="metric"><small>${label}</small><strong class="${ok?"ok":"no"}">${ok?"Confirmé":"Non confirmé"}</strong></div>`).join("");
  const confirmations=fresh?(row?.ai_confirmations||[]):[],contradictions=fresh?(row?.ai_contradictions||[]):[];
  $("checks").innerHTML=[...confirmations.map(text=>`<div class="check"><i></i><span>${escapeHtml(text)}</span></div>`),...contradictions.map(text=>`<div class="check no"><i></i><span>${escapeHtml(text)}</span></div>`)].join("")||'<div class="check no"><i></i><span>Données Deriv et analyse OpenAI récente requises</span></div>';
  $("signalActions").hidden=!(fresh&&verdict!=="ATTENDRE");
  drawChart(cls);
  highlightSelected();
}

function connectLivePrice(){
  if(liveSocket){liveSocket.close();liveSocket=null;}
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
  const row=hasDerivResults()?payload.markets.find(item=>item.market===selected):null;
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
