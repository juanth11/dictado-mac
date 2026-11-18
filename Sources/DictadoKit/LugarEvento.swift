import Foundation

/// El lugar físico de un evento (`EKEvent.location`) tal como lo muestran la agenda del lanzador y la del notch.
public enum LugarEvento {
    /// El lugar limpio, o nil si no hay nada que mostrar: vacío, o una URL (la videollamada ya tiene su botón «Unirse»; no se duplica),
    /// o el mismo texto que el enlace de la reunión. Los espacios y saltos de línea se colapsan; las direcciones largas se recortan.
    public static func limpiar(_ ubicacion: String?, enlace: String? = nil, maximo: Int = 90) -> String? {
        guard let ubicacion else { return nil }
        let plano = ubicacion.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !plano.isEmpty else { return nil }
        if esVideollamada(plano) { return nil }
        if let enlace, plano.localizedCaseInsensitiveContains(enlace) { return nil }
        guard plano.count > maximo else { return plano }
        return String(plano.prefix(maximo - 1)) + "…"
    }

    /// Una URL o un dominio de videollamada pegado como «lugar».
    static func esVideollamada(_ texto: String) -> Bool {
        let t = texto.lowercased()
        if t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("www.") { return true }
        let servicios = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "webex.com", "facetime.apple.com"]
        return servicios.contains { t.contains($0) }
    }

    /// `maps://?q=…` con el lugar codificado; nil si el texto no se puede codificar.
    public static func urlMapas(_ lugar: String) -> URL? {
        var permitidos = CharacterSet.alphanumerics
        permitidos.insert(charactersIn: "-._~")
        guard let q = lugar.addingPercentEncoding(withAllowedCharacters: permitidos) else { return nil }
        return URL(string: "maps://?q=" + q)
    }
}
