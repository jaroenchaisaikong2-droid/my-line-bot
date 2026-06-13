# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชันรองรับข้อความยาวแบบคงรูปแบบเป๊ะๆ)
# ========================================================================

$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","
$sheetUrl = $env:GOOGLE_SHEET_API_URL 

$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)

$csvRaw = Invoke-RestMethod -Uri $sheetUrl -Method Get -TimeoutSec 15
$tasks = ConvertFrom-Csv -InputObject $csvRaw

$allMessages = @()

foreach ($task in $tasks) {
    $rawSendAt = if ($task.sendAt) { $task.sendAt } else { $task.'วันที่และเวลา' }
    if ([string]::IsNullOrEmpty($rawSendAt)) { continue }

    $timeParts = $rawSendAt -split "@"
    $taskTime = [DateTime]::ParseExact($timeParts[1].Trim().Replace(".", ":"), "HH:mm", $null)
    $currentHourMin = [DateTime]::ParseExact($taiTime.ToString("HH:mm"), "HH:mm", $null)
    
    # เงื่อนไขหน้า-หลัง 5 นาที
    if ([Math]::Abs(($currentHourMin - $taskTime).TotalMinutes) -le 5) {
        
        $type = if ($task.type) { $task.type } else { $task.'ประเภทข้อความ' }
        $param1 = if ($task.param1) { $task.param1 } else { $task.'ข้อความ / ลิงก์รูปภาพ' }

        if ($type -eq "text") {
            # [ทีเด็ด] แปลงการกด Enter ใน Google Sheets ให้เป็นบรรทัดใหม่ที่ LINE เข้าใจ
            $formattedText = $param1 -replace "`r`n", "`n"
            $allMessages += @{ type = "text"; text = $formattedText }
        }
        elseif ($type -eq "image") {
            $allMessages += @{ type = "image"; originalContentUrl = $param1; previewImageUrl = $param1 }
        }
    }
}

# ส่งข้อความทั้งหมดในรวดเดียว
if ($allMessages.Count -gt 0) {
    foreach ($id in $groupIds) {
        $body = @{ to = $id.Trim(); messages = $allMessages } | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } -Body $body
    }
}
