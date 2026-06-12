$token = $env:LINE_TOKEN
$groupId = $env:LINE_GROUP_ID

# อ่านข้อความจากไฟล์ message.txt ตรงๆ เลย
$msg = (Get-Content -Path "./message.txt").Trim()

$body = @{
    to = $groupId
    messages = @(@{ type = "text"; text = $msg })
} | ConvertTo-Json -Compress

Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" `
                  -Method Post `
                  -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json; charset=utf-8" } `
                  -Body $body
