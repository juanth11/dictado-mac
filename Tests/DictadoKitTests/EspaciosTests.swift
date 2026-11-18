import Testing
@testable import DictadoKit

private let cal = calendarioDePrueba()

@Test("Espacios: las líneas nuevas (paleta, abrir, reproducir, titulo, fondo) se leen")
func espaciosLineasNuevas() {
    let e = EspaciosIsla.leer("""
    [Personal]
    titulo: Lo tuyo
    fondo: /System/Library/Desktop Pictures/iMac Pink.heic
    paleta: ciruelaCoral
    abrir: Spotify, Fotos
    reproducir: spotify
    al entrar: Modo personal
    """)
    #expect(e.count == 1)
    #expect(e[0].titulo == "Lo tuyo")
    #expect(e[0].paleta == "ciruelaCoral")
    #expect(e[0].abrir == ["Spotify", "Fotos"])
    #expect(e[0].reproducir == "spotify")
    #expect(e[0].rutaFondoDePantalla(home: "/h") == "/System/Library/Desktop Pictures/iMac Pink.heic")
    #expect(e[0].accionesAlEntrar == [.abrir("Spotify"), .abrir("Fotos"), .reproducir("spotify"), .atajo("Modo personal")])
}

@Test("Espacios: una paleta desconocida se ignora y 'mac' o 'paleta:' no cambian el fondo de pantalla")
func espaciosPaletaYFondoSinImagen() {
    let e = EspaciosIsla.leer("[A]\npaleta: rosaFlúor\nfondo: mac\n[B]\nfondo: paleta:bosqueLima\n[C]\nreproducir: no")
    #expect(e[0].paleta == nil && e[0].rutaFondoDePantalla() == nil)
    #expect(e[1].rutaFondoDePantalla() == nil)
    #expect(e[2].reproducir == nil)
}

@Test("Reproducir: solo apps conocidas y el script no lleva nada del archivo")
func reproducirSoloConocidas() {
    #expect(ReproducirApp.script("Spotify") == "tell application \"Spotify\" to play")
    #expect(ReproducirApp.script("Música") == "tell application \"Music\" to play")
    #expect(ReproducirApp.script("Spotify\" to quit") == nil)
    let e = EspacioIsla(nombre: "X", reproducir: "Safari")
    #expect(e.accionesAlEntrar.isEmpty)
}

@Test("Espacios: Hyper + número, siguiente y anterior dan la vuelta")
func espaciosDestinos() {
    let n = ["Mañana", "Trabajo", "Foco", "Personal", "Juego"]
    #expect(EspaciosIsla.resolver(.numero(1), nombres: n, actual: nil) == 0)
    #expect(EspaciosIsla.resolver(.numero(5), nombres: n, actual: "Foco") == 4)
    #expect(EspaciosIsla.resolver(.numero(6), nombres: n, actual: nil) == nil)
    #expect(EspaciosIsla.resolver(.numero(0), nombres: n, actual: nil) == nil)
    #expect(EspaciosIsla.resolver(.siguiente, nombres: n, actual: "Juego") == 0)
    #expect(EspaciosIsla.resolver(.anterior, nombres: n, actual: "Mañana") == 4)
    #expect(EspaciosIsla.resolver(.siguiente, nombres: n, actual: nil) == 0)
    #expect(EspaciosIsla.resolver(.anterior, nombres: n, actual: nil) == 4)
    #expect(EspaciosIsla.resolver(.siguiente, nombres: [], actual: nil) == nil)
}

@Test("Espacios sugeridos: cinco, cada uno con fondo, paleta y Dock propios; Mañana lleva el plan")
func espaciosSugeridos() {
    let e = EspaciosIsla.leer(EspaciosIsla.sugeridos)
    #expect(e.map(\.nombre) == ["Mañana", "Trabajo", "Foco", "Personal", "Juego"])
    #expect(e.allSatisfy { $0.paleta != nil && $0.dock != nil && $0.titulo != nil && $0.fondo != nil })
    #expect(Set(e.compactMap(\.paleta)).count == 5)
    #expect(Set(e.compactMap(\.fondo)).count == 5)
    #expect(e[2].fondo == "aereo:Patagonia" && e[4].fondo == "Radial Sky Blue")
    #expect(e[0].piezasDock(masUsadas: []).contains(.plan) && e[0].piezasDock(masUsadas: []).contains(.agentes))
    #expect(e[2].foco == 25 && e[2].velo == .encendido("ambiente"))
    #expect(e[3].accionesAlEntrar == [.abrir("Spotify"), .reproducir("spotify")])
    let dockTrabajo = "lanzador, reloj, agenda, agentes, | Claude, Spotify, WhatsApp, Safari, abiertas | finder, carpeta:~/Downloads, carpeta:~/Documents/Proyectos, carpeta:~/Documents/Lumina, papelera"
    #expect(e[1].dock == dockTrabajo)
}

@Test("Dock: la pieza plan se lee, se escribe y no se confunde con una app")
func dockPiezaPlan() {
    #expect(ReglasDock.analizar("reloj, plan, agentes", home: "/h") == [.reloj, .plan, .agentes])
    #expect(ReglasDock.serializar([.reloj, .plan, .agentes], home: "/h") == "reloj, plan, agentes")
    #expect(ReglasDock.analizar("app:Plan", home: "/h") == [.app("Plan")])
}

// MARK: Plan de Mañana

@Test("Plan: lo vencido y lo de hoy van a hoy; mañana al domingo, a la semana; lo posterior no se muestra")
func planReparto() {
    let ahora = f(18, 8)   // miércoles
    let items = [
        ItemPlan(texto: "Vencida", vence: f(16, 9), origen: .tarea),
        ItemPlan(texto: "Hoy tarde", vence: f(18, 17), origen: .recordatorio),
        ItemPlan(texto: "Jueves", vence: f(19, 10), origen: .recordatorio),
        ItemPlan(texto: "Domingo", vence: f(22, 20), origen: .hito),
        ItemPlan(texto: "Lunes que viene", vence: f(23, 9), origen: .hito),
        ItemPlan(texto: "Sin fecha del día", origen: .tarea, delDia: true),
        ItemPlan(texto: "Meta de la semana", origen: .meta),
    ]
    let p = PlanPendientesCalculo.armar(items, ahora: ahora, calendario: cal)
    #expect(p.hoy.map(\.texto) == ["Vencida", "Hoy tarde", "Sin fecha del día"])
    #expect(p.semana.map(\.texto) == ["Jueves", "Domingo", "Meta de la semana"])
    #expect(p.total == 6)
}

@Test("Plan: los textos repetidos cuentan una vez y el vacío es vacío")
func planRepetidos() {
    let p = PlanPendientesCalculo.armar([ItemPlan(texto: "Pagar la cuota", origen: .tarea, delDia: true),
                                     ItemPlan(texto: "pagar la cuota", origen: .recordatorio, delDia: true)], ahora: f(18, 8), calendario: cal)
    #expect(p.hoy.count == 1)
    #expect(PlanPendientesCalculo.armar([], ahora: f(18, 8), calendario: cal) == .vacio)
}

@Test("Metas: de la sección Semana salen las abiertas (no las hechas) y de Hitos los que tienen fecha")
func metasPlan() {
    let texto = """
    ## Mes · octubre
    - [ ] Algo del mes · Sistema

    ## Semana · 41
    - [~] CSV de clientes y base la propuesta T3 · clientes · falta el CSV · 30 %
    - [x] Sí a la fase 0 del VPS · Sistema
    - [ ] Revisar el contrato

    ## Hitos
    - 2026-11-19 · Presentar la propuesta T3 (meta interna)
    - sin fecha · nada
    """
    let items = MetasPlan.items(texto, calendario: cal)
    #expect(items.map(\.texto) == ["CSV de clientes y base la propuesta T3", "Revisar el contrato", "Presentar la propuesta T3 (meta interna)"])
    #expect(items[2].vence != nil && items[2].origen == .hito)
    #expect(items[0].vence == nil && items[0].origen == .meta)
}
