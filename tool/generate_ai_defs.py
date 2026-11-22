#!/usr/bin/env python3
"""Generate AI learner entries for the COCA headwords.

For every word the model writes one entry: a Chinese note on the modern high-
frequency meaning and usage, the collocations that matter, three example
sentences with Chinese translations, and a ~100-word passage using the word a
few times. Answers are written verbatim into the app's existing shape
(`text` / `translation` / `phrases`), so the archive needs no adapter.

Word order comes from coca-60000.txt (see tool/extract_coca_mdx.py), ranks and
per-POS frequency from the MDX itself. Generation is resumable: every finished
part lands in content/coca-ai/parts/ and words already covered there are
skipped on the next run. Run tool/assemble_ai_defs.py afterwards to build
content/coca-ai/words.jsonl.

    python tool/generate_ai_defs.py --limit 1000 --workers 8

Endpoint: --base-url/--api-key/--model, else DICT_AI_BASE_URL/DICT_AI_API_KEY/
DICT_AI_MODEL, else the app's own saved settings in shared_preferences.json.
"""

import argparse
import concurrent.futures
import json
import os
import re
import sys
import threading
import time
from functools import lru_cache
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parent.parent
WORDS_TXT = ROOT / "coca-60000.txt"
OUT_DIR = ROOT / "content" / "coca-ai"
PART_DIR = OUT_DIR / "parts"
PREFS = Path(os.environ.get("APPDATA", "")) / "com.example" / "local_dict" / "shared_preferences.json"

CJK = re.compile(r"[\u4e00-\u9fff]")
EN_WORD = re.compile(r"[A-Za-z][A-Za-z'’-]*")


IRREGULAR = {
    "be": ["am", "is", "are", "was", "were", "been", "being"],
    "have": ["has", "had", "having"],
    "do": ["does", "did", "done", "doing"],
    "go": ["goes", "went", "gone", "going"],
    "say": ["says", "said", "saying"],
    "get": ["gets", "got", "gotten", "getting"],
    "make": ["makes", "made", "making"],
    "take": ["takes", "took", "taken", "taking"],
    "come": ["comes", "came", "coming"],
    "see": ["sees", "saw", "seen", "seeing"],
    "know": ["knows", "knew", "known", "knowing"],
    "think": ["thinks", "thought", "thinking"],
    "give": ["gives", "gave", "given", "giving"],
    "find": ["finds", "found", "finding"],
    "tell": ["tells", "told", "telling"],
    "feel": ["feels", "felt", "feeling"],
    "leave": ["leaves", "left", "leaving"],
    "bring": ["brings", "brought", "bringing"],
    "begin": ["begins", "began", "begun", "beginning"],
    "keep": ["keeps", "kept", "keeping"],
    "hold": ["holds", "held", "holding"],
    "write": ["writes", "wrote", "written", "writing"],
    "stand": ["stands", "stood", "standing"],
    "hear": ["hears", "heard", "hearing"],
    "mean": ["means", "meant", "meaning"],
    "meet": ["meets", "met", "meeting"],
    "run": ["runs", "ran", "running"],
    "pay": ["pays", "paid", "paying"],
    "sit": ["sits", "sat", "sitting"],
    "speak": ["speaks", "spoke", "spoken", "speaking"],
    "read": ["reads", "reading"],
    "grow": ["grows", "grew", "grown", "growing"],
    "lose": ["loses", "lost", "losing"],
    "fall": ["falls", "fell", "fallen", "falling"],
    "send": ["sends", "sent", "sending"],
    "build": ["builds", "built", "building"],
    "break": ["breaks", "broke", "broken", "breaking"],
    "spend": ["spends", "spent", "spending"],
    "cut": ["cuts", "cutting"],
    "drive": ["drives", "drove", "driven", "driving"],
    "buy": ["buys", "bought", "buying"],
    "wear": ["wears", "wore", "worn", "wearing"],
    "choose": ["chooses", "chose", "chosen", "choosing"],
    "sell": ["sells", "sold", "selling"],
    "teach": ["teaches", "taught", "teaching"],
    "eat": ["eats", "ate", "eaten", "eating"],
    "drink": ["drinks", "drank", "drunk", "drinking"],
    "sleep": ["sleeps", "slept", "sleeping"],
    "fly": ["flies", "flew", "flown", "flying"],
    "swim": ["swims", "swam", "swum", "swimming"],
    "sing": ["sings", "sang", "sung", "singing"],
    "win": ["wins", "won", "winning"],
    "stride": ["strides", "strode", "striding"],
    "child": ["children"],
    "person": ["people"],
    "man": ["men"],
    "woman": ["women"],
    "foot": ["feet"],
    "tooth": ["teeth"],
    "mouse": ["mice"],
    "life": ["lives"],
    "knife": ["knives"],
    "wife": ["wives"],
}

IRREGULAR.update({
    "arise": ["arises", "arose", "arisen", "arising"],
    "awake": ["awakes", "awoke", "awoken", "awaking"],
    "bear": ["bears", "bore", "borne", "bearing"],
    "beat": ["beats", "beaten", "beating"],
    "become": ["becomes", "became", "becoming"],
    "bend": ["bends", "bent", "bending"],
    "bet": ["bets", "betting"],
    "bind": ["binds", "bound", "binding"],
    "bite": ["bites", "bit", "bitten", "biting"],
    "bleed": ["bleeds", "bled", "bleeding"],
    "blow": ["blows", "blew", "blown", "blowing"],
    "breed": ["breeds", "bred", "breeding"],
    "broadcast": ["broadcasts", "broadcasting"],
    "burst": ["bursts", "bursting"],
    "cast": ["casts", "casting"],
    "catch": ["catches", "caught", "catching"],
    "cling": ["clings", "clung", "clinging"],
    "cost": ["costs", "costing"],
    "creep": ["creeps", "crept", "creeping"],
    "deal": ["deals", "dealt", "dealing"],
    "dig": ["digs", "dug", "digging"],
    "dive": ["dives", "dove", "dived", "diving"],
    "draw": ["draws", "drew", "drawn", "drawing"],
    "dream": ["dreams", "dreamed", "dreamt", "dreaming"],
    "feed": ["feeds", "fed", "feeding"],
    "fight": ["fights", "fought", "fighting"],
    "flee": ["flees", "fled", "fleeing"],
    "fling": ["flings", "flung", "flinging"],
    "forbid": ["forbids", "forbade", "forbidden", "forbidding"],
    "forgive": ["forgives", "forgave", "forgiven", "forgiving"],
    "freeze": ["freezes", "froze", "frozen", "freezing"],
    "hang": ["hangs", "hung", "hanging"],
    "hide": ["hides", "hid", "hidden", "hiding"],
    "hit": ["hits", "hitting"],
    "hurt": ["hurts", "hurting"],
    "lay": ["lays", "laid", "laying"],
    "lead": ["leads", "led", "leading"],
    "lend": ["lends", "lent", "lending"],
    "let": ["lets", "letting"],
    "lie": ["lies", "lay", "lain", "lying"],
    "light": ["lights", "lit", "lighting"],
    "prove": ["proves", "proved", "proven", "proving"],
    "ride": ["rides", "rode", "ridden", "riding"],
    "ring": ["rings", "rang", "rung", "ringing"],
    "rise": ["rises", "rose", "risen", "rising"],
    "seek": ["seeks", "sought", "seeking"],
    "shake": ["shakes", "shook", "shaken", "shaking"],
    "shine": ["shines", "shone", "shining"],
    "shoot": ["shoots", "shot", "shooting"],
    "shut": ["shuts", "shutting"],
    "sink": ["sinks", "sank", "sunk", "sinking"],
    "slide": ["slides", "slid", "sliding"],
    "sow": ["sows", "sowed", "sown", "sowing"],
    "spit": ["spits", "spat", "spitting"],
    "split": ["splits", "splitting"],
    "spread": ["spreads", "spreading"],
    "spring": ["springs", "sprang", "sprung", "springing"],
    "steal": ["steals", "stole", "stolen", "stealing"],
    "stick": ["sticks", "stuck", "sticking"],
    "sting": ["stings", "stung", "stinging"],
    "stink": ["stinks", "stank", "stunk", "stinking"],
    "strike": ["strikes", "struck", "striking"],
    "swear": ["swears", "swore", "sworn", "swearing"],
    "sweep": ["sweeps", "swept", "sweeping"],
    "swing": ["swings", "swung", "swinging"],
    "tear": ["tears", "tore", "torn", "tearing"],
    "throw": ["throws", "threw", "thrown", "throwing"],
    "wake": ["wakes", "woke", "woken", "waking"],
    "weep": ["weeps", "wept", "weeping"],
    "wind": ["winds", "wound", "winding"],
    "withdraw": ["withdraws", "withdrew", "withdrawn", "withdrawing"],
    "wring": ["wrings", "wrung", "wringing"],
    "analysis": ["analyses"],
    "basis": ["bases"],
    "crisis": ["crises"],
    "thesis": ["theses"],
    "phenomenon": ["phenomena"],
    "criterion": ["criteria"],
    "medium": ["media"],
    "datum": ["data"],
    "index": ["indices", "indexes"],
    "matrix": ["matrices"],
    "vertex": ["vertices"],
    "leaf": ["leaves"],
    "half": ["halves"],
    "shelf": ["shelves"],
    "wolf": ["wolves"],
    "thief": ["thieves"],
    "good": ["better", "best"],
    "bad": ["worse", "worst"],
    "far": ["farther", "further", "farthest", "furthest"],
    "overgrow": ["overgrows", "overgrew", "overgrown", "overgrowing"],
    "co-write": ["co-writes", "co-wrote", "co-written", "co-writing"],
    "strew": ["strews", "strewed", "strewn", "strewing"],
    "sling": ["slings", "slung", "slinging"],
    "antenna": ["antennae", "antennas"],
    "formula": ["formulae", "formulas"],
    "larva": ["larvae"],
    "alga": ["algae"],
    "vertebra": ["vertebrae"],
    "cactus": ["cacti", "cactuses"],
    "fungus": ["fungi", "funguses"],
    "nucleus": ["nuclei", "nucleuses"],
    "radius": ["radii", "radiuses"],
    "stimulus": ["stimuli"],
    "syllabus": ["syllabi", "syllabuses"],
    "alumnus": ["alumni"],
    "bacterium": ["bacteria"],
    "minutia": ["minutiae"],
    "underpay": ["underpaid", "underpays", "underpaying"],
    "overpay": ["overpaid", "overpays", "overpaying"],
    "repay": ["repaid", "repays", "repaying"],
    "prepay": ["prepaid", "prepays", "prepaying"],
    "forsake": ["forsook", "forsaken", "forsakes", "forsaking"],
    "smite": ["smote", "smitten", "smites", "smiting"],
    "kneel": ["kneels", "knelt", "kneeled", "kneeling"],
    "lean": ["leans", "leaned", "leant", "leaning"],
    "leap": ["leaps", "leaped", "leapt", "leaping"],
    "learn": ["learns", "learned", "learnt", "learning"],
    "sew": ["sews", "sewed", "sewn", "sewing"],
    "shave": ["shaves", "shaved", "shaven", "shaving"],
    "show": ["shows", "showed", "shown", "showing"],
    "shrink": ["shrinks", "shrank", "shrunk", "shrinking"],
    "slay": ["slays", "slew", "slain", "slaying"],
    "slit": ["slits", "slitting"],
    "smell": ["smells", "smelled", "smelt", "smelling"],
    "speed": ["speeds", "sped", "speeded", "speeding"],
    "spell": ["spells", "spelled", "spelt", "spelling"],
    "spill": ["spills", "spilled", "spilt", "spilling"],
    "spin": ["spins", "spun", "spinning"],
    "spoil": ["spoils", "spoiled", "spoilt", "spoiling"],
    "string": ["strings", "strung", "stringing"],
    "strive": ["strives", "strove", "striven", "striving"],
    "swell": ["swells", "swelled", "swollen", "swelling"],
    "thrust": ["thrusts", "thrusting"],
    "tread": ["treads", "trod", "trodden", "treading"],
    "weave": ["weaves", "wove", "woven", "weaving"],
    "put": ["puts", "putting"],
    "set": ["sets", "setting"],
    "upset": ["upsets", "upsetting"],
    "quit": ["quits", "quitting"],
    "rid": ["rids", "ridding"],
    "shed": ["sheds", "shedding"],
    "bid": ["bids", "bidding"],
    "forecast": ["forecasts", "forecasting"],
    "shoot": ["shoots", "shot", "shooting"],
    "overtake": ["overtook", "overtaken", "overtakes", "overtaking"],
    "overcome": ["overcame", "overcomes", "overcoming"],
    "oversee": ["oversaw", "overseen", "oversees", "overseeing"],
    "oversleep": ["overslept", "oversleeps", "oversleeping"],
    "overthrow": ["overthrew", "overthrown", "overthrows", "overthrowing"],
    "overrun": ["overran", "overruns", "overrunning"],
    "overdo": ["overdid", "overdone", "overdoes", "overdoing"],
    "overeat": ["overate", "overeaten", "overeats", "overeating"],
    "overdraw": ["overdrew", "overdrawn", "overdraws", "overdrawing"],
    "overwrite": ["overwrote", "overwritten", "overwrites", "overwriting"],
    "overhang": ["overhung", "overhangs", "overhanging"],
    "overbuild": ["overbuilt", "overbuilds", "overbuilding"],
    "undertake": ["undertook", "undertaken", "undertakes", "undertaking"],
    "understand": ["understood", "understands", "understanding"],
    "underwrite": ["underwrote", "underwritten", "underwrites", "underwriting"],
    "undercut": ["undercuts", "undercutting"],
    "foresee": ["foresaw", "foreseen", "foresees", "foreseeing"],
    "foretell": ["foretold", "foretells", "foretelling"],
    "forego": ["forewent", "foregone", "foregoes", "foregoing"],
    "withhold": ["withheld", "withholds", "withholding"],
    "withstand": ["withstood", "withstands", "withstanding"],
    "understood": ["understands", "understanding"],
    "misunderstand": ["misunderstood", "misunderstands", "misunderstanding"],
    "elf": ["elves"],
    "calf": ["calves"],
    "loaf": ["loaves"],
    "scarf": ["scarves", "scarfs"],
    "self": ["selves"],
    "dwarf": ["dwarves", "dwarfs"],
    "hoof": ["hooves", "hoofs"],
    "wharf": ["wharves", "wharfs"],
    "housewife": ["housewives"],
    "midwife": ["midwives"],
    "sheaf": ["sheaves"],
    "overhear": ["overheard", "overhears", "overhearing"],
    "louse": ["lice"],
    "goose": ["geese"],
    "ox": ["oxen"],
    "overspend": ["overspent", "overspends", "overspending"],
    "underspend": ["underspent", "underspends", "underspending"],
    "misspend": ["misspent", "misspends", "misspending"],
    "parenthesis": ["parentheses"],
    "diagnosis": ["diagnoses"],
    "emphasis": ["emphases"],
    "hypothesis": ["hypotheses"],
    "oasis": ["oases"],
    "axis": ["axes"],
    "synthesis": ["syntheses"],
    "prognosis": ["prognoses"],
    "paralysis": ["paralyses"],
    "ellipsis": ["ellipses"],
    "synopsis": ["synopses"],
    "interweave": ["interwove", "interwoven", "interweaves", "interweaving"],
    "interbreed": ["interbred", "interbreeds", "interbreeding"],
    "lentils": ["lentil"],
    "gluteus": ["glutes", "glutei"],
    "bacillus": ["bacilli"],
    "locus": ["loci", "locuses"],
    "genus": ["genera", "genuses"],
    "corpus": ["corpora", "corpuses"],
    "accomodate": ["accommodate", "accommodates", "accommodated", "accommodating"],
    "mitochondrion": ["mitochondria"],
    "polyhedron": ["polyhedra", "polyhedrons"],
    "automaton": ["automata", "automatons"],
    "ganglion": ["ganglia", "ganglions"],
    "desideratum": ["desiderata"],
    "stratum": ["strata"],
    "addendum": ["addenda", "addendums"],
    "erratum": ["errata"],
    "ovum": ["ova"],
    "symposium": ["symposia", "symposiums"],
    "millennium": ["millennia", "millenniums"],
    "spectrum": ["spectra", "spectrums"],
    "quantum": ["quanta", "quantums"],
    "curriculum": ["curricula", "curriculums"],
    "memorandum": ["memoranda", "memorandums"],
    "referendum": ["referenda", "referendums"],
    "maximum": ["maxima", "maximums"],
    "minimum": ["minima", "minimums"],
    "optimum": ["optima", "optimums"],
    "paramecium": ["paramecia"],
    "occurence": ["occurrence", "occurrences"],
    "rend": ["rent", "rends", "rending"],
    "befall": ["befell", "befallen", "befalls", "befalling"],
    "outdo": ["outdid", "outdone", "outdoes", "outdoing"],
    "outgrow": ["outgrew", "outgrown", "outgrows", "outgrowing"],
    "outrun": ["outran", "outruns", "outrunning"],
    "outsell": ["outsold", "outsells", "outselling"],
    "outshine": ["outshone", "outshines", "outshining"],
    "outbid": ["outbids", "outbidding"],
    "outthink": ["outthought", "outthinks", "outthinking"],
})


def plural_heads(word):
    """Plural forms of a compound's head noun (lady → ladies, man → men)."""
    out = set(IRREGULAR.get(word, []))
    if word.endswith("y") and len(word) > 2 and word[-2] not in "aeiou":
        out.add(word[:-1] + "ies")
    if word.endswith(("s", "x", "z", "ch", "sh")):
        out.add(word + "es")
    out.add(word + "s")
    out.discard(word)
    return out


@lru_cache(maxsize=8192)
def word_forms(needle):
    """The headword plus its regular inflections; irregulars come from the map."""
    forms = {needle, *IRREGULAR.get(needle, [])}
    if needle in US_UK:
        forms |= word_forms(US_UK[needle])
    for tail in sorted(IRREGULAR, key=len, reverse=True):
        if len(tail) >= 2 and needle.endswith(tail) and needle != tail:
            prefix = needle[: -len(tail)]
            for form in word_forms(tail):
                forms.add(prefix + form)
            break
    if len(needle) >= 3 and all(part.isalpha() for part in re.split(r"[-']", needle)):
        forms.add(needle + "s")
        forms.add(needle + "ed")
        forms.add(needle + "ing")
        if needle.endswith("man"):
            forms.add(needle[:-3] + "men")
        if "-" in needle:
            head, _, tail = needle.partition("-")
            forms.add(head + "s-" + tail)
            for plural in plural_heads(head):
                forms.add(plural + needle[len(head):])
            spaced = needle.replace("-", " ")
            forms.add(spaced)
            forms.add(spaced + "s")
            forms.add(needle.replace("-", ""))
        if needle.endswith("e"):
            forms.add(needle + "d")
            forms.add(needle[:-1] + "ing")
            if needle.endswith("ie"):
                forms.add(needle[:-2] + "ying")
        if needle.endswith("y") and needle[-2] not in "aeiou":
            forms.add(needle[:-1] + "ies")
            forms.add(needle[:-1] + "ied")
        if len(needle) >= 3 and needle[-1] not in "aeiouwy" and needle[-2] in "aeiou":
            forms.add(needle + needle[-1] + "ed")
            forms.add(needle + needle[-1] + "ing")
        if needle.endswith(("s", "x", "z", "ch", "sh")):
            forms.add(needle + "es")
        if needle.endswith("o") and needle[-2] not in "aeiou":
            forms.add(needle + "es")
        for tail, replacements in (
            ("child", ("children",)),
            ("man", ("men",)),
            ("woman", ("women",)),
            ("person", ("people",)),
            ("foot", ("feet",)),
            ("tooth", ("teeth",)),
            ("mouse", ("mice",)),
            ("goose", ("geese",)),
            ("louse", ("lice",)),
            ("ox", ("oxen",)),
        ):
            if needle.endswith(tail) and needle != tail:
                for replacement in replacements:
                    forms.add(needle[: -len(tail)] + replacement)
    return frozenset(forms)


def adverb_forms(needle):
    """-ly forms of an adjective (vicarious → vicariously)."""
    out = {needle + "ly"}
    if needle.endswith("y") and len(needle) > 2 and needle[-2] not in "aeiou":
        out.add(needle[:-1] + "ily")
    if needle.endswith("ic"):
        out.add(needle + "ally")
    if needle.endswith("le"):
        out.add(needle[:-1] + "y")
    if needle.endswith("ue"):
        out.add(needle[:-2] + "uly")
    return out


BOUND_SUFFIXES = {"ness", "wright", "ade", "semitism"}
SLASH_SPLIT = re.compile(r"\s*/\s*")
US_UK = {
    "dependant": "dependent",
    "enquiry": "inquiry",
    "colour": "color",
    "favour": "favor",
    "honour": "honor",
    "labour": "labor",
    "neighbour": "neighbor",
    "behaviour": "behavior",
    "centre": "center",
    "metre": "meter",
    "litre": "liter",
    "theatre": "theater",
    "defence": "defense",
    "offence": "offense",
    "licence": "license",
    "practise": "practice",
    "organise": "organize",
    "realise": "realize",
    "analyse": "analyze",
    "recognise": "recognize",
    "apologise": "apologize",
    "criticise": "criticize",
    "emphasise": "emphasize",
    "summarise": "summarize",
    "traveller": "traveler",
    "counsellor": "counselor",
    "jewellery": "jewelry",
    "programme": "program",
    "catalogue": "catalog",
    "grey": "gray",
}


def occurrences(needle, text, pos=None):
    """Whole-word hits of the headword, its inflections, and adjective adverbs."""
    if "/" in needle:
        return sum(occurrences(part, text, pos) for part in SLASH_SPLIT.split(needle) if part)
    if needle in BOUND_SUFFIXES:
        return len(re.findall(r"(?<![A-Za-z])[A-Za-z]*" + re.escape(needle) + r"(?![A-Za-z])", text, re.I))
    forms = set(word_forms(needle))
    if pos and any("adj" in p for p in pos):
        forms |= adverb_forms(needle)
    if pos and any("adv" in p for p in pos) and needle.endswith("ly"):
        base = needle[:-3] + "y" if needle.endswith("ily") else needle[:-2]
        forms |= word_forms(base)
    total = 0
    for form in forms:
        if "'" in form:
            total += len(re.findall(re.escape(form) + r"(?![A-Za-z])", text, re.I))
        else:
            total += len(
                re.findall(
                    r"(?<![A-Za-z])" + re.escape(form) + r"(?![A-Za-z])", text, re.I
                )
            )
    return total

SYSTEM = """\
You write learner entries for a Chinese-speaking learner of American English. \
You answer with JSON only: no prose, no markdown fences, no commentary.

Rules for every entry:
- Teach only the most common modern uses. Never explain archaic, rare, technical or bookish senses. If a word has one frequent and one rare meaning, the rare one does not exist for you.
- For function words (the, of, to, a, in, that, ...), explain the grammatical job they do and the uses people actually produce, not dictionary definitions.
- Chinese must read like a good teacher's note: concrete, natural, no translationese, no "该词表示" boilerplate.
- English must be idiomatic modern American English at B1-B2 level: natural situations, no clichés, no textbook stiffness, no showing off with rare vocabulary.
- Examples are moments, not definitions. Never write "X means ..." or "X is used to ..." in an English sentence.
- Vary sentence shapes: no two sentences in one entry may open the same way, and at most one may join clauses with ", and".
- The headword appears naturally in the examples and the passage. Never bold it, cap it, quote it or mark it in any way.
- Every field is required. No empty strings, no placeholders.
"""

USER_TEMPLATE = """\
Write learner entries for these {n} words:

{word_lines}

Return JSON exactly in this shape:
{{"items":[{{"word":"...","meaning_zh":"...","usage_zh":"...","collocations":["..."],\
"sentences":[{{"text":"...","translation":"...","phrases":["..."]}}],\
"passage":{{"title":"...","text":"...","phrases":["..."]}}}}]}}

Field rules:
- meaning_zh: 2-4 Chinese sentences. Part of speech, the one or two senses that matter today, and how the word behaves in a sentence (what follows it, what it modifies).
- usage_zh: 2-5 Chinese sentences. High-frequency collocations (write the English collocation in English inside the Chinese sentence), register, typical situations, and the specific mistakes Chinese learners make with this word. This is the part that stops them memorizing the wrong thing.
- collocations: 6-10 English collocations in base form, not full sentences, most frequent modern ones only.
- sentences: exactly 3 objects. text is one natural sentence of 8-20 words, each in a different everyday situation, and the headword — or its normal plural/past/-ing form when that is the natural choice — appears in it. translation is natural simplified Chinese. phrases holds 1-3 collocations copied verbatim from text.
- passage: title of 3-6 English words; text of 95-115 English words, one coherent scene or story (not a definition), where the headword or a normal inflected form of it appears at least twice (very common function words may appear more often). phrases holds 1-3 collocations copied verbatim from text, or [].
- Special forms: "n't" is the contracted negative glued to auxiliaries (don't, isn't, won't, can't); explain and use it that way. The pronoun i is always written I in English and that is the only allowed capitalization. Use the ASCII apostrophe ' in every English field.
"""


def ascii_apostrophe(text):
    return text.replace("\u2019", "'").replace("\u2018", "'")


def load_settings():
    if not PREFS.is_file():
        return {}
    prefs = json.loads(PREFS.read_text(encoding="utf-8"))
    return {
        "base_url": prefs.get("flutter.ai_base_url", ""),
        "api_key": prefs.get("flutter.ai_api_key", ""),
        "model": prefs.get("flutter.ai_model", ""),
    }


def load_word_rows(mdx_path):
    """word -> (best_rank, total_freq, [pos, ...]) from the COCA MDX."""
    from mdict_utils.base.readmdict import MDX

    rows = {}
    for key, data in MDX(mdx_path).items():
        word = key.decode("utf-8")
        found = re.findall(
            r"<div class='pos'>(.*?)</div><div class='rank'>(\d+)</div>"
            r"<div class='freq'>(\d+)</div>",
            data.decode("utf-8"),
        )
        if not found:
            raise ValueError(f"entry {word!r} has no frequency rows")
        rank = min(int(r) for _, r, _ in found)
        freq = sum(int(f) for _, _, f in found)
        rows[word] = (rank, freq, [p for p, _, _ in found])
    return rows


def word_lines(items):
    lines = []
    for i, item in enumerate(items, 1):
        lines.append(
            f"{i}. {item['word']} — part of speech: {', '.join(item['pos'])} — "
            f"COCA rank {item['rank']}, frequency {item['freq']}"
        )
    return "\n".join(lines)


def check_entry(entry, expected):
    """Return (cleaned_entry, problems). Empty problems means usable."""
    problems = []
    if str(entry.get("word", "")).strip().lower() != expected["word"].lower():
        return None, [f"word mismatch: {entry.get('word')!r}"]

    meaning = str(entry.get("meaning_zh", "")).strip()
    usage = str(entry.get("usage_zh", "")).strip()
    if len(meaning) < 30 or not CJK.search(meaning):
        problems.append("meaning_zh too short or not Chinese")
    if len(usage) < 30 or not CJK.search(usage):
        problems.append("usage_zh too short or not Chinese")

    collocations = [
        ascii_apostrophe(str(c).strip())
        for c in entry.get("collocations", [])
        if str(c).strip()
    ]
    if not 4 <= len(collocations) <= 12:
        problems.append(f"collocations: {len(collocations)}")
    if any(CJK.search(c) for c in collocations):
        problems.append("collocations contain Chinese")

    needle = expected["word"].lower()
    sentences = []
    for raw in entry.get("sentences", []):
        text = ascii_apostrophe(str(raw.get("text", "")).strip())
        translation = str(raw.get("translation", "")).strip()
        if CJK.search(text):
            problems.append("sentence text contains Chinese")
            continue
        if not 6 <= len(EN_WORD.findall(text)) <= 28:
            problems.append(f"sentence length: {text!r}")
            continue
        if occurrences(needle, text, expected["pos"]) < 1:
            problems.append(f"sentence does not use {needle}: {text!r}")
            continue
        if len(translation) < 4 or not CJK.search(translation):
            problems.append(f"missing translation: {text!r}")
            continue
        phrases = [
            ascii_apostrophe(str(p).strip())
            for p in raw.get("phrases", [])
            if str(p).strip() and ascii_apostrophe(str(p).strip()).lower() in text.lower()
        ][:3]
        sentences.append({"text": text, "translation": translation, "phrases": phrases})
    if not 2 <= len(sentences) <= 4:
        problems.append(f"sentences: {len(sentences)}")

    raw_passage = entry.get("passage") or {}
    title = ascii_apostrophe(str(raw_passage.get("title", "")).strip())
    passage = ascii_apostrophe(str(raw_passage.get("text", "")).strip())
    if CJK.search(title) or CJK.search(passage):
        problems.append("passage contains Chinese")
    if not 2 <= len(EN_WORD.findall(title)) <= 7:
        problems.append(f"passage title: {title!r}")
    count = len(EN_WORD.findall(passage))
    if not 78 <= count <= 130:
        problems.append(f"passage words: {count}")
    hits = occurrences(needle, passage, expected["pos"])
    if hits < 2:
        problems.append(f"passage uses the word {hits} time(s)")
    phrases = [
        ascii_apostrophe(str(p).strip())
        for p in raw_passage.get("phrases", [])
        if str(p).strip() and ascii_apostrophe(str(p).strip()).lower() in passage.lower()
    ][:3]

    if problems:
        return None, problems
    return {
        "word": needle,
        "source_word": expected["word"],
        "rank": expected["rank"],
        "freq": expected["freq"],
        "pos": expected["pos"],
        "meaning_zh": meaning,
        "usage_zh": usage,
        "collocations": collocations,
        "sentences": sentences,
        "passage": {"title": title, "text": passage, "phrases": phrases},
    }, []


def existing_entries():
    entries = {}
    for path in sorted(PART_DIR.glob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                entry = json.loads(line)
                entries[entry["source_word"]] = entry
    return entries


def write_part(name, entries):
    path = PART_DIR / f"{name}.jsonl"
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        for entry in entries:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")


class Runner:
    def __init__(self, args, total):
        self.args = args
        self.total = total
        self.local = threading.local()
        self.lock = threading.Lock()
        self.done = 0
        self.failed = []

    @property
    def session(self):
        session = getattr(self.local, "session", None)
        if session is None:
            session = self.local.session = requests.Session()
        return session

    def call(self, items):
        user = USER_TEMPLATE.format(n=len(items), word_lines=word_lines(items))
        payload = {
            "model": self.args.model,
            "messages": [
                {"role": "system", "content": SYSTEM},
                {"role": "user", "content": user},
            ],
            "temperature": 0.6,
            "max_tokens": 4096,
        }
        if not self.args.no_json_mode:
            payload["response_format"] = {"type": "json_object"}
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        if self.args.api_key:
            headers["Authorization"] = f"Bearer {self.args.api_key}"
        resp = self.session.post(
            self.args.base_url.rstrip("/") + "/chat/completions",
            headers=headers,
            json=payload,
            timeout=300,
        )
        if resp.status_code == 400 and "response_format" in resp.text and not self.args.no_json_mode:
            self.args.no_json_mode = True
            return self.call(items)
        resp.raise_for_status()
        body = resp.json()
        choice = body["choices"][0]
        return choice["message"]["content"], choice.get("finish_reason"), body.get("usage", {})

    def attempt(self, items):
        """One model call -> (entries, problems)."""
        content, finish, usage = self.call(items)
        text = content.strip()
        if text.startswith("```"):
            text = text.split("```")[1]
            if text.startswith("json"):
                text = text[4:]
        data = json.loads(text)
        parsed = data["items"] if isinstance(data, dict) else data
        by_word = {
            str(e.get("word", "")).strip().lower(): e
            for e in parsed
            if isinstance(e, dict)
        }
        entries, problems = [], []
        for expected in items:
            raw = by_word.get(expected["word"].lower())
            if raw is None:
                problems.append(f"missing entry for {expected['word']!r}")
                continue
            cleaned, errs = check_entry(raw, expected)
            if cleaned is None:
                problems.extend(f"{expected['word']}: {e}" for e in errs)
            else:
                entries.append(cleaned)
        if problems:
            return [], problems + ([f"finish={finish}"] if finish != "stop" else []), usage
        return entries, [], usage

    def batch(self, index, items):
        last = ""
        for attempt in range(1, 4):
            try:
                entries, problems, usage = self.attempt(items)
                if entries:
                    with self.lock:
                        write_part(f"api_{index:04d}", entries)
                        self.done += len(entries)
                        print(
                            f"[{self.done:4d}/{self.total}] part {index}: "
                            f"{len(entries)} entries, {usage.get('completion_tokens', '?')} out tokens",
                            flush=True,
                        )
                    return
                last = "; ".join(problems[:8])
            except Exception as exc:  # noqa: BLE001 - surfaced in the retry message
                last = f"{type(exc).__name__}: {exc}"
                if "429" in str(exc):
                    time.sleep(8 * attempt)
            time.sleep(2 * attempt)
        with self.lock:
            self.failed.append((index, items, last))
        print(f"[batch-fail] part {index}: {last}", flush=True)

    def single(self, word, expected, index):
        last = ""
        for attempt in range(1, 3):
            try:
                entries, problems, _ = self.attempt([expected])
                if entries:
                    with self.lock:
                        write_part(f"api_s{index:04d}", entries)
                        self.done += 1
                        print(f"[{self.done:4d}/{self.total}] single: {word}", flush=True)
                    return True
                last = "; ".join(problems[:6])
            except Exception as exc:  # noqa: BLE001
                last = f"{type(exc).__name__}: {exc}"
            time.sleep(2 * attempt)
        print(f"[word-fail] {word}: {last}", flush=True)
        return False


def main():
    ap = argparse.ArgumentParser(description="Generate AI learner entries for COCA headwords.")
    ap.add_argument("--limit", type=int, default=1000)
    ap.add_argument("--start", type=int, default=0)
    ap.add_argument("--batch", type=int, default=4)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--mdx", default=str(Path.home() / "Downloads" / "COCA Frequency 60,000 — 2020.mdx"))
    ap.add_argument("--base-url", default=os.environ.get("DICT_AI_BASE_URL", ""))
    ap.add_argument("--api-key", default=os.environ.get("DICT_AI_API_KEY", ""))
    ap.add_argument("--model", default=os.environ.get("DICT_AI_MODEL", ""))
    args = ap.parse_args()

    if not args.base_url or not args.model or not args.api_key:
        saved = load_settings()
        args.base_url = args.base_url or saved.get("base_url", "")
        args.api_key = args.api_key or saved.get("api_key", "")
        args.model = args.model or saved.get("model", "")
    if not (args.base_url and args.model):
        sys.exit("no endpoint: pass --base-url/--model or configure the app first")
    args.no_json_mode = False

    words = [w for w in WORDS_TXT.read_text(encoding="utf-8").splitlines() if w]
    targets = words[args.start:args.start + args.limit]
    rows = load_word_rows(args.mdx)
    missing = [w for w in targets if w not in rows]
    if missing:
        sys.exit(f"words missing from the MDX: {missing[:5]}")

    PART_DIR.mkdir(parents=True, exist_ok=True)
    have = existing_entries()
    todo = [
        {"word": w, "rank": rows[w][0], "freq": rows[w][1], "pos": rows[w][2]}
        for w in targets
        if w not in have
    ]
    print(f"targets: {len(targets)}, already done: {len(targets) - len(todo)}, todo: {len(todo)}")

    runner = Runner(args, len(targets))
    runner.done = len(targets) - len(todo)

    next_index = 1 + max(
        [int(m.group(1)) for p in PART_DIR.glob("api_*.jsonl") for m in [re.search(r"api_(\d+)", p.stem)] if m],
        default=0,
    )
    batches = [todo[i:i + args.batch] for i in range(0, len(todo), args.batch)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(runner.batch, next_index + i, batch): batch
            for i, batch in enumerate(batches)
        }
        for future in concurrent.futures.as_completed(futures):
            future.result()

    # One word per call for whatever a batch refused: contractions and short
    # function words are where validation most often rejects a batch.
    single_index = 1 + max(
        [int(m.group(1)) for p in PART_DIR.glob("api_s*.jsonl") for m in [re.search(r"api_s(\d+)", p.stem)] if m],
        default=0,
    )
    for _batch_index, items, _error in runner.failed:
        for item in items:
            expected = next(e for e in todo if e["word"] == item["word"])
            runner.single(item["word"], expected, single_index)
            single_index += 1

    covered = sum(1 for w in targets if w in existing_entries())
    print(f"parts cover {covered}/{len(targets)} words")
    print("next: python tool/assemble_ai_defs.py --limit", args.limit)
    if covered < len(targets):
        sys.exit("some words are still missing; rerun to retry")


if __name__ == "__main__":
    main()
