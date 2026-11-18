import Foundation

// Las ventanas flotantes por app del Dock: cuando una app está abierta y el puntero se queda sobre su icono, sale un panel con sus
// ventanas. Para los navegadores que se pueden controlar con AppleScript (Cra, Chrome y compañía, Safari), también las pestañas de
// cada ventana. Aquí solo hay lo puro (los guiones y su lectura); lo que toca la pantalla vive en la app.

/// Una pestaña de un navegador.
public struct PestanaApp: Equatable, Sendable, Identifiable {
    /// Lo que el navegador entiende para saltar a ella (su id en Cra; su número en Chrome y Safari).
    public var id: String
    public var titulo: String
    public var indice: Int
    public var activa: Bool
    /// La dirección de la página, si el guion la pidió (el selector de apps; el Dock no la usa).
    public var url: String

    public init(id: String, titulo: String, indice: Int, activa: Bool, url: String = "") {
        self.id = id
        self.titulo = titulo
        self.indice = indice
        self.activa = activa
        self.url = url
    }
}

/// Una ventana de un navegador con sus pestañas.
public struct VentanaNavegador: Equatable, Sendable {
    /// Posición de la ventana, de adelante hacia atrás (1 = la de adelante).
    public var indice: Int
    public var id: String
    public var titulo: String
    public var pestanas: [PestanaApp]

    public init(indice: Int, id: String, titulo: String, pestanas: [PestanaApp]) {
        self.indice = indice
        self.id = id
        self.titulo = titulo
        self.pestanas = pestanas
    }
}

public enum FamiliaNavegador: Equatable, Sendable {
    /// Cra (dk.kildahl.cra): su diccionario de AppleScript trae ventanas, pestañas con id y el comando `select`.
    case cra
    /// Chrome, Brave, Edge, Arc, Vivaldi y Opera: ventanas con pestañas numeradas y `active tab index`.
    case chromium
    case safari
}

public enum NavegadoresDock {
    public static let separadorRegistro = "\u{1E}"
    public static let separadorCampo = "\u{1F}"

    public static func familia(bundleID: String?) -> FamiliaNavegador? {
        switch bundleID {
        case "dk.kildahl.cra": return .cra
        case "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.brave.Browser", "com.microsoft.edgemac",
             "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera": return .chromium
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview": return .safari
        default: return nil
        }
    }

    /// Escapa un texto para ponerlo entre comillas dentro de un guion.
    static func comillas(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// El guion que lista ventanas y pestañas. Devuelve un texto con un registro por pestaña:
    /// ventana (número, id, título) y pestaña (número, id, título, activa), campos y registros separados por caracteres de control.
    public static func guionListar(bundleID: String, familia: FamiliaNavegador, conURL: Bool = false) -> String {
        let id: String, titulo: String, activa: String, previo: String
        switch familia {
        case .cra:
            id = "(id of t as text)"; titulo = "(title of t)"
            previo = "set act to \"\"\n      try\n        set act to (id of (active tab of w)) as text\n      end try"
            activa = "((id of t as text) = act)"
        case .chromium:
            id = "(ti as text)"; titulo = "(title of t)"
            previo = "set act to 0\n      try\n        set act to active tab index of w\n      end try"
            activa = "(ti = act)"
        case .safari:
            id = "(ti as text)"; titulo = "(name of t)"
            previo = "set act to 0\n      try\n        set act to index of (current tab of w)\n      end try"
            activa = "(ti = act)"
        }
        let direccion = conURL ? "\n              set uu to \"\"\n              try\n                set uu to (URL of t) as text\n              end try" : ""
        let campoURL = conURL ? " & us & uu" : ""
        return """
        tell application id \(comillas(bundleID))
          set rs to character id 30
          set us to character id 31
          set salida to ""
          set wi to 0
          repeat with w in windows
            set wi to wi + 1
            set wid to ""
            try
              set wid to (id of w) as text
            end try
            set wn to ""
            try
              set wn to name of w
            end try
            \(previo)
            set ti to 0
            repeat with t in tabs of w
              set ti to ti + 1
              set tt to ""
              try
                set tt to \(titulo)
              end try\(direccion)
              set salida to salida & wi & us & wid & us & wn & us & ti & us & \(id) & us & tt & us & \(activa)\(campoURL) & rs
            end repeat
          end repeat
          return salida
        end tell
        """
    }

    /// El guion que lleva a una pestaña: la selecciona, sube su ventana y activa la app.
    public static func guionSaltar(bundleID: String, familia: FamiliaNavegador, ventana: VentanaNavegador, pestana: PestanaApp) -> String {
        let app = comillas(bundleID)
        switch familia {
        case .cra:
            return """
            tell application id \(app)
              activate
              select (first tab of (first window whose id is \(comillas(ventana.id))) whose id is \(comillas(pestana.id)))
            end tell
            """
        case .chromium:
            return """
            tell application id \(app)
              activate
              set active tab index of window \(ventana.indice) to \(pestana.indice)
              set index of window \(ventana.indice) to 1
            end tell
            """
        case .safari:
            return """
            tell application id \(app)
              activate
              set current tab of window \(ventana.indice) to tab \(pestana.indice) of window \(ventana.indice)
              set index of window \(ventana.indice) to 1
            end tell
            """
        }
    }

    /// Lee lo que devolvió `guionListar` y lo agrupa por ventana. Los registros mal formados se ignoran.
    public static func leer(_ texto: String) -> [VentanaNavegador] {
        var ventanas: [VentanaNavegador] = []
        for registro in texto.components(separatedBy: separadorRegistro) where !registro.isEmpty {
            let c = registro.components(separatedBy: separadorCampo)
            guard c.count >= 7, let wi = Int(c[0]), let ti = Int(c[3]) else { continue }
            let pestana = PestanaApp(id: c[4], titulo: c[5], indice: ti, activa: c[6] == "true", url: c.count > 7 ? c[7] : "")
            if let k = ventanas.firstIndex(where: { $0.indice == wi }) {
                ventanas[k].pestanas.append(pestana)
            } else {
                ventanas.append(VentanaNavegador(indice: wi, id: c[1], titulo: c[2], pestanas: [pestana]))
            }
        }
        return ventanas
    }

    /// La ventana de AppleScript que corresponde a una ventana del sistema: por título y, si no, por posición.
    public static func emparejar(titulo: String, posicion: Int, entre ventanas: [VentanaNavegador]) -> VentanaNavegador? {
        if !titulo.isEmpty, let v = ventanas.first(where: { $0.titulo == titulo || (!$0.titulo.isEmpty && titulo.hasPrefix($0.titulo)) }) { return v }
        return ventanas.first { $0.indice == posicion + 1 }
    }
}

/// Lo que dice el panel de ventanas y cuánto mide: dos líneas de texto fijas y el reparto del alto.
public enum PanelVentanasDock {
    public static let avisoMiniaturas = "Activa Grabación de pantalla para ver miniaturas"
    public static let avisoAccesibilidad = "Activa Accesibilidad para listar las ventanas"
    public static let sinVentanas = "Sin ventanas abiertas"
    /// Cuántas pestañas se ven sin desplazarse en el panel.
    public static let pestanasVisibles = 8
    /// Cuánto espera el puntero sobre una app abierta antes de que salga el panel (segundos).
    public static let espera = 0.6

    /// El título que se muestra: sin saltos de línea y recortado.
    public static func titulo(_ s: String, maximo: Int = 46) -> String {
        let limpio = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if limpio.isEmpty { return "Sin título" }
        return limpio.count > maximo ? String(limpio.prefix(maximo - 1)) + "…" : limpio
    }
}
