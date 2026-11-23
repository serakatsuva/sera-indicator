# Sera Boom & Crash pour MetaTrader 5

Indicateur multi-symboles APA + Malaysian SNR. Une instance scanne le catalogue
complet du serveur MT5, suffixes inclus. Boom et GainX sont scannés en achat
après un spike haussier. Crash et PainX sont scannés en vente après un spike
baissier. Cela couvre notamment les variantes Pain/Gain 400, 600, 800, 999 et 1200
lorsqu’elles sont disponibles sur le compte Weltrade SyntX. Les symboles
Boom/Crash combinés sont scannés dans les deux directions.
Le tableau affiche les configurations détectées. Les lignes apparaissent lorsque
le graphique actif correspond au symbole du signal.

## Installer et essayer

1. Dans MT5, ouvre le dossier des données et copie `Sera_Boom_Crash.mq5` dans
   `MQL5/Indicators`. Ouvre le fichier dans MetaEditor et compile avec F7.
2. Ajoute l’indicateur à un seul graphique sur un compte démo. Il sélectionne
   les symboles Boom, Crash, Gain et Pain du serveur dans l’Observateur du marché.
3. Les signaux validés sont exportés vers `Terminal/Common/Files/SeraBoomCrash`.
   Chaque CSV est écrit d’abord comme fichier temporaire, puis publié sous
   son nom final. Les dates dans les exports sont celles du serveur MT5.

Un signal requiert une impulsion M5, la cassure de l’extrême des cinq bougies
précédentes et un premier retest clôturé. L’impulsion mesure par défaut au moins
deux fois la moyenne des true ranges des 14 bougies précédentes. L’indicateur
cherche un niveau A/V H1 opposé encore frais pour la cible et, par défaut,
un niveau A/V H1 frais touché par l’impulsion pour valider l’origine. Le stop
se place au-delà de la mèche de retest. La cotation bid/ask sert d’entrée et
le seuil de 2R est brut de commission et de glissement. Le tableau conserve
l’heure du dernier signal. Les lignes du graphique marquent ce signal historique.

## Envoyer les signaux à GitHub pour analyse IA

Le workflow doit être présent sur la branche par défaut de `serakatsuva/sera-indicator`.
Le fichier d’analyse se place dans `sera-boom-crash/analyze.py` et le workflow
dans `.github/workflows/sera-boom-crash-analysis.yml`. Configure le secret
Actions `OPENAI_API_KEY`. La variable Actions facultative `SERA_OPENAI_MODEL`
remplace le modèle par défaut `gpt-4.1-mini`. Les appels à ce service sont facturables.

Sur la machine MT5, utilise Python 3.10 ou plus. Teste d’abord le format exporté.

```powershell
py bridge.py --preview
```

Définis ensuite `SERA_GITHUB_TOKEN` dans l’environnement du processus Python.
Utilise un jeton GitHub limité à ce dépôt avec la permission Contents (write).
Puis garde le pont ouvert dans un seul processus sur cette machine.

```powershell
py bridge.py --watch
```

Le pont surveille les CSV toutes les 30 secondes et écrit un reçu local après
acceptation par GitHub. Un reçu confirme la remise de l’événement, tandis que
le résultat de l’analyse est dans l’onglet Actions. Un événement accepté juste
avant un arrêt local peut être renvoyé au redémarrage.

Le dépôt est public et les résumés Actions peuvent être visibles publiquement.
Le pont transmet le symbole, les prix, les métriques et les dates du signal,
avec un identifiant haché. Aucun numéro de compte, identifiant de connexion
ou solde n’est collecté. L’analyse est une revue du signal exporté et ne pilote
ni l’affichage MT5 ni des ordres. L’indicateur ne répond qu’aux signaux en cours
au moment du scan et n’exporte pas l’historique complet.
