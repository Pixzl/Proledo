import glob
import json
import os
import re
import sys

T = {
    "Fortsetzen": ("Resume", "Reprendre", "Reanudar"),
    "Pausieren": ("Pause", "Pause", "Pausar"),
    "Stromsparmodus": ("Power saving", "Économie d'énergie", "Ahorro de energía"),
    "Beim Anmelden starten": ("Open at login", "Ouvrir à la connexion", "Abrir al iniciar sesión"),
    "Videoordner öffnen": ("Open video folder", "Ouvrir le dossier des vidéos", "Abrir carpeta de vídeos"),
    "Proledo beenden": ("Quit Proledo", "Quitter Proledo", "Salir de Proledo"),
    "Proledo – Video läuft": ("Proledo – video playing", "Proledo – vidéo en cours", "Proledo – vídeo en reproducción"),
    "Bearbeiten": ("Edit", "Édition", "Edición"),
    "Ausschneiden": ("Cut", "Couper", "Cortar"),
    "Kopieren": ("Copy", "Copier", "Copiar"),
    "Einsetzen": ("Paste", "Coller", "Pegar"),
    "Alles auswählen": ("Select All", "Tout sélectionner", "Seleccionar todo"),
    "Autostart ging nicht: %@": ("Couldn't turn on open at login: %@", "Impossible d'activer l'ouverture à la connexion : %@", "No se pudo activar el inicio automático: %@"),
    "Bitte in Systemeinstellungen › Allgemein › Anmeldeobjekte erlauben.": (
        "Please allow it in System Settings › General › Login Items.",
        "Autorise-le dans Réglages Système › Général › Ouverture.",
        "Permítelo en Ajustes del Sistema › General › Ítems de inicio."),
    "MacBook-Display": ("MacBook display", "Écran du MacBook", "Pantalla del MacBook"),
    "Pausiert": ("Paused", "En pause", "En pausa"),
    "Bildschirm aus": ("Display off", "Écran éteint", "Pantalla apagada"),
    "Gesperrt": ("Locked", "Verrouillé", "Bloqueado"),
    "Pausiert im Akkubetrieb": ("Paused on battery", "En pause sur batterie", "En pausa con batería"),
    "Pausiert im Energiesparmodus": ("Paused in Low Power Mode", "En pause en mode Économie d'énergie", "En pausa en modo de bajo consumo"),
    "Das ist kein gültiger Link.": ("That's not a valid link.", "Ce lien n'est pas valide.", "Ese enlace no es válido."),
    "Zeiten bitte als m:ss oder h:mm:ss eingeben.": ("Enter times as m:ss or h:mm:ss.", "Saisis les durées au format m:ss ou h:mm:ss.", "Escribe los tiempos como m:ss o h:mm:ss."),
    "Der Anfang liegt hinter dem Videoende (%@).": ("The start is past the end of the video (%@).", "Le début se situe après la fin de la vidéo (%@).", "El inicio está después del final del vídeo (%@)."),
    "Das Ende muss nach dem Anfang liegen.": ("The end has to come after the start.", "La fin doit venir après le début.", "El final debe ir después del inicio."),
    "Der Ausschnitt sollte mindestens 3 Sekunden lang sein.": ("The clip should be at least 3 seconds long.", "L'extrait doit durer au moins 3 secondes.", "El fragmento debe durar al menos 3 segundos."),
    "Video als Hintergrund wählen": ("Choose a video for your wallpaper", "Choisis une vidéo comme fond d'écran", "Elige un vídeo como fondo"),
    "Kopieren fehlgeschlagen: %@": ("Copying failed: %@", "La copie a échoué : %@", "No se pudo copiar: %@"),
    "Dieses Videoformat kann der Mac nicht abspielen.": ("Your Mac can't play this video format.", "Ton Mac ne peut pas lire ce format vidéo.", "Tu Mac no puede reproducir este formato de vídeo."),
    "Höhenlinien · %@": ("Contour lines · %@", "Courbes de niveau · %@", "Curvas de nivel · %@"),
    "Das Video konnte nicht erzeugt werden.": ("The video couldn't be created.", "La vidéo n'a pas pu être créée.", "No se pudo crear el vídeo."),
    "yt-dlp nicht gefunden. Installieren mit: brew install yt-dlp": ("yt-dlp not found. Install it with: brew install yt-dlp", "yt-dlp introuvable. Installe-le avec : brew install yt-dlp", "No se encontró yt-dlp. Instálalo con: brew install yt-dlp"),
    "Video konnte nicht gelesen werden.": ("Couldn't read the video.", "Impossible de lire la vidéo.", "No se pudo leer el vídeo."),
    "Livestreams werden nicht unterstützt.": ("Live streams aren't supported.", "Les diffusions en direct ne sont pas prises en charge.", "Las emisiones en directo no son compatibles."),
    "Unbenanntes Video": ("Untitled video", "Vidéo sans titre", "Vídeo sin título"),
    "yt-dlp konnte nicht gestartet werden: %@": ("Couldn't start yt-dlp: %@", "Impossible de lancer yt-dlp : %@", "No se pudo iniciar yt-dlp: %@"),
    "Download fehlgeschlagen (Code %d).": ("Download failed (code %d).", "Le téléchargement a échoué (code %d).", "La descarga falló (código %d)."),
    "Kein Video aktiv": ("No video playing", "Aucune vidéo active", "Ningún vídeo activo"),
    "Läuft auf 1 Monitor": ("Playing on 1 display", "Lecture sur 1 écran", "Reproduciendo en 1 pantalla"),
    "Läuft auf %d Monitoren": ("Playing on %d displays", "Lecture sur %d écrans", "Reproduciendo en %d pantallas"),
    "Wiedergabe fortsetzen": ("Resume playback", "Reprendre la lecture", "Reanudar reproducción"),
    "Wiedergabe pausieren": ("Pause playback", "Mettre en pause", "Pausar reproducción"),
    "Video hinzufügen": ("Add video", "Ajouter une vidéo", "Añadir vídeo"),
    "Video wird vorbereitet…": ("Preparing video…", "Préparation de la vidéo…", "Preparando el vídeo…"),
    "YouTube-Link einfügen": ("Paste a YouTube link", "Colle un lien YouTube", "Pega un enlace de YouTube"),
    "Abbrechen": ("Cancel", "Annuler", "Cancelar"),
    "Link aus der Zwischenablage einfügen und prüfen": ("Paste the link from the clipboard and check it", "Coller le lien du presse-papiers et le vérifier", "Pegar el enlace del portapapeles y comprobarlo"),
    "Weiter": ("Next", "Suivant", "Siguiente"),
    "Video-Infos werden geladen…": ("Loading video info…", "Chargement des infos de la vidéo…", "Cargando información del vídeo…"),
    "yt-dlp fehlt. Installieren mit: brew install yt-dlp": ("yt-dlp is missing. Install it with: brew install yt-dlp", "yt-dlp est manquant. Installe-le avec : brew install yt-dlp", "Falta yt-dlp. Instálalo con: brew install yt-dlp"),
    "Eigene Videodatei wählen…": ("Choose your own video file…", "Choisir un fichier vidéo…", "Elegir un archivo de vídeo…"),
    "Hintergrund erzeugen…": ("Create wallpaper…", "Créer un fond…", "Crear fondo…"),
    "Download abbrechen": ("Cancel download", "Annuler le téléchargement", "Cancelar descarga"),
    "%@ von ≈ %@": ("%@ of ≈ %@", "%@ sur ≈ %@", "%@ de ≈ %@"),
    "Ausschnitt wird geladen und geschnitten": ("Downloading and trimming the clip", "Téléchargement et découpe de l'extrait", "Descargando y recortando el fragmento"),
    "Download startet": ("Starting download", "Démarrage du téléchargement", "Iniciando descarga"),
    "Qualität": ("Quality", "Qualité", "Calidad"),
    "Automatisch": ("Automatic", "Automatique", "Automática"),
    "Nur einen Ausschnitt laden": ("Download only a clip", "Ne télécharger qu'un extrait", "Descargar solo un fragmento"),
    "Von": ("From", "De", "De"),
    "bis": ("to", "à", "a"),
    "Länge des Ausschnitts": ("Clip length", "Durée de l'extrait", "Duración del fragmento"),
    "Für Ausschnitte wird ffmpeg benötigt: brew install ffmpeg": ("Clips need ffmpeg: brew install ffmpeg", "Les extraits nécessitent ffmpeg : brew install ffmpeg", "Los fragmentos necesitan ffmpeg: brew install ffmpeg"),
    "Ziemlich groß. Ein kürzerer Ausschnitt oder eine kleinere Qualität spart Platz.": (
        "That's pretty big. A shorter clip or lower quality saves space.",
        "C'est assez lourd. Un extrait plus court ou une qualité plus basse prend moins de place.",
        "Es bastante grande. Un fragmento más corto o menos calidad ahorra espacio."),
    "Laden": ("Download", "Télécharger", "Descargar"),
    "Hintergrund erzeugen": ("Create wallpaper", "Créer un fond", "Crear fondo"),
    "Schließen": ("Close", "Fermer", "Cerrar"),
    "Neues Muster": ("New pattern", "Nouveau motif", "Nuevo patrón"),
    "Monitor": ("Display", "Écran", "Pantalla"),
    "Dichte": ("Density", "Densité", "Densidad"),
    "Tempo": ("Speed", "Vitesse", "Velocidad"),
    "Linien": ("Lines", "Lignes", "Líneas"),
    "Länge": ("Length", "Durée", "Duración"),
    "%d × %d · nahtlose Schleife · ≈ %@": ("%d × %d · seamless loop · ≈ %@", "%d × %d · boucle continue · ≈ %@", "%d × %d · bucle continuo · ≈ %@"),
    "Erzeugen": ("Create", "Créer", "Crear"),
    "wird berechnet…": ("calculating…", "calcul en cours…", "calculando…"),
    "noch ca. %@": ("about %@ left", "encore environ %@", "faltan unos %@"),
    "Monitore": ("Displays", "Écrans", "Pantallas"),
    "Alle aus": ("All off", "Tout désactiver", "Desactivar todas"),
    "Für alle": ("All displays", "Tous les écrans", "Todas"),
    "Füge oben ein Video hinzu, dann kannst du es hier jedem Monitor zuordnen.": (
        "Add a video above, then you can pick it for each display here.",
        "Ajoute une vidéo ci-dessus, puis attribue-la ici à chaque écran.",
        "Añade un vídeo arriba y luego asígnalo aquí a cada pantalla."),
    "Ausgeblendete Leisten kommen zurück, sobald die Maus an den Rand fährt.": (
        "Hidden bars come back as soon as your pointer hits the edge.",
        "Les barres masquées réapparaissent dès que le pointeur touche le bord.",
        "Las barras ocultas vuelven en cuanto el puntero llega al borde."),
    "Aus": ("Off", "Désactivé", "Desactivado"),
    "Menüleiste": ("Menu bar", "Barre des menus", "Barra de menús"),
    "Menüleiste auf diesem Monitor ausblenden": ("Hide the menu bar on this display", "Masquer la barre des menus sur cet écran", "Ocultar la barra de menús en esta pantalla"),
    "Dock": ("Dock", "Dock", "Dock"),
    "Dock auf diesem Monitor ausblenden (wirkt, wenn das Dock dort ist)": (
        "Hide the Dock on this display (works when the Dock is there)",
        "Masquer le Dock sur cet écran (si le Dock s'y trouve)",
        "Ocultar el Dock en esta pantalla (si el Dock está ahí)"),
    "hochkant": ("portrait", "portrait", "vertical"),
    "Bibliothek": ("Library", "Bibliothèque", "Biblioteca"),
    "Name": ("Name", "Nom", "Nombre"),
    "Doppelklick zum Umbenennen": ("Double-click to rename", "Double-clic pour renommer", "Doble clic para renombrar"),
    "Sparsame Version wird erstellt…": ("Creating a lighter version…", "Création d'une version allégée…", "Creando una versión ligera…"),
    "Umbenennen": ("Rename", "Renommer", "Renombrar"),
    "Video löschen": ("Delete video", "Supprimer la vidéo", "Eliminar vídeo"),
    "Auf allen Monitoren zeigen": ("Show on all displays", "Afficher sur tous les écrans", "Mostrar en todas las pantallas"),
    "Auf %@ zeigen": ("Show on %@", "Afficher sur %@", "Mostrar en %@"),
    "Umbenennen…": ("Rename…", "Renommer…", "Renombrar…"),
    "Im Finder zeigen": ("Show in Finder", "Afficher dans le Finder", "Mostrar en el Finder"),
    "Löschen": ("Delete", "Supprimer", "Eliminar"),
    "Erzeugt": ("Generated", "Généré", "Generado"),
    "Datei": ("File", "Fichier", "Archivo"),
    "sparsam": ("eco", "éco", "eco"),
    "Im Akkubetrieb pausieren": ("Pause on battery", "Pause sur batterie", "Pausar con batería"),
    "Stromsparmodus (30 fps, max. 1440p)": ("Power saving (30 fps, up to 1440p)", "Économie d'énergie (30 i/s, 1440p max.)", "Ahorro de energía (30 fps, máx. 1440p)"),
    "Erstellt von jedem Video einmalig eine sparsame Kopie und spielt diese ab. Das Original bleibt erhalten.": (
        "Makes a lighter copy of each video once and plays that. The original stays untouched.",
        "Crée une fois une copie allégée de chaque vidéo et la lit. L'original reste intact.",
        "Crea una vez una copia ligera de cada vídeo y la reproduce. El original no se toca."),
    "Videoordner im Finder öffnen": ("Open the video folder in Finder", "Ouvrir le dossier des vidéos dans le Finder", "Abrir la carpeta de vídeos en el Finder"),
    "Beenden": ("Quit", "Quitter", "Salir"),
    "%d Std.": ("%d hr", "%d h", "%d h"),
    "%d Min.": ("%d min", "%d min", "%d min"),
    "%d Sek.": ("%d sec", "%d s", "%d s"),
    "Locker": ("Loose", "Aéré", "Suelto"),
    "Normal": ("Normal", "Normal", "Normal"),
    "Dicht": ("Dense", "Dense", "Denso"),
    "Ruhig": ("Calm", "Calme", "Tranquilo"),
    "Lebhaft": ("Lively", "Vif", "Animado"),
    "Fein": ("Fine", "Fines", "Finas"),
    "Kräftig": ("Bold", "Épaisses", "Gruesas"),
    "Willkommen": ("Welcome", "Bienvenue", "Bienvenido"),
    "Proledo hält dein OLED-Display in Bewegung, damit sich nichts einbrennt.": (
        "Proledo keeps your OLED display moving so nothing burns in.",
        "Proledo garde ton écran OLED en mouvement pour que rien ne marque.",
        "Proledo mantiene tu pantalla OLED en movimiento para que nada se queme."),
    "Füge unten ein Video hinzu: per YouTube-Link, als eigene Datei oder selbst erzeugt.": (
        "Add a video below: from a YouTube link, your own file, or made right here.",
        "Ajoute une vidéo ci-dessous : lien YouTube, ton propre fichier ou créée ici.",
        "Añade un vídeo abajo: con un enlace de YouTube, tu propio archivo o creado aquí."),
    "Wähle unter „Monitore“, wo es laufen soll.": (
        "Pick where it plays under “Displays”.",
        "Choisis où elle s'affiche dans « Écrans ».",
        "Elige dónde se reproduce en «Pantallas»."),
    "Blende bei Bedarf Menüleiste und Dock aus.": (
        "Hide the menu bar and Dock if you like.",
        "Masque la barre des menus et le Dock si tu veux.",
        "Oculta la barra de menús y el Dock si quieres."),
    "Hintergrund wird erzeugt · %d %%": ("Creating wallpaper · %d %%", "Création du fond · %d %%", "Creando fondo · %d %%"),
    "Wird erzeugt · %d %%": ("Creating · %d %%", "Création · %d %%", "Creando · %d %%"),
    "Im Hintergrund weiterrechnen": ("Keep working in the background", "Continuer en arrière-plan", "Seguir en segundo plano"),
    "In den Papierkorb legen": ("Move to Trash", "Placer dans la corbeille", "Trasladar a la papelera"),
    "Proledo auf GitHub": ("Proledo on GitHub", "Proledo sur GitHub", "Proledo en GitHub"),
    "Update auf %@ verfügbar": ("Update to %@ available", "Mise à jour %@ disponible", "Actualización %@ disponible"),
    "Alle abwechselnd": ("Rotate all", "Alterner toutes", "Alternar todos"),
    "Wechsel alle": ("Switch every", "Changer toutes les", "Cambiar cada"),
    "Abwechselnd · %@": ("Rotating · %@", "Alternance · %@", "Alternando · %@"),
    "Einstellungen": ("Settings", "Réglages", "Ajustes"),
    "Eigene Datei": ("Your own file", "Ton fichier", "Tu archivo"),
    "Video von deinem Mac": ("A video from your Mac", "Une vidéo de ton Mac", "Un vídeo de tu Mac"),
    "Selbst erzeugen": ("Make your own", "Créer le tien", "Crear el tuyo"),
    "Höhenlinien als Loop": ("Contour lines on a loop", "Courbes de niveau en boucle", "Curvas de nivel en bucle"),
    "Wird erzeugt": ("Creating", "Création", "Creando"),
    "Vom Mac": ("From your Mac", "Depuis ton Mac", "Desde tu Mac"),
    "Höhenlinien-Loop": ("Contour line loop", "Courbes en boucle", "Curvas en bucle"),
    "Menüleiste ausblenden": ("Hide menu bar", "Masquer la barre des menus", "Ocultar barra de menús"),
    "Dock ausblenden": ("Hide Dock", "Masquer le Dock", "Ocultar el Dock"),
    "läuft": ("playing", "en cours", "en uso"),
    "Stil": ("Style", "Style", "Estilo"),
    "Höhenlinien": ("Contour lines", "Courbes de niveau", "Curvas de nivel"),
    "Sternenhimmel": ("Starry sky", "Ciel étoilé", "Cielo estrellado"),
    "Milchstraße": ("Milky Way", "Voie lactée", "Vía Láctea"),
    "Wenige": ("Few", "Peu", "Pocas"),
    "Viele": ("Many", "Beaucoup", "Muchas"),
    "Sternenhimmel · %@": ("Starry sky · %@", "Ciel étoilé · %@", "Cielo estrellado · %@"),
}

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
keys = []
for f in sorted(glob.glob(os.path.join(root, "Sources/Proledo/*.swift"))):
    for m in re.finditer(r'L\("((?:[^"\\]|\\.)*)"\)', open(f).read()):
        if m.group(1) not in keys:
            keys.append(m.group(1))
for f in glob.glob(os.path.join(root, "Sources/Proledo/TopoGenerator.swift")):
    for line in open(f):
        if line.strip().startswith("case ") and '= "' in line:
            for value in re.findall(r'= "([^"]+)"', line):
                if value not in keys:
                    keys.append(value)

missing = [k for k in keys if k not in T]
if missing:
    print("Fehlende Übersetzungen:", *missing, sep="\n  ")
    sys.exit(1)

def placeholders(s):
    return re.findall(r"%[@d]", s)

for k in keys:
    for v in T[k]:
        if placeholders(k) != placeholders(v):
            print("Platzhalter passen nicht:", k, "→", v)
            sys.exit(1)

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')

for lang, index in [("de", None), ("en", 0), ("fr", 1), ("es", 2)]:
    folder = os.path.join(root, "Resources", f"{lang}.lproj")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "Localizable.strings"), "w") as out:
        for k in keys:
            value = k if index is None else T[k][index]
            out.write(f'"{esc(k)}" = "{esc(value)}";\n')
print(f"{len(keys)} Texte in de, en, fr, es geschrieben")
