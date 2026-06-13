# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชันดึงหน้าปก YouTube อัตโนมัติ)
# ========================================================================

$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","
$sheetUrl = $env:GOOGLE_SHEET_API_URL 

$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)

$csvRaw = Invoke-RestMethod -Uri $sheetUrl -Method Get -TimeoutSec 15
$tasks = ConvertFrom-Csv -InputObject $csvRaw | Where-Object { $_.SendAt -or $_.'วันที่และเวลา' }

$textMessages = @{} 
$carouselGroups = @{} 
$otherMessages = @() 

foreach ($task in $tasks) {
    $rawSendAt = if ($task.SendAt) { $task.SendAt } else { $task.'วันที่และเวลา' }
    if ([string]::IsNullOrWhiteSpace($rawSendAt)) { continue }

    try {
        $timeParts = $rawSendAt -split "@"
        if ($timeParts.Count -lt 2) { continue } 

        $taskTime = [DateTime]::ParseExact($timeParts[1].Trim().Replace(".", ":"), "HH:mm", $null)
        $currentHourMin = [DateTime]::ParseExact($taiTime.ToString("HH:mm"), "HH:mm", $null)
        
        if ([Math]::Abs(($currentHourMin - $taskTime).TotalMinutes) -le 5) {
            
            $type = if ($task.Type) { $task.Type } else { $task.'ประเภทข้อความ' }
            $p1 = if ($task.Param1) { $task.Param1 } else { $task.'ข้อความ / ลิงก์รูปภาพ' }
            $p2 = if ($task.Param2) { $task.Param2 } else { $task.'รหัสสติกเกอร์ / พิกัด' }
            $p3 = if ($task.Param3) { $task.Param3 } else { $task.'ลิงก์รูปภาพ' }
            $p4 = if ($task.Param4) { $task.Param4 } else { $task.'ลิงก์ URL' }
            $p5 = if ($task.Param5) { $task.Param5 } else { "DefaultGroup" }

            if ($type -eq "text") {
                if ($textMessages.ContainsKey($rawSendAt)) { $textMessages[$rawSendAt] += "`n" + $p1 }
                else { $textMessages[$rawSendAt] = $p1 }
            }
            elseif ($type -eq "sticker") {
                $otherMessages += @{ type = "sticker"; packageId = $p1; stickerId = $p2 }
            }
            elseif ($type -eq "carousel") {
                $col = @{
                    title = if ([string]::IsNullOrWhiteSpace($p1)) { "-" } else { $p1 }
                    text = if ([string]::IsNullOrWhiteSpace($p2)) { "-" } else { $p2 }
                    actions = @(@{ type = "uri"; label = "ดูรายละเอียด"; uri = if ($p4 -match "^https?://") { $p4 } else { "https://line.me" } })
                }
                
                # --- [ระบบจัดการรูปภาพอัจฉริยะ] ---
                $finalThumbUrl = $null
                
                # 1. ถ้ามีรูปภาพตรงๆ อยู่ใน Param3 ให้ใช้รูปนั้นเป็นอันดับแรก
                if ($p3 -match "^https?://") {
                    $finalThumbUrl = $p3
                }
                # 2. ถ้าช่องรูปว่างเปล่า ให้ตรวจสอบว่า URL เป็น YouTube หรือไม่
                elseif ($p4 -match "youtu\.be/([^?]+)") {
                    $finalThumbUrl = "https://img.youtube.com/vi/$($matches[1])/hqdefault.jpg"
                }
                elseif ($p4 -match "youtube\.com/watch\?v=([^&]+)") {
                    $finalThumbUrl = "https://img.youtube.com/vi/$($matches[1])/hqdefault.jpg"
                }
                
                # ถ้าระบบได้ลิงก์รูปภาพมา (ไม่ว่าจาก Param3 หรือจากสูตร YouTube) ให้ยัดลงในการ์ด
                if ($null -ne $finalThumbUrl) {
                    $col["thumbnailImageUrl"] = $finalThumbUrl
                }
                # --------------------------------

                $groupKey = "${rawSendAt}_${p5}"
                
                if (-not $carouselGroups.ContainsKey($groupKey)) {
                    $carouselGroups[$groupKey] = @()
                }
                $carouselGroups[$groupKey] += $col
            }
        }
    } catch {
        Write-Host "ข้ามแถวที่ข้อมูลไม่สมบูรณ์"
    }
}

$finalMessages = @()

foreach ($key in $textMessages.Keys) { $finalMessages += @{ type = "text"; text = $textMessages[$key] } }
$finalMessages += $otherMessages

foreach ($gKey in $carouselGroups.Keys) {
    $cols = $carouselGroups[$gKey]
    if ($cols.Count -gt 10) { $cols = $cols[0..9] } 
    
    $groupName = ($gKey -split "_")[1]
    
    if ($groupName -ne "DefaultGroup") {
        $finalMessages += @{ type = "text"; text = "📌 $groupName" }
    }
    
    $finalMessages += @{ type = "template"; altText = "คุณได้รับคิวงานกลุ่ม $groupName"; template = @{ type = "carousel"; columns = $cols } }
}

if ($finalMessages.Count -gt 5) {
    Write-Warning "มีข้อความเกิน 5 ก้อน ระบบจะส่งแค่ 5 ก้อนแรก"
    $finalMessages = $finalMessages[0..4]
}

if ($finalMessages.Count -gt 0) {
    foreach ($id in $groupIds) {
        $body = @{ to = $id.Trim(); messages = $finalMessages } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } -Body $body
    }
}
