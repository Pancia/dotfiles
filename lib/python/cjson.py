#!/usr/bin/env python3
"""
CJSON - Compact JSON encoder/decoder

Compresses JSON using:
1. Dictionary aliases for repeated strings
2. Tabular format for homogeneous arrays
"""

import argparse
import json
import sys
from collections import Counter
from typing import Any


ESCAPE_PREFIX = "$$"  # Literal $ becomes $$
ALIAS_PREFIX = "$"
RESERVED_KEYS = {"_dict", "_data", "_cols", "_rows"}


def scan_strings(obj: Any, counter: Counter | None = None) -> Counter:
    """Recursively count all string occurrences in a JSON structure."""
    if counter is None:
        counter = Counter()

    if isinstance(obj, str):
        counter[obj] += 1
    elif isinstance(obj, dict):
        for key, value in obj.items():
            counter[key] += 1
            scan_strings(value, counter)
    elif isinstance(obj, list):
        for item in obj:
            scan_strings(item, counter)

    return counter


def generate_aliases():
    """Generate short aliases: a-z, a0-z9, a00-z99, etc."""
    # Single letters
    for c in "abcdefghijklmnopqrstuvwxyz":
        yield c
    # Letter + digit
    for c in "abcdefghijklmnopqrstuvwxyz":
        for d in "0123456789":
            yield f"{c}{d}"
    # Letter + two digits
    for c in "abcdefghijklmnopqrstuvwxyz":
        for d1 in "0123456789":
            for d2 in "0123456789":
                yield f"{c}{d1}{d2}"


def calculate_savings(string: str, alias: str, occurrences: int) -> int:
    """
    Calculate byte savings from aliasing a string.

    Original cost: (len(string) + 2) * occurrences  # +2 for quotes
    With alias:
      - Dict entry: len(alias) + len(string) + 6  # "$a":"value",
      - References: (len(alias) + 3) * occurrences  # "$a" each time (+1 for $)
    """
    original_bytes = (len(string) + 2) * occurrences
    dict_entry_cost = len(alias) + len(string) + 6
    alias_ref_cost = (len(alias) + 3) * occurrences  # $ + alias + quotes
    new_cost = dict_entry_cost + alias_ref_cost
    return original_bytes - new_cost


def build_dictionary(counter: Counter, min_freq: int = 2) -> dict[str, str]:
    """
    Build alias dictionary for strings worth compressing.
    Returns {original_string: alias}
    """
    alias_gen = generate_aliases()
    result = {}

    # Sort by frequency * length (most savings first)
    candidates = [
        (string, count)
        for string, count in counter.items()
        if count >= min_freq
    ]
    candidates.sort(key=lambda x: x[1] * len(x[0]), reverse=True)

    for string, count in candidates:
        alias = next(alias_gen)
        if calculate_savings(string, alias, count) > 0:
            result[string] = alias

    return result


def is_homogeneous_array(arr: list) -> bool:
    """Check if array contains objects with identical key sets."""
    if len(arr) < 2:
        return False
    if not all(isinstance(x, dict) for x in arr):
        return False
    if not arr[0]:  # Empty first dict
        return False
    keys = tuple(sorted(arr[0].keys()))
    return all(tuple(sorted(x.keys())) == keys for x in arr)


def escape_dollar(s: str) -> str:
    """Escape strings starting with $ to avoid alias collision."""
    if s.startswith(ALIAS_PREFIX):
        return ESCAPE_PREFIX + s[1:]
    return s


def unescape_dollar(s: str) -> str:
    """Unescape $$ back to $."""
    if s.startswith(ESCAPE_PREFIX):
        return ALIAS_PREFIX + s[2:]
    return s


def escape_reserved_key(key: str) -> str:
    """Escape reserved keys by prefixing with underscore."""
    if key in RESERVED_KEYS:
        return "_" + key
    return key


def unescape_reserved_key(key: str) -> str:
    """Unescape reserved keys."""
    if key.startswith("_") and key[1:] in RESERVED_KEYS:
        return key[1:]
    return key


def apply_alias(value: str, alias_map: dict[str, str]) -> str:
    """Apply alias to a string value, or escape if needed."""
    if value in alias_map:
        return ALIAS_PREFIX + alias_map[value]
    return escape_dollar(value)


def encode_key(key: str, alias_map: dict[str, str]) -> str:
    """Encode a dict key with escaping and aliasing."""
    escaped = escape_reserved_key(key)
    return apply_alias(escaped, alias_map)


def encode_value(obj: Any, alias_map: dict[str, str]) -> Any:
    """Recursively encode a JSON value with aliases and tabular format."""
    if isinstance(obj, str):
        return apply_alias(obj, alias_map)

    elif isinstance(obj, dict):
        return {
            encode_key(k, alias_map): encode_value(v, alias_map)
            for k, v in obj.items()
        }

    elif isinstance(obj, list):
        if is_homogeneous_array(obj):
            # Convert to tabular format
            cols = list(obj[0].keys())
            encoded_cols = [apply_alias(c, alias_map) for c in cols]
            rows = [
                [encode_value(item[col], alias_map) for col in cols]
                for item in obj
            ]
            return {"_cols": encoded_cols, "_rows": rows}
        else:
            return [encode_value(item, alias_map) for item in obj]

    else:
        return obj


def encode(obj: Any, min_freq: int = 2) -> Any:
    """Encode JSON to CJSON format."""
    original_is_dict = isinstance(obj, dict)
    counter = scan_strings(obj)
    alias_map = build_dictionary(counter, min_freq)

    encoded = encode_value(obj, alias_map)

    if alias_map:
        # Build reverse dict for output: {alias: original}
        output_dict = {alias: original for original, alias in alias_map.items()}
        if original_is_dict:
            return {"_dict": output_dict, **encoded}
        else:
            return {"_dict": output_dict, "_data": encoded}
    else:
        return encoded


def expand_alias(value: str, reverse_dict: dict[str, str]) -> str:
    """Expand an alias or unescape a $$ string."""
    if value.startswith(ESCAPE_PREFIX):
        return unescape_dollar(value)
    elif value.startswith(ALIAS_PREFIX):
        alias = value[1:]
        if alias in reverse_dict:
            return reverse_dict[alias]
    return value


def decode_key(key: str, reverse_dict: dict[str, str]) -> str:
    """Decode a dict key by expanding alias and unescaping."""
    expanded = expand_alias(key, reverse_dict) if isinstance(key, str) else key
    if isinstance(expanded, str):
        return unescape_reserved_key(expanded)
    return expanded


def decode_value(obj: Any, reverse_dict: dict[str, str]) -> Any:
    """Recursively decode a CJSON value."""
    if isinstance(obj, str):
        return expand_alias(obj, reverse_dict)

    elif isinstance(obj, dict):
        # Check for tabular format
        if "_cols" in obj and "_rows" in obj and len(obj) == 2:
            cols = [decode_key(c, reverse_dict) for c in obj["_cols"]]
            rows = obj["_rows"]
            return [
                {col: decode_value(val, reverse_dict) for col, val in zip(cols, row)}
                for row in rows
            ]
        else:
            return {
                decode_key(k, reverse_dict): decode_value(v, reverse_dict)
                for k, v in obj.items()
            }

    elif isinstance(obj, list):
        return [decode_value(item, reverse_dict) for item in obj]

    else:
        return obj


def decode(cjson: Any) -> Any:
    """Decode CJSON to standard JSON."""
    if isinstance(cjson, dict) and "_dict" in cjson:
        reverse_dict = cjson["_dict"]
        if "_data" in cjson:
            # Non-dict root value
            return decode_value(cjson["_data"], reverse_dict)
        else:
            # Dict root value, decode everything except _dict
            result = {}
            for k, v in cjson.items():
                if k == "_dict":
                    continue
                result[decode_key(k, reverse_dict)] = decode_value(v, reverse_dict)
            return result
    else:
        # No dictionary, just decode (handles escaped $)
        return decode_value(cjson, {})


def stats(original: Any, encoded: Any) -> dict:
    """Calculate compression statistics."""
    original_json = json.dumps(original, separators=(",", ":"))
    encoded_json = json.dumps(encoded, separators=(",", ":"))

    original_size = len(original_json)
    encoded_size = len(encoded_json)
    savings = original_size - encoded_size
    ratio = (savings / original_size * 100) if original_size > 0 else 0

    return {
        "original_bytes": original_size,
        "encoded_bytes": encoded_size,
        "savings_bytes": savings,
        "compression_ratio": f"{ratio:.1f}%",
    }


def main():
    parser = argparse.ArgumentParser(
        description="CJSON - Compact JSON encoder/decoder"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Encode command
    encode_parser = subparsers.add_parser("encode", help="JSON → CJSON")
    encode_parser.add_argument("file", nargs="?", help="Input file (default: stdin)")
    encode_parser.add_argument("-o", "--output", help="Output file (default: stdout)")
    encode_parser.add_argument(
        "--min-freq", type=int, default=2,
        help="Minimum occurrences to alias (default: 2)"
    )
    encode_parser.add_argument(
        "--pretty", action="store_true", help="Pretty-print output"
    )

    # Decode command
    decode_parser = subparsers.add_parser("decode", help="CJSON → JSON")
    decode_parser.add_argument("file", nargs="?", help="Input file (default: stdin)")
    decode_parser.add_argument("-o", "--output", help="Output file (default: stdout)")
    decode_parser.add_argument(
        "--pretty", action="store_true", help="Pretty-print output"
    )

    # Stats command
    stats_parser = subparsers.add_parser("stats", help="Show compression stats")
    stats_parser.add_argument("file", nargs="?", help="Input file (default: stdin)")

    args = parser.parse_args()

    # Read input
    if hasattr(args, "file") and args.file:
        with open(args.file) as f:
            data = json.load(f)
    else:
        data = json.load(sys.stdin)

    # Process
    if args.command == "encode":
        result = encode(data, args.min_freq)
        indent = 2 if args.pretty else None
        output = json.dumps(result, indent=indent, ensure_ascii=False)

    elif args.command == "decode":
        result = decode(data)
        indent = 2 if args.pretty else None
        output = json.dumps(result, indent=indent, ensure_ascii=False)

    elif args.command == "stats":
        encoded = encode(data)
        stat_info = stats(data, encoded)
        output = json.dumps(stat_info, indent=2)

    # Write output
    if hasattr(args, "output") and args.output:
        with open(args.output, "w") as f:
            f.write(output + "\n")
    else:
        print(output)


if __name__ == "__main__":
    main()
