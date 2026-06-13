# [สคริปต์รองรับ Carousel แบบจัดเต็ม]
$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","
$sheetUrl = $env:GOOGLE_SHEET_API_URL 

$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)

$tasks = ConvertFrom-Csv -InputObject (Invoke-RestMethod -Uri $sheetUrl -Method Get)

$carouselColumns = @()

foreach ($task in $tasks) {
    # เช็คเวลา หน้า-หลัง 5 นาที
    $rawSendAt = if ($task.sendAt) { $task.sendAt } else { $task.'วันที่และเวลา' }
    $taskTime = [DateTime]::ParseExact(($rawSendAt -split "@")[1].Trim().Replace(".", ":"), "HH:mm", $null)
    
    if ([Math]::Abs(($taiTime - $taskTime).TotalMinutes) -le 5) {
        if ($task.'ประเภทข้อความ' -eq "carousel") {
            $carouselColumns += @{
                thumbnailImageUrl = $task.'ลิงก์รูปภาพ'
                title = $task.'หัวข้อ (Title)'
                text = $task.'รายละเอียด (Text)'
                actions = @(@{ type = "uri"; label = "ดูรายละเอียด"; uri = $task.'ลิงก์ URL' })
            }
        }
    }
}

if ($carouselColumns.Count -gt 0) {
    $body = @{
        to = $groupIds[0].Trim()
        messages = @(@{
            type = "template"
            altText = "รายการงานวันนี้"
            template = @{ type = "carousel"; columns = $carouselColumns }
        })
    } | ConvertTo-Json -Depth 10
    
    Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } -Body $body
}
