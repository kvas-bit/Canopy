import Foundation

/// Resolved geographic position used for real-sun lighting.
public struct SolarLocation: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    /// e.g. "America/New_York" or "Custom"
    public var label: String
}

/// Lightweight offline solar-position calculator (NOAA fractional-year
/// approximations). No network, no Core Location prompt — coordinates are
/// inferred from the system time zone and can be pinned exactly via:
///
///     defaults write com.kavi.canopy solarLatitude  -float 42.36
///     defaults write com.kavi.canopy solarLongitude -float -71.06
public enum SolarCalculator {

    // MARK: - Location resolution

    public static func currentLocation() -> SolarLocation {
        let defaults = UserDefaults.standard
        let latOverride = defaults.object(forKey: "solarLatitude") as? Double
        let lonOverride = defaults.object(forKey: "solarLongitude") as? Double
        if let lat = latOverride, let lon = lonOverride, abs(lat) <= 90.0, abs(lon) <= 180.0 {
            return SolarLocation(latitude: lat, longitude: lon, label: "Custom")
        }

        let tz = TimeZone.current
        if let coords = tzCoordinates[tz.identifier] {
            return SolarLocation(latitude: coords.lat, longitude: coords.lon, label: tz.identifier)
        }
        // Fallback: estimate longitude from the UTC offset; temperate latitude.
        let estimatedLon = -Double(tz.secondsFromGMT()) / 240.0
        return SolarLocation(latitude: 40.0, longitude: estimatedLon, label: tz.identifier)
    }

    // MARK: - Solar position

    /// Solar elevation angle in degrees above the horizon (negative = below).
    /// Computed from the UTC instant + longitude, so DST and civil-time shifts
    /// are handled implicitly — the sun doesn't care about the clock.
    public static func solarElevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let dayOfYear = Double(utcCal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let utcHours = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400.0) / 3_600.0

        let gamma = 2.0 * .pi / 365.0 * (dayOfYear - 1.0 + (utcHours - 12.0) / 24.0)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                             - 0.014615 * cos(2.0 * gamma) - 0.040849 * sin(2.0 * gamma))
        let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
                 - 0.006758 * cos(2.0 * gamma) + 0.000907 * sin(2.0 * gamma)
                 - 0.002697 * cos(3.0 * gamma) + 0.00148 * sin(3.0 * gamma)

        // True solar time (minutes) — longitude correction applied to real UTC,
        // so no separate timezone term is needed.
        let tst = utcHours * 60.0 + eqTime + 4.0 * longitude
        let hourAngle = (tst / 4.0 - 180.0) * .pi / 180.0

        let lat = latitude * .pi / 180.0
        let cosZenith = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle)
        return 90.0 - acos(min(1.0, max(-1.0, cosZenith))) * 180.0 / .pi
    }

    /// Sunrise/sunset (zenith 90.833°) for the local calendar day containing `date`.
    /// Returns nil for either endpoint during polar day/night.
    public static func sunriseSunset(
        on date: Date,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone = .current
    ) -> (sunrise: Date?, sunset: Date?) {
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = timeZone
        let dayStart = localCal.startOfDay(for: date)

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let dayOfYear = Double(utcCal.ordinality(of: .day, in: .year, for: date) ?? 1)

        // Equation of time / declination sampled at the day's UTC noon —
        // intraday drift is well under a minute of clock error.
        let gamma = 2.0 * .pi / 365.0 * (dayOfYear - 1.0)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                             - 0.014615 * cos(2.0 * gamma) - 0.040849 * sin(2.0 * gamma))
        let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
                 - 0.006758 * cos(2.0 * gamma) + 0.000907 * sin(2.0 * gamma)
                 - 0.002697 * cos(3.0 * gamma) + 0.00148 * sin(3.0 * gamma)

        let lat = latitude * .pi / 180.0
        let zenith = 90.833 * .pi / 180.0
        let cosH = (cos(zenith) - sin(lat) * sin(decl)) / (cos(lat) * cos(decl))
        guard cosH >= -1.0, cosH <= 1.0 else {
            return (nil, nil) // polar night or midnight sun
        }

        let haDeg = acos(cosH) * 180.0 / .pi
        // UTC minutes of sunrise/sunset relative to solar noon (720 min UTC).
        let sunriseUTCMin = 720.0 - 4.0 * (longitude + haDeg) - eqTime
        let sunsetUTCMin = 720.0 - 4.0 * (longitude - haDeg) - eqTime
        let tzOffsetMin = Double(timeZone.secondsFromGMT(for: date)) / 60.0

        return (
            dayStart.addingTimeInterval((sunriseUTCMin + tzOffsetMin) * 60.0),
            dayStart.addingTimeInterval((sunsetUTCMin + tzOffsetMin) * 60.0)
        )
    }

    // MARK: - Menu bar checker summary

    /// e.g. "☀︎ 6:31 AM → ☾ 4:22 PM · America/New_York"
    public static func summary(now: Date = Date()) -> String {
        let loc = currentLocation()
        let (sunrise, sunset) = sunriseSunset(on: now, latitude: loc.latitude, longitude: loc.longitude)
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        fmt.timeZone = .current
        let rise = sunrise.map { fmt.string(from: $0) } ?? "—"
        let set = sunset.map { fmt.string(from: $0) } ?? "—"
        let source = loc.label == "Custom"
            ? String(format: "%.2f, %.2f", loc.latitude, loc.longitude)
            : loc.label.replacingOccurrences(of: "_", with: " ").components(separatedBy: "/").last ?? loc.label
        return "☀︎ \(rise) → ☾ \(set) · \(source)"
    }

    // MARK: - Time zone → representative coordinates

    /// Canonical city coordinates for populated IANA zones. These are
    /// representatives, not borders — error within a zone is typically under
    /// ~20 minutes of solar time, and `solarLatitude`/`solarLongitude`
    /// defaults keys pin an exact position.
    private static let tzCoordinates: [String: (lat: Double, lon: Double)] = [
        // North America
        "America/New_York": (42.36, -71.06),      // US Eastern — Boston centroid (New England)
        "US/Eastern": (42.36, -71.06),
        "America/Detroit": (42.33, -83.05),
        "America/Toronto": (43.65, -79.38),
        "America/Montreal": (45.50, -73.57),
        "America/Chicago": (41.88, -87.63),
        "US/Central": (41.88, -87.63),
        "America/Winnipeg": (49.90, -97.14),
        "America/Mexico_City": (19.43, -99.13),
        "America/Denver": (39.74, -104.99),
        "US/Mountain": (39.74, -104.99),
        "America/Edmonton": (53.55, -113.49),
        "America/Phoenix": (33.45, -112.07),
        "America/Los_Angeles": (34.05, -118.24),
        "US/Pacific": (34.05, -118.24),
        "America/Vancouver": (49.28, -123.12),
        "America/Tijuana": (32.51, -117.04),
        "America/Anchorage": (61.22, -149.90),
        "US/Alaska": (61.22, -149.90),
        "Pacific/Honolulu": (21.31, -157.86),
        "US/Hawaii": (21.31, -157.86),
        "America/Halifax": (44.65, -63.57),
        "America/St_Johns": (47.56, -52.71),
        "America/Puerto_Rico": (18.47, -66.11),
        // Central & South America
        "America/Bogota": (4.71, -74.07),
        "America/Lima": (-12.05, -77.04),
        "America/Santiago": (-33.45, -70.67),
        "America/Sao_Paulo": (-23.55, -46.63),
        "America/Argentina/Buenos_Aires": (-34.60, -58.38),
        "America/Caracas": (10.48, -66.90),
        // Europe
        "Europe/London": (51.51, -0.13),
        "Europe/Dublin": (53.35, -6.26),
        "Europe/Lisbon": (38.72, -9.14),
        "Europe/Madrid": (40.42, -3.70),
        "Europe/Paris": (48.86, 2.35),
        "Europe/Berlin": (52.52, 13.41),
        "Europe/Amsterdam": (52.37, 4.90),
        "Europe/Brussels": (50.85, 4.35),
        "Europe/Rome": (41.90, 12.50),
        "Europe/Zurich": (47.38, 8.54),
        "Europe/Vienna": (48.21, 16.37),
        "Europe/Stockholm": (59.33, 18.07),
        "Europe/Oslo": (59.91, 10.75),
        "Europe/Copenhagen": (55.68, 12.57),
        "Europe/Helsinki": (60.17, 24.94),
        "Europe/Warsaw": (52.23, 21.01),
        "Europe/Prague": (50.08, 14.44),
        "Europe/Budapest": (47.50, 19.04),
        "Europe/Athens": (37.98, 23.73),
        "Europe/Istanbul": (41.01, 28.98),
        "Europe/Moscow": (55.76, 37.62),
        "Europe/Kyiv": (50.45, 30.52),
        "Europe/Reykjavik": (64.15, -21.94),
        // Africa
        "Africa/Cairo": (30.04, 31.24),
        "Africa/Lagos": (6.52, 3.38),
        "Africa/Nairobi": (-1.29, 36.82),
        "Africa/Johannesburg": (-26.20, 28.05),
        "Africa/Casablanca": (33.57, -7.59),
        // Middle East & Asia
        "Asia/Jerusalem": (31.77, 35.21),
        "Asia/Dubai": (25.20, 55.27),
        "Asia/Riyadh": (24.71, 46.68),
        "Asia/Karachi": (24.86, 67.00),
        "Asia/Kolkata": (28.61, 77.21),
        "Asia/Calcutta": (28.61, 77.21),
        "Asia/Dhaka": (23.81, 90.41),
        "Asia/Bangkok": (13.76, 100.50),
        "Asia/Jakarta": (-6.21, 106.85),
        "Asia/Singapore": (1.35, 103.82),
        "Asia/Hong_Kong": (22.32, 114.17),
        "Asia/Shanghai": (31.23, 121.47),
        "Asia/Taipei": (25.03, 121.57),
        "Asia/Manila": (14.60, 120.98),
        "Asia/Seoul": (37.57, 126.98),
        "Asia/Tokyo": (35.68, 139.69),
        "Asia/Almaty": (43.24, 76.89),
        "Asia/Tbilisi": (41.72, 44.79),
        // Oceania
        "Australia/Sydney": (-33.87, 151.21),
        "Australia/Melbourne": (-37.81, 144.96),
        "Australia/Brisbane": (-27.47, 153.03),
        "Australia/Perth": (-31.95, 115.86),
        "Australia/Adelaide": (-34.93, 138.60),
        "Pacific/Auckland": (-36.85, 174.76),
        "Pacific/Fiji": (-18.14, 178.44),
        "Pacific/Guam": (13.44, 144.79),
        // UTC
        "UTC": (0.0, 0.0),
        "Etc/UTC": (0.0, 0.0),
        "GMT": (51.51, -0.13),
    ]
}
