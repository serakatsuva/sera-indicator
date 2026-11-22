// Sera Indicator — graphique d'une position anticipée (boîte risque / objectif, façon outil TradingView).
// Bougies : historique public Deriv (WebSocket). Dessin : boîte rouge (entrée→SL), boîte grise (entrée→TP1),
// TP2 en pointillé, flèche de trajet anticipée, niveaux étiquetés par unité de temps (invalidation / niveau clé).
(function(){
  "use strict";
  const WS_URL="wss://api.derivws.com/trading/v1/options/ws/public?app_id=1089";
  const TF_SECONDS={M15:900,H1:3600,H4:14400,D1:86400};
  const FUTURE_BARS=38;
  const esc=v=>String(v??"").replace(/[&<>'"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]));
  const fmt=v=>{const n=Number(v);if(!Number.isFinite(n))return "—";return n.toLocaleString("fr-FR",{minimumFractionDigits:2,maximumFractionDigits:Math.abs(n)>=1000?2:Math.abs(n)>=10?3:5});};
  let modal=null,chart=null,series=null,overlay=null,current=null,data=[],ro=null;

  function tfs(p){
    const parts=String(p.tf||"").split("/");
    const high=parts.length>1?parts[0]:null,low=parts.length>1?parts[1]:parts[0];
    return {high,low:TF_SECONDS[low]?low:"H1"};
  }

  function fetchCandles(symbol,tf){
    return new Promise((resolve,reject)=>{
      let ws;try{ws=new WebSocket(WS_URL);}catch(e){return reject(e);}
      const timer=setTimeout(()=>{try{ws.close();}catch(e){}reject(new Error("délai dépassé"));},12000);
      ws.addEventListener("open",()=>ws.send(JSON.stringify({ticks_history:symbol,style:"candles",granularity:TF_SECONDS[tf],
        count:220,end:"latest",adjust_start_time:1,req_id:9901})));
      ws.addEventListener("message",ev=>{
        let m;try{m=JSON.parse(ev.data);}catch(e){return;}
        if(Array.isArray(m.candles)){clearTimeout(timer);try{ws.close();}catch(e){}
          resolve(m.candles.map(c=>({time:Number(c.epoch),open:+c.open,high:+c.high,low:+c.low,close:+c.close}))
            .filter(c=>[c.time,c.open,c.high,c.low,c.close].every(Number.isFinite)));}
        else if(m.error){clearTimeout(timer);try{ws.close();}catch(e){}reject(new Error(m.error.message||"erreur"));}
      });
      ws.addEventListener("error",()=>{clearTimeout(timer);reject(new Error("connexion impossible"));});
    });
  }

  function ensureModal(){
    if(modal)return modal;
    modal=document.createElement("div");
    modal.className="pos-modal";modal.hidden=true;
    modal.innerHTML=`<div class="pos-modal-backdrop" data-pos-close></div>
      <div class="pos-modal-card" role="dialog" aria-modal="true" aria-labelledby="posChartTitle">
        <div class="pos-modal-head"><div><strong id="posChartTitle"></strong><small id="posChartSub"></small></div>
          <button type="button" class="pos-modal-close" data-pos-close aria-label="Fermer">✕</button></div>
        <div class="pos-chart-host"><div id="posChart" class="pos-chart"></div><div id="posOverlay" class="pos-overlay"></div></div>
        <p class="pos-chart-note" id="posChartNote"></p>
      </div>`;
    document.body.appendChild(modal);
    modal.addEventListener("click",e=>{if(e.target.closest("[data-pos-close]"))close();});
    document.addEventListener("keydown",e=>{if(e.key==="Escape"&&!modal.hidden)close();});
    return modal;
  }

  function close(){
    if(!modal)return;
    modal.hidden=true;document.body.classList.remove("pos-modal-open");
    if(ro){ro.disconnect();ro=null;}
    if(chart){try{chart.remove();}catch(e){}chart=null;series=null;}
    current=null;
  }

  // Dessin des boîtes : positions en pixels recalculées à chaque changement d'échelle.
  function draw(){
    if(!chart||!series||!current||!data.length)return;
    const {p}=current,ts=chart.timeScale();
    const lastIdx=data.length-1;
    const x0=ts.logicalToCoordinate(lastIdx),x1=ts.logicalToCoordinate(lastIdx+FUTURE_BARS);
    const y=v=>series.priceToCoordinate(v);
    const yE=y(p.entry),yS=y(p.sl),yT1=y(p.tp1),yT2=y(p.tp2);
    if([x0,x1,yE,yS,yT1].some(v=>v===null||!Number.isFinite(v))){overlay.innerHTML="";return;}
    const left=Math.min(x0,x1),w=Math.abs(x1-x0);
    const box=(ya,yb,cls)=>`<div class="pos-box ${cls}" style="left:${left}px;width:${w}px;top:${Math.min(ya,yb)}px;height:${Math.abs(ya-yb)}px"></div>`;
    const line=(yy,cls,label,from=left,to=left+w)=>`<div class="pos-hline ${cls}" style="left:${from}px;width:${to-from}px;top:${yy}px"><span>${esc(label)}</span></div>`;
    const {high,low}=tfs(p);
    const zoneTop=y(p.zone_max),zoneBot=y(p.zone_min);
    let html=box(yE,yS,"risk")+box(yE,yT1,"reward");
    if(Number.isFinite(yT2)&&Math.abs(yT2-yT1)>1)html+=`<div class="pos-hline tp2" style="left:${left}px;width:${w}px;top:${yT2}px"><span>TP2</span></div>`;
    html+=line(yE,"entry","Entrée");
    // niveaux d'origine : bords de la zone (niveau clé de la grande unité, invalidation de la petite unité)
    const keyY=p.side==="BUY"?zoneBot:zoneTop;
    if(Number.isFinite(zoneTop)&&Number.isFinite(zoneBot)){
      html+=line(zoneTop,"key",`${high?high+" niveau clé":"niveau clé"} ${p.side==="BUY"?"s":"r"}`,Math.max(0,left-w*0.9),left+w*0.55);
      html+=line(zoneBot,"inv",`${low} invalidation ${p.side==="BUY"?"x":"x"}`,Math.max(0,left-w*0.9),left+w*0.55);
    }
    // flèche du trajet anticipé : retest de l'entrée puis objectif
    const xm=left+w*0.18,xe=left+w*0.72;
    html+=`<svg class="pos-arrow" width="${Math.max(1,left+w+20)}" height="${overlay.clientHeight||1}">
      <defs><marker id="posHead" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8" fill="none" stroke="#e8edf5" stroke-width="1.4"/></marker></defs>
      <polyline points="${xm},${yE} ${xe},${yT1}" fill="none" stroke="#e8edf5" stroke-width="1.4" stroke-dasharray="5 4" marker-end="url(#posHead)"/></svg>`;
    overlay.innerHTML=html;
  }

  function addLevels(){
    const {p}=current,L=window.LightweightCharts;
    const pl=(price,color,title,style)=>series.createPriceLine({price:Number(price),color,lineWidth:1,lineStyle:style,axisLabelVisible:true,title});
    pl(p.entry,"#8a93a6","Entrée",L.LineStyle.Dotted);
    pl(p.sl,"#ff5f76","SL",L.LineStyle.Dotted);
    pl(p.tp1,"#38e8bb","TP1",L.LineStyle.Dotted);
    if(Number.isFinite(Number(p.tp2)))pl(p.tp2,"#6fb3a3","TP2",L.LineStyle.Dotted);
  }

  async function open(m,p){
    const L=window.LightweightCharts;
    ensureModal();
    current={m,p};
    modal.hidden=false;document.body.classList.add("pos-modal-open");
    const {high,low}=tfs(p);
    modal.querySelector("#posChartTitle").textContent=`${m.market} · ${p.side} · ${p.setup}`;
    modal.querySelector("#posChartSub").textContent=` ${high?high+" → ":""}${low} · qualité ${p.quality}/95`;
    const note=modal.querySelector("#posChartNote");
    note.textContent="Chargement des bougies…";
    overlay=modal.querySelector("#posOverlay");overlay.innerHTML="";
    if(!L||typeof L.createChart!=="function"){note.textContent="Bibliothèque de graphique indisponible.";return;}
    let rows;
    try{rows=await fetchCandles(m.symbol,low);}catch(e){
      if(current&&current.p===p)note.textContent=`Bougies indisponibles (${e.message}). Les niveaux restent : entrée ${fmt(p.entry)}, SL ${fmt(p.sl)}, TP1 ${fmt(p.tp1)}.`;
      return;
    }
    if(!current||current.p!==p||modal.hidden)return;
    data=rows;
    const host=modal.querySelector("#posChart");
    chart=L.createChart(host,{autoSize:true,
      layout:{background:{type:L.ColorType.Solid,color:"transparent"},textColor:"#8fa3b8",fontSize:11,fontFamily:"JetBrains Mono, monospace"},
      grid:{vertLines:{color:"rgba(255,255,255,.035)"},horzLines:{color:"rgba(255,255,255,.05)"}},
      rightPriceScale:{borderColor:"rgba(255,255,255,.09)",scaleMargins:{top:.1,bottom:.1}},
      timeScale:{borderColor:"rgba(255,255,255,.09)",timeVisible:true,secondsVisible:false,rightOffset:FUTURE_BARS+4,barSpacing:7,minBarSpacing:2},
      localization:{locale:"fr-FR"}});
    series=chart.addCandlestickSeries({upColor:"#38e8bb",downColor:"#ff5f76",wickUpColor:"#38e8bb",wickDownColor:"#ff5f76",borderVisible:false,
      autoscaleInfoProvider:orig=>{const b=orig();if(!b)return b;
        const lo=Math.min(b.priceRange.minValue,p.sl,p.tp1),hi=Math.max(b.priceRange.maxValue,p.sl,p.tp1);
        return {...b,priceRange:{minValue:lo,maxValue:hi}};}});
    series.setData(rows);
    addLevels();
    chart.timeScale().scrollToPosition(FUTURE_BARS+4,false);
    note.textContent="Anticipation, pas un ordre : la boîte rouge est le risque (entrée → SL), la grise l’objectif (entrée → TP1). Qualité = score heuristique.";
    const redraw=()=>requestAnimationFrame(draw);
    chart.timeScale().subscribeVisibleLogicalRangeChange(redraw);
    chart.subscribeCrosshairMove(redraw);
    ro=new ResizeObserver(redraw);ro.observe(host);
    redraw();setTimeout(draw,150);
  }

  window.SeraPositionChart={open,close};
})();
