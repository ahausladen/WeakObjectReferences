WeakObjectReferences
====================

A Delphi Unit that implements weak references for objects. It is compatible with Delphi 2009-XE4
Win32/Win64.

The unit should be placed in the Project's uses list directly after any Memory Manager unit because
it hooks some TObject/TMonitor RTL functions. Adding the unit to a DLLs/BPLs can cause problems
because the hooking can't be undone, objects are still be alive. So unloading the DLL/BPL is a no-go.

Usage
-----
```delphi
var
  MyWeakRef, YourWeakRef, HisWeakRef: TWeakReference<TObject>;
  IntfWeakRef: IWeakReference<TObject>;
  MyObject: TObject;
begin
  MyObject := TObject.Create;
  try
    MyWeakRef := MyObject; // implicitly create wrapped weak reference
    YourWeakRef := TWeakReference<TObject>.Create(MyObject); // explicity create wrapped weak reference
    HisWeakRef := YourWeakRef; // copy wrapped weak reference
    IntfWeakRef := TWeakReference<TObject>.New(MyObject); // create weak reference

    Assert(MyWeakRef = YourWeakRef);
    Assert(MyWeakRef.Target <> nil);
    Assert(MyWeakRef = MyObject);
    Assert(MyWeakRef.IsAlive);
    Assert(IntfWeakRef.Target <> nil);
  finally
    MyObject.Free;
  end;
  Assert(MyWeakRef.Target = nil);
  Assert(MyWeakRef = nil);
  Assert(not MyWeakRef.IsAlive);
  Assert(YourWeakRef.Target = nil);
  Assert(HisWeakRef.Target = nil);
  Assert(IntfWeakRef.Target = nil);
end;
```


How it works
------------

The first time a WeakReference is created, a 32-36 bytes large record is allocated for the object and stored
into the TObject.Monitor field. This record implements the IWeakReference<T> interface with a RefCount and a
pointer to the referenced object. All WeakReferences for one object point to this record. The record stays
alive until the last IWeakReference<T> is released. The object itself holds one reference to the IWeakReference<T>
interface and when the object is destroyed it sets the object reference in the record to nil, nil-ing out
every IWeakReference<T> for this object and the object's reference to the record is released, what let the
IWeakReference<T>._Release method clean up after the last IWeakReference<T> interface gets out of scope.


Additional data storage
-----------------------

It is possible add additional data to an object through the ``TInternalWeakReferenceHelper.RegisterAdditionalData``
method and then query it by using ``TInternalWeakReferenceHelper.GetAdditionalData``. This can be used to implement
an alternative TMonitor construct.


What happens to the TObject.Monitor field
-----------------------------------------

The original hidden TObject.Monitor field is moved into the IWeakReference<T> record and all calls from the
TMonitor to get the value of the field are redirected to the record's Monitor field.


License
-------
The project is subject to the Mozilla Public License Version 1.1 (the "License");  
you may not use this project except in compliance with the License. You may obtain a copy of the
License at <http://www.mozilla.org/MPL/>

Software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTY OF
ANY KIND, either express or implied. See the License for the specific language governing rights
and limitations under the License.

The Initial Developer of the Original Code is Andreas Hausladen.  
Portions created by Andreas Hausladen are Copyright (C) 2013 Andreas Hausladen.  
All Rights Reserved.
