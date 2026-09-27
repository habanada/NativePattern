program PatternSearchBenchmark;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  NativePattern,
  NativePattern.Core,
  NativePattern.BoyerMooreHorspool,
  NativePattern.Bitap,
  NativePattern.Sbndm,
  NativePattern.RabinKarp,
  NativePattern.TwoWay,
  NativePattern.Levenshtein,
  NativePattern.Myers,
  NativePattern.AhoCorasick,
  NativePattern.CommentzWalter,
  NativePattern.Avx2;

var
  GRandState: UInt64 = $94D049BB133111EB;
  GChecksum: UInt64;
  GCsv: TStringList;
  GFormat: TFormatSettings;
  GMeasureRuns: Integer;
  GTargetMilliseconds: Integer;
  GCompileTargetMilliseconds: Integer;

function NextRand: UInt64;
begin
  GRandState := GRandState xor (GRandState shl 13);
  GRandState := GRandState xor (GRandState shr 7);
  GRandState := GRandState xor (GRandState shl 17);
  Result := GRandState;
end;

procedure FillRandom(var Data: TBytes);
var
  I: Integer;
begin
  for I := 0 to High(Data) do
    Data[I] := Byte(NextRand);
end;

function CreatePattern(LengthValue: Integer): TBytes;
var
  I: Integer;
begin
  SetLength(Result, LengthValue);
  for I := 0 to High(Result) do
    Result[I] := Byte((I * 131 + LengthValue * 17 + 29) and $FF);
end;

function CreateRandomPattern(LengthValue: Integer; Salt: UInt64): TBytes;
var
  I: Integer;
  State: UInt64;
begin
  SetLength(Result, LengthValue);
  State := $D1B54A32D192ED03 xor Salt xor UInt64(LengthValue);
  for I := 0 to High(Result) do
  begin
    State := State xor (State shl 13);
    State := State xor (State shr 7);
    State := State xor (State shl 17);
    Result[I] := Byte(State);
  end;
end;

function CreatePeriodicPattern(LengthValue, PeriodLength: Integer; Salt: UInt64): TBytes;
var
  I: Integer;
  Base: TBytes;
begin
  if PeriodLength < 1 then
    PeriodLength := 1;
  Base := CreateRandomPattern(PeriodLength, Salt);
  SetLength(Result, LengthValue);
  for I := 0 to High(Result) do
    Result[I] := Base[I mod PeriodLength];
end;

function CreateRepeatedPattern(LengthValue: Integer; Value: Byte): TBytes;
begin
  SetLength(Result, LengthValue);
  if LengthValue > 0 then
    FillChar(Result[0], LengthValue, Value);
end;

procedure InsertPattern(var Data: TBytes; const Pattern: TBytes; Offset: Integer);
begin
  if Length(Pattern) > 0 then
    Move(Pattern[0], Data[Offset], Length(Pattern));
end;

function AlgorithmName(Searcher: TObject): string;
begin
  Result := Searcher.ClassName;
  if Result.StartsWith('T') then
    Delete(Result, 1, 1);
  if Result.EndsWith('Searcher') then
    Delete(Result, Length(Result) - Length('Searcher') + 1, Length('Searcher'));
end;

procedure Emit(const Category, Algorithm: string; DataBytes, PatternLength, PatternCount, Iterations: Integer; ElapsedMs, MBps: Double; Checksum: UInt64);
var
  Line: string;
  NsPerOp: Double;
begin
  if Iterations > 0 then NsPerOp := ElapsedMs * 1000000.0 / Iterations else NsPerOp := 0;
  Writeln(Format('%-12s %-26s data=%9d pattern=%5d count=%4d iter=%7d ms=%10.3f ns/op=%12.1f MB/s=%10.2f checksum=%s', [Category, Algorithm, DataBytes, PatternLength, PatternCount, Iterations, ElapsedMs, NsPerOp, MBps, IntToHex(Checksum, 16)]));
  Line := Category + ';' + Algorithm + ';' + IntToStr(DataBytes) + ';' + IntToStr(PatternLength) + ';' + IntToStr(PatternCount) + ';' + IntToStr(Iterations) + ';' + FloatToStr(ElapsedMs, GFormat) + ';' + FloatToStr(NsPerOp, GFormat) + ';' + FloatToStr(MBps, GFormat) + ';' + IntToHex(Checksum, 16);
  GCsv.Add(Line);
end;

function CalibratedIterations(BaseIterations: Integer; ElapsedMs: Double; TargetMilliseconds: Integer): Integer;
var
  Desired: Double;
begin
  if BaseIterations < 1 then
    BaseIterations := 1;
  if ElapsedMs <= 0 then
    Exit(BaseIterations);
  Desired := BaseIterations * TargetMilliseconds / ElapsedMs;
  if Desired < 1 then
    Exit(1);
  if Desired > 1000000 then
    Exit(1000000);
  Result := Round(Desired);
  if Result < 1 then
    Result := 1;
end;

function MedianMilliseconds(const Values: TArray<Double>): Double;
var
  Sorted: TArray<Double>;
  I, J: Integer;
  V: Double;
begin
  if Length(Values) = 0 then
    Exit(0);
  Sorted := Copy(Values, 0, Length(Values));
  for I := 1 to High(Sorted) do
  begin
    V := Sorted[I];
    J := I - 1;
    while (J >= 0) and (Sorted[J] > V) do
    begin
      Sorted[J + 1] := Sorted[J];
      Dec(J);
    end;
    Sorted[J + 1] := V;
  end;
  if Odd(Length(Sorted)) then
    Result := Sorted[Length(Sorted) div 2]
  else
    Result := (Sorted[Length(Sorted) div 2 - 1] + Sorted[Length(Sorted) div 2]) * 0.5;
end;

function NaiveFindFirst(const Data, Pattern: TBytes): Int64;
var
  I, J: Integer;
  Equal: Boolean;
begin
  Result := -1;
  if (Length(Pattern) = 0) or (Length(Pattern) > Length(Data)) then Exit;
  for I := 0 to Length(Data) - Length(Pattern) do
  begin
    Equal := True;
    for J := 0 to High(Pattern) do
      if Data[I + J] <> Pattern[J] then
      begin
        Equal := False;
        Break;
      end;
    if Equal then Exit(I);
  end;
end;

function NaiveMaskedFindFirst(const Data: TBytes; const Pattern: TBytePattern): Int64;
var
  Bytes, Masks: TBytes;
  I, J: Integer;
  Equal: Boolean;
begin
  Result := -1;
  Bytes := Pattern.Bytes;
  Masks := Pattern.Masks;
  if (Length(Bytes) = 0) or (Length(Bytes) > Length(Data)) then
    Exit;
  for I := 0 to Length(Data) - Length(Bytes) do
  begin
    Equal := True;
    for J := 0 to High(Bytes) do
      if (Data[I + J] and Masks[J]) <> (Bytes[J] and Masks[J]) then
      begin
        Equal := False;
        Break;
      end;
    if Equal then
      Exit(I);
  end;
end;

function NaiveCount(const Data, Pattern: TBytes): Integer;
var
  I, J: Integer;
  Equal: Boolean;
begin
  Result := 0;
  if (Length(Pattern) = 0) or (Length(Pattern) > Length(Data)) then Exit;
  for I := 0 to Length(Data) - Length(Pattern) do
  begin
    Equal := True;
    for J := 0 to High(Pattern) do
      if Data[I + J] <> Pattern[J] then
      begin
        Equal := False;
        Break;
      end;
    if Equal then Inc(Result);
  end;
end;

procedure RequireOffset(Searcher: TSinglePatternSearcher; const Data: TBytes; ExpectedOffset: Int64; const Name: string);
var
  M: TPatternMatch;
begin
  M := Searcher.FindFirst(Data);
  if ExpectedOffset < 0 then
  begin
    if M.Found then raise Exception.CreateFmt('%s benchmark validation expected no match, got %d', [Name, M.Offset]);
  end
  else if (not M.Found) or (M.Offset <> ExpectedOffset) then
    raise Exception.CreateFmt('%s benchmark validation expected %d, got %d', [Name, ExpectedOffset, M.Offset]);
end;

procedure RequireSameMatch(Searcher: TSinglePatternSearcher; const Data: TBytes; const Expected: TPatternMatch; const Name: string);
var
  M: TPatternMatch;
begin
  M := Searcher.FindFirst(Data);
  if M.Found <> Expected.Found then
    raise Exception.Create(Name + ' benchmark validation changed match presence');
  if not M.Found then
    Exit;
  if (M.Offset <> Expected.Offset) or (M.MatchLength <> Expected.MatchLength) or (M.Distance <> Expected.Distance) then
    raise Exception.CreateFmt('%s benchmark validation expected offset=%d length=%d distance=%d, got offset=%d length=%d distance=%d', [Name, Expected.Offset, Expected.MatchLength, Expected.Distance, M.Offset, M.MatchLength, M.Distance]);
end;

procedure RequireMultiMatch(Searcher: TMultiPatternSearcher; const Data: TBytes; ExpectedOffset: Int64; ExpectedPatternIndex: Integer; const Name: string);
var
  M: TPatternMatch;
begin
  M := Searcher.FindFirst(Data);
  if (not M.Found) or (M.Offset <> ExpectedOffset) or (M.PatternIndex <> ExpectedPatternIndex) then
    raise Exception.CreateFmt('%s benchmark validation expected offset=%d pattern=%d, got offset=%d pattern=%d', [Name, ExpectedOffset, ExpectedPatternIndex, M.Offset, M.PatternIndex]);
end;

procedure BenchSingle(const Category: string; Searcher: TSinglePatternSearcher; const Data: TBytes; PatternLength, BaseIterations: Integer);
var
  I, Run, Iterations: Integer;
  M: TPatternMatch;
  SW: TStopwatch;
  Samples: TArray<Double>;
  MBps, Ms: Double;
  LocalChecksum, RunChecksum: UInt64;
begin
  Searcher.FindFirst(Data);
  SW := TStopwatch.StartNew;
  for I := 1 to BaseIterations do
    Searcher.FindFirst(Data);
  SW.Stop;
  Iterations := CalibratedIterations(BaseIterations, SW.Elapsed.TotalMilliseconds, GTargetMilliseconds);
  SetLength(Samples, GMeasureRuns);
  LocalChecksum := 0;
  for Run := 0 to High(Samples) do
  begin
    RunChecksum := 0;
    SW := TStopwatch.StartNew;
    for I := 1 to Iterations do
    begin
      M := Searcher.FindFirst(Data);
      RunChecksum := RunChecksum xor UInt64(M.Offset + 1) xor UInt64(M.MatchLength shl (I and 15));
    end;
    SW.Stop;
    Samples[Run] := SW.Elapsed.TotalMilliseconds;
    LocalChecksum := LocalChecksum xor RunChecksum xor UInt64(Run + 1);
  end;
  Ms := MedianMilliseconds(Samples);
  if Ms > 0 then
    MBps := (Length(Data) * Int64(Iterations) / 1048576.0) / (Ms / 1000.0)
  else
    MBps := 0;
  GChecksum := GChecksum xor LocalChecksum;
  Emit(Category, AlgorithmName(Searcher), Length(Data), PatternLength, 1, Iterations, Ms, MBps, LocalChecksum);
end;

procedure BenchAllSingle(const Category: string; Searcher: TSinglePatternSearcher; const Data: TBytes; PatternLength, BaseIterations, ExpectedCount: Integer);
var
  I, Run, Iterations: Integer;
  A: TPatternMatches;
  SW: TStopwatch;
  Samples: TArray<Double>;
  MBps, Ms: Double;
  LocalChecksum, RunChecksum: UInt64;
begin
  A := Searcher.FindAll(Data);
  if Length(A) <> ExpectedCount then
    raise Exception.CreateFmt('%s FindAll benchmark validation expected %d matches, got %d', [AlgorithmName(Searcher), ExpectedCount, Length(A)]);
  SW := TStopwatch.StartNew;
  for I := 1 to BaseIterations do
    Searcher.FindAll(Data);
  SW.Stop;
  Iterations := CalibratedIterations(BaseIterations, SW.Elapsed.TotalMilliseconds, GTargetMilliseconds);
  SetLength(Samples, GMeasureRuns);
  LocalChecksum := 0;
  for Run := 0 to High(Samples) do
  begin
    RunChecksum := 0;
    SW := TStopwatch.StartNew;
    for I := 1 to Iterations do
    begin
      A := Searcher.FindAll(Data);
      RunChecksum := RunChecksum xor UInt64(Length(A));
      if Length(A) > 0 then
        RunChecksum := RunChecksum xor UInt64(A[High(A)].Offset + 1);
    end;
    SW.Stop;
    Samples[Run] := SW.Elapsed.TotalMilliseconds;
    LocalChecksum := LocalChecksum xor RunChecksum xor UInt64(Run + 1);
  end;
  Ms := MedianMilliseconds(Samples);
  if Ms > 0 then
    MBps := (Length(Data) * Int64(Iterations) / 1048576.0) / (Ms / 1000.0)
  else
    MBps := 0;
  GChecksum := GChecksum xor LocalChecksum;
  Emit(Category, AlgorithmName(Searcher), Length(Data), PatternLength, 1, Iterations, Ms, MBps, LocalChecksum);
end;

procedure BenchFindAllSparse(const Data: TBytes; PatternLength, Iterations: Integer);
var
  Pattern, Work: TBytes;
  Offset, ExpectedCount: Integer;
  S: TSinglePatternSearcher;
begin
  Pattern := CreatePattern(PatternLength);
  Work := Copy(Data);
  Offset := 1024;
  while Offset + PatternLength <= Length(Work) do
  begin
    InsertPattern(Work, Pattern, Offset);
    Inc(Offset, 4096);
  end;
  ExpectedCount := NaiveCount(Work, Pattern);
  S := TBoyerMooreHorspoolSearcher.Create(Pattern);
  try BenchAllSingle('FindAll', S, Work, PatternLength, Iterations, ExpectedCount); finally S.Free; end;
  S := TRabinKarpSearcher.Create(Pattern);
  try BenchAllSingle('FindAll', S, Work, PatternLength, Iterations, ExpectedCount); finally S.Free; end;
  S := TTwoWaySearcher.Create(Pattern);
  try BenchAllSingle('FindAll', S, Work, PatternLength, Iterations, ExpectedCount); finally S.Free; end;
  if PatternLength <= 64 then
  begin
    S := TBitapSearcher.Create(Pattern);
    try BenchAllSingle('FindAll', S, Work, PatternLength, Iterations, ExpectedCount); finally S.Free; end;
    S := TSbndmSearcher.Create(Pattern);
    try BenchAllSingle('FindAll', S, Work, PatternLength, Iterations, ExpectedCount); finally S.Free; end;
  end;
  if TAvx2Searcher.Available then
  begin
    S := TAvx2Searcher.Create(Pattern);
    try BenchAllSingle('FindAll', S, Work, PatternLength, Iterations, ExpectedCount); finally S.Free; end;
  end;
  S := TPatternSearch.Compile(Pattern);
  try BenchAllSingle('FindAll-Auto', S, Work, PatternLength, Iterations, ExpectedCount); finally S.Free; end;
end;

procedure BenchExactPattern(const Data, Pattern: TBytes; const Category, AutoCategory: string; BaseIterations: Integer);
var
  Work: TBytes;
  S: TSinglePatternSearcher;
  ExpectedOffset: Int64;
  PatternLength: Integer;
begin
  PatternLength := Length(Pattern);
  Work := Copy(Data);
  InsertPattern(Work, Pattern, Length(Work) - PatternLength - 7);
  ExpectedOffset := NaiveFindFirst(Work, Pattern);
  S := TBoyerMooreHorspoolSearcher.Create(Pattern);
  try RequireOffset(S, Work, ExpectedOffset, 'BMH'); BenchSingle(Category, S, Work, PatternLength, BaseIterations); finally S.Free; end;
  S := TRabinKarpSearcher.Create(Pattern);
  try RequireOffset(S, Work, ExpectedOffset, 'Rabin-Karp'); BenchSingle(Category, S, Work, PatternLength, BaseIterations); finally S.Free; end;
  S := TTwoWaySearcher.Create(Pattern);
  try RequireOffset(S, Work, ExpectedOffset, 'Two-Way'); BenchSingle(Category, S, Work, PatternLength, BaseIterations); finally S.Free; end;
  if PatternLength <= 64 then
  begin
    S := TBitapSearcher.Create(Pattern);
    try RequireOffset(S, Work, ExpectedOffset, 'Bitap'); BenchSingle(Category, S, Work, PatternLength, BaseIterations); finally S.Free; end;
    S := TSbndmSearcher.Create(Pattern);
    try RequireOffset(S, Work, ExpectedOffset, 'SBNDM'); BenchSingle(Category, S, Work, PatternLength, BaseIterations); finally S.Free; end;
  end;
  if TAvx2Searcher.Available then
  begin
    S := TAvx2Searcher.Create(Pattern);
    try RequireOffset(S, Work, ExpectedOffset, 'AVX2'); BenchSingle(Category, S, Work, PatternLength, BaseIterations); finally S.Free; end;
  end;
  S := TPatternSearch.Compile(Pattern);
  try RequireOffset(S, Work, ExpectedOffset, 'Auto'); BenchSingle(AutoCategory, S, Work, PatternLength, BaseIterations); finally S.Free; end;
end;

procedure BenchExact(const Data: TBytes; PatternLength, BaseIterations: Integer);
begin
  BenchExactPattern(Data, CreatePattern(PatternLength), 'Exact', 'Auto', BaseIterations);
end;

procedure BenchExactVariants(const Data: TBytes; PatternLength, BaseIterations: Integer);
begin
  BenchExactPattern(Data, CreateRandomPattern(PatternLength, $A0761D6478BD642F), 'ExactRandom', 'AutoRandom', BaseIterations);
  BenchExactPattern(Data, CreatePeriodicPattern(PatternLength, 8, $E7037ED1A0B428DB), 'ExactPeriod', 'AutoPeriod', BaseIterations);
  BenchExactPattern(Data, CreateRepeatedPattern(PatternLength, $A7), 'ExactRepeat', 'AutoRepeat', BaseIterations);
end;

procedure BenchNoMatch(const Data: TBytes; PatternLength, Iterations: Integer);
var
  Pattern, Work: TBytes;
  S: TSinglePatternSearcher;
begin
  SetLength(Work, Length(Data));
  if Length(Work) > 0 then
    FillChar(Work[0], Length(Work), $AA);
  SetLength(Pattern, PatternLength);
  if PatternLength > 0 then
  begin
    FillChar(Pattern[0], PatternLength, $AA);
    Pattern[PatternLength - 1] := $AB;
  end;
  S := TBoyerMooreHorspoolSearcher.Create(Pattern);
  try RequireOffset(S, Work, -1, 'BMH NoMatch'); BenchSingle('NoMatch', S, Work, PatternLength, Iterations); finally S.Free; end;
  S := TRabinKarpSearcher.Create(Pattern);
  try RequireOffset(S, Work, -1, 'Rabin-Karp NoMatch'); BenchSingle('NoMatch', S, Work, PatternLength, Iterations); finally S.Free; end;
  S := TTwoWaySearcher.Create(Pattern);
  try RequireOffset(S, Work, -1, 'Two-Way NoMatch'); BenchSingle('NoMatch', S, Work, PatternLength, Iterations); finally S.Free; end;
  if PatternLength <= 64 then
  begin
    S := TBitapSearcher.Create(Pattern);
    try RequireOffset(S, Work, -1, 'Bitap NoMatch'); BenchSingle('NoMatch', S, Work, PatternLength, Iterations); finally S.Free; end;
    S := TSbndmSearcher.Create(Pattern);
    try RequireOffset(S, Work, -1, 'SBNDM NoMatch'); BenchSingle('NoMatch', S, Work, PatternLength, Iterations); finally S.Free; end;
  end;
  if TAvx2Searcher.Available then
  begin
    S := TAvx2Searcher.Create(Pattern);
    try RequireOffset(S, Work, -1, 'AVX2 NoMatch'); BenchSingle('NoMatch', S, Work, PatternLength, Iterations); finally S.Free; end;
  end;
  S := TPatternSearch.Compile(Pattern);
  try RequireOffset(S, Work, -1, 'Auto NoMatch'); BenchSingle('NoMatch-Auto', S, Work, PatternLength, Iterations); finally S.Free; end;
end;

procedure BenchMasked(const Data: TBytes; PatternLength, Iterations: Integer);
var
  PatternBytes, Masks, Work: TBytes;
  Pattern: TBytePattern;
  I: Integer;
  ExpectedOffset: Int64;
  S: TSinglePatternSearcher;
begin
  PatternBytes := CreatePattern(PatternLength);
  SetLength(Masks, PatternLength);
  for I := 0 to PatternLength - 1 do
    case I mod 4 of
      0: Masks[I] := $FF;
      1: Masks[I] := $F0;
      2: Masks[I] := $0F;
    else
      Masks[I] := $00;
    end;
  Pattern := TBytePattern.Masked(PatternBytes, Masks);
  Work := Copy(Data);
  InsertPattern(Work, PatternBytes, Length(Work) - PatternLength - 11);
  ExpectedOffset := NaiveMaskedFindFirst(Work, Pattern);
  S := TBitapSearcher.Create(Pattern);
  try RequireOffset(S, Work, ExpectedOffset, 'Bitap Masked'); BenchSingle('Masked', S, Work, PatternLength, Iterations); finally S.Free; end;
  S := TSbndmSearcher.Create(Pattern);
  try RequireOffset(S, Work, ExpectedOffset, 'SBNDM Masked'); BenchSingle('Masked', S, Work, PatternLength, Iterations); finally S.Free; end;
end;

procedure BenchFuzzy(DataBytes, PatternLength, MaxDistance, Iterations: Integer);
var
  Data, Pattern: TBytes;
  S: TSinglePatternSearcher;
  Expected: TPatternMatch;
begin
  SetLength(Data, DataBytes);
  FillRandom(Data);
  Pattern := CreatePattern(PatternLength);
  InsertPattern(Data, Pattern, Length(Data) - PatternLength - 3);
  if PatternLength > 2 then
    Data[Length(Data) - PatternLength - 3 + PatternLength div 2] := Data[Length(Data) - PatternLength - 3 + PatternLength div 2] xor $5A;
  S := TLevenshteinSearcher.Create(Pattern, MaxDistance);
  try
    Expected := S.FindFirst(Data);
    if not Expected.Found then
      raise Exception.Create('Levenshtein fuzzy benchmark validation found no match');
    BenchSingle('Fuzzy', S, Data, PatternLength, Iterations);
  finally
    S.Free;
  end;
  if PatternLength <= 64 then
  begin
    S := TMyersSearcher.Create(Pattern, MaxDistance);
    try RequireSameMatch(S, Data, Expected, 'Myers'); BenchSingle('Fuzzy', S, Data, PatternLength, Iterations); finally S.Free; end;
  end;
  S := TPatternSearch.Compile(Pattern, saAuto, MaxDistance);
  try RequireSameMatch(S, Data, Expected, 'Auto fuzzy'); BenchSingle('Fuzzy-Auto', S, Data, PatternLength, Iterations); finally S.Free; end;
end;

procedure BenchMulti(const Data: TBytes; PatternCount, PatternLength, BaseIterations: Integer);
var
  Patterns: TArray<TBytes>;
  Work: TBytes;
  I, J, Iterations: Integer;
  S: TMultiPatternSearcher;
  SW: TStopwatch;
  Samples: TArray<Double>;
  M, Expected: TPatternMatch;
  Ms, MBps: Double;
  LocalChecksum, RunChecksum: UInt64;
  Name: string;

  procedure Measure(const Category, AlgorithmNameValue: string);
  var
    MeasureIndex, RunIndex: Integer;
  begin
    SW := TStopwatch.StartNew;
    for MeasureIndex := 1 to BaseIterations do
      S.FindFirst(Work);
    SW.Stop;
    Iterations := CalibratedIterations(BaseIterations, SW.Elapsed.TotalMilliseconds, GTargetMilliseconds);
    SetLength(Samples, GMeasureRuns);
    LocalChecksum := 0;
    for RunIndex := 0 to High(Samples) do
    begin
      RunChecksum := 0;
      SW := TStopwatch.StartNew;
      for MeasureIndex := 1 to Iterations do
      begin
        M := S.FindFirst(Work);
        RunChecksum := RunChecksum xor UInt64(M.Offset + 1) xor UInt64(M.PatternIndex + 1);
      end;
      SW.Stop;
      Samples[RunIndex] := SW.Elapsed.TotalMilliseconds;
      LocalChecksum := LocalChecksum xor RunChecksum xor UInt64(RunIndex + 1);
    end;
    Ms := MedianMilliseconds(Samples);
    if Ms > 0 then MBps := (Length(Work) * Int64(Iterations) / 1048576.0) / (Ms / 1000.0) else MBps := 0;
    GChecksum := GChecksum xor LocalChecksum;
    Emit(Category, AlgorithmNameValue, Length(Work), PatternLength, PatternCount, Iterations, Ms, MBps, LocalChecksum);
  end;

begin
  SetLength(Patterns, PatternCount);
  for I := 0 to PatternCount - 1 do
  begin
    SetLength(Patterns[I], PatternLength);
    for J := 0 to PatternLength - 1 do
      Patterns[I][J] := Byte((I * 53 + J * 109 + 31) and $FF);
  end;
  Work := Copy(Data);
  InsertPattern(Work, Patterns[PatternCount - 1], Length(Work) - PatternLength - 5);
  S := TAhoCorasickSearcher.Create(Patterns);
  try
    Expected := S.FindFirst(Work);
    if not Expected.Found then
      raise Exception.Create('Aho-Corasick multi benchmark validation found no match');
    Name := AlgorithmName(S);
    Measure('Multi', Name);
  finally
    S.Free;
  end;
  S := TCommentzWalterSearcher.Create(Patterns);
  try
    RequireMultiMatch(S, Work, Expected.Offset, Expected.PatternIndex, 'Commentz-Walter');
    Name := AlgorithmName(S);
    Measure('Multi', Name);
  finally
    S.Free;
  end;
  S := TPatternSearch.CompileMany(Patterns);
  try
    RequireMultiMatch(S, Work, Expected.Offset, Expected.PatternIndex, 'Auto multi');
    Name := 'Auto-' + AlgorithmName(S);
    Measure('Multi', Name);
  finally
    S.Free;
  end;
end;

function SameMatches(const A, B: TPatternMatches): Boolean;
var
  I: Integer;
begin
  if Length(A) <> Length(B) then
    Exit(False);
  for I := 0 to High(A) do
    if (A[I].Offset <> B[I].Offset) or (A[I].MatchLength <> B[I].MatchLength) or (A[I].PatternIndex <> B[I].PatternIndex) or (A[I].Distance <> B[I].Distance) then
      Exit(False);
  Result := True;
end;

procedure BenchMultiAllOne(Searcher: TMultiPatternSearcher; const Work: TBytes; const Expected: TPatternMatches; PatternLength, PatternCount, BaseIterations: Integer; const NamePrefix: string);
var
  I, Run, Iterations: Integer;
  A: TPatternMatches;
  SW: TStopwatch;
  Samples: TArray<Double>;
  Ms, MBps: Double;
  LocalChecksum, RunChecksum: UInt64;
begin
  try
    A := Searcher.FindAll(Work);
    if not SameMatches(A, Expected) then
      raise Exception.Create(NamePrefix + AlgorithmName(Searcher) + ' multi FindAll benchmark validation mismatch');
    SW := TStopwatch.StartNew;
    for I := 1 to BaseIterations do
      Searcher.FindAll(Work);
    SW.Stop;
    Iterations := CalibratedIterations(BaseIterations, SW.Elapsed.TotalMilliseconds, GTargetMilliseconds);
    SetLength(Samples, GMeasureRuns);
    LocalChecksum := 0;
    for Run := 0 to High(Samples) do
    begin
      RunChecksum := 0;
      SW := TStopwatch.StartNew;
      for I := 1 to Iterations do
      begin
        A := Searcher.FindAll(Work);
        RunChecksum := RunChecksum xor UInt64(Length(A));
        if Length(A) > 0 then
          RunChecksum := RunChecksum xor UInt64(A[High(A)].Offset + 1) xor UInt64(A[High(A)].PatternIndex + 1);
      end;
      SW.Stop;
      Samples[Run] := SW.Elapsed.TotalMilliseconds;
      LocalChecksum := LocalChecksum xor RunChecksum xor UInt64(Run + 1);
    end;
    Ms := MedianMilliseconds(Samples);
    if Ms > 0 then MBps := (Length(Work) * Int64(Iterations) / 1048576.0) / (Ms / 1000.0) else MBps := 0;
    GChecksum := GChecksum xor LocalChecksum;
    Emit('MultiAll', NamePrefix + AlgorithmName(Searcher), Length(Work), PatternLength, PatternCount, Iterations, Ms, MBps, LocalChecksum);
  finally
    Searcher.Free;
  end;
end;

procedure BenchMultiAll(const Data: TBytes; PatternCount, PatternLength, Iterations: Integer);
var
  Patterns: TArray<TBytes>;
  Work: TBytes;
  Expected: TPatternMatches;
  I, J: Integer;
  Reference: TMultiPatternSearcher;
begin
  SetLength(Patterns, PatternCount);
  for I := 0 to PatternCount - 1 do
  begin
    SetLength(Patterns[I], PatternLength);
    for J := 0 to PatternLength - 1 do
      Patterns[I][J] := Byte((I * 71 + J * 113 + 19) and $FF);
  end;
  Work := Copy(Data);
  InsertPattern(Work, Patterns[0], 1024);
  InsertPattern(Work, Patterns[PatternCount div 2], Length(Work) div 2);
  InsertPattern(Work, Patterns[PatternCount - 1], Length(Work) - PatternLength - 1024);
  Reference := TAhoCorasickSearcher.Create(Patterns);
  try
    Expected := Reference.FindAll(Work);
  finally
    Reference.Free;
  end;
  BenchMultiAllOne(TAhoCorasickSearcher.Create(Patterns), Work, Expected, PatternLength, PatternCount, Iterations, '');
  BenchMultiAllOne(TCommentzWalterSearcher.Create(Patterns), Work, Expected, PatternLength, PatternCount, Iterations, '');
  BenchMultiAllOne(TPatternSearch.CompileMany(Patterns), Work, Expected, PatternLength, PatternCount, Iterations, 'Auto-');
end;

procedure BenchCompileMulti(PatternCount, PatternLength, BaseIterations: Integer);
var
  Patterns: TArray<TBytes>;
  S: TMultiPatternSearcher;
  I, J, K, Run, Iterations: Integer;
  SW: TStopwatch;
  Samples: TArray<Double>;
  Ms: Double;
  LocalChecksum, RunChecksum: UInt64;

  procedure CompileOnce(AlgorithmIndex: Integer; out Searcher: TMultiPatternSearcher);
  begin
    case AlgorithmIndex of
      0: Searcher := TAhoCorasickSearcher.Create(Patterns);
      1: Searcher := TCommentzWalterSearcher.Create(Patterns);
    else
      Searcher := TPatternSearch.CompileMany(Patterns);
    end;
  end;

begin
  SetLength(Patterns, PatternCount);
  for I := 0 to PatternCount - 1 do
  begin
    SetLength(Patterns[I], PatternLength);
    for J := 0 to PatternLength - 1 do
      Patterns[I][J] := Byte((I * 97 + J * 43 + 11) and $FF);
  end;
  for K := 0 to 2 do
  begin
    CompileOnce(K, S);
    S.Free;
    SW := TStopwatch.StartNew;
    for I := 1 to BaseIterations do
    begin
      CompileOnce(K, S);
      S.Free;
    end;
    SW.Stop;
    Iterations := CalibratedIterations(BaseIterations, SW.Elapsed.TotalMilliseconds, GCompileTargetMilliseconds);
    SetLength(Samples, GMeasureRuns);
    LocalChecksum := 0;
    for Run := 0 to High(Samples) do
    begin
      RunChecksum := 0;
      SW := TStopwatch.StartNew;
      for I := 1 to Iterations do
      begin
        CompileOnce(K, S);
        try
          RunChecksum := RunChecksum xor UInt64(S.PatternCount);
        finally
          S.Free;
        end;
      end;
      SW.Stop;
      Samples[Run] := SW.Elapsed.TotalMilliseconds;
      LocalChecksum := LocalChecksum xor RunChecksum xor UInt64(Run + 1);
    end;
    Ms := MedianMilliseconds(Samples);
    GChecksum := GChecksum xor LocalChecksum;
    case K of
      0: Emit('CompileMulti', 'AhoCorasick', 0, PatternLength, PatternCount, Iterations, Ms, 0, LocalChecksum);
      1: Emit('CompileMulti', 'CommentzWalter', 0, PatternLength, PatternCount, Iterations, Ms, 0, LocalChecksum);
    else
      Emit('CompileMulti', 'Auto', 0, PatternLength, PatternCount, Iterations, Ms, 0, LocalChecksum);
    end;
  end;
end;

procedure BenchStreamSingle(Searcher: TSinglePatternSearcher; const Work: TBytes; ExpectedOffset: Int64; PatternLength, BaseIterations: Integer);
var
  Stream: TMemoryStream;
  SW: TStopwatch;
  I, Run, Iterations: Integer;
  M: TPatternMatch;
  Samples: TArray<Double>;
  Ms, MBps: Double;
  LocalChecksum, RunChecksum: UInt64;
begin
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(Work[0], Length(Work));
    Stream.Position := 0;
    M := Searcher.FindFirst(Stream, True);
    if (not M.Found) or (M.Offset <> ExpectedOffset) then raise Exception.CreateFmt('%s stream benchmark validation expected %d, got %d', [AlgorithmName(Searcher), ExpectedOffset, M.Offset]);
    SW := TStopwatch.StartNew;
    for I := 1 to BaseIterations do
    begin
      Stream.Position := 0;
      Searcher.FindFirst(Stream, True);
    end;
    SW.Stop;
    Iterations := CalibratedIterations(BaseIterations, SW.Elapsed.TotalMilliseconds, GTargetMilliseconds);
    SetLength(Samples, GMeasureRuns);
    LocalChecksum := 0;
    for Run := 0 to High(Samples) do
    begin
      RunChecksum := 0;
      SW := TStopwatch.StartNew;
      for I := 1 to Iterations do
      begin
        Stream.Position := 0;
        M := Searcher.FindFirst(Stream, True);
        RunChecksum := RunChecksum xor UInt64(M.Offset + 1);
      end;
      SW.Stop;
      Samples[Run] := SW.Elapsed.TotalMilliseconds;
      LocalChecksum := LocalChecksum xor RunChecksum xor UInt64(Run + 1);
    end;
    Ms := MedianMilliseconds(Samples);
    if Ms > 0 then MBps := (Length(Work) * Int64(Iterations) / 1048576.0) / (Ms / 1000.0) else MBps := 0;
    GChecksum := GChecksum xor LocalChecksum;
    Emit('Stream', AlgorithmName(Searcher), Length(Work), PatternLength, 1, Iterations, Ms, MBps, LocalChecksum);
  finally
    Searcher.Free;
    Stream.Free;
  end;
end;

procedure BenchStream(const Data: TBytes; PatternLength, Iterations: Integer);
var
  Pattern, Work: TBytes;
  ExpectedOffset: Int64;
begin
  Pattern := CreatePattern(PatternLength);
  Work := Copy(Data);
  InsertPattern(Work, Pattern, Length(Work) - PatternLength - 17);
  ExpectedOffset := NaiveFindFirst(Work, Pattern);
  BenchStreamSingle(TBoyerMooreHorspoolSearcher.Create(Pattern), Work, ExpectedOffset, PatternLength, Iterations);
  BenchStreamSingle(TRabinKarpSearcher.Create(Pattern), Work, ExpectedOffset, PatternLength, Iterations);
  BenchStreamSingle(TTwoWaySearcher.Create(Pattern), Work, ExpectedOffset, PatternLength, Iterations);
  if PatternLength <= 64 then
  begin
    BenchStreamSingle(TBitapSearcher.Create(Pattern), Work, ExpectedOffset, PatternLength, Iterations);
    BenchStreamSingle(TSbndmSearcher.Create(Pattern), Work, ExpectedOffset, PatternLength, Iterations);
  end;
  if TAvx2Searcher.Available then BenchStreamSingle(TAvx2Searcher.Create(Pattern), Work, ExpectedOffset, PatternLength, Iterations);
  BenchStreamSingle(TPatternSearch.Compile(Pattern), Work, ExpectedOffset, PatternLength, Iterations);
end;

procedure BenchCompileExact(PatternLength, BaseIterations: Integer);
const
  Algorithms: array[0..4] of TPatternSearchAlgorithm = (saBoyerMooreHorspool, saRabinKarp, saTwoWay, saBitap, saSbndm);
var
  Pattern: TBytes;
  Algorithm: TPatternSearchAlgorithm;
  S: TSinglePatternSearcher;
  SW: TStopwatch;
  Samples: TArray<Double>;
  Ms: Double;
  I, Run, Iterations, AlgorithmIndex: Integer;
  LocalChecksum, RunChecksum: UInt64;
  Name: string;
begin
  Pattern := CreatePattern(PatternLength);
  for AlgorithmIndex := Low(Algorithms) to High(Algorithms) do
  begin
    Algorithm := Algorithms[AlgorithmIndex];
    if (PatternLength > 64) and (Algorithm in [saBitap, saSbndm]) then Continue;
    S := TPatternSearch.Compile(Pattern, Algorithm);
    S.Free;
    SW := TStopwatch.StartNew;
    for I := 1 to BaseIterations do
    begin
      S := TPatternSearch.Compile(Pattern, Algorithm);
      S.Free;
    end;
    SW.Stop;
    Iterations := CalibratedIterations(BaseIterations, SW.Elapsed.TotalMilliseconds, GCompileTargetMilliseconds);
    SetLength(Samples, GMeasureRuns);
    LocalChecksum := 0;
    Name := '';
    for Run := 0 to High(Samples) do
    begin
      RunChecksum := 0;
      SW := TStopwatch.StartNew;
      for I := 1 to Iterations do
      begin
        S := TPatternSearch.Compile(Pattern, Algorithm);
        try
          RunChecksum := RunChecksum xor UInt64(Length(S.Pattern));
          Name := AlgorithmName(S);
        finally
          S.Free;
        end;
      end;
      SW.Stop;
      Samples[Run] := SW.Elapsed.TotalMilliseconds;
      LocalChecksum := LocalChecksum xor RunChecksum xor UInt64(Run + 1);
    end;
    Ms := MedianMilliseconds(Samples);
    GChecksum := GChecksum xor LocalChecksum;
    Emit('Compile', Name, 0, PatternLength, 1, Iterations, Ms, 0, LocalChecksum);
  end;
  if TAvx2Searcher.Available then
  begin
    S := TAvx2Searcher.Create(Pattern);
    S.Free;
    SW := TStopwatch.StartNew;
    for I := 1 to BaseIterations do
    begin
      S := TAvx2Searcher.Create(Pattern);
      S.Free;
    end;
    SW.Stop;
    Iterations := CalibratedIterations(BaseIterations, SW.Elapsed.TotalMilliseconds, GCompileTargetMilliseconds);
    SetLength(Samples, GMeasureRuns);
    LocalChecksum := 0;
    for Run := 0 to High(Samples) do
    begin
      RunChecksum := 0;
      SW := TStopwatch.StartNew;
      for I := 1 to Iterations do
      begin
        S := TAvx2Searcher.Create(Pattern);
        try RunChecksum := RunChecksum xor UInt64(Length(S.Pattern)); finally S.Free; end;
      end;
      SW.Stop;
      Samples[Run] := SW.Elapsed.TotalMilliseconds;
      LocalChecksum := LocalChecksum xor RunChecksum xor UInt64(Run + 1);
    end;
    Ms := MedianMilliseconds(Samples);
    GChecksum := GChecksum xor LocalChecksum;
    Emit('Compile', 'Avx2', 0, PatternLength, 1, Iterations, Ms, 0, LocalChecksum);
  end;
end;

function CsvPath: string;
var
  I: Integer;
  P: string;
begin
  Result := '';
  for I := 1 to ParamCount do
  begin
    P := ParamStr(I);
    if P.StartsWith('--csv=') then
      Exit(Copy(P, Length('--csv=') + 1, MaxInt));
  end;
end;

function HasParam(const Value: string): Boolean;
var
  I: Integer;
begin
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), Value) then
      Exit(True);
  Result := False;
end;

function IntParam(const Name: string; DefaultValue: Integer): Integer;
var
  I, Value: Integer;
  P, Prefix: string;
begin
  Prefix := Name + '=';
  for I := 1 to ParamCount do
  begin
    P := ParamStr(I);
    if P.StartsWith(Prefix) and TryStrToInt(Copy(P, Length(Prefix) + 1, MaxInt), Value) and (Value > 0) then
      Exit(Value);
  end;
  Result := DefaultValue;
end;

var
  Data: TBytes;
  DataSize, DataMegabytes, Iterations, FuzzySize, FuzzyIterations, MultiIterations: Integer;
  DataBytes64: Int64;
  Path: string;
begin
  ReportMemoryLeaksOnShutdown := True;
  GFormat := TFormatSettings.Invariant;
  GCsv := TStringList.Create;
  try
    GCsv.Add('category;algorithm;data_bytes;pattern_length;pattern_count;iterations;elapsed_ms;ns_per_op;mb_per_s;checksum');
    GChecksum := 0;
    if HasParam('--full') then
    begin
      DataSize := 256 * 1024 * 1024;
      Iterations := 7;
      FuzzySize := 256 * 1024;
      FuzzyIterations := 3;
      MultiIterations := 5;
      GTargetMilliseconds := 100;
      GMeasureRuns := 5;
    end
    else
    begin
      DataSize := 64 * 1024 * 1024;
      Iterations := 4;
      FuzzySize := 64 * 1024;
      FuzzyIterations := 2;
      MultiIterations := 3;
      GTargetMilliseconds := 50;
      GMeasureRuns := 5;
    end;
    DataMegabytes := IntParam('--data-mb', DataSize div (1024 * 1024));
    DataBytes64 := Int64(DataMegabytes) * 1024 * 1024;
    if DataBytes64 > MaxInt then
      raise EArgumentException.Create('--data-mb exceeds supported data size');
    DataSize := Integer(DataBytes64);
    GTargetMilliseconds := IntParam('--target-ms', GTargetMilliseconds);
    GMeasureRuns := IntParam('--runs', GMeasureRuns);
    GCompileTargetMilliseconds := GTargetMilliseconds div 2;
    if GCompileTargetMilliseconds < 10 then
      GCompileTargetMilliseconds := 10;
    SetLength(Data, DataSize);
    FillRandom(Data);
    Writeln('NativePE Pattern Search Benchmark');
    Writeln('Data bytes: ', DataSize);
    Writeln('AVX2 available: ', BoolToStr(TAvx2Searcher.Available, True));
    Writeln('Measure runs: ', GMeasureRuns);
    Writeln('Reported time: median');
    Writeln('Target ms/run: ', GTargetMilliseconds);
    Writeln('Compile target ms/run: ', GCompileTargetMilliseconds);
    Writeln;
    BenchCompileExact(8, 2000);
    BenchCompileExact(32, 1000);
    BenchCompileExact(128, 500);
    BenchCompileMulti(16, 8, 100);
    BenchCompileMulti(64, 12, 50);
    BenchCompileMulti(256, 16, 20);
    BenchExact(Data, 4, Iterations);
    BenchExact(Data, 8, Iterations);
    BenchExact(Data, 16, Iterations);
    BenchExact(Data, 32, Iterations);
    BenchExact(Data, 64, Iterations);
    BenchExact(Data, 128, Iterations);
    BenchExact(Data, 300, Iterations);
    BenchExact(Data, 1024, Iterations);
    BenchExactVariants(Data, 128, Iterations);
    BenchExactVariants(Data, 300, Iterations);
    BenchExactVariants(Data, 1024, Iterations);
    BenchFindAllSparse(Data, 16, Iterations);
    BenchNoMatch(Data, 8, Iterations);
    BenchNoMatch(Data, 32, Iterations);
    BenchNoMatch(Data, 128, Iterations);
    BenchMasked(Data, 16, Iterations);
    BenchMasked(Data, 32, Iterations);
    BenchMasked(Data, 64, Iterations);
    BenchFuzzy(FuzzySize, 8, 1, FuzzyIterations);
    BenchFuzzy(FuzzySize, 16, 1, FuzzyIterations);
    BenchFuzzy(FuzzySize, 32, 2, FuzzyIterations);
    BenchFuzzy(FuzzySize, 64, 2, FuzzyIterations);
    BenchMulti(Data, 4, 8, MultiIterations);
    BenchMulti(Data, 16, 8, MultiIterations);
    BenchMulti(Data, 64, 12, MultiIterations);
    BenchMulti(Data, 256, 16, MultiIterations);
    BenchMultiAll(Data, 16, 8, MultiIterations);
    BenchMultiAll(Data, 64, 12, MultiIterations);
    BenchStream(Data, 16, Iterations);
    BenchStream(Data, 64, Iterations);
    BenchStream(Data, 300, Iterations);
    Path := CsvPath;
    if Path <> '' then
    begin
      ForceDirectories(ExtractFileDir(ExpandFileName(Path)));
      GCsv.SaveToFile(Path, TEncoding.UTF8);
      Writeln('CSV: ', ExpandFileName(Path));
    end;
    Writeln('Global checksum: ', IntToHex(GChecksum, 16));
  finally
    GCsv.Free;
  end;
end.
