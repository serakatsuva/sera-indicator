// Analyse Swing Crypto côté serveur (même moteur que le navigateur : crypto-engine.js) -> data/crypto-signals.json.
// Indépendant du moteur principal : en cas d'erreur réseau, le fichier existant est conservé et le script sort sans erreur.
import {createRequire} from "node:module";
import fs from "node:fs";
const require=createRequire(import.meta.url);
const E=require("../crypto-engine.js");
const WS_URL="wss://api.derivws.com/trading/v1/options/ws/public?app_id=1089";
const FALLBACK=[["cryBTCUSD","BTC/USD"],["cryETHUSD","ETH/USD"],["cryLTCUSD","LTC/USD"],["cryXRPUSD","XRP/USD"],["cryBNBUSD","BNB/USD"],["crySOLUSD","SOL/USD"],["cryADAUSD","ADA/USD"],["cryDOGUSD","DOGE/USD"]];

function selfTest(){
  const mk=(n,f)=>Array.from({length:n},(_,i)=>{const c=100+f(i);return{time:i,open:c-.2,high:c+1,low:c-1,close:c};});
  const up=mk(400,i=>i*.5+Math.sin(i/3)*2);
  const r=E.analyze(up,E.aggregate(up,4),E.aggregate(up,24),{strict:true});
  if(!["BUY","SELL","ATTENDRE"].includes(r.verdict))throw new Error("verdict invalide");
  const short=E.analyze(up.slice(0,30),[],[],{});
  if(short.verdict!=="ATTENDRE")throw new Error("historique court doit attendre");
  console.log("Crypto engine self-test passed");
}
if(process.argv.includes("--self-test")){selfTest();process.exit(0);}

const call=(ws,payload,id)=>new Promise((res,rej)=>{
  const t=setTimeout(()=>{ws.removeEventListener("message",on);rej(new Error("timeout"));},15000);
  function on(ev){let m;try{m=JSON.parse(ev.data);}catch{return;}if(m.req_id!==id)return;clearTimeout(t);ws.removeEventListener("message",on);m.error?rej(new Error(m.error.message)):res(m);}
  ws.addEventListener("message",on);ws.send(JSON.stringify({req_id:id,...payload}));
});
const candles=m=>(m.candles||[]).map(c=>({time:c.epoch,open:+c.open,high:+c.high,low:+c.low,close:+c.close}));

try{
  const ws=new WebSocket(WS_URL);
  await new Promise((res,rej)=>{ws.onopen=res;ws.onerror=()=>rej(new Error("ws"));setTimeout(()=>rej(new Error("ws timeout")),15000);});
  let id=1,list=FALLBACK;
  try{
    const a=await call(ws,{active_symbols:"brief",product_type:"basic"},id++);
    const found=(a.active_symbols||[]).filter(s=>s.market==="cryptocurrency"&&/^cry/i.test(s.symbol)).map(s=>[s.symbol,s.display_name||s.symbol]);
    if(found.length)list=found;
  }catch{}
  const markets=[];
  for(const [symbol,name] of list){
    try{
      const get=async(g,count)=>candles(await call(ws,{ticks_history:symbol,style:"candles",granularity:g,count,end:"latest"},id++));
      const h1=await get(3600,500),h4=await get(14400,300),d1=await get(86400,200);
      markets.push({symbol,name,price:h1.length?h1[h1.length-1].close:null,...E.analyze(h1,h4,d1,{strict:true})});
    }catch(e){console.log(`skip ${symbol}: ${e.message}`);}
  }
  ws.close();
  if(!markets.length)throw new Error("aucune crypto analysée");
  fs.writeFileSync("data/crypto-signals.json",JSON.stringify({schema:"sera-crypto-v1",updated_at:new Date().toISOString(),rule:"strict",
    note:"Score moteur non calibré. Mesure : voir research/crypto_backtest.cjs (ETH 1 an : 62 trades, 50 % gagnants, -0,06 R/trade avant frais).",markets},null,1)+"\n");
  console.log(`crypto-signals.json : ${markets.length} marchés, ${markets.filter(m=>m.verdict!=="ATTENDRE").length} swing(s)`);
}catch(e){
  console.log("Crypto non mis à jour :",e.message);
}
