// Precision drift playbook (with liquidity sweep): ATR stop (current) vs structural SMC stop beyond the sweep wick.
import {gunzipSync} from 'node:zlib';import {readFileSync} from 'node:fs';
import {driftPlaybook,driftProfile,PLAYBOOKS} from '../scripts/drift-playbook.mjs';
const raw=JSON.parse(gunzipSync(readFileSync('research/deriv-history.json.gz')).toString());
const rows=a=>(a||[]).map(([epoch,open,high,low,close])=>({epoch,open,high,low,close}));
const src=readFileSync('research/smc_filters.mjs','utf8');
const manage=new Function('MAXHOLD','return '+src.slice(src.indexOf('function manage'),src.indexOf('// swing points')))(10*86400);
function sweepExtreme(w,dir){const i=w.length-1;for(let b=0;b<3;b++){const k=i-b,base=w.slice(k-20,k);const lo=Math.min(...base.map(x=>x.low)),hi=Math.max(...base.map(x=>x.high));
  if(dir>0&&w[k].low<lo&&w[k].close>lo)return w[k].low;if(dir<0&&w[k].high>hi&&w[k].close<hi)return w[k].high;}return null;}
function run(mode){const T=[];
  for(const m of raw.markets){if(!driftProfile(m.name))continue;const H1=rows(m.H1),M15=rows(m.M15);if(H1.length<1010)continue;let next=0;
    for(let i=960;i<H1.length-1;i++){const t=H1[i].epoch+3600;if(t<next)continue;const w=H1.slice(i-959,i+1),pb=driftPlaybook(m.name,w);
      if(!pb?.active||!pb.liquidity_sweep)continue;let lv=pb.levels;const dir=pb.side==='BUY'?1:-1;
      if(mode!=='atr'){const ext=sweepExtreme(w,dir);if(ext===null)continue;const sl=ext-dir*0.1*pb.atr,risk=Math.abs(lv.entry-sl);
        if(!(risk>0)||dir*(lv.entry-sl)<=0)continue;
        if(mode==='smc_min'&&risk<Math.abs(lv.entry-lv.sl))continue; // keep only when the wick stop is wider (safer) — variant
        const p=PLAYBOOKS[pb.group],at=r=>lv.entry+dir*r*risk;lv={entry:lv.entry,sl,tp1:at(p.tp1),tp2:at(p.tp2),tp3:at(p.tp3)};}
      const path=M15.length&&M15[0].epoch<=t?M15:H1;let lo=0,hi=path.length;while(lo<hi){const md=(lo+hi)>>1;if(path[md].epoch<t)lo=md+1;else hi=md;}
      if(lo>=path.length)break;const res=manage(path,lo,pb.side,lv);if(!res)break;T.push({g:pb.group,t,...res});next=res.end+3600;}}return T;}
const st=l=>{const n=l.length,r=l.reduce((a,x)=>a+x.r,0);return `n=${String(n).padStart(4)} TP1 ${(l.filter(x=>x.tp1).length/n*100).toFixed(1)}% esp ${(r/n).toFixed(3)}R`;};
const base=run('atr'),split=base.map(x=>x.t).sort((a,b)=>a-b)[Math.floor(base.length*.7)];
for(const mode of ['atr','smc']){const T=mode==='atr'?base:run(mode);
  for(const g of ['bullbear','spike']){const l=T.filter(x=>x.g===g);console.log(`${mode==='atr'?'stop ATR (actuel)':'stop SMC sous la meche'} ${g.padEnd(8)} TRAIN ${st(l.filter(x=>x.t<split))} | TEST ${st(l.filter(x=>x.t>=split))}`);}}
