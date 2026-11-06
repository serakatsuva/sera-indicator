// Backtest du moteur Swing Crypto (crypto-engine.js) sur l'historique réel Deriv (research-data).
// Usage : node research/crypto_backtest.cjs chemin/deriv-real-history.json.gz [strict|soft]
// Gestion : 50 % à 1R, stop au point d'entrée, reste à 3R ; un trade à la fois ; sans spread ni frais (donc optimiste).
const fs=require("fs"),zlib=require("zlib");
const E=require("../crypto-engine.js");
const file=process.argv[2],strict=(process.argv[3]||"strict")==="strict";
const d=JSON.parse(zlib.gunzipSync(fs.readFileSync(file)).toString());
const rows=[];
for(const m of d.markets){
  if(!/BTC|ETH|LTC|XRP/.test(m.name)||!m.H1||m.H1.length<2400)continue;
  const h=m.H1.map(r=>({time:r[0],open:r[1],high:r[2],low:r[3],close:r[4]}));
  let i=1800,n=0,tot=0,w=0,l=0,tp1=0;const res=[];
  while(i<h.length-2){
    const w1=h.slice(Math.max(0,i-1800),i+1);
    const h4=E.aggregate(w1.slice(w1.length%4),4),d1=E.aggregate(w1.slice(w1.length%24),24);
    const s=E.analyze(w1,h4,d1,{strict});
    if(s.verdict==="ATTENDRE"){i++;continue;}
    const dir=s.verdict==="BUY"?1:-1;let stop=s.sl,got1=false,r=null;
    let j=i+1;
    for(;j<h.length&&j<i+24*10;j++){
      const hi=h[j].high,lo=h[j].low;
      const hitSL=dir>0?lo<=stop:hi>=stop,hit1=dir>0?hi>=s.tp1:lo<=s.tp1,hit3=dir>0?hi>=s.tp3:lo<=s.tp3;
      if(!got1){
        if(hitSL){r=-1;break;}
        if(hit1){got1=true;stop=s.entry;if(hit3){r=.5*1+.5*3;break;}}
      }else{
        if(hit3){r=.5+1.5;break;}
        if(hitSL){r=.5;break;}
      }
    }
    if(r===null){const c=h[Math.min(j,h.length-1)].close;const open=dir*(c-s.entry)/s.risk;r=got1?.5+.5*Math.max(0,open):Math.max(-1,open);}
    res.push(r);i=j+1;
  }
  n=res.length;tot=res.reduce((a,b)=>a+b,0);w=res.filter(x=>x>0).length;l=res.filter(x=>x<0).length;
  rows.push({market:m.name,bars:h.length,trades:n,win_pct:n?+(100*w/Math.max(1,w+l)).toFixed(1):null,avg_r:n?+(tot/n).toFixed(3):null,total_r:+tot.toFixed(2)});
}
console.log(JSON.stringify({rule:strict?"strict":"soft",rows},null,1));
