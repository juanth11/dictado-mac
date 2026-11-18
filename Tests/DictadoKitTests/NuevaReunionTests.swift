import Testing
@testable import DictadoKit

private func reunion(_ invitados: String = "", meet: Bool = false, google: Bool = true, local: Bool = true) -> NuevaReunion {
    NuevaReunion(titulo: " Revisión ", inicio: f(17, 10), duracionMin: 45, calendarioID: "cal", calendarioEsGoogle: google,
                 invitadosTexto: invitados, conMeet: meet, puedeCrearLocal: local)
}

@Test("Sin invitados ni Meet se crea local")
func caminoLocal() {
    let r = reunion()
    #expect(r.camino == .local)
    #expect(r.botonGuardar == "Guardar")
    #expect(r.avisoDelCamino.contains("aquí"))
}

@Test("Con invitados o con Meet se abre Google Calendar")
func caminoGoogle() {
    #expect(reunion("ana@ejemplo.co").camino == .google)
    #expect(reunion(meet: true).camino == .google)
    #expect(reunion(meet: true).botonGuardar == "Abrir en Google")
}

@Test("Si el calendario no es de Google, con invitados se crea local y se avisa que no se envían")
func caminoSinInvitados() {
    let r = reunion("ana@ejemplo.co", google: false)
    #expect(r.camino == .localSinInvitados)
    #expect(r.avisoDelCamino.contains("no se envían"))
}

@Test("Sin acceso para escribir (solo lectura) cae a Google, nunca a local")
func soloLectura() {
    #expect(reunion(local: false).camino == .google)
    #expect(reunion("a@b.co", google: false, local: false).camino == .google)
}

@Test("Los correos se separan por coma, espacio o línea; se limpian, se bajan a minúsculas y no se repiten")
func correos() {
    let r = NuevaReunion.correos("Ana@Ejemplo.co, pedro@x.com; <luz@y.org>\nana@ejemplo.co  mal@ , sin")
    #expect(r.validos == ["ana@ejemplo.co", "pedro@x.com", "luz@y.org"])
    #expect(r.invalidos == ["mal@", "sin"])
    #expect(!reunion("mal@").valida)
    #expect(reunion("mal@").problemas.first?.contains("mal@") == true)
    #expect(reunion("a@b.co").valida)
}

@Test("El enlace de Google lleva título, franja, invitados y la nota de Meet; el título vacío es «Reunión»")
func enlace() {
    let url = reunion("ana@ejemplo.co, pedro@x.com", meet: true).enlaceGoogle(cuenta: "yo@ejemplo.co")?.absoluteString ?? ""
    #expect(url.contains("action=TEMPLATE"))
    #expect(url.contains("text=Revisi"))
    #expect(url.contains("add=ana%40ejemplo.co,pedro%40x.com"))
    #expect(url.contains("details="))
    #expect(url.contains("authuser=yo%40ejemplo.co"))
    #expect(url.contains("dates=20261117T150000Z/20261117T154500Z"))   // 10:00 en Bogotá (UTC−5), 45 min
    #expect(NuevaReunion(titulo: "  ", inicio: f(17, 10)).tituloFinal == "Reunión")
    #expect(!reunion(meet: false).enlaceGoogle()!.absoluteString.contains("details="))
}

@Test("El fin sale de la duración; una duración absurda no es válida")
func fin() {
    #expect(reunion().fin == f(17, 10, 45))
    var r = reunion()
    r.duracionMin = 0
    #expect(!r.valida)
}
