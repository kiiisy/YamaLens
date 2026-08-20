@MainActor
protocol LocationObservationProvider: AnyObject {
    func authorizationState() -> LocationAuthorizationState
    func requestCurrentLocation() async -> Result<LocationObservation, LocationObservationFailure>
}
