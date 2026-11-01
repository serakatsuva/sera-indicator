// Downloads long Deriv candle history (synthetic indices) for the Sera backtester.
// Runs in GitHub Actions (the Deriv WebSocket is reachable there). Output: research/deriv-history.json.gz
// Usage: node scripts/fetch-history.mjs [--pages-h1 3] [--pages-m15 2]
import {gzipSync} from 'node:zlib';
import {writeFileSync,mkdirSync} from 'node:fs';

const WS='wss://api.derivws.com/trading/v1/options/ws/public?app_id=1089';
const arg=(k,d)=>{const i=process.argv.indexOf(k);return i>0?Number(process.argv[i+1]):d;};
const PAGES={H1:arg('--pages-h1',3),M15:arg('--pages-m15',2),D1:1};
const SET=process.argv.includes('--set')?process.argv[process.argv.indexOf('--set')+1]:'synthetic';   // synthetic | real
const GRAN={M15:900,H1:3600,D1:86400};

function synthetic(item){
  const t=`${item.market||''} ${item.submarket||''} ${item.underlying_symbol_name||item.display_name||''}`.toLowerCase();
  return /synthetic|derived|random|boom|crash|volatility|jump|step|range break|\bdex\b|drift switch|volswitch|exponential/.test(t)
    && !/^frx|^cry|^otc_/i.test(String(item.underlying_symbol||item.symbol||''));
}

function client(){
  const ws=new WebSocket(WS);let id=1;const waiting=new Map();
  ws.addEventListener('message',e=>{let m;try{m=JSON.parse(String(e.data));}catch{return;}const r=waiting.get(m.req_id);if(r){waiting.delete(m.req_id);r(m);}});
  const ready=new Promise((ok,ko)=>{ws.addEventListener('open',ok);ws.addEventListener('error',()=>ko(new Error('ws error')));});
  const call=async req=>{await ready;const req_id=++id;return new Promise((ok,ko)=>{const t=setTimeout(()=>{waiting.delete(req_id);ko(new Error('timeout'));},30000);
    waiting.set(req_id,m=>{clearTimeout(t);ok(m);});ws.send(JSON.stringify({...req,req_id}));});};
  return {call,close:()=>ws.close()};
}

const sleep=ms=>new Promise(r=>setTimeout(r,ms));

async function candles(c,symbol,tf){
  let end='latest',all=[];
  for(let p=0;p<PAGES[tf];p++){
    let m;
    for(let a=0;a<4;a++){
      try{m=await c.call({ticks_history:symbol,style:'candles',granularity:GRAN[tf],count:1000,end,adjust_start_time:1});}catch(e){m={error:{message:e.message}};}
      if(!m.error)break;
      await sleep(1500*(a+1));
    }
    if(m.error||!Array.isArray(m.candles)||!m.candles.length){if(m.error)console.warn(symbol,tf,m.error.message);break;}
    const rows=m.candles.map(x=>[+x.epoch,+x.open,+x.high,+x.low,+x.close]);
    const before=all.length?all[0][0]:Infinity;
    all=rows.concat(all.filter(r=>r[0]>rows[rows.length-1][0]));
    if(all[0][0]>=before)break;
    end=rows[0][0]-1;
    // Forex / indices pages are not full (market closed hours): keep going back while the history still moves back.
    if(rows.length<50)break;
    await sleep(250);
  }
  const seen=new Set();return all.filter(r=>!seen.has(r[0])&&seen.add(r[0])).sort((a,b)=>a[0]-b[0]);
}

const c=client();
const act=await c.call({active_symbols:'brief'});
// "real": Forex, metals, stock indices, crypto offered by Deriv (everything that is not a synthetic index).
const real=i=>/^(frx|cry|otc_|wld)/i.test(String(i.underlying_symbol||i.symbol||''))&&!synthetic(i);
const markets=(act.active_symbols||[]).filter(SET==='real'?real:synthetic).map(i=>({symbol:String(i.underlying_symbol||i.symbol),name:String(i.underlying_symbol_name||i.display_name||i.symbol)}))
  .filter((m,i,a)=>a.findIndex(x=>x.symbol===m.symbol)===i);
console.log(`${markets.length} synthetic markets`);
const out={fetched_at:new Date().toISOString(),set:SET,format:'[epoch,open,high,low,close]',markets:[]};
for(const m of markets){
  const row={...m,market:String(act.active_symbols.find(i=>String(i.underlying_symbol||i.symbol)===m.symbol)?.market||'')};
  for(const tf of ['H1','M15','D1']){row[tf]=await candles(c,m.symbol,tf);}
  console.log(m.name,'H1',row.H1.length,'M15',row.M15.length,'D1',row.D1.length);
  out.markets.push(row);
}
c.close();
// Deriv keeps only a few weeks of H1 for some Forex / metals / stock indices: complete with Yahoo Finance hourly (2 years).
const YAHOO={OTC_AEX:'^AEX',OTC_AS51:'^AXJO',OTC_DJI:'^DJI',OTC_FCHI:'^FCHI',OTC_FTSE:'^FTSE',OTC_GDAXI:'^GDAXI',OTC_HSI:'^HSI',
  OTC_N225:'^N225',OTC_NDX:'^NDX',OTC_SPC:'^GSPC',OTC_SSMI:'^SSMI',OTC_SX5E:'^STOXX50E',
  frxXAUUSD:'GC=F',frxXAGUSD:'SI=F',frxXPTUSD:'PL=F',frxXPDUSD:'PA=F'};
async function yahooH1(sym){
  for(const host of ['https://query1.finance.yahoo.com','https://query2.finance.yahoo.com']){
    try{
      const r=await fetch(`${host}/v8/finance/chart/${encodeURIComponent(sym)}?interval=1h&range=730d&includePrePost=false`,{headers:{'User-Agent':'Mozilla/5.0 SeraIndicator/4.0'},signal:AbortSignal.timeout(30000)});
      if(!r.ok)continue;
      const res=(await r.json())?.chart?.result?.[0],q=res?.indicators?.quote?.[0],ts=res?.timestamp||[];
      if(!q)continue;
      const n=v=>v===null||v===undefined?NaN:Number(v);
      return ts.map((e,i)=>[n(e),n(q.open[i]),n(q.high[i]),n(q.low[i]),n(q.close[i])]).filter(x=>x.every(Number.isFinite)&&x[1]>0&&x[4]>0&&x[2]>=x[3]);
    }catch{/* host suivant */}
  }
  return [];
}
if(SET==='real'){
  for(const row of out.markets){
    if(row.H1.length>=4000)continue;
    const fx=/^frx([A-Z]{3})([A-Z]{3})$/.exec(row.symbol);
    const ysym=YAHOO[row.symbol]||(fx&&!/^X(AU|AG|PT|PD)$/.test(fx[1])?`${fx[1]}${fx[2]}=X`:null);
    if(!ysym)continue;
    const y=await yahooH1(ysym);
    if(y.length>row.H1.length){console.log(`${row.name}: H1 Yahoo ${ysym} ${y.length} (Deriv ${row.H1.length})`);row.H1=y;row.H1_source=`Yahoo ${ysym}`;}
    await sleep(400);
  }
}
mkdirSync('research',{recursive:true});
const FILE=SET==='real'?'research/deriv-real-history.json.gz':'research/deriv-history.json.gz';
writeFileSync(FILE,gzipSync(JSON.stringify(out)));
console.log('saved '+FILE);
process.exit(0);
