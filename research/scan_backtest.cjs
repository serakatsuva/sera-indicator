// Backtest du scan du Copilot (copilot.js -> _scan) : le biais prédit-il le mouvement suivant ?
// Usage : node research/scan_backtest.cjs [horizon_en_bougies_H1=6] [dossier_des_historiques=research/]
// Historiques : deriv-history.json.gz et deriv-real-history.json.gz (branche research-data, workflow "Sera Backtest History").
// Échantillonnage sans chevauchement (un point tous les HORIZON bougies) pour ne pas gonfler la significativité.
const fs=require("fs"),zlib=require("zlib");
global.window={};global.document={getElementById:()=>null,addEventListener(){}};global.fetch=()=>Promise.reject();
require("../copilot.js");
const scan=window.SeraCopilot._scan;
const SP=(process.argv[3]||"research/")+(((process.argv[3]||"research/").endsWith("/"))?"":"/");
const HORIZON=+process.argv[2]||6;          // bougies H1 vers l'avant
const WARM=130;

function load(f){return JSON.parse(zlib.gunzipSync(fs.readFileSync(SP+f)).toString());}
const sets=[["synthetic","deriv-history.json.gz"],["real","deriv-real-history.json.gz"]];

function wilson(k,n,z=1.96){if(!n)return[0,0];const p=k/n,d=1+z*z/n,c=p+z*z/(2*n),m=z*Math.sqrt(p*(1-p)/n+z*z/(4*n*n));return[(c-m)/d,(c+m)/d];}
function atrAt(rows,i){let s=0;for(let k=i-13;k<=i;k++){const p=rows[k-1][4];s+=Math.max(rows[k][2]-rows[k][3],Math.abs(rows[k][2]-p),Math.abs(rows[k][3]-p));}return s/14;}

const buckets=new Map();
function add(key,dir,ret,base,t){ // dir ±1, ret en ATR
  const b=buckets.get(key)||{n:0,hit:0,sum:0,sumsq:0,early:{n:0,hit:0,sum:0},late:{n:0,hit:0,sum:0}};
  const d=dir*ret;b.n++;b.sum+=d;b.sumsq+=d*d;if(d>0)b.hit++;
  const part=t<base?b.early:b.late;part.n++;part.sum+=d;if(d>0)part.hit++;
  buckets.set(key,b);
}
const t0=Date.now();
for(const [setName,file] of sets){
  const data=load(file);
  for(const m of data.markets){
    const h=m.H1;if(!h||h.length<WARM+HORIZON+50)continue;
    const fam=setName==="synthetic"?(/boom|crash|gainx|painx/i.test(m.name)?"spike":/bull|bear/i.test(m.name)?"bullbear":"vol/autre"):(/\//.test(m.name)?(/BTC|ETH|LTC|XRP/.test(m.name)?"crypto":"forex"):"indices");
    const split=h[Math.floor(h.length*.7)][0];
    for(let i=WARM;i+HORIZON<h.length;i+=HORIZON){
      const win=h.slice(i-WARM+1,i+1).map(r=>({open:r[1],high:r[2],low:r[3],close:r[4]}));
      const s=scan(win);if(!s)continue;
      const atr=atrAt(h,i);if(!(atr>0))continue;
      const ret=(h[i+HORIZON][4]-h[i][4])/atr;
      const fams=[ "TOUS", setName+":"+fam ];
      const sides=[];
      if(s.bias!=="NEUTRE")sides.push(["biais(≥2 votes)",s.bias==="BUY"?1:-1]);
      if(s.votes>=3||s.votes<=-3)sides.push(["biais fort(≥3 votes)",s.votes>0?1:-1]);
      if(s.structure)sides.push(["seul:structure",s.structure]);
      if(s.sweep.dir)sides.push(["seul:balayage",s.sweep.dir]);
      if(s.impulse)sides.push(["seul:impulsion",s.impulse]);
      if(s.mom)sides.push(["seul:momentum",s.mom]);
      // contrarien : mêmes votes mais inversés (test d'inversion du signal)
      if(s.bias!=="NEUTRE")sides.push(["INVERSÉ biais",s.bias==="BUY"?-1:1]);
      for(const f of fams)for(const [name,dir] of sides)add(f+" | "+name,dir,ret,split,h[i][0]);
      // référence : toujours acheter / toujours vendre sur les mêmes points
      for(const f of fams){add(f+" | réf:toujours BUY",1,ret,split,h[i][0]);add(f+" | réf:toujours SELL",-1,ret,split,h[i][0]);}
    }
  }
}
const rows=[...buckets.entries()].map(([k,b])=>{
  const [lo,hi]=wilson(b.hit,b.n),mean=b.sum/b.n,sd=Math.sqrt(Math.max(0,b.sumsq/b.n-mean*mean)),t=sd>0?mean/(sd/Math.sqrt(b.n)):0;
  return {k,n:b.n,hit:100*b.hit/b.n,lo:100*lo,hi:100*hi,mean,t,
    earlyN:b.early.n,earlyMean:b.early.n?b.early.sum/b.early.n:NaN,earlyHit:b.early.n?100*b.early.hit/b.early.n:NaN,
    lateN:b.late.n,lateMean:b.late.n?b.late.sum/b.late.n:NaN,lateHit:b.late.n?100*b.late.hit/b.late.n:NaN};
}).sort((a,b)=>a.k.localeCompare(b.k));
fs.writeFileSync(`research/scan-bt-h${HORIZON}.json`,JSON.stringify(rows,null,1));
const f=(x,d=1)=>Number.isFinite(x)?x.toFixed(d):"—";
console.log(`HORIZON=${HORIZON} bougies H1 · ${((Date.now()-t0)/1000).toFixed(0)}s`);
for(const r of rows){
  if(!/^(TOUS|synthetic:|real:)/.test(r.k))continue;
  if(r.n<150)continue;
  console.log(`${r.k.padEnd(52)} n=${String(r.n).padStart(5)}  réussite ${f(r.hit)}% [${f(r.lo)}-${f(r.hi)}]  gain moyen ${f(r.mean,3)} ATR (t=${f(r.t,1)})  | 1re moitié ${f(r.earlyMean,3)} (${f(r.earlyHit,0)}%) · 2e moitié ${f(r.lateMean,3)} (${f(r.lateHit,0)}%)`);
}
