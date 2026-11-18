import Testing
@testable import DictadoKit

private func app(_ nombre: String, _ id: String? = nil) -> EntradaApp { EntradaApp(nombre: nombre, ruta: "/Applications/\(nombre).app", bundleID: id) }

// MARK: Carpetas

@Test("Carpetas: lee [Nombre] y las líneas apps, que se juntan; ignora comentarios y claves ajenas")
func carpetasLeer() {
    let t = """
    # comentario
    [Trabajo]
    apps: Mail, com.apple.Notes
    Apps: Calendario
    otra: cosa

    [Juegos]
    apps:
    []
    """
    let c = CarpetasApps.leer(t)
    #expect(c == [CarpetaApps(nombre: "Trabajo", apps: ["Mail", "com.apple.Notes", "Calendario"]), CarpetaApps(nombre: "Juegos")])
}

@Test("Carpetas: texto() y leer() son inversas")
func carpetasIda() {
    let c = [CarpetaApps(nombre: "A", apps: (1...10).map { "app\($0)" }), CarpetaApps(nombre: "B", apps: ["x"])]
    #expect(CarpetasApps.leer(CarpetasApps.texto(c)) == c)
}

@Test("Carpetas: la categoría decide la carpeta automática")
func carpetasCategorias() {
    #expect(CarpetasApps.carpetaAutomatica(categoria: "public.app-category.productivity", bundleID: nil) == "Trabajo")
    #expect(CarpetasApps.carpetaAutomatica(categoria: "public.app-category.developer-tools", bundleID: nil) == "Desarrollo")
    #expect(CarpetasApps.carpetaAutomatica(categoria: "public.app-category.action-games", bundleID: nil) == "Juegos")
    #expect(CarpetasApps.carpetaAutomatica(categoria: "public.app-category.utilities", bundleID: nil) == "Sistema")
    #expect(CarpetasApps.carpetaAutomatica(categoria: "public.app-category.social-networking", bundleID: nil) == "Comunicación")
    #expect(CarpetasApps.carpetaAutomatica(categoria: "public.app-category.productivity", bundleID: "com.apple.mail") == "Comunicación")
    #expect(CarpetasApps.carpetaAutomatica(categoria: "public.app-category.music", bundleID: nil) == nil)
    #expect(CarpetasApps.carpetaAutomatica(categoria: nil, bundleID: nil) == nil)
}

@Test("Carpetas: agrupar reparte por tema, ordena por nombre y omite las de una sola app")
func carpetasAgrupar() {
    let p = "public.app-category."
    let r = CarpetasApps.agrupar([
        (app("Notas", "com.apple.Notes"), p + "productivity"), (app("Keynote", "com.apple.Keynote"), p + "productivity"),
        (app("Xcode", "com.apple.dt.Xcode"), p + "developer-tools"),
        (app("Terminal", nil), p + "utilities"), (app("Monitor", "com.apple.monitor"), p + "utilities"),
        (app("Fotos", "com.apple.Photos"), nil),
    ])
    #expect(r.map(\.nombre) == ["Trabajo", "Sistema"])
    #expect(r[0].apps == ["com.apple.Keynote", "com.apple.Notes"])
    #expect(r[1].apps == ["com.apple.monitor", "Terminal"])
}

@Test("Carpetas: resolver acepta id o nombre sin tildes, salta lo no instalado y no repite")
func carpetasResolver() {
    let instaladas = [app("Calendario", "com.apple.iCal"), app("Música", "com.apple.Music"), app("Mail", "com.apple.mail")]
    let c = CarpetaApps(nombre: "x", apps: ["musica", "com.apple.mail", "fantasma", "Música", "com.apple.iCal"])
    #expect(CarpetasApps.resolver(c, instaladas: instaladas).map(\.nombre) == ["Música", "Mail", "Calendario"])
}

@Test("Prioridad: lo nombrado va primero en el orden pedido; el resto, estable")
func prioridadOrdenar() {
    let apps = [app("A", "id.a"), app("B", "id.b"), app("C", "id.c"), app("D", "id.d")]
    let r = PrioridadInicio.ordenar(apps, claves: { [$0.nombre, $0.bundleID ?? ""] }, primero: ["id.c", "fantasma", "a"])
    #expect(r.map(\.nombre) == ["C", "A", "B", "D"])
    #expect(PrioridadInicio.ordenar(apps, claves: { [$0.nombre] }, primero: []) == apps)
}

// MARK: Espacios

@Test("Espacios: lee todas las claves, con tildes y variantes")
func espaciosLeer() {
    let e = EspaciosIsla.leer("""
    # nada
    [Foco]
    primero: Notas, Trabajo
    velo: Profundo
    teclas: no
    foco: 40
    Al entrar: Modo concentración

    [Libre]
    velo: sí
    teclas: thock
    foco: 500
    al entrar: ninguno
    """)
    #expect(e.count == 2)
    #expect(e[0] == EspacioIsla(nombre: "Foco", primero: ["Notas", "Trabajo"], velo: .encendido("profundo"), teclas: .apagado, foco: 40,
                                atajo: "Modo concentración"))
    #expect(e[1].velo == .encendido(nil))
    #expect(e[1].teclas == .encendido("thock"))
    #expect(e[1].foco == EspaciosIsla.minutosFocoMaximo)
    #expect(e[1].atajo == nil)
}

@Test("Espacios: sin la línea, el ajuste queda sin cambio")
func espaciosSinCambio() {
    let e = EspaciosIsla.leer("[Solo]\nprimero: Mail")
    #expect(e == [EspacioIsla(nombre: "Solo", primero: ["Mail"])])
}

@Test("Espacios: el archivo inicial trae cuatro espacios; velo y teclas apagados salvo Foco")
func espaciosInicial() {
    let e = EspaciosIsla.leer(EspaciosIsla.inicial)
    #expect(e.map(\.nombre) == ["Trabajo", "Foco", "Mañana", "Descanso"])
    for x in e where x.nombre != "Foco" { #expect(x.velo == .apagado && x.teclas == .apagado && x.foco == nil && x.atajo == nil) }
    let foco = e[1]
    #expect(foco.velo == .encendido("ambiente"))
    #expect(foco.teclas == .apagado)
    #expect(foco.foco == 25)
}

// MARK: Atajos

@Test("Atajos: analizarLista quita vacías y repetidas")
func atajosLista() {
    #expect(AtajosSistema.analizarLista("Uno\n\n  Dos  \nUno\r\nTres\n") == ["Uno", "Dos", "Tres"])
    #expect(AtajosSistema.analizarLista("") == [])
}

@Test("Atajos: sin ajuste, los seis primeros; con ajuste, esos en su orden y solo los que existen")
func atajosElegir() {
    let todos = ["A", "B", "C", "D", "E", "F", "G", "Café"]
    #expect(AtajosSistema.elegir(todos: todos, preferidos: nil) == ["A", "B", "C", "D", "E", "F"])
    #expect(AtajosSistema.elegir(todos: todos, preferidos: ["G", "no existe", "a", "cafe", "G"]) == ["G", "A", "Café"])
    #expect(AtajosSistema.elegir(todos: todos, preferidos: []) == [])
}

@Test("Atajos: la primera línea de stderr con texto, recortada, o el texto fijo")
func atajosError() {
    #expect(AtajosSistema.primeraLinea("\n  Error: no se encontró\nmás") == "Error: no se encontró")
    #expect(AtajosSistema.primeraLinea("  \n") == "El atajo falló")
    #expect(AtajosSistema.primeraLinea(String(repeating: "x", count: 400)).count == 160)
}

@Test("Páginas: cantidad y rango, con una página fuera de rango llevada a la última")
func paginasInicio() {
    #expect(PaginasInicio.cantidad(total: 0, porPagina: 8) == 1)
    #expect(PaginasInicio.cantidad(total: 8, porPagina: 8) == 1)
    #expect(PaginasInicio.cantidad(total: 9, porPagina: 8) == 2)
    #expect(PaginasInicio.rango(pagina: 1, total: 11, porPagina: 8) == 8..<11)
    #expect(PaginasInicio.rango(pagina: 9, total: 11, porPagina: 8) == 8..<11)
    #expect(PaginasInicio.rango(pagina: -2, total: 11, porPagina: 8) == 0..<8)
    #expect(PaginasInicio.rango(pagina: 0, total: 0, porPagina: 8).isEmpty)
}
