// Sera Indicator — stratégie mesurée « sens de la dérive » (Drift Playbook).
// Lit data/playbook-signals.json (signaux en cours, publié par le moteur) et data/playbook-stats.json (mesure sur 1 an).
(function(){
  "use strict";
  const RAW="https://raw.githubusercontent.com/serakatsuva/sera-indicator/main/data/";
  const $=id=>document.getElementById(id);
  const esc=v=>String(v??"").replace(/[&<>'"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c]));
  const pct=v=>Number.isFinite(Number(v))?`${Number(v).toLocaleString("fr-FR",{maximumFractionDigits:1})} %`:"—";
  const rr=v=>Number.isFinite(Number(v))?`${Number(v)>=0?"+":""}${Number(v).toLocaleString("fr-FR",{maximumFractionDigits:2})} R`:"—";
  const price=v=>{const n=Number(v);if(!Number.isFinite(n)||n<=0)return "—";return n.toLocaleString("fr-FR",{maximumFractionDigits:n>=1000?2:n>=10?3:5});};
  let signals=null,stats=null,known=null;

  async function load(name){
    for(const url of [`${RAW}${name}?t=${Date.now()}`,`./data/${name}?t=${Date.now()}`]){
      try{const r=await fetch(url,{cache:"no-store"});if(r.ok)return await r.json();}catch(e){/* source suivante */}
    }
    return null;
  }

  function groupTile(key,g){
    const a=g.all||{},t=g.test||{},pr=stats?.precision?.groups?.[key]?.all;
    return `<article class="pb-tile ${key}" data-pb-group="${esc(key)}">
      <h3>${esc(g.label)}</h3>
      <div class="pb-big">${pct(a.tp1_rate)}<small>des trades atteignent TP1</small></div>
      <ul>
        <li><b>${pct(a.losing_rate)}</b> de trades perdants</li>
        <li><b>${rr(a.expectancy_r)}</b> en moyenne par trade (1 R = le risque)</li>
        <li><b>${esc(a.trades)}</b> trades · <b>${esc(a.positive_months)}/${esc(a.months)}</b> mois gagnants</li>
        <li>Hors échantillon (30 % les plus récents) : TP1 <b>${pct(t.tp1_rate)}</b>, ${rr(t.expectancy_r)}</li>
      </ul>
      ${pr?`<div class="pb-precision" data-pb-precision="${esc(key)}"><b>Mode précision SMC</b> (réglage par défaut des EA) : TP1 <b>${pct(pr.tp1_rate)}</b> · perdants ${pct(pr.losing_rate)} · ${rr(pr.expectancy_r)} / trade · ${esc(pr.trades)} trades</div>`:""}
    </article>`;
  }

  function signalCard(m){
    const side=m.final_verdict,cls=side==="BUY"?"buy":"sell",lv=m.levels||{},me=m.measured||{};
    return `<article class="wt-card ${cls} pb-signal" data-pb-market="${esc(m.market)}">
      <div class="wt-top"><div><h3>${esc(m.market)}</h3><p>${esc(m.label)} · DÉRIVE H1</p></div><span class="wt-signal ${cls}">${esc(side)}</span></div>
      <div class="wt-levels">
        <div><small>Entrée</small><strong>${price(lv.entry)}</strong></div>
        <div class="danger"><small>SL</small><strong>${price(lv.sl)}</strong></div>
        <div><small>TP1</small><strong>${price(lv.tp1)}</strong></div>
        <div><small>TP2</small><strong>${price(lv.tp2)}</strong></div>
        <div><small>TP3</small><strong>${price(lv.tp3)}</strong></div>
      </div>
      <div class="pb-sweep ${m.liquidity_sweep?"ok":"no"}">${m.liquidity_sweep?"✓ Balayage de liquidité (SMC) : pris par les EA en mode précision":"Sans balayage de liquidité : ignoré par les EA en mode précision"}</div>
      <div class="wt-meta"><span>Mesuré sur cet indice : TP1 ${pct(me.tp1_rate)}</span><span>${rr(me.expectancy_r)} / trade</span><span>RSI ${esc(m.rsi)}</span></div>
      <button class="wt-speak" type="button" data-pb-speak="${esc(m.market)}">🔊 Lire</button>
    </article>`;
  }

  function render(){
    const tiles=$("pbGroups"),list=$("pbSignals"),note=$("pbNotice"),base=$("pbBaseline");
    if(!tiles||!list)return;
    const groups=stats?.groups||{};
    tiles.innerHTML=Object.keys(groups).length?Object.entries(groups).map(([k,g])=>groupTile(k,g)).join(""):`<p class="wt-empty">Mesures indisponibles.</p>`;
    const b=stats?.baseline;
    if(base)base.innerHTML=b?`Pour comparer, sur la même année : ${[b.swing_detected,b.swing_confirmed,b.day_confirmed].filter(Boolean)
      .map(x=>`${esc(x.label)} → TP1 ${pct(x.tp1_rate)} (${x.total_r>=0?"+":""}${esc(x.total_r)} R sur ${esc(x.trades)} trades)`).join(" · ")}.`:"";
    const rows=(signals?.markets||[]).filter(m=>m.final_verdict==="BUY"||m.final_verdict==="SELL");
    const watched=(signals?.markets||[]).length;
    if(note){
      note.className=`notice ${rows.length?"success":"loading"}`;
      note.textContent=signals?(rows.length?`${rows.length} signal(s) « dérive » en cours sur ${watched} indices suivis.`
        :`Aucun repli en cours : ${watched} indices suivis (Boom, Crash, Bull/Bear Market). Le signal apparaît dès qu’un repli se forme dans le sens de la dérive.`)
        :"Signaux de la stratégie en attente de la prochaine analyse du moteur.";
    }
    list.innerHTML=rows.map(signalCard).join("");
    const period=stats?.period;
    if($("pbSmc"))$("pbSmc").textContent=stats?.smc_tested||"";
    if($("pbPeriod"))$("pbPeriod").textContent=period?`Mesuré du ${period.from} au ${period.to} sur l’historique réel Deriv, avec la gestion de l’EA (50 % à TP1 puis point mort).`:"";
  }

  function voiceSignal(m){
    return {broker:"Deriv",market:m.market,mode:"swing",verdict:m.final_verdict,confidence:m.final_confidence,
      entry:m.levels?.entry,sl:m.levels?.sl,tp1:m.levels?.tp1,tp2:m.levels?.tp2,tp3:m.levels?.tp3};
  }

  function announce(){
    const now=(signals?.markets||[]).filter(m=>m.final_verdict==="BUY"||m.final_verdict==="SELL");
    const keys=new Set(now.map(m=>`${m.id}|${m.final_verdict}`));
    if(known&&window.SeraVoice&&window.SeraVoice.isOn()){
      const fresh=now.filter(m=>!known.has(`${m.id}|${m.final_verdict}`));
      if(fresh.length)window.SeraVoice.announce(fresh.map(voiceSignal));
    }
    known=keys;
  }

  async function refresh(){
    const [s,st]=await Promise.all([load("playbook-signals.json"),stats?Promise.resolve(stats):load("playbook-stats.json")]);
    if(s)signals=s;
    if(st)stats=st;
    render();
    announce();
  }

  function start(){
    if(!$("playbook"))return;
    $("pbSignals")?.addEventListener("click",e=>{
      const b=e.target.closest("[data-pb-speak]");if(!b||!window.SeraVoice)return;
      const m=(signals?.markets||[]).find(x=>x.market===b.dataset.pbSpeak);
      if(m)window.SeraVoice.speak(window.SeraVoice.signalText(voiceSignal(m)),true);
    });
    refresh();
    setInterval(refresh,60000);
  }
  window.SeraPlaybook={refresh,signals:()=>(signals?.markets||[]).filter(m=>m.final_verdict==="BUY"||m.final_verdict==="SELL")};
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start);else start();
})();
