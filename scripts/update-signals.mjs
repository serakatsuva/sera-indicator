import fs from 'node:fs/promises';
import path from 'node:path';

const OPENAI_API_KEY=process.env.OPENAI_API_KEY||'';
const SCREENING_MODEL=process.env.SCREENING_MODEL||'gpt-5.6-luna';
const OUTPUT=path.join(process.cwd(),'data','signals.json');
const DERIV_WS='wss://api.derivws.com/trading/v1/options/ws/public';
const ENGINE_VERSION='Sera Smart Engine v2.0';

const MARKETS=[
  {market:'Boom 300 Index',symbol:'BOOM300N',family:'boom',spikeBias:'UP'},
  {market:'Boom 500 Index',symbol:'BOOM500',family:'boom',spikeBias:'UP'},
  {market:'Boom 1000 Index',symbol:'BOOM1000',family:'boom',spikeBias:'UP'},
  {market:'Crash 300 Index',symbol:'CRASH300N',family:'crash',spikeBias:'DOWN'},
  {market:'Crash 500 Index',symbol:'CRASH500',family:'crash',spikeBias:'DOWN'},
  {market:'Crash 1000 Index',symbol:'CRASH1000',family:'crash',spikeBias:'DOWN'},
  {market:'Volatility 10 Index',symbol:'R_10',family:'volatility',spikeBias:'NONE'},
  {market:'Volatility 25 Index',symbol:'R_25',family:'volatility',spikeBias:'NONE'},
  {market:'Volatility 50 Index',symbol:'R_50',family:'volatility',spikeBias:'NONE'},
  {market:'Volatility 75 Index',symbol:'R_75',family:'volatility',spikeBias:'NONE'},
  {market:'Volatility 100 Index',symbol:'R_100',family:'volatility',spikeBias:'NONE'}
];

const MODES=[
  {id:'day',label:'Day trading',entry:'M15',confirmation:'H1',duration:{range:'1–12 h',validity:'3 bougies M15',reanalysis:'15 min'}},
  {id:'swing',label:'Swing',entry:'H1',confirmation:'H4',duration:{range:'12 h–4 jours',validity:'3 bougies H1',reanalysis:'1 h'}}
];

const clamp=(value,min,max)=>Math.max(min,Math.min(max,value));
const average=values=>values.length?values.reduce((a,b)=>a+b,0)/values.length:0;

function emaValue(values,period){
  const k=2/(period+1);
  return values.reduce((value,price,index)=>index?value+k*(price-value):price,values[0]);
}

function inspectCandles(candles){
  if(!Array.isArray(candles)||candles.length<80)return null;
  const normalized=candles.map(c=>({open:+c.open,high:+c.high,low:+c.low,close:+c.close,epoch:+c.epoch}));
  if(normalized.some(c=>![c.open,c.high,c.low,c.close,c.epoch].every(Number.isFinite)))return null;

  const closes=normalized.map(c=>c.close),highs=normalized.map(c=>c.high),lows=normalized.map(c=>c.low),last=normalized.at(-1);
  const ema20=emaValue(closes,20),ema50=emaValue(closes,50),ema200=emaValue(closes,Math.min(200,closes.length));
  const ema20Prev=emaValue(closes.slice(0,-6),20);

  const gains=[],losses=[];
  for(let i=closes.length-14;i<closes.length;i++){
    const delta=closes[i]-closes[i-1];
    gains.push(Math.max(delta,0));losses.push(Math.max(-delta,0));
  }
  const avgGain=average(gains),avgLoss=average(losses),rsi=avgLoss===0?100:100-(100/(1+avgGain/avgLoss));

  const trSeries=normalized.map((c,i)=>i?Math.max(c.high-c.low,Math.abs(c.high-normalized[i-1].close),Math.abs(c.low-normalized[i-1].close)):c.high-c.low);
  const atr=average(trSeries.slice(-15));
  const recent=normalized.slice(-22,-2),swingHigh=Math.max(...recent.map(c=>c.high)),swingLow=Math.min(...recent.map(c=>c.low));

  const bullish=ema20>ema50&&last.close>ema20;
  const side=bullish?'BUY':'SELL';
  const bos=bullish?last.close>swingHigh:last.close<swingLow;
  const choch=bullish?last.close>Math.max(...highs.slice(-8,-2)):last.close<Math.min(...lows.slice(-8,-2));
  const sweep=bullish?last.low<swingLow&&last.close>swingLow:last.high>swingHigh&&last.close<swingHigh;

  const body=Math.abs(last.close-last.open),range=Math.max(last.high-last.low,.00001),third=normalized.at(-3);
  const impulse=body/range>.55;
  const fvg=bullish?last.low>third.high:last.high<third.low;
  const retest=bullish?last.low<=ema20&&last.close>ema20:last.high>=ema20&&last.close<ema20;
  const orderBlock=bullish
    ?recent.slice(-6).some(c=>c.close<c.open&&(c.high-c.low)>atr)
    :recent.slice(-6).some(c=>c.close>c.open&&(c.high-c.low)>atr);
  const momentum=bullish?rsi>52&&rsi<78:rsi<48&&rsi>22;
  const trendStrong=bullish?ema20>ema50&&ema50>=ema200:ema20<ema50&&ema50<=ema200;

  const lowerWick=Math.min(last.open,last.close)-last.low,upperWick=last.high-Math.max(last.open,last.close);
  const rejection=bullish?(lowerWick/range>.28&&last.close>last.open):(upperWick/range>.28&&last.close<last.open);
  const spikeRisk=body>atr*2.2||range>atr*2.8;

  const emaSpreadAtr=atr>0?Math.abs(ema20-ema50)/atr:0;
  const emaSlopeAtr=atr>0?(ema20-ema20Prev)/atr:0;
  const recentRange=average(normalized.slice(-12).map(c=>c.high-c.low));
  const baselineRange=average(normalized.slice(-48,-12).map(c=>c.high-c.low))||recentRange;
  const volatilityExpansion=baselineRange>0?recentRange/baselineRange:1;
  const compression=volatilityExpansion<.75;

  let regime='TRANSITION';
  if(spikeRisk)regime='SPIKE_RISK';
  else if(trendStrong&&Math.abs(emaSlopeAtr)>.14&&emaSpreadAtr>.38)regime='TRENDING';
  else if(compression)regime='COMPRESSION';
  else if(emaSpreadAtr<.24&&Math.abs(emaSlopeAtr)<.10)regime='RANGE';

  const checks=[trendStrong,momentum,bos||choch,sweep,impulse,fvg,retest,orderBlock,rejection,!spikeRisk];
  const passed=checks.filter(Boolean).length;
  const structureScore=(bos||choch?18:0)+(sweep?11:0)+(retest?11:0)+(orderBlock?8:0)+(fvg?6:0);
  const trendScore=(trendStrong?22:5)+clamp(emaSpreadAtr*9,0,12)+clamp(Math.abs(emaSlopeAtr)*16,0,10);
  const momentumScore=momentum?12:4;
  const executionScore=(impulse?7:2)+(rejection?6:1);
  const regimePenalty=regime==='SPIKE_RISK'?24:regime==='RANGE'?12:regime==='COMPRESSION'?6:0;
  const trendQuality=Math.round(clamp(trendScore+momentumScore+executionScore+structureScore-regimePenalty,0,100));

  return {
    side,confidence:Math.round(clamp(38+passed*4.8+trendQuality*.16,0,96)),passed,bos,choch,sweep,impulse,fvg,retest,
    orderBlock,momentum,rejection,trendStrong,spikeRisk,regime,trendQuality,emaSpreadAtr,emaSlopeAtr,volatilityExpansion,
    compression,ema20,ema50,ema200,rsi,atr,swingHigh,swingLow,closedAt:last.epoch,price:last.close,
    change:((last.close/closes.at(-2))-1)*100
  };
}

function technicalSetup(meta,entryTf,confirmationTf,mode){
  const aligned=entryTf.side===confirmationTf.side;
  const adverseSpikeDirection=(meta.family==='boom'&&entryTf.side==='SELL')||(meta.family==='crash'&&entryTf.side==='BUY');
  const specificGuard=!adverseSpikeDirection||(entryTf.sweep&&(entryTf.bos||entryTf.choch)&&confirmationTf.trendStrong&&entryTf.passed>=7);
  const regimeOk=entryTf.regime==='TRENDING'||(entryTf.regime==='TRANSITION'&&(entryTf.bos||entryTf.choch)&&entryTf.impulse);
  const minimumChecks=(mode.id==='day'?6:5)+(adverseSpikeDirection?1:0);
  const stability=entryTf.trendQuality>=52&&confirmationTf.trendQuality>=60;
  const confirmed=aligned&&confirmationTf.trendStrong&&entryTf.passed>=minimumChecks&&!entryTf.spikeRisk&&specificGuard&&regimeOk&&stability;
  const localScore=Math.round(clamp(entryTf.trendQuality*.47+confirmationTf.trendQuality*.38+entryTf.passed*1.5+(aligned?7:-10)-(adverseSpikeDirection?3:0),0,97));
  const verdict=confirmed?entryTf.side:'ATTENDRE';
  const confidence=confirmed?Math.max(72,localScore):Math.min(74,localScore);

  let levels=null;
  if(verdict!=='ATTENDRE'){
    const entry=entryTf.price,atrMultiplier=mode.id==='day'?1.2:1.5;
    const structural=verdict==='BUY'?Math.min(entry-entryTf.atr*atrMultiplier,entryTf.swingLow):Math.max(entry+entryTf.atr*atrMultiplier,entryTf.swingHigh);
    const distance=Math.max(Math.abs(entry-structural),entryTf.atr),direction=verdict==='BUY'?1:-1;
    levels={entry,sl:structural,tp1:entry+direction*distance*1.5,tp2:entry+direction*distance*2.4,tp3:entry+direction*distance*3.6};
  }

  const reasons=[
    aligned?'Unités de temps alignées':'Désaccord entre unités de temps',
    confirmationTf.trendStrong?'Tendance de confirmation forte':'Tendance de confirmation faible',
    entryTf.bos||entryTf.choch?'Structure cassée/retournée':'Structure non confirmée',
    entryTf.sweep?'Liquidité balayée':'Pas de sweep de liquidité',
    entryTf.retest?'Retest présent':'Retest absent',
    entryTf.regime==='TRENDING'?'Régime directionnel':'Régime '+entryTf.regime
  ];

  return {
    ...meta,mode:mode.id,mode_label:mode.label,timeframes:[mode.entry,mode.confirmation],duration:mode.duration,price:entryTf.price,
    technical_verdict:verdict,technical_confidence:confidence,levels,entry_tf:entryTf,confirmation_tf:confirmationTf,
    intelligence:{engine:ENGINE_VERSION,local_score:localScore,regime:entryTf.regime,confirmation_regime:confirmationTf.regime,aligned,stability,adverse_spike_direction:adverseSpikeDirection,reasons},
    risk:{risk_reward:3.6,spike_risk:entryTf.spikeRisk,specific_guard:specificGuard,source:'Deriv public WebSocket'}
  };
}

async function fetchAllCandles(){
  return new Promise((resolve,reject)=>{
    const ws=new WebSocket(DERIV_WS),requests=new Map(),received=new Map();
    let settled=false,reqId=100;
    const finish=error=>{
      if(settled)return; settled=true; clearTimeout(timer);
      try{ws.close();}catch{}
      if(error)reject(error);else resolve(received);
    };
    const timer=setTimeout(()=>finish(new Error(`Deriv timeout: ${received.size}/${MARKETS.length*3} candle sets`)),45000);
    ws.addEventListener('open',()=>{
      for(const market of MARKETS){
        for(const [timeframe,granularity] of [['M15',900],['H1',3600],['H4',14400]]){
          reqId+=1; requests.set(reqId,{...market,timeframe});
          ws.send(JSON.stringify({ticks_history:market.symbol,style:'candles',granularity,count:240,end:'latest',adjust_start_time:1,req_id:reqId}));
        }
      }
    });
    ws.addEventListener('message',event=>{
      let message; try{message=JSON.parse(String(event.data));}catch{return;}
      if(message.error||message.errors)return finish(new Error(`Deriv rejected a candle request: ${message.error?.message||message.errors?.[0]?.message||'unknown error'}`));
      if(!message.candles)return;
      const key=Number(message.req_id??message.echo_req?.req_id),request=requests.get(key); if(!request)return;
      received.set(`${request.symbol}:${request.timeframe}`,message.candles.map(c=>({open:+c.open,high:+c.high,low:+c.low,close:+c.close,epoch:+c.epoch})));
      if(received.size===MARKETS.length*3)finish();
    });
    ws.addEventListener('error',()=>finish(new Error('Deriv WebSocket connection failed')));
  });
}

const auditItem={type:'object',additionalProperties:false,properties:{
  id:{type:'string'},verdict:{type:'string',enum:['BUY','SELL','ATTENDRE']},confidence:{type:'number',minimum:0,maximum:100},
  summary:{type:'string'},confirmations:{type:'array',items:{type:'string'}},contradictions:{type:'array',items:{type:'string'}},
  risk:{type:'string'},needs_expert_review:{type:'boolean'}
},required:['id','verdict','confidence','summary','confirmations','contradictions','risk','needs_expert_review']};
const auditSchema={type:'object',additionalProperties:false,properties:{markets:{type:'array',items:auditItem}},required:['markets']};

function extractOutputText(response){
  if(response?.output_text)return response.output_text;
  for(const item of response?.output||[])if(item?.type==='message')for(const content of item?.content||[])if(content?.type==='output_text'&&content.text)return content.text;
  throw new Error('OpenAI returned no output_text');
}

async function callOpenAI(body){
  const res=await fetch('https://api.openai.com/v1/responses',{method:'POST',headers:{Authorization:`Bearer ${OPENAI_API_KEY}`,'Content-Type':'application/json'},body:JSON.stringify(body)});
  const raw=await res.text(); let response={};
  try{response=raw?JSON.parse(raw):{};}catch{throw new Error(`OpenAI returned unreadable JSON (${res.status})`);}
  if(!res.ok)throw new Error(`OpenAI API ${res.status}: ${response?.error?.code||response?.error?.type||'request_failed'}`);
  if(response.status==='incomplete')throw new Error(`OpenAI incomplete response: ${response.incomplete_details?.reason||'unknown'}`);
  return response;
}

function publicSetup(setup){
  const clean=value=>({
    side:value.side,confidence:value.confidence,passed:value.passed,bos:value.bos,choch:value.choch,sweep:value.sweep,impulse:value.impulse,
    fvg:value.fvg,retest:value.retest,orderBlock:value.orderBlock,momentum:value.momentum,rejection:value.rejection,trendStrong:value.trendStrong,
    spikeRisk:value.spikeRisk,regime:value.regime,trendQuality:value.trendQuality,emaSpreadAtr:value.emaSpreadAtr,emaSlopeAtr:value.emaSlopeAtr,
    volatilityExpansion:value.volatilityExpansion,ema20:value.ema20,ema50:value.ema50,ema200:value.ema200,rsi:value.rsi,atr:value.atr,
    swingHigh:value.swingHigh,swingLow:value.swingLow,closedAt:value.closedAt,price:value.price,change:value.change
  });
  return {
    id:`${setup.symbol}:${setup.mode}`,market:setup.market,symbol:setup.symbol,family:setup.family,spikeBias:setup.spikeBias,mode:setup.mode,
    mode_label:setup.mode_label,timeframes:setup.timeframes,duration:setup.duration,price:setup.price,technical_verdict:setup.technical_verdict,
    technical_confidence:setup.technical_confidence,levels:setup.levels,entry_tf:clean(setup.entry_tf),confirmation_tf:clean(setup.confirmation_tf),
    intelligence:setup.intelligence,trend_memory:setup.trend_memory,risk:setup.risk
  };
}

async function auditMarkets(model,setups){
  const instructions=`Tu es Luna, auditeur final de Sera Smart Engine pour les indices synthétiques Deriv.
Le moteur local a déjà analysé tendance, régime de marché, structure, liquidité, retest, momentum, ATR, risque de spike, mémoire de tendance et particularités Boom/Crash/Volatility.
Ton rôle est de CHALLENGER le setup, pas de fabriquer un trade.
Règles strictes:
1. Ne transforme jamais ATTENDRE en BUY/SELL.
2. N'inverse jamais le sens technique proposé.
3. Confirme BUY/SELL seulement si H1/H4 (ou M15/H1) restent cohérents, le régime n'est pas RANGE/SPIKE_RISK, le risque de spike est acceptable, et la mémoire de tendance ne montre pas un flip fragile.
4. Pour Boom, sois plus exigeant sur un SELL; pour Crash, sois plus exigeant sur un BUY.
5. Si structure, liquidité, momentum, régime ou mémoire se contredisent, retourne ATTENDRE.
6. La confiance doit refléter la qualité du setup, jamais une garantie de gain.`;
  const response=await callOpenAI({
    model,reasoning:{effort:'medium'},store:false,instructions,
    input:JSON.stringify({broker:'Deriv',market_family:'Synthetic Indices',engine:ENGINE_VERSION,generated_at:new Date().toISOString(),execution:'decision_support',markets:setups.map(publicSetup)}),
    text:{format:{type:'json_schema',name:'sera_smart_engine_luna_audit',strict:true,schema:auditSchema}}
  });
  const parsed=JSON.parse(extractOutputText(response));
  return {results:parsed.markets||[],response_id:response.id||null,usage:response.usage||null};
}

function attachTrendMemory(setup,previous){
  const id=`${setup.symbol}:${setup.mode}`;
  const old=previous?.markets?.find(item=>item.id===id);
  const currentBias=setup.entry_tf.side===setup.confirmation_tf.side?setup.entry_tf.side:'NEUTRE';
  const previousBias=old?.timing?.bias||old?.trend_memory?.current_bias||'NEUTRE';
  const persistence=Boolean(old&&currentBias!=='NEUTRE'&&currentBias===previousBias);
  const flip=Boolean(old&&previousBias!=='NEUTRE'&&currentBias!=='NEUTRE'&&currentBias!==previousBias);
  const previousFinal=old?.final_verdict||'ATTENDRE';
  const maturityBonus=persistence?5:0,flipPenalty=flip?10:0;
  const candidateScore=Math.round(clamp(setup.technical_confidence+maturityBonus+(setup.entry_tf.regime==='TRENDING'?4:0)-flipPenalty,0,100));
  return {...setup,trend_memory:{previous_bias:previousBias,current_bias:currentBias,previous_final:previousFinal,persistence,flip,candidate_score: candidateScore}};
}

function dynamicReadiness(setup,audit,agreed){
  const entry=setup.entry_tf,confirmation=setup.confirmation_tf,mem=setup.trend_memory||{};
  const aiConfidence=clamp(Number(audit.confidence)||0,0,100);
  const alignment=entry.side===confirmation.side?8:-12;
  const structure=(entry.bos||entry.choch?6:0)+(entry.retest?5:0)+(entry.sweep?4:0)+(entry.rejection?3:0);
  const trend=(entry.trendStrong?5:-4)+(confirmation.trendStrong?8:-7);
  const regime=entry.regime==='TRENDING'?7:entry.regime==='TRANSITION'?1:-8;
  const memory=(mem.persistence?5:0)-(mem.flip?10:0);
  const contradictionPenalty=(audit.contradictions?.length||0)*4+(audit.needs_expert_review?8:0)+(entry.spikeRisk?12:0);
  const confirmationBonus=Math.min(8,(audit.confirmations?.length||0)*2);
  const base=setup.intelligence.local_score*.42+aiConfidence*.38+entry.passed*1.3;
  return Math.round(clamp(base+alignment+structure+trend+regime+memory+confirmationBonus-contradictionPenalty,agreed?75:18,agreed?96:74));
}

function estimateTiming(setup,finalVerdict,finalConfidence){
  const entry=setup.entry_tf,confirmation=setup.confirmation_tf;
  const aligned=entry.side===confirmation.side,bias=aligned?entry.side:'NEUTRE';
  const activeSide=finalVerdict!=='ATTENDRE'?finalVerdict:bias;
  const regimeFactor=entry.regime==='TRENDING'?1.12:entry.regime==='COMPRESSION'?.78:.92;
  const rate=Math.max(entry.atr*.30,entry.atr*(.45+entry.passed*.04+(confirmation.trendStrong?.12:0))*regimeFactor);
  let minHours,maxHours,tp1Hours=null,tp2Hours=null,tp3Hours=null;
  if(finalVerdict!=='ATTENDRE'&&setup.levels){
    const eta=target=>Math.max(1,Math.ceil(Math.abs(target-setup.levels.entry)/rate));
    tp1Hours=eta(setup.levels.tp1);tp2Hours=eta(setup.levels.tp2);tp3Hours=eta(setup.levels.tp3);
    minHours=Math.max(1,Math.floor(tp1Hours*.7));maxHours=Math.min(96,Math.max(minHours+1,Math.ceil(tp3Hours*1.35)));
  }else if(finalConfidence>=65){minHours=3;maxHours=12;}
  else if(finalConfidence>=45){minHours=6;maxHours=24;}
  else{minHours=12;maxHours=48;}
  const style=maxHours<=6?'COURT':maxHours<=24?'MOYEN':'LONG',expiresInHours=style==='COURT'?3:style==='MOYEN'?8:16;
  return {bias,side:finalVerdict!=='ATTENDRE'?finalVerdict:activeSide,position_style:style,duration_min_hours:minHours,duration_max_hours:maxHours,tp1_hours:tp1Hours,tp2_hours:tp2Hours,tp3_hours:tp3Hours,expires_in_hours:expiresInHours,recheck_hours:setup.mode==='swing'?1:.25,is_confirmed:finalVerdict!=='ATTENDRE',basis:'ATR, régime, mémoire de tendance, structure et force multi-timeframe'};
}

function finalize(setup,luna){
  const audit=luna||{verdict:'ATTENDRE',confidence:0,summary:'Luna indisponible: décision autonome soumise aux seuils renforcés du Smart Engine.',confirmations:[],contradictions:[],risk:'Contrôle local renforcé',needs_expert_review:false};
  const aiConfidence=Number(audit.confidence)||0;
  const lunaAgreed=Boolean(luna)&&setup.technical_verdict!=='ATTENDRE'&&audit.verdict===setup.technical_verdict&&aiConfidence>=75&&!audit.needs_expert_review&&!setup.trend_memory?.flip;

  const localThreshold=setup.mode==='swing'?86:88;
  const localAutonomous=!luna
    &&setup.technical_verdict!=='ATTENDRE'
    &&setup.intelligence.local_score>=localThreshold
    &&setup.trend_memory?.candidate_score>=92
    &&setup.entry_tf.trendQuality>=80
    &&setup.confirmation_tf.trendQuality>=80
    &&setup.entry_tf.regime==='TRENDING'
    &&setup.confirmation_tf.regime==='TRENDING'
    &&setup.intelligence.aligned
    &&setup.intelligence.stability
    &&!setup.entry_tf.spikeRisk
    &&!setup.trend_memory?.flip
    &&setup.entry_tf.passed>=6
    &&(!setup.intelligence.adverse_spike_direction||setup.entry_tf.sweep);

  const confirmed=lunaAgreed||localAutonomous;
  const finalVerdict=confirmed?setup.technical_verdict:'ATTENDRE';
  const finalConfidence=localAutonomous
    ?Math.round(clamp(setup.intelligence.local_score+(setup.trend_memory?.persistence?2:0),75,94))
    :dynamicReadiness(setup,audit,lunaAgreed);
  const timing=estimateTiming(setup,finalVerdict,finalConfidence);
  const confirmationSource=lunaAgreed?'luna_audited':localAutonomous?'smart_local':'none';
  const aiTier=luna?`${SCREENING_MODEL} · audit final`:localAutonomous?`${ENGINE_VERSION} · confirmation autonome renforcée`:'Sera Smart Engine local · setup non confirmé';
  const summary=luna?audit.summary:localAutonomous
    ?`Signal confirmé localement par ${ENGINE_VERSION}: régime directionnel fort, alignement multi-timeframe, qualité de tendance élevée et mémoire stable.`
    :audit.summary;
  const confirmations=luna?(audit.confirmations||[]):localAutonomous?[
    'Régime directionnel confirmé sur les deux horizons',
    'Alignement multi-timeframe stable',
    'Score local et qualité de tendance au-dessus du seuil renforcé',
    'Aucun flip récent ni risque de spike détecté'
  ]:[];
  return {...publicSetup(setup),levels:finalVerdict==='ATTENDRE'?null:setup.levels,final_verdict:finalVerdict,final_confidence:finalConfidence,timing,confirmation_source:confirmationSource,score_type:confirmed?'signal_confidence':'setup_readiness',ai_verdict:luna?audit.verdict:'ATTENDRE',ai_confidence:aiConfidence,ai_summary:summary,ai_confirmations:confirmations,ai_contradictions:audit.contradictions||[],ai_risk:audit.risk,needs_expert_review:Boolean(luna&&audit.needs_expert_review),ai_tier:aiTier};
}

async function selfTest(){
  const candles=Array.from({length:240},(_,i)=>{
    const base=1000+i*.8,open=base+Math.sin(i/4)*2,close=base+1+Math.sin(i/4)*2;
    return{open,high:Math.max(open,close)+3,low:Math.min(open,close)-3,close,epoch:1700000000+i*900};
  });
  const result=inspectCandles(candles);
  if(!result||!Number.isFinite(result.atr)||!['BUY','SELL'].includes(result.side)||!result.regime)throw new Error('Smart technical engine self-test failed');
  const setup=technicalSetup(MARKETS[0],result,{...result,trendStrong:true,trendQuality:Math.max(70,result.trendQuality),regime:'TRENDING'},MODES[0]);
  if(!setup.entry_tf||!setup.confirmation_tf||!setup.intelligence)throw new Error('Intelligence assembly failed');
  console.log(ENGINE_VERSION+' self-test passed.');
}

async function readPreviousPayload(){
  try{return JSON.parse(await fs.readFile(OUTPUT,'utf8'));}catch{return null;}
}

function reusableAudit(previous,setup){
  const id=`${setup.symbol}:${setup.mode}`,row=previous?.markets?.find(item=>item.id===id);
  if(!row||row.entry_tf?.closedAt!==setup.entry_tf.closedAt||row.confirmation_tf?.closedAt!==setup.confirmation_tf.closedAt)return null;
  if(!row.ai_verdict||String(row.ai_tier||'').includes('Luna non appelée'))return null;
  return {id,verdict:row.ai_verdict,confidence:row.ai_confidence,summary:row.ai_summary,confirmations:row.ai_confirmations||[],contradictions:row.ai_contradictions||[],risk:row.ai_risk||'',needs_expert_review:Boolean(row.needs_expert_review)};
}

async function main(){
  if(process.argv.includes('--self-test'))return selfTest();
  const previous=await readPreviousPayload(),candles=await fetchAllCandles();

  const rawSetups=MARKETS.flatMap(meta=>MODES.map(mode=>{
    const entry=inspectCandles(candles.get(`${meta.symbol}:${mode.entry}`)),confirmation=inspectCandles(candles.get(`${meta.symbol}:${mode.confirmation}`));
    if(!entry||!confirmation)throw new Error(`Insufficient ${mode.id} candles for ${meta.market}`);
    return technicalSetup(meta,entry,confirmation,mode);
  }));
  const setups=rawSetups.map(setup=>attachTrendMemory(setup,previous));
  const setupId=setup=>`${setup.symbol}:${setup.mode}`;

  const technicalCandidates=setups
    .filter(setup=>setup.technical_verdict!=='ATTENDRE'&&setup.technical_confidence>=72&&setup.intelligence.local_score>=68&&!setup.entry_tf.spikeRisk&&!setup.trend_memory.flip)
    .sort((a,b)=>(b.trend_memory?.candidate_score||0)-(a.trend_memory?.candidate_score||0))
    .slice(0,5);

  const reused=new Map(),newCandidates=[];
  for(const setup of technicalCandidates){
    const audit=reusableAudit(previous,setup);
    if(audit)reused.set(setupId(setup),audit);else newCandidates.push(setup);
  }

  let luna={results:[],response_id:null,usage:null,error:null};
  if(newCandidates.length&&OPENAI_API_KEY){
    try{luna=await auditMarkets(SCREENING_MODEL,newCandidates);}
    catch(error){luna.error=error instanceof Error?error.message:String(error);console.warn(`OpenAI Luna audit skipped: ${luna.error}`);}
  }else if(newCandidates.length){luna.error='OPENAI_API_KEY unavailable';}

  const lunaMap=new Map([...reused,...luna.results.map(row=>[String(row.id),row])]);
  const markets=setups.map(setup=>finalize(setup,lunaMap.get(setupId(setup))));
  const aiCalls=luna.response_id?1:0;

  const payload={
    ok:true,status:aiCalls||reused.size?'ai_analyzed':markets.some(m=>m.confirmation_source==='smart_local')?'smart_local':'technical_only',source_broker:'Deriv',source:'Deriv WebSocket · M15/H1/H4',
    updated_at:new Date().toISOString(),engine_version:ENGINE_VERSION,
    model:aiCalls||reused.size?`${ENGINE_VERSION} + ${SCREENING_MODEL}`:`${ENGINE_VERSION} · local`,
    screening_model:SCREENING_MODEL,deep_model:null,markets_count:markets.length,technical_candidates:technicalCandidates.length,
    ai_candidates:newCandidates.length,ai_calls:aiCalls,ai_attempted:newCandidates.length?1:0,ai_error:luna.error||null,
    cached_ai_validations:reused.size,confirmed_signals:markets.filter(m=>m.final_verdict!=='ATTENDRE').length,markets,
    openai_response_ids:{screening:luna.response_id},usage:{screening:luna.usage},
    safety:'Sera Smart Engine analyse localement tous les marchés. Sans Luna, seuls les setups dépassant des seuils autonomes renforcés peuvent être confirmés. Aucun score ne garantit un gain.'
  };

  await fs.mkdir(path.dirname(OUTPUT),{recursive:true});
  await fs.writeFile(OUTPUT,JSON.stringify(payload,null,2));
  console.log(`Wrote ${markets.length} analyses; ${technicalCandidates.length} smart candidates; ${aiCalls} Luna call(s); ${payload.confirmed_signals} confirmed signals.`);
}

main().catch(error=>{console.error(error instanceof Error?error.message:error);process.exit(1);});
