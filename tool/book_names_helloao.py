"""Названия книг Библии на языках переводов каталога — из открытого API helloao (bible.helloao.org).
Для каждого языка — перевод с наибольшим числом книг; берём commonName (обиходное название).
Выход: G:/aobible-flutter/swift/Kolos/Resources/book-names.json  {lang: {OSIS: name}}"""
import json, sys, time, urllib.request, os, unicodedata
sys.stdout.reconfigure(encoding='utf-8')

OUT = r'G:\aobible-flutter\swift\Kolos\Resources\book-names.json'
WORK = os.path.dirname(os.path.abspath(sys.argv[1]))
avail = json.load(open(sys.argv[1], encoding='utf-8'))['translations']

LANGS = {
    'grc': ['grc'], 'en': ['eng'], 'zh': ['cmn', 'zho', 'chi'], 'fr': ['fra'], 'de': ['deu'], 'be': ['bel'], 'hu': ['hun'],
    'uk': ['ukr'], 'pt': ['por'], 'ja': ['jpn'], 'ro': ['ron'], 'it': ['ita'], 'fi': ['fin'], 'pl': ['pol'], 'he': ['heb', 'hbo'],
    'hr': ['hrv'], 'ar': ['arb', 'ara'], 'sw': ['swh', 'swa'], 'vi': ['vie'], 'la': ['lat'], 'sq': ['als', 'sqi'], 'id': ['ind'],
    'hy': ['hye'], 'da': ['dan'], 'sr': ['srp'], 'et': ['ekk', 'est'], 'eo': ['epo'], 'lv': ['lvs', 'lav'], 'hi': ['hin'],
    'ko': ['kor'], 'cs': ['ces'], 'nb': ['nob', 'nor'], 'fa': ['pes', 'fas'], 'syr': ['syc', 'syr'], 'es': ['spa'], 'sk': ['slk'],
    'nl': ['nld'], 'sv': ['swe'], 'tl': ['tgl'], 'tr': ['tur'], 'el': ['ell'], 'bg': ['bul'], 'ka': ['kat'],
}

USFM = {
    'GEN': 'Gen', 'EXO': 'Exod', 'LEV': 'Lev', 'NUM': 'Num', 'DEU': 'Deut', 'JOS': 'Josh', 'JDG': 'Judg', 'RUT': 'Ruth',
    '1SA': '1Sam', '2SA': '2Sam', '1KI': '1Kgs', '2KI': '2Kgs', '1CH': '1Chr', '2CH': '2Chr', 'EZR': 'Ezra', 'NEH': 'Neh',
    'EST': 'Esth', 'JOB': 'Job', 'PSA': 'Ps', 'PRO': 'Prov', 'ECC': 'Eccl', 'SNG': 'Song', 'ISA': 'Isa', 'JER': 'Jer',
    'LAM': 'Lam', 'EZK': 'Ezek', 'DAN': 'Dan', 'HOS': 'Hos', 'JOL': 'Joel', 'AMO': 'Amos', 'OBA': 'Obad', 'JON': 'Jonah',
    'MIC': 'Mic', 'NAM': 'Nah', 'HAB': 'Hab', 'ZEP': 'Zeph', 'HAG': 'Hag', 'ZEC': 'Zech', 'MAL': 'Mal',
    'MAT': 'Matt', 'MRK': 'Mark', 'LUK': 'Luke', 'JHN': 'John', 'ACT': 'Acts', 'ROM': 'Rom', '1CO': '1Cor', '2CO': '2Cor',
    'GAL': 'Gal', 'EPH': 'Eph', 'PHP': 'Phil', 'COL': 'Col', '1TH': '1Thess', '2TH': '2Thess', '1TI': '1Tim', '2TI': '2Tim',
    'TIT': 'Titus', 'PHM': 'Phlm', 'HEB': 'Heb', 'JAS': 'Jas', '1PE': '1Pet', '2PE': '2Pet', '1JN': '1John', '2JN': '2John',
    '3JN': '3John', 'JUD': 'Jude', 'REV': 'Rev',
    'TOB': 'Tob', 'JDT': 'Jdt', 'WIS': 'Wis', 'SIR': 'Sir', 'BAR': 'Bar', 'LJE': 'EpJer', '1MA': '1Macc', '2MA': '2Macc',
    '3MA': '3Macc', '1ES': '1Esd', '2ES': '2Esd', 'MAN': 'PrMan', 'PS2': 'Ps151', 'SUS': 'Sus', 'BEL': 'Bel',
}

def get(path):
    for _ in range(3):
        try:
            with urllib.request.urlopen('https://bible.helloao.org' + path, timeout=40) as r:
                return json.load(r)
        except Exception as e:
            err = e
            time.sleep(2)
    raise err

# переводы с лучшими названиями (ударения, обычный регистр, не английские) — первыми; остальные книги — из следующих
PREFER = {
    'grc': ['grc_sr', 'grc_bre'], 'ja': ['jpn_kou', 'jpn_meb'], 'cs': ['ces_bkr', 'ces_bib'], 'ro': ['ron_btf', 'ron_wp'],
    'he': ['hbo_wlc', 'heb_lbm', 'heb_mod'], 'uk': ['ukr_npu', 'ukr_1996'], 'it': ['ita_riv'], 'vi': ['vie_vcb'],
    'id': ['ind_obo', 'ind_tsi', 'ind_ayt'], 'en': ['BSB', 'eng_kjv', 'AAB'],
}
EN = {}

def is_caps(n):
    letters = [c for c in n if c.isalpha()]
    return letters and all(not c.islower() for c in letters) and any(c.isupper() for c in letters)

def is_lower(n):
    letters = [c for c in n if c.isalpha()]
    return letters and all(c.islower() for c in letters)

ROMAN = {'I', 'II', 'III', 'IV'}
def word_case(w):
    if w in ROMAN: return w
    for i, c in enumerate(w):
        if c.isalpha():
            return w[:i] + c.upper() + w[i + 1:].lower()
    return w

def tr_case(n):
    # турецкий: I ↔ ı, İ ↔ i
    out = []
    for w in n.split():
        low = w.replace('I', 'ı').replace('İ', 'i').lower()
        if w in ROMAN or not low[:1].isalpha():
            out.append(w if w in ROMAN else low)
            continue
        first = {'ı': 'I', 'i': 'İ'}.get(low[0], low[0].upper())
        out.append(first + low[1:])
    return ' '.join(out)

def normal(n):
    n = ' '.join(n.split())
    if is_caps(n) or is_lower(n):
        n = ' '.join(word_case(w) for w in n.split(' '))
    return n

SR = [('Dž', 'Џ'), ('dž', 'џ'), ('Lj', 'Љ'), ('lj', 'љ'), ('Nj', 'Њ'), ('nj', 'њ')]
SR1 = dict(zip('ABVGDĐEŽZIJKLMNOPRSTĆUFHCČŠabvgdđežzijklmnoprstćufhcčš', 'АБВГДЂЕЖЗИЈКЛМНОПРСТЋУФХЦЧШабвгдђежзијклмнопрстћуфхцчш'))
def sr_cyr(n):
    for a, b in SR: n = n.replace(a, b)
    return ''.join(SR1.get(c, c) for c in n)

def names_of(tid):
    out = {}
    for b in get('/api/%s/books.json' % tid)['books']:
        osis = USFM.get(b.get('id'))
        n = (b.get('commonName') or b.get('name') or '').strip()
        if osis and n: out[osis] = n
    return out

out = {}
order = ['en'] + [l for l in LANGS if l != 'en']
for lang in order:
    codes = LANGS[lang]
    cands = [t['id'] for t in avail if t.get('language') in codes]
    rest = sorted((t for t in avail if t.get('language') in codes), key=lambda t: -(t.get('numberOfBooks') or 0))
    ids = [x for x in PREFER.get(lang, []) if x in cands] + [t['id'] for t in rest if t['id'] not in PREFER.get(lang, [])]
    res, used = {}, []
    for tid in ids[:8]:
        try:
            names = names_of(tid)
        except Exception as e:
            print(lang, tid, 'ошибка', e)
            continue
        # перевод с английскими названиями книг (их больше половины) — не берём; совпадения вроде «Ruth» — норма
        if lang != 'en' and names:
            same = sum(1 for k, v in names.items() if EN.get(k) and v.lower() == EN[k].lower())
            if same * 2 > len(names): continue
        added = 0
        for k, v in names.items():
            if k in res: continue
            if lang in ('ar', 'fa'): v = unicodedata.normalize('NFKC', v)
            v = tr_case(v) if lang == 'tr' and is_caps(v) else normal(v)
            res[k] = v
            added += 1
        if added: used.append(tid)
        if len(res) >= 66: break
    if lang == 'sr': res = {k: sr_cyr(v) for k, v in res.items()}
    if lang == 'en': EN.update(res)
    if res:
        out[lang] = res
    print(lang, used, len(res), res.get('Gen'), '|', res.get('Matt'), '|', res.get('1Tim'))

# точечные поправки источника
FIX = {'tr': {'Zech': 'Zekeriya', '1Sam': '1. Samuel'}}
for l, d in FIX.items():
    if l in out: out[l].update(d)

json.dump(out, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'), sort_keys=True)
print('записано', OUT, os.path.getsize(OUT))
