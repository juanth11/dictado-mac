import Testing
@testable import DictadoKit

private func app(_ nombre: String, _ id: String? = nil, _ ruta: String? = nil) -> EntradaApp {
    EntradaApp(nombre: nombre, ruta: ruta ?? "/Applications/\(nombre).app", bundleID: id)
}
private func nombres(_ l: [EntradaApp]) -> [String] { l.map(\.nombre) }

@Test("Normalizar quita tildes, mayúsculas y espacios de sobra")
func lanz_normalizarTexto() {
    #expect(BusquedaApps.normalizar("  Cálculo   RÁPIDO ") == "calculo rapido")
    #expect(BusquedaApps.normalizar("Ñandú") == "nandu")
}

@Test("Depurar: la misma app por identificador de paquete queda una sola vez, gana la primera")
func lanz_depurarRepetidas() {
    let l = BusquedaApps.depurar([
        app("Safari", "com.apple.Safari", "/Applications/Safari.app"),
        app("Safari", "com.apple.Safari", "/System/Applications/Safari.app"),
        app("Notas", "com.apple.Notes"),
    ])
    #expect(nombres(l) == ["Notas", "Safari"])
    #expect(l.last?.ruta == "/Applications/Safari.app")
}

@Test("Depurar: sin identificador manda la ruta; sin nombre se descarta")
func lanz_depurarSinIdentificador() {
    let l = BusquedaApps.depurar([app("Uno", nil, "/a/Uno.app"), app("Uno", nil, "/a/Uno.app"), app("Uno", nil, "/b/Uno.app"), app("")])
    #expect(l.count == 2)
}

@Test("Depurar ordena por nombre sin tildes ni mayúsculas")
func lanz_depurarOrden() {
    let l = BusquedaApps.depurar([app("zoom", "z"), app("Álbum", "a"), app("Calendario", "c"), app("Aa", "b")])
    #expect(nombres(l) == ["Aa", "Álbum", "Calendario", "zoom"])
}

@Test("Ocultas: se quitan por identificador")
func lanz_ocultas() {
    let l = [app("A", "a"), app("B", "b")]
    #expect(nombres(BusquedaApps.sinOcultas(l, ocultas: ["b"])) == ["A"])
    #expect(BusquedaApps.sinOcultas(l, ocultas: []).count == 2)
}

@Test("Búsqueda sin tildes ni mayúsculas")
func lanz_busquedaInsensible() {
    let l = [app("Cálculo", "c"), app("Calendario", "d")]
    #expect(nombres(BusquedaApps.filtrar(l, consulta: "CALCU")) == ["Cálculo"])
    #expect(nombres(BusquedaApps.filtrar(l, consulta: "calculó")) == ["Cálculo"])
}

@Test("Búsqueda: prefijo, luego inicio de palabra, luego en medio")
func lanz_busquedaRango() {
    let l = BusquedaApps.depurar([app("Monitor de actividad", "1"), app("Mapas", "2"), app("Activity Monitor", "3"), app("Ratón y Monitores", "4"), app("Ajustes del Sistema", "5"), app("Smonitor", "6")])
    #expect(nombres(BusquedaApps.filtrar(l, consulta: "mon")) == ["Monitor de actividad", "Activity Monitor", "Ratón y Monitores", "Smonitor"])
}

@Test("Búsqueda: varias palabras abren varias palabras, en orden")
func lanz_busquedaVariasPalabras() {
    let l = [app("Google Chrome", "g"), app("Chrome Google", "h")]
    #expect(nombres(BusquedaApps.filtrar(l, consulta: "goo chr")) == ["Google Chrome"])
    #expect(BusquedaApps.puntaje(nombre: "Google Chrome", consulta: "chr goo") == nil)
}

@Test("Búsqueda vacía devuelve todo; sin coincidencias, nada")
func lanz_busquedaVacia() {
    let l = [app("A", "a"), app("B", "b")]
    #expect(BusquedaApps.filtrar(l, consulta: "   ").count == 2)
    #expect(BusquedaApps.filtrar(l, consulta: "zzz").isEmpty)
}

@Test("Búsqueda: los nombres de atajos se filtran igual que las apps (mejores primero, sin consulta ninguno)")
func filtrarNombresDeAtajos() {
    let atajos = ["Apagar las luces", "Resumen del día", "Reunión en 5", "Modo concentración"]
    #expect(BusquedaApps.filtrarNombres(atajos, consulta: "re") == ["Resumen del día", "Reunión en 5"])
    #expect(BusquedaApps.filtrarNombres(atajos, consulta: "LUCES") == ["Apagar las luces"])
    #expect(BusquedaApps.filtrarNombres(atajos, consulta: "").isEmpty)
    #expect(BusquedaApps.filtrarNombres(atajos, consulta: "zzz").isEmpty)
}
