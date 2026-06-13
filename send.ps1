# ========================================================================
# โปรแกรมย่อย: send.ps1 (เวอร์ชัน Strict JSON แก้ไข offsetStart ผ่าน 100%)
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
            $p6 = if ($task.Param6) { $task.Param6 } else { "" } 

            if ($type -eq "text") {
                if ($textMessages.ContainsKey($rawSendAt)) { $textMessages[$rawSendAt] += "`n" + $p1 }
                else { $textMessages[$rawSendAt] = $p1 }
            }
            elseif ($type -eq "sticker") {
                $otherMessages += [ordered]@{ type = "sticker"; packageId = $p1; stickerId = $p2 }
            }
            elseif ($type -eq "carousel") {
                
                $titleText = if ([string]::IsNullOrWhiteSpace($p1)) { "-" } else { $p1 }
                $descText = if ([string]::IsNullOrWhiteSpace($p2)) { "-" } else { $p2 }
                $uriLink = if ($p4 -match "^https?://") { $p4 } else { "https://line.me" }
                
                # --- หารูปภาพปกอัตโนมัติ ---
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

                # --- 1. สร้าง Hero Box (ส่วนรูปภาพ) ---
                $heroBox = $null
                if ($null -ne $finalThumbUrl) {
                    $heroItems = @()
                    $heroItems += [ordered]@{
                        type = "image"
                        url = $finalThumbUrl
                        size = "full"
                        aspectRatio = "20:13"
                        aspectMode = "cover"
                    }
                    # ถ้ามีป้ายกำกับ ให้แปะทับรูป
                    if (-not [string]::IsNullOrWhiteSpace($p6)) {
                        $heroItems += [ordered]@{
                            type = "box"
                            layout = "vertical"
                            position = "absolute"
                            backgroundColor = "#FF9800"
                            cornerRadius = "md"
                            paddingAll = "sm"
                            offsetTop = "10px"
                            offsetStart = "10px"  # <--- แก้ไขจาก offsetLeft เป็น offsetStart แล้วตรงนี้ครับ!
                            contents = @(
                                [ordered]@{
                                    type = "text"
                                    text = " $p6 "
                                    color = "#FFFFFF"
                                    size = "xs"
                                    weight = "bold"
                                }
                            )
                        }
                    }
                    $heroBox = [ordered]@{
                        type = "box"
                        layout = "vertical"
                        contents = [array]$heroItems
                    }
                }

                # --- 2. สร้าง Body Box (ส่วนเนื้อหา) ---
                $bodyItems = @()
                
                # ถ้าไม่มีรูปภาพ แต่มีป้ายกำกับ ให้นำป้ายกำกับมาวางไว้บนสุดของเนื้อหา
                if (-not [string]::IsNullOrWhiteSpace($p6) -and $null -eq $heroBox) {
                    $bodyItems += [ordered]@{
                        type = "box"
                        layout = "inline"
                        contents = @(
                            [ordered]@{
                                type = "text"
                                text = " $p6 "
                                color = "#FFFFFF"
                                size = "xs"
                                weight = "bold"
                                backgroundColor = "#FF9800"
                                align = "center"
                            }
                        )
                    }
                }

                $bodyItems += [ordered]@{
                    type = "text"
                    text = $titleText
                    weight = "bold"
                    size = "xl"
                    color = "#E53935"
                    wrap = $true
                    margin = "md"
                }
                
                $bodyItems += [ordered]@{
                    type = "text"
                    text = $descText
                    weight = "bold"
                    size = "sm"
                    color = "#555555"
                    wrap = $true
                    margin = "sm"
                }

                # --- 3. สร้าง Footer Box (ส่วนปุ่มกด) ---
                $footerBox = [ordered]@{
                    type = "box"
                    layout = "vertical"
                    contents = @(
                        [ordered]@{
                            type = "button"
                            style = "primary"
                            color = "#1E88E5"
                            action = [ordered]@{
                                type = "uri"
                                label = "ดูรายละเอียด"
                                uri = $uriLink
                            }
                        }
                    )
                }

                # --- ประกอบร่าง Bubble ---
                $bubble = [ordered]@{
                    type = "bubble"
                    body = [ordered]@{
                        type = "box"
                        layout = "vertical"
                        contents = [array]$bodyItems
                    }
                    footer = $footerBox
                }
                
                if ($null -ne $heroBox) {
                    $bubble["hero"] = $heroBox
                }

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

# จัดคิวข้อความ Text
foreach ($key in $textMessages.Keys) { 
    $cleanText = $textMessages[$key].Trim()
    if (-not [string]::IsNullOrWhiteSpace($cleanText)) {
        $finalMessages += [ordered]@{ type = "text"; text = $cleanText } 
    }
}

# จัดคิวข้อความ Sticker
foreach ($msg in $otherMessages) {
    $finalMessages += $msg
}

# จัดคิวข้อความ Flex Carousel
foreach ($gKey in $carouselGroups.Keys) {
    $cols = $carouselGroups[$gKey]
    if ($cols.Count -gt 10) { $cols = $cols[0..9] } 
    
    $groupName = ($gKey -split "_")[1]
    
    if ($groupName -ne "DefaultGroup") {
        $finalMessages += [ordered]@{ type = "text"; text = "📌 $groupName" }
    }
    
    $finalMessages += [ordered]@{ 
        type = "flex"
        altText = "คุณได้รับข้อความกลุ่ม $groupName"
        contents = [ordered]@{ 
            type = "carousel"
            contents = [array]$cols 
        } 
    }
}

if ($finalMessages.Count -gt 5) { $finalMessages = $finalMessages[0..4] }

# ส่งไปยัง LINE
if ($finalMessages.Count -gt 0) {
    foreach ($id in $groupIds) {
        $body = @{ to = $id.Trim(); messages = [array]$finalMessages } | ConvertTo-Json -Depth 15
        Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } -Body $body
    }

    # =======================================================
# (โค้ดด้านบนคือโค้ด Flex Message มหาเทพตัวเดิม ปล่อยไว้เหมือนเดิมครับ)
# =======================================================

# ส่งไปยัง LINE
if ($finalMessages.Count -gt 0) {
    foreach ($id in $groupIds) {
        $body = @{ to = $id.Trim(); messages = [array]$finalMessages } | ConvertTo-Json -Depth 15
        Invoke-RestMethod -Uri "https://api.line.me/v2/bot/message/push" -Method Post -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } -Body $body
    }
    
    # --- [เพิ่มใหม่] สั่งให้ Google Sheets ย้ายข้อมูลหลังจากส่ง LINE เสร็จ ---
    Write-Host "กำลังส่งสัญญาณบอกให้ Google Sheets ทำความสะอาดตาราง..."
    Invoke-RestMethod -Uri "วาง_ลิงก์_WEB_APP_ยาวๆ_ที่คุณก๊อปปี้มา_ใส่ตรงนี้" -Method Get
}
}
