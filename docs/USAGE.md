# NativePattern Usage Guide

This guide starts with simple searches and then shows compiled searchers, masked signatures, fuzzy search, multi-pattern search, streams, pointers, and direct algorithm selection.

## 1. Use the main API

For most code, start with `TPatternSearch`:

```pascal
uses
  NativePattern,
  NativePattern.Core;
```

The static `FindFirst` and `FindAll` methods create a searcher, run the search, and free the searcher for you.

## 2. Exact byte search

```pascal
var
  Data, Pattern: TBytes;
  Match: TPatternMatch;
begin
  Data := TBytes.Create($90, $48, $8B, $05, $11, $22, $33, $44, $90);
  Pattern := TBytes.Create($48, $8B, $05);
  Match := TPatternSearch.FindFirst(Data, Pattern);
  if Match.Found then
    Writeln('Offset: ', Match.Offset);
end;
```

If you do not pass an algorithm, `saAuto` is used.

## 3. Find all matches

```pascal
var
  Data, Pattern: TBytes;
  Matches: TPatternMatches;
  Match: TPatternMatch;
begin
  Data := TBytes.Create($AA, $BB, $AA, $BB, $AA);
  Pattern := TBytes.Create($AA);
  Matches := TPatternSearch.FindAll(Data, Pattern);
  for Match in Matches do
    Writeln(Match.Offset);
end;
```

Overlapping matches are supported. After a match, the search continues from the next start position.

## 4. String search

```pascal
var
  Match: TPatternMatch;
begin
  Match := TPatternSearch.FindFirst('NativePattern for Delphi', 'Pattern');
  if Match.Found then
    Writeln(Match.Offset, ' ', Match.MatchLength);
end;
```

For string search, `MatchUnit = muChar`.

Offsets and lengths use Delphi `Char` units. One `Char` is one UTF-16 code unit.

## 5. Masked signatures

The easiest way to create a masked pattern is `TBytePattern.Parse`:

```pascal
var
  Data: TBytes;
  Pattern: TBytePattern;
  Match: TPatternMatch;
begin
  Data := TBytes.Create($48, $8B, $45, $11, $22, $8F, $90);
  Pattern := TBytePattern.Parse('48 8B 4? ?? ?? ?F 90');
  Match := TPatternSearch.FindFirst(Data, Pattern, msaSbndm);
  if Match.Found then
    Writeln(Match.Offset);
end;
```

### Signature syntax

```text
48       exact byte 48
??       any byte
?        any byte
A?       high nibble A, low nibble can be anything
?F       high nibble can be anything, low nibble F
```

Valid separators are spaces, tabs, CR/LF, and commas.

There is also a short helper for Bitap:

```pascal
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := TPatternSearch.CompileSignature('48 8B ?? ?? 89');
  try
    Writeln(Searcher.FindFirst(Data).Offset);
  finally
    Searcher.Free;
  end;
end;
```

Bitap and SBNDM support masked patterns up to 64 bytes.

## 6. Compile once and reuse

If you search for the same pattern many times, use `Compile`:

```pascal
var
  Searcher: TSinglePatternSearcher;
  MatchA, MatchB: TPatternMatch;
begin
  Searcher := TPatternSearch.Compile(TBytes.Create($50, $45, $00, $00));
  try
    MatchA := Searcher.FindFirst(ImageA);
    MatchB := Searcher.FindFirst(ImageB);
  finally
    Searcher.Free;
  end;
end;
```

The pattern tables are built only once.

## 7. Start at an offset

Compiled searchers support `StartOffset`:

```pascal
var
  Searcher: TSinglePatternSearcher;
  Match: TPatternMatch;
begin
  Searcher := TPatternSearch.Compile(TBytes.Create($90, $90));
  try
    Match := Searcher.FindFirst(Data, 4096);
  finally
    Searcher.Free;
  end;
end;
```

The same is available for `FindAll`.

## 8. Fuzzy search

Use `MaxDistance > 0` to enable fuzzy search with `saAuto`:

```pascal
var
  Data, Pattern: TBytes;
  Match: TPatternMatch;
begin
  Data := TBytes.Create($10, $20, $31, $40, $50);
  Pattern := TBytes.Create($20, $30, $40);
  Match := TPatternSearch.FindFirst(Data, Pattern, saAuto, 1);
  if Match.Found then
    Writeln('Offset=', Match.Offset, ' Length=', Match.MatchLength, ' Distance=', Match.Distance);
end;
```

For byte patterns up to 64 bytes, `saAuto` uses Myers. For longer patterns, it uses Levenshtein.

`MaxDistance` must be smaller than the pattern length.

### Select the fuzzy algorithm directly

```pascal
var
  Searcher: TSinglePatternSearcher;
begin
  Searcher := TPatternSearch.Compile(Pattern, saMyers, 2);
  try
    Matches := Searcher.FindAll(Data);
  finally
    Searcher.Free;
  end;
end;
```

Myers supports up to 64 bytes or 64 UTF-16 code units.

## 9. Multi-pattern search

```pascal
var
  Patterns: TArray<TBytes>;
  Searcher: TMultiPatternSearcher;
  Matches: TPatternMatches;
  Match: TPatternMatch;
begin
  SetLength(Patterns, 3);
  Patterns[0] := TBytes.Create($4D, $5A);
  Patterns[1] := TBytes.Create($50, $45, $00, $00);
  Patterns[2] := TBytes.Create($DE, $AD, $BE, $EF);
  Searcher := TPatternSearch.CompileMany(Patterns, maAuto);
  try
    Matches := Searcher.FindAll(Data);
    for Match in Matches do
      Writeln('Pattern=', Match.PatternIndex, ' Offset=', Match.Offset);
  finally
    Searcher.Free;
  end;
end;
```

`PatternIndex` tells you which input pattern matched.

`maAuto` selects between Aho-Corasick and Commentz-Walter.

With at least four patterns and a minimum pattern length of four, `maAuto` prefers Commentz-Walter. Otherwise it uses Aho-Corasick.

You can also select an algorithm directly:

```pascal
Searcher := TPatternSearch.CompileMany(Patterns, maAhoCorasick);
```

or:

```pascal
Searcher := TPatternSearch.CompileMany(Patterns, maCommentzWalter);
```

## 10. Stream search

```pascal
var
  Stream: TFileStream;
  Searcher: TSinglePatternSearcher;
  Match: TPatternMatch;
begin
  Stream := TFileStream.Create('image.bin', fmOpenRead or fmShareDenyNone);
  Searcher := TPatternSearch.Compile(TBytes.Create($50, $45, $00, $00));
  try
    Match := Searcher.FindFirst(Stream, True);
  finally
    Searcher.Free;
    Stream.Free;
  end;
end;
```

Stream search reads data in chunks and keeps enough overlap to find matches that cross chunk boundaries.

`PreservePosition=True` restores the original stream position. With `False`, the search may change the stream position.

## 11. Search a `TList<Byte>`

```pascal
var
  Bytes: TList<Byte>;
  Match: TPatternMatch;
begin
  Bytes := TList<Byte>.Create;
  try
    Bytes.Add($48);
    Bytes.Add($8B);
    Bytes.Add($01);
    Match := TPatternSearch.FindFirst(Bytes, TBytes.Create($48, $8B));
  finally
    Bytes.Free;
  end;
end;
```

The list is converted to a byte array for the search.

## 12. Search a pointer buffer

Compiled searchers also have pointer overloads:

```pascal
var
  Searcher: TSinglePatternSearcher;
  Match: TPatternMatch;
begin
  Searcher := TPatternSearch.Compile(Pattern);
  try
    Match := Searcher.FindFirst(Buffer, BufferSize);
  finally
    Searcher.Free;
  end;
end;
```

`Buffer` must stay valid for `BufferSize` bytes while the call is running.

## 13. Select an exact algorithm directly

`saAuto` is the normal choice. For special cases, you can select an algorithm directly:

```pascal
Searcher := TPatternSearch.Compile(Pattern, saBoyerMooreHorspool);
Searcher := TPatternSearch.Compile(Pattern, saBitap);
Searcher := TPatternSearch.Compile(Pattern, saSbndm);
Searcher := TPatternSearch.Compile(Pattern, saRabinKarp);
Searcher := TPatternSearch.Compile(Pattern, saTwoWay);
Searcher := TPatternSearch.Compile(Pattern, saAvx2);
```

`saAvx2` raises `ENotSupportedException` when AVX2 is not available on the current platform or CPU.

For normal use, prefer `saAuto`.

## 14. Current exact byte auto rules

```text
1..32       AVX2 when available
33..64      SBNDM
65..256     Boyer-Moore-Horspool
>256        Boyer-Moore-Horspool or AVX2, based on the pattern structure
```

If AVX2 is not available, the long byte path falls back to Boyer-Moore-Horspool.

For patterns longer than 256 bytes, the choice uses the expected BMH shift quality. Repeated or strongly periodic patterns can use BMH. Other long patterns can use AVX2.

## 15. Read match fields

```pascal
if Match.Found then
begin
  Writeln('Offset: ', Match.Offset);
  Writeln('Length: ', Match.MatchLength);
  Writeln('Pattern: ', Match.PatternIndex);
  Writeln('Distance: ', Match.Distance);
end;
```

For `TPatternMatch.NotFound`, `Offset = -1`.

Use `Found` as the normal check.

## 16. Performance tips

For one search, the main API is simple:

```pascal
Match := TPatternSearch.FindFirst(Data, Pattern);
```

For many searches with the same pattern, reuse a compiled searcher:

```pascal
Searcher := TPatternSearch.Compile(Pattern);
try
  for I := 0 to High(Buffers) do
    ProcessMatch(Searcher.FindFirst(Buffers[I]));
finally
  Searcher.Free;
end;
```

If many patterns must be searched in the same data, use `CompileMany` instead of running many single-pattern searchers one after another.

For large files that should not be loaded fully into memory, use the stream overload.

## 17. Run the benchmark

```text
PatternSearchBenchmark.exe
PatternSearchBenchmark.exe --data-mb=128
PatternSearchBenchmark.exe --full
PatternSearchBenchmark.exe --data-mb=256 --target-ms=100 --runs=7
PatternSearchBenchmark.exe --data-mb=128 --csv=results.csv
```

Options:

| Option | Meaning |
|---|---|
| `--full` | Use 256 MiB and a longer target time |
| `--data-mb=N` | Data size in MiB |
| `--target-ms=N` | Target time for one measurement run |
| `--runs=N` | Number of runs used for the median |
| `--csv=FILE` | Also save results as UTF-8 CSV |

The benchmark uses adaptive iterations. For very slow cases, one iteration can already take longer than the target time.

## 18. Common errors

### Empty pattern

Empty patterns are invalid and raise `EArgumentException`.

### Bitap or SBNDM with more than 64 bytes

Both algorithms use a 64-bit mask and support at most 64 bytes. For strings, the limit is 32 UTF-16 code units.

### Myers with more than 64 units

Myers supports at most 64 bytes or 64 UTF-16 code units. For longer fuzzy patterns, use `saAuto` or `saLevenshtein`.

### Force AVX2

Before selecting `saAvx2` directly, you can check `TAvx2Searcher.Available`.

`saAuto` checks AVX2 support for you.

### Unicode offsets

String offsets use UTF-16 code units. One visible Unicode character can use more than one code unit.

## 19. Recommended default use

For most programs, these four rules are enough:

1. Use `TPatternSearch.FindFirst` or `FindAll` with `saAuto`.
2. If you search many times with the same pattern, call `Compile` once and reuse the searcher.
3. Use `TBytePattern.Parse` for masked signatures.
4. Use `CompileMany` when you need to search many patterns at once.

This keeps your code small while NativePattern chooses the search strategy.
