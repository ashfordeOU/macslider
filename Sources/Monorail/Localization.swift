#if os(macOS)
import Foundation

/// Translations of the menu bar menu, Settings tabs and the welcome tour.
/// Keys are the English text; anything without a translation stays English.
enum Localization {
    /// "de", "fr", "es", "ja" or "en". Set from Settings (empty follows macOS).
    static var language = "en"

    static let languages: [(code: String, name: String)] = [
        ("", "Same as macOS"), ("en", "English"), ("de", "Deutsch"), ("fr", "Français"), ("es", "Español"), ("ja", "日本語"),
    ]

    static func choose(_ setting: String) {
        let preferred = setting.isEmpty ? (Locale.preferredLanguages.first ?? "en") : setting
        let code = String(preferred.prefix(2))
        language = table.keys.contains(code) ? code : "en"
    }

    static func text(_ english: String) -> String {
        table[language]?[english] ?? english
    }

    private static let table: [String: [String: String]] = [
        "de": [
            "Pause Tiling": "Kacheln pausieren", "Resume Tiling": "Kacheln fortsetzen", "Overview": "Übersicht",
            "Search Windows…": "Fenster suchen …", "Command Palette…": "Befehlspalette …", "Focus Mode": "Fokusmodus",
            "End Focus Mode": "Fokusmodus beenden", "Presentation Mode": "Präsentationsmodus",
            "End Presentation Mode": "Präsentationsmodus beenden", "Stop Recording": "Aufnahme beenden",
            "Reset to Smart Pairs": "Auf intelligente Paare zurücksetzen", "Saved Layouts": "Gesicherte Layouts",
            "Save Current Layout…": "Aktuelles Layout sichern …", "Share Layout…": "Layout teilen …", "Delete": "Löschen",
            "App Pairs": "App-Paare", "Snapshots": "Momentaufnahmen", "Take Snapshot…": "Momentaufnahme erstellen …",
            "Templates": "Vorlagen", "Recent Slides": "Letzte Folien", "Undo Layout Change": "Layoutänderung widerrufen",
            "Retile Windows": "Fenster neu anordnen", "Workspaces": "Arbeitsbereiche", "Park Workspace": "Arbeitsbereich parken",
            "Settings…": "Einstellungen …", "Keyboard Shortcuts": "Tastenkürzel", "Change Shortcuts…": "Tastenkürzel ändern …",
            "Welcome Tour…": "Einführung …", "Check for Updates…": "Nach Updates suchen …", "Quit Monorail": "Monorail beenden",
            "General": "Allgemein", "Layout": "Layout", "Motion & Input": "Bewegung & Eingabe", "Appearance": "Darstellung",
            "Apps": "Apps", "Automation": "Automatisierung", "Insights": "Einblicke", "Shortcuts": "Kürzel", "About": "Über",
            "1. Allow Accessibility": "1. Bedienungshilfen erlauben",
            "2. Choose how you see your slides": "2. Wählen Sie, wie Sie Ihre Folien sehen",
            "3. Get around": "3. Navigieren", "4. Practice": "4. Üben", "Start sliding": "Loslegen",
            "Continue without permission": "Ohne Erlaubnis fortfahren",
            "Open Accessibility Settings": "Bedienungshilfen öffnen",
            "Practice with demo windows": "Mit Übungsfenstern üben", "Close demo windows": "Übungsfenster schließen",
        ],
        "fr": [
            "Pause Tiling": "Suspendre la disposition", "Resume Tiling": "Reprendre la disposition", "Overview": "Vue d’ensemble",
            "Search Windows…": "Rechercher des fenêtres…", "Command Palette…": "Palette de commandes…", "Focus Mode": "Mode concentration",
            "End Focus Mode": "Quitter le mode concentration", "Presentation Mode": "Mode présentation",
            "End Presentation Mode": "Quitter le mode présentation", "Stop Recording": "Arrêter l’enregistrement",
            "Reset to Smart Pairs": "Revenir aux paires intelligentes", "Saved Layouts": "Dispositions enregistrées",
            "Save Current Layout…": "Enregistrer la disposition…", "Share Layout…": "Partager la disposition…", "Delete": "Supprimer",
            "App Pairs": "Paires d’apps", "Snapshots": "Instantanés", "Take Snapshot…": "Prendre un instantané…",
            "Templates": "Modèles", "Recent Slides": "Diapositives récentes", "Undo Layout Change": "Annuler la modification",
            "Retile Windows": "Réorganiser les fenêtres", "Workspaces": "Espaces de travail", "Park Workspace": "Ranger l’espace de travail",
            "Settings…": "Réglages…", "Keyboard Shortcuts": "Raccourcis clavier", "Change Shortcuts…": "Modifier les raccourcis…",
            "Welcome Tour…": "Visite guidée…", "Check for Updates…": "Rechercher des mises à jour…", "Quit Monorail": "Quitter Monorail",
            "General": "Général", "Layout": "Disposition", "Motion & Input": "Mouvement et saisie", "Appearance": "Apparence",
            "Apps": "Apps", "Automation": "Automatisation", "Insights": "Statistiques", "Shortcuts": "Raccourcis", "About": "À propos",
            "1. Allow Accessibility": "1. Autoriser l’accessibilité",
            "2. Choose how you see your slides": "2. Choisissez comment voir vos diapositives",
            "3. Get around": "3. Se déplacer", "4. Practice": "4. S’entraîner", "Start sliding": "C’est parti",
            "Continue without permission": "Continuer sans autorisation",
            "Open Accessibility Settings": "Ouvrir les réglages d’accessibilité",
            "Practice with demo windows": "S’entraîner avec des fenêtres de démo", "Close demo windows": "Fermer les fenêtres de démo",
        ],
        "es": [
            "Pause Tiling": "Pausar mosaico", "Resume Tiling": "Reanudar mosaico", "Overview": "Vista general",
            "Search Windows…": "Buscar ventanas…", "Command Palette…": "Paleta de comandos…", "Focus Mode": "Modo concentración",
            "End Focus Mode": "Salir del modo concentración", "Presentation Mode": "Modo presentación",
            "End Presentation Mode": "Salir del modo presentación", "Stop Recording": "Detener grabación",
            "Reset to Smart Pairs": "Volver a parejas inteligentes", "Saved Layouts": "Distribuciones guardadas",
            "Save Current Layout…": "Guardar distribución actual…", "Share Layout…": "Compartir distribución…", "Delete": "Eliminar",
            "App Pairs": "Parejas de apps", "Snapshots": "Instantáneas", "Take Snapshot…": "Tomar instantánea…",
            "Templates": "Plantillas", "Recent Slides": "Diapositivas recientes", "Undo Layout Change": "Deshacer cambio",
            "Retile Windows": "Reorganizar ventanas", "Workspaces": "Espacios de trabajo", "Park Workspace": "Aparcar espacio de trabajo",
            "Settings…": "Ajustes…", "Keyboard Shortcuts": "Atajos de teclado", "Change Shortcuts…": "Cambiar atajos…",
            "Welcome Tour…": "Recorrido de bienvenida…", "Check for Updates…": "Buscar actualizaciones…", "Quit Monorail": "Salir de Monorail",
            "General": "General", "Layout": "Distribución", "Motion & Input": "Movimiento y entrada", "Appearance": "Apariencia",
            "Apps": "Apps", "Automation": "Automatización", "Insights": "Estadísticas", "Shortcuts": "Atajos", "About": "Acerca de",
            "1. Allow Accessibility": "1. Permitir accesibilidad",
            "2. Choose how you see your slides": "2. Elige cómo ver tus diapositivas",
            "3. Get around": "3. Moverse", "4. Practice": "4. Practicar", "Start sliding": "Empezar",
            "Continue without permission": "Continuar sin permiso",
            "Open Accessibility Settings": "Abrir ajustes de accesibilidad",
            "Practice with demo windows": "Practicar con ventanas de prueba", "Close demo windows": "Cerrar ventanas de prueba",
        ],
        "ja": [
            "Pause Tiling": "タイリングを一時停止", "Resume Tiling": "タイリングを再開", "Overview": "概要",
            "Search Windows…": "ウインドウを検索…", "Command Palette…": "コマンドパレット…", "Focus Mode": "集中モード",
            "End Focus Mode": "集中モードを終了", "Presentation Mode": "プレゼンテーションモード",
            "End Presentation Mode": "プレゼンテーションモードを終了", "Stop Recording": "収録を停止",
            "Reset to Smart Pairs": "スマートペアに戻す", "Saved Layouts": "保存したレイアウト",
            "Save Current Layout…": "現在のレイアウトを保存…", "Share Layout…": "レイアウトを共有…", "Delete": "削除",
            "App Pairs": "アプリペア", "Snapshots": "スナップショット", "Take Snapshot…": "スナップショットを作成…",
            "Templates": "テンプレート", "Recent Slides": "最近のスライド", "Undo Layout Change": "レイアウト変更を取り消す",
            "Retile Windows": "ウインドウを再配置", "Workspaces": "ワークスペース", "Park Workspace": "ワークスペースを退避",
            "Settings…": "設定…", "Keyboard Shortcuts": "キーボードショートカット", "Change Shortcuts…": "ショートカットを変更…",
            "Welcome Tour…": "ようこそツアー…", "Check for Updates…": "アップデートを確認…", "Quit Monorail": "Monorailを終了",
            "General": "一般", "Layout": "レイアウト", "Motion & Input": "動きと入力", "Appearance": "外観",
            "Apps": "アプリ", "Automation": "自動化", "Insights": "インサイト", "Shortcuts": "ショートカット", "About": "情報",
            "1. Allow Accessibility": "1. アクセシビリティを許可",
            "2. Choose how you see your slides": "2. スライドの表示方法を選択",
            "3. Get around": "3. 移動する", "4. Practice": "4. 練習", "Start sliding": "はじめる",
            "Continue without permission": "許可せずに続ける",
            "Open Accessibility Settings": "アクセシビリティ設定を開く",
            "Practice with demo windows": "練習用ウインドウで試す", "Close demo windows": "練習用ウインドウを閉じる",
        ],
    ]
}

/// Shorthand for a translated string.
func L(_ english: String) -> String { Localization.text(english) }
#endif
