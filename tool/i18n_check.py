"""Фразы интерфейса без перевода: все t('…') в lib/ против словарей assets/i18n/*.json.
Запуск: python -I -X utf8 tool/i18n_check.py [--keys out.json]
--keys — записать недостающие фразы в файл (для пакетного добавления переводов).
"""
import glob
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
T_RE = re.compile(r"""\bt\(\s*'((?:[^'\\]|\\.)*)'""")


def keys_in_code():
    out = {}
    for f in glob.glob(str(ROOT / 'lib' / '**' / '*.dart'), recursive=True):
        text = Path(f).read_text(encoding='utf-8')
        for m in T_RE.finditer(text):
            key = m.group(1).replace("\\'", "'").replace('\\$', '$')
            out.setdefault(key, Path(f).relative_to(ROOT).as_posix())
    return out


def main():
    code = keys_in_code()
    missing_any = {}
    for f in sorted(glob.glob(str(ROOT / 'assets' / 'i18n' / '*.json'))):
        d = json.loads(Path(f).read_text(encoding='utf-8'))
        miss = [k for k in code if k not in d]
        for k in miss:
            missing_any[k] = code[k]
        print(f'{Path(f).name}: нет {len(miss)}')
    if missing_any:
        print('\nНет перевода:')
        for k, f in missing_any.items():
            print(f'  {k}    ({f})')
    if '--keys' in sys.argv:
        Path(sys.argv[sys.argv.index('--keys') + 1]).write_text(json.dumps(missing_any, ensure_ascii=False, indent=1), encoding='utf-8')


if __name__ == '__main__':
    main()
