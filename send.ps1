# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชันป้องกันลิงก์รูปภาพพัง)
# ========================================================================

$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","
$sheetUrl = $env:GOOGLE_SHEET_API_URL 

$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)

$csvRaw = Invoke-RestMethod -Uri $sheetUrl -Method Get -TimeoutSec 15
$tasks = ConvertFrom-Csv -InputObject $csvRaw | Where-Object { $_.SendAt -or $_.'วันที่และเวลา' }

$textMessages = @{} 
$carouselColumns = @() 
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

            if ($type -eq "text") {
                if ($textMessages.ContainsKey($rawSendAt)) { $textMessages[$rawSendAt] += "`n" + $p1 }
                else { $textMessages[$rawSendAt] = $p1 }
            }
            elseif ($type -eq "sticker") {
                $otherMessages += @{ type = "sticker"; packageId = $p1; stickerId = $p2 }
            }
            elseif ($type -eq "carousel") {
                # สร้างการ์ดพื้นฐาน
                $col = @{
                    title = if ([string]::IsNullOrWhiteSpace($p1)) { "-" } else { $p1 }
                    text = if ([string]::IsNullOrWhiteSpace($p2)) { "-" } else { $p2 }
                    # ตรวจสอบลิงก์ปุ่มกด ถ้าไม่มีหรือผิดรูปแบบ ให้ไปที่ line.me แทนกันพัง
                    actions = @(@{ type = "uri"; label = "ดูรายละเอียด"; uri = if ($p4 -match "^https?://") { $p4 } else { "https://line.me" } })
                }
                
                # [จุดสำคัญ] ตรวจสอบรูปภาพ ถ้าเป็นลิงก์จริงๆ ค่อยใส่ ถ้าไม่ใช่ให้ปล่อยว่างไว้
                if ($p3 -match "^https?://") {
                    $col["thumbnailImageUrl"] = $p3
                }
                
                $carouselColumns += $col
            }
        }
    } catch {
        Write-Host "ข้ามแถวที่ข้อมูลไม่สมบูรณ์"
    }
}

$finalMessages = @()
foreach ($key in $textMessages.Keys) { $finalMessages += @{ type = "text"; text = $textMessages[$key] } }
$finalMessages += $otherMessages

if ($carouselColumns.Count -gt 0) {
    # ข้อควรระวังของ LINE API: Carousel ส่งได้สูงสุด 10 การ์ดต่อ 1 ชุดข้อความ
    if ($carouselColumns.Count -gt 10) {
        $carouselColumns = $carouselColumns[0..9]
    }
    
    $finalMessages += @{ type = "template"; altText = "รายการวันนี้"; template = @{ type = "carousel"; columns = $carouselColumns } }
}

if ($finalMessages.Count -gt 0) {
    foreach ($id in $groupIds) {
        $body = @{ to = $id.Trim(); messages = $finalMessages } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } -Body $body
    }
}
