import Testing
@testable import DictadoKit

@Test("Las cuatro operaciones y la precedencia")
func lanz_operaciones() {
    #expect(Aritmetica.evaluar("2+3") == 5)
    #expect(Aritmetica.evaluar("10 - 4") == 6)
    #expect(Aritmetica.evaluar("6×7") == 42)
    #expect(Aritmetica.evaluar("20÷4") == 5)
    #expect(Aritmetica.evaluar("2+3*4") == 14)
    #expect(Aritmetica.evaluar("100/5/2") == 10)
    #expect(Aritmetica.evaluar("2−1") == 1)
}

@Test("Paréntesis y signo unario")
func lanz_parentesis() {
    #expect(Aritmetica.evaluar("(2+3)*4") == 20)
    #expect(Aritmetica.evaluar("-(2+3)*2") == -10)
    #expect(Aritmetica.evaluar("3*-2") == -6)
    #expect(Aritmetica.evaluar("((1+1)*(2+2))") == 8)
}

@Test("Decimales con coma o con punto")
func lanz_decimales() {
    #expect(Aritmetica.resultado("1,5+2,25") == "3,75")
    #expect(Aritmetica.resultado("1.5+2.25") == "3,75")
    #expect(Aritmetica.resultado("0,1+0,2") == "0,3")
    #expect(Aritmetica.resultado(".5*4") == "2")
}

@Test("Porcentaje: solo y sobre una cifra")
func lanz_porcentaje() {
    #expect(Aritmetica.evaluar("50%") == 0.5)
    #expect(Aritmetica.evaluar("200+10%") == 220)
    #expect(Aritmetica.evaluar("200-25%") == 150)
    #expect(Aritmetica.evaluar("200*10%") == 20)
    #expect(Aritmetica.evaluar("(10+10)%") == 0.2)
}

@Test("Un número solo o un paréntesis solo no son una cuenta")
func lanz_noEsCuenta() {
    #expect(Aritmetica.evaluar("42") == nil)
    #expect(Aritmetica.evaluar("(5)") == nil)
    #expect(Aritmetica.evaluar("-5") == nil)
    #expect(Aritmetica.evaluar("") == nil)
}

@Test("Rechaza todo lo que no es aritmética")
func lanz_rechaza() {
    #expect(Aritmetica.evaluar("safari") == nil)
    #expect(Aritmetica.evaluar("2+a") == nil)
    #expect(Aritmetica.evaluar("2x3") == nil)
    #expect(Aritmetica.evaluar("2^3") == nil)
    #expect(Aritmetica.evaluar("sqrt(4)+1") == nil)
    #expect(Aritmetica.evaluar("2(3)") == nil)
    #expect(Aritmetica.evaluar("1+") == nil)
    #expect(Aritmetica.evaluar("(1+2") == nil)
    #expect(Aritmetica.evaluar("1+2)") == nil)
    #expect(Aritmetica.evaluar("1,000.5+1") == nil)
    #expect(Aritmetica.evaluar("1..5+1") == nil)
    #expect(Aritmetica.evaluar("0x10+1") == nil)
    #expect(Aritmetica.evaluar("1e3+1") == nil)
    #expect(Aritmetica.evaluar("system(\"ls\")+1") == nil)
}

@Test("Dividir entre cero y desbordes no dan resultado")
func lanz_limites() {
    #expect(Aritmetica.evaluar("1/0") == nil)
    #expect(Aritmetica.evaluar("5÷(2-2)") == nil)
    #expect(Aritmetica.evaluar("99999999*99999999") == nil)
    let anidado = String(repeating: "(", count: 200) + "1+1" + String(repeating: ")", count: 200)
    #expect(Aritmetica.evaluar(anidado) == nil)
    #expect(Aritmetica.evaluar(String(repeating: "1+", count: 200) + "1") == nil)
}

@Test("Formato: coma decimal, sin ceros de sobra ni -0")
func lanz_formato() {
    #expect(Aritmetica.formatear(5) == "5")
    #expect(Aritmetica.formatear(-0.0) == "0")
    #expect(Aritmetica.formatear(1.0 / 3.0) == "0,3333333333")
    #expect(Aritmetica.formatear(-2.5) == "-2,5")
    #expect(Aritmetica.resultado("10/4") == "2,5")
}
