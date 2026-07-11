import Testing
@testable import AutoLockCore

@Suite struct ScanDemandTests {
    @Test func deviceSelectionCanScanWithoutMonitoring() {
        var demand = ScanDemand()

        demand.request(.deviceSelection)

        #expect(demand.isRequested)
    }

    @Test func cancellingOnePurposeKeepsOtherPurposeActive() {
        var demand = ScanDemand()
        demand.request(.proximityMonitoring)
        demand.request(.deviceSelection)

        demand.cancel(.deviceSelection)

        #expect(demand.isRequested)
    }

    @Test func scanningStopsAfterLastPurposeIsCancelled() {
        var demand = ScanDemand()
        demand.request(.proximityMonitoring)
        demand.request(.deviceSelection)

        demand.cancel(.proximityMonitoring)
        demand.cancel(.deviceSelection)

        #expect(!demand.isRequested)
    }

    @Test func duplicateRequestsAndCancellationsAreIdempotent() {
        var demand = ScanDemand()
        demand.request(.deviceSelection)
        demand.request(.deviceSelection)
        demand.cancel(.deviceSelection)
        demand.cancel(.deviceSelection)

        #expect(!demand.isRequested)
    }
}
