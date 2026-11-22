// Phase d'une position anticipée selon le prix actuel (logique dupliquée dans positions.js — garder identique).
//  NOW      : on peut entrer maintenant (prix dans la zone, ou ordre stop tout juste déclenché)
//  PREP     : en préparation (prix proche, du bon côté, à moins de 1,5 R de l'entrée)
//  UPCOMING : à venir (prix plus loin, du bon côté)
//  PASSED   : déjà passée (SL touché, TP1 atteint, zone traversée sans rebond, ordre stop déjà parti) → à retirer
export const PREP_MAX_R=1.5;
export function positionPhase(p,price){
  const n=Number(price);
  if(!Number.isFinite(n))return 'UPCOMING';
  const d=p.side==='BUY'?1:-1;
  const risk=Math.abs(p.entry-p.sl);
  if(!(risk>0))return 'PASSED';
  if((n-p.sl)*d<=0)return 'PASSED';
  if((n-p.tp1)*d>=0)return 'PASSED';
  const zmin=Number.isFinite(Number(p.zone_min))?Number(p.zone_min):p.entry;
  const zmax=Number.isFinite(Number(p.zone_max))?Number(p.zone_max):p.entry;
  const tol=Number(p.zone_tol)||0;
  if(n>=zmin-tol&&n<=zmax+tol)return 'NOW';
  const dist=Math.abs(n-p.entry)/risk;
  if(p.order==='STOP'){
    if((n-p.entry)*d<0)return dist<=PREP_MAX_R?'PREP':'UPCOMING';
    return dist<=0.3?'NOW':'PASSED';
  }
  // LIMIT : le prix doit venir du côté de l'objectif ; de l'autre côté de la zone, elle est déjà traversée
  const onTargetSide=p.side==='BUY'?n>zmax+tol:n<zmin-tol;
  if(!onTargetSide)return 'PASSED';
  return dist<=PREP_MAX_R?'PREP':'UPCOMING';
}
