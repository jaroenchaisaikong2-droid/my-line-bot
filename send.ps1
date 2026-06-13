# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชัน Flex Message เปลี่ยนสีหัวข้อและปุ่มได้)
# ========================================================================

$token = $env:LINE_TOKEN
$groupIds = $env:LINE_GROUP_ID -split ","
$sheetUrl = $env:GOOGLE_SHEET_API_URL 

$taiTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([System.DateTime]::Now, "SE Asia Standard Time")
$currentDateStr = $taiTime.ToString("dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)

$csvRaw = Invoke-RestMethod -Uri $sheetUrl -Method Get -TimeoutSec 15
$tasks = ConvertFrom-Csv -InputObject $csvRaw | Where-Object { $_.SendAt -or $_.'วันที่และเวลา' }

$textMessages = @{} 
$carouselGroups = @{} 
$otherMessages = @() 

foreach ($task in $tasks) {
    $rawSendAt = if ($task.SendAt) { $task.SendAt } else { $task.'วันที่และเวลา' }
    if ([string]::IsNullOrWhiteSpace($rawSendAt)) { continue }

    try {
        $timeParts = $rawSendAt -split "@"
        if ($timeParts.Count -lt 2) { continue } 

        $taskTime = [DateTime]::ParseExact($timeParts[1].Trim().Replace(".", ":"), "HH:mm", $null)
        $currentHourMin = [DateTime]::ParseExact($taiTime.ToString("HH:mm"), "HH:mm", $null)
        
        if ([Math]::Abs(($currentHourMin - $taskTime).TotalMinutes) -le 5) {
            
            $type = if ($task.Type) { $task.Type } else { $task.'ประเภทข้อความ' }
            $p1 = if ($task.Param1) { $task.Param1 } else { $task.'ข้อความ / ลิงก์รูปภาพ' }
            $p2 = if ($task.Param2) { $task.Param2 } else { $task.'รหัสสติกเกอร์ / พิกัด' }
            $p3 = if ($task.Param3) { $task.Param3 } else { $task.'ลิงก์รูปภาพ' }
            $p4 = if ($task.Param4) { $task.Param4 } else { $task.'ลิงก์ URL' }
            $p5 = if ($task.Param5) { $task.Param5 } else { "DefaultGroup" }

            if ($type -eq "text") {
                if ($textMessages.ContainsKey($rawSendAt)) { $textMessages[$rawSendAt] += "`n" + $p1 }
                else { $textMessages[$rawSendAt] = $p1 }
            }
            elseif ($type -eq "sticker") {
                $otherMessages += @{ type = "sticker"; packageId = $p1; stickerId = $p2 }
            }
            elseif ($type -eq "carousel") {
                
                $titleText = if ([string]::IsNullOrWhiteSpace($p1)) { "-" } else { $p1 }
                $descText = if ([string]::IsNullOrWhiteSpace($p2)) { "-" } else { $p2 }
                $uriLink = if ($p4 -match "^https?://") { $p4 } else { "https://line.me" }
                
                # --- [สร้างการ์ด Flex Message] ---
                $bubble = @{
                    type = "bubble"
                    body = @{
                        type = "box"
                        layout = "vertical"
                        contents = @(
                            @{
                                type = "text"
                                text = $titleText
                                weight = "bold"
                                size = "xl"
                                color = "#E53935" # 🎨 เปลี่ยนสีหัวข้อตรงนี้ (ปัจจุบัน: สีแดง)
                                wrap = $true
                            },
                            @{
                                type = "text"
                                text = $descText
                                size = "sm"
                                color = "#666666" # 🎨 สีรายละเอียด (ปัจจุบัน: สีเทา)
                                wrap = $true
                                margin = "md"
                            }
                        )
                    }
                    footer = @{
                        type = "box"
                        layout = "vertical"
                        spacing = "sm"
                        contents = @(
                            @{
                                type = "button"
                                style = "primary" # เปลี่ยนเป็น "link" ถ้าไม่อยากได้พื้นหลังสี
                                color = "#1E88E5" # 🎨 เปลี่ยนสีปุ่มตรงนี้ (ปัจจุบัน: สีน้ำเงิน)
                                action = @{
                                    type = "uri"
                                    label = "ดูรายละเอียด"
                                    uri = $uriLink
                                }
                            }
                        )
                    }
                }
                
                # --- ระบบดูดรูปภาพ ---
                $finalThumbUrl = $null
                
                if ($p3 -match "^https?://") { $finalThumbUrl = $p3 }
                elseif ($p4 -match "youtu\.be/([^?]+)|youtube\.com/watch\?v=([^&]+)") {
                    $videoId = if ($matches[1]) { $matches[1] } else { $matches[2] }
                    $finalThumbUrl = "https://img.youtube.com/vi/$videoId/hqdefault.jpg"
                }
                elseif ($p4 -match "heyzine\.com|fliphtml5\.com") {
                    try {
                        $htmlContent = Invoke-RestMethod -Uri $p4 -Method Get -TimeoutSec 8
                        if ($htmlContent -match '(?i)<meta\s+(?:property|name)=["'']og:image["'']\s+content=["'']([^"'']+)["'']') {
                            $finalThumbUrl = $matches[1].Replace("&amp;", "&")
                        }
                    } catch {}
                }
                
                # ถ้าระบบหารูปภาพเจอ ให้นำไปประกอบเป็นส่วนบนสุดของการ์ด (Hero)
                if ($null -ne $finalThumbUrl) {
                    $bubble["hero"] = @{
                        type = "image"
                        url = $finalThumbUrl
                        size = "full"
                        aspectRatio = "20:13"
                        aspectMode = "cover"
                    }
                }
                # --------------------------------

                $groupKey = "${rawSendAt}_${p5}"
                if (-not $carouselGroups.ContainsKey($groupKey)) {
                    $carouselGroups[$groupKey] = @()
                }
                $carouselGroups[$groupKey] += $bubble
            }
        }
    } catch {}
}

$finalMessages = @()

foreach ($key in $textMessages.Keys) { 
    $cleanText = $textMessages[$key].Trim()
    if (-not [string]::IsNullOrWhiteSpace($cleanText)) {
        $finalMessages += @{ type = "text"; text = $cleanText } 
    }
}

$finalMessages += $otherMessages

foreach ($gKey in $carouselGroups.Keys) {
    $cols = $carouselGroups[$gKey]
    if ($cols.Count -gt 10) { $cols = $cols[0..9] } 
    
    $groupName = ($gKey -split "_")[1]
    
    if ($groupName -ne "DefaultGroup") {
        $finalMessages += @{ type = "text"; text = "📌 $groupName" }
    }
    
    # [จุดสำคัญ] เปลี่ยนการแพ็กข้อมูลจาก Template เป็น Flex Message
    $finalMessages += @{ 
        type = "flex"
        altText = "คุณได้รับคิวงานกลุ่ม $groupName"
        contents = @{ 
            type = "carousel"
            contents = $cols 
        } 
    }
}

if ($finalMessages.Count -gt 5) {
    $finalMessages = $finalMessages[0..4]
}

if ($finalMessages.Count -gt 0) {
    foreach ($id in $groupIds) {
        $body = @{ to = $id.Trim(); messages = $finalMessages } | ConvertTo-Json -Depth 15
        Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } -Body $body
    }
}
