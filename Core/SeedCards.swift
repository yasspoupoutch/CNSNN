import Foundation
public enum SeedCards {
    public static let all: [Card] = {
        let rows: [(String, String, Category, Difficulty)] = [
            ("Chocolat", "Un carré suffit rarement.", .general, .easy),
            ("Bibliothèque", "Des histoires rangées sur des étagères.", .general, .medium),
            ("Papillon", "Il commence sa vie en chenille.", .animals, .easy),
            ("Éléphant", "Un géant à trompe.", .animals, .easy),
            ("Hippopotame", "Un poids lourd des rivières africaines.", .animals, .hard),
            ("Tournevis", "Il fait tourner sans moteur.", .objects, .easy),
            ("Parapluie", "Votre petit toit les jours de pluie.", .objects, .medium),
            ("Réfrigérateur", "Le gardien des aliments au frais.", .objects, .hard),
            ("Marseille", "La cité phocéenne.", .geography, .easy),
            ("Portugal", "Lisbonne est sa capitale.", .geography, .easy),
            ("Madagascar", "Une grande île peuplée de lémuriens.", .geography, .medium),
            ("Liechtenstein", "Une principauté entre Suisse et Autriche.", .geography, .hard),
            ("Gardien", "Le dernier rempart devant le but.", .football, .easy),
            ("Penalty", "Un duel à onze mètres.", .football, .medium),
            ("Ballon d’or", "Une récompense individuelle très convoitée.", .football, .hard),
            ("Corner", "Un coup de pied tiré depuis un angle.", .football, .easy),
            ("Titanic", "Une histoire d’amour sur un paquebot.", .cinema, .easy),
            ("Gladiator", "Un général romain devenu combattant.", .cinema, .medium),
            ("Interstellar", "Un voyage spatial à travers le temps.", .cinema, .hard),
            ("Ratatouille", "Un petit chef à moustaches.", .cinema, .easy),
            ("Croissant", "Un classique du petit déjeuner.", .general, .easy),
            ("Constellation", "Un dessin dans le ciel nocturne.", .general, .hard),
            ("Escargot", "Il emporte sa maison partout.", .animals, .medium),
            ("Jumelles", "Elles rapprochent ce qui est loin.", .objects, .medium),
            ("Montgolfière", "Un panier porté par de l’air chaud.", .objects, .hard),
            ("Champions", "Ils ont gagné le titre.", .football, .medium),
            ("Casablanca", "Un classique du cinéma et une ville marocaine.", .cinema, .hard),
            ("Strasbourg", "Une ville alsacienne au cœur de l’Europe.", .geography, .medium),
            ("Ornithorynque", "Un mammifère à bec qui pond des œufs.", .animals, .hard),
            ("Métamorphose", "Un changement complet de forme.", .general, .hard)
        ]
        return rows.enumerated().map { Card(id: String(format: "seed-%03d", $0.offset), wordFull: $0.element.0, hint: $0.element.1, category: $0.element.2, difficulty: $0.element.3) }
    }()
}
