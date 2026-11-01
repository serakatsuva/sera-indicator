// Measures support/resistance and SMC filters on top of the Drift Playbook (real Deriv H1 history, EA management).
import {gunzipSync} from 'node:zlib';
import {readFileSync} from 'node:fs';
import {driftPlaybook,driftProfile,PLAYBOOKS} from '../scripts/drift-playbook.mjs';
const raw=JSON.parse(gunzipSync(readFileSync('research/deriv-history.json.gz')).toString());
const rows=a=>(a||[]).map(([epoch,open,high,low,close])=>({epoch,open,high,low,close}));
const WINDOW=960,MAXHOLD=10*86400;
function manage(path,from,side,lv){
  const dir=side==='BUY'?1:-1,risk=Math.abs(lv.entry-lv.sl),R=p=>dir*(p-lv.entry)/risk;
  let stop=lv.sl,stage=0,banked=0,left=1;
  for(let j=from;j<path.length;j++){const c=path[j];
    if(c.epoch-path[from].epoch>MAXHOLD)return {r:banked+left*R(c.open),tp1:stage>0,end:c.epoch};
    const adv=dir>0?c.low:c.high,fav=dir>0?c.high:c.low;
    if(dir>0?adv<=stop:adv>=stop)return {r:banked+left*R(stop),tp1:stage>0,end:c.epoch};
    if(stage<1&&(dir>0?fav>=lv.tp1:fav<=lv.tp1)){stage=1;banked+=0.5*R(lv.tp1);left=0.5;stop=lv.entry;}
    if(stage===1&&(dir>0?fav>=lv.tp2:fav<=lv.tp2)){stage=2;stop=lv.tp1;}
    if(stage>=1&&(dir>0?fav>=lv.tp3:fav<=lv.tp3))return {r:banked+left*R(lv.tp3),tp1:true,end:c.epoch};}
  return null;
}
// swing points: fractal with k bars each side
function swings(w,k=3){const hi=[],lo=[];for(let i=k;i<w.length-k;i++){let h=true,l=true;for(let j=1;j<=k;j++){if(w[i].high<=w[i-j].high||w[i].high<w[i+j].high)h=false;if(w[i].low>=w[i-j].low||w[i].low>w[i+j].low)l=false;}if(h)hi.push(i);if(l)lo.push(i);}return {hi,lo};}
function features(w,pb){
  const n=w.length,i=n-1,c=w[i],dir=pb.side==='BUY'?1:-1,atr=pb.atr,price=c.close,risk=Math.abs(pb.levels.entry-pb.levels.sl);
  const recent=w.slice(-120),{hi,lo}=swings(recent),off=n-recent.length;
  const highs=hi.map(k=>recent[k].high),lows=lo.map(k=>recent[k].low);
  const support=Math.max(...lows.filter(x=>x<price),-Infinity),resist=Math.min(...highs.filter(x=>x>price),Infinity);
  const zoneDist=dir>0?(price-support)/atr:(resist-price)/atr;          // distance to the demand (BUY) / supply (SELL) zone
  const room=dir>0?(resist-price)/risk:(price-support)/risk;               // room to the opposite level, in R
  const prev20=w.slice(i-20,i);
  const sweep=[0,1,2].some(b=>{const k=i-b,base=w.slice(k-20,k);if(base.length<20)return false;
    return dir>0?(w[k].low<Math.min(...base.map(x=>x.low))&&w[k].close>Math.min(...base.map(x=>x.low)))
                :(w[k].high>Math.max(...base.map(x=>x.high))&&w[k].close<Math.max(...base.map(x=>x.high)));});
  let fvg=false;for(let k=i-10;k<=i;k++){if(k<2)continue;if(dir>0?w[k].low>w[k-2].high:w[k].high<w[k-2].low){fvg=true;}}
  // order block: last opposite candle before an impulse of >= 1.5 ATR in drift direction (last 30 bars); price back inside it
  let ob=false;for(let k=i-30;k<i-1;k++){const imp=dir*(w[Math.min(i,k+3)].close-w[k].close);if(imp>=1.5*atr&&(dir>0?w[k].close<w[k].open:w[k].close>w[k].open)){if(price<=w[k].high+0.2*atr&&price>=w[k].low-0.2*atr)ob=true;}}
  // BOS in drift direction within last 48 bars: a close beyond the previous swing high (BUY) / low (SELL)
  let bos=false;const sw=dir>0?hi:lo;for(const k of sw){const lvl=dir>0?recent[k].high:recent[k].low;for(let j=k+1;j<recent.length;j++){if(j+off<i-48)continue;if(dir>0?recent[j].close>lvl:recent[j].close<lvl){bos=true;break;}}}
  // rejection candle at the level: wick against drift >= body
  const body=Math.abs(c.close-c.open),wick=dir>0?Math.min(c.open,c.close)-c.low:c.high-Math.max(c.open,c.close);
  return {zoneDist,room,sweep,fvg,ob,bos,rejection:wick>=body&&wick>0.3*atr,bull:c.close>c.open};
}
const T=[];
for(const m of raw.markets){
  if(!driftProfile(m.name))continue;
  const H1=rows(m.H1),M15=rows(m.M15);if(H1.length<WINDOW+50)continue;
  let next=0;
  for(let i=WINDOW;i<H1.length-1;i++){
    const t=H1[i].epoch+3600;if(t<next)continue;
    const w=H1.slice(i-WINDOW+1,i+1),pb=driftPlaybook(m.name,w);if(!pb?.active)continue;
    const path=M15.length&&M15[0].epoch<=t?M15:H1;let lo=0,hi=path.length;while(lo<hi){const md=(lo+hi)>>1;if(path[md].epoch<t)lo=md+1;else hi=md;}
    if(lo>=path.length)break;const res=manage(path,lo,pb.side,pb.levels);if(!res)break;
    T.push({g:pb.group,t,...res,...features(w,pb)});next=res.end+3600;   // same trade sequence as the live playbook
  }
}
const ts=T.map(x=>x.t).sort((a,b)=>a-b),split=ts[Math.floor(ts.length*.7)];
const st=l=>{const n=l.length;if(!n)return '   n=0';const r=l.reduce((a,x)=>a+x.r,0);return `n=${String(n).padStart(4)} TP1 ${(l.filter(x=>x.tp1).length/n*100).toFixed(1).padStart(5)}% pertes ${(l.filter(x=>x.r<0).length/n*100).toFixed(1).padStart(5)}% esp ${(r/n).toFixed(3).padStart(6)}R total ${r.toFixed(0).padStart(5)}R`;};
const F={
  'aucun filtre':x=>true,
  'zone S/R <= 1 ATR':x=>x.zoneDist<=1,
  'zone S/R <= 2 ATR':x=>x.zoneDist<=2,
  'zone S/R > 2 ATR':x=>x.zoneDist>2,
  'place jusqu au niveau oppose >= TP3':x=>x.room>=1.6,
  'place < TP3':x=>x.room<1.6,
  'balayage de liquidite':x=>x.sweep,
  'pas de balayage':x=>!x.sweep,
  'FVG dans le sens':x=>x.fvg,
  'order block retouche':x=>x.ob,
  'BOS dans le sens (48h)':x=>x.bos,
  'pas de BOS':x=>!x.bos,
  'bougie de rejet':x=>x.rejection,
  'zone<=2 ATR + place>=TP3':x=>x.zoneDist<=2&&x.room>=1.6,
  'BOS + place>=TP3':x=>x.bos&&x.room>=1.6,
  'zone<=2 + BOS':x=>x.zoneDist<=2&&x.bos,
  'sweep ou OB':x=>x.sweep||x.ob,
};
for(const g of ['bullbear','spike']){
  console.log(`\n=== ${PLAYBOOKS[g].label}`);
  for(const [k,f] of Object.entries(F)){
    const l=T.filter(x=>x.g===g&&f(x));
    console.log(`${k.padEnd(38)} TRAIN ${st(l.filter(x=>x.t<split))} | TEST ${st(l.filter(x=>x.t>=split))}`);
  }
}
