#!/usr/bin/env python3
"""Writes UsageNow's Russian, German, Spanish, and French translations into
Shared/Resources/Localizable.xcstrings.

The catalog is the source of truth at run time; this file is where the
translations are kept and reviewed as text. Run it after adding strings
(scripts/sync-strings.sh first, so new keys are in the catalog), then
translate whatever it reports as missing.

Terms follow each language's macOS: строка меню / Menüleiste / barra de menús /
barre des menus, Связка ключей / Schlüsselbund / Llavero / trousseau, and so on.
German uses "du", as macOS does.

Usage: scripts/translations.py
"""

from __future__ import annotations

import json
import pathlib
import sys

LANGUAGES = ("ru", "de", "es", "fr")

# key: (ru, de, es, fr). Keys with several arguments use positional
# specifiers, as the English values in the catalog do.
T: dict[str, tuple[str, str, str, str]] = {
    "%@ %@ usage": ("Использование: %1$@ %2$@", "Nutzung: %1$@ %2$@", "Uso: %1$@ %2$@", "Utilisation : %1$@ %2$@"),
    "%@ API key": ("Ключ API %@", "%@-API-Schlüssel", "Clave de API de %@", "Clé d’API %@"),
    "%@ credits": ("%@ кредитов", "%@ Credits", "%@ créditos", "%@ crédits"),
    "%@ credits today": ("%@ кредитов сегодня", "%@ Credits heute", "%@ créditos hoy", "%@ crédits aujourd’hui"),
    "%@ didn’t accept the API key. Check it in Settings › Providers.": (
        "%@ не принял ключ API. Проверьте его в Настройки › Провайдеры.",
        "%@ hat den API-Schlüssel nicht akzeptiert. Prüfe ihn unter Einstellungen › Anbieter.",
        "%@ no aceptó la clave de API. Revísala en Ajustes › Proveedores.",
        "%@ n’a pas accepté la clé d’API. Vérifiez-la dans Réglages › Fournisseurs.",
    ),
    "%@ isn’t installed": ("%@ не установлен", "%@ ist nicht installiert", "%@ no está instalado", "%@ n’est pas installé"),
    "%@ left": ("осталось %@", "%@ übrig", "queda %@", "%@ restant"),
    "%@ plan": ("План %@", "%@-Tarif", "Plan %@", "Forfait %@"),
    "%@ tokens": ("%@ токенов", "%@ Tokens", "%@ tokens", "%@ tokens"),
    "%@ tokens today": ("%@ токенов сегодня", "%@ Tokens heute", "%@ tokens hoy", "%@ tokens aujourd’hui"),
    "%@ tokens, %@ requests": ("%1$@ токенов, запросов: %2$@", "%1$@ Tokens, %2$@ Anfragen", "%1$@ tokens, %2$@ solicitudes", "%1$@ tokens, %2$@ requêtes"),
    "%@ usage": ("Использование: %@", "Nutzung: %@", "Uso: %@", "Utilisation : %@"),
    "%@ used": ("использовано %@", "%@ verbraucht", "%@ usado", "%@ utilisé"),
    "%@: %@ limit has reset": (
        "%1$@: лимит «%2$@» обновился",
        "%1$@: Limit „%2$@“ wurde zurückgesetzt",
        "%1$@: el límite «%2$@» se ha restablecido",
        "%1$@ : la limite « %2$@ » a été réinitialisée",
    ),
    "%@: %@ limit reached": (
        "%1$@: лимит «%2$@» исчерпан",
        "%1$@: Limit „%2$@“ erreicht",
        "%1$@: límite «%2$@» alcanzado",
        "%1$@ : limite « %2$@ » atteinte",
    ),
    "%@: %@ of the %@ limit left": (
        "%1$@: осталось %2$@ лимита «%3$@»",
        "%1$@: %2$@ vom Limit „%3$@“ übrig",
        "%1$@: queda el %2$@ del límite «%3$@»",
        "%1$@ : il reste %2$@ de la limite « %3$@ »",
    ),
    "%@: %@ of the %@ limit used": (
        "%1$@: использовано %2$@ лимита «%3$@»",
        "%1$@: %2$@ vom Limit „%3$@“ verbraucht",
        "%1$@: usado el %2$@ del límite «%3$@»",
        "%1$@ : %2$@ de la limite « %3$@ » utilisés",
    ),
    "%lld-day": ("%lld дн.", "%lld Tage", "%lld días", "%lld jours"),
    "%lld-hour": ("%lld ч", "%lld Std.", "%lld horas", "%lld heures"),
    "%lld-minute": ("%lld мин", "%lld Min.", "%lld minutos", "%lld minutes"),
    # Countdowns stay compact: the widget gives them a narrow column.
    "%lldd %lldh": ("%1$lldд %2$lldч", "%1$lldT %2$lldh", "%1$lldd %2$lldh", "%1$lldj %2$lldh"),
    "%lldd ago": ("%lld д назад", "vor %lld T", "hace %lld d", "il y a %lld j"),
    "%lldh %@m": ("%1$lldч %2$@м", "%1$lldh %2$@m", "%1$lldh %2$@m", "%1$lldh %2$@m"),
    "%lldh ago": ("%lld ч назад", "vor %lld Std.", "hace %lld h", "il y a %lld h"),
    "%lldm": ("%lld мин", "%lld Min.", "%lld min", "%lld min"),
    "unit.left.short": ("ост.", "übrig", "rest.", "rest."),
    "unit.used.short": ("исп.", "verbr.", "usado", "util."),
    "%lldm ago": ("%lld мин назад", "vor %lld Min.", "hace %lld min", "il y a %lld min"),
    "+%lld more": ("ещё %lld", "+%lld weitere", "+%lld más", "+%lld autres"),
    "15 minutes": ("15 минут", "15 Minuten", "15 minutos", "15 minutes"),
    "30 minutes": ("30 минут", "30 Minuten", "30 minutos", "30 minutes"),
    "5 minutes": ("5 минут", "5 Minuten", "5 minutos", "5 minutes"),
    "5-hour": ("5 часов", "5 Stunden", "5 horas", "5 heures"),
    "A chart of daily activity under each provider in the menu bar window. Turn it off to keep the window short.": (
        "График дневной активности под каждым провайдером в окне строки меню. Выключите, чтобы окно было короче.",
        "Ein Diagramm der täglichen Aktivität unter jedem Anbieter im Menüleistenfenster. Schalte es aus, um das Fenster kurz zu halten.",
        "Un gráfico de la actividad diaria bajo cada proveedor en la ventana de la barra de menús. Desactívalo para que la ventana sea más corta.",
        "Un graphique de l’activité quotidienne sous chaque fournisseur dans la fenêtre de la barre des menus. Désactivez-le pour garder la fenêtre courte.",
    ),
    "AI coding usage tracker for macOS": (
        "Трекер использования ИИ для программирования на macOS",
        "Nutzungs-Tracker für KI-Coding auf macOS",
        "Monitor de uso de IA para programar en macOS",
        "Suivi de l’utilisation de l’IA pour coder sur macOS",
    ),
    "API key": ("Ключ API", "API-Schlüssel", "Clave de API", "Clé d’API"),
    "API key saved": ("Ключ API сохранён", "API-Schlüssel gesichert", "Clave de API guardada", "Clé d’API enregistrée"),
    "API keys can usually spend money, not just read it. If %@ lets you, create a separate key for UsageNow.": (
        "Ключи API обычно позволяют тратить деньги, а не только читать данные. Если %@ это позволяет, создайте отдельный ключ для UsageNow.",
        "API-Schlüssel können meist Geld ausgeben, nicht nur Daten lesen. Wenn %@ es erlaubt, erstelle einen eigenen Schlüssel für UsageNow.",
        "Las claves de API suelen poder gastar dinero, no solo leer datos. Si %@ lo permite, crea una clave aparte para UsageNow.",
        "Les clés d’API permettent généralement de dépenser de l’argent, pas seulement de lire des données. Si %@ le permet, créez une clé distincte pour UsageNow.",
    ),
    "About": ("О программе", "Über", "Acerca de", "À propos"),
    "Activity, last 14 days": ("Активность за 14 дней", "Aktivität, letzte 14 Tage", "Actividad, últimos 14 días", "Activité, 14 derniers jours"),
    "Activity, last 30 days": ("Активность за 30 дней", "Aktivität, letzte 30 Tage", "Actividad, últimos 30 días", "Activité, 30 derniers jours"),
    "Add API Key…": ("Добавить ключ API…", "API-Schlüssel hinzufügen …", "Añadir clave de API…", "Ajouter une clé d’API…"),
    "Allow UsageNow in System Settings to finish setup.": (
        "Разрешите UsageNow в Системных настройках, чтобы завершить настройку.",
        "Erlaube UsageNow in den Systemeinstellungen, um die Einrichtung abzuschließen.",
        "Permite UsageNow en Ajustes del Sistema para terminar la configuración.",
        "Autorisez UsageNow dans Réglages Système pour terminer la configuration.",
    ),
    "Allow UsageNow to access your Claude Code sign-in in Keychain.": (
        "Разрешите UsageNow доступ к входу Claude Code в Связке ключей.",
        "Erlaube UsageNow den Zugriff auf deine Claude Code-Anmeldung im Schlüsselbund.",
        "Permite que UsageNow acceda a tu inicio de sesión de Claude Code en el Llavero.",
        "Autorisez UsageNow à accéder à votre connexion Claude Code dans le trousseau.",
    ),
    "Another app already uses this shortcut. Record a different one.": (
        "Это сочетание уже занято другим приложением. Запишите другое.",
        "Eine andere App verwendet diesen Kurzbefehl bereits. Nimm einen anderen auf.",
        "Otra app ya usa este atajo. Graba uno diferente.",
        "Une autre app utilise déjà ce raccourci. Enregistrez-en un autre.",
    ),
    "Antigravity usage": ("Использование Antigravity", "Antigravity-Nutzung", "Uso de Antigravity", "Utilisation d’Antigravity"),
    "Antigravity usage limits are temporarily unavailable.": (
        "Лимиты Antigravity временно недоступны.",
        "Die Nutzungslimits von Antigravity sind vorübergehend nicht verfügbar.",
        "Los límites de uso de Antigravity no están disponibles temporalmente.",
        "Les limites d’utilisation d’Antigravity sont temporairement indisponibles.",
    ),
    "Appearance": ("Оформление", "Erscheinungsbild", "Apariencia", "Apparence"),
    "Applies to the popover, the menu bar, and the widget.": (
        "Действует в окне UsageNow, строке меню и виджете.",
        "Gilt für das UsageNow-Fenster, die Menüleiste und das Widget.",
        "Se aplica a la ventana de UsageNow, la barra de menús y el widget.",
        "S’applique à la fenêtre UsageNow, à la barre des menus et au widget.",
    ),
    "Available": ("Доступные", "Verfügbar", "Disponibles", "Disponibles"),
    "Cancel": ("Отменить", "Abbrechen", "Cancelar", "Annuler"),
    "Check Now": ("Проверить", "Jetzt suchen", "Comprobar ahora", "Vérifier maintenant"),
    "Check for updates automatically": (
        "Проверять обновления автоматически",
        "Automatisch nach Updates suchen",
        "Buscar actualizaciones automáticamente",
        "Rechercher les mises à jour automatiquement",
    ),
    "Checking usage…": ("Проверка использования…", "Nutzung wird geprüft …", "Comprobando el uso…", "Vérification de l’utilisation…"),
    "Choose a provider in Settings to start tracking usage.": (
        "Выберите провайдера в настройках, чтобы начать отслеживание.",
        "Wähle in den Einstellungen einen Anbieter, um die Nutzung zu verfolgen.",
        "Elige un proveedor en Ajustes para empezar a seguir el uso.",
        "Choisissez un fournisseur dans les réglages pour commencer le suivi.",
    ),
    "Choose which services UsageNow displays and monitors, and drag them into the order you want.": (
        "Выберите сервисы, которые UsageNow показывает и отслеживает, и перетащите их в нужном порядке.",
        "Wähle, welche Dienste UsageNow anzeigt und überwacht, und zieh sie in die gewünschte Reihenfolge.",
        "Elige qué servicios muestra y supervisa UsageNow, y arrástralos en el orden que quieras.",
        "Choisissez les services que UsageNow affiche et surveille, et faites-les glisser dans l’ordre voulu.",
    ),
    "Claude Code usage": ("Использование Claude Code", "Claude Code-Nutzung", "Uso de Claude Code", "Utilisation de Claude Code"),
    "Claude usage limits are temporarily unavailable.": (
        "Лимиты Claude временно недоступны.",
        "Die Nutzungslimits von Claude sind vorübergehend nicht verfügbar.",
        "Los límites de uso de Claude no están disponibles temporalmente.",
        "Les limites d’utilisation de Claude sont temporairement indisponibles.",
    ),
    "Claude usage limits — Experimental": (
        "Лимиты Claude — экспериментально",
        "Claude-Nutzungslimits – experimentell",
        "Límites de uso de Claude — experimental",
        "Limites d’utilisation de Claude — expérimental",
    ),
    "Codex usage": ("Использование Codex", "Codex-Nutzung", "Uso de Codex", "Utilisation de Codex"),
    "Coming soon": ("Скоро", "Demnächst", "Próximamente", "Bientôt"),
    "Copied": ("Скопировано", "Kopiert", "Copiado", "Copié"),
    "Copy": ("Скопировать", "Kopieren", "Copiar", "Copier"),
    "Couldn’t refresh %@": ("Не удалось обновить %@", "%@ konnte nicht aktualisiert werden", "No se pudo actualizar %@", "Impossible d’actualiser %@"),
    "Create a key on %@…": ("Создать ключ на %@…", "Schlüssel bei %@ erstellen …", "Crear una clave en %@…", "Créer une clé sur %@…"),
    "Credits": ("Кредиты", "Credits", "Créditos", "Crédits"),
    "Dark": ("Тёмное", "Dunkel", "Oscuro", "Sombre"),
    "Day": ("День", "Tag", "Día", "Jour"),
    "Display": ("Показывать", "Anzeige", "Mostrar", "Affichage"),
    "Done": ("Готово", "Fertig", "OK", "OK"),
    "Email…": ("Письмо…", "E-Mail …", "Correo…", "E-mail…"),
    "Estimated cost at API prices": (
        "Примерная стоимость по ценам API",
        "Geschätzte Kosten zu API-Preisen",
        "Coste estimado a precios de API",
        "Coût estimé aux tarifs de l’API",
    ),
    "Experimental": ("Экспериментально", "Experimentell", "Experimental", "Expérimental"),
    "Experimental: %@ doesn’t document how to read usage, so this may stop working without notice. If it does, UsageNow shows limits as unavailable rather than guessing.": (
        "Экспериментально: %@ не документирует, как читать использование, поэтому это может перестать работать без предупреждения. Тогда UsageNow покажет, что лимиты недоступны, а не будет угадывать.",
        "Experimentell: %@ dokumentiert nicht, wie sich die Nutzung auslesen lässt, daher kann das ohne Vorwarnung aufhören zu funktionieren. Dann zeigt UsageNow die Limits als nicht verfügbar an, statt zu raten.",
        "Experimental: %@ no documenta cómo leer el uso, así que podría dejar de funcionar sin aviso. Si ocurre, UsageNow mostrará los límites como no disponibles en vez de adivinar.",
        "Expérimental : %@ ne documente pas la lecture de l’utilisation, cela peut donc cesser de fonctionner sans préavis. Dans ce cas, UsageNow affiche les limites comme indisponibles plutôt que de deviner.",
    ),
    "Fetch Claude usage limits": (
        "Получать лимиты Claude",
        "Claude-Nutzungslimits abrufen",
        "Obtener los límites de uso de Claude",
        "Récupérer les limites d’utilisation de Claude",
    ),
    "Fetch current Claude Code subscription limits directly from Anthropic using your existing Claude Code sign-in. This uses an undocumented Anthropic endpoint and may stop working without notice.": (
        "Получать текущие лимиты подписки Claude Code напрямую у Anthropic с помощью вашего входа в Claude Code. Используется недокументированный эндпоинт Anthropic, он может перестать работать без предупреждения.",
        "Ruft die aktuellen Limits deines Claude Code-Abos direkt bei Anthropic ab, mit deiner bestehenden Claude Code-Anmeldung. Dafür wird ein nicht dokumentierter Anthropic-Endpunkt verwendet, der ohne Vorwarnung aufhören kann zu funktionieren.",
        "Obtiene los límites actuales de tu suscripción a Claude Code directamente de Anthropic con tu inicio de sesión de Claude Code. Usa un endpoint no documentado de Anthropic y podría dejar de funcionar sin aviso.",
        "Récupère les limites actuelles de votre abonnement Claude Code directement auprès d’Anthropic, avec votre connexion Claude Code existante. Cela utilise un point de terminaison Anthropic non documenté, qui peut cesser de fonctionner sans préavis.",
    ),
    "Gemini CLI usage": ("Использование Gemini CLI", "Gemini CLI-Nutzung", "Uso de Gemini CLI", "Utilisation de Gemini CLI"),
    "General": ("Основные", "Allgemein", "General", "Général"),
    "Helps improve UsageNow by sharing basic app usage and device information.": (
        "Помогает улучшать UsageNow: передаёт общие сведения об использовании приложения и устройстве.",
        "Hilft, UsageNow zu verbessern, indem grundlegende Infos zur App-Nutzung und zum Gerät geteilt werden.",
        "Ayuda a mejorar UsageNow compartiendo información básica sobre el uso de la app y el dispositivo.",
        "Aide à améliorer UsageNow en partageant des informations de base sur l’utilisation de l’app et l’appareil.",
    ),
    "High usage": ("Высокое использование", "Hohe Nutzung", "Uso alto", "Utilisation élevée"),
    "Icon only": ("Только значок", "Nur Symbol", "Solo icono", "Icône seule"),
    "Install or use a supported AI coding tool to start tracking usage.": (
        "Установите или запустите поддерживаемый инструмент ИИ для программирования, чтобы начать отслеживание.",
        "Installiere oder nutze ein unterstütztes KI-Coding-Tool, um die Nutzung zu verfolgen.",
        "Instala o usa una herramienta de programación con IA compatible para empezar a seguir el uso.",
        "Installez ou utilisez un outil de code IA pris en charge pour commencer le suivi.",
    ),
    "Just now": ("Только что", "Gerade eben", "Ahora mismo", "À l’instant"),
    "Keyboard shortcut": ("Сочетание клавиш", "Tastaturkurzbefehl", "Atajo de teclado", "Raccourci clavier"),
    "Kiro usage": ("Использование Kiro", "Kiro-Nutzung", "Uso de Kiro", "Utilisation de Kiro"),
    "Last 30 days": ("За 30 дней", "Letzte 30 Tage", "Últimos 30 días", "30 derniers jours"),
    "Last checked %@": ("Последняя проверка: %@", "Zuletzt geprüft: %@", "Última comprobación: %@", "Dernière vérification : %@"),
    "Launch UsageNow at login": (
        "Открывать UsageNow при входе",
        "UsageNow bei der Anmeldung öffnen",
        "Abrir UsageNow al iniciar sesión",
        "Ouvrir UsageNow à l’ouverture de session",
    ),
    "Light": ("Светлое", "Hell", "Claro", "Clair"),
    "Limits are checked when UsageNow refreshes. Notifications come from this Mac; nothing is sent anywhere.": (
        "Лимиты проверяются при обновлении UsageNow. Уведомления приходят с этого Mac, ничего никуда не отправляется.",
        "Limits werden geprüft, wenn UsageNow aktualisiert. Mitteilungen kommen von diesem Mac; nichts wird irgendwohin gesendet.",
        "Los límites se comprueban cuando UsageNow se actualiza. Las notificaciones vienen de este Mac; no se envía nada a ningún sitio.",
        "Les limites sont vérifiées lorsque UsageNow s’actualise. Les notifications viennent de ce Mac ; rien n’est envoyé nulle part.",
    ),
    "Limits unavailable": ("Лимиты недоступны", "Limits nicht verfügbar", "Límites no disponibles", "Limites indisponibles"),
    "Manual": ("Вручную", "Manuell", "Manual", "Manuel"),
    "Menu Bar": ("Строка меню", "Menüleiste", "Barra de menús", "Barre des menus"),
    "Models today": ("Модели сегодня", "Modelle heute", "Modelos hoy", "Modèles aujourd’hui"),
    "Monthly": ("Месяц", "Monatlich", "Mensual", "Mensuel"),
    "Most critical usage": ("Ближе всего к лимиту", "Kritischste Nutzung", "Uso más crítico", "Utilisation la plus critique"),
    "Move Down": ("Переместить ниже", "Nach unten", "Bajar", "Descendre"),
    "Move Up": ("Переместить выше", "Nach oben", "Subir", "Monter"),
    "Nearly exhausted": ("Почти исчерпан", "Fast aufgebraucht", "Casi agotado", "Presque épuisé"),
    "Never includes prompts, tokens, project names, files, credentials, or coding activity.": (
        "Никогда не включает промпты, токены, названия проектов, файлы, учётные данные или код.",
        "Enthält niemals Prompts, Tokens, Projektnamen, Dateien, Zugangsdaten oder Programmieraktivität.",
        "Nunca incluye prompts, tokens, nombres de proyectos, archivos, credenciales ni actividad de programación.",
        "N’inclut jamais de prompts, de tokens, de noms de projet, de fichiers, d’identifiants ni d’activité de code.",
    ),
    "Next reset": ("Сброс через", "Nächster Reset", "Próximo reinicio", "Prochain reset"),
    "No API key yet": ("Ключа API ещё нет", "Noch kein API-Schlüssel", "Aún no hay clave de API", "Pas encore de clé d’API"),
    "No activity": ("Нет активности", "Keine Aktivität", "Sin actividad", "Aucune activité"),
    "No providers detected": ("Провайдеры не найдены", "Keine Anbieter gefunden", "No se detectaron proveedores", "Aucun fournisseur détecté"),
    "No providers enabled": ("Провайдеры не включены", "Keine Anbieter aktiviert", "No hay proveedores activados", "Aucun fournisseur activé"),
    "None": ("Нет", "Keiner", "Ninguno", "Aucun"),
    "Not checked yet": ("Ещё не проверялось", "Noch nicht geprüft", "Aún no comprobado", "Pas encore vérifié"),
    "Notifications": ("Уведомления", "Mitteilungen", "Notificaciones", "Notifications"),
    "Notifications are turned off for UsageNow in System Settings.": (
        "Уведомления для UsageNow выключены в Системных настройках.",
        "Mitteilungen für UsageNow sind in den Systemeinstellungen deaktiviert.",
        "Las notificaciones de UsageNow están desactivadas en Ajustes del Sistema.",
        "Les notifications de UsageNow sont désactivées dans Réglages Système.",
    ),
    "Notify me about limits": ("Уведомлять о лимитах", "Über Limits benachrichtigen", "Avisarme de los límites", "M’avertir des limites"),
    "Open %@ to update usage limits.": (
        "Откройте %@, чтобы обновить лимиты.",
        "Öffne %@, um die Nutzungslimits zu aktualisieren.",
        "Abre %@ para actualizar los límites de uso.",
        "Ouvrez %@ pour actualiser les limites d’utilisation.",
    ),
    "Open GitHub Issue…": ("Открыть issue на GitHub…", "GitHub-Issue öffnen …", "Abrir issue en GitHub…", "Ouvrir un ticket GitHub…"),
    "Open Login Items…": ("Открыть «Объекты входа»…", "Anmeldeobjekte öffnen …", "Abrir Ítems de inicio…", "Ouvrir les éléments d’ouverture…"),
    "Open Notification Settings…": (
        "Открыть настройки уведомлений…",
        "Mitteilungseinstellungen öffnen …",
        "Abrir ajustes de notificaciones…",
        "Ouvrir les réglages des notifications…",
    ),
    "Open Provider Settings": (
        "Открыть настройки провайдеров",
        "Anbietereinstellungen öffnen",
        "Abrir ajustes de proveedores",
        "Ouvrir les réglages des fournisseurs",
    ),
    "Open Source Licenses": ("Лицензии открытого ПО", "Open-Source-Lizenzen", "Licencias de código abierto", "Licences open source"),
    "Open Source Licenses…": ("Лицензии открытого ПО…", "Open-Source-Lizenzen …", "Licencias de código abierto…", "Licences open source…"),
    "Open UsageNow": ("Откройте UsageNow", "UsageNow öffnen", "Abre UsageNow", "Ouvrez UsageNow"),
    "Open UsageNow to choose providers.": (
        "Откройте UsageNow, чтобы выбрать провайдеров.",
        "Öffne UsageNow, um Anbieter auszuwählen.",
        "Abre UsageNow para elegir proveedores.",
        "Ouvrez UsageNow pour choisir des fournisseurs.",
    ),
    "Open UsageNow to load usage data.": (
        "Откройте UsageNow, чтобы загрузить данные.",
        "Öffne UsageNow, um Nutzungsdaten zu laden.",
        "Abre UsageNow para cargar los datos de uso.",
        "Ouvrez UsageNow pour charger les données d’utilisation.",
    ),
    "Open the Antigravity app to update usage limits.": (
        "Откройте приложение Antigravity, чтобы обновить лимиты.",
        "Öffne die Antigravity-App, um die Nutzungslimits zu aktualisieren.",
        "Abre la app Antigravity para actualizar los límites de uso.",
        "Ouvrez l’app Antigravity pour actualiser les limites d’utilisation.",
    ),
    "Opens and closes UsageNow from any app.": (
        "Открывает и закрывает UsageNow из любого приложения.",
        "Öffnet und schließt UsageNow aus jeder App.",
        "Abre y cierra UsageNow desde cualquier app.",
        "Ouvre et ferme UsageNow depuis n’importe quelle app.",
    ),
    "Press a shortcut…": ("Нажмите сочетание…", "Kurzbefehl drücken …", "Pulsa un atajo…", "Appuyez sur un raccourci…"),
    "Privacy": ("Конфиденциальность", "Datenschutz", "Privacidad", "Confidentialité"),
    "Providers": ("Провайдеры", "Anbieter", "Proveedores", "Fournisseurs"),
    "Quit": ("Завершить", "Beenden", "Salir", "Quitter"),
    "Quit UsageNow": ("Завершить UsageNow", "UsageNow beenden", "Salir de UsageNow", "Quitter UsageNow"),
    "Record Shortcut": ("Записать сочетание", "Kurzbefehl aufnehmen", "Grabar atajo", "Enregistrer un raccourci"),
    "Refresh": ("Обновить", "Aktualisieren", "Actualizar", "Actualiser"),
    "Refresh Claude Code from Terminal to view usage limits.": (
        "Обновите вход Claude Code в Терминале, чтобы видеть лимиты.",
        "Melde dich im Terminal erneut bei Claude Code an, um die Nutzungslimits zu sehen.",
        "Actualiza Claude Code desde Terminal para ver los límites de uso.",
        "Actualisez Claude Code depuis Terminal pour voir les limites d’utilisation.",
    ),
    "Refresh interval": ("Интервал обновления", "Aktualisierungsintervall", "Intervalo de actualización", "Intervalle d’actualisation"),
    "Refreshing…": ("Обновление…", "Wird aktualisiert …", "Actualizando…", "Actualisation…"),
    "Remaining": ("Осталось", "Verbleibend", "Restante", "Restant"),
    "Remove": ("Удалить", "Entfernen", "Eliminar", "Supprimer"),
    "Remove shortcut": ("Удалить сочетание", "Kurzbefehl entfernen", "Eliminar atajo", "Supprimer le raccourci"),
    "Replace…": ("Заменить…", "Ersetzen …", "Reemplazar…", "Remplacer…"),
    "Report a Problem": ("Сообщить о проблеме", "Problem melden", "Informar de un problema", "Signaler un problème"),
    "Report a Problem…": ("Сообщить о проблеме…", "Problem melden …", "Informar de un problema…", "Signaler un problème…"),
    "Requests": ("Запросы", "Anfragen", "Solicitudes", "Requêtes"),
    "Reset %@ · not updated since": (
        "Сброс %@ · с тех пор не обновлялось",
        "Zurückgesetzt %@ · seitdem nicht aktualisiert",
        "Reinicio %@ · sin actualizar desde entonces",
        "Réinitialisé %@ · pas mis à jour depuis",
    ),
    "Resets %@": ("Сброс %@", "Zurücksetzung %@", "Se reinicia el %@", "Réinitialisation %@"),
    "Resets in %@": ("Сброс через %@", "Zurücksetzung in %@", "Se reinicia en %@", "Réinitialisation dans %@"),
    "Resetting now": ("Сбрасывается", "Wird zurückgesetzt", "Reiniciándose", "Réinitialisation en cours"),
    "Retry": ("Повторить", "Erneut versuchen", "Reintentar", "Réessayer"),
    "Retry refreshing %@": ("Повторить обновление %@", "%@ erneut aktualisieren", "Reintentar actualizar %@", "Réessayer d’actualiser %@"),
    "Save": ("Сохранить", "Sichern", "Guardar", "Enregistrer"),
    "Settings…": ("Настройки…", "Einstellungen …", "Ajustes…", "Réglages…"),
    "Share anonymous usage analytics": (
        "Отправлять анонимную аналитику",
        "Anonyme Nutzungsanalysen teilen",
        "Compartir análisis de uso anónimos",
        "Partager des statistiques d’utilisation anonymes",
    ),
    "Show limits as": ("Показывать лимиты как", "Limits anzeigen als", "Mostrar límites como", "Afficher les limites en"),
    "Show the last 30 days": ("Показывать последние 30 дней", "Die letzten 30 Tage anzeigen", "Mostrar los últimos 30 días", "Afficher les 30 derniers jours"),
    "Shows the icon alone when no usage limit is available.": (
        "Если лимитов нет, показывается только значок.",
        "Zeigt nur das Symbol, wenn kein Nutzungslimit verfügbar ist.",
        "Muestra solo el icono cuando no hay ningún límite de uso disponible.",
        "Affiche uniquement l’icône lorsqu’aucune limite d’utilisation n’est disponible.",
    ),
    "Sign in to %@ to view usage": (
        "Войдите в %@, чтобы видеть использование",
        "Melde dich bei %@ an, um die Nutzung zu sehen",
        "Inicia sesión en %@ para ver el uso",
        "Connectez-vous à %@ pour voir l’utilisation",
    ),
    "System": ("Как в системе", "System", "Sistema", "Système"),
    "The UsageNow name, logo, icon, and other brand assets are not covered by the MIT License.": (
        "Название, логотип, значок и другие элементы бренда UsageNow не подпадают под лицензию MIT.",
        "Name, Logo, Symbol und andere Markenelemente von UsageNow fallen nicht unter die MIT-Lizenz.",
        "El nombre, el logotipo, el icono y otros elementos de marca de UsageNow no están cubiertos por la licencia MIT.",
        "Le nom, le logo, l’icône et les autres éléments de marque de UsageNow ne sont pas couverts par la licence MIT.",
    ),
    "The balance can’t pay for more requests.": (
        "Баланса не хватает на новые запросы.",
        "Das Guthaben reicht für keine weiteren Anfragen.",
        "El saldo no alcanza para más solicitudes.",
        "Le solde ne permet plus de payer de requêtes.",
    ),
    "The full limit is available again.": (
        "Лимит снова доступен полностью.",
        "Das volle Limit ist wieder verfügbar.",
        "Vuelves a tener el límite completo.",
        "La limite complète est de nouveau disponible.",
    ),
    "The key couldn’t be saved to the Keychain.": (
        "Не удалось сохранить ключ в Связке ключей.",
        "Der Schlüssel konnte nicht im Schlüsselbund gesichert werden.",
        "No se pudo guardar la clave en el Llavero.",
        "Impossible d’enregistrer la clé dans le trousseau.",
    ),
    "This build can't update itself: it wasn't made by the release process, which is what signs an update.": (
        "Эта сборка не может обновляться сама: она собрана не в процессе выпуска, который подписывает обновления.",
        "Dieser Build kann sich nicht selbst aktualisieren: Er stammt nicht aus dem Release-Prozess, der Updates signiert.",
        "Esta compilación no puede actualizarse sola: no se creó con el proceso de publicación, que es el que firma las actualizaciones.",
        "Cette version ne peut pas se mettre à jour seule : elle n’a pas été créée par le processus de publication, qui signe les mises à jour.",
    ),
    "This build doesn’t send analytics yet.": (
        "Эта сборка пока не отправляет аналитику.",
        "Dieser Build sendet noch keine Analysen.",
        "Esta compilación aún no envía análisis.",
        "Cette version n’envoie pas encore de statistiques.",
    ),
    "This is everything the report contains: versions, screens, settings, and what each provider shows. No names, emails, file paths, keys, or prompts. Nothing is sent until you send it yourself.": (
        "Это всё, что есть в отчёте: версии, экраны, настройки и то, что показывает каждый провайдер. Никаких имён, адресов почты, путей к файлам, ключей и промптов. Ничего не отправляется, пока вы не отправите отчёт сами.",
        "Das ist alles, was der Bericht enthält: Versionen, Bildschirme, Einstellungen und was jeder Anbieter anzeigt. Keine Namen, E-Mail-Adressen, Dateipfade, Schlüssel oder Prompts. Nichts wird gesendet, bis du es selbst sendest.",
        "Esto es todo lo que contiene el informe: versiones, pantallas, ajustes y lo que muestra cada proveedor. Sin nombres, correos, rutas de archivos, claves ni prompts. No se envía nada hasta que lo envíes tú.",
        "Voici tout ce que contient le rapport : versions, écrans, réglages et ce qu’affiche chaque fournisseur. Aucun nom, e-mail, chemin de fichier, clé ni prompt. Rien n’est envoyé tant que vous ne l’envoyez pas vous-même.",
    ),
    "Tokens": ("Токены", "Tokens", "Tokens", "Tokens"),
    "Track Antigravity limits while the Antigravity app runs.": (
        "Лимиты Antigravity, пока запущено приложение Antigravity.",
        "Antigravity-Limits verfolgen, solange die Antigravity-App läuft.",
        "Sigue los límites de Antigravity mientras la app Antigravity está abierta.",
        "Suivez les limites d’Antigravity tant que l’app Antigravity est ouverte.",
    ),
    "Track Claude Code usage and limits.": (
        "Использование и лимиты Claude Code.",
        "Nutzung und Limits von Claude Code verfolgen.",
        "Sigue el uso y los límites de Claude Code.",
        "Suivez l’utilisation et les limites de Claude Code.",
    ),
    "Track Cline tokens, requests, and cost.": (
        "Токены, запросы и стоимость в Cline.",
        "Tokens, Anfragen und Kosten von Cline verfolgen.",
        "Sigue los tokens, las solicitudes y el coste de Cline.",
        "Suivez les tokens, les requêtes et le coût de Cline.",
    ),
    "Track Codex usage and limits.": (
        "Использование и лимиты Codex.",
        "Nutzung und Limits von Codex verfolgen.",
        "Sigue el uso y los límites de Codex.",
        "Suivez l’utilisation et les limites de Codex.",
    ),
    "Track Gemini CLI activity by model.": (
        "Активность Gemini CLI по моделям.",
        "Gemini CLI-Aktivität nach Modell verfolgen.",
        "Sigue la actividad de Gemini CLI por modelo.",
        "Suivez l’activité de Gemini CLI par modèle.",
    ),
    "Track Grok Build tokens, models, and cost.": (
        "Токены, модели и стоимость в Grok Build.",
        "Tokens, Modelle und Kosten von Grok Build verfolgen.",
        "Sigue los tokens, los modelos y el coste de Grok Build.",
        "Suivez les tokens, les modèles et le coût de Grok Build.",
    ),
    "Track Kiro credits and monthly limits.": (
        "Кредиты и месячные лимиты Kiro.",
        "Credits und Monatslimits von Kiro verfolgen.",
        "Sigue los créditos y los límites mensuales de Kiro.",
        "Suivez les crédits et les limites mensuelles de Kiro.",
    ),
    "Track Ollama Cloud session and weekly limits.": (
        "Лимиты сессии и недели в Ollama Cloud.",
        "Sitzungs- und Wochenlimits von Ollama Cloud verfolgen.",
        "Sigue los límites por sesión y semanales de Ollama Cloud.",
        "Suivez les limites par session et hebdomadaires d’Ollama Cloud.",
    ),
    "Track OpenCode tokens and models.": (
        "Токены и модели в OpenCode.",
        "Tokens und Modelle von OpenCode verfolgen.",
        "Sigue los tokens y los modelos de OpenCode.",
        "Suivez les tokens et les modèles d’OpenCode.",
    ),
    "Track OpenRouter spending and key limits.": (
        "Расходы и лимиты ключа OpenRouter.",
        "Ausgaben und Schlüssellimits von OpenRouter verfolgen.",
        "Sigue el gasto y los límites de clave de OpenRouter.",
        "Suivez les dépenses et les limites de clé d’OpenRouter.",
    ),
    "Track Qoder credits.": ("Кредиты Qoder.", "Qoder-Credits verfolgen.", "Sigue los créditos de Qoder.", "Suivez les crédits de Qoder."),
    "Track Qwen Code tokens and models.": (
        "Токены и модели в Qwen Code.",
        "Tokens und Modelle von Qwen Code verfolgen.",
        "Sigue los tokens y los modelos de Qwen Code.",
        "Suivez les tokens et les modèles de Qwen Code.",
    ),
    "Track Warp agent requests and credits.": (
        "Запросы агента и кредиты Warp.",
        "Agent-Anfragen und Credits von Warp verfolgen.",
        "Sigue las solicitudes del agente y los créditos de Warp.",
        "Suivez les requêtes de l’agent et les crédits de Warp.",
    ),
    "Track your DeepSeek API balance.": (
        "Баланс API DeepSeek.",
        "Dein DeepSeek-API-Guthaben verfolgen.",
        "Sigue tu saldo de la API de DeepSeek.",
        "Suivez votre solde d’API DeepSeek.",
    ),
    "Track your Kimi API balance.": (
        "Баланс API Kimi.",
        "Dein Kimi-API-Guthaben verfolgen.",
        "Sigue tu saldo de la API de Kimi.",
        "Suivez votre solde d’API Kimi.",
    ),
    "Try Again": ("Повторить", "Erneut versuchen", "Reintentar", "Réessayer"),
    "Unavailable": ("Недоступно", "Nicht verfügbar", "No disponible", "Indisponible"),
    "Updated %@": ("Обновлено %@", "Aktualisiert %@", "Actualizado %@", "Actualisé %@"),
    "Updated just now": ("Обновлено только что", "Gerade aktualisiert", "Actualizado ahora mismo", "Actualisé à l’instant"),
    "Updates are off in this build": (
        "В этой сборке обновления выключены",
        "Updates sind in diesem Build deaktiviert",
        "Las actualizaciones están desactivadas en esta compilación",
        "Les mises à jour sont désactivées dans cette version",
    ),
    "Usage Analytics": ("Аналитика использования", "Nutzungsanalysen", "Análisis de uso", "Statistiques d’utilisation"),
    "Usage limits unavailable": ("Лимиты недоступны", "Nutzungslimits nicht verfügbar", "Límites de uso no disponibles", "Limites d’utilisation indisponibles"),
    "UsageNow also checks for new usage when you open it.": (
        "UsageNow также проверяет использование, когда вы его открываете.",
        "UsageNow prüft die Nutzung auch beim Öffnen.",
        "UsageNow también comprueba el uso cuando lo abres.",
        "UsageNow vérifie aussi l’utilisation à son ouverture.",
    ),
    "UsageNow doesn’t include third-party code. Its own source code is available under the MIT License.": (
        "UsageNow не включает сторонний код. Его исходный код доступен по лицензии MIT.",
        "UsageNow enthält keinen Code von Drittanbietern. Der eigene Quellcode ist unter der MIT-Lizenz verfügbar.",
        "UsageNow no incluye código de terceros. Su código fuente está disponible bajo la licencia MIT.",
        "UsageNow n’inclut pas de code tiers. Son code source est disponible sous licence MIT.",
    ),
    "UsageNow installs an update only when it's signed with the UsageNow update key. Checking sends no information about you.": (
        "UsageNow устанавливает обновление, только если оно подписано ключом обновлений UsageNow. Проверка не передаёт никаких сведений о вас.",
        "UsageNow installiert ein Update nur, wenn es mit dem UsageNow-Update-Schlüssel signiert ist. Bei der Suche werden keine Informationen über dich gesendet.",
        "UsageNow solo instala una actualización si está firmada con la clave de actualización de UsageNow. Al comprobar no se envía información sobre ti.",
        "UsageNow n’installe une mise à jour que si elle est signée avec la clé de mise à jour de UsageNow. La vérification n’envoie aucune information vous concernant.",
    ),
    "UsageNow is local-first. Your usage data stays on this Mac.": (
        "UsageNow работает локально. Ваши данные об использовании остаются на этом Mac.",
        "UsageNow arbeitet lokal. Deine Nutzungsdaten bleiben auf diesem Mac.",
        "UsageNow funciona en local. Tus datos de uso se quedan en este Mac.",
        "UsageNow fonctionne en local. Vos données d’utilisation restent sur ce Mac.",
    ),
    "UsageNow uses this key only to read your usage from %@. It stays in the Keychain on this Mac, is never sent anywhere else, and is deleted when you turn %@ off.": (
        "UsageNow использует этот ключ только для чтения вашего использования у %1$@. Он хранится в Связке ключей этого Mac, никуда больше не отправляется и удаляется, когда вы выключаете %2$@.",
        "UsageNow verwendet diesen Schlüssel nur, um deine Nutzung bei %1$@ zu lesen. Er bleibt im Schlüsselbund dieses Mac, wird nirgendwohin sonst gesendet und wird gelöscht, wenn du %2$@ ausschaltest.",
        "UsageNow usa esta clave solo para leer tu uso en %1$@. Se queda en el Llavero de este Mac, nunca se envía a ningún otro sitio y se elimina cuando desactivas %2$@.",
        "UsageNow utilise cette clé uniquement pour lire votre utilisation auprès de %1$@. Elle reste dans le trousseau de ce Mac, n’est envoyée nulle part ailleurs et est supprimée lorsque vous désactivez %2$@.",
    ),
    "Used": ("Использовано", "Verbraucht", "Usado", "Utilisé"),
    "Version %@ (%@)": ("Версия %1$@ (%2$@)", "Version %1$@ (%2$@)", "Versión %1$@ (%2$@)", "Version %1$@ (%2$@)"),
    "Weekly": ("Неделя", "Wöchentlich", "Semanal", "Hebdomadaire"),
    "What these tokens would cost at published API prices, for the models UsageNow has a price for. Your subscription doesn't charge per token.": (
        "Сколько эти токены стоили бы по опубликованным ценам API — для моделей, цены которых известны UsageNow. Подписка не берёт плату за токены.",
        "Was diese Tokens zu veröffentlichten API-Preisen kosten würden, für die Modelle, deren Preis UsageNow kennt. Dein Abo rechnet nicht pro Token ab.",
        "Lo que costarían estos tokens a los precios publicados de la API, para los modelos cuyo precio conoce UsageNow. Tu suscripción no cobra por token.",
        "Ce que ces tokens coûteraient aux tarifs publiés de l’API, pour les modèles dont UsageNow connaît le prix. Votre abonnement ne facture pas au token.",
    ),
    "What these tokens would cost at published API prices. Your subscription doesn't charge per token.": (
        "Сколько эти токены стоили бы по опубликованным ценам API. Подписка не берёт плату за токены.",
        "Was diese Tokens zu veröffentlichten API-Preisen kosten würden. Dein Abo rechnet nicht pro Token ab.",
        "Lo que costarían estos tokens a los precios publicados de la API. Tu suscripción no cobra por token.",
        "Ce que ces tokens coûteraient aux tarifs publiés de l’API. Votre abonnement ne facture pas au token.",
    ),
    "What today's tokens would cost at published API prices, for the models UsageNow has a price for. Your subscription doesn't charge per token.": (
        "Сколько сегодняшние токены стоили бы по опубликованным ценам API — для моделей, цены которых известны UsageNow. Подписка не берёт плату за токены.",
        "Was die heutigen Tokens zu veröffentlichten API-Preisen kosten würden, für die Modelle, deren Preis UsageNow kennt. Dein Abo rechnet nicht pro Token ab.",
        "Lo que costarían los tokens de hoy a los precios publicados de la API, para los modelos cuyo precio conoce UsageNow. Tu suscripción no cobra por token.",
        "Ce que les tokens d’aujourd’hui coûteraient aux tarifs publiés de l’API, pour les modèles dont UsageNow connaît le prix. Votre abonnement ne facture pas au token.",
    ),
    "What today's tokens would cost at published API prices. Your subscription doesn't charge per token.": (
        "Сколько сегодняшние токены стоили бы по опубликованным ценам API. Подписка не берёт плату за токены.",
        "Was die heutigen Tokens zu veröffentlichten API-Preisen kosten würden. Dein Abo rechnet nicht pro Token ab.",
        "Lo que costarían los tokens de hoy a los precios publicados de la API. Tu suscripción no cobra por token.",
        "Ce que les tokens d’aujourd’hui coûteraient aux tarifs publiés de l’API. Votre abonnement ne facture pas au token.",
    ),
    "What’s left of your AI coding limits, at a glance.": (
        "Остаток лимитов ИИ для программирования — с первого взгляда.",
        "Was von deinen KI-Coding-Limits übrig ist, auf einen Blick.",
        "Lo que queda de tus límites de IA para programar, de un vistazo.",
        "Ce qu’il reste de vos limites d’IA pour coder, en un coup d’œil.",
    ),
    "When 20% and 5% of a limit are left, and when a limit you were warned about resets.": (
        "Когда остаётся 20% и 5% лимита, и когда лимит, о котором вы были предупреждены, обновится.",
        "Wenn 20 % und 5 % eines Limits übrig sind und wenn ein Limit, vor dem du gewarnt wurdest, zurückgesetzt wird.",
        "Cuando queda el 20 % y el 5 % de un límite, y cuando se restablece un límite del que se te avisó.",
        "Quand il reste 20 % et 5 % d’une limite, et quand une limite pour laquelle vous avez été averti est réinitialisée.",
    ),
    "about %@": ("около %@", "etwa %@", "unos %@", "environ %@"),
    "at API prices": ("по ценам API", "zu API-Preisen", "a precios de API", "aux tarifs de l’API"),
    "at API prices, partial": ("по ценам API, частично", "zu API-Preisen, unvollständig", "a precios de API, parcial", "aux tarifs de l’API, partiel"),
    "credits today": ("кредитов сегодня", "Credits heute", "créditos hoy", "crédits aujourd’hui"),
    "credits today, partial": ("кредитов сегодня, частично", "Credits heute, unvollständig", "créditos hoy, parcial", "crédits aujourd’hui, partiel"),
    "left": ("осталось", "übrig", "restante", "restant"),
    "spent today": ("потрачено сегодня", "heute ausgegeben", "gastado hoy", "dépensé aujourd’hui"),
    "this month": ("в этом месяце", "diesen Monat", "este mes", "ce mois-ci"),
    "tokens today": ("токенов сегодня", "Tokens heute", "tokens hoy", "tokens aujourd’hui"),
    "used": ("использовано", "verbraucht", "usado", "utilisé"),
    "requests.one": ("запрос", "Anfrage", "solicitud", "requête"),
    "requests.few": ("запроса", "Anfragen", "solicitudes", "requêtes"),
    "requests.many": ("запросов", "Anfragen", "solicitudes", "requêtes"),
    "requests.other": ("запроса", "Anfragen", "solicitudes", "requêtes"),
}

# A word whose form follows a number shown apart from it is one string per
# form; PluralCategory.swift picks which. Forms a language doesn't use repeat
# its general plural.
PLURALS: dict[str, dict[str, dict[str, str]]] = {}


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def main() -> None:
    path = pathlib.Path(__file__).resolve().parent.parent / "Shared/Resources/Localizable.xcstrings"
    catalog = json.loads(path.read_text())
    strings = catalog["strings"]

    missing = []
    for key, entry in strings.items():
        if entry.get("extractionState") == "stale" or entry.get("shouldTranslate") is False:
            continue
        localizations = entry.setdefault("localizations", {})
        if key in PLURALS:
            for language, forms in PLURALS[key].items():
                localizations[language] = {"variations": {"plural": {form: unit(text) for form, text in forms.items()}}}
            continue
        if key not in T:
            missing.append(key)
            continue
        for language, text in zip(LANGUAGES, T[key]):
            localizations[language] = unit(text)

    unused = sorted(set(T) - set(strings))
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n")
    print(f"translated {len(strings) - len(missing)} of {len(strings)} strings")
    if missing:
        print("missing translations:", *missing, sep="\n  ")
    if unused:
        print("translations for strings no longer in the catalog:", *unused, sep="\n  ")
    if missing:
        sys.exit(1)


if __name__ == "__main__":
    main()
