Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class SW2 {
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
 public delegate bool EnumProc(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
 [StructLayout(LayoutKind.Sequential)] public struct R { public int L,T,Rt,B; }
 public static List<string> Hits = new List<string>();
 public static bool Test(IntPtr h, IntPtr l) {
   R r;
   if (!GetWindowRect(h, out r)) return true;
   // intersect com a regiao da faixa (screen): x 1515..1545, y 200..670
   if (r.L < 1545 && r.Rt > 1515 && r.T < 670 && r.B > 200) {
     StringBuilder sb = new StringBuilder(256);
     GetClassName(h, sb, 256);
     uint pid; GetWindowThreadProcessId(h, out pid);
     IntPtr par = GetParent(h);
     Hits.Add(string.Format("h=0x{0:X} pid={1} cls={2} rect={3},{4} {5}x{6} vis={7} parent=0x{8:X}",
        h.ToInt64(), pid, sb, r.L, r.T, r.Rt-r.L, r.B-r.T, IsWindowVisible(h), par.ToInt64()));
   }
   return true;
 }
}
"@
[SW2]::Hits.Clear()
[void][SW2]::EnumWindows([SW2+EnumProc]{ param($h,$l) [void][SW2]::Test($h,$l); return $true }, [IntPtr]::Zero)
Write-Output ('--- top-level intersectando (1515..1545,200..670): ' + [SW2]::Hits.Count + ' ---')
[SW2]::Hits | ForEach-Object { Write-Output $_ }
[SW2]::Hits.Clear()
[void][SW2]::EnumChildWindows([IntPtr]::Zero, [SW2+EnumProc]{ param($h,$l) [void][SW2]::Test($h,$l); return $true }, [IntPtr]::Zero)
Write-Output ('--- TODOS filhos (recursivo global) intersectando: ' + [SW2]::Hits.Count + ' ---')
[SW2]::Hits | ForEach-Object { Write-Output $_ }
