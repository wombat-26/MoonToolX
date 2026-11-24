import CoreLocation
import Observation

/// Standort des Macs für die Entfernung vom Beobachter.
/// Der Standort wird nur lokal verwendet und zwischengespeichert, damit der Wert beim Start sofort erscheint.
@MainActor
@Observable
final class LocationModel: NSObject {
    enum Status { case pending, denied, available }

    private(set) var observer: Observer?
    private(set) var status: Status = .pending

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    private static let cacheKey = "lastObserver"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(Observer.self, from: data) {
            observer = cached
            status = .available
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Fragt beim ersten Mal um Erlaubnis und aktualisiert den Standort danach alle 15 Minuten.
    func start() {
        handle(manager.authorizationStatus)
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                guard let self else { return }
                if self.isAuthorized(self.manager.authorizationStatus) { self.manager.requestLocation() }
            }
        }
    }

    private func isAuthorized(_ s: CLAuthorizationStatus) -> Bool {
        s == .authorizedAlways
    }

    private func handle(_ s: CLAuthorizationStatus) {
        switch s {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .denied
            observer = nil
            UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        default:
            if isAuthorized(s) { manager.requestLocation() }
        }
    }

    private func update(latitude: Double, longitude: Double, altitude: Double?) {
        let new = Observer(latitude: latitude, longitude: longitude, altitudeM: altitude ?? 0)
        observer = new
        status = .available
        if let data = try? JSONEncoder().encode(new) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }
}

extension LocationModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in self.handle(s) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        let alt: Double? = loc.verticalAccuracy > 0 ? loc.altitude : nil
        Task { @MainActor in self.update(latitude: lat, longitude: lon, altitude: alt) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in
            if denied { self.handle(.denied) }
        }
    }
}
