// Sera Drift Playbook — trades only in the direction built into the index generator, after a pull-back.
// Measured on one year of real Deriv H1 history (scripts/backtest-playbook.mjs → data/playbook-stats.json).
//   Boom / GainX           : price drifts DOWN between up-spikes  -> SELL only
//   Crash / PainX          : price drifts UP between down-spikes  -> BUY only
//   Bull Market / Bear Market : built-in up / down drift          -> BUY / SELL only
//   SwitchX / BreakX / TrendX : GainX regime then PainX regime    -> side of the current H1 trend
// SMC confluence (measured, kept because it improves BOTH the training and the test periods): a liquidity sweep in the
// drift direction on one of the last 3 closed H1 candles — the wick takes out the 20-candle low (BUY) / high (SELL) and
// the candle closes back inside. "Precision mode" (default in the EAs) only trades signals with this sweep.
// Support/resistance zones, FVG, order blocks and BOS were measured too and did not improve results: not used.
// Volatility, Step, Jump, FX Vol, SFX Vol, FlipX, PlusX… are random walks: no measured edge, no playbook.
// The same rules are coded in the Weltrade EA (DriftPlaybook) and checked value for value by scripts/qa_swx_engine.py.

export const PLAYBOOKS={
  // rsi: pull-back threshold (BUY when RSI14 < rsi, SELL when RSI14 > 100-rsi); sl: stop in ATR14;
  // tp1/tp2/tp3: targets in R (EA: 50 % closed at TP1 + stop to break-even, stop to TP1 at TP2, rest at TP3).
  bullbear:{label:'Bull / Bear Market',rsi:40,sl:2.5,tp1:0.3,tp2:0.9,tp3:1.5,trend:false},
  spike:{label:'Boom / Crash · GainX / PainX',rsi:45,sl:1.0,tp1:0.3,tp2:0.65,tp3:1.0,trend:true},
  regime:{label:'SwitchX / BreakX / TrendX',rsi:45,sl:1.0,tp1:0.3,tp2:0.65,tp3:1.0,trend:true}
};

// Returns {group, side} for an index name, or null when the generator has no drift to exploit.
export function driftProfile(name){
  const n=String(name||'').toUpperCase().replace(/[ _]/g,'');
  if(n.includes('BULLMARKET'))return {group:'bullbear',side:'BUY'};
  if(n.includes('BEARMARKET'))return {group:'bullbear',side:'SELL'};
  if(n.includes('BOOM')||n.includes('GAINX')&&!n.includes('SWITCHX'))return {group:'spike',side:'SELL'};
  if(n.includes('CRASH')||n.includes('PAINX'))return {group:'spike',side:'BUY'};
  if(n.includes('SWITCHX')||n.includes('BREAKX')||n.includes('TRENDX'))return {group:'regime',side:'TREND'};
  return null;
}

export function emaSeries(values,period){
  const k=2/(period+1),out=new Array(values.length);
  out[0]=values[0];
  for(let i=1;i<values.length;i++)out[i]=k*values[i]+(1-k)*out[i-1];
  return out;
}
export function atrSeries(rows,period=14){
  const out=new Array(rows.length);
  out[0]=rows[0].high-rows[0].low;
  for(let i=1;i<rows.length;i++){
    const r=rows[i],pc=rows[i-1].close;
    const tr=Math.max(r.high-r.low,Math.abs(r.high-pc),Math.abs(r.low-pc));
    out[i]=(out[i-1]*(period-1)+tr)/period;
  }
  return out;
}
export function rsiSeries(closes,period=14){
  const out=new Array(closes.length);let up=1e-9,dn=1e-9;
  out[0]=100-100/(1+up/dn);
  for(let i=1;i<closes.length;i++){
    const d=closes[i]-closes[i-1];
    up=(up*(period-1)+(d>0?d:0))/period;dn=(dn*(period-1)+(d<0?-d:0))/period;
    out[i]=100-100/(1+up/Math.max(dn,1e-12));
  }
  return out;
}

// Liquidity sweep in direction dir (+1 BUY / -1 SELL) on one of the last `bars` candles, against the previous `look` candles.
export function liquiditySweep(rows,dir,bars=3,look=20){
  const i=rows.length-1;
  for(let b=0;b<bars;b++){
    const k=i-b;if(k-look<0)return false;
    let lo=Infinity,hi=-Infinity;
    for(let j=k-look;j<k;j++){if(rows[j].low<lo)lo=rows[j].low;if(rows[j].high>hi)hi=rows[j].high;}
    if(dir>0?(rows[k].low<lo&&rows[k].close>lo):(rows[k].high>hi&&rows[k].close<hi))return true;
  }
  return false;
}

// rows: closed H1 candles (oldest first, >= 210). Returns the playbook state on the last closed candle.
export function driftPlaybook(name,rows){
  const profile=driftProfile(name);
  if(!profile||!Array.isArray(rows)||rows.length<210)return null;
  const p=PLAYBOOKS[profile.group],closes=rows.map(r=>r.close);
  const e20=emaSeries(closes,20),e50=emaSeries(closes,50),atr=atrSeries(rows),rsi=rsiSeries(closes);
  const i=rows.length-1,trendSide=e20[i]>e50[i]?'BUY':e20[i]<e50[i]?'SELL':'NEUTRE';
  const side=profile.side==='TREND'?trendSide:profile.side;
  const dir=side==='BUY'?1:side==='SELL'?-1:0;
  const pullback=dir>0?rsi[i]<p.rsi:dir<0?rsi[i]>100-p.rsi:false;
  const sweep=dir!==0&&liquiditySweep(rows,dir);
  const trendOk=!p.trend||trendSide===side;
  const active=dir!==0&&pullback&&trendOk&&atr[i]>0;
  const entry=closes[i],risk=p.sl*atr[i];
  const at=r=>entry+dir*r*risk;
  const levels=active?{entry,sl:entry-dir*risk,tp1:at(p.tp1),tp2:at(p.tp2),tp3:at(p.tp3),tp4:at(p.tp3+0.05),tp5:at(p.tp3+0.1)}:null;
  return {group:profile.group,label:p.label,side,active,pullback,trend_ok:trendOk,liquidity_sweep:sweep,rsi:rsi[i],atr:atr[i],ema20:e20[i],ema50:e50[i],
    closed_at:rows[i].epoch,price:entry,levels,params:p};
}
