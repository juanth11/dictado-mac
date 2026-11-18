import AppKit

let argumentos = CommandLine.arguments
// Prueba de las notas de reunión sin grabar: arma las notas de una transcripción de ejemplo con el resumen de Claude Code.
// `--probar-notas-reunion [carpeta]` (por omisión, la carpeta de reuniones de los ajustes).
if argumentos.count > 1, argumentos[1] == "--probar-notas-reunion" {
    if argumentos.count > 2 { UserDefaults.dictado.set(argumentos[2], forKey: "reunionesCarpeta") }
    print("Claude Code: " + (ResumenReunion.claude?.path ?? "no está instalado (solo quedará la transcripción)"))
    let ejemplo = """
    # Prueba de Dictado

    - Inicio: 2026-11-17 10:00 · duración: 2 min

    [00:00] Tú: Hola, ¿me escuchan? Esta es una prueba de las notas de reunión.

    [00:05] Otros: Sí, te escuchamos. Quedamos en enviar la propuesta el viernes.

    [00:12] Tú: Perfecto, yo la envío el viernes y la revisamos el lunes.
    """
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dictado-prueba-notas.md")
    try? ejemplo.write(to: tmp, atomically: true, encoding: .utf8)
    let (aviso, bien) = ResumenReunion.guardar(transcripcion: tmp, titulo: "Prueba de Dictado", inicio: Date())
    try? FileManager.default.removeItem(at: tmp)
    print(aviso)
    print("Carpeta: " + ResumenReunion.carpeta.path)
    if argumentos.count > 2 { UserDefaults.dictado.removeObject(forKey: "reunionesCarpeta") }
    exit(bien ? 0 : 1)
}
// SwiftUI necesita renderizar en el hilo principal, sin saltos asíncronos.
if argumentos.count > 2, argumentos[1] == "--animaciones" {
    let ok = MainActor.assumeIsolated { animaciones(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-halo" {
    let ok = MainActor.assumeIsolated { hojaHalo(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 1, argumentos[1] == "--abrir-centro" {
    pedirAbrirCentro()
    exit(0)
}
if argumentos.count > 2, argumentos[1] == "--vista-centro2" {
    let ok = MainActor.assumeIsolated { hojaCentro2(URL(fileURLWithPath: argumentos[2]), escena: argumentos.count > 3 ? argumentos[3] : nil) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-centro-real" {
    let ok = MainActor.assumeIsolated { hojaCentroReal(URL(fileURLWithPath: argumentos[2]), escena: argumentos.count > 3 ? argumentos[3] : nil) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--probar-ventana-centro" {
    let ok = MainActor.assumeIsolated { probarVentanaCentro(URL(fileURLWithPath: argumentos[2]), escena: argumentos.count > 3 ? argumentos[3] : nil) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-centro" {
    let ok = MainActor.assumeIsolated { hojaCentro(URL(fileURLWithPath: argumentos[2]), escena: argumentos.count > 3 ? argumentos[3] : nil) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 1, argumentos[1] == "--probar-centro-memoria" {
    let ok = MainActor.assumeIsolated { probarCentroMemoria(ciclos: argumentos.count > 2 ? Int(argumentos[2]) ?? 30 : 30) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-lanzador" {
    let ok = MainActor.assumeIsolated { hojaLanzador(URL(fileURLWithPath: argumentos[2]), escena: argumentos.count > 3 ? argumentos[3] : nil) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 1, argumentos[1] == "--probar-lanzador-memoria" {
    let ok = MainActor.assumeIsolated { probarLanzadorMemoria(ciclos: argumentos.count > 2 ? Int(argumentos[2]) ?? 30 : 30) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 1, argumentos[1] == "--probar-fondos" {
    let ok = MainActor.assumeIsolated { probarFondos(sacar: argumentos.count > 2 && argumentos[2] == "sacar") }
    exit(ok ? 0 : 1)
}
if argumentos.count > 1, argumentos[1] == "--restaurar-dock" {
    exit(restaurarDockSistemaCLI())
}
if argumentos.count > 2, argumentos[1] == "--vista-isla" {
    let ok = MainActor.assumeIsolated { hojaIsla(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-icono-apps" {
    let ok = MainActor.assumeIsolated { hojaIconoApps(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-dock" {
    let ok = MainActor.assumeIsolated { hojaDock(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-selector" {
    let ok = MainActor.assumeIsolated { hojaSelector(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-espacios" {
    let ok = MainActor.assumeIsolated { hojaEspacios(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 1, argumentos[1] == "--probar-dock-memoria" {
    let ok = MainActor.assumeIsolated { probarDockMemoria() }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-agentes" {
    let ok = MainActor.assumeIsolated { hojaIsla(URL(fileURLWithPath: argumentos[2]), soloAgentes: true) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--foto-real" {
    let ok = MainActor.assumeIsolated { fotoReal(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 4, argumentos[1] == "--comparar" {
    let ok = MainActor.assumeIsolated {
        hojaComparar(URL(fileURLWithPath: argumentos[2]), variante: argumentos[3], foto: URL(fileURLWithPath: argumentos[4]))
    }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-verme" {
    let ok = MainActor.assumeIsolated { hojaVerme(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-salud" {
    let ok = MainActor.assumeIsolated { hojaSalud(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-captura" {
    let ok = MainActor.assumeIsolated { hojaCaptura(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 1, argumentos[1] == "--probar-portapapeles" {
    let ok = MainActor.assumeIsolated { probarPortapapeles() }
    exit(ok ? 0 : 1)
}
if argumentos.count > 1, argumentos[1] == "--probar-papelera" {
    exit(probarPapelera() ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-portapapeles" {
    let ok = MainActor.assumeIsolated { hojaPortapapeles(URL(fileURLWithPath: argumentos[2]), modoLista: argumentos.count > 3) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--estilos" {
    let lista = argumentos.count > 3 ? argumentos[3].split(separator: ",").compactMap { Estilo(rawValue: String($0)) } : Estilo.allCases
    let ok = MainActor.assumeIsolated { hojaEstilos(URL(fileURLWithPath: argumentos[2]), estilos: lista) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-hud" {
    let ok = MainActor.assumeIsolated { hojaHUD(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-acciones" {
    let ok = MainActor.assumeIsolated { hojaAcciones(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
if argumentos.count > 1, argumentos[1] == "--teclas-wav" {
    exit(renderTeclasWAV(URL(fileURLWithPath: argumentos.count > 2 ? argumentos[2] : "/tmp/dictado-teclas")) ? 0 : 1)
}
if argumentos.count > 3, argumentos[1] == "--teclado-wav" {
    exit(cortarTecladoDeArchivo(wav: URL(fileURLWithPath: argumentos[2]), json: URL(fileURLWithPath: argumentos[3]),
                                carpeta: URL(fileURLWithPath: argumentos.count > 4 ? argumentos[4] : "/tmp/dictado-mi-teclado")))
}
if argumentos.count > 2, argumentos[1] == "--teclado-demo" {
    exit(escribirTecladoDemo(URL(fileURLWithPath: argumentos[2])) ? 0 : 1)
}
if argumentos.count > 2, argumentos[1] == "--vista-teclado" {
    let ok = MainActor.assumeIsolated { hojaGrabarTeclado(URL(fileURLWithPath: argumentos[2])) }
    exit(ok ? 0 : 1)
}
// Tecla hyper, ventanas por teclado y buscador (PruebasTeclado.swift).
if let codigo = MainActor.assumeIsolated({ cliTeclado(argumentos) }) { exit(codigo) }
if argumentos.count > 1, argumentos[1].hasPrefix("--") {
    Task {
        let codigo = await CLI.ejecutar(argumentos)
        exit(codigo)
    }
    dispatchMain()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegado = App()
    app.delegate = delegado
    app.setActivationPolicy(.accessory)
    app.run()
}
