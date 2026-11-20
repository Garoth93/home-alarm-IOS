import WidgetKit
import SwiftUI
import AlarmCore

// MARK: - Status widget views

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: StatusEntry

    var body: some View {
        let m3 = M3Theme(seed: Palette.defaultAccent, dark: colorScheme == .dark)
        Group {
            switch family {
            case .systemSmall: SmallStatusView(house: entry.house, m3: m3)
            case .systemMedium: MediumStatusView(house: entry.house, m3: m3, maxZones: 3)
            case .systemLarge: LargeStatusView(house: entry.house, m3: m3)
            case .accessoryCircular: CircularStatusView(house: entry.house)
            case .accessoryRectangular: RectangularStatusView(house: entry.house)
            case .accessoryInline: InlineStatusView(house: entry.house)
            default: SmallStatusView(house: entry.house, m3: m3)
            }
        }
        .environment(\.m3, m3)
        .containerBackground(for: .widget) {
            m3.surfaceContainerLow
        }
    }
}

/// Header with house icon, name and assumed state.
private struct StatusHeader: View {
    let house: HouseSnapshot
    let m3: M3Theme
    var compact = false

    var body: some View {
        let s = house.state
        let tones = s.isArmed ? m3.armed : m3.neutral
        HStack(spacing: 10) {
            IconBadge(icon: s.isArmed ? "lock.shield.fill" : "shield.slash", tones: tones, size: compact ? 34 : 40, cookie: true, filled: s.isArmed)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(house.name)
                    .font(.m3LabelMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(1)
                Text(s.isArmed ? (s.zoneName ?? "Inserito") : s.title)
                    .font(compact ? .m3TitleSmall : .m3TitleMedium)
                    .foregroundStyle(m3.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let since = s.since {
                    Text(since, style: .relative)
                        .font(.m3LabelSmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Rounded action tile with icon + label (used for zones and disarm).
private struct ActionTile: View {
    let title: String
    let icon: String
    let tones: Tones
    var filled = false
    var active = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: active ? "checkmark" : icon)
                .font(.system(size: 17, weight: .semibold))
            Text(title)
                .font(.m3LabelMedium)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(filled ? tones.onAccent : tones.onContainer)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .background(filled ? tones.accent : tones.container, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(active ? tones.accent : .clear, lineWidth: 2))
        .widgetAccentable()
    }
}

private struct SmallStatusView: View {
    let house: HouseSnapshot
    let m3: M3Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusHeader(house: house, m3: m3, compact: true)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "shield.slash.fill")
                Text("Disinserisci")
                    .font(.m3LabelLarge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(m3.danger.onAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(m3.danger.accent, in: Capsule())
            .widgetAccentable()
        }
        .padding(14)
        .widgetURL(house.link(.disarm))
    }
}

private struct MediumStatusView: View {
    let house: HouseSnapshot
    let m3: M3Theme
    let maxZones: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Link(destination: house.openLink) {
                    StatusHeader(house: house, m3: m3, compact: true)
                }
                Spacer(minLength: 0)
                Link(destination: house.link(.disarm)) {
                    ActionTile(title: "Disinserisci", icon: "shield.slash.fill", tones: m3.danger, filled: true)
                        .frame(height: 52)
                }
            }
            .frame(maxWidth: .infinity)
            zoneColumn
                .frame(maxWidth: .infinity)
        }
        .padding(14)
    }

    @ViewBuilder
    private var zoneColumn: some View {
        if house.zones.isEmpty {
            Link(destination: house.openLink) {
                ActionTile(title: house.id == nil ? "Apri l'app" : "Aggiungi zone", icon: "plus", tones: m3.neutral)
            }
        } else {
            VStack(spacing: 8) {
                ForEach(house.zones.prefix(maxZones)) { z in
                    Link(destination: house.link(.arm(zoneID: z.id))) {
                        ZoneRowTile(zone: z, m3: m3, active: house.state.isArmed && house.state.zoneID == z.id)
                    }
                }
            }
        }
    }
}

private struct ZoneRowTile: View {
    let zone: HouseSnapshot.ZoneItem
    let m3: M3Theme
    let active: Bool

    var body: some View {
        let tones = m3.tones(zone.colorHex)
        HStack(spacing: 8) {
            Image(systemName: active ? "checkmark" : zone.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(active ? tones.onAccent : tones.onContainer)
                .frame(width: 26, height: 26)
                .background(active ? tones.accent : tones.container.opacity(0.9), in: Circle())
            Text(zone.name)
                .font(.m3LabelLarge)
                .foregroundStyle(m3.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(active ? tones.container : m3.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .widgetAccentable()
    }
}

private struct LargeStatusView: View {
    let house: HouseSnapshot
    let m3: M3Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Link(destination: house.openLink) {
                StatusHeader(house: house, m3: m3)
            }
            Link(destination: house.link(.disarm)) {
                ActionTile(title: "Disinserisci", icon: "shield.slash.fill", tones: m3.danger, filled: true)
                    .frame(height: 64)
            }
            if house.zones.isEmpty {
                Link(destination: house.openLink) {
                    ActionTile(title: house.id == nil ? "Apri l'app per configurare" : "Aggiungi le zone nell'app", icon: "plus", tones: m3.neutral)
                }
            } else {
                let zones = Array(house.zones.prefix(6))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(zones) { z in
                        Link(destination: house.link(.arm(zoneID: z.id))) {
                            ActionTile(title: z.name, icon: z.icon, tones: m3.tones(z.colorHex),
                                       active: house.state.isArmed && house.state.zoneID == z.id)
                                .frame(height: 62)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if house.supportsStatus {
                Link(destination: house.link(.status)) {
                    HStack {
                        Image(systemName: "questionmark.bubble.fill")
                        Text("Chiedi stato")
                    }
                    .font(.m3LabelLarge)
                    .foregroundStyle(m3.onTertiaryContainer)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(m3.tertiaryContainer, in: Capsule())
                }
            }
        }
        .padding(16)
    }
}

// MARK: Lock screen

private struct CircularStatusView: View {
    let house: HouseSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: house.state.isArmed ? "lock.shield.fill" : "shield.slash.fill")
                    .font(.system(size: 20, weight: .semibold))
                Text(house.state.isArmed ? "ON" : "OFF")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .widgetAccentable()
        }
        .widgetURL(house.link(.disarm))
    }
}

private struct RectangularStatusView: View {
    let house: HouseSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: house.state.isArmed ? "lock.shield.fill" : "shield.slash.fill")
                .font(.system(size: 26, weight: .semibold))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(house.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(house.state.isArmed ? (house.state.zoneName ?? "Inserito") : house.state.title)
                    .font(.subheadline)
                    .lineLimit(1)
                if let since = house.state.since {
                    Text(since, style: .relative)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(house.openLink)
    }
}

private struct InlineStatusView: View {
    let house: HouseSnapshot

    var body: some View {
        let s = house.state
        Label(s.isArmed ? "\(house.name): \(s.zoneName ?? "inserito")" : "\(house.name): \(s.title.lowercased())",
              systemImage: s.isArmed ? "lock.shield.fill" : "shield.slash")
            .widgetURL(house.openLink)
    }
}

// MARK: - Quick action views

struct QuickActionView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: QuickActionEntry

    var body: some View {
        let m3 = M3Theme(seed: Palette.defaultAccent, dark: colorScheme == .dark)
        let tones = m3.tones(entry.colorHex)
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: entry.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .widgetAccentable()
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        IconBadge(icon: entry.symbol, tones: tones, size: 56, cookie: true, filled: true)
                            .widgetAccentable()
                        Spacer(minLength: 0)
                        if entry.armed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(tones.accent)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(entry.title)
                        .font(.m3TitleLarge)
                        .foregroundStyle(tones.onContainer)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(entry.subtitle)
                        .font(.m3LabelMedium)
                        .foregroundStyle(tones.onContainer.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(16)
            }
        }
        .widgetURL(entry.url)
        .environment(\.m3, m3)
        .containerBackground(for: .widget) {
            family == .accessoryCircular ? Color.clear : tones.container
        }
    }
}
