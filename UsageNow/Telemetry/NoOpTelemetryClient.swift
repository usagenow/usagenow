/// Discards every event. The only telemetry client in this build —
/// nothing is sent anywhere.
struct NoOpTelemetryClient: TelemetryClient {
    func send(_ event: TelemetryEvent) async {}
}
