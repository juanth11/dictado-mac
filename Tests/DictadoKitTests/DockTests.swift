import CoreGraphics
import Testing
@testable import DictadoKit

private let casa = "/Users/ana"

// MARK: La línea dock:

@Test("Dock: la línea de ejemplo se lee en orden, con los huecos del |")
func dockAnalizarEjemplo() {
    let p = ReglasDock.analizar("reloj, agenda, agentes, dictar, | Claude, Arc, | carpeta:~/Downloads, papelera", home: casa)
    #expect(p == [.reloj, .agenda, .agentes, .dictar, .hueco, .app("Claude"), .app("Arc"), .hueco, .carpeta(casa + "/Downloads"), .papelera])
}

@Test("Dock: reconoce todas las piezas con y sin tildes, y app: fuerza una app")
func dockAnalizarPiezas() {
    let p = ReglasDock.analizar("Música, BATERÍA, fecha, mac, tareas, foco, app:Foco, grupo:Trabajo, com.apple.Safari", home: casa)
    #expect(p == [.musica, .bateria, .fecha, .mac, .tareas, .foco, .app("Foco"), .grupo("Trabajo"), .app("com.apple.Safari")])
}

@Test("Dock: huecos sobrantes (al principio, al final, seguidos) se limpian; el | puede ir pegado o suelto")
func dockHuecos() {
    #expect(ReglasDock.analizar("| reloj || | agenda |", home: casa) == [.reloj, .hueco, .agenda])
    #expect(ReglasDock.analizar("reloj|agenda", home: casa) == [.reloj, .hueco, .agenda])
    #expect(ReglasDock.analizar("", home: casa).isEmpty)
    #expect(ReglasDock.analizar(" , |, ", home: casa).isEmpty)
}

@Test("Dock: ~ se expande solo al principio y carpeta: sin ruta se descarta")
func dockTilde() {
    #expect(ReglasDock.expandir("~", home: casa) == casa)
    #expect(ReglasDock.expandir("~/Documents/x", home: casa) == casa + "/Documents/x")
    #expect(ReglasDock.expandir("/tmp/a~b", home: casa) == "/tmp/a~b")
    #expect(ReglasDock.analizar("carpeta:, reloj", home: casa) == [.reloj])
}

@Test("Dock: por omisión, lanzador, reloj, clima, agenda, agentes, dictar, las seis más usadas, Descargas y la papelera")
func dockPorOmision() {
    let p = ReglasDock.porOmision(masUsadas: ["a", "b", "c", "d", "e", "f", "g"], home: casa)
    #expect(p == [.lanzador, .reloj, .clima, .agenda, .agentes, .dictar, .hueco, .app("a"), .app("b"), .app("c"), .app("d"), .app("e"), .app("f"), .abiertas, .hueco,
                  .carpeta(casa + "/Downloads"), .finder, .papelera])
    #expect(ReglasDock.porOmision(masUsadas: [], home: casa) == [.lanzador, .reloj, .clima, .agenda, .agentes, .dictar, .abiertas, .hueco, .carpeta(casa + "/Downloads"), .finder, .papelera])
}

@Test("Espacios: la línea dock: se guarda tal cual y sin ella el espacio usa las piezas de siempre")
func dockEnEspacios() {
    let e = EspaciosIsla.leer("[Trabajo]\nprimero: Mail\ndock: reloj, Claude, papelera\n\n[Foco]\nfoco: 25")
    #expect(e[0].dock == "reloj, Claude, papelera")
    #expect(e[1].dock == nil)
    #expect(e[0].piezasDock(masUsadas: ["x"], home: casa) == [.reloj, .app("Claude"), .papelera])
    #expect(e[1].piezasDock(masUsadas: ["x"], home: casa) == ReglasDock.porOmision(masUsadas: ["x"], home: casa))
    let vacia = EspaciosIsla.leer("[A]\ndock: | |")
    #expect(vacia[0].piezasDock(masUsadas: [], home: casa) == ReglasDock.porOmision(masUsadas: [], home: casa))
}

@Test("Espacios: el archivo inicial sigue trayendo cuatro espacios sin línea dock")
func dockInicialSinLinea() {
    let e = EspaciosIsla.leer(EspaciosIsla.inicial)
    #expect(e.count == 4)
    #expect(e.allSatisfy { $0.dock == nil })
}

// MARK: Reparto del ancho

private func colocar(_ p: [PiezaDock], _ ancho: Double) -> DisposicionDock { ReglasDock.colocar(p, anchoDisponible: ancho) }

@Test("Reparto: si cabe, todo va entero y el ancho suma piezas, separaciones y relleno")
func repartoCabe() {
    let r = colocar([.reloj, .agenda, .papelera], 2000)
    #expect(r.piezas.map(\.pieza) == [.reloj, .agenda, .papelera])
    #expect(r.piezas.allSatisfy { $0.modo == .completa })
    let esperado: Double = 142 + 396 + 62 + 20 + 18
    #expect(r.ancho == esperado)
    #expect(r.compactadas.isEmpty && r.soltadas.isEmpty)
}

@Test("Reparto: primero se compacta la música, luego la agenda, el foco y los agentes")
func repartoCompactaEnOrden() {
    let todas: [PiezaDock] = [.musica, .agenda, .foco, .agentes]
    let entero = colocar(todas, 5000).ancho
    let a = colocar(todas, entero - 100)
    #expect(a.compactadas == [.musica])
    #expect(a.piezas.map(\.modo) == [.compacta, .completa, .completa, .completa])
    let b = colocar(todas, entero - 300)
    #expect(b.compactadas == [.musica, .agenda])
    #expect(b.soltadas.isEmpty)
    let ahorro: Double = 172 + 160 + 88 + 128
    let c = colocar(todas, entero - ahorro)
    #expect(c.compactadas == [.musica, .agenda, .foco, .agentes])
    #expect(c.piezas.allSatisfy { $0.modo == .compacta })
}

@Test("Reparto: sin cupo se sueltan piezas en el orden fijado y la papelera se queda")
func repartoSuelta() {
    let piezas: [PiezaDock] = [.reloj, .fecha, .bateria, .mac, .tareas, .dictar, .hueco, .app("A"), .app("B"), .hueco, .carpeta("/x"), .papelera]
    let r = colocar(piezas, 400)
    #expect(r.piezas.last?.pieza == .papelera)
    #expect(r.ancho <= 400)
    #expect(Array(r.soltadas.prefix(4)) == [.bateria, .fecha, .mac, .tareas])
    #expect(!r.piezas.contains { $0.pieza == .bateria || $0.pieza == .fecha })
}

@Test("Reparto: las apps se sueltan de la última a la primera y no quedan huecos sueltos")
func repartoAppsDeAtras() {
    let piezas: [PiezaDock] = [.reloj, .hueco, .app("A"), .app("B"), .app("C"), .hueco, .papelera]
    let ancho: Double = 18 + 142 + 4 + 72 + 4 + 62 + 40   // reloj | A | papelera: cuatro separaciones
    let r = colocar(piezas, ancho)
    #expect(r.soltadas == [.app("C"), .app("B")])
    #expect(r.piezas.map(\.pieza) == [.reloj, .hueco, .app("A"), .hueco, .papelera])
}

@Test("Reparto: con un ancho absurdo queda al menos la papelera y el resultado es estable")
func repartoMinimo() {
    let piezas: [PiezaDock] = [.reloj, .agenda, .agentes, .dictar, .hueco, .app("A"), .hueco, .carpeta("/x"), .papelera]
    let r = colocar(piezas, 10)
    #expect(r.piezas.map(\.pieza) == [.papelera])
    #expect(colocar(piezas, 10) == r)
    #expect(colocar(piezas, 700) == colocar(piezas, 700))
}

@Test("Reparto: lista vacía y huecos solos no rompen nada")
func repartoVacio() {
    #expect(colocar([], 500).piezas.isEmpty)
    #expect(colocar([.hueco, .hueco], 500).piezas.isEmpty)
    #expect(colocar([], 500).ancho == 18)
}

@Test("Selector: el ancho suma los círculos, la cápsula y el +")
func selectorAncho() {
    #expect(MedidasDock.anchoSelector(espacios: 0) == 40)
    let cuatro: Double = 120 + 9 + 10 + 7 + 40
    let uno: Double = 30 + 10 + 7 + 40
    #expect(MedidasDock.anchoSelector(espacios: 4) == cuatro)
    #expect(MedidasDock.anchoSelector(espacios: 1) == uno)
}

@Test("Visibilidad: el selector también mantiene el Dock a la vista")
func visibilidadSelector() {
    var p = PoliticaDock(modo: .alTocarBorde)
    _ = p.bordeSostenido()
    _ = p.punteroEntra(.barra)
    _ = p.punteroEntra(.selector)
    #expect(p.punteroSale(.barra) == .ninguna)
    #expect(p.venceOcultar() == .ninguna)
    #expect(p.punteroSale(.selector) == .programarOcultar(0.6))
}

// MARK: Política de visibilidad

@Test("Visibilidad: al tocar el borde aparece, se queda mientras el puntero esté dentro y se oculta 0,6 s después")
func visibilidadBorde() {
    var p = PoliticaDock(modo: .alTocarBorde)
    #expect(!p.visible)
    #expect(p.bordeSostenido() == .mostrar)
    #expect(p.visible)
    #expect(p.bordeSostenido() == .ninguna)
    #expect(p.punteroEntra(.barra) == .cancelarOcultar)
    #expect(p.venceOcultar() == .ninguna)
    #expect(p.punteroSale(.barra) == .programarOcultar(0.6))
    #expect(p.venceOcultar() == .ocultar)
    #expect(!p.visible)
}

@Test("Visibilidad: un panel de carpeta abierto mantiene el Dock aunque el puntero salga de la barra")
func visibilidadPanel() {
    var p = PoliticaDock(modo: .alTocarBorde)
    _ = p.bordeSostenido()
    _ = p.punteroEntra(.barra)
    _ = p.punteroEntra(.panel)
    #expect(p.punteroSale(.barra) == .ninguna)      // sigue sobre el panel
    #expect(p.venceOcultar() == .ninguna)
    #expect(p.visible)
    #expect(p.punteroSale(.panel) == .programarOcultar(0.6))
    #expect(p.venceOcultar() == .ocultar)
}

@Test("Visibilidad: un menú abierto lo mantiene y al cerrarse se revisa; volver a entrar cancela")
func visibilidadMenu() {
    var p = PoliticaDock(modo: .alTocarBorde)
    _ = p.bordeSostenido()
    _ = p.punteroEntra(.barra)
    #expect(p.menu(abierto: true) == .cancelarOcultar)
    _ = p.punteroSale(.barra)
    #expect(p.venceOcultar() == .ninguna)
    #expect(p.menu(abierto: false) == .programarOcultar(0.6))
    #expect(p.punteroEntra(.barra) == .cancelarOcultar)
    #expect(p.venceOcultar() == .ninguna)
    #expect(p.visible)
}

@Test("Visibilidad: siempre visible nunca se oculta sola; el atajo la esconde y la vuelve a mostrar")
func visibilidadSiempre() {
    var p = PoliticaDock(modo: .siempre)
    #expect(p.visible)
    _ = p.punteroEntra(.barra)
    #expect(p.punteroSale(.barra) == .ninguna)
    #expect(p.venceOcultar() == .ninguna)
    #expect(p.alternarAtajo() == .ocultar)
    #expect(!p.visible)
    #expect(p.alternarAtajo() == .mostrar)
    #expect(p.visible)
}

@Test("Visibilidad: el atajo en modo borde la muestra fija y otra vez la esconde")
func visibilidadAtajo() {
    var p = PoliticaDock(modo: .alTocarBorde)
    #expect(p.alternarAtajo() == .mostrar)
    #expect(p.fija)
    _ = p.punteroEntra(.barra)
    #expect(p.punteroSale(.barra) == .ninguna)
    #expect(p.venceOcultar() == .ninguna)
    #expect(p.alternarAtajo() == .ocultar)
    #expect(!p.visible && !p.fija)
}

@Test("Visibilidad: cambiar de modo; a siempre la muestra, y a borde sin puntero la programa para ocultar")
func visibilidadCambioDeModo() {
    var p = PoliticaDock(modo: .alTocarBorde)
    _ = p.bordeSostenido()
    #expect(p.cambiarModo(.siempre) == .mostrar)
    #expect(p.cambiarModo(.alTocarBorde) == .programarOcultar(0.6))
    #expect(p.cambiarModo(.alTocarBorde) == .ninguna)
    var q = PoliticaDock(modo: .alTocarBorde)
    #expect(q.punteroSale(.barra) == .ninguna)
}

// MARK: Tonos del fondo

private func m(_ r: Double, _ g: Double, _ b: Double) -> MuestraColor { MuestraColor(r: r, g: g, b: b) }
private func canales(_ h: UInt32) -> (Double, Double, Double) { (Double((h >> 16) & 0xFF) / 255, Double((h >> 8) & 0xFF) / 255, Double(h & 0xFF) / 255) }

@Test("Fondo: la base sale del cuarto más oscuro y nunca pasa de 20 % de brillo")
func fondoBase() throws {
    let muestras = [m(0.9, 0.9, 0.95), m(0.8, 0.85, 0.9), m(0.05, 0.1, 0.4), m(0.1, 0.15, 0.5), m(0.95, 0.6, 0.2), m(0.9, 0.9, 0.9), m(0.7, 0.7, 0.8), m(0.02, 0.05, 0.3)]
    let t = try #require(AnalisisFondo.derivar(muestras))
    let (r, g, b) = canales(t.hondo)
    #expect(max(r, g, b) <= AnalisisFondo.brilloMaximoBase + 0.01)
    #expect(max(r, g, b) >= AnalisisFondo.brilloMinimoBase - 0.01)
    #expect(b > r)
}

@Test("Fondo: un fondo casi blanco igual da una base oscura; un fondo de un solo tono da dos colores distintos")
func fondoClaroYUnTono() throws {
    let claro = try #require(AnalisisFondo.derivar([m(0.95, 0.95, 0.95), m(0.9, 0.92, 0.96), m(0.85, 0.85, 0.9), m(0.9, 0.9, 0.9)]))
    let (r, g, b) = canales(claro.hondo)
    #expect(max(r, g, b) <= 0.21)
    let rojo = try #require(AnalisisFondo.derivar([m(0.8, 0.1, 0.1), m(0.9, 0.2, 0.15), m(0.6, 0.05, 0.05), m(0.85, 0.12, 0.1)]))
    #expect(rojo.c2 != rojo.c1)
}

@Test("Fondo: el segundo color es el vivo de tono más lejano; sin muestras no hay tonos")
func fondoDosColores() throws {
    let t = try #require(AnalisisFondo.derivar([m(0.1, 0.1, 0.2), m(0.9, 0.2, 0.1), m(0.1, 0.4, 0.95), m(0.05, 0.05, 0.1)]))
    let (r1, _, b1) = canales(t.c1)
    let (r2, _, b2) = canales(t.c2)
    #expect((r1 > b1) != (r2 > b2))
    #expect(AnalisisFondo.derivar([]) == nil)
}

// MARK: Carpetas

private func arch(_ n: String, _ dias: Int, carpeta: Bool = false) -> ArchivoReciente {
    ArchivoReciente(nombre: n, ruta: "/x/" + n, modificado: f(16, 9).addingTimeInterval(-Double(dias) * 86_400), esCarpeta: carpeta)
}

@Test("Carpeta: lo más reciente primero, sin ocultos, con desempate por nombre")
func carpetaOrden() {
    let r = CarpetaDock.masRecientes([arch("b.pdf", 2), arch(".DS_Store", 0), arch("a.pdf", 2), arch("nuevo.png", 0), arch("viejo.txt", 30)])
    #expect(r.map(\.nombre) == ["nuevo.png", "a.pdf", "b.pdf", "viejo.txt"])
}

@Test("Carpeta: tope de 40 y filas de cinco")
func carpetaTope() {
    let muchos = (0..<100).map { arch("f\($0)", $0) }
    let r = CarpetaDock.masRecientes(muchos)
    #expect(r.count == 40 && r[0].nombre == "f0" && r[39].nombre == "f39")
    #expect(CarpetaDock.masRecientes(muchos, maximo: 0).isEmpty)
    #expect(CarpetaDock.filas(40) == 8 && CarpetaDock.filas(41) == 9 && CarpetaDock.filas(0) == 0 && CarpetaDock.filas(1) == 1)
}

@Test("Carpeta: el sello va en mayúsculas y se corta; la antigüedad se dice corto")
func carpetaTextos() {
    #expect(CarpetaDock.sello("/Users/ana/Downloads") == "DOWNLOADS")
    #expect(CarpetaDock.sello("/x/UnaCarpetaMuyLargaDeVerdad") == "UNACARPETAM…")
    let ahora = f(16, 12)
    #expect(CarpetaDock.hace(ahora.addingTimeInterval(-20), ahora: ahora) == "ahora")
    #expect(CarpetaDock.hace(ahora.addingTimeInterval(-5 * 60), ahora: ahora) == "hace 5 min")
    #expect(CarpetaDock.hace(ahora.addingTimeInterval(-3 * 3600), ahora: ahora) == "hace 3 h")
    #expect(CarpetaDock.hace(ahora.addingTimeInterval(-30 * 3600), ahora: ahora) == "ayer")
    #expect(CarpetaDock.hace(ahora.addingTimeInterval(-4 * 86_400), ahora: ahora) == "hace 4 d")
}

// MARK: Mejoras del Dock (noviembre)

@Test("Dock: la barra se pega al borde de abajo salvo que el Dock del sistema esté abajo y fijo")
func dockColocacion() {
    let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visible = CGRect(x: 0, y: 80, width: 1512, height: 869)
    #expect(ColocacionDock.base(frame: frame, visible: visible, dockSistemaAbajoFijo: false) == 0)
    #expect(ColocacionDock.base(frame: frame, visible: visible, dockSistemaAbajoFijo: true) == 80)
    // visibleFrame sin sentido (negativo o enorme): nunca deja un hueco ni se sale
    #expect(ColocacionDock.reservaInferior(frame: frame, visible: CGRect(x: 0, y: -30, width: 1, height: 1), dockSistemaAbajoFijo: true) == 0)
    #expect(ColocacionDock.reservaInferior(frame: frame, visible: CGRect(x: 0, y: 700, width: 1, height: 1), dockSistemaAbajoFijo: true) == 160)
    // otra pantalla con origen distinto
    let lateral = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
    #expect(ColocacionDock.base(frame: lateral, visible: CGRect(x: 1512, y: -200, width: 1920, height: 1050), dockSistemaAbajoFijo: true) == -200)
}

@Test("Dock: el Dock del sistema reserva abajo solo si está abajo y no se oculta solo")
func dockSistemaReserva() {
    #expect(ColocacionDock.dockSistemaAbajoFijo(orientacion: "bottom", autohide: false))
    #expect(ColocacionDock.dockSistemaAbajoFijo(orientacion: nil, autohide: nil))
    #expect(!ColocacionDock.dockSistemaAbajoFijo(orientacion: "bottom", autohide: true))
    #expect(!ColocacionDock.dockSistemaAbajoFijo(orientacion: "left", autohide: false))
}

@Test("Iconos propios: nombre o identificador a un PNG, con ~ y comentarios")
func iconosPropios() {
    let m = IconosPersonalizados.leer("# x\nCra = ~/iconos/cra.png\ncom.foo.Bar=/tmp/b.png\nmala\n = /x", home: casa)
    #expect(m["cra"] == casa + "/iconos/cra.png")
    #expect(IconosPersonalizados.ruta(EntradaApp(nombre: "Cra", ruta: "/Applications/Cra.app", bundleID: "dk.kildahl.cra"), en: m) == casa + "/iconos/cra.png")
    #expect(IconosPersonalizados.ruta(EntradaApp(nombre: "Otra", ruta: "/x", bundleID: "com.foo.Bar"), en: m) == "/tmp/b.png")
    #expect(IconosPersonalizados.ruta(EntradaApp(nombre: "Z", ruta: "/z"), en: m) == nil)
}

@Test("Papelera: llena si el listado trae algo que no sea .DS_Store; sin permiso, por la cuenta del sistema")
func papeleraLlena() {
    #expect(!EstadoPapelera.llena(listado: [".DS_Store"], entradas: 9))
    #expect(EstadoPapelera.llena(listado: [".DS_Store", "a.txt"], entradas: nil))
    #expect(!EstadoPapelera.llena(listado: [], entradas: nil))
    #expect(EstadoPapelera.llena(listado: nil, entradas: 4))
    #expect(!EstadoPapelera.llena(listado: nil, entradas: 1))
    #expect(!EstadoPapelera.llena(listado: nil, entradas: nil))
}

@Test("Dock: abiertas y finder se leen y se escriben; serializar es la inversa de analizar")
func dockAbiertasFinder() {
    let p = ReglasDock.analizar("reloj, WhatsApp, | abiertas, | carpeta:~/Downloads, finder, papelera", home: casa)
    #expect(p == [.reloj, .app("WhatsApp"), .hueco, .abiertas, .hueco, .carpeta(casa + "/Downloads"), .finder, .papelera])
    let texto = ReglasDock.serializar(p, home: casa)
    #expect(texto == "reloj, WhatsApp | abiertas | carpeta:~/Downloads, finder, papelera")
    #expect(ReglasDock.analizar(texto, home: casa) == p)
    #expect(MedidasDock.ancho(.finder) == 0 && MedidasDock.ancho(.abiertas) == 72)
}

@Test("Dock: fijar y quitar una app de la línea; reemplazar solo la línea dock del espacio")
func dockAlternarApp() {
    let base: [PiezaDock] = [.reloj, .hueco, .app("Claude"), .hueco, .papelera]
    let con = ReglasDock.alternarApp(base, id: "net.whatsapp.WhatsApp")
    #expect(con == [.reloj, .hueco, .app("Claude"), .app("net.whatsapp.WhatsApp"), .hueco, .papelera])
    #expect(ReglasDock.tieneApp(con, id: "net.whatsapp.WhatsApp"))
    #expect(ReglasDock.alternarApp(con, id: "net.whatsapp.WhatsApp") == base)
    let t = "[A]\nvelo: no\n\n[B]\ndock: reloj\nfoco: 5\n"
    let r = ReglasDock.reemplazarLineaDock(en: t, espacio: "A", por: "papelera")
    #expect(r == "[A]\nvelo: no\ndock: papelera\n\n[B]\ndock: reloj\nfoco: 5\n")
    #expect(ReglasDock.reemplazarLineaDock(en: t, espacio: "B", por: "mac").contains("dock: mac\nfoco: 5"))
    #expect(ReglasDock.reemplazarLineaDock(en: t, espacio: "Z", por: "x") == t)
}

@Test("Pila: abanico con pocos elementos, cuadrícula con muchos; la preferencia manda")
func pilaModo() {
    #expect(PilaDock.modo(cuantos: 5) == .abanico)
    #expect(PilaDock.modo(cuantos: 9) == .cuadricula)
    #expect(PilaDock.modo(cuantos: 0) == .cuadricula)
    #expect(PilaDock.modo(cuantos: 30, preferencia: "abanico") == .abanico)
    #expect(PilaDock.modo(cuantos: 3, preferencia: "cuadricula") == .cuadricula)
    #expect(PilaDock.abanico(indice: 0, de: 5).desvio == 0)
    #expect(PilaDock.abanico(indice: 4, de: 5).desvio > PilaDock.abanico(indice: 2, de: 5).desvio)
}

@Test("Panel: las flechas mueven la selección sin salirse; en el abanico arriba sube al siguiente")
func panelNavegacion() {
    #expect(NavegacionPanel.mover(nil, paso: .derecha, total: 12, columnas: 5) == 0)
    #expect(NavegacionPanel.mover(0, paso: .derecha, total: 12, columnas: 5) == 1)
    #expect(NavegacionPanel.mover(0, paso: .izquierda, total: 12, columnas: 5) == 0)
    #expect(NavegacionPanel.mover(2, paso: .abajo, total: 12, columnas: 5) == 7)
    #expect(NavegacionPanel.mover(9, paso: .abajo, total: 12, columnas: 5) == 9)
    #expect(NavegacionPanel.mover(7, paso: .arriba, total: 12, columnas: 5) == 2)
    #expect(NavegacionPanel.mover(0, paso: .arriba, total: 6, columnas: 1, abanico: true) == 1)
    #expect(NavegacionPanel.mover(5, paso: .arriba, total: 6, columnas: 1, abanico: true) == 5)
    #expect(NavegacionPanel.mover(0, paso: .abajo, total: 6, columnas: 1, abanico: true) == 0)
    #expect(NavegacionPanel.mover(3, paso: .abajo, total: 0, columnas: 5) == nil)
}

@Test("Finder: de los documentos de las ventanas salen carpetas únicas, sin la personal ni las fijas")
func finderRutas() {
    let docs = ["file:///Users/ana/Docs/", "file:///Users/ana/Docs", "file:///Users/ana/", "file:///", "file:///Users/ana/Fija/", "file:///Users/ana/Mi%20Carpeta/", "no es url", "file:///Users/ana/archivo.txt"]
    let r = FinderAbiertas.rutas(documentos: docs, fijas: ["/Users/ana/Fija"], home: casa, esCarpeta: { !$0.hasSuffix(".txt") })
    #expect(r == ["/Users/ana/Docs", "/Users/ana/Mi Carpeta"])
}

@Test("Reloj de tarjetas: hora de 1 a 12 sin cero, minutos de dos cifras y AM/PM")
func relojTarjetas() {
    #expect(RelojTarjetas.partes(hora24: 0, minuto: 5) == ("12", "05", "AM"))
    #expect(RelojTarjetas.partes(hora24: 14, minuto: 48) == ("2", "48", "PM"))
    #expect(RelojTarjetas.partes(hora24: 12, minuto: 0) == ("12", "00", "PM"))
}
