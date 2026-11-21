// Sera — positions anticipées « MSNR » (support/résistance de type Malaisie, niveaux tracés sur les clôtures).
// Principe : un niveau OCL de l'unité supérieure, confirmé par un niveau SNR (Classic A/V, RBS/SBR ou QML) de l'unité
// inférieure, dans le sens de la structure de l'unité supérieure. Ne produit PAS d'ordre : c'est une anticipation.
// La qualité (0-95) est un score heuristique, pas une probabilité de gain.
const clamp=(v,lo,hi)=>Math.max(lo,Math.min(hi,v));

export const MSNR_PAIRS=[
  {high:'D1',low:'H4',mode:'swing',label:'OCL D1 + SNR H4'},
  {high:'H4',low:'H1',mode:'swing',label:'OCL H4 + SNR H1'},
  {high:'H1',low:'M15',mode:'day',label:'OCL H1 + SNR M15'}
];

export function atrOf(c,n=14){
  if(!Array.isArray(c)||c.length<n+2)return 0;
  let sum=0;
  for(let i=c.length-n;i<c.length;i++){
    const prev=c[i-1].close;
    sum+=Math.max(c[i].high-c[i].low,Math.abs(c[i].high-prev),Math.abs(c[i].low-prev));
  }
  return sum/n;
}

// Pivots sur les clôtures (« line chart ») ou sur les mèches.
export function pivots(c,strength=2,field='close'){
  const hi=[],lo=[];
  const up=i=>field==='close'?c[i].close:c[i].high,down=i=>field==='close'?c[i].close:c[i].low;
  for(let i=strength;i<c.length-strength;i++){
    let isHigh=true,isLow=true;
    for(let k=1;k<=strength;k++){
      if(!(up(i)>up(i-k)&&up(i)>=up(i+k)))isHigh=false;
      if(!(down(i)<down(i-k)&&down(i)<=down(i+k)))isLow=false;
    }
    if(isHigh)hi.push({i,price:up(i)});
    if(isLow)lo.push({i,price:down(i)});
  }
  return {hi,lo};
}

// Structure de l'unité supérieure : HH+HL = BUY, LH+LL = SELL, sinon NEUTRE.
export function structureTrend(c){
  const {hi,lo}=pivots(c.slice(-120),2,'close');
  if(hi.length<2||lo.length<2)return 'NEUTRE';
  const h1=hi.at(-1).price,h0=hi.at(-2).price,l1=lo.at(-1).price,l0=lo.at(-2).price;
  if(h1>h0&&l1>l0)return 'BUY';
  if(h1<h0&&l1<l0)return 'SELL';
  return 'NEUTRE';
}

// OCL : deux bougies consécutives de même couleur ; niveau entre la clôture de la 1re et l'ouverture de la 2e.
export function oclZones(c,atr){
  const out=[];
  const start=Math.max(1,c.length-90);
  for(let i=start;i<c.length-1;i++){
    const a=c[i],b=c[i+1];
    const bull=a.close>a.open&&b.close>b.open,bear=a.close<a.open&&b.close<b.open;
    if(!bull&&!bear)continue;
    let lo=Math.min(a.close,b.open),hi=Math.max(a.close,b.open);
    if(hi-lo<atr*.1){const mid=(hi+lo)/2;lo=mid-atr*.05;hi=mid+atr*.05;}
    let run=2;
    for(let k=i-1;k>=0&&((bull&&c[k].close>c[k].open)||(bear&&c[k].close<c[k].open));k--)run++;
    const later=c.slice(i+2);
    const broken=bull?later.some(x=>x.close<lo-atr*.1):later.some(x=>x.close>hi+atr*.1);
    if(broken)continue;
    out.push({side:bull?'BUY':'SELL',lo,hi,index:i+1,double:run>=3});
  }
  return out;
}

// SNR de l'unité inférieure : Classic A/V, RBS/SBR, QML.
export function snrLevels(c,atr){
  const out=[];
  const start=Math.max(1,c.length-140);
  // Classic V / A : la bougie suivante prend la liquidité (mèche) de la précédente et clôture dans le sens.
  for(let i=start;i<c.length-1;i++){
    const a=c[i],b=c[i+1];
    if(a.close<a.open&&b.close>b.open&&b.low<=a.low+atr*.05&&b.close>a.close)
      out.push({side:'BUY',kind:'V_CLASSIC',lo:a.close-atr*.2,hi:a.close+atr*.2,index:i+1,liquidity:true,slBase:Math.min(a.low,b.low)});
    if(a.close>a.open&&b.close<b.open&&b.high>=a.high-atr*.05&&b.close<a.close)
      out.push({side:'SELL',kind:'A_CLASSIC',lo:a.close-atr*.2,hi:a.close+atr*.2,index:i+1,liquidity:true,slBase:Math.max(a.high,b.high)});
  }
  const {hi,lo}=pivots(c.slice(-160),2,'close');
  const offset=c.length-Math.min(160,c.length);
  const abs=p=>({i:p.i+offset,price:p.price});
  // RBS / SBR : niveau cassé puis retesté.
  for(const p of hi.map(abs)){
    const after=c.slice(p.i+3);
    const bi=after.findIndex(x=>x.close>p.price+atr*.15);
    if(bi<0)continue;
    if(after.slice(bi).some(x=>x.close<p.price-atr*.3))continue;
    out.push({side:'BUY',kind:'RBS',lo:p.price-atr*.25,hi:p.price+atr*.25,index:p.i+3+bi,liquidity:false,slBase:p.price-atr*.25});
  }
  for(const p of lo.map(abs)){
    const after=c.slice(p.i+3);
    const bi=after.findIndex(x=>x.close<p.price-atr*.15);
    if(bi<0)continue;
    if(after.slice(bi).some(x=>x.close>p.price+atr*.3))continue;
    out.push({side:'SELL',kind:'SBR',lo:p.price-atr*.25,hi:p.price+atr*.25,index:p.i+3+bi,liquidity:false,slBase:p.price+atr*.25});
  }
  // QML : creux, sommet, creux plus bas (la tête), puis cassure du sommet ; entrée sur l'épaule gauche. (miroir pour SELL)
  const all=[...hi.map(p=>({...abs(p),hi:true})),...lo.map(p=>({...abs(p),hi:false}))].sort((x,y)=>x.i-y.i);
  for(let k=0;k+2<all.length;k++){
    const [p1,p2,p3]=[all[k],all[k+1],all[k+2]];
    const closesAfter=c.slice(p3.i+1);
    if(!p1.hi&&p2.hi&&!p3.hi&&p3.price<p1.price&&closesAfter.some(x=>x.close>p2.price)&&!closesAfter.some(x=>x.close<p3.price-atr*.3))
      out.push({side:'BUY',kind:'QML',lo:p1.price-atr*.25,hi:p1.price+atr*.25,index:p3.i,liquidity:true,slBase:p3.price});
    if(p1.hi&&!p2.hi&&p3.hi&&p3.price>p1.price&&closesAfter.some(x=>x.close<p2.price)&&!closesAfter.some(x=>x.close>p3.price+atr*.3))
      out.push({side:'SELL',kind:'QML',lo:p1.price-atr*.25,hi:p1.price+atr*.25,index:p3.i,liquidity:true,slBase:p3.price});
  }
  return out;
}

const KIND_LABEL={V_CLASSIC:'Classic V',A_CLASSIC:'Classic A',RBS:'RBS',SBR:'SBR',QML:'QML'};

// Positions MSNR d'un marché. candles = { D1, H4, H1, M15 } (bougies fermées, plus anciennes d'abord).
export function msnrPositions(candles){
  const result=[];
  for(const pair of MSNR_PAIRS){
    const hc=candles[pair.high],lc=candles[pair.low];
    if(!Array.isArray(hc)||!Array.isArray(lc)||hc.length<40||lc.length<60)continue;
    const atrH=atrOf(hc),atrL=atrOf(lc);
    if(!(atrH>0)||!(atrL>0))continue;
    const trend=structureTrend(hc);
    const price=lc.at(-1).close;
    const zones=oclZones(hc,atrH),snr=snrLevels(lc,atrL);
    const wickLevels=[...pivots(hc.slice(-120),3,'high').hi,...pivots(hc.slice(-120),3,'low').lo,
      ...pivots(lc.slice(-160),3,'high').hi,...pivots(lc.slice(-160),3,'low').lo].map(p=>p.price);
    const tol=atrL*.3;
    const found=[];
    for(const z of zones){
      const direction=z.side==='BUY'?1:-1;
      // le niveau doit être du bon côté du prix et proche (anticipation, pas une zone lointaine)
      const near=z.side==='BUY'?price-z.hi:z.lo-price;
      if(near<-atrL*.5||near>atrL*6)continue;
      for(const s of snr.filter(x=>x.side===z.side&&x.lo<=z.hi+tol&&x.hi>=z.lo-tol)){
        const lowEdge=Math.min(z.lo,s.lo),highEdge=Math.max(z.hi,s.hi);
        const entry=(z.lo+z.hi+s.lo+s.hi)/4;
        const recent=lc.slice(-8);
        const swept=s.liquidity||recent.some(x=>z.side==='BUY'?(x.low<lowEdge&&x.close>lowEdge):(x.high>highEdge&&x.close<highEdge));
        const buffer=atrL*(swept?.6:.25);
        const slBase=s.kind==='QML'?s.slBase:z.side==='BUY'?lowEdge:highEdge;
        const sl=z.side==='BUY'?Math.min(slBase,lowEdge)-buffer:Math.max(slBase,highEdge)+buffer;
        const risk=Math.abs(entry-sl);
        if(!(risk>0)||risk>atrL*5)continue;
        const beyond=wickLevels.filter(x=>(x-entry)*direction>=risk).sort((a,b)=>(a-b)*direction);
        const tp1=beyond[0]!==undefined?beyond[0]:entry+direction*risk*1.5;
        const next=wickLevels.filter(x=>(x-tp1)*direction>=risk*.5).sort((a,b)=>(a-b)*direction);
        const tp2=next[0]!==undefined?next[0]:tp1+direction*risk*1.5;
        if((price-sl)*direction<=0||(price-tp1)*direction>=0)continue;
        const rr1=Math.abs(tp1-entry)/risk,rr2=Math.abs(tp2-entry)/risk;
        let quality=60;
        if(trend===z.side)quality+=15;else if(trend!=='NEUTRE')quality-=20;
        if(z.double)quality+=6;
        if(swept)quality+=8;
        if(s.kind==='QML')quality+=4;
        if(rr1>=2)quality+=5;
        const inside=price>=lowEdge-atrL*.1&&price<=highEdge+atrL*.1;
        found.push({method:'MSNR',setup:`${pair.label} (${KIND_LABEL[s.kind]})`,tf:`${pair.high}/${pair.low}`,mode:pair.mode,
          side:z.side,order:'LIMIT',status:inside?'IN_ZONE':'WAIT_RETEST',trigger:null,
          entry,zone_min:lowEdge,zone_max:highEdge,sl,tp1,tp2,rr1:Number(rr1.toFixed(2)),rr2:Number(rr2.toFixed(2)),
          zone_tol:Number((atrL*.4).toFixed(8)),quality:Math.round(clamp(quality,0,95)),
          aligned:trend===z.side,with_trend:trend===z.side,at_key_level:true,
          liquidity_swept:Boolean(swept),ocl_double:Boolean(z.double),trend_side:trend});
      }
    }
    found.sort((a,b)=>b.quality-a.quality);
    for(const position of found){
      if(!result.some(r=>r.side===position.side&&r.tf===position.tf&&Math.abs(r.entry-position.entry)<=atrL*.5))result.push(position);
    }
  }
  return result.sort((a,b)=>b.quality-a.quality).slice(0,4);
}
