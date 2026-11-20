import SwiftUI
import AlarmCore

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

/// Pressed-state scale used by tappable cards.
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
    var height: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.m3TitleMedium)
            }
            .foregroundStyle(filled ? tones.onAccent : tones.onContainer)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(filled ? tones.accent : tones.container, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Small selectable chip (filter / house switcher).
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

// MARK: - Toast

struct ToastView: View {
    @Environment(\.m3) private var m3
    let toast: Toast

    var body: some View {
        let tones: Tones = {
            switch toast.style {
            case .success: return m3.armed
            case .info: return m3.neutral
            case .error: return m3.danger
            }
        }()
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 15, weight: .bold))
            Text(toast.message)
                .font(.m3LabelLarge)
        }
        .foregroundStyle(tones.onContainer)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(tones.container, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - Pickers

enum Catalog {
    static let houseIcons = [
        "house.fill", "house.lodge.fill", "building.2.fill", "building.fill", "storefront.fill",
        "briefcase.fill", "tent.fill", "beach.umbrella.fill", "mountain.2.fill", "tree.fill",
        "car.fill", "sailboat.fill"
    ]
    static let zoneIcons = [
        "lock.shield.fill", "shield.fill", "moon.stars.fill", "sun.max.fill", "bed.double.fill",
        "sofa.fill", "door.left.hand.closed", "door.garage.closed", "window.vertical.closed", "stairs",
        "figure.walk", "airplane", "suitcase.fill", "car.fill", "tree.fill", "dog.fill",
        "building.2.fill", "house.fill", "eye.fill", "bell.fill"
    ]
    static let colors = [
        "#3949ab", "#1e88e5", "#00897b", "#43a047", "#7cb342", "#f9a825",
        "#fb8c00", "#e53935", "#d81b60", "#8e24aa", "#5e35b1", "#6d4c41", "#546e7a"
    ]
}

struct IconPicker: View {
    @Environment(\.m3) private var m3
    let icons: [String]
    @Binding var selection: String
    let colorHex: String

    var body: some View {
        let tones = m3.tones(colorHex)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(icons, id: \.self) { icon in
                Button {
                    selection = icon
                } label: {
                    IconBadge(icon: icon, tones: tones, size: 44, filled: selection == icon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(icon)
            }
        }
        .padding(.vertical, 6)
    }
}

struct ColorPickerRow: View {
    @Environment(\.m3) private var m3
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Catalog.colors, id: \.self) { hex in
                    let tones = m3.tones(hex)
                    Button {
                        selection = hex
                    } label: {
                        Circle()
                            .fill(tones.accent)
                            .frame(width: 36, height: 36)
                            .overlay {
                                if selection.lowercased() == hex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(tones.onAccent)
                                }
                            }
                            .padding(3)
                            .overlay(Circle().strokeBorder(selection.lowercased() == hex ? tones.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
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
            IconBadge(icon: icon, tones: Tones(accent: m3.primary, onAccent: m3.onPrimary, container: m3.primaryContainer, onContainer: m3.onPrimaryContainer), size: 88, cookie: true)
            Text(title)
                .font(.m3TitleLarge)
                .foregroundStyle(m3.onSurface)
            Text(message)
                .font(.m3BodyMedium)
                .foregroundStyle(m3.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

// MARK: - Formatting helpers

extension Date {
    /// "oggi, 23:05" / "ieri, 07:12" / "12 nov, 22:40"
    var shortLabel: String {
        let it = Locale(identifier: "it_IT")
        let time = formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(it))
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "oggi, \(time)" }
        if cal.isDateInYesterday(self) { return "ieri, \(time)" }
        return formatted(.dateTime.day().month(.abbreviated).locale(it)) + ", " + time
    }

    var timeLabel: String {
        formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "it_IT")))
    }

    var dayHeader: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Oggi" }
        if cal.isDateInYesterday(self) { return "Ieri" }
        return formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "it_IT"))).capitalized
    }
}

extension M3Theme {
    var primaryTones: Tones { Tones(accent: primary, onAccent: onPrimary, container: primaryContainer, onContainer: onPrimaryContainer) }
    var tertiaryTones: Tones { Tones(accent: tertiary, onAccent: surface, container: tertiaryContainer, onContainer: onTertiaryContainer) }

    func tones(for kind: CommandKind) -> Tones {
        switch kind {
        case .arm: return armed
        case .disarm: return danger
        case .status: return tertiaryTones
        }
    }
}
