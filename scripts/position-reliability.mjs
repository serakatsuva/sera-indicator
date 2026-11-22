// Fiabilité d'une position selon ce qui a été MESURÉ (scripts/backtest-msnr.mjs → data/msnr-stats.json).
// Groupes : "drift" = sens de la dérive (Boom vente, Crash achat, Bull Market achat, Bear Market vente, comme le Drift Playbook),
// "counter" = sens contraire sur ces mêmes indices, "random" = autres marchés (Volatility, Step, Jump, Range… : au hasard).
export function marketKind(name=''){
  if(/boom/i.test(name))return 'Boom';
  if(/crash/i.test(name))return 'Crash';
  if(/bull market/i.test(name))return 'Bull';
  if(/bear market/i.test(name))return 'Bear';
  return 'Autre';
}
const DRIFT_SIDE={Boom:'SELL',Crash:'BUY',Bull:'BUY',Bear:'SELL'};
export function driftGroup(name,side){
  const kind=marketKind(name);
  if(!DRIFT_SIDE[kind])return 'random';
  return DRIFT_SIDE[kind]===side?'drift':'counter';
}
// Seuils : avantage = espérance > 0,05 R sur la période d'apprentissage ET hors échantillon, au moins 300 trades chacun.
export const EDGE_MIN_R=0.05,EDGE_MIN_N=300;
export function classify(cell){
  if(!cell)return 'UNMEASURED';
  const {train,test}=cell;
  if(!train||!test||train.n<EDGE_MIN_N||test.n<EDGE_MIN_N)return cell.all&&cell.all.exp_r>EDGE_MIN_R?'PARTIAL':'UNMEASURED';
  if(train.exp_r>EDGE_MIN_R&&test.exp_r>EDGE_MIN_R)return 'EDGE';
  if(train.exp_r<0&&test.exp_r<0)return 'NEGATIVE';
  return 'NEUTRAL';
}
// stats = contenu de data/msnr-stats.json ; position = {method, tf, side}
export function reliabilityFor(stats,marketName,position){
  if(position.method!=='MSNR')return {level:'UNMEASURED',group:driftGroup(marketName,position.side),measured:null};
  const group=driftGroup(marketName,position.side);
  const cell=stats?.cells?.[`${group}|${position.tf}`]||null;
  return {level:classify(cell),group,measured:cell?cell.all:null};
}
