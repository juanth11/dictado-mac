import DictadoKit
import Foundation

/// Ajustes en UserDefaults (dominio app.dictado). Se cambian con `defaults write`:
///   defaults write app.dictado idioma es-MX                  (es-US por defecto)
///   defaults write app.dictado motor speech|dictation
///   defaults write app.dictado estilo prisma|aurora|orbe|…   (también desde el menú)
///   defaults write app.dictado inbox "/ruta/a/tus/ideas"      (adónde van las ideas de ⌥⇧Espacio)
///   defaults write app.dictado protegidas -array "/ruta/1" "/ruta/2"   (carpetas que la limpieza jamás toca)
///   defaults write app.dictado agenda.horaInicio -int 8      (horario para los huecos de la agenda: 8 a 18, lunes a viernes)
///   defaults write app.dictado agenda.horaFin -int 18
///   defaults write app.dictado agenda.dias -array 2 3 4 5 6  (1 = domingo … 7 = sábado)
///   defaults write app.dictado agenda.huecoMinimo -int 30    (minutos)
///   defaults write app.dictado agenda.huecoDias -int 5       (días laborales que se revisan)
///   defaults write app.dictado isla.clasica -bool YES        (la isla abierta con el diseño anterior, sin las cinco pestañas de Aurora)
///   defaults write app.dictado isla.apps -array com.apple.Safari com.apple.Notes   (las apps de Inicio; por omisión, las más usadas)
///   defaults write app.dictado isla.fijas -array com.spotify.client   (apps fijadas al principio de Inicio y del Dock; por omisión, Spotify)
///   defaults write app.dictado isla.atajos -array "Mi atajo" "Otro"   (los atajos de Apple que salen en Inicio; por omisión, los seis primeros)
///   defaults write app.dictado centro -dict-add carpeta "/ruta/a/_sistema/centro"  (de dónde se corre `python3 -m centro`; por
///   omisión, la carpeta que contiene el script de `acciones`)
extension UserDefaults {
    /// El dominio app.dictado. Dentro de la app (bundle app.dictado) es `.standard`: macOS no deja usar el propio
    /// identificador como suite ("will not work") y esos ajustes se perdían en silencio. Fuera del bundle (el binario
    /// de línea de comandos en .build) se lee como suite.
    static let dictado: UserDefaults = Bundle.main.bundleIdentifier == "app.dictado"
        ? .standard : (UserDefaults(suiteName: "app.dictado") ?? .standard)
}

struct Ajustes {
    private let d = UserDefaults.dictado

    // No hay modelo es-CO: es-CO cae en es_ES. es-US (español latinoamericano) se acerca más al acento colombiano.
    var idioma: String { d.string(forKey: "idioma") ?? "es-US" }
    var motor: Motor { Motor(rawValue: d.string(forKey: "motor") ?? "") ?? .speech }
    var estilo: Estilo { Estilo(rawValue: d.string(forKey: "estilo") ?? "") ?? .prisma }
    func guardar(estilo: Estilo) { d.set(estilo.rawValue, forKey: "estilo") }
    var isla: Bool { d.object(forKey: "isla") as? Bool ?? true }
    /// Aprender de lo que corriges después de pegar un dictado (sí por defecto).
    var aprender: Bool { d.object(forKey: "aprender") as? Bool ?? true }
    func guardar(aprender: Bool) { d.set(aprender, forKey: "aprender") }
    func guardar(isla: Bool) { d.set(isla, forKey: "isla") }
    /// Abrir Dictado al iniciar sesión (sí por defecto; se apaga desde el menú).
    var abrirAlIniciar: Bool { d.object(forKey: "abrirAlIniciar") as? Bool ?? true }
    func guardar(abrirAlIniciar: Bool) { d.set(abrirAlIniciar, forKey: "abrirAlIniciar") }
    /// Volumen y brillo en la isla en vez del cuadro de macOS.
    var niveles: Bool { d.object(forKey: "niveles") as? Bool ?? true }
    func guardar(niveles: Bool) { d.set(niveles, forKey: "niveles") }
    /// Carpeta de las ideas dictadas con ⌥⇧Espacio (una nota markdown por idea).
    var carpetaInbox: URL {
        URL(fileURLWithPath: d.string(forKey: "inbox") ?? NSHomeDirectory() + "/Documents/Ideas")
    }

    /// Vuelve a la isla abierta de antes (600 × 200, Agentes/Agenda/Notas/Mac) en vez de las cinco pestañas de Aurora.
    static var islaClasica: Bool { UserDefaults.dictado.bool(forKey: "isla.clasica") }
    /// Las apps fijadas al principio de Inicio (y del Dock), por identificador de paquete: `defaults write app.dictado isla.fijas -array com.spotify.client`.
    /// Por omisión, Spotify. Las que no estén instaladas se saltan.
    static var fijasDeLaIsla: [String] { UserDefaults.dictado.stringArray(forKey: "isla.fijas") ?? MasUsadas.fijasPorOmision }
    /// Identificadores de las apps que el dueño fijó para la pestaña Inicio (vacío: las seis más usadas).
    static var appsDeLaIsla: [String] { UserDefaults.dictado.stringArray(forKey: "isla.apps") ?? [] }

    /// Los atajos de Apple que el dueño eligió para Inicio, por nombre y en su orden (nil: los seis primeros de la app Atajos).
    static var atajosDeLaIsla: [String]? { UserDefaults.dictado.stringArray(forKey: "isla.atajos") }
    /// El espacio de Inicio que quedó activo (nil: ninguno).
    static var espacioDeLaIsla: String? {
        get { UserDefaults.dictado.string(forKey: "isla.espacio") }
        set { UserDefaults.dictado.set(newValue, forKey: "isla.espacio") }
    }

    /// Horario laboral, largo mínimo y horizonte de los huecos libres de la agenda.
    var huecos: ConfigHuecos {
        let base = ConfigHuecos.porOmision
        func entero(_ clave: String, _ omision: Int, _ rango: ClosedRange<Int>) -> Int {
            guard d.object(forKey: clave) != nil else { return omision }
            return min(max(d.integer(forKey: clave), rango.lowerBound), rango.upperBound)
        }
        let dias = (d.array(forKey: "agenda.dias") as? [Int]).map { Set($0.filter { (1...7).contains($0) }) } ?? base.dias
        return ConfigHuecos(inicioMin: entero("agenda.horaInicio", 8, 0...23) * 60, finMin: entero("agenda.horaFin", 18, 1...24) * 60,
                            dias: dias, minimoMin: entero("agenda.huecoMinimo", base.minimoMin, 5...480),
                            diasHorizonte: entero("agenda.huecoDias", base.diasHorizonte, 1...14))
    }

    /// Carpetas que la limpieza nunca propone tocar (además de iCloud y los contenedores de apps).
    static var carpetasProtegidas: [String] {
        UserDefaults.dictado.stringArray(forKey: "protegidas") ?? []
    }

    static var archivoVocabulario: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dictado/vocabulario.txt")
    }

    static var carpetaPortapapeles: URL {
        archivoVocabulario.deletingLastPathComponent().appendingPathComponent("Portapapeles")
    }

    static var archivoCorrecciones: URL {
        archivoVocabulario.deletingLastPathComponent().appendingPathComponent("correcciones.txt")
    }

    /// Términos que el modelo debe preferir (nombres propios, jerga de tu oficio). Una línea por término.
    /// Solo el motor `dictation` los aprovecha; `speech` los ignora (de ahí las correcciones).
    func vocabulario() -> [String] {
        Self.lineas(Self.archivoVocabulario, inicial: Self.vocabularioInicial)
    }

    /// Reemplazos aplicados al texto final: "lo que transcribe = lo correcto".
    func correcciones() -> [(String, String)] {
        Self.lineas(Self.archivoCorrecciones, inicial: Self.correccionesIniciales).compactMap { linea in
            let partes = linea.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            guard partes.count == 2, !partes[0].isEmpty else { return nil }
            return (partes[0], partes[1])
        }
    }

    private static func lineas(_ url: URL, inicial: String) -> [String] {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? inicial.write(to: url, atomically: true, encoding: .utf8)
        }
        let texto = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return texto.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static let correccionesIniciales = """
    # Correcciones de Dictado: "lo que transcribe = lo correcto", una por línea.
    # No distingue mayúsculas y solo reemplaza palabras completas. Se aplica en el siguiente dictado.
    # Ejemplos (borra el # para activarlos):
    # Mac Book = MacBook
    # chat GPT = ChatGPT
    """

    private static let vocabularioInicial = """
    # Vocabulario de Dictado: una palabra o frase por línea. Las líneas con # se ignoran.
    # Pon aquí nombres propios, empresas, clientes y términos de tu oficio.
    # Se aplica desde el siguiente dictado tras reiniciar la app.
    Claude
    MacBook
    WhatsApp
    Google Meet
    """
}
