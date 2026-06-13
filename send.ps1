$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","

# 1. ดึงเวลาปัจจุบันในโซนเวลาประเทศไทย (GMT+7)
$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
$currentTimeStr = $taiTime.ToString("HH:mm") 

$currentCheckStr = "${currentDateStr}@${currentTimeStr}"
Write-Host "เวลาปัจจุบันของไทย: $currentCheckStr"

# 2. อ่านและแปลงไฟล์ตารางงาน JSON
$jsonContent = Get-Content -Path "./schedule_tasks.json" -Raw
$tasks = ConvertFrom-Json $jsonContent

$matchedMessages = $null

# ค้นหางานที่ตรงกับวันและเวลาปัจจุบัน
foreach ($task in $tasks) {
    if ($task.sendAt -eq $currentCheckStr) {
        $matchedMessages = $task.messages
        break
    }
}

# 3. ถ้าเจอคิวงานที่ตรงเป๊ะ ให้ส่งข้อมูลทั้งหมดเข้ากลุ่ม LINE
if ($matchedMessages) {
    Write-Host "เจอคิวงานตรงกัน! กำลังจัดส่ง..."

    foreach ($id in $groupIds) {
        $id = $id.Trim()
        if (-not [string]::IsNullOrEmpty($id)) {
            
            # โครงสร้างส่งหา LINE API
            $bodyObj = @{
                to = $id
                messages = $matchedMessages
            }
            
            # แปลงเป็น JSON string แบบรองรับอักขระพิเศษภาษาไทย
            $bodyJson = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::Default.GetBytes((ConvertTo-Json $bodyObj -Depth 20 -Compress)))

            Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" `
                              -Method Post `
                              -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } `
                              -Body $bodyJson
                              
            Write-Host "ส่งข้อความคอมโบไปกลุ่ม $id สำเร็จแล้ว"
        }
    }
} else {
    Write-Host "รอบนี้ไม่มีคิวงานที่ตรงกับเวลานี้"
}
