import AppKit
import DictadoKit
import SwiftUI

// El Centro a pantalla completa en el lenguaje de la isla (Aurora): el fondo de pantalla del Mac (el mismo del lanzador, con más velo), un riel delgado a la izquierda con diez
// secciones (Hoy, Tablero, Semana, Reuniones, Mac, Consumo, Herramientas, Finanzas, Noticias y Automatizaciones; ⌘1 a ⌘9 y ⌘0), una línea de encabezado (fecha, espacio actual y qué pasa ahora) y, debajo, la
// sección en tarjetas grandes. Es la vista grande de lo mismo que ya ve la isla y el Dock: se lee solo y no pide curar nada.
// Con el ajuste `defaults write app.dictado centro.clasico -bool true` vuelve el Centro de antes (Hoy, Metas, Orquesta, Inbox, Notas).

/// Lo que el Centro nuevo hace fuera de sí mismo.
struct AccionesCentroAurora {
    var cerrar: () -> Void = {}
    /// Abre Salud del Mac en Limpieza; `explicar` despliega la primera categoría segura. Nada se borra desde aquí.
    var abrirSalud: (_ explicar: Bool) -> Void = { _ in }
    /// Abre un enlace web (una noticia) o el tablero de finanzas del cerebro. Solo http o https, o un archivo dentro del cerebro.
    var abrirEnlace: (_ url: URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Entra a una videollamada de la agenda (Hoy).
    var unirse: (_ enlace: URL) -> Void = { NSWorkspace.shared.open($0) }
    var abrirRuta: (_ rutaRelativa: String) -> Void = { _ in }
}

struct RaizCentroAurora: View {
    let datos: DatosCentro
    @Bindable var nav: NavegacionAurora
    /// El fondo de escritorio (pieza compartida con el lanzador): lo lee y lo suelta quien abre la ventana.
    let escritorio: FondoEscritorio
    var paleta = AuroraPaleta.lagunaDurazno
    var simulado = false
    var margenes = EdgeInsets()
    var acciones = AccionesCentroAurora()
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var visto = false

    var body: some View {
        let ahora = datos.reloj.ahora
        ZStack {
            FondoEscritorioVista(fondo: escritorio.fondo(espacio: datos.fondoEspacio()), paleta: paleta, tema: .oscuro, imagen: escritorio.modelo.imagen, video: escritorio.modelo.video,
                                 refuerzo: TemaDelFondo.refuerzoDeVelo(luminancia: escritorio.modelo.luminancia))
                .ignoresSafeArea()
            HStack(alignment: .top, spacing: 0) {
                riel(ahora)
                    .frame(width: AuroraCentro.riel)
                VStack(alignment: .leading, spacing: 16) {
                    cabecera(ahora)
                    seccion
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.trailing, AuroraCentro.margen)
                .padding(.vertical, AuroraCentro.margen)
            }
            .padding(margenes)
        }
        .environment(\.auroraTema, .oscuro)
        .environment(\.auroraPaleta, paleta)
        .environment(\.vidrioSimulado, simulado)
        .environment(\.colorScheme, .dark)
        .environment(\.altoTarjetaAura, nil)
        .foregroundStyle(.white)
        .opacity((visto || simulado) && !nav.saliendo ? 1 : 0)
        .animation(.easeOut(duration: AuroraMovimiento.fundidoCierre), value: nav.saliendo)
        .ignoresSafeArea()
        .onChange(of: nav.seccion) { _, s in datos.visitar(s) }
        .onChange(of: escritorio.fondo(espacio: datos.fondoEspacio())) { escritorio.sincronizar(espacio: datos.fondoEspacio()) }
        .onAppear { withAnimation(.easeOut(duration: sinMovimiento ? AuroraMovimiento.fundidoSinMovimiento : 0.22)) { visto = true } }
    }

    // MARK: Riel

    private func riel(_ ahora: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Centro").font(.system(size: 22, weight: .bold)).tracking(-0.3)
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
            ForEach(SeccionAurora.allCases, id: \.self) { s in
                ItemRielAurora(titulo: s.titulo, simbolo: s.simbolo, atajo: s.atajo, activo: nav.seccion == s, aviso: datos.aviso(s, ahora: ahora)) { nav.seccion = s }
            }
            Spacer(minLength: 0)
            Text("esc para cerrar").font(AuroraCentro.minimo).foregroundStyle(AuroraCentro.sutil).padding(.horizontal, 16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, AuroraCentro.margen)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Secciones del Centro")
    }

    // MARK: Encabezado

    private func cabecera(_ ahora: Date) -> some View {
        let fecha = FraseCentro.fecha(ahora)
        let frase = datos.frase(ahora: ahora)
        return HStack(spacing: 16) {
            Text(fecha.prefix(1).uppercased() + fecha.dropFirst()).font(AuroraCentro.titulo).tracking(-0.3).lineLimit(1)
            if let espacio = datos.espacio(), !espacio.isEmpty { ChipAurora(texto: espacio, icono: "square.stack") }
            Spacer(minLength: 12)
            Text(frase).font(.system(size: 17, weight: .medium)).foregroundStyle(AuroraCentro.resumen).lineLimit(1)
            BotonAura(icono: "xmark", estilo: .oscuro, redondo: true, grande: true, ayuda: "Cerrar el Centro", accion: acciones.cerrar)
        }
        .frame(height: AuroraCentro.altoCabecera)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fecha). \(frase)")
    }

    // MARK: Sección

    @ViewBuilder private var seccion: some View {
        switch nav.seccion {
        case .hoy: HoyAurora(datos: datos, simulado: simulado, abrir: acciones.abrirEnlace, abrirRuta: acciones.abrirRuta, unirse: acciones.unirse)
        case .tablero: TableroAurora(datos: datos, nav: nav, simulado: simulado)
        case .semana: SemanaAurora(datos: datos, nav: nav, simulado: simulado)
        case .reuniones: ReunionesAurora(datos: datos, nav: nav, simulado: simulado)
        case .mac: MacCentroAurora(salud: datos.salud, abrirSalud: acciones.abrirSalud, simulado: simulado)
        case .consumo: ConsumoAurora(lectura: datos.lecturas.consumo, nav: nav, ahora: datos.reloj.ahora, simulado: simulado)
        case .herramientas: HerramientasAurora(lectura: datos.lecturas.herramientas, nav: nav, ahora: datos.reloj.ahora, simulado: simulado)
        case .finanzas: FinanzasAurora(lectura: datos.lecturas.finanzas, abrir: acciones.abrirRuta, simulado: simulado)
        case .noticias: NoticiasAurora(lectura: datos.lecturas.noticias, nav: nav, ahora: datos.reloj.ahora, simulado: simulado, abrir: acciones.abrirEnlace)
        case .automatizaciones: AutomatizacionesAurora(lectura: datos.lecturas.automatizaciones, ahora: datos.reloj.ahora, simulado: simulado)
        }
    }
}
