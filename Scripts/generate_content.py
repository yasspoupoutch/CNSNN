#!/usr/bin/env python3
"""Cartes, duos Double sens et vecteurs de test communs à l'iPhone et à Android.

    python3 Scripts/generate_content.py          valide Shared/*.tsv puis réécrit les fichiers générés
    python3 Scripts/generate_content.py --check  échoue si un fichier généré n'est plus à jour (CI)
    python3 Scripts/generate_content.py --words  affiche les mots normalisés (contrôle des mots du jour)

Les deux applications lisent les mêmes listes (Shared/cards.tsv, Shared/duos.tsv). Les règles des
modes Sprint, Survie et Double sens sont réécrites ici en Python : les vecteurs produits sont rejoués
par les tests Swift et Kotlin, qui doivent trouver exactement les mêmes mots, records et vies.
"""
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / 'Shared'
KOTLIN_CORE = ROOT / 'Android/core/src/main/kotlin/com/poupoutch/cnsnn/core'
KOTLIN_TEST = ROOT / 'Android/core/src/test/kotlin/com/poupoutch/cnsnn/core'
CATEGORIES = {'Général': 'general', 'Football': 'football', 'Cinéma': 'cinema', 'Géographie': 'geography', 'Animaux': 'animals', 'Objets': 'objects'}
KOTLIN_CATEGORIES = {'general': 'GENERAL', 'football': 'FOOTBALL', 'cinema': 'CINEMA', 'geography': 'GEOGRAPHY', 'animals': 'ANIMALS', 'objects': 'OBJECTS'}
DIFFICULTIES = {'F': 'easy', 'M': 'medium', 'D': 'hard'}
ORDER = ['easy', 'medium', 'hard']


# ---- Same text rules as Core/WordEngine.swift and WordEngine.kt

def normalize(value):
    value = value.replace('œ', 'oe').replace('Œ', 'OE').replace('æ', 'ae').replace('Æ', 'AE')
    value = ''.join(c for c in unicodedata.normalize('NFD', value) if not unicodedata.combining(c))
    return ''.join(c for c in value.upper() if 'A' <= c <= 'Z')


def consonants(value):
    return ''.join(c for c in normalize(value) if c not in 'AEIOUY')


# ---- Sources

def rows(name):
    for number, line in enumerate((SHARED / name).read_text(encoding='utf-8').splitlines(), 1):
        if line.strip() and not line.startswith('#'):
            yield number, [part.strip() for part in line.split('\t')]


def seed_cards():
    """The 134 original cards (Core/SeedCards.swift), ids seed-000…"""
    text = (ROOT / 'Core/SeedCards.swift').read_text(encoding='utf-8')
    found = re.findall(r'\("([^"]+)", "([^"]+)", \.(\w+), \.(\w+)\)', text)
    return [{'id': 'seed-%03d' % i, 'word': w, 'hint': h, 'category': c, 'difficulty': d} for i, (w, h, c, d) in enumerate(found)]


def daily_pool():
    text = (ROOT / 'Core/DailyPool.swift').read_text(encoding='utf-8')
    return [w for w, _ in re.findall(r'\("([^"]+)", "([^"]+)"', text)]


class Invalid(Exception):
    pass


def check_hint(word, hint, where):
    if not 8 <= len(hint) <= 120:
        raise Invalid(f'{where} : indice de {len(hint)} caractères (8 à 120)')
    if hint[-1] not in '.!?»':
        raise Invalid(f'{where} : l’indice doit finir par une ponctuation')
    if normalize(word) in normalize(hint):
        raise Invalid(f'{where} : l’indice contient la réponse')
    if "'" in hint or "'" in word:
        raise Invalid(f'{where} : apostrophe droite, utiliser ’')


def check_word(word, where):
    full = normalize(word)
    if not 3 <= len(full) <= 40 or not consonants(word):
        raise Invalid(f'{where} : mot invalide « {word} »')


def load_cards():
    seeds = seed_cards()
    if len(seeds) != 134:
        raise Invalid(f'Core/SeedCards.swift : {len(seeds)} cartes lues au lieu de 134')
    taken = {normalize(c['word']): c['id'] for c in seeds}
    reserved = {normalize(w) for w in daily_pool()}
    cards = []
    for number, parts in rows('cards.tsv'):
        where = f'cards.tsv ligne {number}'
        if len(parts) != 4:
            raise Invalid(f'{where} : 4 colonnes attendues')
        level, category, word, hint = parts
        if level not in DIFFICULTIES or category not in CATEGORIES:
            raise Invalid(f'{where} : difficulté ou catégorie inconnue')
        check_word(word, where)
        check_hint(word, hint, where)
        key = normalize(word)
        if key in taken:
            raise Invalid(f'{where} : « {word} » existe déjà ({taken[key]})')
        if key in reserved:
            raise Invalid(f'{where} : « {word} » est réservé au mot du jour')
        card = {'id': 'seed-' + key.lower(), 'word': word, 'hint': hint, 'category': CATEGORIES[category], 'difficulty': DIFFICULTIES[level]}
        taken[key] = card['id']
        cards.append(card)
    return seeds, cards


def load_duos():
    duos, words, sets = [], {}, {}
    for number, parts in rows('duos.tsv'):
        where = f'duos.tsv ligne {number}'
        if len(parts) != 4:
            raise Invalid(f'{where} : 4 colonnes attendues')
        first, first_hint, second, second_hint = parts
        for word, hint in ((first, first_hint), (second, second_hint)):
            check_word(word, where)
            check_hint(word, hint, where)
            # Each answer must not hint at the other one either.
            other = second if word == first else first
            if normalize(other) in normalize(hint):
                raise Invalid(f'{where} : l’indice de « {word} » contient « {other} »')
        a, b = normalize(first), normalize(second)
        if a == b:
            raise Invalid(f'{where} : les deux réponses sont identiques')
        if consonants(first) != consonants(second):
            raise Invalid(f'{where} : {consonants(first)} ≠ {consonants(second)}')
        if first_hint == second_hint:
            raise Invalid(f'{where} : deux fois le même indice')
        for key in (a, b):
            if key in words:
                raise Invalid(f'{where} : « {key} » est déjà dans le duo de la ligne {words[key]}')
            words[key] = number
        set_ = consonants(first)
        if set_ in sets:
            raise Invalid(f'{where} : les consonnes {set_} sont déjà jouées ligne {sets[set_]}')
        sets[set_] = number
        duos.append({'id': f'duo-{a.lower()}-{b.lower()}', 'consonants': set_, 'first': (first, first_hint), 'second': (second, second_hint)})
    if len(duos) < 30:
        raise Invalid(f'{len(duos)} duos : il en faut au moins 30')
    return duos


# ---- Reference rules (Core/Modes.swift, Modes.kt)

MASK = (1 << 64) - 1


class Random:
    """SplitMix64: the same numbers from the same seed on every platform."""
    def __init__(self, seed):
        self.state = seed & MASK

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK
        return z ^ (z >> 31)

    def int(self, bound):
        return self.next() % bound


def pick(pool, weights, used, recent, rng):
    roll = rng.int(100)
    target = 'easy' if roll < weights[0] else 'medium' if roll < weights[0] + weights[1] else 'hard'
    order = {'easy': ['easy', 'medium', 'hard'], 'medium': ['medium', 'easy', 'hard'], 'hard': ['hard', 'medium', 'easy']}[target]
    for avoid_recent in (True, False):
        for level in order:
            options = [c for c in pool if c['difficulty'] == level and c['id'] not in used and not (avoid_recent and c['id'] in recent)]
            if options:
                return options[rng.int(len(options))]
    return None


class Sprint:
    DURATION, PENALTY, WEIGHTS = 90_000, 5_000, (40, 40, 20)

    def __init__(self, pool, seed, recent=()):
        self.pool, self.rng, self.recent = pool, Random(seed), set(recent)
        self.used, self.card = [], None
        self.found = self.streak = self.best_combo = self.wrong = self.skips = self.penalty = 0
        self.finished = False
        self.draw()

    def remaining(self, t):
        return max(0, self.DURATION - t - self.penalty)

    def draw(self):
        self.card = pick(self.pool, self.WEIGHTS, set(self.used), self.recent, self.rng)
        if self.card is None:
            self.finished = True
        else:
            self.used.append(self.card['id'])

    def answer(self, text, t):
        if self.finished or self.remaining(t) == 0:
            self.finished = True
            return
        if normalize(text) == normalize(self.card['word']):
            self.streak += 1
            self.found += 1
            self.best_combo = max(self.best_combo, self.streak)
            self.draw()
        else:
            self.wrong += 1
            self.streak = 0

    def skip(self, t):
        if self.finished or self.remaining(t) == 0:
            self.finished = True
            return
        self.skips += 1
        self.streak = 0
        self.penalty += self.PENALTY
        if self.remaining(t) == 0:
            self.finished = True
        else:
            self.draw()


class Survival:
    MAX_LIVES, PER_LEVEL, BONUS_EVERY = 3, 5, 10
    WEIGHTS = [(100, 0, 0), (70, 30, 0), (40, 50, 10), (20, 55, 25), (10, 50, 40), (5, 40, 55), (0, 30, 70)]

    def __init__(self, pool, seed, recent=()):
        self.pool, self.rng, self.recent = pool, Random(seed), set(recent)
        self.used, self.card = [], None
        self.lives, self.found, self.wrong, self.skips, self.gained = 3, 0, 0, 0, 0
        self.finished = False
        self.draw()

    @property
    def level(self):
        return self.found // self.PER_LEVEL + 1

    def draw(self):
        weights = self.WEIGHTS[min(self.level - 1, len(self.WEIGHTS) - 1)]
        self.card = pick(self.pool, weights, set(self.used), self.recent, self.rng)
        if self.card is None:
            self.finished = True
        else:
            self.used.append(self.card['id'])

    def answer(self, text):
        if self.finished:
            return
        if normalize(text) == normalize(self.card['word']):
            self.found += 1
            if self.found % self.BONUS_EVERY == 0 and self.lives < self.MAX_LIVES:
                self.lives += 1
                self.gained += 1
            self.draw()
        else:
            self.wrong += 1
            self.lives -= 1
            self.finished = self.lives == 0

    def skip(self):
        if self.finished:
            return
        self.skips += 1
        self.lives -= 1
        if self.lives == 0:
            self.finished = True
        else:
            self.draw()


class DuoGame:
    ROUNDS = 5

    def __init__(self, duos, seed, recent=()):
        self.rng = Random(seed)
        self.duos = []
        for _ in range(self.ROUNDS):
            picked = {d['id'] for d in self.duos}
            options = [d for d in duos if d['id'] not in picked and d['id'] not in recent] or [d for d in duos if d['id'] not in picked]
            self.duos.append(options[self.rng.int(len(options))])
        self.round, self.errors, self.excluded = 0, 0, 0
        self.found = [[False, False] for _ in self.duos]
        self.skipped = [False for _ in self.duos]
        self.completed_at, self.end_ms, self.finished = None, None, False

    def complete(self):
        return all(self.found[self.round]) or self.skipped[self.round]

    def answer(self, text, t):
        if self.finished or self.complete():
            return
        duo, key = self.duos[self.round], normalize(text)
        words = [normalize(duo['first'][0]), normalize(duo['second'][0])]
        if key in words:
            index = words.index(key)
            if self.found[self.round][index]:
                return
            self.found[self.round][index] = True
            if self.complete():
                self.close(t)
        else:
            self.errors += 1

    def skip(self, t):
        if self.finished or self.complete():
            return
        self.skipped[self.round] = True
        self.close(t)

    def close(self, t):
        self.completed_at = t
        if self.round == len(self.duos) - 1:
            self.finished, self.end_ms = True, t - self.excluded

    def next(self, t):
        if self.finished or not self.complete():
            return
        self.excluded += t - self.completed_at
        self.completed_at = None
        self.round += 1

    def play_ms(self, t):
        if self.end_ms is not None:
            return self.end_ms
        return t - self.excluded - (t - self.completed_at if self.completed_at is not None else 0)

    def words_found(self):
        return sum(a + b for a, b in self.found)

    def solved(self):
        return sum(1 for a, b in self.found if a and b)

    def record(self, t):
        # Pairs found first, then the time (DuoRecord in Core/Modes.swift).
        return self.solved() * 100_000 + max(0, 99_999 - max(0, self.play_ms(t)) // 1000)


# ---- Scenarios replayed by both test suites

# Friend challenge: 2 easy, 2 medium and 1 hard word, the same for both players (Core/Challenge.swift).
CHALLENGE_LEVELS = [[100, 0, 0], [100, 0, 0], [0, 100, 0], [0, 100, 0], [0, 0, 100]]


def challenge_draw(pool, seed, recent=()):
    rng, used = Random(seed), []
    for weights in CHALLENGE_LEVELS:
        used.append(pick(pool, weights, set(used), set(recent), rng)['id'])
    return used


def scenarios(pool, duos):
    out = {'random': [], 'sprint': [], 'survival': [], 'duo': [], 'challenge': []}
    for seed, recent in ((0, ()), (42, ()), (2**63 + 5, ()), (MASK, ())):
        out['challenge'].append((seed, list(recent), challenge_draw(pool, seed, recent)))
    first = challenge_draw(pool, 42)
    out['challenge'].append((42, first[:3], challenge_draw(pool, 42, first[:3])))
    for seed in (0, 1, 42, 2**63 + 5, MASK):
        rng = Random(seed)
        out['random'].append((seed, [rng.next() for _ in range(4)], Random(seed).int(97)))

    def sprint_case(seed, actions):
        game, steps = Sprint(pool, seed), []
        for action in actions:
            kind, t = action.split('@')
            t = int(t)
            if kind == 'ok':
                game.answer(game.card['word'], t)
            elif kind == 'ko':
                game.answer('ZZZ', t)
            else:
                game.skip(t)
            steps.append((action, game.card['id'] if game.card else '', game.streak, game.found, game.wrong, game.skips, game.remaining(t), game.finished))
        out['sprint'].append((seed, Sprint(pool, seed).card['id'], steps, game.best_combo))

    sprint_case(42, ['ok@3000', 'ok@6000', 'ok@9000', 'ok@12000', 'ok@15000', 'ok@18000', 'ko@20000', 'ok@22000', 'skip@25000', 'ok@26000', 'ok@27000'])
    sprint_case(7, ['ok@1000', 'skip@2000', 'skip@3000', 'ko@4000', 'ok@50000', 'ok@69000', 'ok@71000'])
    sprint_case(2024, ['skip@1000'] * 17 + ['ok@2000', 'skip@3000'])

    def survival_case(seed, actions):
        game, steps = Survival(pool, seed), []
        for kind in actions:
            if kind == 'ok':
                game.answer(game.card['word'])
            elif kind == 'ko':
                game.answer('ZZZ')
            else:
                game.skip()
            steps.append((kind, game.card['id'] if game.card else '', game.card['difficulty'] if game.card else '', game.lives, game.found, game.level, game.gained, game.finished))
        out['survival'].append((seed, steps))

    survival_case(42, ['ko', 'ko'] + ['ok'] * 10 + ['skip'] + ['ok'] * 25 + ['ko', 'ko', 'ko'])
    survival_case(99, ['ok'] * 3 + ['skip', 'ko', 'ok', 'ko'])

    def duo_case(seed, actions):
        game, steps = DuoGame(duos, seed), []
        for action in actions:
            kind, t = action.split('@')
            t = int(t)
            duo = game.duos[min(game.round, len(game.duos) - 1)]
            if kind == 'a':
                game.answer(duo['first'][0], t)
            elif kind == 'b':
                game.answer(duo['second'][0], t)
            elif kind == 'ko':
                game.answer('ZZZ', t)
            elif kind == 'skip':
                game.skip(t)
            else:
                game.next(t)
            steps.append((action, game.round, game.words_found(), game.solved(), game.errors, game.play_ms(t), game.record(t), game.finished))
        out['duo'].append((seed, [d['id'] for d in game.duos], steps))

    duo_case(42, ['a@4000', 'ko@6000', 'b@9000', 'next@15000', 'b@20000', 'a@21000', 'next@22000', 'a@30000', 'skip@40000', 'next@41000',
                  'b@50000', 'a@51000', 'next@60000', 'a@61000', 'b@62000'])
    duo_case(5, ['b@1000', 'a@2000', 'next@2500', 'a@3000', 'b@4000', 'next@4000', 'b@5000', 'a@6000', 'next@6000', 'a@7000', 'b@8000',
                 'next@8000', 'a@9000', 'b@10000'])
    duo_case(77, ['skip@500000', 'next@500000', 'ko@500001', 'skip@500002', 'next@500002', 'skip@500003', 'next@500003', 'skip@500004',
                  'next@500004', 'a@900000', 'skip@900000'])
    return out


# ---- Code generation

def swift_string(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def kotlin_string(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$') + '"'


HEADER = 'Généré par Scripts/generate_content.py depuis Shared/{}. Ne pas modifier à la main.'


def swift_cards(cards):
    lines = [f'// {HEADER.format("cards.tsv")}', 'import Foundation', '',
             '/// Classique cards added in version 1.0, also played in Sprint and Survie. Ids are the', '/// normalized word, so they never shift when the list grows.',
             'public enum ExtraCards {', '    public static let all: [Card] = ['] 
    lines += [f'        Card(id: {swift_string(c["id"])}, wordFull: {swift_string(c["word"])}, hint: {swift_string(c["hint"])}, category: .{c["category"]}, difficulty: .{c["difficulty"]}),' for c in cards]
    lines += ['    ]', '}', '']
    return '\n'.join(lines)


def kotlin_cards(cards):
    lines = [f'// {HEADER.format("cards.tsv")}', 'package com.poupoutch.cnsnn.core', '',
             '/** Classique cards added in version 1.0, also played in Sprint and Survie (same ids as Core/ExtraCards.swift). */',
             'object ExtraCards {', '    val all: List<Card> = listOf(']
    lines += [f'        Card({kotlin_string(c["id"])}, {kotlin_string(c["word"])}, {kotlin_string(c["hint"])}, Category.{KOTLIN_CATEGORIES[c["category"]]}, Difficulty.{c["difficulty"].upper()}),' for c in cards]
    lines += ['    )', '}', '']
    return '\n'.join(lines)


def swift_duos(duos):
    lines = [f'// {HEADER.format("duos.tsv")}', 'import Foundation', '', '/// Double sens: two different French words with exactly the same consonants.', 'public enum DuoBank {', '    public static let all: [Duo] = [']
    lines += [f'        Duo(id: {swift_string(d["id"])}, first: DuoWord(word: {swift_string(d["first"][0])}, hint: {swift_string(d["first"][1])}), second: DuoWord(word: {swift_string(d["second"][0])}, hint: {swift_string(d["second"][1])})),' for d in duos]
    lines += ['    ]', '}', '']
    return '\n'.join(lines)


def kotlin_duos(duos):
    lines = [f'// {HEADER.format("duos.tsv")}', 'package com.poupoutch.cnsnn.core', '', '/** Double sens: two different French words with exactly the same consonants (same list as Core/Duos.swift). */', 'object DuoBank {', '    val all: List<Duo> = listOf(']
    lines += [f'        Duo({kotlin_string(d["id"])}, DuoWord({kotlin_string(d["first"][0])}, {kotlin_string(d["first"][1])}), DuoWord({kotlin_string(d["second"][0])}, {kotlin_string(d["second"][1])})),' for d in duos]
    lines += ['    )', '}', '']
    return '\n'.join(lines)


def vector_rows(s, lang):
    """The scenarios as plain literals (strings, integers, booleans) in Swift or Kotlin."""
    q = swift_string if lang == 'swift' else kotlin_string
    lst = (lambda items: '[' + ', '.join(items) + ']') if lang == 'swift' else (lambda items: 'listOf(' + ', '.join(items) + ')')
    b = lambda v: 'true' if v else 'false'
    u = (lambda v: str(v)) if lang == 'swift' else (lambda v: f'{v}uL')
    out = {}
    out['random'] = [f'RandomCase(seed: {u(seed)}, values: {lst([u(v) for v in values])}, mod97: {mod})' if lang == 'swift' else
                     f'RandomCase({u(seed)}, {lst([u(v) for v in values])}, {mod})' for seed, values, mod in s['random']]
    def sprint_step(st):
        a, card, streak, found, wrong, skips, remaining, fin = st
        return (f'SprintStep(action: {q(a)}, card: {q(card)}, streak: {streak}, found: {found}, wrong: {wrong}, skips: {skips}, remainingMs: {remaining}, finished: {b(fin)})' if lang == 'swift'
                else f'SprintStep({q(a)}, {q(card)}, {streak}, {found}, {wrong}, {skips}, {remaining}, {b(fin)})')
    out['sprint'] = [(f'SprintCase(seed: {u(seed)}, first: {q(first)}, steps: {lst([sprint_step(x) for x in steps])}, bestCombo: {best})' if lang == 'swift'
                      else f'SprintCase({u(seed)}, {q(first)}, {lst([sprint_step(x) for x in steps])}, {best})') for seed, first, steps, best in s['sprint']]
    def survival_step(st):
        a, card, level_name, lives, found, level, gained, fin = st
        return (f'SurvivalStep(action: {q(a)}, card: {q(card)}, difficulty: {q(level_name)}, lives: {lives}, found: {found}, level: {level}, gained: {gained}, finished: {b(fin)})' if lang == 'swift'
                else f'SurvivalStep({q(a)}, {q(card)}, {q(level_name)}, {lives}, {found}, {level}, {gained}, {b(fin)})')
    out['survival'] = [(f'SurvivalCase(seed: {u(seed)}, steps: {lst([survival_step(x) for x in steps])})' if lang == 'swift'
                        else f'SurvivalCase({u(seed)}, {lst([survival_step(x) for x in steps])})') for seed, steps in s['survival']]
    def duo_step(st):
        a, rnd, found, solved, errors, ms, record, fin = st
        return (f'DuoStep(action: {q(a)}, round: {rnd}, found: {found}, solved: {solved}, errors: {errors}, playMs: {ms}, record: {record}, finished: {b(fin)})' if lang == 'swift'
                else f'DuoStep({q(a)}, {rnd}, {found}, {solved}, {errors}, {ms}, {record}, {b(fin)})')
    out['challenge'] = [(f'ChallengeCase(seed: {u(seed)}, recent: {lst([q(i) for i in recent])}, cards: {lst([q(i) for i in ids])})' if lang == 'swift'
                         else f'ChallengeCase({u(seed)}, {lst([q(i) for i in recent])}, {lst([q(i) for i in ids])})') for seed, recent, ids in s['challenge']]
    out['duo'] = [(f'DuoCase(seed: {u(seed)}, duos: {lst([q(i) for i in ids])}, steps: {lst([duo_step(x) for x in steps])})' if lang == 'swift'
                   else f'DuoCase({u(seed)}, {lst([q(i) for i in ids])}, {lst([duo_step(x) for x in steps])})') for seed, ids, steps in s['duo']]
    return out


def swift_vectors(s):
    v = vector_rows(s, 'swift')
    body = lambda key: ',\n'.join('        ' + row for row in v[key])
    return f'''// Généré par Scripts/generate_content.py (règles de référence en Python). Ne pas modifier à la main.
// Rejoué aussi par Android (ModeVectors.kt) : les deux applications doivent trouver les mêmes résultats.
import Foundation

struct RandomCase {{ let seed: UInt64; let values: [UInt64]; let mod97: Int }}
struct SprintStep {{ let action: String; let card: String; let streak: Int; let found: Int; let wrong: Int; let skips: Int; let remainingMs: Int; let finished: Bool }}
struct SprintCase {{ let seed: UInt64; let first: String; let steps: [SprintStep]; let bestCombo: Int }}
struct SurvivalStep {{ let action: String; let card: String; let difficulty: String; let lives: Int; let found: Int; let level: Int; let gained: Int; let finished: Bool }}
struct SurvivalCase {{ let seed: UInt64; let steps: [SurvivalStep] }}
struct DuoStep {{ let action: String; let round: Int; let found: Int; let solved: Int; let errors: Int; let playMs: Int; let record: Int; let finished: Bool }}
struct DuoCase {{ let seed: UInt64; let duos: [String]; let steps: [DuoStep] }}
struct ChallengeCase {{ let seed: UInt64; let recent: [String]; let cards: [String] }}

enum ModeVectors {{
    static let random: [RandomCase] = [
{body('random')}
    ]
    static let sprint: [SprintCase] = [
{body('sprint')}
    ]
    static let survival: [SurvivalCase] = [
{body('survival')}
    ]
    static let duo: [DuoCase] = [
{body('duo')}
    ]
    static let challenge: [ChallengeCase] = [
{body('challenge')}
    ]
}}
'''


def kotlin_vectors(s):
    v = vector_rows(s, 'kotlin')
    body = lambda key: ',\n'.join('        ' + row for row in v[key])
    return f'''// Généré par Scripts/generate_content.py (règles de référence en Python). Ne pas modifier à la main.
// Rejoué aussi par l'iPhone (Tests/Core/ModeVectors.swift) : les deux applications doivent trouver les mêmes résultats.
package com.poupoutch.cnsnn.core

data class RandomCase(val seed: ULong, val values: List<ULong>, val mod97: Int)
data class SprintStep(val action: String, val card: String, val streak: Int, val found: Int, val wrong: Int, val skips: Int, val remainingMs: Int, val finished: Boolean)
data class SprintCase(val seed: ULong, val first: String, val steps: List<SprintStep>, val bestCombo: Int)
data class SurvivalStep(val action: String, val card: String, val difficulty: String, val lives: Int, val found: Int, val level: Int, val gained: Int, val finished: Boolean)
data class SurvivalCase(val seed: ULong, val steps: List<SurvivalStep>)
data class DuoStep(val action: String, val round: Int, val found: Int, val solved: Int, val errors: Int, val playMs: Int, val record: Int, val finished: Boolean)
data class DuoCase(val seed: ULong, val duos: List<String>, val steps: List<DuoStep>)
data class ChallengeCase(val seed: ULong, val recent: List<String>, val cards: List<String>)

object ModeVectors {{
    val random = listOf(
{body('random')}
    )
    val sprint = listOf(
{body('sprint')}
    )
    val survival = listOf(
{body('survival')}
    )
    val duo = listOf(
{body('duo')}
    )
    val challenge = listOf(
{body('challenge')}
    )
}}
'''


def outputs():
    seeds, cards = load_cards()
    duos = load_duos()
    pool = sorted(seeds + cards, key=lambda c: c['id'])
    sorted_duos = sorted(duos, key=lambda d: d['id'])
    s = scenarios(pool, sorted_duos)
    return {
        ROOT / 'Core/ExtraCards.swift': swift_cards(cards),
        KOTLIN_CORE / 'ExtraCards.kt': kotlin_cards(cards),
        ROOT / 'Core/Duos.swift': swift_duos(duos),
        KOTLIN_CORE / 'Duos.kt': kotlin_duos(duos),
        ROOT / 'Tests/Core/ModeVectors.swift': swift_vectors(s),
        KOTLIN_TEST / 'ModeVectors.kt': kotlin_vectors(s),
    }, seeds, cards, duos


def main():
    try:
        files, seeds, cards, duos = outputs()
    except Invalid as error:
        sys.exit(f'Contenu invalide : {error}')
    if '--words' in sys.argv:
        for c in seeds + cards:
            print('carte', normalize(c['word']))
        for d in duos:
            print('duo', normalize(d['first'][0]))
            print('duo', normalize(d['second'][0]))
        return
    stale = [path for path, text in files.items() if not path.exists() or path.read_text(encoding='utf-8') != text]
    if '--check' in sys.argv:
        if stale:
            sys.exit('Fichiers générés à refaire (python3 Scripts/generate_content.py) : ' + ', '.join(str(p.relative_to(ROOT)) for p in stale))
    else:
        for path in stale:
            path.write_text(files[path], encoding='utf-8')
    counts = {level: sum(1 for c in seeds + cards if c['difficulty'] == level) for level in ORDER}
    print(f'{len(cards)} nouvelles cartes ({len(seeds) + len(cards)} en tout : {counts["easy"]} faciles, {counts["medium"]} moyennes, {counts["hard"]} difficiles), {len(duos)} duos.')


if __name__ == '__main__':
    main()
