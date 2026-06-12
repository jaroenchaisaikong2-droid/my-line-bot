$token = $env:LINE_TOKEN
$groupId = $env:LINE_GROUP_ID_TEST
$body = @{
    to = $groupId
    messages = @(@{ type = "text"; text = "สวัสดีครับ! นี่คือลิงก์งานวันนี้ https://www.google.com" })
} | ConvertTo-Json
Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } -Body $body
