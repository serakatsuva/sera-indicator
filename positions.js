// Sera Indicator — page « Positions » : uniquement les anticipations APA (price action) et MSNR (OCL + SNR).
// Lit data/positions-signals.json. Anticipations, pas des ordres : la qualité est un score heuristique.
(function(){
  "use strict";
  const RAW="https://raw.githubusercontent.com/serakatsuva/sera-indicator/main/data/";
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??"").replace(/[&<>'"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]));
  const num=v=>{const n=Number(v);return Number.isFinite(n)?n:null;};
  const price=v=>{const n=num(v);if(n===null)return "—";return n.toLocaleString("fr-FR",{maximumFractionDigits:Math.abs(n)>=1000?2:Math.abs(n)>=10?3:5});};
  const STATUS={IN_ZONE:"Dans la zone",WAIT_RETEST:"Attendre le retest",ARMED:"Armée (déclencheur)"};
  const state={data:null,market:"",method:"",side:""};

  async function load(){
    for(const url of [`${RAW}positions-signals.json?t=${Date.now()}`,`./data/positions-signals.json?t=${Date.now()}`]){
      try{const r=await fetch(url,{cache:"no-store"});if(r.ok)return await r.json();}catch(e){/* source suivante */}
    }
    return null;
  }

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

  function card(m,p){
    const cls=p.side==="BUY"?"buy":"sell";
    const q=Math.max(0,Math.min(95,Number(p.quality)||0));
    const tags=[p.aligned?"aligné sur la structure":"contre / hors structure",p.liquidity_swept?"liquidité prise":"",p.ocl_double?"OCL double":""].filter(Boolean);
    return `<article class="wt-card ${cls} pos-card" data-pos-market="${esc(m.market)}">
      <div class="wt-top"><div><h3>${esc(m.market)}</h3><p>${esc(p.setup)} · ${esc(p.tf)}</p></div><span class="wt-signal ${cls}">${esc(p.side)}</span></div>
      <div class="pos-quality" title="Score heuristique, pas une probabilité de gain"><i style="width:${q/0.95}%"></i><span>Qualité ${q}/95</span></div>
      <div class="wt-levels">
        <div><small>${esc(p.order==="STOP"?"Entrée (stop)":"Entrée (limite)")}</small><strong>${price(p.entry)}</strong></div>
        <div class="danger"><small>SL</small><strong>${price(p.sl)}</strong></div>
        <div><small>TP1</small><strong>${price(p.tp1)}</strong></div>
        <div><small>TP2</small><strong>${price(p.tp2)}</strong></div>
      </div>
      <div class="wt-meta"><span>${esc(STATUS[p.status]||p.status)}</span><span>R:R ${esc(p.rr1)} / ${esc(p.rr2)}</span><span>${esc(p.method)}</span></div>
      <p class="pos-note">${esc(tags.join(" · "))}${live(p,m.price)?` — ${esc(live(p,m.price))}`:""}</p>
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
        items.push({m,p});
      }
    }
    items.sort((a,b)=>b.p.quality-a.p.quality);
    list.innerHTML=items.length?items.map(x=>card(x.m,x.p)).join(""):`<p class="wt-empty">Aucune position anticipée avec ces filtres.</p>`;
    if(note){note.className="notice";note.textContent=`${items.length} position(s) affichée(s) · mise à jour ${d.updated_at?new Date(d.updated_at).toLocaleString("fr-FR"):"—"} · ${d.disclaimer||""}`;}
  }

  function bind(){
    for(const [id,key] of [["posMarket","market"],["posMethod","method"],["posSide","side"]]){
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
    setInterval(async()=>{const d=await load();if(d){state.data=d;render();}},120000);
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",init);else init();
})();
