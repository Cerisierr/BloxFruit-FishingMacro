; ============================================================================
;  FORMATTING / SCREENSHOT / OCR
; ============================================================================
TMP_DIR := A_Temp . "\BloxFishing"
HOOK_SHOT_NAME := "sale.png"

CleanTmp() {
    try DirCreate(TMP_DIR)
    cutoff := DateAdd(A_Now, -1, "Days")
    Loop Files, TMP_DIR . "\*.*" {
        if (A_LoopFileTimeModified < cutoff && A_LoopFileName != "ocr.ps1")
            try FileDelete(A_LoopFileFullPath)
    }
}

; Save a screen rectangle as a PNG (GDI+). Returns true on success.
PngSave(x, y, w, h, path) {
    static token := 0
    if !token {
        si := Buffer(24, 0)
        NumPut("UInt", 1, si, 0)
        tk := 0
        if (DllCall("gdiplus\GdiplusStartup", "ptr*", &tk, "ptr", si, "ptr", 0) != 0)
            return false
        token := tk
    }
    hdcS := DllCall("GetDC", "ptr", 0, "ptr")
    hdc := DllCall("CreateCompatibleDC", "ptr", hdcS, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcS, "int", w, "int", h, "ptr")
    old := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
    DllCall("BitBlt", "ptr", hdc, "int", 0, "int", 0, "int", w, "int", h
        , "ptr", hdcS, "int", x, "int", y, "uint", 0x00CC0020)
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    pBmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "ptr", hbm, "ptr", 0, "ptr*", &pBmp)
    ok := false
    if pBmp {
        clsid := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "wstr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "ptr", clsid)
        ok := (DllCall("gdiplus\GdipSaveImageToFile", "ptr", pBmp, "wstr", path, "ptr", clsid, "ptr", 0) == 0)
        DllCall("gdiplus\GdipDisposeImage", "ptr", pBmp)
    }
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdc)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcS)
    return ok && FileExist(path)
}

; Windows 10/11 built-in OCR, driven through PowerShell (no extra install).
OcrScriptWrite(path) {
    script := "
    (
    param([string]$ImgPath, [string]$OutPath)
    $ErrorActionPreference = 'Stop'
    try {
      Add-Type -AssemblyName System.Runtime.WindowsRuntime
      $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
      $null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
      $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
      $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
      $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
      $null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
      $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -like 'IAsyncOperation*' })[0]
      function Await($op, $type) { $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op)); $null = $t.Wait(-1); $t.Result }
      Add-Type -AssemblyName System.Drawing
      $src = [System.Drawing.Bitmap]::FromFile($ImgPath)
      $big = New-Object System.Drawing.Bitmap ([int]($src.Width * 3)), ([int]($src.Height * 3))
      $g = [System.Drawing.Graphics]::FromImage($big)
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $g.DrawImage($src, 0, 0, $big.Width, $big.Height)
      $g.Dispose(); $src.Dispose()
      $ImgPath = $ImgPath + '.x3.png'
      $big.Save($ImgPath, [System.Drawing.Imaging.ImageFormat]::Png); $big.Dispose()
      $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImgPath)) ([Windows.Storage.StorageFile])
      $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
      $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
      $bmp = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
      $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
      if ($engine -eq $null) { Set-Content -Path $OutPath -Value 'ERR:no-ocr-engine'; exit }
      $res = Await ($engine.RecognizeAsync($bmp)) ([Windows.Media.Ocr.OcrResult])
      Set-Content -Path $OutPath -Value $res.Text
    } catch { Set-Content -Path $OutPath -Value ('ERR:' + $_.Exception.Message) }
    )"
    try {
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(script)
        f.Close()
        return true
    }
    return false
}

OcrFile(png) {
    ps := TMP_DIR . "\ocr.ps1"
    out := TMP_DIR . "\ocr_out.txt"
    try FileDelete(out)
    OcrScriptWrite(ps)
    try {
        RunWait('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' . ps
            . '" "' . png . '" "' . out . '"', , "Hide")
    } catch {
        return ""
    }
    try return Trim(FileRead(out))
    return ""
}

; Largest number in a piece of OCR text ("$ 483,112" -> 483112), or -1.
ParseMoney(text) {
    best := -1
    pos := 1
    while RegExMatch(text, "(\d[\d,. ]*)", &m, pos) {
        digits := RegExReplace(m[1], "\D")
        if (digits != "" && StrLen(digits) <= 12) {
            v := Integer(digits)
            if (v > best)
                best := v
        }
        pos := m.Pos + Max(1, m.Len)
    }
    return best
}

; "Lv. 868" -> 868, or -1.
ParseLevel(text) {
    if RegExMatch(text, "i)L[vV]\.?\s*(\d{1,4})", &m)
        return Integer(m[1])
    v := ParseMoney(text)
    return (v >= 1 && v <= 9999) ? v : -1
}

ReadLevel() {
    r := SubRect(BotState.win, Regions.level)
    path := TMP_DIR . "\level.png"
    if !PngSave(r.x, r.y, r.w, r.h, path)
        return -1
    lv := ParseLevel(OcrFile(path))
    return (lv >= 1 && lv <= 3000) ? lv : -1
}

; Read the level from the HUD and count the levels gained. Only valid while the
; HUD is visible (not in a dialogue). Jumps of more than 25 are treated as OCR noise.
UpdateLevel() {
    if !Cfg.trackLevel
        return
    lv := ReadLevel()
    BotState.levelRead := Now()
    if (lv < 0)
        return
    if (BotState.levelStart < 0) {
        BotState.levelStart := lv
        BotState.levelLast := lv
        LogMsg("[level] starting level " . lv)
        return
    }
    if (lv >= BotState.levelLast && lv - BotState.levelLast <= 25) {
        if (lv > BotState.levelLast) {
            Tally("levels", lv - BotState.levelLast)
            LogMsg("[level] now " . lv . " (+" . BotStats.levels . " this session)")
        }
        BotState.levelLast := lv
    }
}

LevelText() {
    if (BotState.levelStart < 0)
        return "n/a"
    return BotState.levelStart . " > " . BotState.levelLast . "  (+" . BotStats.levels . ")"
}

; Read the $ counter (bottom-left of the HUD). -1 if unreadable.
ReadMoney() {
    r := SubRect(BotState.win, Regions.money)
    path := TMP_DIR . "\money.png"
    if !PngSave(r.x, r.y, r.w, r.h, path)
        return -1
    BotState.lastOcr := RegExReplace(OcrFile(path), "\s+", " ")
    v := ParseMoney(BotState.lastOcr)
    if (v >= 0 && v < 100000000000) {
        BotState.moneyLast := v
        return v
    }
    return -1
}

; Poll the $ counter until it is readable, has changed from `before` and shows the
; same value twice in a row (the counter animates after a sale). Returns the last
; good value (or -1). If nothing changes it gives up after `timeout` seconds.
ReadMoneyWait(before, timeout := 10) {
    t0 := A_TickCount
    last := -1
    same := 0
    while ((A_TickCount - t0) / 1000 < timeout && Alive()) {
        v := ReadMoney()
        if (v >= 0) {
            same := (v == last) ? same + 1 : 1
            last := v
            if (same >= 2 && (before < 0 || v != before))
                return v
            if (same >= 4)                                ; steady and unchanged: nothing was paid out
                return v
        } else {
            same := 0
        }
        Wait(0.3)
    }
    return last
}
