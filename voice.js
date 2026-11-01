// Sera Indicator — lecture vocale des signaux (synthèse vocale du navigateur, en français).
// Bouton 🔊 en haut : active les annonces des nouveaux signaux Deriv et Weltrade ; "Lire" lit les signaux en cours.
(function(){
  "use strict";
  const KEY="seraVoiceOn";
  const EA_FEED_RAW="https://raw.githubusercontent.com/serakatsuva/sera-indicator/main/data/ea-signals.json";
  const EA_FEED_LOCAL="./data/ea-signals.json";
  const synth=window.speechSynthesis||null;
  let on=false;
  try{on=localStorage.getItem(KEY)==="1";}catch(e){on=false;}
  let knownDeriv=null;

  const $=id=>document.getElementById(id);

  function frNumber(value){
    const n=Number(value);
    if(!Number.isFinite(n)||n<=0)return "";
    const digits=n>=1000?2:n>=10?3:5;
    return n.toLocaleString("fr-FR",{maximumFractionDigits:digits});
  }

  function frenchVoice(){
    if(!synth)return null;
    const voices=synth.getVoices()||[];
    return voices.find(v=>/^fr(-|_)FR/i.test(v.lang))||voices.find(v=>/^fr/i.test(v.lang))||null;
  }

  function speak(text,interrupt){
    if(!synth||!text)return false;
    if(interrupt)synth.cancel();
    const u=new SpeechSynthesisUtterance(text);
    u.lang="fr-FR";
    const v=frenchVoice();
    if(v)u.voice=v;
    u.rate=1;
    synth.speak(u);
    return true;
  }

  const sideWord=v=>v==="BUY"?"achat":v==="SELL"?"vente":"attente";

  // {broker, market, mode, verdict, confidence, entry, sl, tp1, tp2, tp3}
  function signalText(s){
    const parts=[`${s.broker}. Signal ${s.mode==="day"?"Day":"Swing"}. ${s.market}. ${sideWord(s.verdict)}.`];
    if(Number(s.confidence)>0)parts.push(`Confiance ${Math.round(Number(s.confidence))} pour cent.`);
    if(frNumber(s.entry))parts.push(`Entrée ${frNumber(s.entry)}.`);
    if(frNumber(s.sl))parts.push(`Stop loss ${frNumber(s.sl)}.`);
    ["tp1","tp2","tp3"].forEach((k,i)=>{if(frNumber(s[k]))parts.push(`Objectif ${i+1} : ${frNumber(s[k])}.`);});
    return parts.join(" ");
  }

  function announce(list){
    if(!on||!list||!list.length)return;
    speak((list.length>1?`${list.length} nouveaux signaux. `:"Nouveau signal. ")+list.map(signalText).join(" "),false);
  }

  function derivSignals(feed){
    return (feed?.markets||[])
      .filter(m=>(m.final_verdict==="BUY"||m.final_verdict==="SELL")&&m.levels)
      .map(m=>({id:m.id,broker:"Deriv",market:m.market,mode:m.mode,verdict:m.final_verdict,confidence:m.final_confidence,
                entry:m.levels.entry,sl:m.levels.sl,tp1:m.levels.tp1,tp2:m.levels.tp2,tp3:m.levels.tp3}));
  }

  async function loadDerivFeed(){
    for(const url of [`${EA_FEED_RAW}?t=${Date.now()}`,`${EA_FEED_LOCAL}?t=${Date.now()}`]){
      try{const r=await fetch(url,{cache:"no-store"});if(r.ok)return await r.json();}catch(e){/* source suivante */}
    }
    return null;
  }

  let lastDeriv=[];
  async function watchDeriv(){
    const feed=await loadDerivFeed();
    if(!feed)return;
    lastDeriv=derivSignals(feed);
    const now=new Set(lastDeriv.map(s=>`${s.id}|${s.verdict}`));
    if(knownDeriv)announce(lastDeriv.filter(s=>!knownDeriv.has(`${s.id}|${s.verdict}`)));
    knownDeriv=now;
  }

  function readAll(){
    const all=[...lastDeriv,...(window.SeraWeltrade?window.SeraWeltrade.signals():[])];
    if(!all.length){speak("Aucun signal Deriv ni Weltrade en cours pour le moment.",true);return;}
    speak(`${all.length} signal${all.length>1?"s":""} en cours. `+all.map(signalText).join(" "),true);
  }

  // Analyse affichée dans la fenêtre de détail Deriv (variables globales de app.js).
  function readSelectedDeriv(){
    try{
      /* global payload, selected, selectedMode */
      const rows=(typeof payload!=="undefined"&&payload&&Array.isArray(payload.markets))?payload.markets:[];
      const row=rows.find(r=>r.market===selected&&r.mode===selectedMode)||rows.find(r=>r.market===selected);
      if(!row){speak("Analyse indisponible pour le moment.",true);return;}
      const v=row.final_verdict;
      if(v==="BUY"||v==="SELL"){
        const lv=row.levels||{};
        speak(signalText({broker:"Deriv",market:row.market,mode:row.mode,verdict:v,confidence:row.final_confidence,entry:lv.entry,sl:lv.sl,tp1:lv.tp1,tp2:lv.tp2,tp3:lv.tp3}),true);
      }else{
        const c=Math.round(Number(row?.decision_engine?.condition_pass_percent)||0);
        const sc=Math.round(Number(row?.decision_engine?.score)||0);
        speak(`Deriv. ${row.market}. ${row.mode==="day"?"Day":"Swing"}. Pas de signal pour le moment : attendre. Score ${sc}, conditions ${c} pour cent.`,true);
      }
    }catch(e){speak("Analyse indisponible pour le moment.",true);}
  }

  function updateButton(){
    const btn=$("voiceToggle");
    if(!btn)return;
    btn.classList.toggle("on",on);
    btn.setAttribute("aria-pressed",on?"true":"false");
    btn.textContent=on?"🔊 Voix ON":"🔈 Voix";
    btn.title=synth?(on?"Les nouveaux signaux sont annoncés à voix haute":"Activer l’annonce vocale des signaux"):"La synthèse vocale n’est pas disponible sur ce navigateur";
    if(!synth)btn.disabled=true;
  }

  function start(){
    const btn=$("voiceToggle");
    btn?.addEventListener("click",()=>{
      on=!on;
      try{localStorage.setItem(KEY,on?"1":"0");}catch(e){/* préférence non mémorisée */}
      updateButton();
      if(on)speak("Lecture vocale activée. Les nouveaux signaux Deriv et Weltrade seront annoncés.",true);
      else if(synth)synth.cancel();
    });
    $("voiceReadAll")?.addEventListener("click",readAll);
    $("speakSelected")?.addEventListener("click",readSelectedDeriv);
    if(synth&&typeof synth.addEventListener==="function")synth.addEventListener("voiceschanged",()=>{});
    updateButton();
    watchDeriv();
    setInterval(watchDeriv,60000);
  }

  window.SeraVoice={speak,signalText,announce,frNumber,isOn:()=>on,readAll};
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start);else start();
})();
