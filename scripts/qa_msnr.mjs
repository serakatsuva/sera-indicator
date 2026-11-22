import {msnrPositions,structureTrend,atrOf} from './msnr-engine.mjs';
function gen(n,seed,step,base=1000,vol=6){
  let x=seed,p=base;const out=[];
  const r=()=>{x=(x*1664525+1013904223)%4294967296;return x/4294967296-.5;};
  for(let i=0;i<n;i++){
    const open=p,drift=Math.sin(i/9)*vol*.6+step,close=open+drift+r()*vol;
    out.push({epoch:i*900,open,close,high:Math.max(open,close)+Math.abs(r())*vol*.5,low:Math.min(open,close)-Math.abs(r())*vol*.5});p=close;
  }return out;
}
let total=0;
for(const seed of [1,2,3,4,5,6,7,8]){
  const c={D1:gen(200,seed,.8,1000,14),H4:gen(300,seed+10,.5,1000,10),H1:gen(300,seed+20,.3,1000,6),M15:gen(300,seed+30,.2,1000,3)};
  const pos=msnrPositions(c);total+=pos.length;
  for(const p of pos){
    const d=p.side==='BUY'?1:-1;
    if(!((p.tp1-p.entry)*d>0&&(p.entry-p.sl)*d>0&&p.tp2*d>=p.tp1*d))throw new Error('bad levels '+JSON.stringify(p));
    if(p.quality<0||p.quality>95)throw new Error('quality');
  }
}
console.log('ok positions',total);
