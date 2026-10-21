/*
 * Sera Chart Engine — graphique de position basé sur TradingView Lightweight Charts
 * (open source, Apache-2.0, intégré dans vendor/ : aucun CDN, aucun coût).
 *
 * - 300 bougies, zoom molette/pincement, défilement, axe du temps en heure locale
 * - Entrée, SL, TP1–TP5 et zone d'entrée sur l'axe des prix
 * - Boîtes risque/rendement façon outil "Position longue/courte"
 * - Flèche BUY/SELL sur la bougie du signal, EMA20/EMA50
 * - Choix de l'unité de temps (Swing H1/H4/D1, Day M15/H1) et du cadrage
 *
 * app.js appelle SeraChart.render(ctx). Si la bibliothèque est absente ou si une
 * erreur survient, render() renvoie false et l'ancien graphique canvas prend le relais.
 */
(function(){
  "use strict";

  const TF_SECONDS={M15:900,H1:3600,H4:14400,D1:86400};
  const HISTORY_COUNT=300;
  const HISTORY_TTL_MS=120000;
  const COLORS={
    up:"#38e8bb",down:"#ff5f76",entry:"#4da3ff",sl:"#ff5f76",tp:"#38e8bb",
    zone:"rgba(77,163,255,.55)",ema20:"#54d8ff",ema50:"#ffb142",text:"#8fa3b8"
  };

  const state={
    disabled:false,chart:null,candles:null,ema20:null,ema50:null,
    host:null,container:null,overlay:null,toolbar:null,legend:null,
    dataKey:"",lastTime:0,lastLength:0,
    priceLines:[],levelsKey:"",markersKey:"",
    tfByMode:{},frame:"plan",
    history:new Map(),historyLoading:new Map(),historyAt:new Map(),
    ctx:null,overlayFrame:0,precision:-1,data:[]
  };

  const tzShift=()=>-new Date().getTimezoneOffset()*60;
  const toChartTime=epoch=>Math.floor(Number(epoch))+tzShift();
  const finite=v=>Number.isFinite(Number(v))&&Number(v)>0;

  function lib(){return window.LightweightCharts&&typeof window.LightweightCharts.createChart==="function"?window.LightweightCharts:null;}

  function availableTimeframes(ctx){
    if(ctx.isForex)return ["H1"];
    return ctx.spec.macro?["H1","H4","D1"]:["M15","H1"];
  }

  function currentTf(ctx){
    const list=availableTimeframes(ctx);
    const chosen=state.tfByMode[ctx.mode];
    return list.includes(chosen)?chosen:ctx.spec.entry;
  }

  /* ---------- données ---------- */

  function normalize(rows){
    const byTime=new Map();
    for(const c of rows||[]){
      const epoch=Number(c.epoch),open=Number(c.open),high=Number(c.high),low=Number(c.low),close=Number(c.close);
      if(![epoch,open,high,low,close].every(Number.isFinite)||open<=0||high<=0||low<=0||close<=0)continue;
      byTime.set(epoch,{epoch,open,high:Math.max(high,open,close),low:Math.min(low,open,close),close});
    }
    return [...byTime.values()].sort((a,b)=>a.epoch-b.epoch);
  }

  function loadHistory(ctx,tf){
    if(ctx.isForex||!ctx.symbol||!ctx.wsUrl)return;
    const key=`${ctx.symbol}:${tf}`;
    if(state.historyLoading.has(key))return;
    if(Date.now()-(state.historyAt.get(key)||0)<HISTORY_TTL_MS&&state.history.get(key)?.length)return;
    let ws;
    try{ws=new WebSocket(ctx.wsUrl);}catch{return;}
    const done=()=>{clearTimeout(timer);state.historyLoading.delete(key);try{ws.close();}catch{}};
    const timer=setTimeout(done,12000);
    state.historyLoading.set(key,true);
    ws.addEventListener("open",()=>ws.send(JSON.stringify({
      ticks_history:ctx.symbol,style:"candles",granularity:TF_SECONDS[tf],
      count:HISTORY_COUNT,end:"latest",adjust_start_time:1,req_id:8801
    })));
    ws.addEventListener("message",event=>{
      let message;try{message=JSON.parse(event.data);}catch{return;}
      if(Array.isArray(message.candles)){
        state.history.set(key,normalize(message.candles));
        state.historyAt.set(key,Date.now());
        done();
        if(state.ctx)render(state.ctx);
      }else if(message.error)done();
    });
    ws.addEventListener("error",done);
  }

  function seriesFor(ctx,tf){
    if(ctx.isForex)return normalize(ctx.row?.chart_candles||[]);
    const history=state.history.get(`${ctx.symbol}:${tf}`)||[];
    const live=normalize(ctx.liveSeries(tf));
    if(!history.length)return live;
    // Les bougies live (ticks) complètent ou remplacent la fin de l'historique.
    const merged=new Map(history.map(c=>[c.epoch,c]));
    const firstHistory=history[0].epoch;
    for(const c of live)if(c.epoch>=firstHistory)merged.set(c.epoch,c);
    return [...merged.values()].sort((a,b)=>a.epoch-b.epoch).slice(-HISTORY_COUNT);
  }

  function emaPoints(rows,period){
    const k=2/(period+1);let value=null;const out=[];
    rows.forEach((c,i)=>{
      value=value===null?c.close:value+k*(c.close-value);
      if(i>=period-1)out.push({time:toChartTime(c.epoch),value});
    });
    return out;
  }

  /* ---------- montage ---------- */

  function mount(ctx){
    const L=lib();
    const host=document.getElementById("chartArea");
    if(!L||!host)return false;
    if(state.chart&&state.host===host&&host.contains(state.container))return true;
    teardown();

    host.classList.add("tv-active");
    const container=document.createElement("div");
    container.className="tv-chart";container.id="seraTvChart";
    const overlay=document.createElement("canvas");
    overlay.className="tv-position-layer";overlay.setAttribute("aria-hidden","true");
    const legend=document.createElement("div");
    legend.className="tv-legend";legend.id="seraChartLegend";
    const toolbar=document.createElement("div");
    toolbar.className="tv-toolbar";toolbar.id="seraChartToolbar";
    container.append(overlay,legend);
    host.append(container,toolbar);

    const chart=L.createChart(container,{
      autoSize:true,
      layout:{background:{type:L.ColorType.Solid,color:"transparent"},textColor:COLORS.text,fontSize:11,fontFamily:"JetBrains Mono, monospace"},
      grid:{vertLines:{color:"rgba(255,255,255,.035)"},horzLines:{color:"rgba(255,255,255,.05)"}},
      rightPriceScale:{borderColor:"rgba(255,255,255,.09)",scaleMargins:{top:.08,bottom:.08}},
      timeScale:{borderColor:"rgba(255,255,255,.09)",timeVisible:true,secondsVisible:false,rightOffset:24,barSpacing:7,minBarSpacing:2},
      crosshair:{mode:L.CrosshairMode.Normal},
      localization:{locale:"fr-FR",priceFormatter:p=>state.ctx?.fmt?state.ctx.fmt(p):String(p)},
      handleScroll:true,handleScale:true
    });
    const candles=chart.addCandlestickSeries({
      upColor:COLORS.up,downColor:COLORS.down,wickUpColor:COLORS.up,wickDownColor:COLORS.down,borderVisible:false,
      autoscaleInfoProvider:original=>{
        const base=original();
        const bounds=frameBounds();
        if(!base||!bounds)return base;
        return {...base,priceRange:{
          minValue:Math.min(base.priceRange.minValue,bounds.min),
          maxValue:Math.max(base.priceRange.maxValue,bounds.max)
        }};
      }
    });
    const ema20=chart.addLineSeries({color:COLORS.ema20,lineWidth:1,priceLineVisible:false,lastValueVisible:false,crosshairMarkerVisible:false});
    const ema50=chart.addLineSeries({color:COLORS.ema50,lineWidth:1,priceLineVisible:false,lastValueVisible:false,crosshairMarkerVisible:false});

    chart.subscribeCrosshairMove(param=>updateLegend(param?.seriesData?.get?.(candles)||null));
    chart.timeScale().subscribeVisibleLogicalRangeChange(scheduleOverlay);
    if(window.ResizeObserver)new ResizeObserver(scheduleOverlay).observe(container);

    Object.assign(state,{chart,candles,ema20,ema50,host,container,overlay,toolbar,legend,
      dataKey:"",lastTime:0,lastLength:0,priceLines:[],levelsKey:"",markersKey:"",precision:-1});
    const canvas=document.getElementById("liveCandlesCanvas");
    if(canvas){const c2=canvas.getContext("2d");c2&&c2.clearRect(0,0,canvas.width,canvas.height);}
    const axis=document.getElementById("livePriceAxis");
    if(axis)axis.innerHTML="";
    return true;
  }

  function teardown(){
    try{state.chart&&state.chart.remove();}catch{}
    state.container?.remove();state.toolbar?.remove();
    state.host?.classList.remove("tv-active");
    Object.assign(state,{chart:null,candles:null,ema20:null,ema50:null,container:null,overlay:null,toolbar:null,legend:null,host:null});
  }

  /* ---------- barre d'outils ---------- */

  function renderToolbar(ctx,tf){
    const list=availableTimeframes(ctx);
    const frames=[["prix","Prix"],["plan","Plan TP3"],["full","Tout TP5"]];
    const key=`${ctx.mode}|${list.join(",")}|${tf}|${state.frame}`;
    if(state.toolbar.dataset.key===key)return;
    state.toolbar.dataset.key=key;
    state.toolbar.innerHTML=
      `<div class="tv-group" role="group" aria-label="Unité de temps du graphique">${list.map(t=>`<button type="button" data-tf="${t}" class="${t===tf?"active":""}" aria-pressed="${t===tf}">${t}</button>`).join("")}</div>`+
      `<div class="tv-group" role="group" aria-label="Cadrage">${frames.map(([id,label])=>`<button type="button" data-frame="${id}" class="${id===state.frame?"active":""}" aria-pressed="${id===state.frame}">${label}</button>`).join("")}</div>`+
      `<button type="button" class="tv-reset" data-reset="1" title="Revenir aux dernières bougies">⟲</button>`;
    state.toolbar.onclick=event=>{
      const button=event.target.closest("button");if(!button||!state.ctx)return;
      if(button.dataset.tf){state.tfByMode[state.ctx.mode]=button.dataset.tf;state.dataKey="";}
      if(button.dataset.frame){state.frame=button.dataset.frame;}
      if(button.dataset.reset){state.chart.timeScale().scrollToRealTime();}
      render(state.ctx);
      if(button.dataset.frame)state.chart.priceScale("right").applyOptions({autoScale:true});
    };
  }

  /* ---------- niveaux et position ---------- */

  function frameBounds(){
    const ctx=state.ctx;if(!ctx||state.frame==="prix")return null;
    const lv=ctx.levels||{};
    const keys=state.frame==="full"?["entry","sl","tp1","tp2","tp3","tp4","tp5","zoneMin","zoneMax"]:["entry","sl","tp1","tp2","tp3","zoneMin","zoneMax"];
    const values=keys.map(k=>Number(lv[k])).filter(finite);
    if(!values.length)return null;
    return {min:Math.min(...values),max:Math.max(...values)};
  }

  function syncPriceLines(ctx){
    const L=lib(),lv=ctx.levels||{},plan=ctx.plan;
    const key=JSON.stringify([lv,plan?.side,plan?.isProjected,state.precision]);
    if(key===state.levelsKey)return;
    state.levelsKey=key;
    for(const line of state.priceLines){try{state.candles.removePriceLine(line);}catch{}}
    state.priceLines=[];
    const projected=plan?.isProjected?" (projeté)":"";
    const add=(price,color,title,width=1,style=L.LineStyle.Dashed,axis=true)=>{
      if(!finite(price))return;
      state.priceLines.push(state.candles.createPriceLine({price:Number(price),color,lineWidth:width,lineStyle:style,axisLabelVisible:axis,title}));
    };
    add(lv.zoneMin,COLORS.zone,"",1,L.LineStyle.Dotted,false);
    add(lv.zoneMax,COLORS.zone,"",1,L.LineStyle.Dotted,false);
    add(lv.sl,COLORS.sl,"SL",2,L.LineStyle.Solid);
    add(lv.entry,COLORS.entry,`ENTRÉE${projected}`,2,L.LineStyle.Solid);
    ["tp1","tp2","tp3","tp4","tp5"].forEach((k,i)=>add(lv[k],COLORS.tp,`TP${i+1}`,k==="tp3"?2:1,k==="tp3"?L.LineStyle.Solid:L.LineStyle.Dashed));
  }

  function signalTime(ctx,data,tf){
    const closedAt=Number(ctx.row?.entry_tf?.closedAt);
    if(!data.length)return null;
    if(!Number.isFinite(closedAt))return toChartTime(data.at(-1).epoch);
    const bucket=Math.floor(closedAt/TF_SECONDS[tf])*TF_SECONDS[tf];
    let candidate=null;
    for(const c of data){if(c.epoch<=bucket)candidate=c;else break;}
    return toChartTime((candidate||data.at(-1)).epoch);
  }

  function syncMarkers(ctx,data,tf){
    const side=ctx.plan?.side||ctx.prediction;
    const time=(side==="BUY"||side==="SELL")?signalTime(ctx,data,tf):null;
    const key=`${side}|${time}|${ctx.plan?.isProjected}`;
    if(key===state.markersKey)return;
    state.markersKey=key;
    if(!time){state.candles.setMarkers([]);return;}
    const label=ctx.plan?.isProjected?`SETUP ${side}`:side;
    state.candles.setMarkers([side==="BUY"
      ?{time,position:"belowBar",color:COLORS.entry,shape:"arrowUp",text:label}
      :{time,position:"aboveBar",color:COLORS.down,shape:"arrowDown",text:label}]);
  }

  function scheduleOverlay(){
    if(state.overlayFrame)return;
    state.overlayFrame=requestAnimationFrame(()=>{state.overlayFrame=0;drawOverlay();});
  }

  // Boîtes risque / rendement façon outil "Position longue / courte".
  function drawOverlay(){
    const {overlay,container,chart,candles,ctx}=state;
    if(!overlay||!chart||!ctx)return;
    const width=container.clientWidth,height=container.clientHeight,dpr=Math.max(1,window.devicePixelRatio||1);
    if(overlay.width!==Math.round(width*dpr)||overlay.height!==Math.round(height*dpr)){
      overlay.width=Math.round(width*dpr);overlay.height=Math.round(height*dpr);
    }
    const g=overlay.getContext("2d");if(!g)return;
    g.setTransform(dpr,0,0,dpr,0,0);g.clearRect(0,0,width,height);
    const plan=ctx.plan;
    if(!plan||!finite(plan.entry)||!finite(plan.sl)||!finite(plan.target))return;
    const scaleWidth=chart.priceScale("right").width()||60;
    const plotRight=width-scaleWidth;
    const yEntry=candles.priceToCoordinate(Number(plan.entry));
    const yStop=candles.priceToCoordinate(Number(plan.sl));
    const yTarget=candles.priceToCoordinate(Number(plan.target));
    if([yEntry,yStop,yTarget].some(v=>v===null||!Number.isFinite(v)))return;
    let x0=state.signalTime!=null?chart.timeScale().timeToCoordinate(state.signalTime):null;
    if(x0===null||!Number.isFinite(x0)||x0>plotRight-40)x0=plotRight*.62;
    // La boîte commence juste après la bougie du signal pour laisser la flèche visible.
    x0=Math.max(0,x0+(chart.timeScale().options().barSpacing||7)*.8);
    const w=Math.max(30,plotRight-x0-4);
    const buy=plan.side==="BUY";
    g.save();g.beginPath();g.rect(0,0,plotRight,height);g.clip();

    const box=(yA,yB,fill,stroke)=>{
      const top=Math.min(yA,yB),h=Math.max(2,Math.abs(yA-yB));
      g.fillStyle=fill;g.fillRect(x0,top,w,h);
      g.strokeStyle=stroke;g.lineWidth=1;g.strokeRect(x0+.5,top+.5,w-1,h-1);
    };
    box(yEntry,yTarget,"rgba(56,232,187,.13)","rgba(56,232,187,.45)");
    box(yEntry,yStop,"rgba(255,95,118,.13)","rgba(255,95,118,.45)");

    const risk=Math.abs(plan.entry-plan.sl),reward=Math.abs(plan.target-plan.entry);
    const rr=risk>0?(reward/risk).toFixed(2):"—";
    const fmt=ctx.fmt||String;
    g.font="700 11px JetBrains Mono, monospace";
    g.textBaseline="middle";
    const label=(text,y,color)=>{
      const tw=g.measureText(text).width+10;
      const tx=Math.max(4,Math.min(x0+6,plotRight-tw-6)),ty=Math.min(height-10,Math.max(10,y));
      g.fillStyle="rgba(7,15,25,.86)";g.fillRect(tx-2,ty-9,tw,18);
      g.fillStyle=color;g.fillText(text,tx+3,ty);
    };
    const targetY=buy?Math.min(yEntry,yTarget):Math.max(yEntry,yTarget);
    const stopY=buy?Math.max(yEntry,yStop):Math.min(yEntry,yStop);
    label(`${plan.side}${plan.isProjected?" projeté":""} · R:R 1:${rr}`,targetY+(buy?13:-13),"#7ff3cf");
    label(`Risque ${fmt(risk)}`,stopY+(buy?-13:13),"#ff9aaa");
    g.restore();
  }

  function updateLegend(point){
    if(!state.legend)return;
    const c=point||state.data.at(-1);
    const fmt=state.ctx?.fmt||String;
    const tf=state.ctx?currentTf(state.ctx):"";
    const ohlc=c?`<span class="tv-ohl">O <b>${fmt(c.open)}</b> H <b>${fmt(c.high)}</b> B <b>${fmt(c.low)}</b></span> C <b class="${c.close>=c.open?"up":"down"}">${fmt(c.close)}</b>`:"Chargement des bougies…";
    state.legend.innerHTML=`<span class="tv-tf">${tf}</span> ${ohlc} <span class="tv-ema"><i style="background:${COLORS.ema20}"></i>EMA20 <i style="background:${COLORS.ema50}"></i>EMA50</span>`;
  }

  /* ---------- rendu principal ---------- */

  function render(ctx){
    if(state.disabled||!lib())return false;
    try{
      state.ctx=ctx;
      if(!mount(ctx))return false;
      const tf=currentTf(ctx);
      renderToolbar(ctx,tf);
      loadHistory(ctx,tf);

      const data=seriesFor(ctx,tf);
      state.data=data;
      const decimals=Math.max(0,Math.min(8,Number(ctx.decimals?.(data.at(-1)?.close||ctx.levels?.entry))||2));
      if(decimals!==state.precision){
        state.precision=decimals;
        state.candles.applyOptions({priceFormat:{type:"price",precision:decimals,minMove:Number((10**-decimals).toFixed(decimals))}});
      }

      const key=`${ctx.market}|${ctx.mode}|${tf}`;
      const points=data.map(c=>({time:toChartTime(c.epoch),open:c.open,high:c.high,low:c.low,close:c.close}));
      const last=points.at(-1);
      const canUpdate=key===state.dataKey&&last&&points.length>=state.lastLength&&points.length-state.lastLength<=1&&last.time>=state.lastTime&&state.lastLength>0;
      if(canUpdate){
        state.candles.update(last);
        const e20=emaPoints(data,20).at(-1),e50=emaPoints(data,50).at(-1);
        if(e20)state.ema20.update(e20);
        if(e50)state.ema50.update(e50);
      }else{
        state.candles.setData(points);
        state.ema20.setData(emaPoints(data,20));
        state.ema50.setData(emaPoints(data,50));
        if(key!==state.dataKey){
          state.markersKey="";
          state.chart.timeScale().scrollToRealTime();
        }
      }
      state.dataKey=key;state.lastLength=points.length;state.lastTime=last?.time||0;

      syncPriceLines(ctx);
      syncMarkers(ctx,data,tf);
      state.signalTime=signalTime(ctx,data,tf);
      updateLegend(null);
      scheduleOverlay();
      return true;
    }catch(error){
      // Sécurité : en cas de problème, on revient à l'ancien graphique canvas.
      console.warn("Sera Chart Engine désactivé:",error);
      state.disabled=true;teardown();
      return false;
    }
  }

  window.SeraChart={render,state,version:"1.0.0"};
})();
