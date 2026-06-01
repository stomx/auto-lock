import Foundation

public enum BestDeviceSelector {
    /// 추적 대상 ID들 중 스캐너에 보이는 기기에서 smoothedRssi 최대값을 고른다.
    public static func select(trackedIDs: [UUID], from devices: [UUID: DiscoveredDevice]) -> ProximitySnapshot.BestDevice? {
        var best: ProximitySnapshot.BestDevice? = nil
        for id in trackedIDs {
            if let d = devices[id] {
                if best == nil || d.smoothedRssi > best!.smoothedRssi {
                    best = ProximitySnapshot.BestDevice(id: id, smoothedRssi: d.smoothedRssi, lastSeen: d.lastSeen)
                }
            }
        }
        return best
    }
}
