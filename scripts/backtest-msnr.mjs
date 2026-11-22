// Mesure des positions MSNR (scripts/msnr-engine.mjs, le code utilisé en direct) sur l'historique Deriv.
// Entrée : ordre limite au prix d'entrée de la position (annulé si le SL est touché avant), sortie complète au TP1 ou au SL,
// 10 jours maximum, SL prioritaire si une bougie touche les deux. Résultats par critère, avec découpe 70 % / 30 % (hors échantillon).
// Usage : node scripts/backtest-msnr.mjs history.json.gz [--step 4] [--json out.json] [--min-quality N]
import {gunzipSync} from 'node:zlib';
import {readFileSync,writeFileSync} from 'node:fs';
import {msnrPositions} from './msnr-engine.mjs';
import {positionPhase} from './position-phase.mjs';
import {driftGroup} from './position-reliability.mjs';
import {aggregateCandles} from './update-signals.mjs';

const arg=(n,d)=>{const i=process.argv.indexOf(n);return i>0?process.argv[i+1]:d;};
const file=process.argv[2]||'/tmp/hist/deriv-history.json.gz';
const STEP=Number(arg('--step',4)),OUT=arg('--json',''),STATS=arg('--out',''),WINDOW=400,FILL_BARS=48,MAXHOLD=10*86400;
const raw=JSON.parse(gunzipSync(readFileSync(file)).toString());
const rows=a=>(a||[]).map(([epoch,open,high,low,close])=>({epoch,open,high,low,close}));
// bougies entièrement fermées à l'instant t (epoch + durée <= t) : pas de regard vers le futur
const upTo=(c,t,sec)=>{let lo=0,hi=c.length;while(lo<hi){const m=(lo+hi)>>1;if(c[m].epoch+sec<=t)lo=m+1;else hi=m;}return c.slice(0,lo);};

function simulate(p,path,from,fillBars=FILL_BARS){
  const d=p.side==='BUY'?1:-1,risk=Math.abs(p.entry-p.sl);
  let filled=-1;
  for(let j=from;j<Math.min(path.length,from+fillBars);j++){
    const c=path[j];
    if((d>0?c.low<=p.sl:c.high>=p.sl))return null;               // SL avant l'entrée : annulée
    if((d>0?c.low<=p.entry:c.high>=p.entry)){filled=j;break;}
  }
  if(filled<0)return null;
  const t0=path[filled].epoch;
  for(let j=filled;j<path.length;j++){
    const c=path[j];
    if(c.epoch-t0>MAXHOLD)return {r:d*(c.open-p.entry)/risk,exit:'TIME'};
    const hitSL=d>0?c.low<=p.sl:c.high>=p.sl,hitTP=d>0?c.high>=p.tp1:c.low<=p.tp1;
    if(hitSL)return {r:-1,exit:'SL'};                                  // SL prioritaire
    // bougie d'entrée : l'ordre des touches est inconnu, le TP1 ne compte qu'à partir de la bougie suivante
    if(hitTP&&j>filled)return {r:Math.abs(p.tp1-p.entry)/risk,exit:'TP1'};
  }
  return null;
}

const trades=[];
let t0All=Infinity,t1All=0;
for(const m of raw.markets){
  const H1=rows(m.H1),D1=rows(m.D1),M15=rows(m.M15);
  if(H1.length<WINDOW+100)continue;
  const H4=aggregateCandles(H1,14400),W1=aggregateCandles(D1,604800,259200);
  const lastSeen=new Map();
  for(let i=WINDOW;i<H1.length-60;i+=STEP){
    const t=H1[i].epoch+3600;
    const series={W1:upTo(W1,t,604800).slice(-120),D1:upTo(D1,t,86400).slice(-220),H4:upTo(H4,t,14400).slice(-300),H1:H1.slice(Math.max(0,i-300),i+1),
      M15:upTo(M15,t,900).slice(-300)};
    const price=H1[i].close;
    let found;try{found=msnrPositions(series);}catch{continue;}
    for(const p of found){
      const phase=positionPhase(p,price);
      if(phase!=='NOW'&&phase!=='PREP')continue;
      const risk=Math.abs(p.entry-p.sl),key=`${m.symbol}|${p.tf}|${p.side}|${Math.round(p.entry/(risk*.5))}`;
      if(i-(lastSeen.get(key)??-1e9)<72)continue;
      lastSeen.set(key,i);
      const fine=/\/M15$/.test(p.tf)&&M15.length;
      let res;
      if(fine){const k=M15.findIndex(c=>c.epoch>=t);if(k<0)continue;res=simulate(p,M15,k,192);}
      else res=simulate(p,H1,i+1);
      if(!res)continue;
      trades.push({group:driftGroup(m.name,p.side),market:m.name,t,tf:p.tf,side:p.side,kind:(p.setup.match(/\(([^)]+)\)/)||[])[1],quality:p.quality,aligned:p.aligned,
        swept:p.liquidity_swept,double:p.ocl_double,rr1:p.rr1,phase,riskPct:risk/p.entry*100,...res});
      t0All=Math.min(t0All,t);t1All=Math.max(t1All,t);
    }
  }
}
const split=t0All+(t1All-t0All)*.7;
const stat=list=>{
  const n=list.length;if(!n)return {n:0};
  const wins=list.filter(x=>x.exit==='TP1').length,sum=list.reduce((s,x)=>s+x.r,0);
  const be=list.reduce((s,x)=>s+1/(1+x.rr1),0)/n; // taux de gain nécessaire pour l'équilibre
  return {n,tp1:+(100*wins/n).toFixed(1),breakeven:+(100*be).toFixed(1),expR:+(sum/n).toFixed(3)};
};
const show=(label,fn)=>{
  const groups={};for(const x of trades){const k=fn(x);(groups[k]=groups[k]||[]).push(x);}
  console.log(`\n== ${label}`);
  for(const [k,l] of Object.entries(groups).sort()){
    const all=stat(l),tr=stat(l.filter(x=>x.t<split)),te=stat(l.filter(x=>x.t>=split));
    console.log(`${String(k).padEnd(22)} all n=${String(all.n).padStart(5)} TP1 ${String(all.tp1).padStart(5)}% (eq ${all.breakeven}%) ${String(all.expR).padStart(7)}R | test n=${te.n} TP1 ${te.tp1}% ${te.expR}R`);
  }
};
console.log('trades',trades.length,'global',JSON.stringify(stat(trades)));
show('paire',x=>x.tf);
show('qualité',x=>x.quality>=90?'90+':x.quality>=80?'80-89':x.quality>=70?'70-79':x.quality>=60?'60-69':'<60');
show('aligné',x=>x.aligned);
show('liquidité prise',x=>x.swept);
show('OCL double',x=>x.double);
show('type SNR',x=>x.kind);
show('phase',x=>x.phase);
show('R:R TP1',x=>x.rr1<1.2?'<1.2':x.rr1<2?'1.2-2':x.rr1<3?'2-3':'3+');
show('sens',x=>x.side);
if(OUT)writeFileSync(OUT,JSON.stringify(trades));

if(STATS){
  const cell=l=>{const s=stat(l);return {n:s.n,tp1_rate:s.tp1,breakeven_rate:s.breakeven,exp_r:s.expR};};
  const cells={};
  for(const x of trades){(cells[`${x.group}|${x.tf}`]=cells[`${x.group}|${x.tf}`]||[]).push(x);}
  const out={generated:new Date().toISOString(),method:'MSNR backtest (scripts/backtest-msnr.mjs)',
    note:"Ordre limite à l'entrée, sortie complète au TP1 ou au SL, SL prioritaire, 10 jours max. exp_r = espérance en R par trade ; breakeven_rate = taux de TP1 nécessaire pour l'équilibre. Trades qui se recouvrent : n n'est pas un nombre de situations indépendantes.",
    history:{from:new Date(t0All*1000).toISOString(),to:new Date(t1All*1000).toISOString(),split_70_30:new Date(split*1000).toISOString()},
    cells:Object.fromEntries(Object.entries(cells).map(([k,l])=>[k,{all:cell(l),train:cell(l.filter(x=>x.t<split)),test:cell(l.filter(x=>x.t>=split))}]))};
  writeFileSync(STATS,JSON.stringify(out,null,1));
  console.log('stats écrites',STATS);
}
