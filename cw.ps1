param([int]$X, [int]$Y)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class M {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, int e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
}
'@
[M]::SetProcessDPIAware() | Out-Null
$h = (Get-Process local_dict).MainWindowHandle
[M]::SetWindowPos($h, [IntPtr]::new(-1), 40, 40, 1600, 900, 0x0040) | Out-Null
[M]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 300
[M]::SetWindowPos($h, [IntPtr]::new(-2), 40, 40, 1600, 900, 0x0040) | Out-Null
Start-Sleep -Milliseconds 400
if ($X -ge 0) {
  [M]::SetCursorPos($X, $Y) | Out-Null
  Start-Sleep -Milliseconds 150
  [M]::mouse_event(2,0,0,0,0)
  [M]::mouse_event(4,0,0,0,0)
  Start-Sleep -Milliseconds 500
}
"ok"
