//
//  WeatherApplet.swift
//  wink
//

import CoreLocation
import SwiftUI

/// Today's weather for the device location, from Open-Meteo.
@Observable
final class WeatherModel {
    struct Snapshot {
        let temperature: Measurement<UnitTemperature>
        /// 0...1 chance of rain in the current hour.
        let rainNow: Double
        let high: Measurement<UnitTemperature>
        let low: Measurement<UnitTemperature>
        /// 0...1 chance of rain over the whole day.
        let rainToday: Double
    }

    enum State {
        case loading
        case needsPermission
        case loaded(Snapshot)
        case failed(LocalizedStringKey)
    }

    private enum LoadError: Error {
        case locationDenied
        case noLocation
    }

    private(set) var state: State = .loading

    /// Shows the location prompt. Only call this after the user taps, since the case hides the prompt.
    func requestAccess() async {
        state = .loading
        await fetch()
    }

    func load() async {
        // Asking for location here would put a hidden prompt over the screen, so wait for a tap.
        if CLLocationManager().authorizationStatus == .notDetermined {
            state = .needsPermission
            return
        }
        await fetch()
    }

    private func fetch() async {
        do {
            let location = try await Self.currentLocation()
            state = .loaded(try await WeatherSource.snapshot(at: location))
        } catch LoadError.locationDenied {
            state = .failed("Allow location access in Settings")
        } catch {
            state = .failed("Weather unavailable")
        }
    }

    /// The first location fix, asking for when-in-use permission if needed.
    private static func currentLocation() async throws -> CLLocation {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }

        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location {
                return location
            }
            if update.authorizationDenied || update.authorizationDeniedGlobally {
                throw LoadError.locationDenied
            }
        }
        throw LoadError.noLocation
    }
}

/// Fetches today's weather from Open-Meteo (open-meteo.com): free, no API key or account.
/// Data is CC BY 4.0, so a public release needs an "Open-Meteo" attribution.
enum WeatherSource {
    /// The slice of Open-Meteo's forecast response the applet uses.
    nonisolated private struct Forecast: Decodable {
        nonisolated struct Current: Decodable {
            /// Local time, e.g. "2026-10-27T14:15".
            let time: String
            let temperature_2m: Double
        }
        nonisolated struct Hourly: Decodable {
            /// Local hour starts, e.g. "2026-10-27T14:00".
            let time: [String]
            /// Percent, 0...100. Can be missing for some hours.
            let precipitation_probability: [Double?]
        }
        nonisolated struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Double?]
        }

        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    private struct BadResponse: Error {}

    static func snapshot(at location: CLLocation) async throws -> WeatherModel.Snapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m"),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            // Times come back in the location's own time zone, so "today" and "this hour" line up.
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        guard let url = components?.url else { throw BadResponse() }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BadResponse() }
        let forecast = try JSONDecoder().decode(Forecast.self, from: data)

        guard let high = forecast.daily.temperature_2m_max.first,
              let low = forecast.daily.temperature_2m_min.first else { throw BadResponse() }

        // The hourly entry whose hour matches the current time ("2026-10-27T14").
        let currentHour = forecast.current.time.prefix(13)
        let hourIndex = forecast.hourly.time.firstIndex { $0.hasPrefix(currentHour) } ?? 0
        let rainNow = forecast.hourly.precipitation_probability.indices.contains(hourIndex)
            ? forecast.hourly.precipitation_probability[hourIndex] ?? 0
            : 0

        return WeatherModel.Snapshot(
            temperature: Measurement(value: forecast.current.temperature_2m, unit: .celsius),
            rainNow: rainNow / 100,
            high: Measurement(value: high, unit: .celsius),
            low: Measurement(value: low, unit: .celsius),
            rainToday: (forecast.daily.precipitation_probability_max.first.flatMap { $0 } ?? 0) / 100
        )
    }
}

/// Four circles: temperature now, chance of rain now, today's high over low, chance of rain today.
struct WeatherApplet: View {
    @State private var weather = WeatherModel()

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, WinkLayout.islandClearance)
            .padding(.bottom, WinkLayout.bottomInset)
            .task { await weather.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch weather.state {
        case .loading:
            ProgressView()
                .tint(WinkTheme.primaryText)
        case .needsPermission:
            PermissionPrompt(title: "Allow location access") {
                await weather.requestAccess()
            }
        case .failed(let message):
            Text(message)
                .font(.wink(26))
                .multilineTextAlignment(.center)
                .foregroundStyle(WinkTheme.secondaryText)
                .padding(.horizontal, pt(40))
        case .loaded(let snapshot):
            WeatherGrid(snapshot: snapshot)
        }
    }
}

private struct WeatherGrid: View {
    let snapshot: WeatherModel.Snapshot

    var body: some View {
        Grid(horizontalSpacing: pt(16), verticalSpacing: pt(16)) {
            GridRow {
                WeatherCircle(fill: WeatherColors.temperature(snapshot.temperature)) {
                    value(snapshot.temperature.formatted(Self.degrees))
                }
                .accessibilityLabel("Temperature now")

                WeatherCircle(fill: WeatherColors.rain(snapshot.rainNow)) {
                    value(snapshot.rainNow.formatted(Self.percent))
                    caption("now")
                }
                .accessibilityLabel("Chance of rain now")
            }
            GridRow {
                WeatherCircle(fill: LinearGradient(
                    colors: [WeatherColors.temperature(snapshot.high), WeatherColors.temperature(snapshot.low)],
                    startPoint: .top,
                    endPoint: .bottom
                )) {
                    VStack(spacing: 0) {
                        Text(snapshot.high.formatted(Self.degrees))
                            .font(.wink(34))
                        Text(snapshot.low.formatted(Self.degrees))
                            .font(.wink(34, weight: .regular))
                    }
                    .monospacedDigit()
                }
                .accessibilityLabel("High and low today")

                WeatherCircle(fill: WeatherColors.rain(snapshot.rainToday)) {
                    value(snapshot.rainToday.formatted(Self.percent))
                    caption("today")
                }
                .accessibilityLabel("Chance of rain today")
            }
        }
    }

    private static let degrees = Measurement<UnitTemperature>.FormatStyle(
        width: .narrow,
        usage: .weather,
        numberFormatStyle: .number.precision(.fractionLength(0))
    )
    private static let percent = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))

    private func value(_ text: String) -> some View {
        Text(text)
            .font(.wink(40))
            .monospacedDigit()
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.wink(16, weight: .medium))
            .opacity(0.7)
    }
}

/// A filled circle with black text centered in it.
private struct WeatherCircle<Fill: ShapeStyle, Content: View>: View {
    let fill: Fill
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .foregroundStyle(.black)
        .frame(width: pt(120), height: pt(120))
        .background(Circle().fill(fill))
        .accessibilityElement(children: .combine)
    }
}

/// Maps weather values onto the color gradients.
enum WeatherColors {
    /// Blue at -5 °C and below, white at 15 °C, red at 35 °C and above.
    static func temperature(_ temperature: Measurement<UnitTemperature>) -> Color {
        let celsius = temperature.converted(to: .celsius).value
        if celsius < 15 {
            return Color.white.mix(with: WinkTheme.cold, by: min((15 - celsius) / 20, 1))
        } else {
            return Color.white.mix(with: WinkTheme.hot, by: min((celsius - 15) / 20, 1))
        }
    }

    /// White for no chance of rain, blue for certain rain.
    static func rain(_ chance: Double) -> Color {
        Color.white.mix(with: WinkTheme.rain, by: min(max(chance, 0), 1))
    }
}

#Preview("Loaded") {
    WindowPreview {
        WeatherGrid(snapshot: WeatherModel.Snapshot(
            temperature: Measurement(value: 4, unit: .celsius),
            rainNow: 0.2,
            high: Measurement(value: 29, unit: .celsius),
            low: Measurement(value: 12, unit: .celsius),
            rainToday: 0.8
        ))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, WinkLayout.islandClearance)
        .padding(.bottom, WinkLayout.bottomInset)
    }
}
