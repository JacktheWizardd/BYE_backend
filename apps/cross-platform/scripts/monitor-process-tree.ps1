param([int]$ControllerId, [string]$OutputFile, [string]$ReadyFile, [string]$StopFile)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public class ElectronProcessTree {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct Entry {
    public uint size, usage, id; public UIntPtr heap; public uint module, threads, parent;
    public int priority; public uint flags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string name;
  }
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint id);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool Process32FirstW(IntPtr snapshot, ref Entry entry);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool Process32NextW(IntPtr snapshot, ref Entry entry);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  public static Entry[] Read() {
    var snapshot=CreateToolhelp32Snapshot(2, 0);
    if(snapshot==new IntPtr(-1)) throw new System.ComponentModel.Win32Exception();
    try {
      var entries=new List<Entry>(); var entry=new Entry(); entry.size=(uint)Marshal.SizeOf(typeof(Entry));
      if(!Process32FirstW(snapshot, ref entry)) throw new System.ComponentModel.Win32Exception();
      do { entries.Add(entry); } while(Process32NextW(snapshot, ref entry));
      return entries.ToArray();
    } finally { CloseHandle(snapshot); }
  }
}
'@
$samples = [System.Collections.Generic.List[object]]::new()
$seen = @{}
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$peakRss = 0L; $peakPrivate = 0L
[IO.File]::WriteAllText($ReadyFile, 'ready')
while (-not (Test-Path -LiteralPath $StopFile)) {
  if (-not (Get-Process -Id $ControllerId -ErrorAction SilentlyContinue)) { break }
  $entries = [ElectronProcessTree]::Read()
  # Only Electron roots belonging to this controller, plus every descendant.
  # Controller, PowerShell monitor and unrelated Electron apps are excluded.
  $family = @($ControllerId); $ancestors = @($ControllerId)
  while ($ancestors.Count -gt 0) {
    $nextAncestors = @()
    foreach ($ancestor in $ancestors) {
      foreach ($child in $entries | Where-Object { $_.parent -eq $ancestor -and $_.id -ne $PID }) {
        if ($family -notcontains [int]$child.id) { $family += [int]$child.id; $nextAncestors += [int]$child.id }
      }
    }
    $ancestors = $nextAncestors
  }
  $pending = @($entries | Where-Object { $family -contains [int]$_.id -and $_.name -eq 'electron.exe' } | ForEach-Object { [int]$_.id })
  $tracked = @($pending)
  while ($pending.Count -gt 0) {
    $next = @()
    foreach ($parentId in $pending) {
      foreach ($child in $entries | Where-Object parent -eq $parentId) {
        if ($tracked -notcontains [int]$child.id) { $tracked += [int]$child.id; $next += [int]$child.id }
      }
    }
    $pending = $next
  }
  $rss = 0L; $privateBytes = 0L
  foreach ($processId in $tracked) {
    $item = $entries | Where-Object id -eq $processId
    $seen[[string]$processId] = @{ name = $item.name; parent = $item.parent }
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($process) { $rss += $process.WorkingSet64; $privateBytes += $process.PrivateMemorySize64 }
  }
  if ($tracked.Count -gt 0) {
    $peakRss = [Math]::Max($peakRss, $rss); $peakPrivate = [Math]::Max($peakPrivate, $privateBytes)
    $samples.Add(@{ elapsedMs = $timer.ElapsedMilliseconds; rssBytes = $rss; privateBytes = $privateBytes; processIds = $tracked })
  }
  Start-Sleep -Milliseconds 100
}
@{ peakRssBytes = $peakRss; peakPrivateBytes = $peakPrivate; processes = $seen; samples = $samples; sampling = 'Toolhelp32 enumeration + Get-Process every 100 ms plus collection overhead; controller and monitor excluded' } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputFile -Encoding utf8
