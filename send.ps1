# บังคับให้ PowerShell อ่านและเขียนเป็น UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$token = $env:LINE_TOKEN
$groupId = $env:LINE_GROUP_ID
# ตอนนี้คุณสามารถใส่ภาษาไทยได้แล้ว
$msg = "รายงานประจำวัน: ลิงก์งานวันนี้พร้อมแล้วครับ https://www.google.com"

$body = @{
    to = $groupId
    messages = @(@{ type = "text"; text = $msg })
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } -Body $body
