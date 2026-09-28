import Foundation

public struct MardColor: Equatable, Hashable, Sendable {
    public let code: String
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(code: String, hex: String) {
        self.code = code
        let (r, g, b) = MardColor.parseHex(hex)
        self.red = r
        self.green = g
        self.blue = b
    }

    private static func parseHex(_ hex: String) -> (Double, Double, Double) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        return (r, g, b)
    }
}

public enum MardPalette {
    public static let standard221: [MardColor] = [
        MardColor(code: "A1", hex: "FAF4C8"), MardColor(code: "A2", hex: "FFFFD5"),
        MardColor(code: "A3", hex: "FEFF8B"), MardColor(code: "A4", hex: "FBED56"),
        MardColor(code: "A5", hex: "F4D738"), MardColor(code: "A6", hex: "FEAC4C"),
        MardColor(code: "A7", hex: "FE8B4C"), MardColor(code: "A8", hex: "FFDA45"),
        MardColor(code: "A9", hex: "FF995B"), MardColor(code: "A10", hex: "F77C31"),
        MardColor(code: "A11", hex: "FFDD99"), MardColor(code: "A12", hex: "FE9F72"),
        MardColor(code: "A13", hex: "FFC365"), MardColor(code: "A14", hex: "FD543D"),
        MardColor(code: "A15", hex: "FFF365"), MardColor(code: "A16", hex: "FFFF9F"),
        MardColor(code: "A17", hex: "FFE36E"), MardColor(code: "A18", hex: "FEBE7D"),
        MardColor(code: "A19", hex: "FD7C72"), MardColor(code: "A20", hex: "FFD568"),
        MardColor(code: "A21", hex: "FFE395"), MardColor(code: "A22", hex: "F4F57D"),
        MardColor(code: "A23", hex: "E6C9B7"), MardColor(code: "A24", hex: "F7F8A2"),
        MardColor(code: "A25", hex: "FFD67D"), MardColor(code: "A26", hex: "FFC830"),

        MardColor(code: "B1", hex: "E6EE31"), MardColor(code: "B2", hex: "63F347"),
        MardColor(code: "B3", hex: "9EF780"), MardColor(code: "B4", hex: "5DE035"),
        MardColor(code: "B5", hex: "35E352"), MardColor(code: "B6", hex: "65E2A6"),
        MardColor(code: "B7", hex: "3DAF80"), MardColor(code: "B8", hex: "1C9C4F"),
        MardColor(code: "B9", hex: "27523A"), MardColor(code: "B10", hex: "95D3C2"),
        MardColor(code: "B11", hex: "5D722A"), MardColor(code: "B12", hex: "166F41"),
        MardColor(code: "B13", hex: "CAEB7B"), MardColor(code: "B14", hex: "ADE946"),
        MardColor(code: "B15", hex: "2E5132"), MardColor(code: "B16", hex: "C5ED9C"),
        MardColor(code: "B17", hex: "9BB13A"), MardColor(code: "B18", hex: "E6EE49"),
        MardColor(code: "B19", hex: "24B88C"), MardColor(code: "B20", hex: "C2F0CC"),
        MardColor(code: "B21", hex: "156A6B"), MardColor(code: "B22", hex: "0B3C43"),
        MardColor(code: "B23", hex: "303A21"), MardColor(code: "B24", hex: "EEFCA5"),
        MardColor(code: "B25", hex: "4E846D"), MardColor(code: "B26", hex: "8D7A35"),
        MardColor(code: "B27", hex: "CCE1AF"), MardColor(code: "B28", hex: "9EE5B9"),
        MardColor(code: "B29", hex: "C5E254"), MardColor(code: "B30", hex: "E2FCB1"),
        MardColor(code: "B31", hex: "B0E792"), MardColor(code: "B32", hex: "9CAB5A"),

        MardColor(code: "C1", hex: "E8FFE7"), MardColor(code: "C2", hex: "A9F9FC"),
        MardColor(code: "C3", hex: "A0E2FB"), MardColor(code: "C4", hex: "41CCFF"),
        MardColor(code: "C5", hex: "01ACEB"), MardColor(code: "C6", hex: "50AAF0"),
        MardColor(code: "C7", hex: "3677D2"), MardColor(code: "C8", hex: "0F54C0"),
        MardColor(code: "C9", hex: "324BCA"), MardColor(code: "C10", hex: "3EBCE2"),
        MardColor(code: "C11", hex: "28DDDE"), MardColor(code: "C12", hex: "1C334D"),
        MardColor(code: "C13", hex: "CDE8FF"), MardColor(code: "C14", hex: "D5FDFF"),
        MardColor(code: "C15", hex: "22C4C6"), MardColor(code: "C16", hex: "1557A8"),
        MardColor(code: "C17", hex: "04D1F6"), MardColor(code: "C18", hex: "1D3344"),
        MardColor(code: "C19", hex: "1887A2"), MardColor(code: "C20", hex: "176DAF"),
        MardColor(code: "C21", hex: "BEDDFF"), MardColor(code: "C22", hex: "67B4BE"),
        MardColor(code: "C23", hex: "C8E2FF"), MardColor(code: "C24", hex: "7CC4FF"),
        MardColor(code: "C25", hex: "A9E5E5"), MardColor(code: "C26", hex: "3CAED8"),
        MardColor(code: "C27", hex: "D3DFFA"), MardColor(code: "C28", hex: "BBCFED"),
        MardColor(code: "C29", hex: "34488E"),

        MardColor(code: "D1", hex: "AEB4F2"), MardColor(code: "D2", hex: "858EDD"),
        MardColor(code: "D3", hex: "2F54AF"), MardColor(code: "D4", hex: "182A84"),
        MardColor(code: "D5", hex: "B843C5"), MardColor(code: "D6", hex: "AC7BDE"),
        MardColor(code: "D7", hex: "8854B3"), MardColor(code: "D8", hex: "E2D3FF"),
        MardColor(code: "D9", hex: "D5B9F8"), MardColor(code: "D10", hex: "361851"),
        MardColor(code: "D11", hex: "B9BAE1"), MardColor(code: "D12", hex: "DE9AD4"),
        MardColor(code: "D13", hex: "B90095"), MardColor(code: "D14", hex: "8B279B"),
        MardColor(code: "D15", hex: "2F1F90"), MardColor(code: "D16", hex: "E3E1EE"),
        MardColor(code: "D17", hex: "C4D4F6"), MardColor(code: "D18", hex: "A45EC7"),
        MardColor(code: "D19", hex: "D8C3D7"), MardColor(code: "D20", hex: "9C32B2"),
        MardColor(code: "D21", hex: "9A009B"), MardColor(code: "D22", hex: "333A95"),
        MardColor(code: "D23", hex: "EBDAFC"), MardColor(code: "D24", hex: "7786E5"),
        MardColor(code: "D25", hex: "494FC7"), MardColor(code: "D26", hex: "DFC2F8"),

        MardColor(code: "E1", hex: "FDD3CC"), MardColor(code: "E2", hex: "FEC0DF"),
        MardColor(code: "E3", hex: "FFB7E7"), MardColor(code: "E4", hex: "E8649E"),
        MardColor(code: "E5", hex: "F551A2"), MardColor(code: "E6", hex: "F13D74"),
        MardColor(code: "E7", hex: "C63478"), MardColor(code: "E8", hex: "FFDBE9"),
        MardColor(code: "E9", hex: "E970CC"), MardColor(code: "E10", hex: "D33793"),
        MardColor(code: "E11", hex: "FCDDD2"), MardColor(code: "E12", hex: "F78FC3"),
        MardColor(code: "E13", hex: "B5006D"), MardColor(code: "E14", hex: "FFD1BA"),
        MardColor(code: "E15", hex: "F8C7C9"), MardColor(code: "E16", hex: "FFF3EB"),
        MardColor(code: "E17", hex: "FFE2EA"), MardColor(code: "E18", hex: "FFC7DB"),
        MardColor(code: "E19", hex: "FEBAD5"), MardColor(code: "E20", hex: "D8C7D1"),
        MardColor(code: "E21", hex: "BD9DA1"), MardColor(code: "E22", hex: "B785A1"),
        MardColor(code: "E23", hex: "937A8D"), MardColor(code: "E24", hex: "E1BCE8"),

        MardColor(code: "F1", hex: "FD957B"), MardColor(code: "F2", hex: "FC3D46"),
        MardColor(code: "F3", hex: "F74941"), MardColor(code: "F4", hex: "FC283C"),
        MardColor(code: "F5", hex: "E7002F"), MardColor(code: "F6", hex: "943630"),
        MardColor(code: "F7", hex: "971937"), MardColor(code: "F8", hex: "BC0028"),
        MardColor(code: "F9", hex: "E2677A"), MardColor(code: "F10", hex: "8A4526"),
        MardColor(code: "F11", hex: "5A2121"), MardColor(code: "F12", hex: "FD4E6A"),
        MardColor(code: "F13", hex: "F35744"), MardColor(code: "F14", hex: "FFA9AD"),
        MardColor(code: "F15", hex: "D30022"), MardColor(code: "F16", hex: "FEC2A6"),
        MardColor(code: "F17", hex: "E69C79"), MardColor(code: "F18", hex: "D37C46"),
        MardColor(code: "F19", hex: "C1444A"), MardColor(code: "F20", hex: "CD9391"),
        MardColor(code: "F21", hex: "F7B4C6"), MardColor(code: "F22", hex: "FDC0D0"),
        MardColor(code: "F23", hex: "F67E66"), MardColor(code: "F24", hex: "E698AA"),
        MardColor(code: "F25", hex: "E54B4F"),

        MardColor(code: "G1", hex: "FFE2CE"), MardColor(code: "G2", hex: "FFC4AA"),
        MardColor(code: "G3", hex: "F4C3A5"), MardColor(code: "G4", hex: "E1B383"),
        MardColor(code: "G5", hex: "EDB045"), MardColor(code: "G6", hex: "E99C17"),
        MardColor(code: "G7", hex: "9D5B3E"), MardColor(code: "G8", hex: "753832"),
        MardColor(code: "G9", hex: "E6B483"), MardColor(code: "G10", hex: "D98C39"),
        MardColor(code: "G11", hex: "E0C593"), MardColor(code: "G12", hex: "FFC890"),
        MardColor(code: "G13", hex: "B7714A"), MardColor(code: "G14", hex: "8D614C"),
        MardColor(code: "G15", hex: "FCF9E0"), MardColor(code: "G16", hex: "F2D9BA"),
        MardColor(code: "G17", hex: "78524B"), MardColor(code: "G18", hex: "FFE4CC"),
        MardColor(code: "G19", hex: "E07935"), MardColor(code: "G20", hex: "A94023"),
        MardColor(code: "G21", hex: "B88558"),

        MardColor(code: "H1", hex: "FDFBFF"), MardColor(code: "H2", hex: "FEFFFF"),
        MardColor(code: "H3", hex: "B6B1BA"), MardColor(code: "H4", hex: "89858C"),
        MardColor(code: "H5", hex: "48464E"), MardColor(code: "H6", hex: "2F2B2F"),
        MardColor(code: "H7", hex: "000000"), MardColor(code: "H8", hex: "E7D6DB"),
        MardColor(code: "H9", hex: "EDEDED"), MardColor(code: "H10", hex: "EEE9EA"),
        MardColor(code: "H11", hex: "CECDD5"), MardColor(code: "H12", hex: "FFF5ED"),
        MardColor(code: "H13", hex: "F5ECD2"), MardColor(code: "H14", hex: "CFD7D3"),
        MardColor(code: "H15", hex: "98A6A8"), MardColor(code: "H16", hex: "1D1414"),
        MardColor(code: "H17", hex: "F1EDED"), MardColor(code: "H18", hex: "FFFDF0"),
        MardColor(code: "H19", hex: "F6EFE2"), MardColor(code: "H20", hex: "949FA3"),
        MardColor(code: "H21", hex: "FFFBE1"), MardColor(code: "H22", hex: "CACAD4"),
        MardColor(code: "H23", hex: "9A9D94"),

        MardColor(code: "M1", hex: "BCC6B8"), MardColor(code: "M2", hex: "8AA386"),
        MardColor(code: "M3", hex: "697D80"), MardColor(code: "M4", hex: "E3D2BC"),
        MardColor(code: "M5", hex: "D0CCAA"), MardColor(code: "M6", hex: "B0A782"),
        MardColor(code: "M7", hex: "B4A497"), MardColor(code: "M8", hex: "B38281"),
        MardColor(code: "M9", hex: "A58767"), MardColor(code: "M10", hex: "C5B2BC"),
        MardColor(code: "M11", hex: "9F7594"), MardColor(code: "M12", hex: "644749"),
        MardColor(code: "M13", hex: "D19066"), MardColor(code: "M14", hex: "C77362"),
        MardColor(code: "M15", hex: "757D78"),
    ]
}
