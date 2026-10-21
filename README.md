# Sera Indicator

Sera Indicator est un système d’aide à la décision pour les indices synthétiques Deriv et 27 paires Forex. Le Day trading utilise M15/H1. Le Swing haute conviction utilise H1/H4 avec un filtre macro D1 et deux cycles de confirmation.

## Fonctionnement

- Les bougies Deriv M15, H1 et D1 sont récupérées depuis le WebSocket public Deriv; H4 est consolidé à partir de H1.
- Les 27 paires Forex cochées sont analysées en H1, H4 et D1 à partir de bougies publiques Yahoo Finance. Ces prix sont indicatifs et doivent être confirmés sur le symbole `-STD` du broker avant exécution.
- Sera Autonomous Engine v4.0 analyse tendance, régime de marché, momentum, structure, liquidité, retest, ATR, ADX/DMI, mémoire de tendance, épuisement et risque de spike.
- Les modèles ouverts XGBoost, LightGBM, Chronos-2 et TimesFM fournissent des confirmations complémentaires.
- Le moteur autonome peut confirmer seul BUY/SELL. En Swing, il exige notamment H1/H4/D1 alignés, un score minimal de 84/100, 72 % de consensus, 80 % des conditions et deux cycles cohérents.
- Le résultat final reste BUY, SELL ou ATTENDRE. Aucun score ne garantit un gain.

### Paires Forex suivies

`USDBRL-STD`, `USDCAD-STD`, `USDCHF-STD`, `USDCLP-STD`, `USDCNH-STD`, `USDCOP-STD`, `USDCZK-STD`, `USDDKK-STD`, `USDHUF-STD`, `USDIDR-STD`, `USDINR-STD`, `USDJPY-STD`, `USDKRW-STD`, `USDMXN-STD`, `USDNOK-STD`, `USDPLN-STD`, `USDSEK-STD`, `USDSGD-STD`, `USDTHB-STD`, `USDTRY-STD`, `USDTWD-STD`, `USDZAR-STD`, `USDILS-STD`, `AUDUSD-STD`, `EURUSD-STD`, `GBPUSD-STD` et `NZDUSD-STD`.

## Exécution MT5 — Sera EA Swing Intelligent v2.10

Le dossier `mt5/` contient `Sera_EA_Swing_Intelligent.mq5` (et une copie identique, `Sera_Swing_Executor.mq5`).

L’EA prend **automatiquement** les Swing publiés par le moteur : ordre au marché sur `EXECUTE_NOW`, ordre limite dans la zone d’entrée sur `WAIT_RETRACE`, puis gestion TP1–TP5.

**Compte réel autorisé** : `AllowRealAccount = true` (choix du propriétaire). L’EA trade sur le compte MT5 connecté, réel ou démo. Pour bloquer le réel, passer ce paramètre à `false` dans les entrées de l’EA.

Pour l’activer dans MT5 : *Outils → Options → Expert Advisors* → autoriser WebRequest pour `https://serakatsuva.github.io`, attacher l’EA sur **un seul** graphique et activer **Algo Trading**.

### Nouveautés v1.90

- **Signaux frais uniquement** : `MaximumSignalAgeMinutes = 20` (le moteur publie en continu), et chaque marché dont la dernière bougie est trop ancienne est ignoré (`freshness_gate`).
- **Confirmation sur les données du broker** (`UseBrokerConfirmation`) : avant toute entrée, les EMA20/EMA50 H1 et H4 calculées sur les bougies du broker doivent aller dans le sens du signal. Sinon l’entrée est reportée au cycle suivant.
- **Sortie intelligente** : fermeture si le serveur inverse le signal de ce setup (`CloseOnSignalReversal`) ou si la position dépasse la durée maximale (`MaximumSwingHoldingHours = 240`, `MaximumDayHoldingHours = 48`).
- **Pas de nouvelle entrée Forex/CFD du vendredi 19:00 UTC au dimanche 22:00 UTC** (`AvoidForexWeekendGap`), pour éviter les gaps du week-end. Les indices synthétiques (24/7) ne sont pas concernés.
- **Symboles Forex reconnus chez tous les brokers** : `EUR/USD`, `EURUSD-STD`, `EURUSD`, `EURUSD.m`, `frxEURUSD`…
- Profils de risque synthétiques étendus (DEX, Drift Switch, VolSwitch, Baskets).
- Option `TradeDaySignals` (désactivée par défaut) pour prendre aussi les signaux Day M15/H1.

### v2.10 — les signaux décident, coupure en cas de retournement

**Nombre de positions** (`EnableBalanceScaling = true`) : l’EA prend **chaque bon signal**, une position par marché (`OnePositionPerSymbol`), jusqu’à **50 positions** (`MaximumOpenPositionsCap`). Les profits n’entrent pas dans le calcul. Le seul frein est le **risque cumulé** : la somme des pertes possibles jusqu’aux SL de toutes les positions ne dépasse pas **10 % de l’équité** (`MaximumTotalOpenRiskPercent`). Une position sécurisée au point mort compte pour 0. `BalancePerPositionUSD` (0 par défaut) permet, si on le souhaite, de limiter à 1 position par tranche de balance. Perte journalière maximale : **5 % de la balance** (`DailyLossPercentLimit`).

**Coupure en cas de retournement** (`CutOnMarketReversal = true`), vérifiée toutes les 30 secondes sur chaque position Sera :

- **données du broker** (bougies H1 clôturées après l’entrée) : croisement EMA20/EMA50 contre la position avec clôture du mauvais côté de l’EMA50, **confirmé** par une clôture H4 de l’autre côté de l’EMA20 H4 ; ou cassure du plus bas / plus haut des **24 dernières bougies H1** (`ReversalStructureBars`) ;
- **analyse serveur** : tendances H1 et H4 retournées **et** tendance H4 cassée (EMA20 passée de l’autre côté de l’EMA50) ;
- toujours actifs : verdict final inversé (`CloseOnSignalReversal`) et durée maximale (`MaximumSwingHoldingHours`).

Un simple repli dans la tendance ne déclenche pas la coupure : c’est justement là que se font les entrées en retracement.

Le haut du graphique MT5 affiche le nombre de positions ouvertes, la capacité et le risque ouvert. L’EA ouvre au plus une nouvelle position par cycle de 30 secondes.

### Garde-fous conservés

- `EnableAutomaticTrading = true`
- risque par trade : **0,50 %**
- perte maximale calculée par trade : **1 USD**
- lot maximum : **0,05**
- confiance minimale : **75 %**
- conditions autonomes minimales : **80 %**
- score d’exécution EA minimal : **78 %**; le serveur impose **84 %** aux signaux Swing haute conviction
- état requis pour l’ordre réel : **EXECUTE_NOW**
- sans mise à l’échelle (`EnableBalanceScaling = false`) : 1 position, 2 entrées par jour
- Stop Loss obligatoire
- anti-doublon persistant par setup

L’EA résout le symbole MT5 à partir du nom de marché et du code Deriv avant toute tentative d’ordre. Un BUY/SELL directionnel ne suffit plus : l’ordre réel exige aussi l’état `EXECUTE_NOW` calculé par le moteur. Si aucun symbole valide n’est trouvé, aucun ordre n’est envoyé.

GitHub Pages ne reçoit aucun identifiant MT5. L’EA s’exécute dans le terminal MT5 déjà authentifié et lit les signaux publiés dans `data/signals.json`.

## Mode réel et risque

Le projet est désormais conçu pour fournir des décisions destinées à un usage réel et l’EA autorise le compte réel par défaut. Cela ne transforme pas les signaux en certitudes : slippage, changement de régime, spikes, latence, erreurs de symbole et mouvements rapides peuvent produire des pertes.

Les limites de risque sont conservées dans l’EA et ne doivent pas être interprétées comme une garantie de protection totale.

Aucune clé OpenAI n’est utilisée par le pipeline de génération des signaux.


## Ensemble IA open source

Sera ajoute maintenant un ensemble quantitatif open source au moteur autonome :

- **XGBoost** : classification directionnelle entraînée sur les bougies de chaque instrument à chaque cycle.
- **LightGBM** : second classifieur indépendant, entraîné sur les mêmes séries multi-marchés.
- **Chronos-2 small** : modèle de prévision de séries temporelles utilisé périodiquement sur les candidats les plus forts.
- **TimesFM 2.5 200M** : second modèle de prévision temporelle. La version 2.5 est utilisée afin de rester sur les poids Apache-2.0.

Le pipeline planifie XGBoost et LightGBM toutes les cinq minutes. Chronos-2 et TimesFM recalculent les huit meilleurs candidats toutes les quinze minutes; les prévisions conservées ne votent que si la bougie de référence est identique et si elles ont moins de vingt minutes. GitHub Actions peut retarder une exécution planifiée; l’interface indique alors le retard et neutralise les anciens signaux.
- **Qwen3-0.6B via WebLLM** : conseiller facultatif exécuté localement dans le navigateur lorsque WebGPU est disponible.

Les modèles open source ne peuvent pas transformer un `ATTENDRE` local en ordre réel ni contourner les garde-fous. Ils peuvent confirmer une direction ou mettre l’exécution en attente en cas de désaccord important.

L’EA **v1.50** applique également un garde-fou indépendant : si au moins deux modèles open source disponibles donnent un consensus opposé suffisamment fort, l’ordre `EXECUTE_NOW` est bloqué.

Les classifieurs dont la qualité de validation est insuffisante sont exclus du consensus plutôt que comptés comme des votes.


## Setup directionnel et TP1–TP5

Sera Autonomous Engine v4.0 distingue le **setup détecté** du **signal final exécutable**.

- Un setup précoce est affiché comme **SETUP BUY** (bleu) ou **SETUP SELL** (rouge).
- Lorsque la structure le permet, Sera calcule immédiatement une **Entrée projetée**, un **Stop Loss** et **TP1 à TP5**.
- Tant que le moteur n’est pas en `EXECUTE_NOW`, ces niveaux restent des projections d’analyse et l’EA ne les utilise pas pour ouvrir un ordre.
- Un BUY/SELL final doit toujours respecter les seuils de conditions, le score d’exécution, les garde-fous de risque et le consensus open source.

### EA v1.50 — gestion intelligente

L’EA v1.50 ajoute :

- protection contre une entrée trop éloignée du prix calculé ;
- contrôle du spread par rapport à la distance de risque ;
- choix dynamique de l’objectif final : TP3, TP4 ou TP5 selon la qualité du setup ;
- passage du Stop Loss au break-even après TP1 ;
- verrouillage progressif du profit : TP1 après TP2, TP2 après TP3 et TP3 après TP4 ;
- maintien du garde-fou `EXECUTE_NOW` et du veto de l’ensemble open source.

Cette gestion progressive réduit l’exposition d’un trade déjà favorable mais ne garantit ni l’atteinte des objectifs ni l’absence de perte.


## Intelligence v4.0 — Swing haute conviction

Le moteur v4.0 conserve les confirmations indépendantes et durcit le Swing :

- alignement obligatoire H1/H4/D1 ;
- score minimal 84/100 et consensus pondéré minimal 72 % ;
- au moins 80 % des conditions applicables ;
- confirmation du même biais sur deux cycles successifs (`1/2`, puis `2/2`) ;
- qualité minimale H1/H4/D1 et force ADX/DMI sur les trois horizons ;
- rejet des zones d’épuisement RSI H4/D1, des flips récents et des régimes à risque ;
- uniquement des continuations de cassure ou de pullback pour un BUY/SELL Swing final.

Les confirmations techniques comprennent aussi :

- ADX / DMI pour la force et la direction de tendance ;
- MACD histogram pour l’alignement du momentum ;
- Bollinger squeeze/release pour les changements de régime ;
- Donchian breakout pour les cassures ;
- Efficiency Ratio pour distinguer tendance propre et bruit ;
- structure HH/HL ou LH/LL ;
- pattern Engulfing dans les contextes de reversal/pullback.

Ces règles réduisent fortement le nombre de signaux et visent des mouvements plus longs, mais elles ne peuvent garantir l’absence de retournement ni un résultat positif.

## EA réel v1.60

L’EA v1.60 conserve le risque par trade et ajoute des protections de compte réel :

- perte maximale par trade : **1 USD** par défaut ;
- risque : **0,50 %** du solde, plafonné par la limite USD ;
- maximum **1 position Sera** ouverte ;
- maximum **2 entrées par jour** ;
- circuit breaker à **3 USD de perte journalière** ;
- circuit breaker à **3 % de drawdown** ;
- pause après **2 pertes consécutives** ;
- contrôle de marge libre ;
- contrôle de la distance minimale SL/TP imposée par le broker ;
- contrôle spread, prix trop éloigné de l’entrée, consensus OSS et état `EXECUTE_NOW`.

Ces valeurs sont des garde-fous de départ et ne constituent pas une garantie de performance.

## Alertes Gmail Swing

Le workflow de cinq minutes peut envoyer automatiquement un email lorsqu’un **nouveau setup Swing** apparaît ou change de statut important.

Le message contient : instrument, BUY/SELL, entrée proposée, zone d’entrée, prix de référence, SL, TP1–TP5, amplitude pips/points, durée estimée, confiance, conditions, consensus stratégies, consensus des modèles open source et score d’exécution.

Pour activer l’envoi, configurer les trois Repository Secrets suivants dans GitHub :

- `GMAIL_ALERT_FROM` : compte Gmail expéditeur ;
- `GMAIL_APP_PASSWORD` : mot de passe d’application Google, jamais le mot de passe normal du compte ;
- `GMAIL_ALERT_TO` : adresse qui reçoit les alertes.

Les secrets ne sont pas écrits dans le dépôt ni affichés dans les logs.


## Sera EA Swing Intelligent v1.70

Le robot MT5 porte désormais le nom **Sera EA Swing Intelligent**.

### Ordres Swing intelligents

- `EXECUTE_NOW` : ordre BUY/SELL au marché si tous les garde-fous passent.
- `WAIT_RETRACE` avec BUY/SELL final confirmé : l’EA peut placer un **Buy Limit** ou **Sell Limit** dans la zone d’entrée calculée.
- Les pending orders ont une expiration automatique et sont supprimés si le setup devient invalide, change de sens ou passe à `EXECUTE_NOW`.
- Un simple setup détecté sans BUY/SELL final confirmé ne suffit pas pour placer un ordre réel.

### Lot adaptatif, sans martingale

Le volume reste calculé à partir de la distance réelle entre l’entrée et le Stop Loss. Le risque de base est **0,50 %** et peut augmenter progressivement jusqu’à **0,75 % maximum** lorsque l’équité progresse par paliers et que le compte reste sain.

Le moteur peut également appliquer un petit bonus de risque après une journée bénéficiaire. À l’inverse, une perte récente ou un drawdown réduit automatiquement le risque.

Le système ne double pas le lot après une perte : **aucune martingale**. Les limites de perte par trade, drawdown journalier, pertes consécutives, marge libre et volume maximum restent actives.


## Adaptive Evidence Engine

Sera possède désormais une mémoire d’expérience persistante. À chaque cycle, le moteur :

- enregistre les BUY/SELL confirmés avec leur marché, régime, type de setup, Entry, SL et TP1–TP5 ;
- rejoue les bougies suivantes de manière conservatrice pour déterminer si le SL, le break-even ou les objectifs ont été atteints ;
- construit une performance par **marché + mode + type de setup + régime** ;
- n’utilise cette mémoire qu’après un nombre minimum d’échantillons ;
- ajuste faiblement la confiance et le score d’exécution, avec un plafonnement strict ;
- peut rétrograder un `EXECUTE_NOW` en `WAIT_CONFIRMATION` si l’historique comparable devient mauvais ;
- ne peut jamais créer un BUY/SELL, inverser la direction ou contourner les garde-fous.

Cette couche évite que Sera soit seulement un empilement d’indicateurs : il commence à mesurer ce qui fonctionne réellement dans ses propres décisions.


## Moteur v4.1 — corrections de fiabilité Swing

- **2 cycles = 2 bougies H1 clôturées distinctes.** Avant, chaque exécution de 5 minutes relisait la même bougie H1 et comptait un nouveau cycle : la confirmation `2/2` pouvait être atteinte en 5 minutes sur des données identiques. Le compteur n’avance désormais que lorsqu’une nouvelle bougie d’entrée (H1 en Swing, M15 en Day) est clôturée.
- **ADX réel (Wilder, 14).** L’ancien calcul utilisait une seule valeur DX brute, très bruitée, qui dépassait souvent 20 sans vraie tendance. RSI(14) et ATR(14) utilisent aussi le lissage de Wilder, comme MT5 et TradingView.
- **Garde-fou de fraîcheur.** Si la dernière bougie d’entrée clôturée est trop ancienne (Forex le week-end, flux interrompu), le marché reste sur `ATTENDRE` et aucun setup n’est affiché (`freshness_gate`, `candle_age_minutes`).
- **Forex H4/D1 alignés sur 22:00 UTC** (clôture New York), comme les graphiques des brokers MT5, au lieu de minuit UTC.
- **Bougies ouvertes exclues** dans tous les cas lors de l’agrégation H4/D1.
- **`mt5/Sera_Swing_Executor.mq5` corrigé** : il modifiait des paramètres `const` (erreur de compilation MQL5). Il est maintenant identique à `Sera_EA_Swing_Intelligent.mq5`, et la QA vérifie que les deux copies restent identiques.
- Les commits automatiques de `data/` ne relancent plus les tests navigateur Playwright à chaque cycle de 5 minutes.

## Graphique de position — Sera Chart Engine

Le graphique du popup d’analyse utilise désormais **TradingView Lightweight Charts** (gratuit, open source, Apache 2.0), intégré dans `vendor/` : aucun CDN, aucune clé, chargement rapide.

- jusqu’à **300 bougies**, zoom (molette ou pincement), défilement, axe du temps en heure locale ;
- **Entrée, SL, TP1–TP5** et zone d’entrée affichés sur l’axe des prix ;
- **boîtes risque / rendement** (vert vers TP3, rouge vers le SL) avec le ratio R:R, comme l’outil « Position » de TradingView ;
- **flèche BUY / SELL** sur la bougie du signal, **EMA20 / EMA50**, légende OHLC au survol ;
- choix de l’unité de temps : **H1 / H4 / D1** en Swing, **M15 / H1** en Day (Forex : H1 publié par le serveur) ;
- cadrage **Prix** (bougies seules), **Plan TP3** (par défaut) ou **Tout TP5**, et bouton ⟲ pour revenir aux dernières bougies.

Si la bibliothèque ne se charge pas, l’ancien graphique canvas reprend automatiquement la main.

### Corrections liées

- Les heures vides renvoyées par Yahoo (`null`) devenaient des bougies à **0** dans le moteur et faussaient l’ATR, les plus bas de swing et le D1 des paires Forex. Elles sont maintenant écartées.
- `liveEntryProposal` plantait sur une paire Forex avec setup détecté lorsqu’aucun prix Deriv live n’était disponible ; corrigé.

## Analyse en continu (quasi temps réel)

GitHub ne garantit pas les tâches planifiées : sur ce dépôt, le `cron` toutes les 5 minutes ne se déclenchait en pratique que toutes les 3 à 5 heures. Le workflow **Sera Autonomous Engine** relance donc lui-même le cycle suivant à la fin de chaque exécution (étape « Chain next cycle ») : une nouvelle analyse est publiée environ toutes les **6 à 10 minutes**, 24h/24. Le `cron` ne sert plus que de filet de sécurité pour relancer la chaîne si elle s’arrête.

- XGBoost et LightGBM tournent à chaque cycle ; Chronos-2 et TimesFM au plus toutes les ~14 minutes (horodatage `foundation_updated_at` dans `data/open-source-ai.json`).
- L’interface considère une analyse serveur comme exploitable pendant **20 minutes** ; les prix Deriv restent en direct par WebSocket.
- **Pause / reprise** : dans GitHub → *Settings* → *Secrets and variables* → *Actions* → *Variables*, créer `SERA_REALTIME` = `off` pour arrêter la chaîne ; supprimer la variable (puis lancer le workflow une fois via *Run workflow*) pour la relancer.

### Autres corrections

- Les indices **Volatility** étaient classés « DEX » (le mot « Index » contient « dex »), ce qui faussait le consensus de famille du moteur et les filtres de l’interface.
- Si `raw.githubusercontent.com` est injoignable, l’app utilise maintenant la copie publiée avec le site au lieu d’afficher une page vide.
- Les tests d’interface obsolètes ont été mis à jour : toute la suite Playwright passe.

## Temps réel dans l’application

- **Indices Deriv** : prix et bougies en direct (WebSocket Deriv), comme avant.
- **Forex** : l’application s’abonne aussi aux ticks Deriv des paires disponibles (`deriv_forex_symbols`, publié par le moteur à chaque cycle). Le prix de la carte passe de « SERVEUR » à « LIVE » et la bougie H1 en cours du graphique bouge tick par tick. Les paires absentes chez Deriv (souvent les exotiques) gardent le prix serveur.
- **Signaux** : relus toutes les **20 secondes** ; l’interface n’est reconstruite que lorsqu’une nouvelle analyse arrive. Une coupure réseau passagère ne fait plus disparaître la dernière analyse.
- La décision BUY/SELL reste celle du moteur serveur (cycle continu de ~5 min) ; le prix live Forex est indicatif et doit être confirmé sur MT5.
