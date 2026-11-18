import Foundation

/// Un modo de dictado: en qué apps o pestañas aplica y cómo quieres el texto ahí. Se escriben en `modos.txt`.
public struct ModoDictado: Equatable, Sendable {
    public var nombre: String
    /// Nombres de app ("Mail") o bundle ids ("com.apple.mail"; uno que termina en "." vale como prefijo). "*" = cualquier app.
    public var apps: [String]
    /// Palabras del título de la ventana o pestaña ("Gmail", "Google Docs").
    public var pestanas: [String]
    public var instrucciones: String
    /// false: el dictado se pega tal cual, sin IA.
    public var pulir: Bool

    public init(nombre: String, apps: [String] = [], pestanas: [String] = [], instrucciones: String = "", pulir: Bool = true) {
        self.nombre = nombre
        self.apps = apps
        self.pestanas = pestanas
        self.instrucciones = instrucciones
        self.pulir = pulir
    }
}

public enum ModosDictado {
    /// Lee el archivo de modos. Formato:
    ///   [Nombre]
    ///   apps: Mail, com.microsoft.Outlook
    ///   pestañas: Gmail
    ///   instrucciones: Tono profesional…   (se puede repetir; se juntan)
    ///   pulir: no
    public static func leer(_ texto: String) -> [ModoDictado] {
        var modos: [ModoDictado] = []
        for cruda in texto.split(separator: "\n", omittingEmptySubsequences: false) {
            let linea = cruda.trimmingCharacters(in: .whitespaces)
            if linea.isEmpty || linea.hasPrefix("#") { continue }
            if linea.hasPrefix("["), linea.hasSuffix("]") {
                modos.append(ModoDictado(nombre: String(linea.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            guard !modos.isEmpty, let dos = linea.firstIndex(of: ":") else { continue }
            let clave = linea[..<dos].trimmingCharacters(in: .whitespaces).lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)
            let valor = linea[linea.index(after: dos)...].trimmingCharacters(in: .whitespaces)
            let lista = valor.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            switch clave {
            case "apps", "app": modos[modos.count - 1].apps += lista
            case "pestanas", "pestana", "titulos", "titulo": modos[modos.count - 1].pestanas += lista
            case "instrucciones", "instruccion", "tono":
                let actual = modos[modos.count - 1].instrucciones
                modos[modos.count - 1].instrucciones = actual.isEmpty ? valor : actual + " " + valor
            case "pulir":
                modos[modos.count - 1].pulir = !["no", "false", "0", "nunca"].contains(valor.lowercased())
            default: break
            }
        }
        return modos
    }

    /// El modo para la app al frente. En un navegador manda el título de la pestaña; en otra app, la app y, si no
    /// coincide ninguna, el título de su ventana. Si nada coincide, el modo con `apps: *` (o nil).
    public static func elegir(_ modos: [ModoDictado], bundle: String?, nombreApp: String?, titulo: String?,
                              navegador: Bool) -> ModoDictado? {
        func porTitulo() -> ModoDictado? {
            guard let titulo, !titulo.isEmpty else { return nil }
            return modos.first { $0.pestanas.contains { titulo.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
        }
        func porApp() -> ModoDictado? {
            modos.first { modo in
                modo.apps.contains { entrada in
                    if entrada == "*" { return false }
                    if let bundle, entrada.contains(".") {
                        return entrada.hasSuffix(".") ? bundle.hasPrefix(entrada) : bundle == entrada
                    }
                    return nombreApp.map { $0.compare(entrada, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame } ?? false
                }
            }
        }
        let comodin = modos.first { $0.apps.contains("*") }
        if navegador { return porTitulo() ?? porApp() ?? comodin }
        return porApp() ?? porTitulo() ?? comodin
    }
}
