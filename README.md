# Sera Indicator

Sera Indicator est un système d’aide à la décision et d’exécution Deriv pour le Day trading M15/H1 et le Swing H1/H4.

## Fonctionnement

- Les bougies Deriv M15, H1 et H4 sont récupérées depuis le WebSocket public Deriv.
- Sera Autonomous Engine v3.3 analyse tendance, régime de marché, momentum, structure, liquidité, retest, ATR, mémoire de tendance et risque de spike.
- OpenAI Luna intervient uniquement comme conseiller/auditeur facultatif lorsqu’il est disponible.
- Sans Luna, le moteur peut confirmer seul BUY/SELL lorsque au moins 80 % des conditions applicables sont validées, tout en exigeant les garde-fous critiques.
- Le résultat final reste BUY, SELL ou ATTENDRE. Aucun score ne garantit un gain.

## Exécution Deriv MT5 — mode réel

Le dossier `mt5/` contient `Sera_Swing_Executor.mq5`.

La version **v1.40** est configurée pour fonctionner directement sur le compte MT5 connecté :

- `EnableAutomaticTrading = true`
- `AllowRealAccount = true`
- `AllowSmartLocalExecution = true`
- risque par trade : **0,50 %**
- perte maximale calculée par trade : **1 USD**
- lot maximum : **0,02**
- confiance minimale : **75 %**
- conditions autonomes minimales : **80 %**
- score d’exécution minimal : **78 %**
- état requis pour l’ordre réel : **EXECUTE_NOW**
- maximum : **1 position Sera ouverte**
- maximum : **2 entrées Sera par jour**
- Stop Loss obligatoire
- anti-doublon persistant par setup

L’EA résout le symbole MT5 à partir du nom de marché et du code Deriv avant toute tentative d’ordre. Un BUY/SELL directionnel ne suffit plus : l’ordre réel exige aussi l’état `EXECUTE_NOW` calculé par le moteur. Si aucun symbole valide n’est trouvé, aucun ordre n’est envoyé.

GitHub Pages ne reçoit aucun identifiant MT5. L’EA s’exécute dans le terminal MT5 déjà authentifié et lit les signaux publiés dans `data/signals.json`.

## Mode réel et risque

Le projet est désormais conçu pour fournir des décisions destinées à un usage réel et l’EA autorise le compte réel par défaut. Cela ne transforme pas les signaux en certitudes : slippage, changement de régime, spikes, latence, erreurs de symbole et mouvements rapides peuvent produire des pertes.

Les limites de risque sont conservées dans l’EA et ne doivent pas être interprétées comme une garantie de protection totale.

La clé `OPENAI_API_KEY`, si elle est configurée, reste exclusivement dans GitHub Actions Secrets et n’est jamais envoyée au navigateur. Elle n’est pas nécessaire au fonctionnement autonome du moteur.


## Ensemble IA open source

Sera ajoute maintenant un ensemble quantitatif open source au moteur autonome :

- **XGBoost** : classification directionnelle entraînée sur les bougies Deriv à chaque cycle.
- **LightGBM** : second classifieur indépendant, également entraîné sur les données Deriv.
- **Chronos-2 small** : modèle de prévision de séries temporelles utilisé périodiquement sur les candidats les plus forts.
- **TimesFM 2.5 200M** : second modèle de prévision temporelle. La version 2.5 est utilisée afin de rester sur les poids Apache-2.0.
- **Qwen3-0.6B via WebLLM** : conseiller facultatif exécuté localement dans le navigateur lorsque WebGPU est disponible.

Les modèles open source ne peuvent pas transformer un `ATTENDRE` local en ordre réel ni contourner les garde-fous. Ils peuvent confirmer une direction ou mettre l’exécution en attente en cas de désaccord important.

L’EA **v1.41** applique également un garde-fou indépendant : si au moins deux modèles open source disponibles donnent un consensus opposé suffisamment fort, l’ordre `EXECUTE_NOW` est bloqué.

Les classifieurs dont la qualité de validation est insuffisante sont exclus du consensus plutôt que comptés comme des votes.
