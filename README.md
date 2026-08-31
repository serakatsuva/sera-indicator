# Sera Indicator

Sera Indicator est un tableau de signaux swing H1/H4 pour les indices synthétiques Deriv.

## Fonctionnement

- Les bougies Deriv H1 et H4 sont récupérées par le WebSocket public officiel.
- Le moteur technique contrôle la tendance, le momentum, la structure, la liquidité, les retests et le risque de spike.
- OpenAI Luna effectue le premier audit et Sol approfondit les meilleurs setups.
- Un signal BUY ou SELL n'est affiché que si la technique et OpenAI confirment le même sens.
- Sans confirmation suffisante, le résultat reste ATTENDRE.

## Sécurité

L'application affiche uniquement des signaux. Elle ne se connecte pas au compte Deriv et ne place aucun ordre. Toute exécution reste manuelle.

La clé `OPENAI_API_KEY` est conservée exclusivement dans GitHub Actions Secrets et n'est jamais envoyée au navigateur.
