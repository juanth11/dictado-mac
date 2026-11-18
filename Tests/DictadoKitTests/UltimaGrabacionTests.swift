import Testing
@testable import DictadoKit

@Test("La última transcripción manda por la marca del nombre, no por quién se tocó después")
func ultimaPorMarca() {
    let c = carpetaTemporal()
    escribirArchivo("a", c, "202611131600-planeacion.md")
    let nueva = escribirArchivo("b", c, "202611161130-comite.md")
    escribirArchivo("c", c, "202611101720-informe.md")
    escribirArchivo("pista", c, "202611161130-comite-tu-000000.caf")
    #expect(UltimaGrabacion.transcripcionMasReciente(en: c)?.lastPathComponent == nueva.lastPathComponent)
}

@Test("Sin transcripciones no hay última, y los enlaces ultima*.md no cuentan como transcripción")
func sinTranscripciones() {
    let c = carpetaTemporal()
    escribirArchivo("x", c, "ultima.md")
    #expect(UltimaGrabacion.transcripcionMasReciente(en: c) == nil)
    #expect(UltimaGrabacion.actualizar(carpeta: c, inbox: nil) == nil)
}

@Test("Actualizar deja ultima.md y ultima-notas.md apuntando a la última transcripción y a su nota")
func enlacesAlDia() {
    let c = carpetaTemporal("reuniones"), inbox = carpetaTemporal("inbox")
    escribirArchivo("viejo", c, "202611131600-planeacion.md")
    let t = escribirArchivo("# Comité\n[00:03] Tú: hola", c, "202611161130-comite.md")
    let nota = escribirArchivo(notaConTranscripcion(t.path), inbox, "reunion-comite-202611161130.md")
    escribirArchivo(notaConTranscripcion("/tmp/otra-cosa.md"), inbox, "reunion-otra-202611171000.md")
    let r = UltimaGrabacion.actualizar(carpeta: c, inbox: inbox)
    #expect(r?.transcripcion == t.path)
    #expect(r?.notas == nota.path)
    #expect(destinoDeEnlace(c.appendingPathComponent("ultima.md")) == t.path)
    #expect(destinoDeEnlace(c.appendingPathComponent("ultima-notas.md")) == nota.path)
    #expect(leerArchivo(c.appendingPathComponent("ultima.md")).contains("Tú: hola"))
}

@Test("Una grabación nueva mueve los enlaces; sin nota, ultima-notas.md se quita")
func enlacesSeMueven() {
    let c = carpetaTemporal("reuniones"), inbox = carpetaTemporal("inbox")
    let t1 = escribirArchivo("uno", c, "202611131600-planeacion.md")
    let n1 = escribirArchivo(notaConTranscripcion(t1.path), inbox, "reunion-planeacion-202611131600.md")
    UltimaGrabacion.actualizar(carpeta: c, inbox: inbox)
    #expect(destinoDeEnlace(c.appendingPathComponent("ultima-notas.md")) == n1.path)
    let t2 = escribirArchivo("dos", c, "202611161130-comite.md")
    let r = UltimaGrabacion.actualizar(carpeta: c, inbox: inbox)
    #expect(destinoDeEnlace(c.appendingPathComponent("ultima.md")) == t2.path)
    #expect(r?.notas == nil)
    #expect(!existeArchivo(c.appendingPathComponent("ultima-notas.md")))
}

@Test("Una nota conocida (la que acaba de crear el cerebro) manda sobre la búsqueda")
func notaConocida() {
    let c = carpetaTemporal("reuniones"), inbox = carpetaTemporal("inbox")
    escribirArchivo("uno", c, "202611161130-comite.md")
    let nota = escribirArchivo("sin frontmatter", inbox, "reunion-comite-202611161130.md")
    let r = UltimaGrabacion.actualizar(carpeta: c, inbox: inbox, nota: nota)
    #expect(r?.notas == nota.path)
}

@Test("No pisa un ultima.md que sea un archivo de verdad")
func noPisaArchivos() {
    let c = carpetaTemporal("reuniones")
    escribirArchivo("uno", c, "202611161130-comite.md")
    let propio = escribirArchivo("mío", c, "ultima.md")
    UltimaGrabacion.actualizar(carpeta: c, inbox: nil)
    #expect(leerArchivo(propio) == "mío")
    #expect(destinoDeEnlace(propio) == nil)
}

@Test("La salida de texto y la de JSON dicen lo mismo")
func salidas() {
    let r = UltimaGrabacion.Rutas(transcripcion: "/t/a.md", notas: nil, enlaceTranscripcion: "/t/ultima.md", enlaceNotas: "/t/ultima-notas.md")
    #expect(UltimaGrabacion.texto(r).contains("transcripción: /t/a.md"))
    #expect(UltimaGrabacion.texto(r).contains("sin notas todavía"))
    #expect(UltimaGrabacion.texto(nil) == "sin grabaciones todavía")
    let j = UltimaGrabacion.json(r)
    #expect(j.contains("\"transcripcion\" : \"/t/a.md\""))
    #expect(j.contains("\"notas\" : null"))
    #expect(UltimaGrabacion.json(nil).contains("\"hay\" : false"))
}

@Test("El lector de notas guarda la ruta de la transcripción")
func actaConTranscripcion() {
    let acta = LectorActa.interpretar(notaConTranscripcion("/tmp/x/202611161130-comite.md"), archivo: "reunion-comite.md")
    #expect(acta?.transcripcion == "/tmp/x/202611161130-comite.md")
    #expect(LectorActa.interpretar("# Notas · Algo\n\nResumen.", archivo: "reunion-algo.md")?.transcripcion == nil)
}
