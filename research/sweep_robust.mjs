// Liquidity sweep filter applied INSIDE the trade loop (true sequence), with neighbouring settings to check robustness.
import {gunzipSync} from 'node:zlib';import {readFileSync} from 'node:fs';
import {driftPlaybook,driftProfile} from '../scripts/drift-playbook.mjs';
const raw=JSON.parse(gunzipSync(readFileSync('research/deriv-history.json.gz')).toString());
const rows=a=>(a||[]).map(([epoch,open,high,low,close])=>({epoch,open,high,low,close}));
const src=readFileSync('research/smc_filters.mjs','utf8');
const manage=new Function('MAXHOLD','return '+src.slice(src.indexOf('function manage'),src.indexOf('// swing points')))(10*86400);
const MAXHOLD=10*86400;
function sweep(w,dir,bars,look){const i=w.length-1;for(let b=0;b<bars;b++){const k=i-b,base=w.slice(k-look,k);
  const lo=Math.min(...base.map(x=>x.low)),hi=Math.max(...base.map(x=>x.high));
  if(dir>0?(w[k].low<lo&&w[k].close>lo):(w[k].high>hi&&w[k].close<hi))return true;}return false;}
function run(bars,look){const T=[];
  for(const m of raw.markets){if(!driftProfile(m.name))continue;const H1=rows(m.H1),M15=rows(m.M15);if(H1.length<1010)continue;let next=0;
    for(let i=960;i<H1.length-1;i++){const t=H1[i].epoch+3600;if(t<next)continue;const w=H1.slice(i-959,i+1),pb=driftPlaybook(m.name,w);if(!pb?.active)continue;
      if(bars&&!sweep(w,pb.side==='BUY'?1:-1,bars,look))continue;
      const path=M15.length&&M15[0].epoch<=t?M15:H1;let lo=0,hi=path.length;while(lo<hi){const md=(lo+hi)>>1;if(path[md].epoch<t)lo=md+1;else hi=md;}
      if(lo>=path.length)break;const res=manage(path,lo,pb.side,pb.levels);if(!res)break;T.push({g:pb.group,t,...res});next=res.end+3600;}}
  return T;}
const st=l=>{const n=l.length,r=l.reduce((a,x)=>a+x.r,0);return `n=${String(n).padStart(4)} TP1 ${(l.filter(x=>x.tp1).length/n*100).toFixed(1)}% esp ${(r/n).toFixed(3)}R total ${r.toFixed(0)}R`;};
const base=run(0,0),split=base.map(x=>x.t).sort((a,b)=>a-b)[Math.floor(base.length*.7)];
for(const [bars,look] of [[0,0],[1,20],[3,20],[5,20],[3,10],[3,30]]){
  const T=bars?run(bars,look):base;
  for(const g of ['bullbear','spike']){const l=T.filter(x=>x.g===g);
    console.log(`${bars?`balayage ${bars} bougies / ${look}`:'sans filtre       '} ${g.padEnd(8)} TRAIN ${st(l.filter(x=>x.t<split))} | TEST ${st(l.filter(x=>x.t>=split))}`);}
}
