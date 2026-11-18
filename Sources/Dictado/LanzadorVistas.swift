import AppKit
import DictadoKit
import SwiftUI

/// Lo que las vistas del lanzador piden hacer (la ventana lo ejecuta).
struct AccionesLanzador {
    var cerrar: () -> Void = {}
    var lanzar: (EntradaApp) -> Void = { _ in }
    var copiarCalculo: (String) -> Void = { _ in }
    var ocultar: (EntradaApp) -> Void = { _ in }
    var alternarFija: (EntradaApp) -> Void = { _ in }
    var mostrarEnFinder: (EntradaApp) -> Void = { _ in }
    var abrirCarpeta: (String) -> Void = { _ in }
    var volver: () -> Void = {}
    /// Solo se llama desde un clic en el resultado (o Return): buscar no corre nada.
    var correrAtajo: (String) -> Void = { _ in }
    var elegirEspacio: (EspacioIsla) -> Void = { _ in }
    var unirse: (URL) -> Void = { _ in }
    var abrirAgentes: () -> Void = {}
    var dictar: () -> Void = {}
    var dictarEncargo: () -> Void = {}
    var elegirFondo: (FondoLanzador) -> Void = { _ in }
    var elegirImagen: () -> Void = {}
    var alternarTema: () -> Void = {}
    var elegirTema: (PreferenciaTema) -> Void = { _ in }
    /// El tema pudo cambiar (llegó la imagen del fondo): la ventana ajusta su apariencia.
    var temaCambio: () -> Void = {}

    /// Lo que piden las piezas compartidas con la isla (la reunión, los agentes).
    var deLaIsla: AccionesIsla { AccionesIsla(unirse: unirse, dictar: dictar, dictarEncargo: dictarEncargo) }
}

/// La pantalla del lanzador. En los renders (`simulado`) no hay campo de texto de AppKit ni vidrio real ni animación de entrada.
struct RaizLanzador: View {
    @Bindable var estado: EstadoLanzador
    let catalogo: CatalogoApps
    let datos: DatosLanzador
    let acciones: AccionesLanzador
    var simulado = false
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var visto = false
    @FocusState private var enfocado: Bool

    var body: some View {
        let tema = estado.tema
        let paleta = estado.paletaVigente
        let lista = estado.elementos
        GeometryReader { geo in
            ZStack(alignment: .top) {
                FondoEscritorioVista(fondo: estado.fondo, paleta: paleta, tema: tema, imagen: estado.fondoModelo.imagen, video: estado.fondoModelo.video)
                    .ignoresSafeArea()
                Color.clear.contentShape(Rectangle()).onTapGesture { acciones.cerrar() }
                    .accessibilityHidden(true)
                lienzoEscalado(geo.size, lista)
                barraSuperior
                if estado.selectorAbierto {
                    SelectorFondo(estado: estado, acciones: acciones)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, AuroraMedida.botonesTop + AuroraMedida.botonCircular + 10)
                        .padding(.trailing, AuroraMedida.botonesDerecha)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.auroraTema, tema)
        .environment(\.auroraPaleta, paleta)
        .environment(\.colorScheme, tema.esquema)
        .scaleEffect(visto || sinMovimiento || simulado ? 1 : AuroraMovimiento.escalaInicial)
        .opacity((visto || simulado) && !estado.saliendo ? 1 : 0)
        .animation(.easeOut(duration: AuroraMovimiento.fundidoCierre), value: estado.saliendo)
        .animation(.easeOut(duration: AuroraMovimiento.datoDuracion), value: estado.selectorAbierto)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(AuroraMovimiento.abrir(sinMovimiento: sinMovimiento)) { visto = true }
            if !simulado { DispatchQueue.main.async { enfocado = true } }
        }
        .onChange(of: estado.consulta) { estado.consultaCambio() }
        .onChange(of: estado.fondo) { estado.sincronizarFondo() }
        .onChange(of: estado.tema) { acciones.temaCambio() }
        .task(id: visibles(lista).flatMap { $0.apps.map(\.id) }) { catalogo.pedirIconos(visibles(lista).flatMap(\.apps)) }
    }

    /// Lo de la página actual: para pedir solo sus íconos (y los cuatro de cada carpeta).
    private func visibles(_ lista: [MosaicoInicio]) -> [MosaicoInicio] {
        let rango = estado.rejilla.rango(pagina: estado.pagina)
        return Array(lista[min(rango.lowerBound, lista.count)..<min(rango.upperBound, lista.count)])
    }

    // MARK: Barra superior

    private var barraSuperior: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 8) {
                campoBusqueda
                filaSegmentos
            }
            .padding(.top, AuroraMedida.busquedaTop)
            ContenedorVidrio(separacion: AuroraMedida.botonesSeparacion) {
                HStack(spacing: AuroraMedida.botonesSeparacion) {
                    BotonCircularAurora(simbolo: "photo", ayuda: "Fondo del lanzador", accion: { estado.selectorAbierto.toggle() })
                    BotonCircularAurora(simbolo: "circle.lefthalf.filled", ayuda: "Tema: \(estado.preferencia.nombre). Toca para cambiarlo", accion: acciones.alternarTema)
                    BotonCircularAurora(simbolo: "xmark", ayuda: "Cerrar el lanzador", accion: acciones.cerrar)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, AuroraMedida.botonesTop)
            .padding(.trailing, AuroraMedida.botonesDerecha)
        }
    }

    private var campoBusqueda: some View {
        let tema = estado.tema
        return HStack(spacing: AuroraMedida.busquedaSeparacion) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AuroraMedida.busquedaLupa, weight: .medium))
                .foregroundStyle(tema.textoSuave)
            if simulado {   // ImageRenderer no dibuja campos de AppKit
                Text(estado.consulta.isEmpty ? "Buscar" : estado.consulta)
                    .font(AuroraTipo.busqueda)
                    .foregroundStyle(estado.consulta.isEmpty ? tema.textoSuave : tema.textoPleno)
                Spacer(minLength: 0)
            } else {
                TextField("", text: $estado.consulta, prompt: Text("Buscar apps, atajos o calcular").foregroundStyle(tema.textoSuave))
                    .textFieldStyle(.plain)
                    .font(AuroraTipo.busqueda)
                    .foregroundStyle(tema.textoPleno)
                    .focused($enfocado)
                    .accessibilityLabel("Buscar apps o atajos, o calcular")
            }
        }
        .padding(.horizontal, AuroraMedida.busquedaRelleno)
        .frame(width: AuroraMedida.busquedaAncho, height: AuroraMedida.busquedaAlto)
        .vidrioAuroraCapsula()
    }

    /// Bajo el buscador: los dos segmentos (Mis apps y Todas) y los espacios de `espacios.txt` (elegir uno hace lo mismo que en Inicio y
    /// el Dock; tocar el activo lo quita; ⌘1 a ⌘4 también).
    private var filaSegmentos: some View {
        HStack(spacing: 4) {
            chip("Mis apps", activo: estado.segmento == .misApps && estado.carpetaAbierta == nil && estado.consulta.isEmpty,
                 ayuda: "Tus apps: fijadas, carpetas y más usadas") { estado.elegirSegmento(.misApps) }
            chip("Todas", activo: estado.segmento == .todas && estado.consulta.isEmpty, ayuda: "Todas las apps, por nombre") { estado.elegirSegmento(.todas) }
            if !datos.lanzador.espacios.isEmpty {
                Capsule().fill(estado.tema.textoTenue).frame(width: 1, height: 16).padding(.horizontal, 4).accessibilityHidden(true)
                ForEach(Array(datos.lanzador.espacios.prefix(6).enumerated()), id: \.element.nombre) { i, e in
                    let activo = datos.lanzador.espacioActual == e.nombre
                    chip(e.nombre, activo: activo,
                         ayuda: "\(e.nombre) (⌘\(i + 1)): \(LanzadorIsla.resumen(e))" + (activo ? ". Toca otra vez para quitar el espacio." : ""),
                         etiqueta: "Espacio \(e.nombre)" + (activo ? ", activo" : ""), acento: e.acento) { acciones.elegirEspacio(e) }
                }
            }
        }
    }

    private func chip(_ titulo: String, activo: Bool, ayuda: String, etiqueta: String? = nil, acento: Color? = nil, accion: @escaping () -> Void) -> some View {
        let tema = estado.tema
        return Button(action: accion) {
            Text(titulo).font(AuroraLanzador.chipFuente)
                .foregroundStyle(activo ? tema.fondoChipActivo : tema.textoChip)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: AuroraLanzador.chipAlto)
                .background { Capsule().fill(activo ? tema.textoPleno : tema.fila) }
                .indicadorEspacio(activo: activo, acento: acento)
                .contentShape(Capsule())
        }
        .buttonStyle(PulsadoAurora())
        .help(ayuda)
        .accessibilityLabel(etiqueta ?? titulo)
        .accessibilityHint(ayuda)
        .accessibilityAddTraits(activo ? .isSelected : [])
    }

    // MARK: Lienzo

    /// La composición, centrada en el espacio que dejan la barra de arriba y el Dock de abajo, a la escala que pide la pantalla: la rejilla
    /// crece con ella (el ícono pasa de 70 a 96 como mucho) y se encoge hasta los 48 del mínimo.
    private func lienzoEscalado(_ pantalla: CGSize, _ lista: [MosaicoInicio]) -> some View {
        let alto = AuroraMedida.lienzoAlto + AuroraMedida.paginasAlto
        let g = Self.geometria(pantalla: pantalla, alto: alto, reserva: estado.reservaInferior)
        return lienzo(lista)
            .frame(width: AuroraMedida.lienzoAncho, height: alto, alignment: .top)
            .scaleEffect(g.escala, anchor: .top)
            .padding(.top, g.arriba)
    }

    /// La escala y el margen de arriba del lienzo (separado para probarlo con medidas de pantalla).
    static func geometria(pantalla: CGSize, alto: CGFloat, reserva: CGFloat) -> (escala: CGFloat, arriba: CGFloat) {
        let barra = AuroraLanzador.altoBarra
        let libre = max(pantalla.height - barra - reserva, 1)
        let alAncho = (pantalla.width - 2 * AuroraLanzador.margenLateral) / AuroraMedida.lienzoAncho
        let escala = min(max(min(alAncho, libre / alto), AuroraLanzador.escalaMin), AuroraLanzador.escalaMax)
        return (escala, barra + max(0, (libre - alto * escala) / 2))
    }

    private func punto(_ c: RejillaLanzador.Celda) -> CGPoint {
        CGPoint(x: CGFloat(c.columna) * (AuroraMedida.celda + AuroraMedida.separacionColumnas),
                y: CGFloat(c.fila) * (AuroraMedida.filaAlto + AuroraMedida.separacionFilas))
    }

    private func punto(_ b: RejillaLanzador.Bloque) -> CGPoint { punto(.init(fila: b.fila, columna: b.columna)) }

    @ViewBuilder private func ubicado<V: View>(_ b: RejillaLanzador.Bloque, @ViewBuilder _ vista: () -> V) -> some View {
        let p = punto(b)
        vista()
            .frame(width: AuroraMedida.ancho(columnas: b.ancho), height: AuroraMedida.alto(filas: b.alto))
            .offset(x: p.x, y: p.y)
    }

    private var lienzoWidgets: some View {
        let ahora = datos.ahora()
        return ZStack(alignment: .topLeading) {
            ubicado(RejillaLanzador.fecha) { WidgetFecha(ahora: ahora, agenda: datos.agenda, simulado: simulado) }
            ubicado(RejillaLanzador.musica) {
                TarjetaMusicaLanzador(musica: datos.musica, fondo: estado.fondoModelo.imagen, simulado: simulado)
            }
            // El clima va directo sobre el fondo; dentro de una carpeta, su hueco lo ocupa el chip para volver.
            if estado.carpetaAbierta == nil {
                if datos.lanzador.espacio?.muestraPlan == true {
                    // En Mañana (o con la pieza `plan` en su Dock), el plan del día y la semana toma el lugar del clima.
                    ubicado(RejillaLanzador.clima) {
                        TarjetaPlanLanzador(plan: PlanManana.compartido, ahora: ahora, abrirAgentes: acciones.abrirAgentes, simulado: simulado)
                            .onAppear { if !simulado { PlanManana.compartido.refrescar() } }
                    }
                } else {
                    ubicado(RejillaLanzador.clima) { ClimaLanzador(clima: datos.clima, ahora: ahora) }
                }
            }
            ubicado(RejillaLanzador.agentes) {
                TarjetaAgentesLanzador(claude: datos.claude, agentes: datos.agentes, tablero: datos.tablero, ahora: ahora,
                                       acciones: acciones.deLaIsla, abrirAgentes: acciones.abrirAgentes, simulado: simulado)
            }
            ubicado(RejillaLanzador.agenda) {
                TarjetaAgendaLanzador(agenda: datos.agenda, ahora: ahora, config: datos.config, acciones: acciones.deLaIsla, simulado: simulado)
            }
        }
        .environment(\.altoTarjetaAura, nil)   // las tarjetas se estiran al bloque de 2 × 2
    }

    private func lienzo(_ lista: [MosaicoInicio]) -> some View {
        let rej = RejillaLanzador(total: lista.count, conWidgets: estado.conWidgets)
        let tema = estado.tema
        let cuenta = estado.calculo
        let hayCuenta = cuenta != nil && !estado.consulta.isEmpty
        let bajada: CGFloat = hayCuenta ? FilaCalculo.alto + AuroraMedida.separacionFilas : 0
        return ZStack(alignment: .topLeading) {
            if rej.conWidgets {
                ContenedorVidrio { lienzoWidgets }
                    .transition(.opacity)
            }
            if hayCuenta, let cuenta {
                FilaCalculo(consulta: estado.consulta, resultado: cuenta, activa: estado.enCalculo) { acciones.copiarCalculo(cuenta) }
                    .frame(width: AuroraMedida.lienzoAncho, height: FilaCalculo.alto)
            }
            ForEach(Array(rej.rango(pagina: estado.pagina)), id: \.self) { i in
                if lista.indices.contains(i) {
                    let p = punto(rej.celda(de: i))
                    celda(lista[i], seleccionada: estado.seleccion == i)
                        .offset(x: p.x, y: p.y + bajada)
                }
            }
            if estado.carpetaAbierta != nil { volverDeCarpeta }
            if lista.isEmpty && !estado.consulta.trimmingCharacters(in: .whitespaces).isEmpty && !hayCuenta {
                Text("Sin resultados para «\(estado.consulta)»")
                    .font(AuroraTipo.titulo)
                    .foregroundStyle(tema.textoSuave)
                    .frame(width: AuroraMedida.lienzoAncho, alignment: .center)
                    .offset(y: AuroraMedida.alto(filas: 1))
            }
            if rej.paginas > 1 { indicadorPaginas(rej) }
        }
        .animation(AuroraMovimiento.dato, value: rej.conWidgets)
        .frame(width: AuroraMedida.lienzoAncho, alignment: .topLeading)
    }

    @ViewBuilder private func celda(_ m: MosaicoInicio, seleccionada: Bool) -> some View {
        switch m {
        case .app(let app):
            CeldaApp(app: app, icono: catalogo.iconos[app.id], seleccionada: seleccionada,
                     abierta: catalogo.abiertas.contains(app.id), lanzar: { acciones.lanzar(app) },
                     fija: estado.esFija(app), ocultar: { acciones.ocultar(app) }, alternarFija: { acciones.alternarFija(app) }, mostrarEnFinder: { acciones.mostrarEnFinder(app) })
        case .carpeta(let c, let r):
            CeldaCarpeta(nombre: c.nombre, apps: Array(r.prefix(4)), total: r.count, iconos: catalogo.iconos, seleccionada: seleccionada) {
                acciones.abrirCarpeta(c.nombre)
            }
        case .atajo(let n):
            CeldaAtajo(nombre: n, seleccionada: seleccionada) { acciones.correrAtajo(n) }
        }
    }

    /// Dentro de una carpeta: un chip para volver (Esc también), en el hueco que deja el clima.
    private var volverDeCarpeta: some View {
        let tema = estado.tema
        return Button { acciones.volver() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                Text(estado.carpetaAbierta ?? "").font(AuroraNotch.chipFuente).lineLimit(1)
            }
            .foregroundStyle(tema.textoPleno)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background { Capsule().fill(tema.filaActiva) }
            .contentShape(Capsule())
        }
        .buttonStyle(PulsadoAurora())
        .offset(x: punto(.init(fila: 0, columna: 2)).x + 4, y: 4)   // en el hueco del clima
        .help("Volver")
        .accessibilityLabel("Volver desde la carpeta \(estado.carpetaAbierta ?? "")")
    }

    private func indicadorPaginas(_ rej: RejillaLanzador) -> some View {
        let tema = estado.tema
        return HStack(spacing: AuroraMedida.paginasSeparacion) {
            ForEach(0..<rej.paginas, id: \.self) { n in
                Circle()
                    .fill(n == estado.pagina ? tema.textoPleno : tema.textoTenue)
                    .frame(width: AuroraMedida.puntoPagina, height: AuroraMedida.puntoPagina)
                    .onTapGesture { estado.pagina = n; if estado.seleccion != nil { estado.seleccion = rej.rango(pagina: n).lowerBound } }
                    .accessibilityElement()
                    .accessibilityLabel("Página \(n + 1) de \(rej.paginas)")
                    .accessibilityAddTraits(n == estado.pagina ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(width: AuroraMedida.lienzoAncho)
        .offset(y: AuroraMedida.lienzoAlto + AuroraMedida.paginasAlto / 2 - AuroraMedida.puntoPagina)
    }
}

// MARK: - Una app

struct CeldaApp: View {
    let app: EntradaApp
    let icono: NSImage?
    let seleccionada: Bool
    let abierta: Bool
    let lanzar: () -> Void
    var fija = false
    let ocultar: () -> Void
    var alternarFija: () -> Void = {}
    let mostrarEnFinder: () -> Void
    @Environment(\.auroraTema) private var tema
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var encima = false

    var body: some View {
        Button(action: lanzar) {
            VStack(spacing: AuroraMedida.iconoEspacioEtiqueta) {
                ZStack(alignment: .bottom) {
                    imagen
                        .scaleEffect(encima && !sinMovimiento ? AuroraMovimiento.punteroEscala : 1)
                        .animation(AuroraMovimiento.puntero, value: encima)
                    if abierta { IndicadorAbierta().offset(y: AuroraMedida.indicadorAbierta.height + 2) }
                }
                .frame(width: AuroraMedida.icono, height: AuroraMedida.icono)
                EtiquetaApp(texto: app.nombre)
            }
            .padding(.top, AuroraMedida.celdaArriba)
            .frame(width: AuroraMedida.celda, height: AuroraMedida.filaAlto, alignment: .top)
            .background {
                if seleccionada {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(tema.filaActiva)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(tema.filaActivaBorde, lineWidth: 1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .onHover { encima = $0 }
        .contextMenu {
            if app.bundleID != nil { Button(fija ? "Quitar de fijas" : "Fijar", action: alternarFija) }
            Button("Ocultar", action: ocultar)
            Button("Mostrar en Finder", action: mostrarEnFinder)
        }
        .accessibilityLabel(app.nombre)
        .accessibilityValue((abierta ? "abierta" : "") + (fija ? (abierta ? ", fija" : "fija") : ""))
        .accessibilityAddTraits(seleccionada ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Abre la app")
    }

    @ViewBuilder private var imagen: some View {
        if let icono {
            Image(nsImage: icono)
                .resizable()
                .frame(width: AuroraMedida.icono, height: AuroraMedida.icono)
                .shadow(color: .black.opacity(AuroraEfecto.sombraIcono.opacidad), radius: AuroraEfecto.sombraIcono.radio, y: AuroraEfecto.sombraIcono.y)
        } else {
            MosaicoIcono(lado: AuroraMedida.icono) {
                Text(String(app.nombre.prefix(1)).uppercased()).font(.system(size: 28, weight: .semibold))
            }
        }
    }
}

/// Una carpeta de `carpetas.txt`: un mosaico con los iconos de sus cuatro primeras apps; se abre en el sitio.
struct CeldaCarpeta: View {
    let nombre: String
    let apps: [EntradaApp]
    let total: Int
    let iconos: [String: NSImage]
    let seleccionada: Bool
    let abrir: () -> Void
    @Environment(\.auroraTema) private var tema
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var encima = false

    var body: some View {
        Button(action: abrir) {
            VStack(spacing: AuroraMedida.iconoEspacioEtiqueta) {
                mosaico
                    .scaleEffect(encima && !sinMovimiento ? AuroraMovimiento.punteroEscala : 1)
                    .animation(AuroraMovimiento.puntero, value: encima)
                    .frame(width: AuroraMedida.icono, height: AuroraMedida.icono)
                EtiquetaApp(texto: nombre)
            }
            .padding(.top, AuroraMedida.celdaArriba)
            .frame(width: AuroraMedida.celda, height: AuroraMedida.filaAlto, alignment: .top)
            .background { if seleccionada { fondoSeleccion(tema) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .onHover { encima = $0 }
        .accessibilityLabel("Carpeta \(nombre), \(total) apps")
        .accessibilityAddTraits(seleccionada ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Abre la carpeta")
    }

    private var mosaico: some View {
        let lado = AuroraMedida.icono
        let mini = (lado - 3 * 6) / 2
        return RoundedRectangle(cornerRadius: lado * AuroraMedida.iconoRadioProporcion, style: .continuous)
            .fill(tema.mosaico)
            .overlay(RoundedRectangle(cornerRadius: lado * AuroraMedida.iconoRadioProporcion, style: .continuous)
                .strokeBorder(LinearGradient(colors: [tema.bordeArriba, tema.bordeAbajo], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay {
                VStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { fila in
                        HStack(spacing: 4) {
                            ForEach(0..<2, id: \.self) { col in
                                let i = fila * 2 + col
                                Group {
                                    if i < apps.count, let img = iconos[apps[i].id] { Image(nsImage: img).resizable().scaledToFit() } else { Color.clear }
                                }
                                .frame(width: mini, height: mini)
                            }
                        }
                    }
                }
            }
            .frame(width: lado, height: lado)
            .shadow(color: .black.opacity(AuroraEfecto.sombraIcono.opacidad), radius: AuroraEfecto.sombraIcono.radio, y: AuroraEfecto.sombraIcono.y)
    }
}

/// Un atajo de Apple que coincide con lo buscado. No corre al buscar: solo con Return o un clic.
struct CeldaAtajo: View {
    let nombre: String
    let seleccionada: Bool
    let correr: () -> Void
    @Environment(\.auroraTema) private var tema
    @State private var encima = false

    var body: some View {
        Button(action: correr) {
            VStack(spacing: AuroraMedida.iconoEspacioEtiqueta) {
                MosaicoIcono(lado: AuroraMedida.icono) {
                    Image(systemName: "bolt.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(AuroraAcento.foco)
                }
                .scaleEffect(encima ? AuroraMovimiento.punteroEscala : 1)
                .animation(AuroraMovimiento.puntero, value: encima)
                .frame(width: AuroraMedida.icono, height: AuroraMedida.icono)
                EtiquetaApp(texto: nombre)
            }
            .padding(.top, AuroraMedida.celdaArriba)
            .frame(width: AuroraMedida.celda, height: AuroraMedida.filaAlto, alignment: .top)
            .background { if seleccionada { fondoSeleccion(tema) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsadoAurora())
        .onHover { encima = $0 }
        .help("Correr el atajo «\(nombre)»")
        .accessibilityLabel("Atajo \(nombre)")
        .accessibilityAddTraits(seleccionada ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Corre el atajo")
    }
}

/// El nombre bajo el ícono: hasta dos líneas, centrado (no se corta con puntos suspensivos mientras quepa en dos).
struct EtiquetaApp: View {
    let texto: String
    @Environment(\.auroraTema) private var tema

    var body: some View {
        Text(texto)
            .font(AuroraTipo.etiquetaApp)
            .foregroundStyle(tema.textoPleno)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(tema.esOscuro ? AuroraEfecto.sombraTextoOscuro.opacidad : 0),
                    radius: AuroraEfecto.sombraTextoOscuro.radio, y: AuroraEfecto.sombraTextoOscuro.y)
            .frame(width: AuroraMedida.celda - 6, alignment: .top)
    }
}

@ViewBuilder private func fondoSeleccion(_ tema: AuroraTema) -> some View {
    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(tema.filaActiva)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(tema.filaActivaBorde, lineWidth: 1))
}

// MARK: - La cuenta

/// Si lo escrito es aritmética, el resultado es la primera fila; Return lo copia.
struct FilaCalculo: View {
    static let alto: CGFloat = 72
    let consulta: String
    let resultado: String
    let activa: Bool
    let copiar: () -> Void
    @Environment(\.auroraTema) private var tema

    var body: some View {
        Button(action: copiar) {
            HStack(spacing: 12) {
                Text("= " + resultado)
                    .font(AuroraTipo.frase(34))
                    .tracking(34 * AuroraTipo.fraseInterletra)
                    .foregroundStyle(tema.textoPleno)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 0)
                RotuloAurora(texto: "↩ copiar")
            }
            .padding(.horizontal, AuroraMedida.widgetRelleno + 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .superficieWidget()
            .overlay {
                if activa {
                    RoundedRectangle(cornerRadius: AuroraMedida.widgetRadio, style: .continuous).strokeBorder(tema.filaActivaBorde, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(PulsadoAurora())
        .accessibilityLabel("Resultado: \(resultado)")
        .accessibilityHint("Copia el resultado")
    }
}

// MARK: - Widgets
