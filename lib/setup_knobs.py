#!/usr/bin/env python3
"""dots-tailscale 의 setup.sh 에 직접 넣은 TS_ 환경변수를 찾아내고 tsnet.conf 값과 합칩니다.

사용법:
  setup_knobs.py extract 원본파일 설치된파일
      원본과 달라진 곳이 TS_이름=값 추가뿐이면 그 값을 한 줄에 하나씩 출력하고 0 으로 끝납니다.
      다른 변경이 섞여 있으면 이유를 표준 오류로 알리고 1 로 끝납니다.
  setup_knobs.py merge "기존 값" TS_이름=값 ...
      같은 이름은 새 값으로 바꾸고, 새 이름은 뒤에 붙인 결과를 출력합니다.
"""
import difflib
import re
import sys

SAFE = r"[A-Za-z0-9._:/,-]*"
VALUE = r"(?:\"%s\"|'%s'|%s)" % (SAFE, SAFE, SAFE)
ASSIGN = re.compile(r"(TS_[A-Z0-9_]+)=(%s)" % VALUE)
PREFIX = re.compile(r"(?:TS_[A-Z0-9_]+=%s\s+)+" % VALUE)
KNOB_LINE = re.compile(r"\s*(?:export\s+)?((?:TS_[A-Z0-9_]+=%s\s*)+)" % VALUE)
FILLER = re.compile(r"\s*(?:#.*)?")
ITEM = re.compile(r"TS_[A-Z0-9_]+=%s" % SAFE)


class OtherChange(Exception):
    """TS_ 설정 말고 다른 변경이 있을 때 씁니다."""


def items_from(text):
    items = []
    for name, value in ASSIGN.findall(text):
        if value[:1] in "\"'":
            value = value[1:-1]
        items.append("%s=%s" % (name, value))
    return items


def prefixed_knobs(old, new):
    """new 가 old 앞에 TS_ 할당만 붙인 줄이면 그 할당을, 아니면 None 을 돌려줍니다."""
    old, new = old.strip(), new.strip()
    if old == new:
        return []
    if not old or not new.endswith(old):
        return None
    prefix = new[: len(new) - len(old)]
    return items_from(prefix) if PREFIX.fullmatch(prefix) else None


def added_knobs(line):
    """새로 끼어든 줄이 TS_ 할당이나 빈 줄, 주석이면 그 할당을, 아니면 None 을 돌려줍니다."""
    match = KNOB_LINE.fullmatch(line)
    if match:
        return items_from(match.group(1))
    return [] if FILLER.fullmatch(line) else None


def extract(pristine, installed):
    old_lines, new_lines = pristine.splitlines(), installed.splitlines()
    found = []
    matcher = difflib.SequenceMatcher(None, old_lines, new_lines, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        # 원본에서 사라져도 되는 줄은 빈 줄과 주석뿐입니다. 나머지 원본 줄은 순서대로 남아 있어야 하고,
        # 앞에 TS_ 할당이 붙는 것만 허용합니다.
        olds = [line for line in old_lines[i1:i2] if not FILLER.fullmatch(line)]
        k = 0
        for line in new_lines[j1:j2]:
            if k < len(olds):
                knobs = prefixed_knobs(olds[k], line)
                if knobs is not None:
                    found += knobs
                    k += 1
                    continue
            knobs = added_knobs(line)
            if knobs is None:
                raise OtherChange("바뀌거나 추가된 줄: " + line.strip()[:120])
            found += knobs
        if k < len(olds):
            raise OtherChange("원본에서 사라진 줄: " + olds[k].strip()[:120])
    return merge("", found).split()


def merge(existing, items):
    order, values = [], {}
    for item in existing.split() + list(items):
        if not ITEM.fullmatch(item):
            raise ValueError(item)
        name, value = item.split("=", 1)
        if name not in values:
            order.append(name)
        values[name] = value
    return " ".join("%s=%s" % (name, values[name]) for name in order)


def read(path):
    with open(path, encoding="utf-8", errors="surrogateescape") as stream:
        return stream.read()


def main(argv):
    if len(argv) == 3 and argv[0] == "extract":
        try:
            knobs = extract(read(argv[1]), read(argv[2]))
        except OSError as error:
            print("setup_knobs: 파일을 읽지 못했습니다: %s" % error, file=sys.stderr)
            return 2
        except OtherChange as error:
            print(str(error), file=sys.stderr)
            return 1
        if knobs:
            print("\n".join(knobs))
        return 0
    if len(argv) >= 2 and argv[0] == "merge":
        try:
            print(merge(argv[1], argv[2:]))
        except ValueError as error:
            print("setup_knobs: TS_이름=값 형식이 아닙니다: %s" % error, file=sys.stderr)
            return 2
        return 0
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
