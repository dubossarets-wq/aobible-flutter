' Значок «AO Bible» на панели задач: открыть актуальную версию приложения.
' Окно уже открыто — вывести его вперёд; нет — запустить живой режим (tool/live.mjs) без чёрного окна консоли.
' Первая сборка — около минуты; дальше окно обновляется само при каждой правке кода. Журнал — tool/live.log.
Option Explicit
Dim sh, fso, root, wmi, procs
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))

Set wmi = GetObject("winmgmts:\\.\root\cimv2")
Set procs = wmi.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name = 'aobible.exe'")
If procs.Count > 0 Then
  sh.AppActivate "aobible"
  WScript.Quit
End If

' живой режим уже собирается (запущен, окно ещё не появилось) — второй не запускаем
Set procs = wmi.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name = 'node.exe' AND CommandLine LIKE '%live.mjs%'")
If procs.Count > 0 Then WScript.Quit

sh.CurrentDirectory = root
sh.Run "cmd /c """"C:\Program Files\nodejs\node.exe"" """ & root & "\tool\live.mjs"" > """ & root & "\tool\live.log"" 2>&1""", 0, False
