import SwiftUI
import InstaCore
import UniformTypeIdentifiers

// MARK: - Surfaces

/// Material 3 card: tonal surface, large continuous corners.
struct M3Card<Content: View>: View {
    @Environment(\.m3) private var m3
    var color: Color?
    var padding: CGFloat
    var corner: CGFloat
    let content: Content

    init(color: Color? = nil, padding: CGFloat = 16, corner: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.color = color
        self.padding = padding
        self.corner = corner
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color ?? m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct SectionTitle: View {
    @Environment(\.m3) private var m3
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.m3TitleMedium)
                .foregroundStyle(m3.onSurface)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.m3LabelMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

// MARK: - Buttons

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Material 3 filled / tonal pill button.
struct PillButton: View {
    let title: String
    let icon: String
    let tones: Tones
    var filled = true
    var height: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.m3LabelLarge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(filled ? tones.onAccent : tones.onContainer)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 8)
            .background(filled ? tones.accent : tones.container, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

struct Chip: View {
    @Environment(\.m3) private var m3
    let title: String
    var icon: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(.m3LabelLarge)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(selected ? m3.onSecondaryContainer : m3.onSurfaceVariant)
            .background(selected ? m3.secondaryContainer : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : m3.outlineVariant, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Avatar

/// Initials on a stable muted color (the export has no profile pictures).
struct Avatar: View {
    let initials: String
    let colorHex: String
    var size: CGFloat = 44
    var ring: Color?

    init(row: AccountRow, size: CGFloat = 44, ring: Color? = nil) {
        initials = row.initials
        colorHex = row.colorHex
        self.size = size
        self.ring = ring
    }

    var body: some View {
        let base = RGBColor(hex: colorHex) ?? RGBColor(red: 0.5, green: 0.5, blue: 0.5)
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(rgb: base).gradient))
            .overlay {
                if let ring { Circle().strokeBorder(ring, lineWidth: max(2, size * 0.06)) }
            }
            .accessibilityHidden(true)
    }
}

/// Overlapping avatars (overview previews).
struct AvatarStack: View {
    @Environment(\.m3) private var m3
    let rows: [AccountRow]
    var size: CGFloat = 34
    var max: Int = 6

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(rows.prefix(max)) { r in
                Avatar(row: r, size: size)
                    .overlay(Circle().strokeBorder(m3.surfaceContainerLow, lineWidth: 2.5))
            }
        }
    }
}

/// Small badge for the user's mark.
struct MarkBadge: View {
    @Environment(\.m3) private var m3
    let mark: MarkState

    var body: some View {
        if mark != .none {
            let tones = mark == .keep ? m3.keep : m3.reject
            Label(mark == .keep ? "Tenuto" : "Da smettere", systemImage: mark == .keep ? "checkmark" : "xmark")
                .font(.m3LabelSmall)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(tones.onContainer)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(tones.container, in: Capsule())
        }
    }
}

// MARK: - Toast

struct Toast: Identifiable, Equatable {
    enum Style { case success, info, error }
    let id = UUID()
    let message: String
    let icon: String
    let style: Style
    var canUndo = false
}

struct ToastView: View {
    @Environment(\.m3) private var m3
    let toast: Toast
    let onUndo: () -> Void

    var body: some View {
        let tones: Tones = {
            switch toast.style {
            case .success: return m3.keep
            case .info: return Tones(accent: m3.primary, onAccent: m3.onPrimary, container: m3.surfaceContainerHighest, onContainer: m3.onSurface)
            case .error: return m3.reject
            }
        }()
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 15, weight: .bold))
            Text(toast.message)
                .font(.m3LabelLarge)
                .lineLimit(2)
            if toast.canUndo {
                Button("Annulla", action: onUndo)
                    .font(.m3LabelLarge)
                    .foregroundStyle(m3.primary)
                    .padding(.leading, 4)
            }
        }
        .foregroundStyle(tones.onContainer)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(tones.container, in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @Environment(\.m3) private var m3
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            IconBadge(icon: icon, tones: m3.primaryTones, size: 88, cookie: true)
            Text(title)
                .font(.m3TitleLarge)
                .foregroundStyle(m3.onSurface)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.m3BodyMedium)
                .foregroundStyle(m3.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
}

/// Plain text document for `.fileExporter` (JSON and CSV).
struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let s = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = s
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
