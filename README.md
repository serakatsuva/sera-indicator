# Sera Indicator

Sera Indicator est un système d’aide à la décision et d’exécution Deriv pour le Day trading M15/H1 et le Swing H1/H4.

## Fonctionnement

- Les bougies Deriv M15, H1 et H4 sont récupérées depuis le WebSocket public Deriv.
- Sera Smart Engine v2 analyse tendance, régime de marché, momentum, structure, liquidité, retest, ATR, mémoire de tendance et risque de spike.
- OpenAI Luna intervient comme audit supplémentaire lorsqu’il est disponible.
- Si Luna est indisponible, seuls les setups dépassant les seuils Smart Local renforcés peuvent devenir des signaux finaux.
- Le résultat final reste BUY, SELL ou ATTENDRE. Aucun score ne garantit un gain.

## Exécution Deriv MT5 — mode réel

Le dossier `mt5/` contient `Sera_Swing_Executor.mq5`.

La version **v1.20** est configurée pour fonctionner directement sur le compte MT5 connecté :

- `EnableAutomaticTrading = true`
- `AllowRealAccount = true`
- `AllowSmartLocalExecution = true`
- risque par trade : **0,50 %**
- perte maximale calculée par trade : **1 USD**
- lot maximum : **0,02**
- confiance minimale : **75 %**
- maximum : **1 position Sera ouverte**
- maximum : **2 entrées Sera par jour**
- Stop Loss obligatoire
- anti-doublon persistant par setup

L’EA résout le symbole MT5 à partir du nom de marché et du code Deriv avant toute tentative d’ordre. Si aucun symbole valide n’est trouvé, aucun ordre n’est envoyé.

GitHub Pages ne reçoit aucun identifiant MT5. L’EA s’exécute dans le terminal MT5 déjà authentifié et lit les signaux publiés dans `data/signals.json`.

## Mode réel et risque

Le projet est désormais conçu pour fournir des décisions destinées à un usage réel et l’EA autorise le compte réel par défaut. Cela ne transforme pas les signaux en certitudes : slippage, changement de régime, spikes, latence, erreurs de symbole et mouvements rapides peuvent produire des pertes.

Les limites de risque sont conservées dans l’EA et ne doivent pas être interprétées comme une garantie de protection totale.

La clé `OPENAI_API_KEY` reste exclusivement dans GitHub Actions Secrets et n’est jamais envoyée au navigateur.
