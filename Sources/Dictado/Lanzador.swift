import AppKit
import DictadoKit
import Observation
import SwiftUI

/// El lanzador de Aurora: una pantalla completa con tus apps (las mismas fuentes que Inicio: fijadas, carpetas de `carpetas.txt` y
/// más usadas), un buscador que también calcula y corre tus atajos de Apple, los espacios de `espacios.txt` y las piezas de la isla
/// (Fecha, Música, la próxima reunión y los agentes con el Tablero del centro). Hyper + L lo abre y lo cierra; Esc (o un clic en un
/// espacio vacío, o irte a otra app) también. Se crea al abrirlo y se suelta al cerrarlo: cerrado no ocupa memoria de ventana ni
/// corre nada (solo vigila las carpetas de apps con FSEvents).
///
/// La primera pantalla es la tuya: las apps fijadas (`isla.fijas`), tus carpetas (`carpetas.txt`) y las más usadas, hasta lo que cabe;
/// el resto vive en el segmento "Todas" y en la búsqueda. Detrás va el fondo de pantalla del Mac (`LanzadorFondo.swift`) con el velo de la
/// maqueta; el tema sale de su luminancia salvo que fuerces uno. Se abre con Hyper + L, con la esquina activa (`LanzadorEsquina.swift`),
/// con la pieza del Dock o desde el menú. Con el Dock propio encendido, la barra queda a la vista debajo.
///
/// Ajustes (defaults write app.dictado …):
///   lanzador.tema     automatico | oscuro | claro | sistema   (automatico por omisión: según el fondo)
///   lanzador.fondo    mac | paleta:<nombre> | imagen:<ruta>    (global; un espacio lo cambia con la línea `fondo:` de espacios.txt)
///   lanzador.paleta   lagunaDurazno | medianocheOro | ciruelaCoral | bosqueLima | tintaLavanda | terracota
///   lanzador.esquina  ninguna | inferiorDerecha | inferiorIzquierda | superiorDerecha | superiorIzquierda
///   lanzador.ocultas  -array "com.ejemplo.App" …     (clic derecho → Ocultar; para volver a verlas, "Mostrar apps ocultas" en el selector de fondo)
///   isla.fijas        -array com.spotify.client …     (clic derecho → Fijar / Quitar de fijas)

/// Las dos listas del lanzador: lo tuyo (fijadas, carpetas y más usadas, en una sola pantalla) o todas las apps, por nombre.
enum SegmentoLanzador { case misApps, todas }

@MainActor @Observable
final class EstadoLanzador {
    static let claveTema = "lanzador.tema"
    static let clavePaleta = "lanzador.paleta"
    static let claveOcultas = "lanzador.ocultas"
    static let claveFondo = "lanzador.fondo"

    var consulta = ""
    /// Índice en los resultados (nil = ninguna elegida todavía).
    var seleccion: Int?
    /// La fila de la cuenta (si la consulta es aritmética) es la elegida.
    var enCalculo = false
    var pagina = 0
    var segmento = SegmentoLanzador.misApps
    var paleta: AuroraPaleta
    var ocultas: Set<String>
    /// El fondo de escritorio (pieza compartida con el Centro): la elección, la preferencia de tema y la imagen ya leída.
    let escritorio: FondoEscritorio
    var preferencia: PreferenciaTema { get { escritorio.preferencia } set { escritorio.preferencia = newValue } }
    /// El fondo global (texto de `lanzador.fondo`); nil = el fondo del Mac.
    var fondoGlobal: String? { get { escritorio.fondoGlobal } set { escritorio.fondoGlobal = newValue } }
    /// El fondo ya leído (la imagen del Mac o la que elegiste) y su luminancia.
    var fondoModelo: FondoEscritorioModelo { escritorio.modelo }
    /// La pantalla donde está abierto (nil en los renders, que traen su imagen).
    var pantalla: NSScreen? { get { escritorio.pantalla } set { escritorio.pantalla = newValue } }
    /// Cuánto se deja libre abajo: el Dock propio a la vista, o un poco de aire.
    var reservaInferior = AuroraLanzador.margenInferior
    /// El selector del fondo (el botón de la foto) está abierto.
    var selectorAbierto = false
    /// En el selector: ¿el fondo elegido vale solo para el espacio activo?
    var ambitoEspacio = false
    /// Si el Mac está en oscuro al abrir (para la preferencia "sistema").
    var sistemaOscuro: Bool { get { escritorio.sistemaOscuro } set { escritorio.sistemaOscuro = newValue } }
    var catalogo: CatalogoApps
    /// Lo que leen los widgets, las carpetas y los atajos: lo pone la ventana al abrir y lo quita al cerrar.
    var datos: DatosLanzador?
    /// La carpeta abierta en el sitio (de `carpetas.txt`); nil = la pantalla principal.
    var carpetaAbierta: String?
    /// Se está cerrando: la vista se desvanece (el fundido lo hace SwiftUI, no un animador de la ventana).
    var saliendo = false

    init(catalogo: CatalogoApps, defaults: UserDefaults = .dictado) {
        self.catalogo = catalogo
        escritorio = FondoEscritorio(defaults: defaults)
        paleta = AuroraPaleta(rawValue: defaults.string(forKey: Self.clavePaleta) ?? "") ?? .lagunaDurazno
        ocultas = Set(defaults.stringArray(forKey: Self.claveOcultas) ?? [])
    }

    /// El fondo que vale: el del espacio activo, si tiene uno; si no, el global; si no, el fondo del Mac.
    var fondo: FondoLanzador { escritorio.fondo(espacio: datos?.lanzador.espacio?.fondo) }

    /// Con el tema en automático, la luminancia del fondo decide (las paletas propias son oscuras; sin imagen todavía, oscuro).
    var tema: AuroraTema { escritorio.tema(espacio: datos?.lanzador.espacio?.fondo) }

    /// Lee (en otro hilo) el fondo que vale para esta pantalla. Se llama al abrir y cada vez que cambia el fondo.
    func sincronizarFondo() { escritorio.sincronizar(espacio: datos?.lanzador.espacio?.fondo) }

    /// La cuenta resuelta ("1.234" si escribiste 1000+234), o nil si no es una cuenta.
    var calculo: String? { Aritmetica.resultado(consulta) }

    /// Lo que se ve en la rejilla. Sin consulta, en "Mis apps": las fijadas, tus carpetas y las más usadas, hasta lo que cabe en una
    /// pantalla (el espacio activo puede adelantar lo suyo); en "Todas": todas por nombre, en páginas. Con consulta: las apps que
    /// coinciden y, después, los atajos cuyo nombre coincide (solo se corren con Return o un clic). Siempre sin las ocultas.
    var elementos: [MosaicoInicio] {
        guard let datos else { return [] }
        let visibles = BusquedaApps.sinOcultas(catalogo.apps, ocultas: ocultas)
        if !consulta.trimmingCharacters(in: .whitespaces).isEmpty {
            return BusquedaApps.filtrar(visibles, consulta: consulta).map(MosaicoInicio.app)
                + BusquedaApps.filtrarNombres(datos.lanzador.todosLosAtajos, consulta: consulta).map(MosaicoInicio.atajo)
        }
        if carpetaAbierta == nil, segmento == .todas { return visibles.map(MosaicoInicio.app) }
        let usadas = datos.apps.usadas.isEmpty ? datos.apps.apps : datos.apps.usadas
        let lista = LanzadorIsla.mosaicosDeApps(carpetas: datos.lanzador.carpetas, catalogo: visibles, masUsadas: usadas,
                                                espacio: datos.lanzador.espacio, carpetaAbierta: carpetaAbierta)
        return carpetaAbierta == nil ? Array(lista.prefix(RejillaLanzador(total: 0, conWidgets: true).porPagina)) : lista
    }

    /// Los widgets (y el clima) se ven en "Mis apps" y dentro de una carpeta; "Todas" y la búsqueda usan toda la pantalla.
    var conWidgets: Bool { consulta.isEmpty && (segmento == .misApps || carpetaAbierta != nil) }

    var rejilla: RejillaLanzador { RejillaLanzador(total: elementos.count, conWidgets: conWidgets) }

    func elegirSegmento(_ s: SegmentoLanzador) {
        guard s != segmento || carpetaAbierta != nil else { return }
        segmento = s
        carpetaAbierta = nil
        pagina = 0
        seleccion = nil
    }

    func abrirCarpeta(_ nombre: String) {
        carpetaAbierta = nombre
        pagina = 0
        seleccion = nil
    }

    func cerrarCarpeta() {
        carpetaAbierta = nil
        pagina = 0
        seleccion = nil
    }

    func reiniciar() {
        consulta = ""
        seleccion = nil
        enCalculo = false
        pagina = 0
        carpetaAbierta = nil
        segmento = .misApps
        selectorAbierto = false
        ambitoEspacio = false
        saliendo = false
        sistemaOscuro = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua
    }

    /// Cambió lo escrito: la selección vuelve al principio (la cuenta, si la hay; si no, el primer resultado).
    func consultaCambio() {
        pagina = 0
        if consulta.trimmingCharacters(in: .whitespaces).isEmpty {
            seleccion = nil
            enCalculo = false
        } else if calculo != nil {
            enCalculo = true
            seleccion = nil
        } else {
            enCalculo = false
            seleccion = elementos.isEmpty ? nil : 0
        }
    }

    func mover(_ direccion: DireccionRejilla) {
        let total = elementos.count
        if enCalculo {
            if (direccion == .abajo || direccion == .derecha), total > 0 {
                enCalculo = false
                seleccion = 0
            }
            return
        }
        guard total > 0 else { return }
        guard let actual = seleccion else { seleccion = 0; return }
        let rej = rejilla
        if direccion == .arriba, rej.celda(de: actual).fila == 0, calculo != nil {
            enCalculo = true
            seleccion = nil
            return
        }
        let nueva = rej.mover(desde: actual, direccion)
        seleccion = nueva
        pagina = rej.pagina(de: nueva)
    }

    func cambiarPagina(_ delta: Int) {
        let rej = rejilla
        let nueva = min(max(pagina + delta, 0), rej.paginas - 1)
        guard nueva != pagina else { return }
        pagina = nueva
        if seleccion != nil { seleccion = rej.rango(pagina: nueva).lowerBound }
    }

    func alternarTema(defaults: UserDefaults = .dictado) {
        elegirTema(preferencia.siguiente, defaults: defaults)
    }

    func elegirTema(_ p: PreferenciaTema, defaults: UserDefaults = .dictado) {
        preferencia = p
        defaults.set(p.rawValue, forKey: Self.claveTema)
    }

    /// Elige el fondo: para el espacio activo (su línea `fondo:` en espacios.txt) o para todos (el ajuste global; así, además, el espacio
    /// activo deja de llevar el suyo y se ve lo que elegiste).
    func elegirFondo(_ f: FondoLanzador, defaults: UserDefaults = .dictado) {
        let espacio = datos?.lanzador.espacio
        if ambitoEspacio, let espacio {
            datos?.lanzador.fijarFondo(f, espacio: espacio.nombre)
        } else {
            fondoGlobal = f.texto
            defaults.set(f.texto, forKey: Self.claveFondo)
            if let espacio, espacio.fondo != nil { datos?.lanzador.fijarFondo(nil, espacio: espacio.nombre) }
        }
        if case .paleta(let nombre) = f, let p = AuroraPaleta(rawValue: nombre) {
            paleta = p
            defaults.set(p.rawValue, forKey: Self.clavePaleta)
        }
        sincronizarFondo()
    }

    /// Fijar o quitar de las fijas (`isla.fijas`: las mismas de Inicio y del Dock).
    func alternarFija(_ app: EntradaApp, defaults: UserDefaults = .dictado) {
        guard let id = app.bundleID else { return }
        defaults.set(MasUsadas.alternarFija(Ajustes.fijasDeLaIsla, id: id), forKey: "isla.fijas")
        pagina = 0
    }

    func esFija(_ app: EntradaApp) -> Bool { app.bundleID.map { Ajustes.fijasDeLaIsla.contains($0) } ?? false }

    func mostrarOcultas(defaults: UserDefaults = .dictado) {
        ocultas = []
        defaults.removeObject(forKey: Self.claveOcultas)
    }

    func ocultar(_ app: EntradaApp, defaults: UserDefaults = .dictado) {
        ocultas.insert(app.id)
        defaults.set(ocultas.sorted(), forKey: Self.claveOcultas)
        let total = elementos.count
        if let s = seleccion, s >= total { seleccion = total > 0 ? total - 1 : nil }
        pagina = min(pagina, rejilla.paginas - 1)
    }
}

/// Lo que el lanzador lee: la agenda, lo que suena, las sesiones de Claude y los agentes, el Tablero del centro, y lo mismo que
/// Inicio para las apps (las más usadas, las carpetas, los espacios y los atajos). Son los de la isla si está encendida.
struct DatosLanzador {
    let agenda: Agenda
    let musica: Musica
    let claude: SesionesClaude
    let agentes: AgentesRemotos
    let tablero: TableroIsla?
    let lanzador: LanzadorIsla
    let apps: AppsUsadas
    let clima: ClimaModelo
    var foco: Foco?
    var config: ConfigHuecos = Ajustes().huecos
    var ahora: () -> Date = { Date() }
}

@MainActor
final class Lanzador: NSObject, NSWindowDelegate {
    private let isla: () -> Isla?
    let catalogo: CatalogoApps
    let estado: EstadoLanzador
    private var ventana: NSWindow?
    /// La vista de SwiftUI de la ventana: se guarda para vaciarla al cerrar (ver `soltar`).
    private var anfitrion: NSHostingView<AnyView>?
    private var monitorTeclas: Any?
    private var monitorRueda: Any?
    private var observadorPantallas: NSObjectProtocol?
    private var anterior: NSRunningApplication?
    private var cerrando = false
    private var cierre: DispatchWorkItem?
    /// El selector de archivos (Elegir imagen…) es una hoja de la ventana: mientras está, perder el foco no cierra el lanzador.
    private var hojaAbierta = false
    /// Sin isla, el lanzador crea sus propios datos UNA vez y los conserva: cada `Agenda()` o `SesionesClaude()` vivos abren el
    /// almacén de Calendario, observadores, un reloj y un flujo de FSEvents que nadie cierra, así que crearlos en cada apertura
    /// dejaba uno más (con su memoria) por cada vez que se abría el lanzador.
    private var propios: DatosLanzador?
    private var acumulado: CGFloat = 0
    private var yaCambio = false
    private var ultimoCambio = Date.distantPast
    /// Si se avisó al Dock propio (para avisarle también al cerrar).
    private var dockAvisado = false

    /// Datos de otra procedencia (las pruebas): sin ellos, los de la isla o unos propios.
    private let datosDePrueba: (() -> DatosLanzador)?

    init(isla: @escaping () -> Isla?, datosDePrueba: (() -> DatosLanzador)? = nil) {
        self.isla = isla
        self.datosDePrueba = datosDePrueba
        let catalogo = CatalogoApps()
        self.catalogo = catalogo
        estado = EstadoLanzador(catalogo: catalogo)
        super.init()
        if datosDePrueba == nil {
            // Una pieza del Dock que abre otra cosa (la isla, dictar) cierra primero el lanzador.
            Dock.alAccionar = { [weak self] in self?.cerrar(devolver: false) }
        }
    }

    var abierto: Bool { ventana?.isVisible == true }

    func alternar() {
        if abierto { cerrar() } else { abrir() }
    }

    func abrir() {
        guard ventana == nil else { return }
        let pantalla = Self.pantallaDelPuntero()
        // El Dock propio sube sobre el lanzador y se queda a la vista; si hay barra en esa pantalla, se le deja su sitio.
        let hayBarra = Dock.lanzadorAbierto(en: pantalla)
        dockAvisado = true
        estado.reservaInferior = hayBarra ? AuroraLanzador.bandaDock : AuroraLanzador.margenInferior
        let v = prepararApertura(pantalla)
        if let frontal = NSWorkspace.shared.frontmostApplication, frontal != NSRunningApplication.current { anterior = frontal }
        ventana = v
        NSApp.activate(ignoringOtherApps: true)
        v.alphaValue = 1
        v.makeKeyAndOrderFront(nil)
        instalarMonitores()
    }

    /// Para la prueba de memoria: arma la ventana y toda su jerarquía de vistas igual que `abrir`, pero sin ordenarla al frente,
    /// sin activar la app, sin tocar el Dock y sin monitores. Nada llega a la pantalla.
    func abrirSinMostrar() {
        guard ventana == nil else { return }
        let v = prepararApertura(Self.pantallaDelPuntero())
        ventana = v
        // El foco del buscador, como al abrir de verdad (el campo toma el foco dentro de su ventana).
        if let c = v.contentView, let campo = Self.campoDeTexto(en: c) { v.makeFirstResponder(campo) }
    }

    /// La pantalla donde está el puntero (el lanzador se abre ahí); si no se sabe, la principal.
    static func pantallaDelPuntero() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Lo común de abrir: lo que se lee, lo que se refresca y la ventana con su contenido. Nada de esto espera a la imagen del fondo:
    /// se lee en otro hilo y entra con un fundido.
    private func prepararApertura(_ pantalla: NSScreen?) -> NSWindow {
        estado.reiniciar()
        estado.pantalla = pantalla
        catalogo.alAbrir()
        let datos = datosVivos()
        estado.datos = datos
        estado.sincronizarFondo()
        datos.agenda.refrescar()
        datos.lanzador.alAbrir()      // carpetas, espacios y atajos (con tope de frecuencia)
        datos.apps.refrescar()
        datos.tablero?.refrescar()
        cerrando = false
        return crearVentana(datos, pantalla: pantalla)
    }

    private static func campoDeTexto(en vista: NSView) -> NSTextField? {
        if let c = vista as? NSTextField, c.isEditable { return c }
        for hija in vista.subviews { if let c = campoDeTexto(en: hija) { return c } }
        return nil
    }

    private func datosVivos() -> DatosLanzador {
        if let datosDePrueba { return datosDePrueba() }
        if let i = isla() {
            return DatosLanzador(agenda: i.agenda, musica: i.musica, claude: i.claude, agentes: i.agentes, tablero: i.tablero, lanzador: i.lanzador,
                                 apps: i.appsUsadas, clima: .compartido, foco: i.foco)
        }
        if let propios { return propios }
        let nuevos = DatosLanzador(agenda: Agenda(), musica: Musica(vivo: false), claude: SesionesClaude(), agentes: AgentesRemotos(vivo: false),
                                   tablero: TableroIsla(), lanzador: LanzadorIsla(), apps: AppsUsadas(), clima: .compartido)
        propios = nuevos
        return nuevos
    }

    /// Cierra: un fundido corto hecho por SwiftUI (sin animador de la ventana, que se queda con ella) y, pasado, se suelta todo.
    func cerrar(devolver: Bool = true) {
        guard let v = ventana, !cerrando else { return }
        cerrando = true
        if dockAvisado { Dock.lanzadorCerrado(); dockAvisado = false }
        let app = devolver ? anterior : nil
        estado.saliendo = true
        let tarea = DispatchWorkItem { [weak self, weak v] in
            MainActor.assumeIsolated {
                if let v { self?.soltar(v) }
                app?.activate()
            }
        }
        cierre = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + AuroraMovimiento.fundidoCierre, execute: tarea)
    }

    /// Suelta la ventana y todo lo que cuelga de ella, en orden: el foco del campo de texto (el editor de campo retiene su vista),
    /// el contenido de SwiftUI (vaciado, como el Dock: así el grafo de vistas se libera aunque AppKit tarde en soltar la ventana),
    /// la vista, el delegado y, al final, la ventana. La imagen del fondo se suelta con ella.
    private func soltar(_ v: NSWindow) {
        cierre = nil
        if let m = monitorTeclas { NSEvent.removeMonitor(m) }
        if let m = monitorRueda { NSEvent.removeMonitor(m) }
        if let o = observadorPantallas { NotificationCenter.default.removeObserver(o) }
        monitorTeclas = nil
        monitorRueda = nil
        observadorPantallas = nil
        if dockAvisado { Dock.lanzadorCerrado(); dockAvisado = false }
        catalogo.alCerrar()
        v.makeFirstResponder(nil)
        anfitrion?.rootView = AnyView(EmptyView())
        anfitrion = nil
        v.contentView = nil
        v.delegate = nil
        v.orderOut(nil)
        v.close()
        estado.fondoModelo.soltar()
        estado.pantalla = nil
        estado.datos = nil
        estado.carpetaAbierta = nil
        hojaAbierta = false
        if ventana === v { ventana = nil }
        cerrando = false
    }

    private func crearVentana(_ datos: DatosLanzador, pantalla: NSScreen?) -> NSWindow {
        let marco = pantalla?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let v = VentanaLanzador(contentRect: marco, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        v.setFrame(marco, display: false)
        v.title = "Lanzador"
        v.backgroundColor = .clear
        v.isOpaque = false
        v.hasShadow = false
        v.level = NSWindow.Level(rawValue: AuroraLanzador.nivelVentana)   // por encima de ventanas, barra de menús y Dock del sistema; el Dock propio, un nivel más
        v.isReleasedWhenClosed = false
        v.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        v.delegate = self
        let acciones = AccionesLanzador(
            cerrar: { [weak self] in self?.cerrarPasoAPaso() },
            lanzar: { [weak self] app in self?.lanzar(app) },
            copiarCalculo: { [weak self] texto in self?.copiar(texto) },
            ocultar: { [weak self] app in self?.estado.ocultar(app) },
            alternarFija: { [weak self] app in self?.estado.alternarFija(app) },
            mostrarEnFinder: { [weak self] app in
                self?.cerrar(devolver: false)
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.ruta)])
            },
            abrirCarpeta: { [weak self] nombre in self?.estado.abrirCarpeta(nombre) },
            volver: { [weak self] in self?.estado.cerrarCarpeta() },
            correrAtajo: { [weak self] nombre in self?.correrAtajo(nombre) },
            elegirEspacio: { [weak self] e in self?.elegirEspacio(e) },
            unirse: { [weak self] url in
                self?.cerrar(devolver: false)
                NSWorkspace.shared.open(url)
            },
            abrirAgentes: { [weak self] in
                self?.cerrar(devolver: false)
                self?.isla()?.abrirPestana(.agentes, en: nil)
            },
            dictar: { [weak self] in
                self?.cerrar(devolver: false)
                self?.isla()?.alDictar?()
            },
            dictarEncargo: { [weak self] in
                self?.cerrar(devolver: false)
                self?.isla()?.alDictarEncargo?()
            },
            elegirFondo: { [weak self] f in
                guard let self else { return }
                withAnimation(AuroraMovimiento.espacio) { self.estado.elegirFondo(f) }
                self.ajustarApariencia()
            },
            elegirImagen: { [weak self] in self?.elegirImagen() },
            alternarTema: { [weak self] in
                guard let self else { return }
                withAnimation(AuroraMovimiento.espacio) { self.estado.alternarTema() }
                self.ajustarApariencia()
            },
            elegirTema: { [weak self] p in
                guard let self else { return }
                withAnimation(AuroraMovimiento.espacio) { self.estado.elegirTema(p) }
                self.ajustarApariencia()
            },
            temaCambio: { [weak self] in self?.ajustarApariencia() })
        let raiz = RaizLanzador(estado: estado, catalogo: catalogo, datos: datos, acciones: acciones)
        let host = NSHostingView(rootView: AnyView(raiz))
        host.sizingOptions = []
        anfitrion = host
        v.contentView = host
        ajustarApariencia(v)
        return v
    }

    /// La ventana toma la apariencia del tema: así el campo de texto y el vidrio hablan el mismo idioma. Con el tema en automático, el tema
    /// puede cambiar cuando llega la imagen: la vista lo avisa.
    func ajustarApariencia(_ v: NSWindow? = nil) {
        (v ?? ventana)?.appearance = NSAppearance(named: estado.tema.esOscuro ? .darkAqua : .aqua)
    }

    // MARK: Acciones

    func lanzar(_ app: EntradaApp) {
        cerrar(devolver: false)
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.ruta), configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    private func elegirEspacio(_ e: EspacioIsla) {
        guard let datos = estado.datos else { return }
        datos.lanzador.elegirEspacio(e, foco: datos.foco)   // el mismo camino que Inicio y el Dock
        estado.pagina = 0
        estado.seleccion = nil
        estado.sincronizarFondo()   // el espacio puede traer su propio fondo
    }

    /// El botón de cerrar y el clic en un espacio vacío: primero el selector del fondo, si está abierto; si no, el lanzador.
    private func cerrarPasoAPaso() {
        if estado.selectorAbierto { estado.selectorAbierto = false } else { cerrar() }
    }

    /// Un atajo de Apple, con el mismo corredor que los de Inicio (`ProcesoAtajos`, con tope de tiempo y fuera del hilo principal).
    /// Solo se llama desde Return o un clic.
    private func correrAtajo(_ nombre: String) {
        cerrar(devolver: false)
        Task.detached(priority: .userInitiated) {
            _ = ProcesoAtajos.ejecutar(["run", nombre], limite: AtajosSistema.segundosLimite)
        }
    }

    private func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        cerrar()
    }

    /// "Elegir imagen…": el selector de archivos como hoja de la propia ventana (un panel suelto quedaría detrás de ella).
    private func elegirImagen() {
        guard let v = ventana, !hojaAbierta else { return }
        let panel = NSOpenPanel()
        panel.title = "Fondo del lanzador"
        panel.message = "Elige una imagen para el fondo del lanzador"
        panel.prompt = "Elegir"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        hojaAbierta = true
        panel.beginSheetModal(for: v) { [weak self] r in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hojaAbierta = false
                self.ventana?.makeKeyAndOrderFront(nil)
                guard r == .OK, let url = panel.url else { return }
                withAnimation(AuroraMovimiento.espacio) { self.estado.elegirFondo(.imagen(url.path)) }
                self.ajustarApariencia()
            }
        }
    }

    /// Return: la cuenta (se copia), o el elemento elegido: una app se abre, una carpeta se abre en el sitio y un atajo se corre.
    func confirmar() {
        if estado.enCalculo, let c = estado.calculo { copiar(c); return }
        let lista = estado.elementos
        guard let s = estado.seleccion, lista.indices.contains(s) else { return }
        switch lista[s] {
        case .app(let a): lanzar(a)
        case .carpeta(let c, _): estado.abrirCarpeta(c.nombre)
        case .atajo(let n): correrAtajo(n)
        }
    }

    // MARK: Teclado y rueda

    private func instalarMonitores() {
        if monitorTeclas == nil {
            monitorTeclas = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evento in
                let caja = CajaEvento(evento)
                let consumido = MainActor.assumeIsolated { self?.tecla(caja.evento) ?? false }
                return consumido ? nil : evento
            }
        }
        if monitorRueda == nil {
            monitorRueda = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] evento in
                let caja = CajaEvento(evento)
                let consumido = MainActor.assumeIsolated { self?.rueda(caja.evento) ?? false }
                return consumido ? nil : evento
            }
        }
        // Si cambian las pantallas (se conecta o se quita una, cambia la resolución), la ventana ya no calza: se cierra.
        if observadorPantallas == nil {
            observadorPantallas = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cerrar(devolver: false) }
            }
        }
    }

    /// true = la tecla se atendió aquí (no sigue al campo de texto).
    private func tecla(_ e: NSEvent) -> Bool {
        guard let v = ventana, v.isKeyWindow, !hojaAbierta else { return false }
        let mods = e.modifierFlags.intersection([.command, .control, .option])
        if mods == [.command] {   // ⌘1 a ⌘9: el espacio de ese número
            if let n = Self.digitos[e.keyCode], let datos = estado.datos, datos.lanzador.espacios.indices.contains(n - 1) {
                elegirEspacio(datos.lanzador.espacios[n - 1])
                return true
            }
            return false
        }
        if !mods.isEmpty { return false }
        switch e.keyCode {
        case 53: escape()                                    // esc: el selector, la búsqueda, la carpeta y, al final, el lanzador
        case 36, 76: confirmar()                            // return
        case 123: estado.mover(.izquierda)
        case 124: estado.mover(.derecha)
        case 125: estado.mover(.abajo)
        case 126: estado.mover(.arriba)
        case 116: estado.cambiarPagina(-1)                  // re pág
        case 121: estado.cambiarPagina(1)                   // av pág
        default:
            // Escribir en cualquier momento busca: si el campo perdió el foco (un clic en un espacio vacío), vuelve a tomarlo.
            if let c = e.characters?.unicodeScalars.first, c.value >= 0x20, !(0xF700...0xF8FF).contains(c.value), !(v.firstResponder is NSTextView),
               let contenido = v.contentView, let campo = Self.campoDeTexto(en: contenido) {
                if estado.selectorAbierto { estado.selectorAbierto = false }
                v.makeFirstResponder(campo)
            }
            return false
        }
        return true
    }

    private static let digitos: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    /// Esc cierra de a una cosa: el selector del fondo, la búsqueda, la carpeta abierta y, al final, el lanzador.
    private func escape() {
        if estado.selectorAbierto { estado.selectorAbierto = false }
        else if !estado.consulta.isEmpty { estado.consulta = ""; estado.consultaCambio() }
        else if estado.carpetaAbierta != nil { estado.cerrarCarpeta() }
        else { cerrar() }
    }

    /// Dos dedos de lado (o la rueda) pasan de página; un gesto cambia una sola.
    private func rueda(_ e: NSEvent) -> Bool {
        guard let v = ventana, v.isKeyWindow else { return false }
        let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? e.scrollingDeltaX : e.scrollingDeltaY
        if e.phase == .began || e.phase == .mayBegin { acumulado = 0; yaCambio = false }
        if e.phase == [] && e.momentumPhase == [] {   // rueda de mouse: sin fases
            guard Date().timeIntervalSince(ultimoCambio) > 0.35, abs(d) > 0.5 else { return true }
            ultimoCambio = Date()
            estado.cambiarPagina(d < 0 ? 1 : -1)
            return true
        }
        if e.phase == .ended || e.momentumPhase == .ended { acumulado = 0; yaCambio = false; return true }
        guard !yaCambio else { return true }
        acumulado += d
        if abs(acumulado) > 40 {
            estado.cambiarPagina(acumulado < 0 ? 1 : -1)
            yaCambio = true
        }
        return true
    }

    // MARK: Ventana

    /// Te fuiste a otra app: el lanzador se cierra (sin devolverte a la anterior). El selector de archivos (una hoja) no cuenta.
    func windowDidResignKey(_ notification: Notification) {
        guard !hojaAbierta else { return }
        cerrar(devolver: false)
    }

    /// La ventana se cerró por otro camino (no por `cerrar`): también se suelta con toda su jerarquía.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let v = self.ventana else { return }
            self.soltar(v)
        }
    }

    /// Para las pruebas: ¿sigue viva la ventana?
    var ventanaViva: Bool { ventana != nil }
    var primerRespondedor: NSResponder? { ventana?.firstResponder }
    var vistaDelContenido: NSView? { ventana?.contentView }
    var ventanaActual: NSWindow? { ventana }
}

/// Una ventana sin marco que igual recibe el teclado.
private final class VentanaLanzador: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Un evento de teclado o rueda que cruza a MainActor: el monitor local ya corre en el hilo principal.
private struct CajaEvento: @unchecked Sendable {
    let evento: NSEvent
    init(_ evento: NSEvent) { self.evento = evento }
}
