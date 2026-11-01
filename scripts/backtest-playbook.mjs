// Measures the Drift Playbook (scripts/drift-playbook.mjs, the code used live) on real Deriv H1 history,
// with the EA management: 50 % closed at TP1 and stop to break-even, stop to TP1 at TP2, rest at TP3, 10 days max.
// The position is checked on M15 when available (stop first when a candle touches both). One trade at a time per index.
// Usage: node scripts/backtest-playbook.mjs research/deriv-history.json.gz [--out data/playbook-stats.json]
import {gunzipSync} from 'node:zlib';
import {readFileSync,writeFileSync} from 'node:fs';
import {driftPlaybook,driftProfile,PLAYBOOKS} from './drift-playbook.mjs';

const file=process.argv[2]||'research/deriv-history.json.gz';
const PRECISION=process.argv.includes('--precision');
const oi=process.argv.indexOf('--out');const OUT=oi>0?process.argv[oi+1]:'data/playbook-stats.json';
const raw=JSON.parse(gunzipSync(readFileSync(file)).toString());
const rows=a=>(a||[]).map(([epoch,open,high,low,close])=>({epoch,open,high,low,close}));
const WINDOW=960,MAXHOLD=10*86400;

function manage(path,from,side,lv,partial=0.5){
  const dir=side==='BUY'?1:-1,risk=Math.abs(lv.entry-lv.sl),R=p=>dir*(p-lv.entry)/risk;
  let stop=lv.sl,stage=0,banked=0,left=1;
  for(let j=from;j<path.length;j++){
    const c=path[j];
    if(c.epoch-path[from].epoch>MAXHOLD)return {r:banked+left*R(c.open),tp1:stage>0,exit:'TIME',end:c.epoch};
    const adv=dir>0?c.low:c.high,fav=dir>0?c.high:c.low;
    if(dir>0?adv<=stop:adv>=stop)return {r:banked+left*R(stop),tp1:stage>0,exit:stage?'STOP_PROTEGE':'SL',end:c.epoch};
    if(stage<1&&(dir>0?fav>=lv.tp1:fav<=lv.tp1)){stage=1;banked+=partial*R(lv.tp1);left-=partial;stop=lv.entry;}
    if(stage<2&&stage>=1&&(dir>0?fav>=lv.tp2:fav<=lv.tp2)){stage=2;stop=lv.tp1;}
    if(stage>=1&&(dir>0?fav>=lv.tp3:fav<=lv.tp3))return {r:banked+left*R(lv.tp3),tp1:true,exit:'TP3',end:c.epoch};
  }
  return null;
}

const trades=[];
for(const m of raw.markets){
  if(!driftProfile(m.name))continue;
  const H1=rows(m.H1),M15=rows(m.M15);
  if(H1.length<WINDOW+50)continue;
  let next=0;
  for(let i=WINDOW;i<H1.length-1;i++){
    const t=H1[i].epoch+3600;           // the H1 candle i is closed
    if(t<next)continue;
    const pb=driftPlaybook(m.name,H1.slice(i-WINDOW+1,i+1));
    if(!pb?.active||(PRECISION&&!pb.liquidity_sweep))continue;
    const useM15=M15.length&&M15[0].epoch<=t;
    const path=useM15?M15:H1;
    let k=0,lo=0,hi=path.length;while(lo<hi){const mid=(lo+hi)>>1;if(path[mid].epoch<t)lo=mid+1;else hi=mid;}k=lo;
    if(k>=path.length)break;
    const res=manage(path,k,pb.side,pb.levels);
    if(!res)break;
    trades.push({market:m.name,group:pb.group,side:pb.side,t,...res});
    next=res.end+3600;
  }
}
const sum=list=>{
  const n=list.length,r=list.map(x=>x.r);
  const months=new Map();for(const x of list){const k=new Date(x.t*1000).toISOString().slice(0,7);months.set(k,(months.get(k)||0)+x.r);}
  return {trades:n,tp1_rate:n?+(list.filter(x=>x.tp1).length/n*100).toFixed(1):0,losing_rate:n?+(r.filter(v=>v<0).length/n*100).toFixed(1):0,
    expectancy_r:n?+(r.reduce((a,b)=>a+b,0)/n).toFixed(3):0,total_r:+r.reduce((a,b)=>a+b,0).toFixed(1),
    positive_months:[...months.values()].filter(v=>v>0).length,months:months.size};
};
const ts=trades.map(x=>x.t).sort((a,b)=>a-b),split=ts[Math.floor(ts.length*0.7)]||0;
const out={precision:PRECISION,generated_at:new Date().toISOString(),source:'Historique H1/M15 Deriv réel (1 an) — scripts/backtest-playbook.mjs',
  period:{from:new Date(ts[0]*1000).toISOString().slice(0,10),to:new Date(ts.at(-1)*1000).toISOString().slice(0,10)},
  management:'50 % encaissés à TP1 + stop au point d’entrée, stop à TP1 quand TP2 est touché, reste à TP3 ; stop vérifié en premier',
  groups:{},markets:{}};
for(const g of Object.keys(PLAYBOOKS)){
  const list=trades.filter(x=>x.group===g);if(!list.length)continue;
  out.groups[g]={label:PLAYBOOKS[g].label,params:PLAYBOOKS[g],all:sum(list),train:sum(list.filter(x=>x.t<split)),test:sum(list.filter(x=>x.t>=split))};
}
for(const name of [...new Set(trades.map(x=>x.market))])out.markets[name]=sum(trades.filter(x=>x.market===name));
writeFileSync(OUT,JSON.stringify(out,null,1));
for(const [g,v] of Object.entries(out.groups))
  console.log(`${v.label}: ${v.all.trades} trades, TP1 ${v.all.tp1_rate}%, perdants ${v.all.losing_rate}%, ${v.all.expectancy_r} R/trade, mois positifs ${v.all.positive_months}/${v.all.months} | test : TP1 ${v.test.tp1_rate}% ${v.test.expectancy_r} R`);
for(const [k,v] of Object.entries(out.markets))console.log(`  ${k}: ${v.trades} trades, TP1 ${v.tp1_rate}%, perdants ${v.losing_rate}%, ${v.expectancy_r} R`);
