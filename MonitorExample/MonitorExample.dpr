program MonitorExample;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  SysUtils,
  Classes,
  WeakObjectReferences in '..\Source\WeakObjectReferences.pas',
  CritSectMonitor in 'CritSectMonitor.pas';

procedure Main;
var
  Obj: TObject;
  Thread: TThread;
begin
  Obj := TObject.Create;
  try
    TCritSectMonitor.Enter(Obj);
    WriteLn('Main enter');

    Thread := TThread.CreateAnonymousThread(
      procedure()
      begin
        WriteLn('Thread start');
        TCritSectMonitor.Enter(Obj);
        WriteLn('Thread entered');
        TCritSectMonitor.Exit(Obj);
      end);
    Thread.FreeOnTerminate := False;

    WriteLn('Main wait');

    Thread.Start;
    Sleep(1000);

    WriteLn('Main leave');
    TCritSectMonitor.Exit(Obj);
    Thread.WaitFor;
  finally
    Obj.Free;
  end;

  if DebugHook <> 0 then
  begin
    WriteLn;
    WriteLn('Press <ENTER> to quit.');
    ReadLn;
  end;
end;

begin
  Main;
end.
