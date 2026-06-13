# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชันรวมร่างอัจฉริยะ)
# ========================================================================

$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","
$sheetUrl = $env:GOOGLE_SHEET_API_URL 

$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)

$csvRaw = Invoke-RestMethod -Uri $sheetUrl -Method Get -TimeoutSec 15
$tasks = ConvertFrom-Csv -InputObject $csvRaw

$textMessages = @{} # เก็บข้อความรวมร่าง
$carouselColumns = @() # เก็บการ์ด Carousel
$otherMessages = @() # เก็บสติกเกอร์และอื่นๆ

foreach ($task in $tasks) {
    $rawSendAt = if ($task.SendAt) { $task.SendAt } else { $task.'วันที่และเวลา' }
    if ([string]::IsNullOrEmpty($rawSendAt)) { continue }

    $timeParts = $rawSendAt -split "@"
    $taskTime = [DateTime]::ParseExact($timeParts[1].Trim().Replace(".", ":"), "HH:mm", $null)
    $currentHourMin = [DateTime]::ParseExact($taiTime.ToString("HH:mm"), "HH:mm", $null)
    
    # เช็คเวลา หน้า-หลัง 5 นาที
    if ([Math]::Abs(($currentHourMin - $taskTime).TotalMinutes) -le 5) {
        
        $type = if ($task.Type) { $task.Type } else { $task.'ประเภทข้อความ' }
        $p1 = if ($task.Param1) { $task.Param1 } else { $task.'ข้อความ / ลิงก์รูปภาพ' }
        $p2 = if ($task.Param2) { $task.Param2 } else { $task.'รหัสสติกเกอร์ / พิกัด' }
        $p3 = if ($task.Param3) { $task.Param3 } else { $task.'ลิงก์รูปภาพ' }
        $p4 = if ($task.Param4) { $task.Param4 } else { $task.'ลิงก์ URL' }

        if ($type -eq "text") {
            if ($textMessages.ContainsKey($rawSendAt)) { $textMessages[$rawSendAt] += "`n" + $p1 }
            else { $textMessages[$rawSendAt] = $p1 }
        }
        elseif ($type -eq "sticker") {
            $otherMessages += @{ type = "sticker"; packageId = $p1; stickerId = $p2 }
        }
        elseif ($type -eq "carousel") {
            $carouselColumns += @{
                thumbnailImageUrl = $p3
                title = $p1
                text = $p2
                actions = @(@{ type = "uri"; label = "ดูรายละเอียด"; uri = $p4 })
            }
        }
    }
}

# จัดเตรียมรายการข้อความที่จะส่ง
$finalMessages = @()
foreach ($key in $textMessages.Keys) { $finalMessages += @{ type = "text"; text = $textMessages[$key] } }
$finalMessages += $otherMessages

if ($carouselColumns.Count -gt 0) {
    $finalMessages += @{
        type = "template"
        altText = "รายการวันนี้"
        template = @{ type = "carousel"; columns = $carouselColumns }
    }
}

# ส่งเข้า Line
if ($finalMessages.Count -gt 0) {
    foreach ($id in $groupIds) {
        $body = @{ to = $id.Trim(); messages = $finalMessages } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } -Body $body
    }
}
