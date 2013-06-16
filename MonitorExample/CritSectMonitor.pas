unit CritSectMonitor;

interface

uses
  Windows;

type
  PCritSectMonitor = ^TCritSectMonitor;
  TCritSectMonitor = record
  private
    FCriticalSection: TRTLCriticalSection;
    FInitialized: Integer;
    procedure Initialize;
    class procedure DestroyCritSect(Data: Pointer); static;
    class function GetCriticalSection(const AObject: TObject): PCritSectMonitor; static;
  public
    class procedure Enter(const AObject: TObject); static;
    class function TryEnter(const AObject: TObject): Boolean; static;
    class procedure Exit(const AObject: TObject); static;
    class procedure SetSpinCount(const AObject: TObject; ASpinCount: Integer); static;
  end;

implementation

uses
  WeakObjectReferences;

var
  CritSectMonitorOffset: Integer;
  CPUCount: Integer;

class procedure TCritSectMonitor.DestroyCritSect(Data: Pointer);
begin
  if PCritSectMonitor(Data).FInitialized <> 0 then
  begin
    while PCritSectMonitor(Data).FInitialized > 0 do // wait till the initialiation is over
      if CPUCount = 1 then
        SwitchToThread;
    DeleteCriticalSection(PCritSectMonitor(Data).FCriticalSection);
  end;
end;

procedure TCritSectMonitor.Initialize;
begin
  try
    if InterlockedIncrement(FInitialized) = 1 then
      InitializeCriticalSectionAndSpinCount(FCriticalSection, 4000)
    else
    begin
      while FInitialized > 0 do // spinning
        if CPUCount = 1 then
          SwitchToThread;
    end;
  finally
    FInitialized := -1; // release the lock and mark as initialized
  end;
end;

class function TCritSectMonitor.GetCriticalSection(const AObject: TObject): PCritSectMonitor;
begin
  Result := PCritSectMonitor(TInternalWeakReferenceHelper.GetAdditionalData(AObject, CritSectMonitorOffset));
  if Result.FInitialized >= 0 then
    Result.Initialize;
end;

class procedure TCritSectMonitor.SetSpinCount(const AObject: TObject; ASpinCount: Integer);
begin
  SetCriticalSectionSpinCount(GetCriticalSection(AObject).FCriticalSection, DWORD(ASpinCount));
end;

class procedure TCritSectMonitor.Enter(const AObject: TObject);
begin
  EnterCriticalSection(GetCriticalSection(AObject).FCriticalSection);
end;

class function TCritSectMonitor.TryEnter(const AObject: TObject): Boolean;
begin
  Result := TryEnterCriticalSection(GetCriticalSection(AObject).FCriticalSection);
end;

class procedure TCritSectMonitor.Exit(const AObject: TObject);
begin
  LeaveCriticalSection(GetCriticalSection(AObject).FCriticalSection);
end;

procedure Init;
var
  SystemInfo: TSystemInfo;
begin
  GetSystemInfo(SystemInfo);
  CPUCount := SystemInfo.dwNumberOfProcessors;
  CritSectMonitorOffset := TInternalWeakReferenceHelper.RegisterAdditionalData(SizeOf(TCritSectMonitor), TCritSectMonitor.DestroyCritSect);
end;

initialization
  Init;

end.
