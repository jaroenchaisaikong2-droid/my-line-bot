# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชันแยกกลุ่ม Carousel อิสระด้วย Param5)
# ========================================================================

$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","
$sheetUrl = $env:GOOGLE_SHEET_API_URL 

$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)

$csvRaw = Invoke-RestMethod -Uri $sheetUrl -Method Get -TimeoutSec 15
$tasks = ConvertFrom-Csv -InputObject $csvRaw | Where-Object { $_.SendAt -or $_.'วันที่และเวลา' }

$textMessages = @{} 
$carouselGroups = @{} # [เปลี่ยนใหม่] เก็บ Carousel แยกเป็นกลุ่มๆ
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
            
            # [ของใหม่] ตัวแปรกลุ่ม ถ้าไม่ได้กรอก จะเหมาว่าเป็น "DefaultGroup"
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
                if ($p3 -match "^https?://") { $col["thumbnailImageUrl"] = $p3 }
                
                # [ของใหม่] นำเวลาและชื่อกลุ่มมาต่อกันเป็นกุญแจ (เช่น "14:00_ชุดที่1") เพื่อแยกหมวดหมู่
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

# 1. นำข้อความ Text เข้าคิว
foreach ($key in $textMessages.Keys) { $finalMessages += @{ type = "text"; text = $textMessages[$key] } }

# 2. นำสติกเกอร์เข้าคิว
$finalMessages += $otherMessages

# 3. [ของใหม่] นำ Carousel แต่ละกลุ่มเข้าคิว
foreach ($gKey in $carouselGroups.Keys) {
    $cols = $carouselGroups[$gKey]
    # LINE จำกัด 1 กลุ่มมีได้ไม่เกิน 10 การ์ด
    if ($cols.Count -gt 10) { $cols = $cols[0..9] } 
    
    $finalMessages += @{ type = "template"; altText = "คุณได้รับข้อความแบบการ์ด"; template = @{ type = "carousel"; columns = $cols } }
}

# [ข้อควรระวัง] LINE API อนุญาตให้ส่งข้อความ (บอลลูน) ได้สูงสุด 5 ก้อนต่อ 1 การรัน
if ($finalMessages.Count -gt 5) {
    Write-Warning "มีข้อความเกิน 5 ก้อน ระบบจะส่งแค่ 5 ก้อนแรกตามข้อจำกัดของ LINE API"
    $finalMessages = $finalMessages[0..4]
}

if ($finalMessages.Count -gt 0) {
    foreach ($id in $groupIds) {
        $body = @{ to = $id.Trim(); messages = $finalMessages } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } -Body $body
    }
}
