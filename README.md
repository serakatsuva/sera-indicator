# Sera Indicator

Sera Indicator est un tableau de signaux swing H1/H4 pour les indices synthétiques Deriv.

## Fonctionnement

- Les bougies Deriv H1 et H4 sont récupérées par le WebSocket public officiel.
- Le moteur technique contrôle la tendance, le momentum, la structure, la liquidité, les retests et le risque de spike.
- OpenAI Luna effectue le premier audit et Sol approfondit les meilleurs setups.
- Un signal BUY ou SELL n'est affiché que si la technique et OpenAI confirment le même sens.
- Sans confirmation suffisante, le résultat reste ATTENDRE.

## Exécution Deriv MT5

Le dossier `mt5/` contient `Sera_Swing_Executor.mq5`. Cet Expert Advisor peut lire le fichier public de signaux et ouvrir un trade uniquement lorsqu’un signal Swing BUY/SELL récent est confirmé. Il est verrouillé sur compte Démo par défaut, exige un Stop Loss, limite le risque et mémorise les signaux déjà traités.

GitHub Pages ne se connecte pas directement au terminal MT5 et ne reçoit aucun identifiant. L’EA s’exécute dans le terminal MT5 déjà authentifié.

## Sécurité

Sans l’EA installé et Algo Trading activé, l’application ne place aucun ordre. Le passage à un compte réel exige de modifier volontairement `AllowRealAccount` dans les paramètres de l’EA.

La clé `OPENAI_API_KEY` est conservée exclusivement dans GitHub Actions Secrets et n'est jamais envoyée au navigateur.
