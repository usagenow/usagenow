# Changelog (Spanish)

What's New in Spanish: each version's changes, shorter than CHANGELOG.md. Headings stay in English; the app translates them. A version missing here shows in English.

## 0.9.0

### Added

- **JetBrains AI (experimental).** Límites locales de AI Assistant desde tu IDE de JetBrains, con la fecha de recarga comunicada, en la barra de menús y los widgets. Los datos antiguos conservan su fecha original. Sin credenciales ni solicitudes de red. Pendiente de validación con AI Assistant activo.
- **Widgets personales.** Elige proveedores y cuentas para cada widget, o deja la selección vacía para seguir UsageNow. Renombrar conserva la elección; una cuenta eliminada no se sustituye silenciosamente.
- **Widget grande.** Hasta cuatro filas detalladas de proveedores y cuentas, con dos ventanas de cuota y sus reinicios. Solo muestra la instantánea depurada.
- **Ritmo de consumo.** Gráfico local y estimación claramente indicada para la ventana más crítica, a partir de tres lecturas recientes durante al menos 15 minutos. Repeticiones en caché, datos antiguos, pausas largas, reinicios o duraciones desconocidas no generan pronósticos. No usa tokens.
- **Incidencias opcionales.** Páginas públicas de OpenAI, Claude, Cursor y GitHub Copilot, desactivadas por defecto y con caché de diez minutos. Estado separado de la conexión y los límites; no se envían datos de cuenta ni de uso.
- **Neerlandés (Nederlands).** App, widgets y novedades integradas: ahora diez idiomas.
- **Iconos renovados de Windsurf y ElevenLabs.** Logotipos correctos para las apariencias clara y oscura.

- **Antigravity sin IDE.** Si el IDE no responde, UsageNow lee el informe oficial `agy /usage` de versiones compatibles de CLI 1.x desde la 1.1.11. No inicia un turno del agente ni accede a credenciales; caché de cinco minutos. Verificado con CLI 1.2.2.

## 0.8.0

### Added

- Las claves, los tokens y las cookies se verifican con una consulta de uso de solo lectura antes de guardarlos. Mensajes claros sobre credenciales, permisos, red y Llavero; cancelar conserva la conexión anterior.
- Ante HTTP 429, la conexión se pausa hasta que el servicio permita reintentar, también al actualizar manualmente. Las otras cuentas siguen funcionando y los datos anteriores conservan su fecha original.
- Cursor, GitHub Copilot, Perplexity, ElevenLabs y Z.ai: conexión explícita en Ajustes, desactivada por defecto. Cursor y Perplexity ofrecen una ventana temporal de inicio de sesión o cookies manuales; Copilot usa tu token de GitHub. ElevenLabs usa la API oficial; las otras cuatro integraciones son experimentales. Aún no verificadas con cuentas reales.
- Los créditos y caracteres de la cuenta se muestran aparte de la actividad de hoy. Los cupos ilimitados o desconocidos no se convierten en porcentajes inventados.
- Windsurf: límites diarios y semanales, reinicios y plan desde la caché local; en planes antiguos, créditos del ciclo de facturación. Sin leer credenciales ni hacer solicitudes de red. Aún no verificado con una instalación actual con sesión iniciada.
- Portugués, japonés, coreano y hebreo: ahora nueve idiomas. El widget admite la lectura de derecha a izquierda.
- «Novedades» está traducido a todos los idiomas de la aplicación y funciona sin conexión.
- Elige una cuenta añadida para la barra de menús, como «Codex · Trabajo». Si la eliminas, se muestra la cuenta principal del proveedor.

### Fixed

- El widget conserva la fecha de los datos de cada proveedor. Actualizar Codex ya no hace parecer recientes los límites antiguos de Claude; un reloj señala los datos desactualizados.
- Tras un reinicio, el porcentaje anterior queda desconocido hasta recibir datos nuevos. La cuenta atrás sigue entre actualizaciones del widget.
- Una lectura nueva guarda su fecha aunque el porcentaje no cambie.

### Development

- Las compilaciones Debug tienen identificadores y contenedor de datos propios para no interferir con el widget instalado. No se actualizan automáticamente; las pruebas no inician proveedores reales.

## 0.7.2

### Fixed

- Privacidad y Acerca de no se podían abrir en ruso, francés o español: los títulos de las pestañas no cabían en la ventana de Ajustes. Ahora se ensancha para que quepan.

## 0.7.1

### Added

- Elige el idioma de UsageNow en Ajustes › General › Idioma: el de macOS, o alemán, inglés, español, francés o ruso. El widget lo sigue.
- Renombra una cuenta añadida desde su menú … en Ajustes › Proveedores.

### Changed

- Las acciones de una cuenta añadida comparten un menú, para que su fila quepa en cualquier idioma.
- Una carpeta de cuenta vacía o que falta lo indica, en vez de pedirte iniciar sesión.

### Fixed

- Añadir una cuenta hacía que las demás cuentas añadidas volvieran a leer sus sesiones del mes.

## 0.7.0

### Added

- Más de una cuenta: una segunda carpeta de Codex o Claude Code, u otra clave de API de DeepSeek, Kimi, OpenRouter u Ollama Cloud, cada una con su propia sección —«Codex · Trabajo»— con el nombre que elijas. UsageNow nunca lee el nombre ni el correo de la cuenta.
- Qwen Code: los tokens, las solicitudes y los modelos de hoy, y lo que habrían costado, desde las grabaciones de sesión que Qwen Code escribe en tu Mac.
- Cline: los tokens, las solicitudes de API y los modelos de hoy, con el coste que registró Cline, desde las tareas de Cline en tu editor y la CLI de Cline. Nunca se leen prompts, respuestas ni claves.
- Grok Build: los tokens, las llamadas al modelo y los modelos de hoy, con el coste que informó xAI, desde los registros de sesión de Grok Build.
- Las dos últimas semanas en el widget, para proveedores sin límites: la forma de tu actividad, nunca cantidades.
- UsageNow en alemán, español, francés y ruso, según el idioma de tu Mac.
- Novedades en Ajustes › Acerca de: los cambios de cada versión, dentro de la app.

### Changed

- En Cline y Grok Build, el coste que se muestra es el que registró la herramienta, no una estimación.

## 0.6.1

### Added

- Avisos de límites: cuando queda el 20 % de un límite y de nuevo el 5 %, una vez cada uno, y cuando se restablece un límite del que se te avisó. Desactivados por defecto; actívalos en Ajustes › Notificaciones.
- Un atajo de teclado propio para abrir UsageNow desde cualquier app. Grábalo en Ajustes › Barra de menús. No necesita permisos adicionales.

### Changed

- La estimación de coste conoce Claude Sonnet 5.5 y GPT-6.1.

### Fixed

- «Reintentar», una clave de API recién añadida o un proveedor recién activado podían ignorarse si se pulsaban durante una actualización.
- Antigravity ya no retrasa a otros proveedores mientras UsageNow busca su servidor de lenguaje.
- Una línea muy larga en un archivo de sesión se omite sin cargarla en memoria.

## 0.6.0

### Added

- Los últimos 30 días bajo cada proveedor: una barra por día, con los tokens del mes, el coste estimado y el modelo más usado. Pasa por una barra para ver ese día. Desactiva los gráficos en Ajustes › General.
- OpenCode: tokens, solicitudes y modelos de hoy, y lo que costarían, desde la base de datos local de OpenCode, en solo lectura. Los prompts y las respuestas nunca se leen.
- Qoder: créditos gastados hoy y las respuestas que pagaron, de las transcripciones que Qoder escribe en tu Mac. Nunca se abre el inicio de sesión de Qoder.
- Ollama Cloud (experimental): límites por sesión y semanales, con tu propia clave de Cloud API.
- Mostrar los límites como restante o usado, en la ventana, la barra de menús y el widget.
- Créditos en el widget para Kiro, Warp y Qoder.
- Informar de un problema en Ajustes › Acerca de: ve el informe completo y envíalo tú como issue de GitHub o correo. Sin nombres, rutas, claves ni prompts.

### Changed

- La ventana de la barra de menús es más opaca y se desplaza en vez de salirse de una pantalla pequeña.
- Ajustes › Proveedores cabe en la pantalla de un portátil.
- La estimación de coste conoce los modelos más recientes, como Claude Opus 5.5 y GPT-6.
- Leer un mes de archivos de sesión es varias veces más rápido y usa mucha menos memoria.

### Fixed

- Los límites de Codex dejaron de actualizarse con ChatGPT 26.9, que movió su CLI de Codex integrada.
- Los límites de Claude desactualizados dicen ahora cómo actualizarlos, para que un porcentaje de hace una hora no pase por actual.
- El widget lee datos de una app más nueva en vez de pedirte que abras UsageNow.
- UsageNow podía cerrarse sin avisar si el app-server de Codex terminaba antes de tiempo.

## 0.5.0

### Added

- Kiro: el límite mensual de créditos de tu plan, cuándo se reinicia y los créditos y prompts de hoy, a partir de lo que Kiro escribe en tu Mac. Sin peticiones a Kiro ni credenciales de Kiro.
- Warp: solicitudes del agente, créditos y tokens por modelo de hoy, desde la base de datos local de Warp, en solo lectura.
- DeepSeek, Kimi y OpenRouter: saldos y gasto desde sus API oficiales, con tu propia clave de API. La clave se queda en tu Llavero y solo va a ese proveedor. Ninguno de los tres se ha comprobado aún con una cuenta real.

## 0.4.0

### Added

- Lo que costarían los tokens de hoy: una estimación junto a los totales de cada proveedor, a los precios publicados de la API, con los tokens en caché a precio de caché. Una idea de escala, no una factura: una suscripción no cobra por token.
- Actualizaciones dentro de la app. UsageNow busca e instala sus propias actualizaciones, y solo las que llevan su firma. Comprobar no envía nada sobre ti. Desde la 0.3.0, instala la 0.4.0 a mano una vez.

### Changed

- Actualizar dibuja un arco de progreso alrededor de la flecha en vez de girar el icono.
- El porcentaje de la barra de menús tiene el tamaño de los iconos de al lado.

## 0.3.0

### Added

- Antigravity: límites de 5 horas y semanales para cada grupo de modelos y tu plan, desde la app Antigravity mientras está abierta. Sin credenciales y sin salir de 127.0.0.1.
- Gemini CLI: tokens, solicitudes y modelos de sus grabaciones locales de sesión. No informa de límites de uso, así que no se muestra ninguno.
- Actividad por modelo: una lista «Modelos hoy» para Codex, Claude Code y Gemini CLI, el más activo primero.
- Planes Team: Claude muestra el puesto, como Team · Premium; Codex muestra Team, Business y Enterprise.
- Modos de la barra de menús para Antigravity y Gemini CLI.
- Reordena los proveedores arrastrándolos en Ajustes; la ventana y el widget siguen el orden.
- Cursor y GitHub Copilot aparecen como próximamente.

### Changed

- Con tres o más proveedores, el widget mediano muestra una fila para cada uno y el pequeño hasta tres, primero los más cerca de un límite.
- Un proveedor añadido en una actualización empieza activado una vez. Los que desactivaste siguen desactivados.

### Fixed

- Los límites de uso de Claude ya no piden tu contraseña de inicio de sesión y vuelven solos tras ejecutar Claude Code.
- Una ventana de límite de Claude que se reinició mientras no estabas sigue visible, y los límites alcanzados aparecen sin iniciar sesión.
- Los últimos límites conocidos de Claude sobreviven a cerrar o actualizar la app.

## 0.2.0

### Added

- Datos reales: límites, horas de reinicio y plan de Codex desde el app-server oficial de Codex; tokens, solicitudes y el último modelo de Codex y Claude Code desde los archivos de sesión locales.
- Widgets de escritorio en tamaño pequeño y mediano.
- Límites de uso de Claude Code: experimentales y desactivados por defecto.
- Codex y Claude Code se pueden activar o desactivar por separado.
- Modos de la barra de menús: solo icono, el uso más crítico o un proveedor.
- Apariencia clara, oscura o del sistema.

### Changed

- El uso se muestra como lo que queda —«58 % restante»— y las barras se acortan a medida que usas más.
- Las ventanas de límite aparecen tal como las informa un proveedor; nunca se inventa una que falte.
- Si no se pueden leer los límites, los últimos valores conocidos se quedan un día, marcados como desactualizados, con un motivo de una línea.

## 0.1.0

### Added

- La app nativa de la barra de menús, sus ajustes y sus estados, con datos de ejemplo.
