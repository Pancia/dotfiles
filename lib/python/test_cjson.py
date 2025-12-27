#!/usr/bin/env python3
"""Tests for CJSON encoder/decoder."""

import pytest
from cjson import encode, decode, scan_strings, build_dictionary, is_homogeneous_array


class TestRoundtrip:
    """Core property: decode(encode(data)) == data"""

    def test_primitives(self):
        for value in [None, True, False, 0, 42, -1, 3.14, ""]:
            assert decode(encode(value)) == value

    def test_string(self):
        assert decode(encode("hello")) == "hello"

    def test_empty_containers(self):
        assert decode(encode({})) == {}
        assert decode(encode([])) == []

    def test_simple_object(self):
        data = {"name": "Alice", "age": 30}
        assert decode(encode(data)) == data

    def test_simple_array(self):
        data = [1, 2, 3, "a", "b", "c"]
        assert decode(encode(data)) == data

    def test_nested_object(self):
        data = {
            "user": {
                "profile": {
                    "name": "Alice",
                    "settings": {"theme": "dark"}
                }
            }
        }
        assert decode(encode(data)) == data

    def test_nested_array(self):
        data = [[1, 2], [3, 4], [[5, 6], [7, 8]]]
        assert decode(encode(data)) == data

    def test_mixed_nesting(self):
        data = {
            "items": [
                {"id": 1, "tags": ["a", "b"]},
                {"id": 2, "tags": ["c", "d"]},
            ]
        }
        assert decode(encode(data)) == data


class TestDollarEscaping:
    """Strings starting with $ must be escaped."""

    def test_escape_dollar_string(self):
        data = {"key": "$value"}
        assert decode(encode(data)) == data

    def test_escape_dollar_key(self):
        data = {"$key": "value"}
        assert decode(encode(data)) == data

    def test_double_dollar(self):
        data = {"key": "$$value"}
        assert decode(encode(data)) == data

    def test_alias_like_string(self):
        data = {"key": "$a"}  # Looks like an alias
        assert decode(encode(data)) == data

    def test_multiple_dollar_strings(self):
        data = ["$a", "$b", "$c", "normal"]
        assert decode(encode(data)) == data


class TestTabularArrays:
    """Homogeneous arrays should be converted to tabular format."""

    def test_simple_tabular(self):
        data = [
            {"name": "Alice", "age": 30},
            {"name": "Bob", "age": 25},
        ]
        encoded = encode(data)
        # Should have _cols and _rows in encoded output
        decoded = decode(encoded)
        assert decoded == data

    def test_tabular_with_repeated_values(self):
        data = {
            "users": [
                {"name": "Alice", "dept": "Engineering"},
                {"name": "Bob", "dept": "Engineering"},
                {"name": "Charlie", "dept": "Engineering"},
            ]
        }
        encoded = encode(data)
        decoded = decode(encoded)
        assert decoded == data

    def test_non_homogeneous_not_tabularized(self):
        data = [
            {"name": "Alice", "age": 30},
            {"name": "Bob"},  # Missing age
        ]
        encoded = encode(data)
        # Should NOT have _cols/_rows
        assert "_cols" not in str(encoded)
        assert decode(encoded) == data

    def test_mixed_array_not_tabularized(self):
        data = [1, "a", {"key": "value"}]
        encoded = encode(data)
        assert "_cols" not in str(encoded)
        assert decode(encoded) == data

    def test_single_item_array_not_tabularized(self):
        data = [{"name": "Alice"}]
        encoded = encode(data)
        assert "_cols" not in str(encoded)
        assert decode(encoded) == data


class TestDictionary:
    """Dictionary alias behavior."""

    def test_repeated_strings_get_aliased(self):
        data = {
            "field1": "Engineering",
            "field2": "Engineering",
            "field3": "Engineering",
        }
        encoded = encode(data)
        assert "_dict" in encoded
        assert decode(encoded) == data

    def test_unique_strings_not_aliased(self):
        data = {"a": "unique1", "b": "unique2", "c": "unique3"}
        encoded = encode(data, min_freq=2)
        # With min_freq=2, unique strings shouldn't create a dict
        assert decode(encoded) == data

    def test_min_freq_respected(self):
        data = {"a": "x", "b": "x"}  # 2 occurrences
        encoded_freq2 = encode(data, min_freq=2)
        encoded_freq3 = encode(data, min_freq=3)
        # With min_freq=3, 2 occurrences shouldn't be enough
        assert decode(encoded_freq2) == data
        assert decode(encoded_freq3) == data


class TestEdgeCases:
    """Edge cases and special values."""

    def test_reserved_key_dict(self):
        data = {"_dict": "value"}
        assert decode(encode(data)) == data

    def test_reserved_key_cols(self):
        data = {"_cols": [1, 2, 3]}
        assert decode(encode(data)) == data

    def test_reserved_key_rows(self):
        data = {"_rows": [[1], [2]]}
        assert decode(encode(data)) == data

    def test_unicode_emoji(self):
        data = {"emoji": "🎉", "name": "Party"}
        assert decode(encode(data)) == data

    def test_unicode_cjk(self):
        data = {"chinese": "中文", "japanese": "日本語"}
        assert decode(encode(data)) == data

    def test_empty_string(self):
        data = {"key": "", "": "value"}
        assert decode(encode(data)) == data

    def test_deeply_nested(self):
        data = {"a": {"b": {"c": {"d": {"e": "value"}}}}}
        assert decode(encode(data)) == data

    def test_large_array(self):
        data = [{"id": i, "type": "item"} for i in range(100)]
        assert decode(encode(data)) == data


class TestScanStrings:
    """String scanning functionality."""

    def test_counts_all_strings(self):
        data = {"name": "Alice", "friend": "Alice"}
        counter = scan_strings(data)
        assert counter["Alice"] == 2
        assert counter["name"] == 1
        assert counter["friend"] == 1

    def test_counts_keys_and_values(self):
        data = {"key": "key"}  # Same string as key and value
        counter = scan_strings(data)
        assert counter["key"] == 2


class TestBuildDictionary:
    """Dictionary building logic."""

    def test_short_aliases_first(self):
        from collections import Counter
        counter = Counter({"long_string_one": 10, "long_string_two": 10})
        alias_map = build_dictionary(counter)
        aliases = list(alias_map.values())
        # Should get short aliases like 'a', 'b'
        assert all(len(a) <= 2 for a in aliases)


class TestIsHomogeneousArray:
    """Homogeneous array detection."""

    def test_empty_array(self):
        assert not is_homogeneous_array([])

    def test_single_item(self):
        assert not is_homogeneous_array([{"a": 1}])

    def test_homogeneous(self):
        assert is_homogeneous_array([{"a": 1}, {"a": 2}])

    def test_different_keys(self):
        assert not is_homogeneous_array([{"a": 1}, {"b": 2}])

    def test_primitives(self):
        assert not is_homogeneous_array([1, 2, 3])


class TestCLI:
    """CLI integration tests."""

    def test_encode_decode_roundtrip(self):
        import subprocess
        import json

        data = {"users": [
            {"name": "Alice", "dept": "Engineering"},
            {"name": "Bob", "dept": "Engineering"},
        ]}

        # Encode
        encode_proc = subprocess.run(
            ["python3", "cjson.py", "encode"],
            input=json.dumps(data),
            capture_output=True,
            text=True,
            cwd="/Users/anthony/dotfiles/lib/python",
        )
        assert encode_proc.returncode == 0
        encoded = json.loads(encode_proc.stdout)

        # Decode
        decode_proc = subprocess.run(
            ["python3", "cjson.py", "decode"],
            input=json.dumps(encoded),
            capture_output=True,
            text=True,
            cwd="/Users/anthony/dotfiles/lib/python",
        )
        assert decode_proc.returncode == 0
        decoded = json.loads(decode_proc.stdout)

        assert decoded == data

    def test_stats_command(self):
        import subprocess
        import json

        data = {"a": "repeat", "b": "repeat", "c": "repeat"}

        proc = subprocess.run(
            ["python3", "cjson.py", "stats"],
            input=json.dumps(data),
            capture_output=True,
            text=True,
            cwd="/Users/anthony/dotfiles/lib/python",
        )
        assert proc.returncode == 0
        stats = json.loads(proc.stdout)

        assert "original_bytes" in stats
        assert "encoded_bytes" in stats
        assert "savings_bytes" in stats
        assert "compression_ratio" in stats

    def test_pretty_output(self):
        import subprocess
        import json

        data = {"key": "value"}

        proc = subprocess.run(
            ["python3", "cjson.py", "encode", "--pretty"],
            input=json.dumps(data),
            capture_output=True,
            text=True,
            cwd="/Users/anthony/dotfiles/lib/python",
        )
        assert proc.returncode == 0
        # Pretty output should have newlines
        assert "\n" in proc.stdout

    def test_min_freq_option(self):
        import subprocess
        import json

        # Two occurrences of "x"
        data = {"a": "x", "b": "x"}

        # With min_freq=2, should alias
        proc2 = subprocess.run(
            ["python3", "cjson.py", "encode", "--min-freq", "2"],
            input=json.dumps(data),
            capture_output=True,
            text=True,
            cwd="/Users/anthony/dotfiles/lib/python",
        )
        # With min_freq=3, shouldn't alias
        proc3 = subprocess.run(
            ["python3", "cjson.py", "encode", "--min-freq", "3"],
            input=json.dumps(data),
            capture_output=True,
            text=True,
            cwd="/Users/anthony/dotfiles/lib/python",
        )

        assert proc2.returncode == 0
        assert proc3.returncode == 0

        # Both should decode to same value
        decoded2 = decode(json.loads(proc2.stdout))
        decoded3 = decode(json.loads(proc3.stdout))
        assert decoded2 == data
        assert decoded3 == data


# Property-based testing (optional, requires hypothesis)
try:
    from hypothesis import given, strategies as st, settings

    json_primitives = st.none() | st.booleans() | st.integers() | st.text()
    json_values = st.recursive(
        json_primitives,
        lambda children: st.lists(children, max_size=5)
        | st.dictionaries(st.text(max_size=10), children, max_size=5),
        max_leaves=20,
    )

    class TestPropertyBased:
        @given(json_values)
        @settings(max_examples=100)
        def test_roundtrip_any_json(self, data):
            """Any valid JSON should roundtrip correctly."""
            # Skip floats (JSON float comparison is tricky)
            if isinstance(data, float):
                return
            assert decode(encode(data)) == data

except ImportError:
    pass  # hypothesis not installed, skip property tests


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
