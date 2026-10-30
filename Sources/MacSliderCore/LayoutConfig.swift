/// When the strip recentres on the focused column.
public enum CenterMode: String, Codable, CaseIterable, Sendable {
    /// Scroll only as far as needed to bring the focused column into view.
    case never
    /// Centre the focused column when it would otherwise be (partly) off-screen.
    case onOverflow
    /// Always keep the focused column centred.
    case always
}

/// Geometry settings that drive `Strip.layout`.
public struct LayoutConfig: Equatable, Codable, Sendable {
    /// Space between neighbouring columns and between stacked windows.
    public var gap: Double
    /// Space between the strip and the edges of the display's visible area.
    public var edgeGap: Double
    /// How many points of an off-screen ("parked") window stay visible.
    /// macOS refuses to move a window entirely off every display.
    public var parkSliver: Double
    /// Width presets, as fractions of the usable display width, cycled by "Cycle width".
    public var widthPresets: [Double]
    /// Width given to newly tiled windows.
    public var defaultWidth: Double
    public var centerMode: CenterMode
    /// Height reserved above tabbed columns for their tab bar.
    public var tabBarHeight: Double
    /// Which way the strip runs.
    public var direction: StripDirection

    public init(
        gap: Double = 8,
        edgeGap: Double = 8,
        parkSliver: Double = 4,
        widthPresets: [Double] = [0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0, 0.75],
        defaultWidth: Double = 0.5,
        centerMode: CenterMode = .never,
        tabBarHeight: Double = 28,
        direction: StripDirection = .leftToRight
    ) {
        self.gap = gap
        self.edgeGap = edgeGap
        self.parkSliver = parkSliver
        self.widthPresets = widthPresets
        self.defaultWidth = defaultWidth
        self.centerMode = centerMode
        self.tabBarHeight = tabBarHeight
        self.direction = direction
    }

    public static let minimumWidth = 0.1
    public static let maximumWidth = 1.0

    /// Presets sorted, de-duplicated and clamped to the valid range.
    public var sanitizedPresets: [Double] {
        let clamped = widthPresets.map { Self.clampWidth($0) }
        var result: [Double] = []
        for value in clamped.sorted() where !result.contains(where: { abs($0 - value) < 0.001 }) {
            result.append(value)
        }
        return result.isEmpty ? [0.5] : result
    }

    public static func clampWidth(_ width: Double) -> Double {
        min(max(width, minimumWidth), maximumWidth)
    }

    /// The width of the area columns are laid out in, for a viewport of `viewportWidth`.
    public func usableWidth(_ viewportWidth: Double) -> Double {
        max(viewportWidth - 2 * edgeGap, 1)
    }

    /// Converts a width fraction to points. Fractions are chosen so that
    /// columns whose fractions sum to 1 exactly fill the usable width,
    /// gaps included (two ½ columns fit side by side).
    public func columnWidth(fraction: Double, viewportWidth: Double) -> Double {
        let usable = usableWidth(viewportWidth)
        return max(fraction * (usable + gap) - gap, 1)
    }

    /// Inverse of `columnWidth(fraction:viewportWidth:)`.
    public func fraction(forColumnWidth width: Double, viewportWidth: Double) -> Double {
        let usable = usableWidth(viewportWidth)
        return Self.clampWidth((width + gap) / (usable + gap))
    }
}

extension LayoutConfig {
    enum CodingKeys: String, CodingKey {
        case gap, edgeGap, parkSliver, widthPresets, defaultWidth, centerMode, tabBarHeight, direction
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LayoutConfig()
        self.init(
            gap: (try? c.decodeIfPresent(Double.self, forKey: .gap)) ?? d.gap,
            edgeGap: (try? c.decodeIfPresent(Double.self, forKey: .edgeGap)) ?? d.edgeGap,
            parkSliver: (try? c.decodeIfPresent(Double.self, forKey: .parkSliver)) ?? d.parkSliver,
            widthPresets: (try? c.decodeIfPresent([Double].self, forKey: .widthPresets)) ?? d.widthPresets,
            defaultWidth: (try? c.decodeIfPresent(Double.self, forKey: .defaultWidth)) ?? d.defaultWidth,
            centerMode: (try? c.decodeIfPresent(CenterMode.self, forKey: .centerMode)) ?? d.centerMode,
            tabBarHeight: (try? c.decodeIfPresent(Double.self, forKey: .tabBarHeight)) ?? d.tabBarHeight,
            direction: (try? c.decodeIfPresent(StripDirection.self, forKey: .direction)) ?? d.direction
        )
    }
}
