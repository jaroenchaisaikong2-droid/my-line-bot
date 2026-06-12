$token = $env:LINE_TOKEN
$groupId = $env:LINE_GROUP_ID
$msg = "Daily Report: Link is ready at https://www.google.com"

$body = @{
    to = $groupId
    messages = @(@{ type = "text"; text = $msg })
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } -Body $body
