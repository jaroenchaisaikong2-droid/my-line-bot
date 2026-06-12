$token = $env:LINE_TOKEN
$groupId = $env:LINE_GROUP_ID

# สั่งให้ PowerShell ไปอ่านข้อความจากไฟล์ .txt โดยบังคับเป็น UTF-8
$msg = Get-Content -Path "./message.txt" -Encoding UTF8

$body = @{
    to = $groupId
    messages = @(@{ type = "text"; text = $msg })
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } -Body $body
