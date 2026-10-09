import SwiftUI

/// Design tokens de l'app : espacements, rayons, couleurs sémantiques.
/// Source unique pour garder une mise en page cohérente entre les écrans
/// (équivalent des variables CSS/tokens Figma côté web).
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
    }

    // Couleurs sémantiques : un seul endroit à changer si la palette évolue.
    // S'appuient sur les couleurs système (adaptation clair/sombre gratuite).
    static let success = Color.green
    static let warning = Color.orange
    static let failure = Color.red
}

/// Fond légèrement surélevé + coins arrondis, pour détacher une ligne de
/// liste (file d'attente, récents, historique) du fond de la fenêtre.
struct CardBackground: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill((tint ?? Color.primary).opacity(tint == nil ? 0.05 : 0.08))
            )
    }
}

extension View {
    /// `tint` : teinte le fond selon le statut (ex. rouge pour un échec).
    /// `nil` → fond neutre.
    func cardBackground(tint: Color? = nil) -> some View {
        modifier(CardBackground(tint: tint))
    }
}
