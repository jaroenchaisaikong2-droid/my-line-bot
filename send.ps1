# บรรทัดนี้สำคัญที่สุดสำหรับภาษาไทย
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$token = $env:LINE_TOKEN
$groupId = $env:LINE_GROUP_ID  # แก้ให้เป็น LINE_GROUP_ID ตรงกับที่ตั้งใน Secret
$msg = $env:MESSAGE_TEXT

# เพิ่มบรรทัดเช็คค่า เพื่อให้รู้ว่าตัวไหนที่มันหาไม่เจอ
if ([string]::IsNullOrEmpty($token)) { Write-Error "LINE_TOKEN หายไป!" }
if ([string]::IsNullOrEmpty($groupId)) { Write-Error "LINE_GROUP_ID หายไป!" }

$body = @{
    to = $groupId
    messages = @(@{ type = "text"; text = $msg })
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } -Body $body
