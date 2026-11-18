import Foundation

public enum Medida {
    /// 8 900 000 000 → "8,9 GB"; 640 000 000 → "640 MB".
    public static func bytes(_ b: Double) -> String {
        if b >= 1e9 { return String(format: "%.1f GB", b / 1e9).replacingOccurrences(of: ".", with: ",") }
        if b >= 1e6 { return String(format: "%.0f MB", b / 1e6) }
        return String(format: "%.0f KB", b / 1e3)
    }

    public static func porcentaje(_ f: Double) -> String { "\(Int((f * 100).rounded())) %" }
}
