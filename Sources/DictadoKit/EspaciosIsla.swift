import Foundation

/// Qué hace un espacio con algo que ya existe en la app (el velo, las teclas).
public enum AjusteEspacio: Equatable, Sendable {
    /// El espacio no dice nada: se deja como está.
    case sinCambio
    case apagado
    /// Encendido; con un modo (velo) o un perfil (teclas) si el archivo lo nombra.
    case encendido(String?)
}

/// Un espacio de Inicio (Trabajo, Foco, Mañana, Descanso): qué va primero y qué ajustes de la app toma al activarlo.
public struct EspacioIsla: Equatable, Sendable {
    public var nombre: String
    /// Nombres de apps, carpetas o atajos que Inicio muestra primero, en este orden.
    public var primero: [String]
    public var velo: AjusteEspacio
    public var teclas: AjusteEspacio
    /// Minutos de un bloque de foco que empieza al entrar (nil: ninguno).
    public var foco: Int?
    /// Nombre de un atajo de Apple que se corre al entrar (así se engancha un modo de concentración del sistema).
    public var atajo: String?
    /// La línea `dock:` tal cual (las piezas del Dock en este espacio); nil: las de siempre (`ReglasDock.porOmision`).
    public var dock: String?
    /// La línea `fondo:` tal cual (el fondo en este espacio: `mac`, `paleta:<nombre>`, `imagen:<ruta>`, un fondo de macOS por nombre o `aereo:<nombre>`); nil: el global.
    public var fondo: String?
    /// La paleta Aurora del espacio (`paleta:`): tiñe el Dock, el lanzador y el indicador del espacio. nil: la de siempre.
    public var paleta: String?
    /// Apps que se abren al entrar (`abrir:`), por nombre, sin quitarte el foco.
    public var abrir: [String]
    /// Una app a la que se le manda "reproducir" al entrar (`reproducir:`; hoy Spotify o Música).
    public var reproducir: String?
    /// Una frase corta que dice para qué es el espacio (`titulo:`); sale en la ayuda del chip y del selector.
    public var titulo: String?

    public init(nombre: String, primero: [String] = [], velo: AjusteEspacio = .sinCambio, teclas: AjusteEspacio = .sinCambio,
                foco: Int? = nil, atajo: String? = nil, dock: String? = nil, fondo: String? = nil,
                paleta: String? = nil, abrir: [String] = [], reproducir: String? = nil, titulo: String? = nil) {
        self.nombre = nombre
        self.primero = primero
        self.velo = velo
        self.teclas = teclas
        self.foco = foco
        self.atajo = atajo
        self.dock = dock
        self.fondo = fondo
        self.paleta = paleta
        self.abrir = abrir
        self.reproducir = reproducir
        self.titulo = titulo
    }

    /// Las piezas del Dock de este espacio: las de la línea `dock:` o, sin ella, las de siempre con estas apps.
    public func piezasDock(masUsadas: [String], home: String = NSHomeDirectory()) -> [PiezaDock] {
        guard let dock, !dock.trimmingCharacters(in: .whitespaces).isEmpty else { return ReglasDock.porOmision(masUsadas: masUsadas, home: home) }
        let piezas = ReglasDock.analizar(dock, home: home)
        return piezas.isEmpty ? ReglasDock.porOmision(masUsadas: masUsadas, home: home) : piezas
    }
}

public enum EspaciosIsla {
    /// Las paletas Aurora que acepta `paleta:` (los nombres de `AuroraPaleta` en la app).
    public static let paletasConocidas = ["lagunaDurazno", "medianocheOro", "ciruelaCoral", "bosqueLima", "tintaLavanda", "terracota"]
    public static let minutosFocoMinimo = 5
    public static let minutosFocoMaximo = 120

    /// Lee `espacios.txt`:
    ///   [Foco]
    ///   primero: Notas, Trabajo        (apps, carpetas o atajos que van primero en Inicio)
    ///   velo: ambiente | profundo | sí | no     (sin la línea: no se toca)
    ///   teclas: thock | sí | no                 (sin la línea: no se toca)
    ///   foco: 25                                (minutos de un bloque de foco al entrar)
    ///   al entrar: Modo concentración           (un atajo de Apple que se corre al entrar)
    ///   dock: reloj, agenda, | Claude, Arc, | carpeta:~/Downloads, papelera   (las piezas del Dock en este espacio)
    ///   fondo: mac | paleta:lagunaDurazno | imagen:~/Pictures/fondo.jpg | Sonoma | aereo:Patagonia   (el fondo en este espacio)
    public static func leer(_ texto: String) -> [EspacioIsla] {
        var espacios: [EspacioIsla] = []
        for cruda in texto.split(separator: "\n", omittingEmptySubsequences: false) {
            let linea = cruda.trimmingCharacters(in: .whitespaces)
            if linea.isEmpty || linea.hasPrefix("#") { continue }
            if linea.hasPrefix("["), linea.hasSuffix("]") {
                let nombre = String(linea.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if !nombre.isEmpty { espacios.append(EspacioIsla(nombre: nombre)) }
                continue
            }
            guard !espacios.isEmpty, let dos = linea.firstIndex(of: ":") else { continue }
            let clave = BusquedaApps.normalizar(String(linea[..<dos])).replacingOccurrences(of: " ", with: "")
            let valor = linea[linea.index(after: dos)...].trimmingCharacters(in: .whitespaces)
            let i = espacios.count - 1
            switch clave {
            case "primero", "apps", "inicio":
                espacios[i].primero += valor.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            case "velo": espacios[i].velo = ajuste(valor)
            case "teclas": espacios[i].teclas = ajuste(valor)
            case "foco":
                espacios[i].foco = Int(valor).map { min(max($0, minutosFocoMinimo), minutosFocoMaximo) }
            case "dock":
                espacios[i].dock = valor.isEmpty ? nil : valor
            case "fondo":
                espacios[i].fondo = FondoLanzador(texto: valor) == nil ? nil : valor
            case "paleta":
                espacios[i].paleta = EspaciosIsla.paletasConocidas.first { BusquedaApps.normalizar($0) == BusquedaApps.normalizar(valor) }
            case "abrir":
                espacios[i].abrir += valor.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            case "reproducir":
                espacios[i].reproducir = valor.isEmpty || ["no", "ninguno"].contains(BusquedaApps.normalizar(valor)) ? nil : valor
            case "titulo", "lema":
                espacios[i].titulo = valor.isEmpty ? nil : valor
            case "alentrar", "atajo":
                espacios[i].atajo = valor.isEmpty || ["no", "ninguno"].contains(BusquedaApps.normalizar(valor)) ? nil : valor
            default: break
            }
        }
        return espacios
    }

    private static func ajuste(_ valor: String) -> AjusteEspacio {
        let v = BusquedaApps.normalizar(valor)
        if v.isEmpty { return .sinCambio }
        if ["no", "apagado", "off", "false", "0", "nunca"].contains(v) { return .apagado }
        if ["si", "on", "encendido", "true", "1"].contains(v) { return .encendido(nil) }
        return .encendido(v)
    }

    /// El encabezado de `espacios.txt`: qué líneas entiende cada espacio.
    public static let encabezado = """
    # Espacios de Dictado: un solo concepto para el Dock, el lanzador y Inicio. Cambiar de espacio cambia el fondo de pantalla, el Dock,
    # el orden de las apps y los ajustes. Cada uno empieza con [Nombre] y sigue con estas líneas (todas opcionales):
    #   titulo: una frase corta que dice para qué es el espacio (sale en la ayuda del chip y del selector).
    #   fondo: el fondo de pantalla al entrar. Se recuerda el anterior y se devuelve al quitar el espacio. También es el fondo del lanzador
    #          y del Centro. Puede ser: una imagen (/ruta/foto.heic o imagen:/ruta); un fondo de macOS por nombre (fondo: Pro Black,
    #          fondo: The Cliffs; el que esté en el Mac); un aéreo animado (fondo: aereo:Patagonia, por nombre o identificador; también vale
    #          aereo:nevadas): en el lanzador y el Centro se mueve y en el escritorio queda un cuadro fijo del mismo aéreo. mac (sin cambiar
    #          nada) o paleta:lagunaDurazno solo cambian el lanzador. Si el fondo pedido no está en el Mac, el escritorio no cambia.
    #          Los fondos de macOS y los aéreos que no estén en el Mac se bajan una vez en Ajustes del Sistema → Fondo de pantalla (los
    #          aéreos, también en Salvapantallas).
    #   paleta: lagunaDurazno | medianocheOro | ciruelaCoral | bosqueLima | tintaLavanda | terracota. Tiñe el Dock, el lanzador y el
    #           indicador del espacio. Sin la línea, el Dock toma los tonos del fondo de pantalla.
    #   dock: las piezas del Dock en este espacio, en orden y separadas por coma; "|" deja un hueco pequeño. Piezas: reloj, agenda,
    #         agentes, plan, tareas, dictar, foco, musica, mac, bateria, fecha, clima, lanzador, abiertas, finder, papelera; una app por
    #         nombre o identificador (Claude, com.apple.Safari; el identificador sirve en cualquier idioma del sistema); grupo:Trabajo (una carpeta de carpetas.txt); carpeta:~/Downloads.
    #         Sin la línea, el Dock lleva lo de siempre.
    #   primero: apps, carpetas o atajos (por nombre) que el lanzador y Inicio muestran primero, en ese orden.
    #   velo: ambiente | profundo | sí | no   (sin la línea, no se toca)
    #   teclas: thock | clack | crema | burbuja | sí | no   (sin la línea, no se toca)
    #   foco: minutos de un bloque de foco que empieza al entrar (5 a 120).
    #   abrir: apps que se abren al entrar, por nombre, sin quitarte lo que estás haciendo.
    #   reproducir: spotify | música. Le manda "reproducir" a esa app al entrar (macOS pide el permiso de Automatización la primera vez).
    #   al entrar: nombre de un atajo de Apple que se corre al entrar (por ejemplo, para un modo de concentración del sistema).
    # Las acciones corren solo cuando tú eliges el espacio (un clic, Hyper + número o Hyper + [ ]), nunca solas.
    # El espacio actual se recuerda. Los cambios valen la próxima vez que abras la isla o el Dock.
    """

    /// El archivo de la primera vez: cuatro espacios prudentes. El velo y los sonidos quedan apagados salvo en Foco
    /// (velo ambiente y un bloque de 25 minutos). Nada de esto borra ni cambia archivos: solo ajustes de la app.
    public static let inicial = encabezado + """


    [Trabajo]
    primero: Trabajo, Desarrollo
    velo: no
    teclas: no

    [Foco]
    primero: Notas, Recordatorios
    velo: ambiente
    teclas: no
    foco: 25

    [Mañana]
    primero: Calendario, Mail, Comunicación
    velo: no
    teclas: no

    [Descanso]
    primero: Spotify, Juegos
    velo: no
    teclas: no
    """
}
