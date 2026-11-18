import Testing
@testable import DictadoKit

// La sección Hoy del Centro: la sección que abre según la hora, si un archivo del día es de hoy, los correos que se muestran, el "hace…", la bandeja
// de Gmail y las citas del día. (Sin `import Foundation`: con las Command Line Tools no puede convivir con Testing; las fechas vienen de AyudasFechas.)

private let cal = calendarioDePrueba()

@Test("Hoy: el Centro abre en Hoy antes del mediodía y en lo de siempre después")
func hoyAbreSegunLaHora() {
    #expect(HoyCentro.abreEnHoy(ahora: f(16, 0, 5), calendario: cal))
    #expect(HoyCentro.abreEnHoy(ahora: f(16, 5, 30), calendario: cal))
    #expect(HoyCentro.abreEnHoy(ahora: f(16, 11, 59), calendario: cal))
    #expect(!HoyCentro.abreEnHoy(ahora: f(16, 12, 0), calendario: cal))
    #expect(!HoyCentro.abreEnHoy(ahora: f(16, 14, 48), calendario: cal))
    #expect(!HoyCentro.abreEnHoy(ahora: f(16, 23, 59), calendario: cal))
}

@Test("Hoy: un archivo es de hoy solo si su día es el de hoy")
func hoyEsDeHoy() {
    let ahora = f(16, 6, 40)
    #expect(HoyCentro.esDeHoy("2026-11-16", ahora: ahora, calendario: cal))
    #expect(HoyCentro.esDeHoy("2026-11-16T05:30:20-05:00", ahora: ahora, calendario: cal))
    #expect(!HoyCentro.esDeHoy("2026-11-15", ahora: ahora, calendario: cal))
    #expect(!HoyCentro.esDeHoy("2026-11-17", ahora: ahora, calendario: cal))
    #expect(!HoyCentro.esDeHoy("", ahora: ahora, calendario: cal))
    #expect(!HoyCentro.esDeHoy(nil, ahora: ahora, calendario: cal))
    #expect(!HoyCentro.esDeHoy("16 nov", ahora: ahora, calendario: cal))
}

@Test("Hoy: la frescura de un archivo dice de hoy, de ayer o de hace N días")
func hoyFrescura() {
    let ahora = f(16, 6, 40)
    #expect(HoyCentro.frescura(dia: f(16, 5, 30), ahora: ahora, calendario: cal) == "de hoy")
    #expect(HoyCentro.frescura(dia: f(15, 23, 0), ahora: ahora, calendario: cal) == "de ayer")
    #expect(HoyCentro.frescura(dia: f(13, 9, 0), ahora: ahora, calendario: cal) == "de hace 3 días")
    #expect(HoyCentro.frescura(dia: f(17, 9, 0), ahora: ahora, calendario: cal) == nil)
    #expect(HoyCentro.frescura(dia: nil, ahora: ahora, calendario: cal) == nil)
}

private func correo(_ de: String, _ asunto: String, _ fecha: Fecha?, sinLeer: Bool = false) -> HoyCentro.Correo {
    HoyCentro.Correo(de: de, asunto: asunto, fecha: fecha, sinLeer: sinLeer, enlace: nil)
}

@Test("Hoy: los correos muestran primero los sin leer y el más reciente, y dicen cuántos faltan")
func hoyCorreosAMostrar() {
    let lista = [
        correo("A", "viejo leído", f(14, 9)),
        correo("B", "reciente leído", f(16, 8)),
        correo("C", "viejo sin leer", f(15, 9), sinLeer: true),
        correo("D", "reciente sin leer", f(16, 7), sinLeer: true),
        correo("E", "sin fecha", nil),
    ]
    let r = HoyCentro.correosAMostrar(lista, total: 16, maximo: 3)
    #expect(r.visibles.map(\.de) == ["D", "C", "B"])
    #expect(r.faltan == 13)   // el total que dice la lectura (16) menos los 3 que se ven
    // Sin total, faltan los de la lista que no caben.
    let s = HoyCentro.correosAMostrar(lista, total: nil, maximo: 4)
    #expect(s.visibles.map(\.de) == ["D", "C", "B", "A"] && s.faltan == 1)
    // Todo cabe: no falta nada. El total menor que la lista no inventa negativos.
    let t = HoyCentro.correosAMostrar(lista, total: 2, maximo: 10)
    #expect(t.visibles.count == 5 && t.faltan == 0)
    // Sin correos.
    let v = HoyCentro.correosAMostrar([], total: 0, maximo: 6)
    #expect(v.visibles.isEmpty && v.faltan == 0)
    // El orden entre iguales es el de la lectura.
    let i = HoyCentro.correosAMostrar([correo("X", "1", nil), correo("Y", "2", nil)], total: nil, maximo: 5)
    #expect(i.visibles.map(\.de) == ["X", "Y"])
}

@Test("Hoy: el tiempo relativo de un correo")
func hoyHace() {
    let ahora = f(16, 12, 0)
    #expect(HoyCentro.hace(ahora, ahora: ahora) == "ahora")
    #expect(HoyCentro.hace(f(16, 11, 30), ahora: ahora) == "hace 30 min")
    #expect(HoyCentro.hace(f(16, 9, 0), ahora: ahora) == "hace 3 h")
    #expect(HoyCentro.hace(f(15, 9, 0), ahora: ahora) == "ayer")
    #expect(HoyCentro.hace(f(13, 9, 0), ahora: ahora) == "hace 3 d")
}

@Test("Hoy: Abrir Gmail va a la bandeja de la misma cuenta que los enlaces de los correos")
func hoyEnlaceBandeja() {
    #expect(HoyCentro.enlaceBandeja(["https://mail.google.com/mail/u/2/#inbox/18c2f"]) == "https://mail.google.com/mail/u/2/#inbox")
    #expect(HoyCentro.enlaceBandeja([nil, "https://mail.google.com/mail/u/0/?tab=rm#all/abc"]) == "https://mail.google.com/mail/u/0/#inbox")
    #expect(HoyCentro.enlaceBandeja(["https://mail.google.com/mail/u/ana@ejemplo.co/#inbox/1"]) == "https://mail.google.com/mail/u/ana@ejemplo.co/#inbox")
    // Sin enlaces, o con enlaces que no son de Gmail, la bandeja a secas.
    #expect(HoyCentro.enlaceBandeja([]) == "https://mail.google.com/mail/#inbox")
    #expect(HoyCentro.enlaceBandeja(["https://ejemplo.co/mail/u/1/"]) == "https://mail.google.com/mail/#inbox")
    #expect(HoyCentro.enlaceBandeja(["https://mail.google.com/mail/u/"]) == "https://mail.google.com/mail/#inbox")
}

private func cita(_ titulo: String, _ h1: Int, _ h2: Int, dia: Int = 16, todo: Bool = false, lugar: String? = nil, video: Bool = false, invitados: Int = 0) -> HoyCentro.Cita {
    HoyCentro.Cita(titulo: titulo, inicio: f(dia, h1), fin: f(dia, h2), todoElDia: todo, lugar: lugar, videollamada: video, invitados: invitados)
}

@Test("Hoy: la agenda del día deja solo lo de hoy, en orden, con lo de todo el día aparte y sin repetidos")
func hoyAgendaDelDia() {
    let citas = [
        cita("Cierre", 15, 16), cita("Comité", 9, 10), cita("Mañana", 9, 10, dia: 17), cita("Festivo", 0, 23, todo: true),
        cita("Comité", 9, 10),   // repetida (el mismo evento leído dos veces)
        cita("Ayer", 9, 10, dia: 15),
    ]
    let r = HoyCentro.delDia(citas, ahora: f(16, 8), calendario: cal)
    #expect(r.conHora.map(\.titulo) == ["Comité", "Cierre"])
    #expect(r.todoElDia.map(\.titulo) == ["Festivo"])
    #expect(HoyCentro.delDia([], ahora: f(16, 8), calendario: cal).conHora.isEmpty)
}

@Test("Hoy: una cita ya pasó, está en curso o falta")
func hoyMomento() {
    let c = cita("Comité", 9, 10)
    #expect(HoyCentro.momento(c, ahora: f(16, 8, 59)) == .luego)
    #expect(HoyCentro.momento(c, ahora: f(16, 9, 0)) == .enCurso)
    #expect(HoyCentro.momento(c, ahora: f(16, 9, 59)) == .enCurso)
    #expect(HoyCentro.momento(c, ahora: f(16, 10, 0)) == .paso)
}

@Test("Hoy: la segunda línea de una cita junta el lugar, los invitados y la videollamada sin inventar")
func hoyDetalleDeCita() {
    #expect(HoyCentro.detalle(cita("A", 9, 10, lugar: "Oficina", invitados: 3)) == "Oficina · 3 invitados")
    #expect(HoyCentro.detalle(cita("B", 9, 10, video: true, invitados: 1)) == "1 invitado")
    #expect(HoyCentro.detalle(cita("C", 9, 10, video: true)) == "Videollamada")
    #expect(HoyCentro.detalle(cita("D", 9, 10, lugar: "  ")) == "")
    #expect(HoyCentro.detalle(cita("E", 9, 10)) == "")
}

@Test("Hoy: Unirse aparece 10 minutos antes y hasta que termina, solo con enlace")
func hoyPuedeUnirse() {
    let c = cita("Comité", 9, 10)
    #expect(!HoyCentro.puedeUnirse(inicio: c.inicio, fin: c.fin, conEnlace: true, ahora: f(16, 8, 49)))
    #expect(HoyCentro.puedeUnirse(inicio: c.inicio, fin: c.fin, conEnlace: true, ahora: f(16, 8, 50)))
    #expect(HoyCentro.puedeUnirse(inicio: c.inicio, fin: c.fin, conEnlace: true, ahora: f(16, 9, 30)))
    #expect(!HoyCentro.puedeUnirse(inicio: c.inicio, fin: c.fin, conEnlace: true, ahora: f(16, 10, 0)))
    #expect(!HoyCentro.puedeUnirse(inicio: c.inicio, fin: c.fin, conEnlace: false, ahora: f(16, 9, 30)))
}
