
![NativePattern logo](docs/assets/nativepattern-logo.png)

NativePattern is a fast pattern search library for Delphi. It has one API for byte arrays, strings, streams, `TList<Byte>`, masked signatures, fuzzy search, and multi-pattern search.

The main API is `TPatternSearch` from `NativePattern`. If you search for the same pattern many times, you can compile a searcher once and reuse it.

## Features

- Exact search in `TBytes`, `string`, `TStream`, and `TList<Byte>`
- `FindFirst` and `FindAll`
- Automatic algorithm selection with `saAuto`
- AVX2 search on supported Windows x64 systems
- Boyer-Moore-Horspool
- Bitap
- SBNDM
- Rabin-Karp
- Two-Way
- Levenshtein
- Myers Bit-Vector
- Aho-Corasick
- Commentz-Walter
- Masked byte signatures with byte and nibble wildcards
- Multi-pattern search
- Stream search with chunk overlap
- Start offsets for compiled searchers
- Distance and match length for fuzzy matches
- DUnitX tests and randomized stress tests
- Benchmark tool with median results, adaptive iterations, and custom data size

## Requirements

NativePattern is a Delphi library.

The AVX2 searcher is available on Windows x64 when the CPU supports AVX2. All other algorithms can still be used without AVX2.

You can check AVX2 support at runtime:

```pascal
uses
  NativePattern.Avx2;

if TAvx2Searcher.Available then
  Writeln('AVX2 available');
```

## Add it to a project

Add the NativePattern units to your project, or add the NativePattern folder to the Delphi Search Path.

For normal use, these units are usually enough:

```pascal
uses
  NativePattern,
  NativePattern.Core;
```

If you want to use an algorithm class directly, also add its unit. For example, add `NativePattern.Avx2` for `TAvx2Searcher`.

## Quick start

### Find text in a string

```pascal
var
  Match: TPatternMatch;
begin
  Match := TPatternSearch.FindFirst('Hello world', 'world');
  if Match.Found then
    Writeln(Match.Offset);
end;
```

For string search, `Offset` and `MatchLength` use Delphi `Char` positions, not byte positions.

### Find the first byte pattern

```pascal
var
  Data, Pattern: TBytes;
  Match: TPatternMatch;
begin
  Data := TBytes.Create($10, $20, $48, $8B, $01, $90);
  Pattern := TBytes.Create($48, $8B, $01);
  Match := TPatternSearch.FindFirst(Data, Pattern);
  if Match.Found then
    Writeln(Match.Offset);
end;
```

`saAuto` is the default. For byte patterns, NativePattern chooses an algorithm from the pattern length, AVX2 support, and for long patterns also from the pattern structure.

### Find all matches

```pascal
var
  Matches: TPatternMatches;
  Match: TPatternMatch;
begin
  Matches := TPatternSearch.FindAll('AB--AB--AB', 'AB');
  for Match in Matches do
    Writeln(Match.Offset);
end;
```

### Search with a masked signature

```pascal
var
  Data: TBytes;
  Match: TPatternMatch;
begin
  Data := TBytes.Create($48, $8B, $11, $22, $89, $44);
  Match := TPatternSearch.FindFirst(Data, TBytePattern.Parse('48 8B ?? ?? 89'));
  if Match.Found then
    Writeln(Match.Offset);
end;
```

Supported tokens:

| Token | Meaning |
|---|---|
| `48` | Exact byte |
| `??` or `?` | Any byte |
| `A?` | High nibble must be `A` |
| `?F` | Low nibble must be `F` |

Spaces, tabs, line breaks, and commas can be used as separators.

### Fuzzy search

```pascal
var
  Data, Pattern: TBytes;
  Match: TPatternMatch;
begin
  Data := TBytes.Create($10, $20, $30, $41, $50);
  Pattern := TBytes.Create($20, $30, $40);
  Match := TPatternSearch.FindFirst(Data, Pattern, saAuto, 1);
  if Match.Found then
    Writeln(Match.Offset, ' distance=', Match.Distance);
end;
```

With `saAuto` and `MaxDistance > 0`, NativePattern uses Myers for short patterns and Levenshtein for longer patterns.

### Reuse a compiled searcher

If you search for the same pattern many times, compile it once:

```pascal
var
  Searcher: TSinglePatternSearcher;
  Match: TPatternMatch;
begin
  Searcher := TPatternSearch.Compile(TBytes.Create($48, $8B, $05));
  try
    Match := Searcher.FindFirst(BufferA);
    Match := Searcher.FindFirst(BufferB);
  finally
    Searcher.Free;
  end;
end;
```

This avoids rebuilding pattern tables for every search.

### Search for many patterns at once

```pascal
var
  Patterns: TArray<TBytes>;
  Searcher: TMultiPatternSearcher;
  Matches: TPatternMatches;
begin
  SetLength(Patterns, 3);
  Patterns[0] := TBytes.Create($4D, $5A);
  Patterns[1] := TBytes.Create($50, $45, $00, $00);
  Patterns[2] := TBytes.Create($DE, $AD, $BE, $EF);
  Searcher := TPatternSearch.CompileMany(Patterns);
  try
    Matches := Searcher.FindAll(Data);
  finally
    Searcher.Free;
  end;
end;
```

For a multi-pattern match, `PatternIndex` is the index of the matching pattern in the input array.

### Search a stream

```pascal
var
  Stream: TFileStream;
  Match: TPatternMatch;
begin
  Stream := TFileStream.Create('sample.bin', fmOpenRead or fmShareDenyNone);
  try
    Match := TPatternSearch.FindFirst(Stream, TBytes.Create($50, $45, $00, $00));
  finally
    Stream.Free;
  end;
end;
```

`PreservePosition` is `True` by default. After the search, the original stream position is restored.

More examples are in [`docs/USAGE.md`](docs/USAGE.md).

## Match result

`TPatternMatch` contains:

| Field | Meaning |
|---|---|
| `Offset` | Start offset of the match, or `-1` when no match was found |
| `MatchLength` | Length of the matched data |
| `PatternIndex` | Pattern index for multi-pattern search, normally `0` for single-pattern search |
| `Distance` | Edit distance for fuzzy search, `0` for exact matches |
| `MatchUnit` | `muByte` or `muChar` |

Use `Found` to check a result:

```pascal
if Match.Found then
  Writeln(Match.Offset);
```

## Algorithms

| Algorithm | Exact | Masked | Fuzzy | Multi | Notes |
|---|:---:|:---:|:---:|:---:|---|
| Boyer-Moore-Horspool | yes | no | no | no | Fast for many medium and long patterns |
| Bitap | yes | yes | no | no | Up to 64 bytes, strings up to 32 UTF-16 code units |
| SBNDM | yes | yes | no | no | Up to 64 bytes, strings up to 32 UTF-16 code units |
| Rabin-Karp | yes | no | no | no | Rolling hash search |
| Two-Way | yes | no | no | no | Linear exact search, can be selected directly |
| AVX2 | yes | no | no | no | Windows x64 with AVX2 support |
| Myers | no | no | yes | no | Up to 64 bytes or 64 UTF-16 code units |
| Levenshtein | no | no | yes | no | No 64 byte limit |
| Aho-Corasick | no | no | no | yes | Multi-pattern search |
| Commentz-Walter | no | no | no | yes | Multi-pattern search with larger skips |

### Exact `saAuto` for byte patterns

The current byte auto path is based on benchmark results:

- 1 to 32 bytes: AVX2 when available
- 33 to 64 bytes: SBNDM
- 65 to 256 bytes: Boyer-Moore-Horspool
- More than 256 bytes: Boyer-Moore-Horspool or AVX2, based on the expected BMH shift quality of the pattern
- Without AVX2: Boyer-Moore-Horspool is used for long patterns

Two-Way is still available with `saTwoWay`.

## Strings and Unicode

Delphi `string` uses UTF-16.

For string search:

- `Offset` and `MatchLength` use Delphi `Char` units.
- `MatchUnit` is `muChar`.
- One Delphi `Char` is one UTF-16 code unit.
- One visible Unicode character can use more than one UTF-16 code unit.

This matters for characters outside the BMP because they use a surrogate pair.

## Fuzzy search rules

`MaxDistance` must be from `0` to `PatternLength - 1`.

For a fuzzy match, `Distance` contains the edit distance.

For one start position, the match with the lowest distance is preferred. If two matches have the same distance, the shorter match is preferred.

Myers supports patterns up to 64 bytes or 64 UTF-16 code units. For longer fuzzy patterns, `saAuto` uses Levenshtein.

## Masked patterns

You can create `TBytePattern` directly or parse a signature:

```pascal
var
  Pattern: TBytePattern;
begin
  Pattern := TBytePattern.Parse('48 8B 4? ?? ?F 90');
end;
```

Bitap and SBNDM support masked patterns up to 64 bytes.

## Streams

Stream search works in blocks and keeps enough overlap to find matches that cross a block boundary.

With `PreservePosition=True`, the original stream position is restored. With `False`, the search may change the stream position.

## Benchmark

`PatternSearchBenchmark` measures compile time, exact search, `FindAll`, no-match cases, masked search, fuzzy search, multi-pattern search, and stream search.

It uses several measurement runs and reports the median.

Examples:

```text
PatternSearchBenchmark.exe
PatternSearchBenchmark.exe --data-mb=128
PatternSearchBenchmark.exe --full
PatternSearchBenchmark.exe --data-mb=256 --target-ms=100 --runs=7
PatternSearchBenchmark.exe --data-mb=128 --csv=results.csv
```

The default data size is 64 MiB. `--full` uses 256 MiB. `--data-mb=` overrides the data size.

Benchmark results depend on the CPU and on the data. The auto heuristic was tested with normal, random, periodic, and repeated long patterns.

### Example benchmark result

A 128 MiB run with 5 median runs and a target of 50 ms per run gave about these exact `saAuto` results on the test system:

| Pattern length | Auto algorithm | Reported speed |
|---:|---|---:|
| 16 | AVX2 | about 11,500 MB/s |
| 32 | AVX2 | about 11,800 MB/s |
| 64 | SBNDM | about 13,100 MB/s |
| 128 | Boyer-Moore-Horspool | about 12,800 MB/s |
| 300 | AVX2 | about 11,600 MB/s |
| 1024 | AVX2 | about 11,800 MB/s |

These numbers are not a promise for other CPUs or other data. They are only example values from the test system and were used to tune `saAuto`.

## Tests

The project has DUnitX tests and a randomized stress test.

The stress test compares the searchers with independent reference code and uses repeatable seeds.

The benchmark is not a correctness test. It is only used for performance checks and for tuning heuristics.

## Project layout

```text
NativePattern/
  src/
    NativePattern.pas
    NativePattern.Core.pas
    NativePattern.Avx2.pas
    NativePattern.Bitap.pas
    NativePattern.BoyerMooreHorspool.pas
    NativePattern.CommentzWalter.pas
    NativePattern.Levenshtein.pas
    NativePattern.Myers.pas
    NativePattern.RabinKarp.pas
    NativePattern.Sbndm.pas
    NativePattern.TwoWay.pas
    NativePattern.AhoCorasick.pas
  Tests/
    TestPatternSearch.dpr
    TestPatternSearchRandom.dpr
    TestPatternSearchStress.dpr
    dunitx/
      NativePattern.Tests.pas
      PatternSearchDUnitX.dpr
  benchmarks/
    PatternSearchBenchmark.dpr
  docs/
    USAGE.md
  README.md
  LICENSE
```

## License

NativePattern is released under the MIT License.

Copyright (c) 2026 Selahattin Erkoc

See [`LICENSE`](LICENSE).
