{**************************************************************************************************}
{                                                                                                  }
{ WeakReference implementation for objects                                                         }
{                                                                                                  }
{ The contents of this file are subject to the Mozilla Public License Version 1.1 (the "License"); }
{ you may not use this file except in compliance with the License. You may obtain a copy of the    }
{ License at http://www.mozilla.org/MPL/                                                           }
{                                                                                                  }
{ Software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTY OF   }
{ ANY KIND, either express or implied. See the License for the specific language governing rights  }
{ and limitations under the License.                                                               }
{                                                                                                  }
{ The Original Code is WeakObjectReferences.pas.                                                   }
{                                                                                                  }
{ The Initial Developer of the Original Code is Andreas Hausladen.                                 }
{ Portions created by Andreas Hausladen are Copyright (C) 2013 Andreas Hausladen.                  }
{ All Rights Reserved.                                                                             }
{                                                                                                  }
{ Contributor(s):                                                                                  }
{                                                                                                  }
{**************************************************************************************************}
{$A8,B-,K-,M-,O+,P+,Q-,R-,S-,T-,W-,X+,Z1}
unit WeakObjectReferences;

interface

{$WEAKPACKAGEUNIT}

// The WeakReference interface supports the QueryInterface method if ALLOW_QUERYINTERFACE is defined and
// redirects it to the actual object or returns E_NOINTERFACE is the object is nil.
{$DEFINE ALLOW_QUERYINTERFACE}

// If USE_MONITOR_FIELD is defined the WeakReference is stored in the TObject.Monitor field and the original
// Monitor field is redirected (hooking). Without this option all objects that support weak references must
// inherit from TWeakRefBaseObject.
{$DEFINE USE_MONITOR_FIELD}

type
  { All objects that support WeakReferences must inherit from TWeakRefBaseObject if USE_MONITOR_FIELD is
    disabled. }
  TWeakRefBaseObject = class(TObject)
  private
    FWeakReferences: Pointer;
  public
    destructor Destroy; override;
  end;

  { WeakReference }
  IWeakReference<T: class> = interface
    function GetTarget: T;
    
    { Target returns the object. If the object is already destroyed it return nil. }
    property Target: T read GetTarget;
    { IsAlive return True if the object is still alive. }
    function IsAlive: Boolean;
  end;

  { TWeakReference is a wrapper around the IWeakReference interface that makes the usage a little bit
    easier like direct assignment of the object without the "TWeakReference<T>.New(Object)" call. }
  TWeakReference<T: class> = record
  private
    FWeakRef: IWeakReference<T>;
    function GetTarget: T; inline;
  public
    { Target returns the object. If the object is already destroyed it return nil. }
    property Target: T read GetTarget;
    { IsAlive return True if the object is still alive. }
    function IsAlive: Boolean; inline;

    constructor Create(const AObject: TObject);
    procedure Assign(const AObject: TObject); inline;

    class operator Implicit(const AObject: T): TWeakReference<T>; overload; inline;
    class operator Implicit(const AValue: TWeakReference<T>): T; overload; inline;
    class operator Implicit(const AWeakRef: IWeakReference<T>): TWeakReference<T>; overload; inline;
    class operator Implicit(const AWeakRef: TWeakReference<T>): IWeakReference<T>; overload; inline;
    class operator Equal(const AWeakRef: TWeakReference<T>; const AObject: TObject): Boolean; overload; inline;
    class operator NotEqual(const AWeakRef: TWeakReference<T>; const AObject: TObject): Boolean; overload; inline;

    { New() creates a new WeakReference for the object. }
    class function New(const AObject: TObject): IWeakReference<T>; overload; static;
  end;

  { Helper class that is used internally. }
  TInternalWeakReferenceHelper = record
  private
    type
      PPWeakObjectHelper = ^PWeakObjectHelper;
      PWeakObjectHelper = ^TWeakObjectHelper;

      PWeakObjectHelperData = ^TWeakObjectHelperData;
      TWeakObjectHelperData = record
        InterfaceSelfPtr: PWeakObjectHelper;
        FObject: Pointer;
        FRefCount: Integer;
        ExtraData: record end;
      end;

      TWeakObjectHelper = record
        {$IFDEF ALLOW_QUERYINTERFACE}
        QueryInterface: function(Data: PWeakObjectHelperData; const IID: TGUID; out Obj): HRESULT; stdcall;
        {$ELSE}
          {$IFDEF USE_MONITOR_FIELD}
        Monitor: Pointer; // Use the QueryInterface slot
          {$ELSE}
        QueryInterface: Pointer;
          {$ENDIF USE_MONITOR_FIELD}
        {$ENDIF ALLOW_QUERYINTERFACE}
        AddRef: function(Data: PWeakObjectHelperData): Integer; stdcall;
        Release: function(Data: PWeakObjectHelperData): Integer; stdcall;
        GetTarget: function(Data: PWeakObjectHelperData): TObject;
        IsAlive: function(Data: PWeakObjectHelperData): Boolean;

        {$IFDEF ALLOW_QUERYINTERFACE}
          {$IFDEF USE_MONITOR_FIELD}
        Monitor: Pointer;
          {$ENDIF USE_MONITOR_FIELD}
        {$ENDIF ALLOW_QUERYINTERFACE}
        Data: TWeakObjectHelperData;
      end;

      TAdditionalDataDtorProc = procedure(Data: Pointer);

      TAdditionalDataDtor = record
        Offset: Integer;
        Dtor: TAdditionalDataDtorProc;
      end;

    class var
      AdditionalDataSize: Integer;
      AdditionalDataDtors: array of TAdditionalDataDtor;
      HelperAllocated: Boolean;

    class function GetWeakReferenceField(const AObject: TObject): PPWeakObjectHelper; static;
    class function Equals(const AWeakRef: IInterface; const AObject: TObject): Boolean; static;

    class procedure DestroyingObject(const AObject: TObject); static;
    class function GetWeakObjectHelper(const AObject: TObject): PWeakObjectHelper; static;
    class procedure GetNilWeakReference(var AWeakRef: IInterface); static;
  public
    { RegisterAdditionalData adds additional bytes to the Helper's memory block that can be used
      by other libraries to store data in the object. This function throws a RunError(255) if there
      is already a Helper allocated or Size if less than or equal zero. The returned value is
      the offset that must be used when calling GetAdditionalData. }
    class function RegisterAdditionalData(ASize: Integer; ADtor: TAdditionalDataDtorProc = nil): Integer; static;
    { GetAdditionalData returns a pointer to the additional data that was registered with
      RegisterAdditionalData. The memory is initialized with zeros. A RunError(255) is thrown
      if the Offset is negative or larger than the allocated size. The returned value points to
      the memory that contains the data. }
    class function GetAdditionalData(const AObject: TObject; AOffset: Integer): Pointer; static;
  end;

implementation

uses
  Windows;

const
  {$IFDEF CPUX64}
  HelperDefaultSize = (SizeOf(TInternalWeakReferenceHelper.TWeakObjectHelper) + 7) and not 7; // 8 Byte alignment
  {$ELSE}
  HelperDefaultSize = (SizeOf(TInternalWeakReferenceHelper.TWeakObjectHelper) + 3) and not 3; // 4 Byte alignment
  {$ENDIF CPUX64}

{$IFDEF USE_MONITOR_FIELD}
  {$DEFINE HOOK_CLASSDESTROY}
{$ENDIF USE_MONITOR_FIELD}

{ TWeakRefBaseObject }

destructor TWeakRefBaseObject.Destroy;
begin
  {$IFNDEF HOOK_CLASSDESTROY}
  TInternalWeakReferenceHelper.DestroyingObject(Self);
  {$ENDIF ~HOOK_CLASSDESTROY}
  inherited Destroy;
end;

{ Interface Callback function }

{$IFDEF ALLOW_QUERYINTERFACE}
function WeakReference_QueryInterface(Data: TInternalWeakReferenceHelper.PWeakObjectHelperData; const IID: TGUID; out Obj): HRESULT; stdcall;
var
  Instance: TObject;
  LUnknown: IUnknown;
begin
  Result := E_NOINTERFACE;
  Instance := Data.FObject;
  if Instance <> nil then
    if Instance.GetInterface(IUnknown, LUnknown) then
      Result := LUnknown.QueryInterface(IID, Obj);
end;
{$ENDIF ALLOW_QUERYINTERFACE}

function WeakReference_AddRef(Data: TInternalWeakReferenceHelper.PWeakObjectHelperData): Integer; stdcall;
begin
  Result := InterlockedIncrement(Data.FRefCount);
end;

function WeakReference_Release(Data: TInternalWeakReferenceHelper.PWeakObjectHelperData): Integer; stdcall;
begin
  Result := InterlockedDecrement(Data.FRefCount);
  if Result = 0 then
    FreeMem(Data.InterfaceSelfPtr); // Use the "Self" reference to get the start of the memory block
end;

function WeakRefNilTarget_IgnoreRefCount(Data: TInternalWeakReferenceHelper.PWeakObjectHelperData): Integer; stdcall;
begin
  Result := -1;
end;

function WeakReference_GetTarget(Data: TInternalWeakReferenceHelper.PWeakObjectHelperData): TObject;
begin
  Result := TObject(Data.FObject);
end;

function WeakReference_IsAlive(Data: TInternalWeakReferenceHelper.PWeakObjectHelperData): Boolean;
begin
  Result := Data.FObject <> nil;
end;

const
  // This constant is used as the WeakReference interface if it references a nil-Object
  WeakRefNilTarget: TInternalWeakReferenceHelper.TWeakObjectHelper = (
    {$IFDEF ALLOW_QUERYINTERFACE}
    QueryInterface: WeakReference_QueryInterface;
    {$ELSE}
      {$IFDEF USE_MONITOR_FIELD}
    Monitor: nil;
      {$ELSE}
    QueryInterface: nil;
      {$ENDIF USE_MONITOR_FIELD}
    {$ENDIF ALLOW_QUERYINTERFACE}
    AddRef: WeakRefNilTarget_IgnoreRefCount;
    Release: WeakRefNilTarget_IgnoreRefCount;
    GetTarget: WeakReference_GetTarget;
    IsAlive: WeakReference_IsAlive;
    // Monitor: nil;
    Data: (
      InterfaceSelfPtr: @WeakRefNilTarget;
      FObject: nil;
      FRefCount: -1;
    );
  );

{ TInternalWeakReferenceHelper }

class function TInternalWeakReferenceHelper.GetWeakReferenceField(const AObject: TObject): PPWeakObjectHelper;
begin
  {$IFDEF USE_MONITOR_FIELD}
  if System.MonitorSupport <> nil then
    Result := PPWeakObjectHelper(PByte(AObject) + AObject.InstanceSize - hfFieldSize + hfMonitorOffset)
  else
  // SysUtils isn't used => TWeakRefBaseObject must be used
  {$ENDIF USE_MONITOR_FIELD}
  if AObject is TWeakRefBaseObject then
    Result := @PWeakObjectHelper(TWeakRefBaseObject(AObject).FWeakReferences)
  else
    Result := nil;
end;

class function TInternalWeakReferenceHelper.GetWeakObjectHelper(const AObject: TObject): PWeakObjectHelper;
var
  OldHelper: PWeakObjectHelper;
  Field: PPWeakObjectHelper;
  {$IFDEF USE_MONITOR_FIELD}
  Monitor: PMonitor;
  {$ENDIF USE_MONITOR_FIELD}
begin
  Field := GetWeakReferenceField(AObject);
  if Field = nil then
    RunError(255); // no place to put the WeakReference field
  Result := Field^;

  {$IFDEF USE_MONITOR_FIELD}
  Monitor := nil;
  if (Result <> nil) and (@Result^.AddRef <> @WeakReference_AddRef) then
  begin
    if System.MonitorSupport = nil then
      RunError(255); // somebody else has hooked the Monitor field

    // A Monitor already exists for this object => move it to our monitor field
    Monitor := PMonitor(Result);
    Result := nil;
  end;
  {$ENDIF USE_MONITOR_FIELD}

  if Result = nil then
  begin
    HelperAllocated := True;
    GetMem(Pointer(Result), HelperDefaultSize + AdditionalDataSize);

    {$IFDEF USE_MONITOR_FIELD}
    Result.Monitor := Monitor;
    {$ELSE}
    Result.QueryInterface := nil;
    {$ENDIF USE_MONITOR_FIELD}
    {$IFDEF ALLOW_QUERYINTERFACE}
    Result.QueryInterface := WeakReference_QueryInterface;
    {$ENDIF ALLOW_QUERYINTERFACE}
    Result.AddRef := WeakReference_AddRef;
    Result.Release := WeakReference_Release;
    Result.GetTarget := WeakReference_GetTarget;
    Result.IsAlive := WeakReference_IsAlive;
    Result.Data.InterfaceSelfPtr := Result;
    Result.Data.FRefCount := 1; // => RefCount >= 2 (object + this reference)
    Result.Data.FObject := Pointer(AObject);

    if AdditionalDataSize > 0 then
      FillChar(Result.Data.ExtraData, AdditionalDataSize, 0);

    {$IFDEF USE_MONITOR_FIELD}
    OldHelper := InterlockedCompareExchangePointer(Pointer(Field^), Result, Monitor);
    if OldHelper <> Pointer(Monitor) then
    {$ELSE}
    OldHelper := InterlockedCompareExchangePointer(Pointer(Field^), Result, nil);
    if OldHelper <> nil then
    {$ENDIF USE_MONITOR_FIELD}
    begin
      // another thread was faster
      FreeMem(Result);
      Result := OldHelper;
    end;
  end;
end;

class procedure TInternalWeakReferenceHelper.GetNilWeakReference(var AWeakRef: IInterface);
begin
  AWeakRef := IInterface(@WeakRefNilTarget.Data.InterfaceSelfPtr);
end;

class function TInternalWeakReferenceHelper.RegisterAdditionalData(ASize: Integer; ADtor: TAdditionalDataDtorProc): Integer;
var
  Index: Integer;
begin
  if HelperAllocated or (ASize <= 0) then
    RunError(255);

  Result := AdditionalDataSize;
  if Assigned(ADtor) then
  begin
    Index := Length(AdditionalDataDtors);
    SetLength(AdditionalDataDtors, Index + 1);
    AdditionalDataDtors[Index].Offset := Result;
    AdditionalDataDtors[Index].Dtor := ADtor;
  end;
  {$IFDEF CPUX64}
  Inc(AdditionalDataSize, (ASize + 7) and not 7); // 8 Byte alignment
  {$ELSE}
  Inc(AdditionalDataSize, (ASize + 3) and not 3); // 4 Byte alignment
  {$ENDIF CPUX64}
end;

class procedure TInternalWeakReferenceHelper.DestroyingObject(const AObject: TObject);
var
  Field: PPWeakObjectHelper;
  Ref: PWeakObjectHelper;
  I: Integer;
begin
  Field := GetWeakReferenceField(AObject);
  Ref := Field^;
  if (Ref <> nil) {$IFDEF USE_MONITOR_FIELD}and (@Ref.AddRef = @WeakReference_AddRef){$ENDIF} then
  begin
    // Call Dtors if they are registered
    if TInternalWeakReferenceHelper.AdditionalDataDtors <> nil then
      for I := Length(TInternalWeakReferenceHelper.AdditionalDataDtors) - 1 downto 0 do
        TInternalWeakReferenceHelper.AdditionalDataDtors[I].Dtor(PByte(@Ref.Data.ExtraData) + TInternalWeakReferenceHelper.AdditionalDataDtors[I].Offset);
    Ref.Data.FObject := nil; // set all WeakReferences to nil
    {$IFDEF USE_MONITOR_FIELD}
    Field^ := Ref.Monitor; // restore Monitor field (should be nil, but who knows what some user code does to it)
    {$ELSE}
    Field^ := nil;
    {$ENDIF USE_MONITOR_FIELD}
    WeakReference_Release(@Ref.Data);
  end;
end;

class function TInternalWeakReferenceHelper.Equals(const AWeakRef: IInterface; const AObject: TObject): Boolean;
begin
  if AWeakRef <> nil then
    Result := PWeakObjectHelperData(AWeakRef)^.FObject = AObject
  else
    Result := AObject = nil;
end;

class function TInternalWeakReferenceHelper.GetAdditionalData(const AObject: TObject; AOffset: Integer): Pointer;
begin
  if (AOffset < 0) or (AOffset >= AdditionalDataSize) then
    RunError(255);
  if AObject <> nil then
    Result := PByte(@GetWeakObjectHelper(AObject).Data.ExtraData) + AOffset
  else
    Result := nil;
end;

{ TWeakReference<T> }

class function TWeakReference<T>.New(const AObject: TObject): IWeakReference<T>;
begin
  if AObject <> nil then
    IInterface(Result) := IInterface(@TInternalWeakReferenceHelper.GetWeakObjectHelper(AObject).Data.InterfaceSelfPtr)
  else
    TInternalWeakReferenceHelper.GetNilWeakReference(IInterface(Result));
end;

constructor TWeakReference<T>.Create(const AObject: TObject);
begin
  FWeakRef := TWeakReference<T>.New(AObject);
end;

procedure TWeakReference<T>.Assign(const AObject: TObject);
begin
  FWeakRef := TWeakReference<T>.New(AObject);
end;

function TWeakReference<T>.GetTarget: T;
begin
  if FWeakRef <> nil then
    Result := FWeakRef.Target
  else
    Result := nil;
end;

function TWeakReference<T>.IsAlive: Boolean;
begin
  Result := (FWeakRef <> nil) and FWeakRef.IsAlive;
end;

class operator TWeakReference<T>.Implicit(const AValue: TWeakReference<T>): T;
begin
  Result := AValue.Target;
end;

class operator TWeakReference<T>.Implicit(const AObject: T): TWeakReference<T>;
begin
  Result.Assign(AObject);
end;

class operator TWeakReference<T>.Implicit(const AWeakRef: IWeakReference<T>): TWeakReference<T>;
begin
  Result.FWeakRef := AWeakRef;
end;

class operator TWeakReference<T>.Implicit(const AWeakRef: TWeakReference<T>): IWeakReference<T>;
begin
  Result := AWeakRef.FWeakRef;
end;

class operator TWeakReference<T>.Equal(const AWeakRef: TWeakReference<T>; const AObject: TObject): Boolean;
begin
  Result := TInternalWeakReferenceHelper.Equals(AWeakRef.FWeakRef, AObject);
end;

class operator TWeakReference<T>.NotEqual(const AWeakRef: TWeakReference<T>; const AObject: TObject): Boolean;
begin
  Result := not TInternalWeakReferenceHelper.Equals(AWeakRef.FWeakRef, AObject);
end;

{$IFDEF HOOK_CLASSDESTROY}

{------------------------------------------------------------------------------------------------------------}

function GetActualAddress(Proc: Pointer): Pointer;
type
  {$IFDEF CPUX64}
  PAbsoluteIndirectJmp64 = ^TAbsoluteIndirectJmp64;
  TAbsoluteIndirectJmp64 = packed record
    OpCode: Word;   //$FF25(Jmp, FF /4)
    Rel: Integer;
  end;
  {$ELSE}
  PAbsoluteIndirectJmp32 = ^TAbsoluteIndirectJmp32;
  TAbsoluteIndirectJmp32 = packed record
    OpCode: Word;   //$FF25(Jmp, FF /4)
    Addr: ^Pointer;
  end;
  {$ENDIF CPUX64}
begin
  Result := Proc;
  if Result <> nil then
  begin
    {$IFDEF CPUX64}
    if (PAbsoluteIndirectJmp64(Result).OpCode = $25FF) then
      Result := PPointer(PByte(@PAbsoluteIndirectJmp64(Result).OpCode) + SizeOf(TAbsoluteIndirectJmp64) + PAbsoluteIndirectJmp64(Result).Rel)^;
    {$ELSE}
    if (PAbsoluteIndirectJmp32(Result).OpCode = $25FF) then
      Result := PAbsoluteIndirectJmp32(Result).Addr^;
    {$ENDIF CPUX64}
  end;
end;

function InjectJump(Proc: PByte; Target: Pointer): Boolean;
{$IF not declared(SIZE_T)}
type
  SIZE_T = ULONG_PTR;
{$IFEND}
var
  Buffer: array[0..5] of Byte;
  n: SIZE_T;
begin
  Buffer[0] := $E9; // JMP
  PInteger(@Buffer[1])^ := PByte(Target) - (Proc + 5);
  Buffer[5] := $90; // NOP, not necessary but looks better
  Result := WriteProcessMemory(GetCurrentProcess, Proc, @Buffer, SizeOf(Buffer), n);
end;

function GetSystemClassDestroyAddr: Pointer;
asm
  {$IFDEF CPUX64}
  mov rax, OFFSET System.@ClassDestroy
  {$ELSE}
  mov eax, OFFSET System.@ClassDestroy
  {$ENDIF CPUX64}
end;

{$IFDEF USE_MONITOR_FIELD}
function GetCallTargetBetween(Proc: PByte; StartP, EndP: PByte; SkipMatchingCalls: Integer = 0;
  MaxCalls: Integer = 10): PByte;
var
  Offset: Integer;
begin
  while MaxCalls > 0 do
  begin
    if Proc^ = $E8 then // CALL
    begin
      Offset := PInteger(Proc + 1)^;
      Result := Proc + (1 + SizeOf(Integer)) + Offset;
      if (Result >= StartP) and (Result <= EndP) then
      begin
        if SkipMatchingCalls <= 0 then
          Exit;
        Dec(SkipMatchingCalls);
      end;
      Dec(MaxCalls);
    end;
    Inc(Proc);
  end;
  Result := nil;
end;
{$ENDIF USE_MONITOR_FIELD}

{------------------------------------------------------------------------------------------------------------}

procedure _ClassDestroy(const Instance: TObject);
begin
  TInternalWeakReferenceHelper.DestroyingObject(Instance);
  Instance.FreeInstance;
end;

{$IFDEF USE_MONITOR_FIELD}
function MonitorGetFieldAddress(const AObject: TObject): PPMonitor;
var
  Ref: TInternalWeakReferenceHelper.PWeakObjectHelper;
begin
  Result := PPMonitor(PByte(AObject) + AObject.InstanceSize - hfFieldSize + hfMonitorOffset);
  Ref := TInternalWeakReferenceHelper.PPWeakObjectHelper(Result)^;
  if (Ref <> nil) and TInternalWeakReferenceHelper.HelperAllocated then
  begin
    // If our WeakReference is placed into the Monitor field, return the backuped Monitor
    if @Ref.AddRef = @WeakReference_AddRef then
      Result := Ref.Monitor;
  end;
end;
{$ENDIF USE_MONITOR_FIELD}

procedure InitHooks;
{$IFDEF USE_MONITOR_FIELD}
var
  P, EndP: PByte;
  GetMonitorProc, GetFieldAddressProc: PByte;
{$ENDIF USE_MONITOR_FIELD}
begin
  {$IFDEF USE_MONITOR_FIELD}
  P := GetActualAddress(@TMonitor.Exit);
  EndP := GetActualAddress(@TMonitor.SetSpinCount);

  // Go through TMonitor.Exit and find the private TMonitor.GetMonitor call.
  GetMonitorProc := GetCallTargetBetween(P, P, EndP);
  GetFieldAddressProc := nil;
  // Go through TMonitor.GetMonitor and find the private TMonitor.GetFieldAddress (it is marked as inline,
  // but the compiler can't inline it what makes this easy)
  if GetMonitorProc <> nil then
    GetFieldAddressProc := GetCallTargetBetween(GetMonitorProc, P, EndP);

  if GetFieldAddressProc <> nil then
    InjectJump(GetFieldAddressProc, @MonitorGetFieldAddress)
  else
    RunError(255); // cannot hook TMonitor.GetFieldAddress
  {$ENDIF USE_MONITOR_FIELD}

  InjectJump(GetActualAddress(GetSystemClassDestroyAddr), @_ClassDestroy);
end;
{$ENDIF HOOK_CLASSDESTROY}

{$IFDEF HOOK_CLASSDESTROY}
initialization
  InitHooks;
{$ENDIF HOOK_CLASSDESTROY}

end.
