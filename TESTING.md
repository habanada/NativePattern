# Pattern Search Tests and Benchmarks

Target environment:

- RAD Studio / Delphi 23.0
- Win64
- DUnitX from RAD Studio or a separate DUnitX checkout
- CRLF Delphi source files

## Main commands

Standard Release test run:

```text
scripts\run-pattern-tests.bat
```

Debug test run with range and overflow checks:

```text
scripts\run-pattern-tests.bat Debug
```

Full Release stress run:

```text
scripts\run-pattern-stress-full.bat Release
```

Reproduce a full stress run with a fixed seed:

```text
scripts\run-pattern-stress-full.bat Release --seed=D1B54A32D192ED03
```

Full test and benchmark run:

```text
scripts\run-pattern-all.bat Release full
```

CI-style Debug plus full Release plus full benchmark:

```text
scripts\run-pattern-ci.bat
```

Every runner exits non-zero on the first failed build or test.

## Build behavior

`scripts\build-pattern-suite.bat` invokes `dcc64` directly. It deletes the selected configuration's DCU directory before each suite build and uses `-B`, so stale units cannot satisfy a test build.

Debug uses:

```text
-$O- -$D+ -$L+ -$R+ -$Q+
```

Release uses:

```text
-$O+ -$D- -$L- -$R- -$Q-
```

Outputs are separated by configuration:

```text
bin\Win64\Debug
bin\Win64\Release
dcu\Win64\Debug
dcu\Win64\Release
```

If `dcc64.exe` is not on `PATH`, run from a RAD Studio command prompt or let the script load the default Delphi 23.0 `rsvars.bat`.

## DUnitX contract suite

Project:

```text
tests\dunitx\PatternSearchDUnitX.dpr
```

The suite contains 100 fixed contract tests. They assert concrete offsets, match lengths, edit distances, pattern indexes, units, exception behavior and dispatcher types.

Coverage includes:

- `TPatternMatch.NotFound`
- signature parsing and malformed input
- public dynamic-array immutability
- input-array copy semantics
- exact expected offsets and overlapping matches
- `StartOffset`
- 1, 64 and 65 byte bit-algorithm boundaries
- long periodic Two-Way patterns
- UTF-16 code-unit offsets, surrogate pairs and embedded `#0`
- byte, nibble, full and arbitrary bit masks
- Levenshtein substitution, insertion and deletion
- Myers substitution, insertion and deletion
- one-best-match-per-start fuzzy semantics
- zero-distance fuzzy/exact equivalence
- Aho-Corasick and Commentz-Walter expected pattern indexes
- duplicate, prefix and suffix multi-patterns
- copied multi-pattern input ownership for both engines
- exact, masked, fuzzy and multi-pattern chunk-boundary searches
- fuzzy candidate improvement across a 64 KiB boundary
- sorted fuzzy `FindAll` results when an earlier start becomes valid only after the next stream chunk
- stream current-position and `PreservePosition` contracts
- no duplicate boundary matches
- nil and empty streams
- automatic exact thresholds at 64, 65, 256 and 257 bytes
- automatic fuzzy and multi-pattern selection
- explicit algorithm selection
- invalid `MaxDistance` combinations
- AVX2/scalar equivalence when AVX2 is available

NUnit-compatible XML is written on every DUnitX run to:

```text
test-results\PatternSearchDUnitX-<Config>.xml
```

Override the path with `NATIVEPE_DUNITX_XML`.

If DUnitX is not on the Delphi library path:

```text
set DUNITX_PATH=C:\path\to\DUnitX\Source
```

## Deterministic and random console suites

The build also creates:

```text
TestPatternSearch.exe
TestPatternSearchRandom.exe
TestPatternSearchStress.exe
```

`TestPatternSearch.exe` holds compact deterministic regressions.

`TestPatternSearchRandom.exe` performs reproducible differential tests against simple reference search implementations.

`TestPatternSearchStress.exe` is the large differential suite. It uses a deterministic xorshift sequence and reports the initial seed and current state on failure.

Reproduce a sequence with:

```text
TestPatternSearchStress.exe --full --seed=D1B54A32D192ED03
```

## Stress dimensions

Standard run:

```text
Exact byte:          10000
Masked byte:          6000
Fuzzy byte:           1500
Multi-pattern:        3000
Exact string:         3000
Fuzzy string:          500
Exact stream:          500
Masked stream:         250
Multi-pattern stream:  200
```

Full run:

```text
Exact byte:          50000
Masked byte:         30000
Fuzzy byte:           8000
Multi-pattern:       15000
Exact string:        15000
Fuzzy string:         2500
Exact stream:         2500
Masked stream:        1200
Multi-pattern stream: 1000
```

A fixed fuzzy-stream regression runs in addition to those counts.

Exact byte stress deliberately includes pattern lengths:

```text
1 2 3 7 8 15 16 31 32 63 64 65 127 255 256 257
```

Random exact cases also extend to 320 bytes and use both low-entropy and full-byte alphabets.

Masked cases use masks including:

```text
FF F0 0F 00 3C C3
```

String stress includes ASCII, `#0` and non-ASCII UTF-16 code units.

## Differential references

Exact implementations are checked against naive byte/string scanning:

```text
Boyer-Moore-Horspool
Bitap
SBNDM
Rabin-Karp
Two-Way
AVX2 when available
Auto dispatcher
```

Masked implementations are checked against per-byte mask comparison:

```text
Bitap
SBNDM
```

Fuzzy implementations are checked against independent full dynamic-programming edit distance over every admissible substring:

```text
Levenshtein
Myers Bit-Vector
```

Multi-pattern implementations are checked against naive search of every pattern:

```text
Aho-Corasick
Commentz-Walter
```

The optimized algorithm is never used as its own differential oracle.

## Benchmark

Quick benchmark:

```text
scripts\run-pattern-benchmark.bat Release
```

Full benchmark:

```text
scripts\run-pattern-benchmark.bat Release full
```

CSV output is separated by configuration and mode:

```text
test-results\pattern-benchmark-Release-quick.csv
test-results\pattern-benchmark-Release-full.csv
```

Columns:

```text
category;algorithm;data_bytes;pattern_length;pattern_count;iterations;elapsed_ms;ns_per_op;mb_per_s;checksum
```

Scan scenarios include:

- exact patterns at 4, 8, 16, 32, 64, 128, 300 and 1024 bytes
- guaranteed no-match cases
- sparse `FindAll` throughput
- masked patterns at 16, 32 and 64 bytes
- fuzzy patterns at 8, 16, 32 and 64 positions
- multi-pattern `FindFirst` sets with 4, 16, 64 and 256 patterns
- multi-pattern `FindAll` throughput with 16 and 64 patterns
- stream scanning at 16, 64 and 300 bytes
- automatic dispatcher paths
- AVX2 when available

Preprocessing is measured separately in the `Compile` category for exact searchers and `CompileMulti` for Aho-Corasick, Commentz-Walter and the automatic multi-pattern dispatcher. Scan throughput constructs the searcher before timing, matching the compile-once/search-many design.

Before timed loops, the benchmark validates results. Exact and masked searches use naive reference results. Fuzzy engines are cross-checked against the Levenshtein contract already covered independently by the stress suite. Multi-pattern engines are required to agree before measurement. Stream benchmarks validate the exact expected offset.

Every timed loop contributes to a checksum so result paths cannot be optimized away accidentally and CSV runs can be compared for consistency.
