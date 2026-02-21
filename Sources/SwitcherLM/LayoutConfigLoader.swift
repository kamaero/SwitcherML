import Foundation

struct LayoutConfigLoader {
    let config: LayoutConfig
    let activePair: LayoutConfig.LayoutPair
    let leftToRightMap: [Character: Character]
    let rightToLeftMap: [Character: Character]

    static func load() -> LayoutConfigLoader {
        guard let url = Bundle.module.url(forResource: "Layouts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(LayoutConfig.self, from: data) else {
            return fallback()
        }

        guard let pair = config.pairs.first(where: { $0.id == config.defaultPair }) ?? config.pairs.first else {
            return fallback()
        }

        guard let leftMap = pair.left.map else {
            return fallback()
        }

        let leftToRight = mapFromStrings(leftMap)
        let rightToLeft = invert(leftToRight)
        return LayoutConfigLoader(
            config: config,
            activePair: pair,
            leftToRightMap: leftToRight,
            rightToLeftMap: rightToLeft
        )
    }

    private static func mapFromStrings(_ raw: [String: String]) -> [Character: Character] {
        var map: [Character: Character] = [:]
        for (k, v) in raw {
            guard let kc = k.first, let vc = v.first else { continue }
            map[kc] = vc
        }
        return map
    }

    private static func invert(_ map: [Character: Character]) -> [Character: Character] {
        var inverted: [Character: Character] = [:]
        for (k, v) in map {
            inverted[v] = k
        }
        return inverted
    }

    private static func fallback() -> LayoutConfigLoader {
        let leftMap: [Character: Character] = [
            "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е",
            "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
            "[": "х", "]": "ъ", "a": "ф", "s": "ы", "d": "в",
            "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
            "l": "д", ";": "ж", "'": "э", "z": "я", "x": "ч",
            "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
            ",": "б", ".": "ю", "/": ".", "`": "ё",
            "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е",
            "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
            "{": "Х", "}": "Ъ", "A": "Ф", "S": "Ы", "D": "В",
            "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л",
            "L": "Д", ":": "Ж", "\"": "Э", "Z": "Я", "X": "Ч",
            "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь",
            "<": "Б", ">": "Ю", "?": ",", "~": "Ё",
        ]

        let config = LayoutConfig(
            defaultPair: "en-ru",
            pairs: [
                LayoutConfig.LayoutPair(
                    id: "en-ru",
                    name: "English ⇄ Russian",
                    left: LayoutConfig.LayoutSide(id: "en", name: "English", script: "latin", map: nil),
                    right: LayoutConfig.LayoutSide(id: "ru", name: "Russian", script: "cyrillic", map: nil)
                )
            ]
        )

        return LayoutConfigLoader(
            config: config,
            activePair: config.pairs[0],
            leftToRightMap: leftMap,
            rightToLeftMap: invert(leftMap)
        )
    }
}
