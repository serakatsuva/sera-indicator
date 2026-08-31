import fs from 'node:fs/promises';
import path from 'node:path';

const OPENAI_API_KEY=process.env.OPENAI_API_KEY||'';
const SCREENING_MODEL=process.env.SCREENING_MODEL||'gpt-5.6-luna';
const DEEP_MODEL=process.env.DEEP_MODEL||'gpt-5.6-sol';
const OUTPUT=path.join(process.cwd(),'data','signals.json');
const DERIV_WS='wss://api.derivws.com/trading/v1/options/ws/public';
const MARKETS=[
  {market:'Boom 300 Index',symbol:'BOOM300N'},
  {market:'Boom 500 Index',symbol:'BOOM500'},
  {market:'Boom 1000 Index',symbol:'BOOM1000'},
  {market:'Crash 300 Index',symbol:'CRASH300N'},
  {market:'Crash 500 Index',symbol:'CRASH500'},
  {market:'Crash 1000 Index',symbol:'CRASH1000'},
  {market:'Volatility 10 Index',symbol:'R_10'},
  {market:'Volatility 25 Index',symbol:'R_25'},
  {market:'Volatility 50 Index',symbol:'R_50'},
  {market:'Volatility 75 Index',symbol:'R_75'},
  {market:'Volatility 100 Index',symbol:'R_100'}
];
const MODES=[
  {id:'day',label:'Day trading',entry:'M15',confirmation:'H1',entryGranularity:900,confirmationGranularity:3600,duration:{range:'1–12 h',validity:'3 bougies M15',reanalysis:'15 min'}},
  {id:'swing',label:'Swing',entry:'H1',confirmation:'H4',entryGranularity:3600,confirmationGranularity:14400,duration:{range:'12 h–4 jours',validity:'3 bougies H1',reanalysis:'1 h'}}
];

function inspectCandles(candles){
  if(!Array.isArray(candles)||candles.length<60)return null;
  const normalized=candles.map(c=>({open:+c.open,high:+c.high,low:+c.low,close:+c.close,epoch:+c.epoch}));
  if(normalized.some(c=>![c.open,c.high,c.low,c.close,c.epoch].every(Number.isFinite)))return null;
  const closes=normalized.map(c=>c.close),highs=normalized.map(c=>c.high),lows=normalized.map(c=>c.low),last=normalized.at(-1);
  const ema=period=>{const k=2/(period+1);return closes.reduce((value,price,index)=>index?value+k*(price-value):price,closes[0]);};
  const ema20=ema(20),ema50=ema(50),ema200=ema(Math.min(200,closes.length));
  const gains=[],losses=[];
  for(let i=closes.length-14;i<closes.length;i++){const delta=closes[i]-closes[i-1];gains.push(Math.max(delta,0));losses.push(Math.max(-delta,0));}
  const avgGain=gains.reduce((a,b)=>a+b,0)/14,avgLoss=losses.reduce((a,b)=>a+b,0)/14,rsi=avgLoss===0?100:100-(100/(1+avgGain/avgLoss));
  const trs=normalized.slice(-15).map((c,i,a)=>i?Math.max(c.high-c.low,Math.abs(c.high-a[i-1].close),Math.abs(c.low-a[i-1].close)):c.high-c.low),atr=trs.reduce((a,b)=>a+b,0)/trs.length;
  const recent=normalized.slice(-22,-2),swingHigh=Math.max(...recent.map(c=>c.high)),swingLow=Math.min(...recent.map(c=>c.low));
  const bullish=ema20>ema50&&last.close>ema20,side=bullish?'BUY':'SELL';
  const bos=bullish?last.close>swingHigh:last.close<swingLow,choch=bullish?last.close>Math.max(...highs.slice(-8,-2)):last.close<Math.min(...lows.slice(-8,-2));
  const sweep=bullish?last.low<swingLow&&last.close>swingLow:last.high>swingHigh&&last.close<swingHigh;
  const body=Math.abs(last.close-last.open),range=Math.max(last.high-last.low,.00001),impulse=body/range>.55,third=normalized.at(-3);
  const fvg=bullish?last.low>third.high:last.high<third.low,retest=bullish?last.low<=ema20&&last.close>ema20:last.high>=ema20&&last.close<ema20;
  const orderBlock=bullish?recent.slice(-6).some(c=>c.close<c.open&&(c.high-c.low)>atr):recent.slice(-6).some(c=>c.close>c.open&&(c.high-c.low)>atr);
  const momentum=bullish?rsi>52&&rsi<78:rsi<48&&rsi>22,trendStrong=bullish?ema20>ema50&&ema50>=ema200:ema20<ema50&&ema50<=ema200;
  const spikeRisk=body>atr*2.2||(last.high-last.low)>atr*2.8,checks=[trendStrong,momentum,bos||choch,sweep,impulse,fvg,retest,orderBlock,!spikeRisk],passed=checks.filter(Boolean).length;
  return {side,confidence:Math.min(95,Math.round(42+passed*5.5)),passed,bos,choch,sweep,impulse,fvg,retest,orderBlock,momentum,trendStrong,spikeRisk,ema20,ema50,ema200,rsi,atr,swingHigh,swingLow,closedAt:last.epoch,price:last.close,change:((last.close/closes.at(-2))-1)*100};
}

function technicalSetup(meta,entryTf,confirmationTf,mode){
  const aligned=entryTf.side===confirmationTf.side;
  const guard=meta.market.startsWith('Boom')?entryTf.side!=='SELL'||entryTf.sweep:meta.market.startsWith('Crash')?entryTf.side!=='BUY'||entryTf.sweep:true;
  const minimumChecks=mode.id==='day'?6:5;
  const confirmed=aligned&&confirmationTf.trendStrong&&entryTf.passed>=minimumChecks&&!entryTf.spikeRisk&&guard;
  const verdict=confirmed?entryTf.side:'ATTENDRE';
  const confidence=confirmed?Math.round(entryTf.confidence*.58+confirmationTf.confidence*.42):Math.min(74,Math.round((entryTf.confidence+confirmationTf.confidence)/2));
  let levels=null;
  if(verdict!=='ATTENDRE'){
    const entry=entryTf.price,atrMultiplier=mode.id==='day'?1.2:1.5,structural=verdict==='BUY'?Math.min(entry-entryTf.atr*atrMultiplier,entryTf.swingLow):Math.max(entry+entryTf.atr*atrMultiplier,entryTf.swingHigh),distance=Math.max(Math.abs(entry-structural),entryTf.atr),direction=verdict==='BUY'?1:-1;
    levels={entry,sl:structural,tp1:entry+direction*distance*1.5,tp2:entry+direction*distance*2.4,tp3:entry+direction*distance*3.6};
  }
  return {...meta,mode:mode.id,mode_label:mode.label,timeframes:[mode.entry,mode.confirmation],duration:mode.duration,price:entryTf.price,technical_verdict:verdict,technical_confidence:confidence,levels,entry_tf:entryTf,confirmation_tf:confirmationTf,risk:{risk_reward:3.6,spike_risk:entryTf.spikeRisk,boom_crash_guard:guard,source:'Deriv public WebSocket'}};
}

async function fetchAllCandles(){
  return new Promise((resolve,reject)=>{
    const ws=new WebSocket(DERIV_WS),requests=new Map(),received=new Map();
    let settled=false,reqId=100;
    const finish=error=>{
      if(settled)return;
      settled=true;
      clearTimeout(timer);
      try{ws.close();}catch{}
      if(error)reject(error);else resolve(received);
    };
    const timer=setTimeout(()=>finish(new Error(`Deriv timeout: ${received.size}/${MARKETS.length*2} candle sets`)),45000);
    ws.addEventListener('open',()=>{
      for(const market of MARKETS){
        for(const [timeframe,granularity] of [['M15',900],['H1',3600],['H4',14400]]){
          reqId+=1;
          requests.set(reqId,{...market,timeframe});
          ws.send(JSON.stringify({ticks_history:market.symbol,style:'candles',granularity,count:240,end:'latest',adjust_start_time:1,req_id:reqId}));
        }
      }
    });
    ws.addEventListener('message',event=>{
      let message;
      try{message=JSON.parse(String(event.data));}catch{return;}
      if(message.error||message.errors)return finish(new Error(`Deriv rejected a candle request: ${message.error?.message||message.errors?.[0]?.message||'unknown error'}`));
      if(!message.candles)return;
      const key=Number(message.req_id??message.echo_req?.req_id),request=requests.get(key);
      if(!request)return;
      const candles=message.candles.map(c=>({open:+c.open,high:+c.high,low:+c.low,close:+c.close,epoch:+c.epoch}));
      received.set(`${request.symbol}:${request.timeframe}`,candles);
      if(received.size===MARKETS.length*3)finish();
    });
    ws.addEventListener('error',()=>finish(new Error('Deriv WebSocket connection failed')));
  });
}

const auditItem={type:'object',additionalProperties:false,properties:{id:{type:'string'},verdict:{type:'string',enum:['BUY','SELL','ATTENDRE']},confidence:{type:'number',minimum:0,maximum:100},summary:{type:'string'},confirmations:{type:'array',items:{type:'string'}},contradictions:{type:'array',items:{type:'string'}},risk:{type:'string'},needs_expert_review:{type:'boolean'}},required:['id','verdict','confidence','summary','confirmations','contradictions','risk','needs_expert_review']};
const auditSchema={type:'object',additionalProperties:false,properties:{markets:{type:'array',items:auditItem}},required:['markets']};

function extractOutputText(response){if(response?.output_text)return response.output_text;for(const item of response?.output||[]){if(item?.type!=='message')continue;for(const content of item?.content||[]){if(content?.type==='output_text'&&content.text)return content.text;}}throw new Error('OpenAI returned no output_text');}
async function callOpenAI(body){const res=await fetch('https://api.openai.com/v1/responses',{method:'POST',headers:{Authorization:`Bearer ${OPENAI_API_KEY}`,'Content-Type':'application/json'},body:JSON.stringify(body)});const raw=await res.text();let response={};try{response=raw?JSON.parse(raw):{};}catch{throw new Error(`OpenAI returned unreadable JSON (${res.status})`);}if(!res.ok)throw new Error(`OpenAI API ${res.status}: ${response?.error?.code||response?.error?.type||'request_failed'}`);if(response.status==='incomplete')throw new Error(`OpenAI incomplete response: ${response.incomplete_details?.reason||'unknown'}`);return response;}
function publicSetup(setup){const clean=value=>({side:value.side,confidence:value.confidence,passed:value.passed,bos:value.bos,choch:value.choch,sweep:value.sweep,impulse:value.impulse,fvg:value.fvg,retest:value.retest,orderBlock:value.orderBlock,momentum:value.momentum,trendStrong:value.trendStrong,spikeRisk:value.spikeRisk,ema20:value.ema20,ema50:value.ema50,ema200:value.ema200,rsi:value.rsi,atr:value.atr,swingHigh:value.swingHigh,swingLow:value.swingLow,closedAt:value.closedAt,price:value.price,change:value.change});return {id:`${setup.symbol}:${setup.mode}`,market:setup.market,symbol:setup.symbol,mode:setup.mode,mode_label:setup.mode_label,timeframes:setup.timeframes,duration:setup.duration,price:setup.price,technical_verdict:setup.technical_verdict,technical_confidence:setup.technical_confidence,levels:setup.levels,entry_tf:clean(setup.entry_tf),confirmation_tf:clean(setup.confirmation_tf),risk:setup.risk};}
async function auditMarkets(model,setups,deep=false){
  const instructions=deep?'Tu es Sol, seconde couche de contrôle de Sera Indicator pour les indices synthétiques Deriv. Vérifie chaque setup selon son mode: Day trading M15/H1 ou Swing H1/H4. Confirme uniquement le même BUY/SELL technique ou remplace-le par ATTENDRE. Examine structure, liquidité, retest, momentum, ATR, risque de spike et cohérence entrée/SL/TP.':'Tu es Luna, première couche de contrôle indépendante de Sera Indicator. Respecte le mode et ses unités de temps. Confirme le même BUY/SELL technique ou remplace-le par ATTENDRE; ne transforme jamais ATTENDRE en signal et n’inverse jamais le sens. Repère contradictions multi-timeframe et risque de spike.';
  const response=await callOpenAI({model,reasoning:{effort:deep?'medium':'low'},store:false,instructions,input:JSON.stringify({broker:'Deriv',market_family:'Synthetic Indices',generated_at:new Date().toISOString(),modes:['Day M15/H1','Swing H1/H4'],execution:'manual_only',markets:setups.map(publicSetup)}),text:{format:{type:'json_schema',name:deep?'sera_deriv_sol_audit':'sera_deriv_luna_audit',strict:true,schema:auditSchema}}});
  const parsed=JSON.parse(extractOutputText(response));return {results:parsed.markets||[],response_id:response.id||null,usage:response.usage||null};
}

function dynamicReadiness(setup,audit,agreed){
  const entry=setup.entry_tf,confirmation=setup.confirmation_tf;
  const aiConfidence=Math.max(0,Math.min(100,Number(audit.confidence)||0));
  const alignment=entry.side===confirmation.side?8:-10;
  const structure=(entry.bos||entry.choch?6:0)+(entry.retest?5:0)+(entry.sweep?4:0);
  const trend=(entry.trendStrong?5:-3)+(confirmation.trendStrong?8:-6);
  const momentum=(entry.momentum?4:-3)+(confirmation.momentum?3:-2);
  const confluence=(entry.fvg?2:0)+(entry.orderBlock?3:0)+(entry.impulse?2:0);
  const volatilityRatio=setup.price?Math.abs(entry.atr/setup.price)*100:0;
  const volatilityPenalty=volatilityRatio>5?7:volatilityRatio>2.5?4:0;
  const contradictionPenalty=(audit.contradictions?.length||0)*4+(audit.needs_expert_review?8:0)+(entry.spikeRisk?10:0);
  const confirmationBonus=Math.min(8,(audit.confirmations?.length||0)*2);
  const base=setup.technical_confidence*.38+aiConfidence*.32+entry.passed*1.8;
  const raw=base+alignment+structure+trend+momentum+confluence+confirmationBonus-volatilityPenalty-contradictionPenalty;
  return Math.round(Math.max(agreed?75:18,Math.min(agreed?96:74,raw)));
}

function estimateTiming(setup,finalVerdict,finalConfidence){
  const entry=setup.entry_tf,confirmation=setup.confirmation_tf;
  const aligned=entry.side===confirmation.side;
  const bias=aligned?entry.side:'NEUTRE';
  const activeSide=finalVerdict!=='ATTENDRE'?finalVerdict:bias;
  const rate=Math.max(entry.atr*.35,entry.atr*(.5+entry.passed*.045+(confirmation.trendStrong?.12:0)));
  let minHours,maxHours,tp1Hours=null,tp2Hours=null,tp3Hours=null;
  if(finalVerdict!=='ATTENDRE'&&setup.levels){
    const eta=target=>Math.max(1,Math.ceil(Math.abs(target-setup.levels.entry)/rate));
    tp1Hours=eta(setup.levels.tp1);tp2Hours=eta(setup.levels.tp2);tp3Hours=eta(setup.levels.tp3);
    minHours=Math.max(1,Math.floor(tp1Hours*.7));maxHours=Math.min(96,Math.max(minHours+1,Math.ceil(tp3Hours*1.35)));
  }else if(finalConfidence>=65){minHours=3;maxHours=12;
  }else if(finalConfidence>=45){minHours=6;maxHours=24;
  }else{minHours=12;maxHours=48;}
  const style=maxHours<=6?'COURT':maxHours<=24?'MOYEN':'LONG';
  const expiresInHours=style==='COURT'?3:style==='MOYEN'?8:16;
  return {bias,side:finalVerdict!=='ATTENDRE'?finalVerdict:activeSide,position_style:style,duration_min_hours:minHours,duration_max_hours:maxHours,tp1_hours:tp1Hours,tp2_hours:tp2Hours,tp3_hours:tp3Hours,expires_in_hours:expiresInHours,recheck_hours:4,is_confirmed:finalVerdict!=='ATTENDRE',basis:'ATR H1, distance aux objectifs, force H1/H4 et volatilité récente'};
}

function finalize(setup,luna,sol){
  const audit=sol||luna||{verdict:'ATTENDRE',confidence:0,summary:'Analyse OpenAI absente.',confirmations:[],contradictions:['Validation IA absente'],risk:'Inconnu',needs_expert_review:true};
  const aiConfidence=Number(audit.confidence)||0;
  const agreed=setup.technical_verdict!=='ATTENDRE'&&audit.verdict===setup.technical_verdict&&aiConfidence>=75&&!audit.needs_expert_review;
  const finalVerdict=agreed?setup.technical_verdict:'ATTENDRE';
  const finalConfidence=dynamicReadiness(setup,audit,agreed);
  const timing=estimateTiming(setup,finalVerdict,finalConfidence);
  return {...publicSetup(setup),levels:finalVerdict==='ATTENDRE'?null:setup.levels,final_verdict:finalVerdict,final_confidence:finalConfidence,timing,score_type:agreed?'signal_confidence':'setup_readiness',ai_verdict:audit.verdict,ai_confidence:aiConfidence,ai_summary:audit.summary,ai_confirmations:audit.confirmations||[],ai_contradictions:audit.contradictions||[],ai_risk:audit.risk,needs_expert_review:Boolean(audit.needs_expert_review),ai_tier:sol?DEEP_MODEL+' · validation profonde':SCREENING_MODEL+' · contrôle initial'};
}

async function selfTest(){const candles=Array.from({length:240},(_,i)=>{const base=1000+i*.8,open=base+Math.sin(i/4)*2,close=base+1+Math.sin(i/4)*2,high=Math.max(open,close)+3,low=Math.min(open,close)-3;return{open,high,low,close,epoch:1700000000+i*900};});const result=inspectCandles(candles);if(!result||!Number.isFinite(result.atr)||!['BUY','SELL'].includes(result.side))throw new Error('Technical engine self-test failed');const setup=technicalSetup(MARKETS[0],result,{...result,trendStrong:true},MODES[0]);if(!setup.entry_tf||!setup.confirmation_tf)throw new Error('Multi-horizon assembly failed');console.log('Deriv multi-horizon signal engine self-test passed.');}

async function main(){
  if(process.argv.includes('--self-test'))return selfTest();
  if(!OPENAI_API_KEY)throw new Error('OPENAI_API_KEY is not configured');
  const candles=await fetchAllCandles();
  const setups=MARKETS.flatMap(meta=>MODES.map(mode=>{const entry=inspectCandles(candles.get(`${meta.symbol}:${mode.entry}`)),confirmation=inspectCandles(candles.get(`${meta.symbol}:${mode.confirmation}`));if(!entry||!confirmation)throw new Error(`Insufficient ${mode.id} candles for ${meta.market}`);return technicalSetup(meta,entry,confirmation,mode);}));
  const luna=await auditMarkets(SCREENING_MODEL,setups,false),lunaMap=new Map(luna.results.map(row=>[String(row.id),row]));
  const setupId=setup=>`${setup.symbol}:${setup.mode}`;
  const deepCandidates=setups.filter(setup=>setup.technical_verdict!=='ATTENDRE'&&lunaMap.get(setupId(setup))?.verdict===setup.technical_verdict).sort((a,b)=>b.technical_confidence-a.technical_confidence).slice(0,8);
  let sol={results:[],response_id:null,usage:null};if(deepCandidates.length)sol=await auditMarkets(DEEP_MODEL,deepCandidates,true);
  const solMap=new Map(sol.results.map(row=>[String(row.id),row])),markets=setups.map(setup=>finalize(setup,lunaMap.get(setupId(setup)),solMap.get(setupId(setup))));
  const payload={ok:true,status:'ai_analyzed',source_broker:'Deriv',source:'Deriv WebSocket · M15/H1/H4',updated_at:new Date().toISOString(),model:`${SCREENING_MODEL} + ${DEEP_MODEL}`,screening_model:SCREENING_MODEL,deep_model:DEEP_MODEL,markets_count:markets.length,confirmed_signals:markets.filter(m=>m.final_verdict!=='ATTENDRE').length,markets,openai_response_ids:{screening:luna.response_id,deep:sol.response_id},usage:{screening:luna.usage,deep:sol.usage},safety:'Signaux uniquement. Aucun accès au compte et aucun ordre automatique. BUY/SELL exige un accord technique et OpenAI avec confiance IA >= 75.'};
  await fs.mkdir(path.dirname(OUTPUT),{recursive:true});await fs.writeFile(OUTPUT,JSON.stringify(payload,null,2));console.log(`Wrote ${markets.length} Deriv analyses; ${payload.confirmed_signals} confirmed signals.`);
}

main().catch(error=>{console.error(error instanceof Error?error.message:error);process.exit(1);});
