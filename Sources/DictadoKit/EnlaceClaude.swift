import Foundation

public enum EnlaceClaude {
    /// Claude para Mac acepta `claude://claude.ai/new?q=<texto>` (lo usa su propio servicio "Ask Claude") y deja
    /// el texto en un chat nuevo. Corta en 14.336 caracteres y rechaza un `q` que empiece por "/".
    public static func url(_ texto: String) -> URL? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 14_000, !t.hasPrefix("/") else { return nil }
        let permitidos = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let q = t.addingPercentEncoding(withAllowedCharacters: permitidos) else { return nil }
        return URL(string: "claude://claude.ai/new?q=\(q)&surface=chat")
    }
}
