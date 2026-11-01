// Sera backtester: replays the REAL engine (scripts/update-signals.mjs) candle by candle on Deriv history
// and simulates each trade with the EA management (50 % at TP1, stop to break-even, final TP3, time limit).
// Usage: node scripts/backtest.mjs research/deriv-history.json.gz [--mode swing|day|both] [--out research/events.jsonl] [--markets 5]
import {gunzipSync} from 'node:zlib';
import {readFileSync,writeFileSync} from 'node:fs';
import * as E from './update-signals.mjs';

const args=process.argv.slice(2);
const opt=(k,d)=>{const i=args.indexOf(k);return i>=0?args[i+1]:d;};
const file=args[0]||'research/deriv-history.json.gz';
const modeArg=opt('--mode','both');
const OUT=opt('--out','research/events.jsonl');
const LIMIT=Number(opt('--markets',0));
const raw=JSON.parse(gunzipSync(readFileSync(file)).toString());
const rows=a=>(a||[]).map(([epoch,open,high,low,close])=>({epoch,open,high,low,close}));

let markets=raw.markets.map(m=>({...m,family:E.marketFamilyFromName(m.name),spikeBias:E.marketSpikeBias(m.name),H1:rows(m.H1),M15:rows(m.M15),D1:rows(m.D1)}))
  .filter(m=>m.H1.length>1100);
if(LIMIT)markets=markets.slice(0,LIMIT);

// Simulated clock: the engine reads Date.now() (freshness, closed candles).
let NOW=0;const realNow=Date.now;Date.now=()=>NOW*1000;

const upto=(arr,t)=>{let lo=0,hi=arr.length;while(lo<hi){const mid=(lo+hi)>>1;if(arr[mid].epoch<t)lo=mid+1;else hi=mid;}return lo;}; // first index with epoch>=t
function windowBefore(arr,closeTime,sec,count){ // candles fully closed at closeTime
  const end=upto(arr,closeTime-sec+1); return arr.slice(Math.max(0,end-count),end);
}

const MODES=E.MODES.filter(m=>modeArg==='both'||m.id===modeArg);
const events=[];
const ENTRY_SEC={swing:3600,day:900};

function simulate(m,mode,verdict,levels,t){
  // forward path on M15 when available (more precise), else H1
  const path=m.M15.length&&m.M15[0].epoch<=t?m.M15:m.H1;
  const sec=path===m.M15?900:3600;
  const maxHold=mode==='swing'?10*86400:12*3600;
  const dir=verdict==='BUY'?1:-1,entry=levels.entry,risk=Math.abs(entry-levels.sl);
  if(!(risk>0))return null;
  const R=p=>dir*(p-entry)/risk;
  let i=upto(path,t),tp1=false,stop=levels.sl,mfe=0,mae=0,out=null;
  for(;i<path.length;i++){
    const c=path[i];if(c.epoch-t>maxHold){out={r:tp1?0.75+0.5*R(c.open):R(c.open),why:'TIME',bars:i};break;}
    const fav=dir>0?c.high:c.low,adv=dir>0?c.low:c.high;
    mfe=Math.max(mfe,R(fav));mae=Math.min(mae,R(adv));
    const hitStop=dir>0?adv<=stop:adv>=stop;
    if(hitStop){out={r:tp1?0.75+0.5*R(stop):-1,why:tp1?'BE':'SL'};break;}    // stop checked first (conservative)
    if(!tp1&&(dir>0?fav>=levels.tp1:fav<=levels.tp1)){tp1=true;stop=entry;}
    if(tp1&&(dir>0?fav>=levels.tp3:fav<=levels.tp3)){out={r:0.75+0.5*3.6,why:'TP3'};break;}
  }
  if(!out)return null; // not finished in the history
  return {...out,tp1,mfe:+mfe.toFixed(2),mae:+mae.toFixed(2),hours:Math.round(((path[Math.min(i,path.length-1)]?.epoch||t)-t)/3600)};
}

const tfCount={M15:240,H1:960,D1:240};
const tfSec={M15:900,H1:3600,D1:86400};
for(const mode of MODES){
  const step=ENTRY_SEC[mode.id];
  const base=mode.id==='swing'?'H1':'M15';
  const times=new Set();
  for(const m of markets)for(const c of m[base].slice(mode.id==='swing'?1000:260))times.add(c.epoch+step);
  const clock=[...times].sort((a,b)=>a-b);
  const previous=new Map(),openUntil=new Map();
  let n=0;const t0=realNow();
  for(const t of clock){
    NOW=t+5;
    const setups=[];
    for(const m of markets){
      const entryRows=windowBefore(m[mode.entry],t,tfSec[mode.entry],tfCount[mode.entry]);
      if(entryRows.length<80||entryRows.at(-1).epoch+tfSec[mode.entry]!==t)continue;
      const h1=mode.entry==='H1'?entryRows:windowBefore(m.H1,t,3600,960);
      const conf=mode.confirmation==='H4'?E.aggregateCandles(h1,14400):h1;
      const macroRows=mode.macro?windowBefore(m.D1,t,86400,240):null;
      const entry=E.inspectCandles(entryRows),confirmation=E.inspectCandles(conf),macro=macroRows?E.inspectCandles(macroRows):null;
      if(!entry||!confirmation||(mode.macro&&!macro))continue;
      const meta={market:m.name,symbol:m.symbol,family:m.family,spikeBias:m.spikeBias};
      const setup=E.technicalSetup(meta,entry,confirmation,mode,macro);
      const id=`${m.symbol}:${mode.id}`;
      setups.push({m,setup:E.attachTrendMemory(setup,{markets:previous.has(id)?[previous.get(id)]:[]})});
    }
    const ctx=E.buildFamilyContexts(setups.map(s=>s.setup));
    for(const {m,setup} of setups){
      const s=E.attachFamilyContext(setup,ctx);s.autonomous=E.autonomousDecision(s);
      const fin=E.finalize(s,null);
      const id=fin.id,prev=previous.get(id);previous.set(id,fin);
      const eng=fin.decision_engine;
      const isSignal=fin.final_verdict==='BUY'||fin.final_verdict==='SELL';
      const detected=eng.setup_detected&&(eng.detected_side==='BUY'||eng.detected_side==='SELL');
      if(!isSignal&&!detected)continue;
      if((openUntil.get(id)||0)>t)continue;           // one trade at a time per market/mode
      const side=isSignal?fin.final_verdict:eng.detected_side;
      const levels=fin.levels||fin.projected_levels;
      if(!levels)continue;
      const res=simulate(m,mode.id,side,levels,t);
      if(!res)continue;
      openUntil.set(id,t+res.hours*3600);
      const e=fin.entry_tf,c=fin.confirmation_tf,d=fin.macro_tf||{};
      events.push({t,market:m.name,family:m.family,mode:mode.id,side,signal:isSignal,state:fin.execution_state,exec_score:fin.execution_score,
        confidence:fin.final_confidence,score:eng.score,conditions:eng.condition_pass_percent,consensus:eng.consensus,setup:eng.setup_type,
        cycles:fin.trend_memory?.bias_cycles,regime:e.regime,c_regime:c.regime,d_regime:d.regime,adx:+(+e.adx).toFixed(1),c_adx:+(+c.adx).toFixed(1),
        rsi:+(+e.rsi).toFixed(1),c_rsi:+(+c.rsi).toFixed(1),d_rsi:+(+d.rsi||0).toFixed(1),bos:!!e.bos,choch:!!e.choch,sweep:!!e.sweep,fvg:!!e.fvg,ob:!!e.orderBlock,
        retest:!!e.retest,impulse:!!e.impulse,rejection:!!e.rejection,squeeze:!!e.squeeze,er:+(+e.efficiencyRatio||0).toFixed(2),tq:Math.round(e.trendQuality||0),
        c_tq:Math.round(c.trendQuality||0),spread_atr:+(+e.emaSpreadAtr||0).toFixed(2),slope_atr:+(+e.emaSlopeAtr||0).toFixed(2),
        risk_atr:+(Math.abs(levels.entry-levels.sl)/(e.atr||1)).toFixed(2),fam_agree:!!fin.family_context?.agrees,hour:new Date(t*1000).getUTCHours(),
        ...res});
    }
    if(++n%500===0)console.error(`${mode.id} ${n}/${clock.length} steps, ${events.length} trades, ${Math.round((realNow()-t0)/1000)} s`);
  }
}
writeFileSync(OUT,events.map(e=>JSON.stringify(e)).join('\n'));
const stat=list=>{const w=list.filter(e=>e.tp1).length,r=list.reduce((a,e)=>a+e.r,0);return `${list.length} trades, TP1 ${list.length?Math.round(w/list.length*100):0}%, total ${r.toFixed(1)} R`;};
console.log('ALL',stat(events));
console.log('SIGNALS',stat(events.filter(e=>e.signal)));
for(const f of [...new Set(events.map(e=>e.family))])console.log(f,stat(events.filter(e=>e.family===f)));
