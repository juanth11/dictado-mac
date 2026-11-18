import AppKit
import ApplicationServices
import DictadoKit

/// Modos por app: el tono del pulido según dónde dictas, con tus propias instrucciones. Viven en
/// `~/Library/Application Support/Dictado/modos.txt` (menú → Editar modos…); se leen en cada dictado, así que un
/// cambio vale desde el siguiente. La primera vez el archivo se arma con la tabla de siempre (`TablaModos`).
enum ModosApp {
    static var archivo: URL {
        Ajustes.archivoVocabulario.deletingLastPathComponent().appendingPathComponent("modos.txt")
    }

    static let neutro = ModoDictado(nombre: "Cualquier otra app", apps: ["*"], instrucciones: ModoPulido.neutro.tono)

    static func todos() -> [ModoDictado] {
        if !FileManager.default.fileExists(atPath: archivo.path) {
            try? FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? inicial.write(to: archivo, atomically: true, encoding: .utf8)
        }
        let modos = ModosDictado.leer((try? String(contentsOf: archivo, encoding: .utf8)) ?? "")
        return modos.isEmpty ? ModosDictado.leer(inicial) : modos
    }

    static func elegir(bundle: String?, nombreApp: String?, titulo: String?) -> ModoDictado {
        ModosDictado.elegir(todos(), bundle: bundle, nombreApp: nombreApp, titulo: titulo,
                            navegador: bundle.map(TablaModos.navegadores.contains) ?? false) ?? neutro
    }

    /// El modo para la app que está al frente ahora.
    @MainActor
    static func actual() -> ModoDictado {
        let app = NSWorkspace.shared.frontmostApplication
        return elegir(bundle: app?.bundleIdentifier, nombreApp: app?.localizedName, titulo: app.flatMap(tituloVentana))
    }

    /// Título de la ventana enfocada de esa app (la pestaña activa en un navegador). Usa Accesibilidad.
    static func tituloVentana(_ app: NSRunningApplication) -> String? {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.2)
        var ventana: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &ventana) == .success,
              let ventana, CFGetTypeID(ventana) == AXUIElementGetTypeID() else { return nil }
        var titulo: CFTypeRef?
        AXUIElementCopyAttributeValue(ventana as! AXUIElement, kAXTitleAttribute as CFString, &titulo)
        return titulo as? String
    }

    /// El archivo de la primera vez: los mismos modos que traía la tabla fija.
    static var inicial: String {
        let grupos: [(String, ModoPulido)] = [("Chat", .chat), ("Correo", .correo),
                                              ("IA, terminal y código", .prompt), ("Documento", .documento)]
        var s = """
        # Modos de Dictado: cómo quieres el texto según la app donde dictas.
        # Cada modo empieza con [Nombre] y sigue con estas líneas:
        #   apps: nombres de app (Mail, WhatsApp) o bundle ids, separados por coma.
        #         Un id que termina en "." vale como prefijo (com.jetbrains. = todas las de JetBrains). * = cualquier app.
        #   pestañas: palabras del título de la pestaña o la ventana (Gmail, Google Docs). En un navegador mandan ellas.
        #   instrucciones: cómo quieres el texto ahí. Puedes poner varias líneas "instrucciones:"; se juntan.
        #   pulir: no   → en esas apps el dictado se pega tal cual, sin IA.
        # Gana el primer modo que coincida. Los cambios valen desde el siguiente dictado.
        # Las instrucciones cambian el estilo (tono, formato, trato); el pulido nunca agrega ideas ni saludos.

        """
        for (nombre, modo) in grupos {
            let apps = TablaModos.apps.filter { $0.1 == modo }.map(\.0)
            let pestanas = TablaModos.titulos.filter { $0.1 == modo }.map(\.0)
            s += "\n[\(nombre)]\n"
            if !apps.isEmpty { s += "apps: " + apps.joined(separator: ", ") + "\n" }
            if !pestanas.isEmpty { s += "pestañas: " + pestanas.joined(separator: ", ") + "\n" }
            s += "instrucciones: \(modo.tono)\n"
        }
        s += "\n[\(neutro.nombre)]\napps: *\ninstrucciones: \(ModoPulido.neutro.tono)\n"
        return s
    }
}
