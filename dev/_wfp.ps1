Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class WF {
 [DllImport("user32.dll")]public static extern IntPtr WindowFromPoint(P p);
 [DllImport("user32.dll")]public static extern IntPtr GetAncestor(IntPtr h,uint f);
 [DllImport("user32.dll")]public static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern bool GetClientRect(IntPtr h,out R r);
 [DllImport("user32.dll")]public static extern IntPtr GetParent(IntPtr h);
 [StructLayout(LayoutKind.Sequential)]public struct P{public int X,Y;}
 [StructLayout(LayoutKind.Sequential)]public struct R{public int L,T,Rt,B;}
}
"@
# pontos na faixa branca (janela em 380,146; faixa client x1143..1160 y64..509 -> screen x1523..1540 y210..655)
$pts = @(@(1531,300), @(1531,400), @(1531,500), @(1550,400), @(1520,400))
foreach ($pt in $pts) {
    $p = New-Object WF+P; $p.X = $pt[0]; $p.Y = $pt[1]
    $h = [WF]::WindowFromPoint($p)
    if ($h -eq [IntPtr]::Zero) { Write-Output ("({0},{1}) -> nenhum" -f $pt[0], $pt[1]); continue }
    $sb = New-Object System.Text.StringBuilder 200
    [void][WF]::GetClassName($h,$sb,200)
    $r = New-Object WF+R; [void][WF]::GetWindowRect($h,[ref]$r)
    $top = [WF]::GetAncestor($h, 2)
    $sb2 = New-Object System.Text.StringBuilder 200
    [void][WF]::GetClassName($top,$sb2,200)
    $rt = New-Object WF+R; [void][WF]::GetWindowRect($top,[ref]$rt)
    $par = [WF]::GetParent($h)
    $sb3 = New-Object System.Text.StringBuilder 200
    if ($par -ne [IntPtr]::Zero) { [void][WF]::GetClassName($par,$sb3,200) }
    Write-Output ("({0},{1}) -> cls={2} rect={3},{4} {5}x{6} parent={7} top=0x{8:X}[{9}] rect={10},{11}" -f `
        $pt[0],$pt[1],$sb.ToString(),$r.L,$r.T,($r.Rt-$r.L),($r.B-$r.T),$sb3.ToString(),$top.ToInt64(),$sb2.ToString(),$rt.L,$rt.T)
}
