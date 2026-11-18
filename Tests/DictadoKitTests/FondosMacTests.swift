import Testing
@testable import DictadoKit

// MARK: La línea fondo: con fondos de macOS y aéreos

@Test("Fondo: un nombre de fondo de macOS suelto o con sistema: es .sistema; una paleta conocida sigue siendo paleta")
func fondoSistemaTexto() {
    #expect(FondoLanzador(texto: "Sonoma") == .sistema("Sonoma"))
    #expect(FondoLanzador(texto: "iMac Orange") == .sistema("iMac Orange"))
    #expect(FondoLanzador(texto: "sistema: Radial Sky Blue") == .sistema("Radial Sky Blue"))
    #expect(FondoLanzador(texto: "macOS:Pro Black") == .sistema("Pro Black"))
    #expect(FondoLanzador(texto: "sistema:") == nil)
    #expect(FondoLanzador(texto: "Terracota") == .paleta("Terracota"))
    #expect(FondoLanzador(texto: "tintaLavanda") == .paleta("tintaLavanda"))
    #expect(FondoLanzador(texto: "paleta:lagunaDurazno") == .paleta("lagunaDurazno"))
    #expect(FondoLanzador(texto: "mac") == .mac)
    #expect(FondoLanzador(texto: "/System/Library/Desktop Pictures/Sonoma.heic") == .imagen("/System/Library/Desktop Pictures/Sonoma.heic"))
}

@Test("Fondo: aereo: lee el nombre o el identificador, con o sin tilde, y se vuelve a escribir igual")
func fondoAereoTexto() {
    #expect(FondoLanzador(texto: "aereo:Patagonia") == .aereo("Patagonia"))
    #expect(FondoLanzador(texto: "aéreo: Hong Kong") == .aereo("Hong Kong"))
    #expect(FondoLanzador(texto: "AEREO:B004358B") == .aereo("B004358B"))
    #expect(FondoLanzador(texto: "aerial:Yosemite") == .aereo("Yosemite"))
    #expect(FondoLanzador(texto: "aereo:") == nil)
    #expect(FondoLanzador.aereo("Patagonia").esAereo)
    #expect(!FondoLanzador.sistema("Sonoma").esAereo)
    for f in [FondoLanzador.aereo("Patagonia"), .sistema("Pro Black"), .mac, .imagen("/tmp/a.heic")] { #expect(FondoLanzador(texto: f.texto) == f) }
    #expect(FondoLanzador.resolver(espacio: "aereo:Patagonia", global: "paleta:terracota") == .aereo("Patagonia"))
}

@Test("Fondo: en espacios.txt la línea fondo: con un nombre de macOS o un aéreo se conserva")
func fondoSistemaEnEspacios() {
    let e = EspaciosIsla.leer("[Mañana]\nfondo: iMac Orange\n\n[Foco]\nfondo: aereo:Patagonia\n\n[Juego]\nfondo: /System/Library/Desktop Pictures/Radial Sky Blue.heic")
    #expect(e[0].fondo == "iMac Orange")
    #expect(e[1].fondo == "aereo:Patagonia")
    #expect(e[2].fondo == "/System/Library/Desktop Pictures/Radial Sky Blue.heic")
}

// MARK: Fondos de sistema por nombre

private let rutasSistema = [
    "/System/Library/Desktop Pictures/Sonoma.heic",
    "/System/Library/Desktop Pictures/.wallpapers/Sonoma Horizon/Sonoma Horizon.heic",
    "/System/Library/Desktop Pictures/.wallpapers/Sonoma Horizon/Sonoma Horizon Thumbnail.png",
    "/System/Library/Desktop Pictures/.thumbnails/Big Sur Mountains.heic",
    "/System/Library/Desktop Pictures/iMac Orange.heic",
    "/System/Library/Desktop Pictures/Radial Sky Blue.heic",
    "/System/Library/Desktop Pictures/.wallpapers/Sonoma/Sonoma Graphic Dark Landscape.mov",
    "/Users/x/Library/Application Support/com.apple.mobileAssetDesktop/Pro Black.heic",
]

@Test("Fondo de sistema: el nombre del archivo sin extensión, sin importar mayúsculas ni tildes; exacto antes que parecido")
func fondoSistemaElegir() {
    #expect(CatalogoFondos.elegirSistema("Sonoma", entre: rutasSistema) == "/System/Library/Desktop Pictures/Sonoma.heic")
    #expect(CatalogoFondos.elegirSistema("sonoma.heic", entre: rutasSistema) == "/System/Library/Desktop Pictures/Sonoma.heic")
    #expect(CatalogoFondos.elegirSistema("Sonoma Horizon", entre: rutasSistema)?.hasSuffix("Sonoma Horizon/Sonoma Horizon.heic") == true)
    #expect(CatalogoFondos.elegirSistema("imac orange", entre: rutasSistema) == "/System/Library/Desktop Pictures/iMac Orange.heic")
    #expect(CatalogoFondos.elegirSistema("Radial Sky", entre: rutasSistema) == "/System/Library/Desktop Pictures/Radial Sky Blue.heic")
    #expect(CatalogoFondos.elegirSistema("Pro Black", entre: rutasSistema)?.hasSuffix("mobileAssetDesktop/Pro Black.heic") == true)
}

@Test("Fondo de sistema: miniaturas, videos y nombres que no están dan nil")
func fondoSistemaNoEsta() {
    #expect(CatalogoFondos.elegirSistema("Big Sur Mountains", entre: rutasSistema) == nil)
    #expect(CatalogoFondos.elegirSistema("Sonoma Graphic Dark Landscape", entre: rutasSistema) == nil)
    #expect(CatalogoFondos.elegirSistema("Peak", entre: rutasSistema) == nil)
    #expect(CatalogoFondos.elegirSistema("  ", entre: rutasSistema) == nil)
    #expect(CatalogoFondos.elegirSistema("Sonoma", entre: []) == nil)
}

// MARK: Aéreos

private let catalogoJSON = """
{"version":1,"categories":[{"id":"C-LAND","localizedNameKey":"AerialCategoryLandscapes"},{"id":"C-CITY","localizedNameKey":"AerialCategoryCities"}],
 "assets":[
  {"id":"B004358B-5A27-42E5-B49E-93FC100B2371","accessibilityLabel":"Patagonia","categories":["C-LAND"],"preferredOrder":27},
  {"id":"25A6CFB2-0000-0000-0000-000000000001","accessibilityLabel":"Patagonia","categories":["C-LAND"],"preferredOrder":3},
  {"id":"4109D42A-0000-0000-0000-000000000002","accessibilityLabel":"Yosemite","categories":["C-LAND"],"preferredOrder":9},
  {"id":"024891DE-0000-0000-0000-000000000003","accessibilityLabel":"Hong Kong","categories":["C-CITY"],"preferredOrder":1},
  {"id":"2F52E34C-0000-0000-0000-000000000004","accessibilityLabel":"Greenland","categories":["C-LAND"]},
  {"accessibilityLabel":"sin id"}]}
"""

@Test("Aéreos: el catálogo se lee con su nombre, su categoría en español y su orden; un archivo roto da lista vacía")
func aereosLeer() {
    let a = CatalogoFondos.aereos(json: catalogoJSON)
    #expect(a.count == 5)
    #expect(a[0] == AereoMac(id: "B004358B-5A27-42E5-B49E-93FC100B2371", nombre: "Patagonia", categoria: "Paisajes", orden: 27))
    #expect(a[3].categoria == "Ciudades")
    #expect(a[4].orden == Int.max)
    #expect(CatalogoFondos.aereos(json: "no es json").isEmpty)
    #expect(CatalogoFondos.aereos(json: "{}").isEmpty)
}

@Test("Aéreos: por nombre gana el descargado; por identificador (o su comienzo) el exacto; sin descargar, el de menor orden")
func aereosElegir() {
    let a = CatalogoFondos.aereos(json: catalogoJSON)
    let bajado: Set<String> = ["B004358B-5A27-42E5-B49E-93FC100B2371"]
    #expect(CatalogoFondos.elegirAereo("Patagonia", entre: a, descargados: bajado)?.id == "B004358B-5A27-42E5-B49E-93FC100B2371")
    #expect(CatalogoFondos.elegirAereo("patagonia", entre: a, descargados: [])?.id.hasPrefix("25A6CFB2") == true)
    #expect(CatalogoFondos.elegirAereo("b004358b", entre: a, descargados: [])?.nombre == "Patagonia")
    #expect(CatalogoFondos.elegirAereo("25A6CFB2", entre: a, descargados: bajado)?.id.hasPrefix("25A6CFB2") == true)
    #expect(CatalogoFondos.elegirAereo("hong", entre: a, descargados: [])?.nombre == "Hong Kong")
    #expect(CatalogoFondos.elegirAereo("Marte", entre: a, descargados: bajado) == nil)
    #expect(CatalogoFondos.elegirAereo("", entre: a, descargados: bajado) == nil)
}

@Test("Aéreos: 'nevadas' pide uno de montañas nevadas, el descargado primero")
func aereosNevados() {
    let a = CatalogoFondos.aereos(json: catalogoJSON)
    #expect(CatalogoFondos.elegirAereo("montañas nevadas", entre: a, descargados: ["B004358B-5A27-42E5-B49E-93FC100B2371"])?.id.hasPrefix("B004358B") == true)
    #expect(CatalogoFondos.elegirAereo("nevadas", entre: a, descargados: [])?.nombre == "Patagonia")
}

@Test("Aéreos: el cuadro fijo se guarda con un nombre simple y único")
func aereoNombreCuadro() {
    let a = AereoMac(id: "B004358B-5A27-42E5-B49E-93FC100B2371", nombre: "Patagonia", categoria: "Paisajes", orden: 1)
    #expect(CatalogoFondos.nombreDeCuadro(a) == "patagonia-b004358b")
    #expect(CatalogoFondos.nombreDeCuadro(AereoMac(id: "AAAAAAAA-1", nombre: "Hong Kong", categoria: "", orden: 0)) == "hong-kong-aaaaaaaa")
}

@Test("Cuadro bonito: con detalle y luminancia media gana a uno liso, quemado u oscuro")
func cuadroBonito() {
    #expect(CatalogoFondos.cuadroBonito(luminancias: [0.9, 0.45, 0.05, 0.5], contrastes: [0.1, 0.25, 0.2, 0.02]) == 1)
    #expect(CatalogoFondos.cuadroBonito(luminancias: [], contrastes: []) == nil)
    #expect(CatalogoFondos.cuadroBonito(luminancias: [0.5], contrastes: []) == nil)
    #expect(CatalogoFondos.cuadroBonito(luminancias: [0.3], contrastes: [0.1]) == 0)
}
