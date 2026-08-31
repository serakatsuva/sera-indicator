# Installation de Sera Indicator dans TradingView

1. Ouvrir le fichier `Sera_Indicator_AI_Bridge.pine` sur GitHub.
2. Copier tout le code dans **TradingView > Pine Editor**.
3. Cliquer sur **Save**, puis **Add to chart**.
4. Dans les paramètres, conserver les confirmations minimales à `6/8` pour le premier test.
5. Créer une alerte sur **Sera Indicator AI Bridge** et choisir **Any alert() function call**.
6. Cocher **Webhook URL** et renseigner l'adresse HTTPS Sera qui sera fournie après le déploiement du récepteur.

## Lecture des signaux

- `BUY IA?` ou `SELL IA?` est un pré-signal technique détecté à la clôture de la bougie.
- Le verdict final `CONFIRMÉ`, `REJETÉ` ou `ATTENDRE` apparaît dans Sera Indicator après le contrôle IA.
- Les trois lignes du graphique sont EMA 20, EMA 50 et EMA 200.
- Le panneau affiche séparément les tendances H1 et H4.

## Sécurité

Ne jamais saisir une clé OpenAI dans Pine Script ou dans le message TradingView.
Le champ `Jeton webhook` recevra seulement un jeton limité, créé pour authentifier les alertes.
L'indicateur n'ouvre et ne ferme aucune position.
