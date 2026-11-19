#!/usr/bin/env python3
"""Static pre-flight checks for the EW27Player Swift sources.

There is no Swift compiler on this device, so this catches the classes of
mistake that actually break the CI build: unbalanced delimiters, a
ViewModifier without the required `func body(content:)`, calls to design
system helpers with argument labels that do not exist, references to
symbols that were removed, and duplicate type declarations.
"""
import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else "EW27Player")

US = "\x00"  # placeholder for characters inside strings/comments


def strip_code(src: str) -> str:
    """Blank out comments and string literals, preserving line structure."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            depth = 1
            out.append("  ")
            i += 2
            while i < n and depth:
                if src.startswith("/*", i):
                    depth += 1
                    out.append("  ")
                    i += 2
                elif src.startswith("*/", i):
                    depth -= 1
                    out.append("  ")
                    i += 2
                else:
                    out.append("\n" if src[i] == "\n" else " ")
                    i += 1
            continue
        if src.startswith('"""', i):
            out.append("   ")
            i += 3
            while i < n and not src.startswith('"""', i):
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            out.append("   ")
            i += 3
            continue
        if c == '"':
            out.append(" ")
            i += 1
            while i < n:
                if src[i] == "\\":
                    out.append(" ")
                    i += 1
                    if i < n:
                        out.append(" ")
                        i += 1
                    continue
                if src[i] == '"':
                    out.append(" ")
                    i += 1
                    break
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def split_top(s: str, sep: str = ",") -> list:
    """Split on `sep` at bracket depth 0."""
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        if ch == sep and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts if p.strip()]


def labels_of(params: str) -> list:
    out = []
    for p in split_top(params):
        head = p.split(":")[0].strip()
        if not head:
            continue
        # `label name` or `name` (single identifier means label == name)
        out.append(head.split()[0])
    return out


def main() -> int:
    files = sorted(ROOT.rglob("*.swift"))
    if not files:
        print(f"no .swift files under {ROOT}")
        return 2

    errors, warnings = [], []
    cleaned = {}

    # 1. delimiter balance
    for f in files:
        raw = f.read_text()
        code = strip_code(raw)
        cleaned[f] = code
        for open_c, close_c in (("{", "}"), ("(", ")"), ("[", "]")):
            if code.count(open_c) != code.count(close_c):
                errors.append(
                    f"{f}: unbalanced {open_c}{close_c} "
                    f"({code.count(open_c)} vs {code.count(close_c)})"
                )

    # 2. ViewModifier must define func body(content: Content)
    for f, code in cleaned.items():
        for m in re.finditer(r"struct\s+(\w+)\s*:\s*[^{]*ViewModifier\b[^{]*\{", code):
            name = m.group(1)
            tail = code[m.end(): m.end() + 800]
            if not re.search(r"func\s+body\s*\(\s*content\s*:\s*Content\s*\)", tail):
                errors.append(
                    f"{f}: {name} conforms to ViewModifier but has no "
                    f"`func body(content: Content)`"
                )

    # 3. design-system declarations in `extension View`
    declared = {}
    for f, code in cleaned.items():
        for ext in re.finditer(r"extension\s+View\s*\{", code):
            depth, i = 1, ext.end()
            while i < len(code) and depth:
                if code[i] == "{":
                    depth += 1
                elif code[i] == "}":
                    depth -= 1
                i += 1
            body = code[ext.end(): i - 1]
            for fn in re.finditer(
                r"func\s+(\w+)\s*(<[^>]*>)?\(([^)]*)\)\s*->\s*some\s+View", body
            ):
                declared.setdefault(fn.group(1), set()).update(labels_of(fn.group(3)))

    # 4. call sites of those helpers
    for f, code in cleaned.items():
        for m in re.finditer(r"\.(\w+)\s*\(", code):
            name = m.group(1)
            if name not in declared:
                continue
            depth, i = 1, m.end()
            while i < len(code) and depth:
                if code[i] == "(":
                    depth += 1
                elif code[i] == ")":
                    depth -= 1
                i += 1
            args = code[m.end(): i - 1]
            used = set(labels_of(args))
            unknown = used - declared[name]
            if unknown:
                line = code[: m.start()].count("\n") + 1
                errors.append(
                    f"{f}:{line}: .{name}(...) uses unknown label(s) "
                    f"{sorted(unknown)}; declared {sorted(declared[name])}"
                )

    # 4b. memberwise-init labels for simple structs
    def block_body(code: str, start: int) -> str:
        depth, i = 1, start
        while i < len(code) and depth:
            if code[i] == "{":
                depth += 1
            elif code[i] == "}":
                depth -= 1
            i += 1
        return code[start: i - 1]

    def stored_props(body: str) -> list:
        props, depth = [], 0
        for stmt in body.replace(";", "\n").splitlines():
            line = stmt.strip()
            if depth == 0:
                m = re.match(
                    r"(?:@\w+(?:\([^)]*\))?\s+)*(?:var|let)\s+(\w+)\s*(?::|=)", line
                )
                if m and "{" not in line:
                    props.append(m.group(1))
            depth += stmt.count("{") - stmt.count("}")
        return props

    structs = {}
    for f, code in cleaned.items():
        for m in re.finditer(r"struct\s+(\w+)[^{]*\{", code):
            body = block_body(code, m.end())
            if re.search(r"\binit\s*\(", body):
                continue
            props = stored_props(body)
            if props:
                structs[m.group(1)] = props

    for f, code in cleaned.items():
        for name, props in structs.items():
            for m in re.finditer(r"(?<![.\w])" + name + r"\s*\(", code):
                args = block_body(code, m.end())
                if "{" in args or "\n" in args.strip():
                    continue
                bad = [u for u in labels_of(args) if u not in props]
                if bad:
                    line = code[: m.start()].count("\n") + 1
                    errors.append(
                        f"{f}:{line}: {name}(...) unknown label(s) {bad}; "
                        f"stored properties are {props}"
                    )

    # 5. removed / undefined design-system symbols
    for f, code in cleaned.items():
        if "LiquidGlassModifier" in code:
            errors.append(f"{f}: references removed symbol LiquidGlassModifier")

    # 6. duplicate top-level type declarations
    seen = {}
    for f, code in cleaned.items():
        for m in re.finditer(r"^\s*(?:public\s+|internal\s+|private\s+|final\s+)*"
                             r"(?:struct|class|enum|actor)\s+(\w+)", code, re.M):
            seen.setdefault(m.group(1), []).append(str(f))
    for name, where in seen.items():
        if len(where) > 1:
            warnings.append(f"type {name} declared in {len(where)} files: {where}")

    print(f"checked {len(files)} files")
    print(f"design-system helpers: {', '.join(sorted(declared)) or '(none)'}")
    for w in warnings:
        print("WARN  ", w)
    for e in errors:
        print("ERROR ", e)
    if not errors:
        print("OK — no blocking issues found")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
