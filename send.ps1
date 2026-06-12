$token = $env:LINE_TOKEN
$groupId = $env:LINE_GROUP_ID
# การใช้ [System.Text.Encoding]::UTF8.GetString ช่วยแก้ปัญหาตัวแปรจาก Secret ได้ครับ
$msg = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::Default.GetBytes($env:MESSAGE_TEXT))

$body = @{
    to = $groupId
    messages = @(@{ type = "text"; text = $msg })
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } -Body $body
