# 🎛️ AudioDashboard v1.0 for Godot 4.3+

[English](#english) | [Español](#español) | [Français](#français) | [Deutsch](#deutsch)

---

<a name="english"></a>
# English Documentation

A centralized visual tool to manage your project's audio system, designed for professional workflows and atomized organization.

## 🚀 Installation & Activation

1.  Place the `AudioDashboard` folder in `res://addons/`.
2.  Go to **Project Settings -> Plugins** and check **Enabled** for AudioDashboard.
3.  **Automatic Configuration:** Upon activation, the plugin will automatically register `AudioManager` as an Autoload (Singleton) and create the necessary folder structure in `res://resources/audio_data/`.

## 🖥️ The Dashboard Interface

The Dashboard appears as a new tab at the top of the editor (next to 2D, 3D, Script, and AssetLib).

### 1. Library (Left Panel)
*   **Resource Tree:** Displays all your `SoundData` files organized by folders.
*   **Search Bar:** Quickly filter sounds by name.
*   **Init Folders:** Creates standard categories (SFX, UI, Music, etc.) to get you started.
*   **Drag & Drop:** Drag `.wav` or `.mp3` files from Godot's FileSystem into a Dashboard folder to automatically create a new `SoundData`.
*   **Hierarchy Persistence:** The expansion state of your folders is saved and restored automatically between sessions.

### 2. Sound Inspector (Central Panel)
When selecting a sound in the library, you can configure:
*   **Volume & Pitch:** Basic controls with Pitch Randomness to avoid ear fatigue.
*   **Output Bus:** Select which mixer bus to route the sound to.
*   **3D Settings:** Max distance, attenuation, and panning strength.
*   **Playback Mode:** 
	*   *Random:* Picks a clip at random.
	*   *Sequential:* Follows the list order.
	*   *Random No Repeat:* Avoids repeating the last X sounds.
*   **Clip Manager:** Drag multiple audio files into the "Clips" box to create variations of the same sound.
*   **Visual Waveform:** Adjust Fade In/Out and Trims visually using the waveform editor.

### 3. SoundBank Management 📦
*   **SoundBanks:** Manage memory by grouping resources into banks that can be loaded/unloaded as needed.
*   **Inspector Pinning:** Click the "Pin" icon in the Bank header to lock the view. This allows you to select other sounds in the tree or use the context menu without losing focus on the current Bank.
*   **Context Menu:** Right-click any sound in the tree and select **"Add to Active Bank"** to quickly link it to the pinned bank.

### 4. Mixer Console
*   Real-time synchronization with Godot's `AudioServer`.
*   Create, rename, and delete buses directly from the Dashboard.
*   Adjust volumes visually with synchronized sliders and high-precision spinboxes.

### 5. Live Monitor
*   Track active voices, buses, and RAM usage in real-time while the game is running.
*   Fully localized column headers and playback states (Playing/Paused).

## 🛠️ AudioManager API (Singleton)

#### 1. `play_global(data, volume_offset = 0.0)`
Plays a sound globally (UI or Music).
```gdscript
AudioManager.play_global(Sounds.UI_CLICK)
```

#### 2. `play_at_position(data, position, volume_offset = 0.0)`
Plays a sound in 3D space with distance culling.
```gdscript
AudioManager.play_at_position(Sounds.EXPLOSION, global_position)
```

#### 3. `load_bank(bank_resource)` / `unload_bank(bank_resource)`
Manages memory usage by loading/unloading audio data.

## 💡 Pro Tips
*   **Manual Compilation**: Regenerate `Sounds.gd` constants at any time to update IDE autocomplete.
*   **Visual Clip Editor**: Click on any clip inside a `SoundData` to adjust fades and volume curves visually.
*   **i18n Support**: Full support for English, Spanish, French, and German.

---

<a name="español"></a>
# Documentación en Español

Una herramienta visual centralizada para gestionar el sistema de audio de tu proyecto, diseñada para flujos de trabajo profesionales y organización atomizada.

## 🚀 Instalación y Activación

1.  Asegúrate de que la carpeta `AudioDashboard` esté en `res://addons/`.
2.  Ve a **Project Settings -> Plugins** y marca **Enabled** en AudioDashboard.
3.  **Configuración Automática:** Al activarlo, el plugin registrará automáticamente el `AudioManager` como un Autoload (Singleton) y creará la estructura de carpetas necesaria en `res://resources/audio_data/`.

## 🖥️ La Interfaz del Dashboard

El Dashboard aparece como una nueva pestaña en el menú superior del editor (junto a 2D, 3D, Script y AssetLib).

### 1. Librería (Panel Izquierdo)
*   **Árbol de Recursos:** Muestra todos tus archivos `SoundData` organizados por carpetas.
*   **Buscador:** Filtra rápidamente sonidos por nombre.
*   **Drag & Drop:** Arrastra archivos de audio desde el FileSystem de Godot hacia una carpeta del Dashboard para generar un `SoundData` automático.
*   **Persistencia de Jerarquía:** El estado de apertura de tus carpetas se mantiene intacto entre sesiones de trabajo.

### 2. Inspector de Sonido (Panel Central)
Configura tus sonidos con total precisión:
*   **Volumen y Pitch:** Controles con aleatoriedad (Pitch Randomness) para dar variedad orgánica a tu juego.
*   **Ajustes 3D:** Distancia máxima, modelos de atenuación y fuerza de paneo.
*   **Editor Visual:** Ajusta curvas de Fade In/Out y recorta muestras de audio directamente sobre la forma de onda.

### 3. Gestión de SoundBanks 📦
*   **SoundBanks:** Agrupa recursos para gestionar la carga en memoria (RAM) de forma dinámica.
*   **Pinning del Inspector:** Usa el icono de la chincheta para bloquear la vista del banco.
*   **Menú Contextual:** Haz clic derecho sobre cualquier sonido y elige **"Añadir al Banco Activo"** para integrarlo instantáneamente.

### 4. Mezclador (Mixer Console)
*   Sincronizado en tiempo real con el `AudioServer` de Godot.
*   Permite crear, renombrar y borrar buses sin salir del Dashboard.

### 5. Monitor en Vivo
*   Rastrea voces activas y el estado de los buses mientras juegas.
*   Cabeceras y estados (Reproduciendo/Pausado) totalmente localizados.

## 🛠️ API de AudioManager (Singleton)

#### 1. `play_global(data, volume_offset = 0.0)`
Reproduce un sonido de forma global (interfaz o música). 
```gdscript
AudioManager.play_global(Sounds.WETCLICK)
```

#### 2. `play_at_position(data, global_pos, volume_offset = 0.0)`
Reproduce sonido en una posición espacial con culling automático por distancia.

## 💡 Tips Pro
*   **Compilación Manual**: Genera el archivo de constantes `Sounds.gd` para tener autocompletado total en tus scripts.
*   **Editor de Clips**: Haz clic en cualquier clip dentro de un `SoundData` para manipular sus fades y recortes visualmente.
*   **Internacionalización (i18n)**: Soporte completo para Inglés, Español, Francés y Alemán.

---

<a name="français"></a>
# Documentation en Français

Un outil visuel centralisé pour gérer le système audio de votre projet, conçu pour des flux de travail professionnels et une organisation atomisée.

## 🚀 Installation et Activation

1.  Placez le dossier `AudioDashboard` dans `res://addons/`.
2.  Allez dans **Project Settings -> Plugins** et cochez **Enabled** pour AudioDashboard.
3.  **Configuration Automatique :** Lors de l'activation, le plugin enregistrera automatiquement `AudioManager` en tant qu'Autoload (Singleton) et créera la structure de dossiers nécessaire dans `res://resources/audio_data/`.

## 🖥️ L'Interface du Dashboard

Le Dashboard apparaît comme un nouvel onglet en haut de l'éditeur (à côté de 2D, 3D, Script et AssetLib).

### 1. Bibliothèque (Panneau de Gauche)
*   **Arborescence des Ressources :** Affiche tous vos fichiers `SoundData` organisés par dossiers.
*   **Barre de Recherche :** Filtrez rapidement les sons par nom.
*   **Drag & Drop :** Faites glisser des fichiers `.wav` ou `.mp3` depuis le FileSystem vers un dossier du Dashboard pour créer automatiquement un nouveau `SoundData`.
*   **Persistance de la Hiérarchie :** L'état d'expansion de vos dossiers est sauvegardé et restauré automatiquement.

### 2. Inspecteur de Son (Panneau Central)
Configurez vos sons avec précision :
*   **Volume et Pitch :** Contrôles de base avec aléatoire de Pitch pour éviter la fatigue auditive.
*   **Réglages 3D :** Distance max, modèles d'atténuation et force du panoramique.
*   **Éditeur Visuel :** Ajustez les courbes de Fade In/Out et recadrez les échantillons directement sur la forme d'onde.

### 3. Gestion des SoundBanks 📦
*   **SoundBanks :** Regroupez les ressources pour gérer le chargement en mémoire (RAM) de manière dynamique.
*   **Épinglage de l'Inspecteur :** Cliquez sur l'icône "Épingler" dans l'en-tête de la banque pour verrouiller la vue.
*   **Menu Contextuel :** Faites un clic droit sur n'importe quel son et sélectionnez **"Ajouter à la Banque Active"** pour l'intégrer instantanément.

### 4. Console de Mixage
*   Synchronisation en temps réel avec l' `AudioServer` de Godot.
*   Créez, renommez et supprimez des bus directement depuis le Dashboard.

### 5. Moniteur en Direct
*   Suivez les voix actives, les bus et l'utilisation de la RAM en temps réel pendant que le jeu tourne.
*   En-têtes de colonnes et états de lecture (Lecture/Pause) entièrement localisés.

## 🛠️ API AudioManager (Singleton)

#### 1. `play_global(data, volume_offset = 0.0)`
Joue un son globalement (Interface ou Musique).
```gdscript
AudioManager.play_global(Sounds.UI_CLICK)
```

#### 2. `play_at_position(data, position, volume_offset = 0.0)`
Joue un son dans l'espace 3D avec culling de distance.

## 💡 Conseils Pro
*   **Compilation Manuelle** : Régénérez les constantes `Sounds.gd` à tout moment pour mettre à jour l'autocomplétion.
*   **Éditeur de Clips Visuel** : Cliquez sur n'importe quel clip dans un `SoundData` pour ajuster visuellement les fondus.
*   **Support i18n** : Support complet pour l'anglais, l'espagnol, le français et l'allemand.

---

<a name="deutsch"></a>
# Dokumentation auf Deutsch

Ein zentralisiertes visuelles Tool zur Verwaltung des Audiosystems Ihres Projekts, entwickelt für professionelle Workflows und atomisierte Organisation.

## 🚀 Installation & Aktivierung

1.  Platzieren Sie den Ordner `AudioDashboard` in `res://addons/`.
2.  Gehen Sie zu **Project Settings -> Plugins** und aktivieren Sie AudioDashboard unter **Enabled**.
3.  **Automatische Konfiguration:** Nach der Aktivierung registriert das Plugin automatisch `AudioManager` als Autoload (Singleton) und erstellt die erforderliche Ordnerstruktur in `res://resources/audio_data/`.

## 🖥️ Die Dashboard-Oberfläche

Das Dashboard erscheint als neuer Tab oben im Editor (neben 2D, 3D, Script und AssetLib).

### 1. Bibliothek (Linkes Panel)
*   **Ressourcen-Baum:** Zeigt alle Ihre `SoundData`-Dateien nach Ordnern organisiert an.
*   **Suchleiste:** Filtern Sie Sounds schnell nach Namen.
*   **Drag & Drop:** Ziehen Sie `.wav`- oder `.mp3`-Dateien aus dem FileSystem in einen Dashboard-Ordner, um automatisch ein neues `SoundData` zu erstellen.
*   **Hierarchie-Persistenz:** Der Erweiterungszustand Ihrer Ordner wird automatisch zwischen Sitzungen gespeichert.

### 2. Sound-Inspektor (Mittleres Panel)
Konfigurieren Sie Ihre Sounds präzise:
*   **Lautstärke & Pitch:** Grundlegende Steuerung mit Zufallstonhöhe zur Vermeidung von Audio-Ermüdung.
*   **3D-Einstellungen:** Maximale Distanz, Dämpfungsmodelle und Panning-Stärke.
*   **Visueller Wellenform-Editor:** Passen Sie Fade In/Out und Trims visuell über den Wellenform-Editor an.

### 3. SoundBank-Verwaltung 📦
*   **SoundBanks:** Verwalten Sie den Speicherbedarf, indem Sie Ressourcen in Banken gruppieren, die bei Bedarf geladen/entladen werden können.
*   **Inspektor anheften:** Klicken Sie auf das "Anheften"-Icon im Bank-Header, um die Ansicht zu sperren.
*   **Kontextmenü:** Rechtsklicken Sie auf einen beliebigen Sound im Baum und wählen Sie **"Zur aktiven Bank hinzufügen"**.

### 4. Mischpult (Mixer Console)
*   Echtzeit-Synchronisation mit Godots `AudioServer`.
*   Buse direkt im Dashboard erstellen, umbenennen und löschen.

### 5. Live-Monitor
*   Verfolgen Sie aktive Stimmen, Buse und den RAM-Verbrauch in Echtzeit während des Spiels.
*   Vollständig lokalisierte Spaltenüberschriften und Wiedergabestatus (Wiedergabe/Pause).

## 🛠️ AudioManager API (Singleton)

#### 1. `play_global(data, volume_offset = 0.0)`
Spielt einen Sound global ab (UI oder Musik).
```gdscript
AudioManager.play_global(Sounds.UI_CLICK)
```

#### 2. `play_at_position(data, position, volume_offset = 0.0)`
Spielt einen Sound im 3D-Raum mit Distanz-Culling ab.

## 💡 Profi-Tipps
*   **Manuelle Kompilierung**: Regenerieren Sie `Sounds.gd` Konstanten jederzeit für die IDE-Autovervollständigung.
*   **Visueller Clip-Editor**: Klicken Sie auf einen Clip innerhalb eines `SoundData`, um Fades visuell anzupassen.
*   **i18n-Unterstützung**: Volle Unterstützung für Englisch, Spanisch, Französisch und Deutsch.
