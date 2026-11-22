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
  const c={D1:gen(200,seed,.8,1000,14),H4:gen(300,seed+10,.5,1000,10),H1:gen(300,seed+20,.3,1000,6),M15:gen(300,seed+30,.2,1000,3),
    W1:gen(120,seed+40,1.2,1000,25),M30:gen(300,seed+50,.15,1000,2),M5:gen(400,seed+60,.1,1000,1),M1:gen(400,seed+70,.05,1000,.5)};
  const pos=msnrPositions(c);total+=pos.length;
  for(const p of pos){
    const d=p.side==='BUY'?1:-1;
    if(!((p.tp1-p.entry)*d>0&&(p.entry-p.sl)*d>0&&p.tp2*d>=p.tp1*d))throw new Error('bad levels '+JSON.stringify(p));
    if(p.quality<0||p.quality>95)throw new Error('quality');
  }
}
const modes=new Set();
for(const seed of [1,2,3,4,5,6,7,8,9,10,11,12]){const c={D1:gen(200,seed,.8,1000,14),H4:gen(300,seed+10,.5,1000,10),H1:gen(300,seed+20,.3,1000,6),M15:gen(300,seed+30,.2,1000,3),W1:gen(120,seed+40,1.2,1000,25),M30:gen(300,seed+50,.15,1000,2),M5:gen(400,seed+60,.1,1000,1),M1:gen(400,seed+70,.05,1000,.5)};for(const p of msnrPositions(c))modes.add(p.mode+':'+p.tf);}
console.log('ok positions',total,[...modes].join(' '));

import {positionPhase} from './position-phase.mjs';
const sell={side:'SELL',order:'LIMIT',entry:100,zone_min:99,zone_max:101,zone_tol:.5,sl:110,tp1:80,tp2:60};
const buy={side:'BUY',order:'LIMIT',entry:100,zone_min:99,zone_max:101,zone_tol:.5,sl:90,tp1:120,tp2:140};
const cases=[[sell,100,'NOW'],[sell,95,'PREP'],[sell,80.5,'UPCOMING'],[sell,111,'PASSED'],[sell,79,'PASSED'],[sell,105,'PASSED'],
  [buy,100.2,'NOW'],[buy,105,'PREP'],[buy,119,'UPCOMING'],[buy,89,'PASSED'],[buy,121,'PASSED'],[buy,95,'PASSED'],
  [{...buy,order:'STOP',entry:105,zone_min:105,zone_max:105},103,'PREP'],[{...buy,order:'STOP',entry:105,zone_min:105,zone_max:105},112,'PASSED'],[{...buy,order:'STOP',entry:105,zone_min:105,zone_max:105},108,'NOW']];
for(const [p,px,want] of cases){const got=positionPhase(p,px);if(got!==want)throw new Error(`phase ${p.side} ${p.order} @${px}: ${got} != ${want}`);}
console.log('ok phases');
