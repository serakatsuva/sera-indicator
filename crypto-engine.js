/* Sera — moteur Swing Crypto (H1/H4/D1). Même fichier dans le navigateur (window.SeraCryptoEngine) et sous Node (scripts/update-crypto.mjs).
   Règle « stricte » : H1, H4 et D1 doivent aller dans le même sens (EMA 20/50 + structure + ADX), l'entrée se fait sur repli H1 (RSI),
   stop derrière le dernier creux/sommet H1, objectifs 1R / 2R / 3R. Le score est un score moteur NON calibré : voir data/crypto-report.json. */
(function(root){
  "use strict";
  const ema=(v,n)=>{const k=2/(n+1);const o=[];let p=v[0];for(let i=0;i<v.length;i++){p=i?v[i]*k+p*(1-k):v[0];o.push(p);}return o;};
  function atr(c,n=14){
    if(c.length<n+2)return 0;
    let s=0;for(let i=c.length-n;i<c.length;i++){const p=c[i-1].close;s+=Math.max(c[i].high-c[i].low,Math.abs(c[i].high-p),Math.abs(c[i].low-p));}
    return s/n;
  }
  function rsi(c,n=14){
    if(c.length<n+2)return 50;
    let g=0,l=0;for(let i=c.length-n;i<c.length;i++){const d=c[i].close-c[i-1].close;if(d>0)g+=d;else l-=d;}
    return l===0?100:100-100/(1+g/l);
  }
  function adx(c,n=14){
    if(c.length<n*2+2)return 0;
    let tr=0,pd=0,md=0;const dx=[];
    const start=c.length-n*2;
    for(let i=start;i<c.length;i++){
      const up=c[i].high-c[i-1].high,dn=c[i-1].low-c[i].low;
      const t=Math.max(c[i].high-c[i].low,Math.abs(c[i].high-c[i-1].close),Math.abs(c[i].low-c[i-1].close));
      tr+=t;pd+=(up>dn&&up>0)?up:0;md+=(dn>up&&dn>0)?dn:0;
      if((i-start+1)%n===0&&tr>0){const a=100*pd/tr,b=100*md/tr;dx.push(100*Math.abs(a-b)/Math.max(1e-9,a+b));tr=pd=md=0;}
    }
    return dx.length?dx.reduce((a,b)=>a+b,0)/dx.length:0;
  }
  function pivots(c,k=3){
    const hi=[],lo=[];
    for(let i=k;i<c.length-k;i++){
      let h=true,l=true;
      for(let j=1;j<=k;j++){if(c[i].high<=c[i-j].high||c[i].high<=c[i+j].high)h=false;if(c[i].low>=c[i-j].low||c[i].low>=c[i+j].low)l=false;}
      if(h)hi.push({i,p:c[i].high});if(l)lo.push({i,p:c[i].low});
    }
    return {hi,lo};
  }
  function trendOf(c){
    if(!c||c.length<60)return null;
    const cl=c.map(x=>x.close),e20=ema(cl,20),e50=ema(cl,50),n=cl.length-1;
    const piv=pivots(c);
    const hh=piv.hi.length>=2&&piv.hi[piv.hi.length-1].p>piv.hi[piv.hi.length-2].p;
    const hl=piv.lo.length>=2&&piv.lo[piv.lo.length-1].p>piv.lo[piv.lo.length-2].p;
    const lh=piv.hi.length>=2&&piv.hi[piv.hi.length-1].p<piv.hi[piv.hi.length-2].p;
    const ll=piv.lo.length>=2&&piv.lo[piv.lo.length-1].p<piv.lo[piv.lo.length-2].p;
    const up=cl[n]>e50[n]&&e20[n]>e50[n]&&e50[n]>e50[n-5];
    const down=cl[n]<e50[n]&&e20[n]<e50[n]&&e50[n]<e50[n-5];
    let dir=0;
    if(up&&(hh||hl))dir=1;else if(down&&(lh||ll))dir=-1;
    return {dir,adx:adx(c),atr:atr(c),rsi:rsi(c),ema20:e20[n],ema50:e50[n],close:cl[n],pivots:piv};
  }
  const pct=(a,b)=>b?100*(a-b)/b:0;
  const strength=a=>a>=30?"forte":a>=20?"modérée":"faible";
  const word=d=>d>0?"haussier":d<0?"baissier":"sans tendance claire";
  /* Lecture détaillée : tendance, force, repli, volatilité, supports/résistances, variation et volume 24 h. */
  function describe(a1,t1,t4,td){
    const px=t1.close,lines=[];
    const near=(t,above)=>{const l=above?t.pivots.hi:t.pivots.lo;const v=l.map(x=>x.p).filter(p=>above?p>px:p<px);return v.length?(above?Math.min(...v):Math.max(...v)):null;};
    const res=near(t4,true)??near(td,true),sup=near(t4,false)??near(td,false);
    lines.push(`D1 ${word(td.dir)} (ADX ${td.adx.toFixed(0)}, tendance ${strength(td.adx)}).`);
    lines.push(`H4 ${word(t4.dir)} (ADX ${t4.adx.toFixed(0)}, tendance ${strength(t4.adx)}).`);
    const r=t1.rsi;
    lines.push(`H1 ${word(t1.dir)} · RSI ${r.toFixed(0)} (${r>70?"surachat":r<30?"survente":r>=55?"momentum haussier":r<=45?"momentum baissier":"neutre"}).`);
    lines.push(`Volatilité : ATR H1 = ${(100*t1.atr/px).toFixed(2)} % du prix, ATR H4 = ${(100*t4.atr/px).toFixed(2)} %.`);
    if(res)lines.push(`Résistance proche ${res.toPrecision(6)} (${pct(res,px)>=0?"+":""}${pct(res,px).toFixed(2)} %).`);
    if(sup)lines.push(`Support proche ${sup.toPrecision(6)} (${pct(sup,px).toFixed(2)} %).`);
    if(a1.length>25){const c24=a1[a1.length-25].close;lines.push(`Variation 24 h : ${pct(px,c24)>=0?"+":""}${pct(px,c24).toFixed(2)} %.`);}
    const vols=a1.map(x=>x.volume).filter(v=>Number.isFinite(v));
    if(vols.length>=200){const last=vols.slice(-24).reduce((x,y)=>x+y,0),prev=vols.slice(-24*8,-24).reduce((x,y)=>x+y,0)/7;
      if(prev>0)lines.push(`Volume 24 h = ${(last/prev).toFixed(1)} × la moyenne des 7 jours précédents (${last/prev>1.5?"forte activité":last/prev<0.6?"faible activité":"activité normale"}).`);}
    return {lines,support:sup,resistance:res};
  }
  /* h1/h4/d1 : tableaux de bougies {open,high,low,close} du plus ancien au plus récent (la dernière bougie peut être en cours : on la retire). */
  function analyze(h1,h4,d1,opts={}){
    const o=Object.assign({strict:true,minAdxD1:18,minAdxH4:15,minRR:2},opts);
    const closed=a=>a&&a.length?a.slice(0,-1):a;
    const a1=closed(h1),a4=closed(h4),ad=closed(d1);
    const t1=trendOf(a1),t4=trendOf(a4),td=trendOf(ad);
    const out={verdict:"ATTENDRE",side:"NEUTRE",score:0,reason:"",tf:{h1:t1?.dir??0,h4:t4?.dir??0,d1:td?.dir??0}};
    if(!t1||!t4||!td){out.reason="Historique insuffisant";return out;}
    out.detail=describe(a1,t1,t4,td);
    const dirs=[t1.dir,t4.dir,td.dir];
    const aligned=o.strict?dirs.every(d=>d!==0&&d===dirs[0]):(t4.dir!==0&&t4.dir===td.dir);
    if(!aligned){out.reason=o.strict?"H1, H4 et D1 ne vont pas dans le même sens":"H4 et D1 ne vont pas dans le même sens";return out;}
    const dir=td.dir;
    if(td.adx<o.minAdxD1||t4.adx<o.minAdxH4){out.reason="Tendance trop faible (ADX)";return out;}
    const r=t1.rsi;
    const pulled=dir>0?(r>=35&&r<=55):(r>=45&&r<=65);
    if(!pulled){out.reason=dir>0?"Pas de repli H1 : attendre un RSI H1 entre 35 et 55":"Pas de rebond H1 : attendre un RSI H1 entre 45 et 65";out.side=dir>0?"BUY":"SELL";return out;}
    const last=a1[a1.length-1],px=last.close,a=t1.atr;
    const piv=t1.pivots;
    let sl;
    if(dir>0){const lo=piv.lo.length?piv.lo[piv.lo.length-1].p:px-2*a;sl=Math.min(lo,px-1.5*a)-0.2*a;}
    else{const hi=piv.hi.length?piv.hi[piv.hi.length-1].p:px+2*a;sl=Math.max(hi,px+1.5*a)+0.2*a;}
    const risk=Math.abs(px-sl);
    if(!(risk>0)){out.reason="Stop invalide";return out;}
    const tp=k=>px+dir*risk*k;
    const rr=2;
    if(rr<o.minRR){out.reason="R:R insuffisant";return out;}
    const score=Math.round(Math.min(95,50+Math.min(20,td.adx-18)+Math.min(10,t4.adx-15)+(o.strict?10:0)));
    return Object.assign(out,{verdict:dir>0?"BUY":"SELL",side:dir>0?"BUY":"SELL",score,reason:"H1, H4 et D1 alignés, repli H1 validé",
      entry:px,sl,tp1:tp(1),tp2:tp(2),tp3:tp(3),risk,rr,atr:a,rsi:r,adxD1:td.adx,adxH4:t4.adx});
  }
  function aggregate(h1,hours){
    const out=[];
    for(let i=0;i+hours<=h1.length;i+=hours){
      const g=h1.slice(i,i+hours);
      out.push({time:g[0].time,open:g[0].open,high:Math.max(...g.map(x=>x.high)),low:Math.min(...g.map(x=>x.low)),close:g[g.length-1].close});
    }
    return out;
  }
  const api={analyze,trendOf,aggregate,atr,rsi,adx};
  if(typeof module!=="undefined"&&module.exports)module.exports=api;else root.SeraCryptoEngine=api;
})(typeof window!=="undefined"?window:globalThis);
