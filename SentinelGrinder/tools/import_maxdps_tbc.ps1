param(
    [string]$OutputPath = "c:\Users\Bastien\Desktop\SentinelCore\GrindBuddy\modules\RotationProfileCatalog.lua"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipMap = @{
    "DRUID"   = "c:\Users\Bastien\Downloads\MaxDps-Druid-master.zip"
    "HUNTER"  = "c:\Users\Bastien\Downloads\MaxDps-Hunter-master.zip"
    "PRIEST"  = "c:\Users\Bastien\Downloads\MaxDps-Priest-master.zip"
    "ROGUE"   = "c:\Users\Bastien\Downloads\MaxDps-Rogue-master.zip"
    "SHAMAN"  = "c:\Users\Bastien\Downloads\MaxDps-Shaman-master.zip"
    "WARLOCK" = "c:\Users\Bastien\Downloads\MaxDps-Warlock-master.zip"
    "WARRIOR" = "c:\Users\Bastien\Downloads\MaxDps-Warrior-master.zip"
    "PALADIN" = "c:\Users\Bastien\Downloads\MaxDps-Paladin-master.zip"
    "MAGE"    = "c:\Users\Bastien\Downloads\MaxDps-Mage-master.zip"
}

function Get-UniqueOrdered {
    param([object[]]$Items)

    $seen = @{}
    $out = @()
    foreach ($x in $Items) {
        if ($null -eq $x) {
            continue
        }
        $k = [string]$x
        if (-not $seen.ContainsKey($k)) {
            $seen[$k] = $true
            $out += $x
        }
    }
    return $out
}

$profiles = @()

foreach ($classKey in $zipMap.Keys) {
    $zipPath = $zipMap[$classKey]
    if (-not (Test-Path $zipPath)) {
        Write-Warning "Missing zip: $zipPath"
        continue
    }

    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entries = $archive.Entries |
            Where-Object { $_.FullName -match "Specialization/TBC/[^/]+\.lua$" } |
            Sort-Object FullName

        foreach ($entry in $entries) {
            $stream = $entry.Open()
            $reader = New-Object System.IO.StreamReader($stream)
            $text = $reader.ReadToEnd()
            $reader.Dispose()
            $stream.Dispose()

            $spec = [System.IO.Path]::GetFileNameWithoutExtension($entry.FullName)

            $spellMap = @{}
            foreach ($m in [regex]::Matches($text, "classtable\.(\w+)\s*=\s*(\d+)")) {
                $spellMap[$m.Groups[1].Value] = [int]$m.Groups[2].Value
            }

            $priorityNames = @()
            $checkSpellNames = @()
            $selfBuffNames = @()
            $targetDebuffNames = @()
            $executeRules = @()

            $lines = $text -split "\r?\n"
            foreach ($ln in $lines) {
                $trim = $ln.Trim()
                if ($trim.StartsWith("--")) {
                    continue
                }

                $mSet = [regex]::Match($trim, "setSpell\s*=\s*classtable\.(\w+)")
                if ($mSet.Success) {
                    $priorityNames += $mSet.Groups[1].Value
                }

                $mCheck = [regex]::Match($trim, "CheckSpellUsable\(classtable\.(\w+)")
                if ($mCheck.Success) {
                    $checkSpellNames += $mCheck.Groups[1].Value
                }

                $mBuff = [regex]::Match($trim, "FindBuffAuraData\(classtable\.(\w+)\)\.refreshable")
                if ($mBuff.Success) {
                    $selfBuffNames += $mBuff.Groups[1].Value
                }

                $mDebuff = [regex]::Match($trim, "FindADAuraData\(classtable\.(\w+)\)\.refreshable")
                if ($mDebuff.Success) {
                    $targetDebuffNames += $mDebuff.Groups[1].Value
                }

                $mExec = [regex]::Match($trim, "CheckSpellUsable\(classtable\.(\w+).+targethealthPerc\s*<\s*(\d+)")
                if ($mExec.Success) {
                    $executeRules += [pscustomobject]@{
                        name = $mExec.Groups[1].Value
                        hp = [int]$mExec.Groups[2].Value
                    }
                }
            }

            $priorityIds = @()
            foreach ($n in (Get-UniqueOrdered -Items $priorityNames)) {
                if ($spellMap.ContainsKey($n)) {
                    $priorityIds += $spellMap[$n]
                }
            }

            if ($priorityIds.Count -eq 0) {
                foreach ($n in (Get-UniqueOrdered -Items $checkSpellNames)) {
                    if ($spellMap.ContainsKey($n)) {
                        $priorityIds += $spellMap[$n]
                    }
                }
            }

            if ($priorityIds.Count -eq 0) {
                continue
            }

            $selfBuffIds = @()
            foreach ($n in (Get-UniqueOrdered -Items $selfBuffNames)) {
                if ($spellMap.ContainsKey($n)) {
                    $selfBuffIds += $spellMap[$n]
                }
            }

            $targetDebuffIds = @()
            foreach ($n in (Get-UniqueOrdered -Items $targetDebuffNames)) {
                if ($spellMap.ContainsKey($n)) {
                    $targetDebuffIds += $spellMap[$n]
                }
            }

            $execPairs = @()
            $seenExec = @{}
            foreach ($r in $executeRules) {
                if (-not $spellMap.ContainsKey($r.name)) {
                    continue
                }
                $sid = $spellMap[$r.name]
                $k = "$sid|$($r.hp)"
                if ($seenExec.ContainsKey($k)) {
                    continue
                }
                $seenExec[$k] = $true
                $execPairs += [pscustomobject]@{
                    spell_id = $sid
                    target_hp_lte = $r.hp
                }
            }

            $profileId = ("{0}_{1}_tbc_maxdps" -f $classKey.ToLower(), $spec.ToLower())
            $profiles += [pscustomobject]@{
                id = $profileId
                class_key = $classKey
                spec = $spec
                source = "MaxDps TBC"
                priority = $priorityIds
                self_buffs = $selfBuffIds
                target_debuffs = $targetDebuffIds
                execute = $execPairs
            }
        }
    } finally {
        $archive.Dispose()
    }
}

$profiles = $profiles | Sort-Object class_key, spec

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("local Catalog = {}")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Catalog.profiles = {")

foreach ($p in $profiles) {
    [void]$sb.AppendLine("    {")
    [void]$sb.AppendLine(('        id = "{0}",' -f $p.id))
    [void]$sb.AppendLine(('        class_key = "{0}",' -f $p.class_key))
    [void]$sb.AppendLine(('        spec = "{0}",' -f $p.spec))
    [void]$sb.AppendLine(('        source = "{0}",' -f $p.source))

    $prio = ($p.priority | ForEach-Object { $_.ToString() }) -join ", "
    [void]$sb.AppendLine(("        priority = {{ {0} }}," -f $prio))

    $buffs = ($p.self_buffs | ForEach-Object { $_.ToString() }) -join ", "
    [void]$sb.AppendLine(("        self_buffs = {{ {0} }}," -f $buffs))

    $debuffs = ($p.target_debuffs | ForEach-Object { $_.ToString() }) -join ", "
    [void]$sb.AppendLine(("        target_debuffs = {{ {0} }}," -f $debuffs))

    [void]$sb.AppendLine("        execute = {")
    foreach ($e in $p.execute) {
        [void]$sb.AppendLine(("            {{ spell_id = {0}, target_hp_lte = {1} }}," -f $e.spell_id, $e.target_hp_lte))
    }
    [void]$sb.AppendLine("        },")
    [void]$sb.AppendLine("    },")
}

[void]$sb.AppendLine("}")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("function Catalog.get_all()")
[void]$sb.AppendLine("    return Catalog.profiles")
[void]$sb.AppendLine("end")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("return Catalog")

[System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("Generated: {0} ({1} profiles)" -f $OutputPath, $profiles.Count)
