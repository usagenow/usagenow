# Changelog (French)

What's New in French: each version's changes, shorter than CHANGELOG.md. Headings stay in English; the app translates them. A version missing here shows in English.

## 1.0.0

### Added

- Kazakh, ouzbek et turc dans l’app et les widgets : treize langues. L’ouzbek utilise Ö, Ğ, Ş et Ç.
- Configuration initiale facultative avec choix des fournisseurs, à ignorer ou rouvrir dans Réglages. Les installations existantes conservent leurs choix. La première lecture commence après la configuration ou son abandon.
- Seuils par fournisseur, alertes de réinitialisation distinctes et heures silencieuses selon le fuseau du Mac. Les alertes ignorées ne s’accumulent pas ; les anciennes données ne déclenchent pas d’avertissement.
- CLI facultative : usagenow status et usagenow status --json lisent l’instantané sécurisé avec sa fraîcheur. Aucun appel fournisseur, authentification ou export d’historique. Installation dans Réglages › Général.
- Actualisation au réveil et vérification de la migration des notifications et des instantanés. La CLI retire les pourcentages après réinitialisation et refuse les formats incompatibles.

## 0.9.0

### Added

- **JetBrains AI (expérimental).** Limites locales d’AI Assistant depuis votre IDE JetBrains, avec la date de renouvellement indiquée, dans la barre des menus et les widgets. Les anciennes valeurs conservent leur date d’origine. Aucun identifiant ni appel réseau. La vérification avec AI Assistant actif reste à effectuer.
- **Widgets personnels.** Choisissez fournisseurs et comptes pour chaque widget, ou laissez la sélection vide pour suivre UsageNow. Renommer conserve le choix ; un compte supprimé n’est jamais remplacé silencieusement.
- **Grand widget.** Jusqu’à quatre lignes détaillées de fournisseurs et de comptes, avec deux fenêtres de quota et leurs réinitialisations. Il affiche uniquement l’instantané filtré.
- **Rythme de consommation.** Graphique local et estimation explicite pour la fenêtre la plus critique, à partir d’au moins trois relevés récents sur 15 minutes. Le cache, les données anciennes, les longues pauses, les réinitialisations et les durées inconnues ne produisent pas de prévision. Aucun calcul à partir des jetons.
- **Incidents des services en option.** Pages publiques d’OpenAI, Claude, Cursor et GitHub Copilot, désactivées par défaut et mises en cache dix minutes. État distinct de la connexion et des quotas ; aucune donnée de compte ou d’utilisation envoyée.
- **Néerlandais (Nederlands).** App, widgets et notes de version intégrées : dix langues désormais.
- **Nouvelles icônes Windsurf et ElevenLabs.** Logos adaptés aux apparences claire et sombre.

- **Antigravity sans IDE.** Si l’IDE ne répond pas, UsageNow lit le rapport officiel `agy /usage` des versions compatibles du CLI 1.x à partir de 1.1.11. Aucun tour d’agent ni accès aux identifiants par UsageNow ; cache de cinq minutes. Vérifié avec le CLI 1.2.2.

## 0.8.0

### Added

- Les clés, jetons et cookies sont vérifiés par une requête d’utilisation en lecture seule avant l’enregistrement. Des messages clairs distinguent identifiants, autorisations, réseau et trousseau ; annuler conserve la connexion précédente.
- En cas de HTTP 429, la connexion attend jusqu’à l’heure autorisée par le service, même lors d’une actualisation manuelle. Les autres comptes continuent et les anciennes données conservent leur date d’origine.
- Cursor, GitHub Copilot, Perplexity, ElevenLabs et Z.ai : connexion explicite dans Réglages, désactivée par défaut. Cursor et Perplexity proposent une fenêtre de connexion temporaire ou un cookie manuel ; Copilot utilise votre jeton GitHub. ElevenLabs utilise l’API officielle ; les quatre autres intégrations sont expérimentales. Pas encore vérifiées avec de vrais comptes.
- Les crédits et caractères du compte sont séparés de l’activité du jour. Aucun pourcentage inventé pour les quotas illimités ou inconnus.
- Windsurf : limites quotidiennes et hebdomadaires, réinitialisations et forfait depuis le cache local ; crédits du cycle de facturation pour les anciens forfaits. Aucun identifiant lu ni requête réseau. Pas encore vérifié avec une installation actuelle connectée.
- Portugais, japonais, coréen et hébreu : neuf langues au total. Le widget prend en charge la lecture de droite à gauche.
- « Nouveautés » est traduit dans toutes les langues de l’app et fonctionne hors ligne.
- Choisissez un compte ajouté pour la barre des menus, comme « Codex · Travail ». Sa suppression rétablit le compte principal du fournisseur.

### Fixed

- Le widget conserve la date des données de chaque fournisseur. Actualiser Codex ne fait plus paraître récents les anciens quotas Claude ; une horloge signale les données anciennes.
- Après une réinitialisation, l’ancien pourcentage devient inconnu jusqu’à l’arrivée de nouvelles données. Le compte à rebours continue entre les actualisations du widget.
- Une nouvelle lecture enregistre sa date même si le pourcentage ne change pas.

### Development

- Les builds Debug ont leurs propres identifiants et conteneur de données, sans perturber le widget installé. Les mises à jour automatiques sont désactivées ; les tests ne lancent aucun fournisseur réel.

## 0.7.2

### Fixed

- Confidentialité et À propos ne s’ouvraient pas en russe, en français ou en espagnol : les titres des onglets ne tenaient pas dans la fenêtre des réglages. Elle s’élargit désormais.

## 0.7.1

### Added

- Choisissez la langue d’UsageNow dans Réglages › Général › Langue : celle de macOS, ou l’allemand, l’anglais, l’espagnol, le français ou le russe. Le widget suit.
- Renommez un compte ajouté depuis son menu … dans Réglages › Fournisseurs.

### Changed

- Les actions d’un compte ajouté partagent un menu, pour que sa ligne tienne dans toutes les langues.
- Un dossier de compte vide ou manquant le signale, au lieu de vous demander de vous connecter.

### Fixed

- Ajouter un compte faisait relire aux autres comptes ajoutés leurs sessions du mois.

## 0.7.0

### Added

- Plus d’un compte : un second dossier Codex ou Claude Code, ou une autre clé d’API DeepSeek, Kimi, OpenRouter ou Ollama Cloud, chacun avec sa propre section — « Codex · Travail » — sous le nom de votre choix. UsageNow ne lit jamais le nom ni l’adresse e-mail du compte.
- Qwen Code — les tokens, requêtes et modèles du jour, et ce qu’ils auraient coûté, depuis les enregistrements de session que Qwen Code écrit sur votre Mac.
- Cline — les tokens, requêtes d’API et modèles du jour, avec le coût enregistré par Cline, depuis les tâches Cline de votre éditeur et la CLI Cline. Prompts, réponses et clés ne sont jamais lus.
- Grok Build — les tokens, appels au modèle et modèles du jour, avec le coût indiqué par xAI, depuis les journaux de session de Grok Build.
- Les deux dernières semaines dans le widget, pour les fournisseurs sans limites — la forme de votre activité, jamais de montants.
- UsageNow en allemand, espagnol, français et russe, selon la langue de votre Mac.
- Nouveautés dans Réglages › À propos : les modifications de chaque version, dans l’app.

### Changed

- Pour Cline et Grok Build, le coût affiché est celui enregistré par l’outil, pas une estimation.

## 0.6.1

### Added

- Notifications de limites : quand il reste 20 % d’une limite puis 5 %, une fois chacune, et quand une limite pour laquelle vous avez été averti est réinitialisée. Désactivées par défaut ; activez-les dans Réglages › Notifications.
- Un raccourci clavier personnel pour ouvrir UsageNow depuis n’importe quelle app. Enregistrez-le dans Réglages › Barre des menus. Aucune autorisation supplémentaire.

### Changed

- L’estimation de coût connaît Claude Sonnet 5.5 et GPT-6.1.

### Fixed

- « Réessayer », une clé d’API tout juste ajoutée ou un fournisseur tout juste activé pouvaient être ignorés pendant une actualisation.
- Antigravity ne retarde plus les autres fournisseurs pendant que UsageNow cherche son serveur de langage.
- Une ligne très longue dans un fichier de session est ignorée sans être chargée en mémoire.

## 0.6.0

### Added

- Les 30 derniers jours sous chaque fournisseur : une barre par jour, avec les tokens du mois, le coût estimé et le modèle le plus utilisé. Survolez une barre pour voir ce jour. Désactivez les graphiques dans Réglages › Général.
- OpenCode — tokens, requêtes et modèles du jour et leur coût, depuis la base locale d’OpenCode, en lecture seule. Prompts et réponses ne sont jamais lus.
- Qoder — crédits dépensés aujourd’hui et les réponses qu’ils ont payées, depuis les transcriptions que Qoder écrit sur votre Mac. La connexion de Qoder n’est jamais ouverte.
- Ollama Cloud (expérimental) — limites par session et hebdomadaires, avec votre propre clé Cloud API.
- Limites affichées en restant ou en utilisé, dans la fenêtre, la barre des menus et le widget.
- Crédits dans le widget pour Kiro, Warp et Qoder.
- Signaler un problème dans Réglages › À propos : voyez tout le rapport, puis envoyez-le vous-même en ticket GitHub ou par e-mail. Aucun nom, chemin, clé ni prompt.

### Changed

- La fenêtre de la barre des menus est plus opaque et défile au lieu de dépasser d’un petit écran.
- Réglages › Fournisseurs tient sur un écran de portable.
- L’estimation de coût connaît les modèles les plus récents, dont Claude Opus 5.5 et GPT-6.
- Lire un mois de fichiers de session est plusieurs fois plus rapide et consomme bien moins de mémoire.

### Fixed

- Les limites de Codex ne se mettaient plus à jour avec ChatGPT 26.9, qui a déplacé sa CLI Codex intégrée.
- Les limites Claude obsolètes indiquent maintenant comment les actualiser, pour qu’un pourcentage vieux d’une heure ne passe pas pour actuel.
- Le widget lit les données d’une app plus récente au lieu de vous demander d’ouvrir UsageNow.
- UsageNow pouvait quitter sans prévenir si le app-server de Codex se terminait trop tôt.

## 0.5.0

### Added

- Kiro — la limite mensuelle de crédits de votre forfait, sa date de réinitialisation, et les crédits et prompts du jour, d’après ce que Kiro écrit sur votre Mac. Aucune requête à Kiro, aucun identifiant Kiro.
- Warp — requêtes de l’agent, crédits et tokens par modèle du jour, depuis la base locale de Warp, en lecture seule.
- DeepSeek, Kimi et OpenRouter — soldes et dépenses via leurs API officielles, avec votre propre clé d’API. La clé reste dans votre trousseau et ne va qu’à ce fournisseur. Aucun des trois n’a encore été vérifié sur un vrai compte.

## 0.4.0

### Added

- Ce que coûteraient les tokens du jour : une estimation à côté des totaux de chaque fournisseur, aux tarifs publiés de l’API, les tokens en cache au tarif du cache. Un ordre de grandeur, pas une facture — un abonnement ne facture pas au token.
- Mises à jour dans l’app. UsageNow recherche et installe ses propres mises à jour, uniquement celles qui portent sa signature. La vérification n’envoie rien sur vous. Depuis la 0.3.0, installez la 0.4.0 à la main une fois.

### Changed

- L’actualisation dessine un arc de progression autour de la flèche au lieu de faire tourner l’icône.
- Le pourcentage de la barre des menus est dimensionné comme les icônes voisines.

## 0.3.0

### Added

- Antigravity — limites sur 5 heures et à la semaine par groupe de modèles, et votre forfait, depuis l’app Antigravity tant qu’elle tourne. Aucun identifiant, rien au-delà de 127.0.0.1.
- Gemini CLI — tokens, requêtes et modèles depuis ses enregistrements de session locaux. Il ne fournit aucune limite, donc aucune n’est affichée.
- Activité par modèle : une liste « Modèles du jour » pour Codex, Claude Code et Gemini CLI, le plus actif en premier.
- Forfaits Team : Claude affiche le siège, comme Team · Premium ; Codex affiche Team, Business et Enterprise.
- Modes de barre des menus pour Antigravity et Gemini CLI.
- Réorganisez les fournisseurs en les faisant glisser dans les réglages ; la fenêtre et le widget suivent.
- Cursor et GitHub Copilot apparaissent comme « bientôt ».

### Changed

- À partir de trois fournisseurs, le widget moyen affiche une ligne chacun et le petit jusqu’à trois — les plus proches d’une limite d’abord.
- Un fournisseur ajouté par une mise à jour démarre activé une fois. Ceux que vous avez désactivés le restent.

### Fixed

- Les limites Claude ne demandent plus votre mot de passe de session et reviennent d’elles-mêmes après avoir lancé Claude Code.
- Une fenêtre de limite Claude réinitialisée pendant votre absence reste visible, et les limites atteintes s’affichent sans aucune connexion.
- Les dernières limites Claude connues survivent à la fermeture ou à la mise à jour de l’app.

## 0.2.0

### Added

- De vraies données : limites, réinitialisations et forfait de Codex depuis le app-server officiel ; tokens, requêtes et dernier modèle de Codex et Claude Code depuis les fichiers de session locaux.
- Widgets de bureau en petite et moyenne taille.
- Limites d’utilisation de Claude Code — expérimentales et désactivées par défaut.
- Codex et Claude Code peuvent être activés ou désactivés séparément.
- Modes de barre des menus : icône seule, utilisation la plus critique ou un fournisseur.
- Apparence claire, sombre ou système.

### Changed

- L’utilisation s’affiche en restant — « 58 % restant » — et les barres raccourcissent à mesure que vous consommez.
- Les fenêtres de limite apparaissent telles que le fournisseur les signale ; une fenêtre manquante n’est jamais inventée.
- Quand les limites ne peuvent pas être lues, les dernières valeurs connues restent une journée, marquées comme obsolètes, avec une raison en une ligne.

## 0.1.0

### Added

- L’app native de barre des menus, ses réglages et ses états, avec des données d’exemple.
