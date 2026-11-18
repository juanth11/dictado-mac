import Foundation

/// El dueño del sistema: los pendientes de las notas de reunión (`- [ ] Nombre · qué · cuándo`) que son tuyos.
/// El nombre sale del ajuste `nombre` (`defaults write app.dictado nombre "Ana"`) o, si no está, del primer nombre
/// de la cuenta del Mac. "Tú", "Tu" y "¿?" (sin dueño claro) también cuentan como tuyos.
public enum Dueno {
    public static var nombre: String {
        if let n = UserDefaults.standard.string(forKey: "nombre")?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
    }

    /// ¿Esta línea es tuya? Compara sin mayúsculas con el nombre configurado.
    public static func esMio(_ quien: String, nombre: String = Dueno.nombre) -> Bool {
        let q = quien.trimmingCharacters(in: .whitespaces).lowercased()
        if q == "tú" || q == "tu" || q == "¿?" { return true }
        let n = nombre.lowercased()
        return !n.isEmpty && q.hasPrefix(n)
    }
}
