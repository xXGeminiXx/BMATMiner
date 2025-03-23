#Requires AutoHotkey v2.0
#SingleInstance Force
; 🐝 BeeBrained's PS99 Mining Event Automation 🐝
; Last Updated: March 23, 2025
;
; == Testing Instructions ==
; 1. Ensure Roblox and Pet Simulator 99 are installed and running.
; 2. Place the script in a folder with write permissions (e.g., C:\Apps\Automation Stuff).
; 3. Run the script as administrator to ensure proper window activation.
; 4. The script auto-starts, assuming you're in Area 5 with automining active. Use F2 to stop, P to pause/resume, F3 to toggle explosives, and Esc to exit.
; 5. Monitor the GUI and log file (mining_log.txt) for errors.
; 6. If templates fail to validate, ensure an internet connection and check the GitHub repository for the latest template files.
;
; == Known Issues ==
; - Template matching may fail if game resolution or UI scaling changes. Adjust templates or confidence levels in BB_smartTemplateMatch if needed.
; - Window activation may fail on some systems. Ensure Roblox is not minimized and run as admin.
; - Assumes default Roblox hotkeys ('t' for teleport, 'f' for automine/inventory). Update config if different.
; - Reconnect in BB_resetGameState may need manual intervention if Roblox URL launches aren’t set up.
; - Screenshot functionality is disabled (placeholder in BB_updateStatusAndLog).
; - Automine detection now uses a large search area on the left side of the screen and falls back to pixel movement detection if template matching fails.
; - Errors or GUIs are cleared by pressing 'F' (not Esc), which also opens the inventory if no errors/GUIs are present.

; ===================== Run as Admin =====================

if !A_IsAdmin {
    Run("*RunAs " . A_ScriptFullPath)
    ExitApp()
}

; ===================== GLOBAL VARIABLES =====================
global BB_VERSION := "1.4.6"
global BB_running := false
global BB_paused := false
global BB_automationState := "Idle"
global BB_stateHistory := []
global BB_CLICK_DELAY_MAX := 1500
global BB_CLICK_DELAY_MIN := 500
global BB_INTERACTION_DURATION := 5000
global BB_CYCLE_INTERVAL := 180000
global BB_ENABLE_EXPLOSIVES := false
global BB_BOMB_INTERVAL := 10000
global BB_TNT_CRATE_INTERVAL := 30000
global BB_TNT_BUNDLE_INTERVAL := 15000
global BB_logFile := A_ScriptDir "\mining_log.txt"
global BB_CONFIG_FILE := A_ScriptDir "\mining_config.ini"
global BB_ENABLE_LOGGING := true
global BB_TEMPLATE_FOLDER := A_ScriptDir . "\mining_templates"
global BB_BACKUP_TEMPLATE_FOLDER := A_ScriptDir "\backup_templates"
global BB_WINDOW_TITLE := IniRead(BB_CONFIG_FILE, "Window", "WINDOW_TITLE", "Roblox")
global BB_EXCLUDED_TITLES := []
global BB_TEMPLATES := Map()
global BB_missingTemplatesReported := Map()
global BB_TEMPLATE_RETRIES := 3
global BB_FAILED_INTERACTION_COUNT := 0
global BB_MAX_FAILED_INTERACTIONS := 5
global BB_ANTI_AFK_INTERVAL := 300000
global BB_RECONNECT_CHECK_INTERVAL := 10000
global BB_active_windows := []
global BB_last_window_check := 0
global BB_myGUI := ""
global BB_BOMB_HOTKEY := "^b"
global BB_TNT_CRATE_HOTKEY := "^t"
global BB_TNT_BUNDLE_HOTKEY := "^n"
global BB_TELEPORT_HOTKEY := "t"
global BB_MAX_BUY_ATTEMPTS := 6
global BB_isAutofarming := false
global BB_lastBombStatus := "Idle"
global BB_lastTntCrateStatus := "Idle"
global BB_lastTntBundleStatus := "Idle"
global BB_currentArea := "Unknown"
global BB_merchantState := "Not Interacted"
global BB_lastError := "None"
global BB_validTemplates := 0
global BB_totalTemplates := 0
global BB_SAFE_MODE := false
global BB_imageCache := Map()
global BB_performanceData := Map()

; ===================== DEFAULT CONFIGURATION =====================

defaultIni := "
(
[Timing]
INTERACTION_DURATION=5000
CYCLE_INTERVAL=180000
CLICK_DELAY_MIN=500
CLICK_DELAY_MAX=1500
ANTI_AFK_INTERVAL=300000
RECONNECT_CHECK_INTERVAL=10000
BOMB_INTERVAL=10000
TNT_CRATE_INTERVAL=30000
TNT_BUNDLE_INTERVAL=15000

[Window]
WINDOW_TITLE=Pet Simulator 99
EXCLUDED_TITLES=Roblox Account Manager

[Features]
ENABLE_EXPLOSIVES=false
SAFE_MODE=false

[Templates]
automine_button=automine_button.png
teleport_button=teleport_button.png
area_4_button=area_4_button.png
area_5_button=area_5_button.png
mining_merchant=mining_merchant.png
buy_button=buy_button.png
merchant_window=merchant_window.png
autofarm_on=autofarm_on.png
autofarm_off=autofarm_off.png
error_message=error_message.png
error_message_alt1=error_message_alt1.png
connection_lost=connection_lost.png

[Hotkeys]
BOMB_HOTKEY=^b
TNT_CRATE_HOTKEY=^t
TNT_BUNDLE_HOTKEY=^n
TELEPORT_HOTKEY=t

[Retries]
TEMPLATE_RETRIES=3
MAX_FAILED_INTERACTIONS=5
MAX_BUY_ATTEMPTS=6

[Logging]
ENABLE_LOGGING=true
)"

; ===================== UTILITY FUNCTIONS =====================

BB_setState(newState) {
    global BB_automationState, BB_stateHistory, BB_FAILED_INTERACTION_COUNT
    BB_stateHistory.Push({state: BB_automationState, time: A_Now})
    if (BB_stateHistory.Length > 10)
        BB_stateHistory.RemoveAt(1)
    BB_automationState := newState
    ; Reset failed interaction count on successful state transition (unless transitioning to Error)
    if (newState != "Error") {
        BB_FAILED_INTERACTION_COUNT := 0
        BB_updateStatusAndLog("Reset failed interaction count on successful state transition")
    }
    BB_updateStatusAndLog("State changed: " . newState)
}

BB_updateStatusAndLog(message, updateGUI := true, isError := false, takeScreenshot := false) {
    global BB_ENABLE_LOGGING, BB_logFile, BB_myGUI, BB_isAutofarming, BB_currentArea, BB_merchantState, BB_lastError
    global BB_lastBombStatus, BB_lastTntCrateStatus, BB_lastTntBundleStatus, BB_validTemplates, BB_totalTemplates
    static firstRun := true
    
    if BB_ENABLE_LOGGING {
        timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        logMessage := "[" . timestamp . "] " . (isError ? "ERROR: " : "") . message . "`n"
        
        if firstRun {
            try {
                FileDelete(BB_logFile)
            } catch {
                ; Ignore if file doesn't exist
            }
            firstRun := false
        }
        FileAppend(logMessage, BB_logFile)
    }
    
    if isError
        BB_lastError := message
    
    if updateGUI && IsObject(BB_myGUI) {
        BB_myGUI["Status"].Text := (BB_running ? (BB_paused ? "Paused" : "Running") : "Idle")
        BB_myGUI["Status"].SetFont(BB_running ? (BB_paused ? "cOrange" : "cGreen") : "cRed")
        BB_myGUI["WindowCount"].Text := BB_active_windows.Length
        BB_myGUI["AutofarmStatus"].Text := (BB_isAutofarming ? "ON" : "OFF")
        BB_myGUI["AutofarmStatus"].SetFont(BB_isAutofarming ? "cGreen" : "cRed")
        BB_myGUI["ExplosivesStatus"].Text := (BB_ENABLE_EXPLOSIVES ? "ON" : "OFF")
        BB_myGUI["ExplosivesStatus"].SetFont(BB_ENABLE_EXPLOSIVES ? "cGreen" : "cRed")
        BB_myGUI["TemplateStatus"].Text := BB_validTemplates . "/" . BB_totalTemplates
        BB_myGUI["TemplateStatus"].SetFont(BB_validTemplates = BB_totalTemplates ? "cGreen" : "cRed")
        BB_myGUI["CurrentArea"].Text := BB_currentArea
        BB_myGUI["MerchantState"].Text := BB_merchantState
        BB_myGUI["BombStatus"].Text := BB_lastBombStatus
        BB_myGUI["TntCrateStatus"].Text := BB_lastTntCrateStatus
        BB_myGUI["TntBundleStatus"].Text := BB_lastTntBundleStatus
        BB_myGUI["LastAction"].Text := message
        BB_myGUI["LastError"].Text := BB_lastError
        BB_myGUI["LastError"].SetFont(isError ? "cRed" : "cBlack")
    }
    
    ToolTip message, 0, 100
    SetTimer(() => ToolTip(), -3000)
}

BB_clearLog(*) {
    global BB_logFile
    FileDelete(BB_logFile)
    BB_updateStatusAndLog("Log file cleared")
}

BB_validateImage(filePath) {
    if !FileExist(filePath) {
        return "File does not exist"
    }
    if (StrLower(SubStr(filePath, -3)) != "png") {
        return "Invalid file extension"
    }
    fileSize := FileGetSize(filePath)
    if (fileSize < 8) {
        BB_updateStatusAndLog("File too small to be a PNG: " . fileSize . " bytes (Path: " . filePath . ")", true)
        return "File too small"
    }
    BB_updateStatusAndLog("File assumed valid (skipped FileOpen check): " . filePath)
    return "Assumed Valid (Skipped FileOpen)"
}

BB_downloadTemplate(templateName, fileName) {
    global BB_TEMPLATE_FOLDER, BB_BACKUP_TEMPLATE_FOLDER, BB_validTemplates, BB_totalTemplates
    BB_totalTemplates++
    templateUrl := "https://raw.githubusercontent.com/xXGeminiXx/BMATMiner/main/mining_templates/" . fileName
    localPath := BB_TEMPLATE_FOLDER . "\" . fileName
    backupPath := BB_BACKUP_TEMPLATE_FOLDER . "\" . fileName

    if !FileExist(localPath) {
        try {
            BB_updateStatusAndLog("Attempting to download " . fileName . " from " . templateUrl)
            downloadWithStatus(templateUrl, localPath)
            validationResult := BB_validateImage(localPath)
            if (validationResult = "Valid" || InStr(validationResult, "Assumed Valid")) {
                BB_validTemplates++
                BB_updateStatusAndLog("Downloaded and validated template: " . fileName)
            } else {
                BB_updateStatusAndLog("Validation failed: " . validationResult, true, true)
                if FileExist(backupPath) {
                    FileCopy(backupPath, localPath, 1)
                    validationResult := BB_validateImage(localPath)
                    if (validationResult = "Valid" || InStr(validationResult, "Assumed Valid")) {
                        BB_validTemplates++
                        BB_updateStatusAndLog("Using backup template for " . fileName)
                    } else {
                        BB_updateStatusAndLog("Backup invalid: " . validationResult, true, true)
                    }
                }
            }
        } catch as err {
            BB_updateStatusAndLog("Download failed: " . err.Message, true, true)
            if FileExist(backupPath) {
                FileCopy(backupPath, localPath, 1)
                validationResult := BB_validateImage(localPath)
                if (validationResult = "Valid" || InStr(validationResult, "Assumed Valid")) {
                    BB_validTemplates++
                    BB_updateStatusAndLog("Using backup template for " . fileName)
                } else {
                    BB_updateStatusAndLog("Backup invalid: " . validationResult, true, true)
                }
            } else {
                BB_updateStatusAndLog("No backup available for " . fileName, true, true)
            }
        }
    } else {
        validationResult := BB_validateImage(localPath)
        if (validationResult = "Valid" || InStr(validationResult, "Assumed Valid")) {
            BB_validTemplates++
            BB_updateStatusAndLog("Template already exists and is valid: " . fileName)
        } else {
            BB_updateStatusAndLog("Existing template invalid: " . validationResult . " - Attempting redownload", true, true)
            try {
                BB_updateStatusAndLog("Attempting to redownload " . fileName . " from " . templateUrl)
                downloadWithStatus(templateUrl, localPath)
                validationResult := BB_validateImage(localPath)
                if (validationResult = "Valid" || InStr(validationResult, "Assumed Valid")) {
                    BB_validTemplates++
                    BB_updateStatusAndLog("Redownloaded and validated template: " . fileName)
                } else {
                    BB_updateStatusAndLog("Redownloaded template invalid: " . validationResult, true, true)
                }
            } catch as err {
                BB_updateStatusAndLog("Redownload failed: " . err.Message, true, true)
            }
        }
    }
}

BB_httpDownload(url, dest) {
    BB_updateStatusAndLog("Attempting PowerShell download for: " . url)
    psCommand := "(New-Object System.Net.WebClient).DownloadFile('" . url . "','" . dest . "')"
    try {
        SplitPath(dest, , &dir)
        if !DirExist(dir) {
            DirCreate(dir)
            BB_updateStatusAndLog("Created directory: " . dir)
        }
        exitCode := RunWait("PowerShell -NoProfile -Command " . Chr(34) . psCommand . Chr(34), , "Hide")
        if (exitCode != 0) {
            throw Error("PowerShell exited with code " . exitCode)
        }
        maxWait := 10
        loop maxWait {
            if FileExist(dest) {
                fileSize := FileGetSize(dest)
                if (fileSize > 0) {
                    BB_updateStatusAndLog("Download succeeded using PowerShell => " . dest . " (Size: " . fileSize . " bytes)")
                    Sleep(1000)
                    return true
                }
            }
            Sleep(1000)
        }
        throw Error("File not created or empty after download")
    } catch as err {
        BB_updateStatusAndLog("PowerShell download failed: " . err.Message, true, true)
        if FileExist(dest) {
            FileDelete(dest)
        }
        return false
    }
}

BB_robustWindowActivation(hwnd) {
    try {
        WinActivate(hwnd)
        if WinWaitActive("ahk_id " . hwnd, , 2) {
            BB_updateStatusAndLog("Window activated successfully: " . hwnd)
            return true
        } else {
            BB_updateStatusAndLog("Window activation timed out: " . hwnd, true)
            return false
        }
    } catch as err {
        BB_updateStatusAndLog("Window activation failed: " . hwnd . " - " . err.Message, true, true)
        return false
    }
}

BB_clickAt(x, y) {
    global BB_CLICK_DELAY_MIN, BB_CLICK_DELAY_MAX, BB_performanceData
    hwnd := WinGetID("A")
    if (!hwnd || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("No Roblox window active for clicking at x=" . x . ", y=" . y, true)
        return false
    }
    WinGetPos(&winX, &winY, &winW, &winH, hwnd)
    if (x < winX || x > winX + winW || y < winY || y > winY + winH) {
        BB_updateStatusAndLog("Click coordinates x=" . x . ", y=" . y . " are outside window", true)
        return false
    }
    startTime := A_TickCount
    delay := Random(BB_CLICK_DELAY_MIN, BB_CLICK_DELAY_MAX)
    MouseMove(x, y, 10)
    Sleep(delay)
    Click
    elapsed := A_TickCount - startTime
    BB_performanceData["ClickAt"] := BB_performanceData.Has("ClickAt") ? (BB_performanceData["ClickAt"] + elapsed) / 2 : elapsed
    BB_updateStatusAndLog("Clicked at x=" . x . ", y=" . y . " (" . elapsed . "ms)")
    return true
}

downloadWithStatus(url, dest) {
    try {
        if (!BB_httpDownload(url, dest)) {
            throw Error("Download failed")
        }
        Sleep(1000)
        fileSize := FileGetSize(dest)
        BB_updateStatusAndLog("Downloaded file size: " . fileSize . " bytes")
        if (fileSize < 8) {
            throw Error("File too small to be a PNG: " . fileSize . " bytes")
        }
        return true
    } catch as err {
        BB_updateStatusAndLog("downloadWithStatus failed: " . err.Message, true, true)
        if (FileExist(dest)) {
            FileDelete(dest)
        }
        throw err
    }
}

StrJoin(arr, delimiter) {
    result := ""
    for i, value in arr
        result .= (i > 1 ? delimiter : "") . value
    return result
}

; ===================== LOAD CONFIGURATION =====================

BB_loadConfig() {
    global BB_CONFIG_FILE, BB_logFile, BB_ENABLE_LOGGING, BB_WINDOW_TITLE, BB_EXCLUDED_TITLES
    global BB_CLICK_DELAY_MIN, BB_CLICK_DELAY_MAX, BB_INTERACTION_DURATION, BB_CYCLE_INTERVAL
    global BB_TEMPLATE_FOLDER, BB_BACKUP_TEMPLATE_FOLDER, BB_TEMPLATES, BB_TEMPLATE_RETRIES, BB_MAX_FAILED_INTERACTIONS
    global BB_ANTI_AFK_INTERVAL, BB_RECONNECT_CHECK_INTERVAL, BB_BOMB_INTERVAL
    global BB_TNT_CRATE_INTERVAL, BB_TNT_BUNDLE_INTERVAL, BB_ENABLE_EXPLOSIVES, BB_SAFE_MODE
    global BB_BOMB_HOTKEY, BB_TNT_CRATE_HOTKEY, BB_TNT_BUNDLE_HOTKEY, BB_TELEPORT_HOTKEY, BB_MAX_BUY_ATTEMPTS
    global BB_validTemplates, BB_totalTemplates

    if !FileExist(BB_CONFIG_FILE) {
        FileAppend(defaultIni, BB_CONFIG_FILE)
        BB_updateStatusAndLog("Created default mining_config.ini")
    }

    if !DirExist(BB_TEMPLATE_FOLDER)
        DirCreate(BB_TEMPLATE_FOLDER)
    if !DirExist(BB_BACKUP_TEMPLATE_FOLDER)
        DirCreate(BB_BACKUP_TEMPLATE_FOLDER)

    BB_validTemplates := 0
    BB_totalTemplates := 0

	for templateName, fileName in Map(
		"automine_button", "automine_button.png",
		"teleport_button", "teleport_button.png",
		"area_4_button", "area_4_button.png",
		"area_5_button", "area_5_button.png",
		"mining_merchant", "mining_merchant.png",
		"buy_button", "buy_button.png",
		"merchant_window", "merchant_window.png",
		"autofarm_on", "autofarm_on.png",
		"autofarm_off", "autofarm_off.png",
		"go_to_top_button", "go_to_top_button.png",
		"error_message", "error_message.png",        ; Added
		"error_message_alt1", "error_message_alt1.png",  ; Added
		"connection_lost", "connection_lost.png"     ; Added
	) {
		BB_downloadTemplate(templateName, fileName)
		BB_TEMPLATES[templateName] := fileName
	}

    BB_updateStatusAndLog("Template validation summary: " . BB_validTemplates . "/" . BB_totalTemplates . " templates are valid")

    BB_INTERACTION_DURATION := IniRead(BB_CONFIG_FILE, "Timing", "INTERACTION_DURATION", 5000)
    BB_CYCLE_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "CYCLE_INTERVAL", 180000)
    BB_CLICK_DELAY_MIN := IniRead(BB_CONFIG_FILE, "Timing", "CLICK_DELAY_MIN", 500)
    BB_CLICK_DELAY_MAX := IniRead(BB_CONFIG_FILE, "Timing", "CLICK_DELAY_MAX", 1500)
    BB_ANTI_AFK_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "ANTI_AFK_INTERVAL", 300000)
    BB_RECONNECT_CHECK_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "RECONNECT_CHECK_INTERVAL", 10000)
    BB_BOMB_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "BOMB_INTERVAL", 10000)
    BB_TNT_CRATE_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "TNT_CRATE_INTERVAL", 30000)
    BB_TNT_BUNDLE_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "TNT_BUNDLE_INTERVAL", 15000)

    if BB_performanceData.Has("ClickAt") {
        avgClickTime := BB_performanceData["ClickAt"]
        BB_CLICK_DELAY_MIN := Max(500, avgClickTime - 100)
        BB_CLICK_DELAY_MAX := Max(1500, avgClickTime + 100)
        BB_updateStatusAndLog("Adjusted click delays: Min=" . BB_CLICK_DELAY_MIN . ", Max=" . BB_CLICK_DELAY_MAX . " based on performance")
    } else {
        BB_updateStatusAndLog("No performance data available, using default click delays: Min=" . BB_CLICK_DELAY_MIN . ", Max=" . BB_CLICK_DELAY_MAX)
    }

    BB_WINDOW_TITLE := IniRead(BB_CONFIG_FILE, "Window", "WINDOW_TITLE", "Pet Simulator 99")
    excludedStr := IniRead(BB_CONFIG_FILE, "Window", "EXCLUDED_TITLES", "Roblox Account Manager")
    BB_EXCLUDED_TITLES := StrSplit(excludedStr, ",")

    BB_ENABLE_EXPLOSIVES := IniRead(BB_CONFIG_FILE, "Features", "ENABLE_EXPLOSIVES", false)
    BB_SAFE_MODE := IniRead(BB_CONFIG_FILE, "Features", "SAFE_MODE", false)

    BB_BOMB_HOTKEY := IniRead(BB_CONFIG_FILE, "Hotkeys", "BOMB_HOTKEY", "^b")
    BB_TNT_CRATE_HOTKEY := IniRead(BB_CONFIG_FILE, "Hotkeys", "TNT_CRATE_HOTKEY", "^t")
    BB_TNT_BUNDLE_HOTKEY := IniRead(BB_CONFIG_FILE, "Hotkeys", "TNT_BUNDLE_HOTKEY", "^n")
    BB_TELEPORT_HOTKEY := IniRead(BB_CONFIG_FILE, "Hotkeys", "TELEPORT_HOTKEY", "t")

    BB_TEMPLATE_RETRIES := IniRead(BB_CONFIG_FILE, "Retries", "TEMPLATE_RETRIES", 3)
    BB_MAX_FAILED_INTERACTIONS := IniRead(BB_CONFIG_FILE, "Retries", "MAX_FAILED_INTERACTIONS", 5)
    BB_MAX_BUY_ATTEMPTS := IniRead(BB_CONFIG_FILE, "Retries", "MAX_BUY_ATTEMPTS", 6)

    BB_ENABLE_LOGGING := IniRead(BB_CONFIG_FILE, "Logging", "ENABLE_LOGGING", true)
}

; ===================== GUI SETUP =====================

BB_setupGUI() {
    global BB_myGUI, BB_BOMB_HOTKEY, BB_TNT_CRATE_HOTKEY, BB_TNT_BUNDLE_HOTKEY, BB_VERSION
    BB_myGUI := Gui("", "🐝 BeeBrained’s PS99 Mining Event Macro v" . BB_VERSION . " 🐝")  ; Removed +AlwaysOnTop
    BB_myGUI.OnEvent("Close", BB_exitApp)
    
    BB_myGUI.Add("Text", "x10 y10 w400 h20 Center", "🐝 BeeBrained’s PS99 Mining Event Macro v" . BB_VERSION . " 🐝")
    hotkeyText := "Hotkeys: F1 (Start) | F2 (Stop) | P (Pause) | F3 (Explosives) | Esc (Exit)"
    hotkeyText .= " | " . BB_BOMB_HOTKEY . " (Bomb) | " . BB_TNT_CRATE_HOTKEY . " (TNT Crate) | " . BB_TNT_BUNDLE_HOTKEY . " (TNT Bundle)"
    BB_myGUI.Add("Text", "x10 y30 w400 h25 Center", hotkeyText)
    
    BB_myGUI.Add("GroupBox", "x10 y60 w400 h120", "Script Status")
    BB_myGUI.Add("Text", "x20 y80 w180 h20", "Status:")
    BB_myGUI.Add("Text", "x200 y80 w200 h20", "Idle").Name := "Status"
    BB_myGUI.Add("Text", "x20 y100 w180 h20", "Active Windows:")
    BB_myGUI.Add("Text", "x200 y100 w200 h20", "0").Name := "WindowCount"
    BB_myGUI.Add("Text", "x20 y120 w180 h20", "Autofarm:")
    BB_myGUI.Add("Text", "x200 y120 w200 h20 cRed", "Unknown").Name := "AutofarmStatus"
    BB_myGUI.Add("Text", "x20 y140 w180 h20", "Explosives:")
    BB_myGUI.Add("Text", "x200 y140 w200 h20 cRed", "OFF").Name := "ExplosivesStatus"
    BB_myGUI.Add("Text", "x20 y160 w180 h20", "Templates Valid:")
    BB_myGUI.Add("Text", "x200 y160 w200 h20", "0/0").Name := "TemplateStatus"
    
    BB_myGUI.Add("GroupBox", "x10 y190 w400 h80", "Game State")
    BB_myGUI.Add("Text", "x20 y210 w180 h20", "Current Area:")
    BB_myGUI.Add("Text", "x200 y210 w200 h20", "Unknown").Name := "CurrentArea"
    BB_myGUI.Add("Text", "x20 y230 w180 h20", "Merchant Interaction:")
    BB_myGUI.Add("Text", "x200 y230 w200 h20", "Not Interacted").Name := "MerchantState"
    
    BB_myGUI.Add("GroupBox", "x10 y280 w400 h80", "Explosives Status")
    BB_myGUI.Add("Text", "x20 y300 w180 h20", "Bomb:")
    BB_myGUI.Add("Text", "x200 y300 w200 h20", "Idle").Name := "BombStatus"
    BB_myGUI.Add("Text", "x20 y320 w180 h20", "TNT Crate:")
    BB_myGUI.Add("Text", "x200 y320 w200 h20", "Idle").Name := "TntCrateStatus"
    BB_myGUI.Add("Text", "x20 y340 w180 h20", "TNT Bundle:")
    BB_myGUI.Add("Text", "x200 y340 w200 h20", "Idle").Name := "TntBundleStatus"
    
    BB_myGUI.Add("GroupBox", "x10 y370 w400 h100", "Last Action/Error")
    BB_myGUI.Add("Text", "x20 y390 w180 h20", "Last Action:")
    BB_myGUI.Add("Text", "x200 y390 w200 h40 Wrap", "None").Name := "LastAction"
    BB_myGUI.Add("Text", "x20 y430 w180 h20", "Last Error:")
    BB_myGUI.Add("Text", "x200 y430 w200 h40 Wrap cRed", "None").Name := "LastError"
    
    BB_myGUI.Add("Button", "x10 y480 w120 h30", "Reload Config").OnEvent("Click", BB_loadConfigFromFile)
    BB_myGUI.Add("Button", "x290 y480 w120 h30", "Clear Log").OnEvent("Click", BB_clearLog)
    
    BB_myGUI.Show("x0 y0 w420 h520")
}

; ===================== HOTKEYS =====================

Hotkey("F2", BB_stopAutomation)
Hotkey("p", BB_togglePause)
Hotkey("F3", BB_toggleExplosives)
Hotkey("Esc", BB_exitApp)

; ===================== CORE FUNCTIONS =====================

BB_startAutomation(*) {
    global BB_running, BB_paused, BB_currentArea, BB_automationState, BB_ENABLE_EXPLOSIVES
    if BB_running {
        BB_updateStatusAndLog("Already running, ignoring start request")
        return
    }
    BB_running := true
    BB_paused := false
    BB_currentArea := "Area 5"
    BB_automationState := "Idle"
    BB_updateStatusAndLog("Running - Starting Mining Automation")
    SetTimer(BB_reconnectCheckLoop, BB_RECONNECT_CHECK_INTERVAL)
    if BB_ENABLE_EXPLOSIVES {
        SetTimer(BB_bombLoop, BB_BOMB_INTERVAL)
        SetTimer(BB_tntCrateLoop, BB_TNT_CRATE_INTERVAL)
        SetTimer(BB_tntBundleLoop, BB_TNT_BUNDLE_INTERVAL)
        BB_updateStatusAndLog("Explosives timers started")
    } else {
        SetTimer(BB_bombLoop, 0)
        SetTimer(BB_tntCrateLoop, 0)
        SetTimer(BB_tntBundleLoop, 0)
        BB_updateStatusAndLog("Explosives timers disabled")
    }
    SetTimer(BB_miningAutomationLoop, 1000)  ; Start the loop with a 1-second interval
}

BB_stopAutomation(*) {
    global BB_running, BB_paused, BB_currentArea, BB_merchantState, BB_automationState
    BB_running := false
    BB_paused := false
    BB_currentArea := "Unknown"
    BB_merchantState := "Not Interacted"
    BB_automationState := "Idle"
    SetTimer(BB_miningAutomationLoop, 0)
    SetTimer(BB_reconnectCheckLoop, 0)
    SetTimer(BB_bombLoop, 0)
    SetTimer(BB_tntCrateLoop, 0)
    SetTimer(BB_tntBundleLoop, 0)
    BB_updateStatusAndLog("Stopped automation")
}

BB_togglePause(*) {
    global BB_running, BB_paused
    if BB_running {
        BB_paused := !BB_paused
        BB_updateStatusAndLog(BB_paused ? "Paused" : "Resumed")
        Sleep 200
    }
}

BB_toggleExplosives(*) {
    global BB_ENABLE_EXPLOSIVES, BB_myGUI
    BB_ENABLE_EXPLOSIVES := !BB_ENABLE_EXPLOSIVES
    if BB_ENABLE_EXPLOSIVES {
        SetTimer(BB_bombLoop, BB_BOMB_INTERVAL)
        SetTimer(BB_tntCrateLoop, BB_TNT_CRATE_INTERVAL)
        SetTimer(BB_tntBundleLoop, BB_TNT_BUNDLE_INTERVAL)
        BB_updateStatusAndLog("Explosives Enabled - Timers started")
    } else {
        SetTimer(BB_bombLoop, 0)
        SetTimer(BB_tntCrateLoop, 0)
        SetTimer(BB_tntBundleLoop, 0)
        BB_updateStatusAndLog("Explosives Disabled - Timers stopped")
    }
}

BB_updateActiveWindows() {
    global BB_active_windows, BB_last_window_check, BB_WINDOW_TITLE, BB_EXCLUDED_TITLES
    currentTime := A_TickCount
    if (currentTime - BB_last_window_check < 5000) {
        BB_updateStatusAndLog("Window check skipped (recently checked)")
        return BB_active_windows
    }
    
    BB_active_windows := []
    try {
        winList := WinGetList()
    } catch {
        BB_updateStatusAndLog("Failed to retrieve window list", true, true)
        return BB_active_windows
    }
    
    activeHwnd := WinGetID("A")
    for hwnd in winList {
        try {
            title := WinGetTitle(hwnd)
            if (InStr(title, "Roblox") && !InStr(title, "Chrome") && !InStr(title, "Firefox") && !BB_hasExcludedTitle(title)) {
                BB_active_windows.Push(hwnd)
                BB_updateStatusAndLog("Found Roblox window: " . title . " (hwnd: " . hwnd . ", active: " . (hwnd = activeHwnd ? "Yes" : "No") . ")")
            }
        } catch as err {
            BB_updateStatusAndLog("Error checking window " . hwnd . ": " . err.Message, true, true)
        }
    }
    
    if (BB_active_windows.Length > 1 && activeHwnd) {
        prioritized := []
        for hwnd in BB_active_windows {
            if (hwnd = activeHwnd) {
                prioritized.InsertAt(1, hwnd)
            } else {
                prioritized.Push(hwnd)
            }
        }
        BB_active_windows := prioritized
    }
    
    BB_last_window_check := currentTime
    BB_updateStatusAndLog("Found " . BB_active_windows.Length . " valid Roblox windows")
    return BB_active_windows
}

BB_hasExcludedTitle(title) {
    global BB_EXCLUDED_TITLES
    for excluded in BB_EXCLUDED_TITLES {
        if InStr(title, excluded)
            return true
    }
    return false
}

; ===================== ERROR HANDLING =====================

BB_checkForError() {
    global BB_automationState, BB_FAILED_INTERACTION_COUNT, BB_currentArea, BB_merchantState
    FoundX := ""
    FoundY := ""
    errorTypes := ["error_message", "error_message_alt1", "connection_lost"]
    errorDetected := false
    errorType := ""

    for type in errorTypes {
        if BB_smartTemplateMatch(type, &FoundX, &FoundY) {
            errorDetected := true
            errorType := type
            BB_updateStatusAndLog("WARNING: Error detected (" . errorType . " at x=" . FoundX . ", y=" . FoundY . ")", true, true, true)
            break
        } else {
            BB_updateStatusAndLog("Info: Template '" . type . "' not found during error check")  ; Log as info, not error
        }
    }

    if errorDetected {
        BB_updateStatusAndLog("Handling error: " . errorType)
        
        errorActions := Map(
            "DisableAutomine", () => (SendInput("{f down}"), Sleep(100), SendInput("{f up}"), Sleep(500), BB_checkAutofarming()),
            "TeleportToArea4", () => (SendInput("{f down}"), Sleep(100), SendInput("{f up}"), Sleep(500), SendInput("{" . BB_TELEPORT_HOTKEY . "}"), Sleep(1000), BB_openTeleportMenu()),
            "Shopping", () => (SendInput("{f down}"), Sleep(100), SendInput("{f up}"), Sleep(500), BB_interactWithMerchant()),
            "TeleportToArea5", () => (SendInput("{f down}"), Sleep(100), SendInput("{f up}"), Sleep(500), SendInput("{" . BB_TELEPORT_HOTKEY . "}"), Sleep(1000), BB_openTeleportMenu()),
            "EnableAutomine", () => (SendInput("{f down}"), Sleep(100), SendInput("{f up}"), Sleep(500), BB_checkAutofarming()),
            "Idle", () => (SendInput("{Space down}"), Sleep(100), SendInput("{Space up}"), Sleep(500)),
            "Mining", () => (SendInput("{Space down}"), Sleep(100), SendInput("{Space up}"), Sleep(500))
        )

        action := errorActions.Has(BB_automationState) ? errorActions[BB_automationState] : errorActions["Idle"]
        actionResult := action()
        
        BB_updateStatusAndLog("Attempted recovery from error in state " . BB_automationState . " (Result: " . (actionResult ? "Success" : "Failed") . ")")
        
        BB_FAILED_INTERACTION_COUNT++
        if (BB_FAILED_INTERACTION_COUNT >= BB_MAX_FAILED_INTERACTIONS) {
            BB_updateStatusAndLog("Too many failed recoveries (" . BB_FAILED_INTERACTION_COUNT . "), attempting to reset game state", true, true)
            if !BB_resetGameState() {
                BB_stopAutomation()
                return true
            }
        }
        
        return true
    }
    
    BB_updateStatusAndLog("No errors detected on screen")
    return false
}

BB_goToTop() {
    FoundX := ""
    FoundY := ""
    BB_updateStatusAndLog("Attempting to go to the top of the mining area...")
    
    ; Search for the "Go to Top" button on the right side of the screen
    searchArea := [A_ScreenWidth - 300, 50, A_ScreenWidth - 50, 150]
    
    loop 3 {
        if BB_smartTemplateMatch("go_to_top_button", &FoundX, &FoundY, searchArea) {
            BB_clickAt(FoundX, FoundY)
            BB_updateStatusAndLog("Clicked 'Go to Top' button at x=" . FoundX . ", y=" . FoundY)
            Sleep(5000)  ; Wait for the player to reach the top
            return true
        } else {
            BB_updateStatusAndLog("Info: 'go_to_top_button' not found on attempt " . A_Index)
            Sleep(1000)
        }
    }
    
    BB_updateStatusAndLog("Failed to find 'Go to Top' button after 3 attempts")
    return false
}

BB_resetGameState() {
    global BB_currentArea, BB_merchantState, BB_isAutofarming, BB_automationState, BB_FAILED_INTERACTION_COUNT
    BB_updateStatusAndLog("Attempting to reset game state")
    
    windows := BB_updateActiveWindows()
    for hwnd in windows {
        try {
            WinClose("ahk_id " . hwnd)
            BB_updateStatusAndLog("Closed Roblox window: " . hwnd)
        } catch as err {
            BB_updateStatusAndLog("Failed to close Roblox window " . hwnd . ": " . err.Message, true, true)
            return false
        }
    }
    
    Sleep(5000)
    
    try {
        Run("roblox://placeId=8737890210")
        BB_updateStatusAndLog("Attempted to reopen Pet Simulator 99")
    } catch as err {
        BB_updateStatusAndLog("Failed to reopen Roblox: " . err.Message, true, true)
        return false
    }
    
    Sleep(30000)
    
    BB_currentArea := "Unknown"
    BB_merchantState := "Not Interacted"
    BB_isAutofarming := false
    BB_automationState := "Idle"
    BB_FAILED_INTERACTION_COUNT := 0
    
    windows := BB_updateActiveWindows()
    if (windows.Length > 0) {
        BB_updateStatusAndLog("Game state reset successful, resuming automation")
        return true
    } else {
        BB_updateStatusAndLog("Failed to reset game state: No Roblox windows found after restart", true, true)
        return false
    }
}

BB_checkForUpdates() {
    global BB_VERSION
    versionUrl := "https://raw.githubusercontent.com/xXGeminiXx/BMATMiner/main/version.txt"
    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.Open("GET", versionUrl, false)
        http.Send()
        if (http.Status != 200)
            throw Error("HTTP status " . http.Status . " received")
        latestVersion := Trim(http.ResponseText, " `t`r`n")
        BB_updateStatusAndLog("Current version: " . BB_VERSION . " | Remote version: " . latestVersion)
        if (!RegExMatch(latestVersion, "^\d+\.\d+\.\d+$")) {
            throw Error("Invalid version format: '" . latestVersion . "'")
        }
        if (latestVersion != BB_VERSION) {
            BB_updateStatusAndLog("New version available: " . latestVersion . " (current: " . BB_VERSION . ")")
        } else {
            BB_updateStatusAndLog("Script is up to date (version: " . BB_VERSION . ")")
        }
    } catch as err {
        BB_updateStatusAndLog("Failed to check for updates: " . err.Message, true, true)
    }
}

; ===================== MINING AUTOMATION FUNCTIONS =====================

BB_checkAutofarming() {
    global BB_isAutofarming
    FoundX := ""
    FoundY := ""
    
    BB_updateStatusAndLog("Checking autofarm state...")
    if BB_smartTemplateMatch("automine_button", &FoundX, &FoundY) {
        BB_updateStatusAndLog("Automine button found at x=" . FoundX . ", y=" . FoundY)
        BB_isAutofarming := true  ; Assume automining is on if the button is found
        return true
    } else {
        BB_updateStatusAndLog("Automine button not found, checking for pixel movement...")
        
        ; Check for pixel movement in multiple screen regions to detect if the user is moving (indicating automining)
        regions := [
            [A_ScreenWidth//4, A_ScreenHeight//4],      ; Top-left
            [3*A_ScreenWidth//4, A_ScreenHeight//4],    ; Top-right
            [A_ScreenWidth//4, 3*A_ScreenHeight//4],    ; Bottom-left
            [3*A_ScreenWidth//4, 3*A_ScreenHeight//4]   ; Bottom-right
        ]
        
        initialColors := []
        for region in regions {
            color := PixelGetColor(region[1], region[2], "RGB")
            initialColors.Push(color)
        }
        
        Sleep(1000)  ; Wait 1 second to check for changes
        
        isMoving := false
        loop 3 {  ; Check multiple times to confirm
            for index, region in regions {
                newColor := PixelGetColor(region[1], region[2], "RGB")
                if (newColor != initialColors[index]) {
                    isMoving := true
                    break
                }
            }
            if (isMoving) {
                break
            }
            Sleep(500)
        }
        
        if (isMoving) {
            BB_updateStatusAndLog("Pixel movement detected, assuming autofarming is ON")
            BB_isAutofarming := true
            return true
        } else {
            BB_updateStatusAndLog("No pixel movement detected, assuming autofarming is OFF")
            BB_isAutofarming := false
            return false
        }
    }
}

BB_disableAutomine() {
    FoundX := ""
    FoundY := ""
    
    ; Step 1: Go to the top to ensure the automine button is visible
    BB_goToTop()
    
    ; Step 2: Try to find and click the automine button
    if BB_smartTemplateMatch("automine_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Clicked automine button to disable automining")
        Sleep(1000)
        
        ; Validate using pixel movement
        regions := [
            [A_ScreenWidth//4, A_ScreenHeight//4],      ; Top-left
            [3*A_ScreenWidth//4, A_ScreenHeight//4],    ; Top-right
            [A_ScreenWidth//4, 3*A_ScreenHeight//4],    ; Bottom-left
            [3*A_ScreenWidth//4, 3*A_ScreenHeight//4]   ; Bottom-right
        ]
        
        initialColors := []
        for region in regions {
            color := PixelGetColor(region[1], region[2], "RGB")
            initialColors.Push(color)
        }
        
        Sleep(1000)  ; Wait 1 second to check for changes
        
        isMoving := false
        loop 3 {
            for index, region in regions {
                newColor := PixelGetColor(region[1], region[2], "RGB")
                if (newColor != initialColors[index]) {
                    isMoving := true
                    break
                }
            }
            if (isMoving) {
                break
            }
            Sleep(500)
        }
        
        if (!isMoving) {
            BB_updateStatusAndLog("No pixel movement detected, automining disabled successfully")
            global BB_isAutofarming := false
            return true
        } else {
            BB_updateStatusAndLog("Pixel movement still detected, automining may not be disabled")
        }
    }
    
    ; Step 3: If the button isn't found, use the F key to toggle automining
    BB_updateStatusAndLog("Automine button not found, using F key to toggle automining...")
    SendInput("{f down}")
    Sleep(100)
    SendInput("{f up}")
    Sleep(1000)
    
    ; Validate using pixel movement
    regions := [
        [A_ScreenWidth//4, A_ScreenHeight//4],      ; Top-left
        [3*A_ScreenWidth//4, A_ScreenHeight//4],    ; Top-right
        [A_ScreenWidth//4, 3*A_ScreenHeight//4],    ; Bottom-left
        [3*A_ScreenWidth//4, 3*A_ScreenHeight//4]   ; Bottom-right
    ]
    
    initialColors := []
    for region in regions {
        color := PixelGetColor(region[1], region[2], "RGB")
        initialColors.Push(color)
    }
    
    Sleep(1000)  ; Wait 1 second to check for changes
    
    isMoving := false
    loop 3 {
        for index, region in regions {
            newColor := PixelGetColor(region[1], region[2], "RGB")
            if (newColor != initialColors[index]) {
                isMoving := true
                break
            }
        }
        if (isMoving) {
            break
        }
        Sleep(500)
    }
    
    if (!isMoving) {
        BB_updateStatusAndLog("No pixel movement detected after using F key, automining disabled successfully")
        global BB_isAutofarming := false
        return true
    } else {
        BB_updateStatusAndLog("Pixel movement still detected after using F key, failed to disable automining")
        return false
    }
}

BB_openTeleportMenu() {
    global BB_TELEPORT_HOTKEY
    FoundX := ""
    FoundY := ""
    if BB_smartTemplateMatch("teleport_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Opened teleport menu")
        Sleep(1000)
        return true
    }
    SendInput("{" . BB_TELEPORT_HOTKEY . " down}")
    Sleep(100)
    SendInput("{" . BB_TELEPORT_HOTKEY . " up}")
    BB_updateStatusAndLog("Failed to open teleport menu via image, used hotkey " . BB_TELEPORT_HOTKEY)
    Sleep(1000)
    if BB_smartTemplateMatch("area_4_button", &FoundX, &FoundY) {
        BB_updateStatusAndLog("Teleport menu opened successfully via hotkey")
        return true
    }
    BB_updateStatusAndLog("Failed to open teleport menu", true)
    return false
}

BB_teleportToArea(areaTemplate) {
    global BB_currentArea
    FoundX := ""
    FoundY := ""
    if BB_smartTemplateMatch(areaTemplate, &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_currentArea := (areaTemplate = "area_4_button") ? "Area 4" : (areaTemplate = "area_5_button") ? "Area 5" : "Unknown"
        BB_updateStatusAndLog("Teleported to " . BB_currentArea)
        Sleep(2000)
        return true
    }
    BB_updateStatusAndLog("Failed to teleport to " . areaTemplate, true)
    return false
}

BB_interactWithMerchant() {
    global BB_merchantState
    FoundX := ""
    FoundY := ""
    if BB_smartTemplateMatch("mining_merchant", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_merchantState := "Interacted"
        BB_updateStatusAndLog("Interacting with merchant")
        Sleep(1000)
        return true
    }
    BB_merchantState := "Failed to Interact"
    BB_updateStatusAndLog("Failed to interact with merchant", true)
    return false
}

BB_buyMerchantItems() {
    global BB_MAX_BUY_ATTEMPTS, BB_merchantState
    FoundX := ""
    FoundY := ""
    if !BB_smartTemplateMatch("merchant_window", &FoundX, &FoundY) {
        BB_merchantState := "Window Not Detected"
        BB_updateStatusAndLog("Merchant window not detected", true)
        return false
    }
    
    searchArea := [FoundX, FoundY + 50, FoundX + 500, FoundY + 300]
    buyCount := 0
    while (buyCount < BB_MAX_BUY_ATTEMPTS) {
        FoundX := ""
        FoundY := ""
        if BB_smartTemplateMatch("buy_button", &FoundX, &FoundY, searchArea) {
            BB_clickAt(FoundX, FoundY)
            BB_updateStatusAndLog("Clicked buy button " . (buyCount + 1))
            buyCount++
            Sleep(500)
        } else {
            BB_updateStatusAndLog("No more buy buttons found after " . buyCount . " purchases")
            break
        }
    }
    BB_merchantState := "Items Purchased (" . buyCount . ")"
    return true
}

BB_enableAutomine() {
    FoundX := ""
    FoundY := ""
    BB_updateStatusAndLog("Attempting to enable automining...")
    
    ; First, check if automining is already on
    if BB_checkAutofarming() {
        BB_updateStatusAndLog("Automining is already enabled")
        return true
    }
    
    ; Try to find and click the automine button
    loop 3 {  ; Retry up to 3 times
        if BB_smartTemplateMatch("automine_button", &FoundX, &FoundY) {
            BB_clickAt(FoundX, FoundY)
            BB_updateStatusAndLog("Clicked automine button at x=" . FoundX . ", y=" . FoundY)
            Sleep(1000)
            
            ; Validate if automining is now on by checking for pixel movement
            regions := [
                [A_ScreenWidth//4, A_ScreenHeight//4],      ; Top-left
                [3*A_ScreenWidth//4, A_ScreenHeight//4],    ; Top-right
                [A_ScreenWidth//4, 3*A_ScreenHeight//4],    ; Bottom-left
                [3*A_ScreenWidth//4, 3*A_ScreenHeight//4]   ; Bottom-right
            ]
            
            initialColors := []
            for region in regions {
                color := PixelGetColor(region[1], region[2], "RGB")
                initialColors.Push(color)
            }
            
            Sleep(1000)  ; Wait 1 second to check for changes
            
            isMoving := false
            loop 3 {  ; Check multiple times to confirm
                for index, region in regions {
                    newColor := PixelGetColor(region[1], region[2], "RGB")
                    if (newColor != initialColors[index]) {
                        isMoving := true
                        break
                    }
                }
                if (isMoving) {
                    break
                }
                Sleep(500)
            }
            
            if (isMoving) {
                BB_updateStatusAndLog("Pixel movement detected after clicking, automining enabled successfully")
                global BB_isAutofarming := true
                return true
            } else {
                BB_updateStatusAndLog("No pixel movement detected after clicking, retrying...")
                Sleep(1000)
            }
        } else {
            BB_updateStatusAndLog("Info: 'automine_button' not found on attempt " . A_Index)
            Sleep(1000)
        }
    }
    
    BB_updateStatusAndLog("Failed to enable automining after 3 attempts")
    global BB_isAutofarming := false
    return false
}

; ===================== EXPLOSIVES FUNCTIONS =====================

BB_sendHotkeyWithDownUp(hotkey) {
    hwnd := WinGetID("A")
    if (!hwnd || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("No Roblox window active for hotkey: " . hotkey, true, true)
        return false
    }

    modifiers := ""
    key := hotkey
    if (InStr(hotkey, "^")) {
        modifiers .= "Ctrl "
        key := StrReplace(key, "^", "")
    }
    if (InStr(hotkey, "+")) {
        modifiers .= "Shift "
        key := StrReplace(key, "+", "")
    }
    if (InStr(hotkey, "!")) {
        modifiers .= "Alt "
        key := StrReplace(key, "!", "")
    }

    if (InStr(modifiers, "Ctrl")) {
        SendInput("{Ctrl down}")
    }
    if (InStr(modifiers, "Shift")) {
        SendInput("{Shift down}")
    }
    if (InStr(modifiers, "Alt")) {
        SendInput("{Alt down}")
    }

    SendInput("{" . key . " down}")
    Sleep(100)
    SendInput("{" . key . " up}")

    if (InStr(modifiers, "Alt")) {
        SendInput("{Alt up}")
    }
    if (InStr(modifiers, "Shift")) {
        SendInput("{Shift up}")
    }
    if (InStr(modifiers, "Ctrl")) {
        SendInput("{Ctrl up}")
    }
    Sleep(100)
    return true
}

BB_useBomb() {
    global BB_BOMB_HOTKEY, BB_lastBombStatus
    BB_sendHotkeyWithDownUp(BB_BOMB_HOTKEY)
    BB_lastBombStatus := "Used at " . A_Now
    BB_updateStatusAndLog("Used bomb with hotkey: " . BB_BOMB_HOTKEY)
    BB_checkForError()
}

BB_useTntCrate() {
    global BB_TNT_CRATE_HOTKEY, BB_lastTntCrateStatus
    BB_sendHotkeyWithDownUp(BB_TNT_CRATE_HOTKEY)
    BB_lastTntCrateStatus := "Used at " . A_Now
    BB_updateStatusAndLog("Used TNT crate with hotkey: " . BB_TNT_CRATE_HOTKEY)
    BB_checkForError()
}

BB_useTntBundle() {
    global BB_TNT_BUNDLE_HOTKEY, BB_lastTntBundleStatus
    BB_sendHotkeyWithDownUp(BB_TNT_BUNDLE_HOTKEY)
    BB_lastTntBundleStatus := "Used at " . A_Now
    BB_updateStatusAndLog("Used TNT bundle with hotkey: " . BB_TNT_BUNDLE_HOTKEY)
    BB_checkForError()
}

BB_bombLoop() {
    global BB_running, BB_paused, BB_ENABLE_EXPLOSIVES, BB_isAutofarming
    if (BB_running && !BB_paused && BB_ENABLE_EXPLOSIVES && BB_checkAutofarming()) {
        BB_useBomb()
    } else {
        BB_updateStatusAndLog("Bomb loop skipped (not running, paused, explosives off, or not autofarming)")
    }
}

BB_tntCrateLoop() {
    global BB_running, BB_paused, BB_ENABLE_EXPLOSIVES, BB_isAutofarming
    if (BB_running && !BB_paused && BB_ENABLE_EXPLOSIVES && BB_checkAutofarming()) {
        BB_useTntCrate()
    } else {
        BB_updateStatusAndLog("TNT crate loop skipped (not running, paused, explosives off, or not autofarming)")
    }
}

BB_tntBundleLoop() {
    global BB_running, BB_paused, BB_ENABLE_EXPLOSIVES, BB_isAutofarming
    if (BB_running && !BB_paused && BB_ENABLE_EXPLOSIVES && BB_checkAutofarming()) {
        BB_useTntBundle()
    } else {
        BB_updateStatusAndLog("TNT bundle loop skipped (not running, paused, explosives off, or not autofarming)")
    }
}

; ===================== STATE MACHINE AUTOMATION LOOP =====================

BB_miningAutomationLoop() {
    global BB_running, BB_paused, BB_automationState, BB_FAILED_INTERACTION_COUNT, BB_MAX_FAILED_INTERACTIONS
    global BB_currentArea, BB_merchantState, BB_isAutofarming, BB_CYCLE_INTERVAL, BB_ENABLE_EXPLOSIVES

    if (!BB_running || BB_paused) {
        BB_updateStatusAndLog("Automation loop skipped (not running or paused)")
        return
    }

    windows := BB_updateActiveWindows()
    if (windows.Length = 0) {
        BB_updateStatusAndLog("No Roblox windows found")
        return
    }

    BB_updateStatusAndLog("Starting automation cycle")
    for hwnd in windows {
        if (!BB_running || BB_paused) {
            BB_updateStatusAndLog("Automation loop interrupted")
            break
        }
        if !BB_robustWindowActivation(hwnd) {
            BB_FAILED_INTERACTION_COUNT++
            BB_updateStatusAndLog("Skipping window due to activation failure")
            continue
        }

        if BB_checkForError() {
            BB_setState("Error")
        }

        switch BB_automationState {
            case "Idle":
                BB_currentArea := "Area 5"
                if BB_checkAutofarming() {
                    BB_setState("DisableAutomine")
                } else {
                    BB_updateStatusAndLog("Autofarming not detected in Area 5, enabling it first")
                    BB_enableAutomine()
                }
            case "DisableAutomine":
                if BB_disableAutomine() {
                    BB_setState("TeleportToArea4")
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            case "TeleportToArea4":
                if BB_openTeleportMenu() && BB_teleportToArea("area_4_button") {
                    BB_setState("Shopping")
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            case "Shopping":
                if BB_interactWithMerchant() && BB_buyMerchantItems() {
                    SendInput("{Esc}")
                    Sleep(500)
                    BB_setState("TeleportToArea5")
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            case "TeleportToArea5":
                if BB_openTeleportMenu() && BB_teleportToArea("area_5_button") {
                    BB_setState("EnableAutomine")
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            case "EnableAutomine":
                if BB_enableAutomine() {
                    BB_setState("Mining")
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            case "Mining":
                BB_updateStatusAndLog("Mining in Area 5 for ~3 minutes")
                Sleep(180000)
                BB_setState("Idle")
            case "Error":
                if (BB_FAILED_INTERACTION_COUNT >= BB_MAX_FAILED_INTERACTIONS) {
                    BB_updateStatusAndLog("Too many failed interactions, stopping", true, true)
                    BB_stopAutomation()
                    return
                }
                BB_updateStatusAndLog("Recovering from error state")
                BB_setState("Idle")
        }
    }
}

; ===================== ANTI-AFK AND RECONNECT FUNCTIONS =====================

BB_reconnectCheckLoop() {
    global BB_running, BB_paused
    if (!BB_running || BB_paused)
        return
    windows := BB_updateActiveWindows()
    if (windows.Length = 0) {
        BB_updateStatusAndLog("No Roblox windows found, waiting for reconnect")
    }
}

; ===================== UTILITY FUNCTIONS =====================

BB_loadConfigFromFile(*) {
    BB_loadConfig()
    MsgBox("Configuration reloaded from " . BB_CONFIG_FILE)
}

BB_exitApp(*) {
    global BB_running
    BB_running := false
    SetTimer(BB_miningAutomationLoop, 0)
    SetTimer(BB_reconnectCheckLoop, 0)
    SetTimer(BB_bombLoop, 0)
    SetTimer(BB_tntCrateLoop, 0)
    SetTimer(BB_tntBundleLoop, 0)
    BB_updateStatusAndLog("Script terminated")
    ExitApp()
}

BB_smartTemplateMatch(templateName, &FoundX, &FoundY, searchArea := "") {
    global BB_TEMPLATES, BB_TEMPLATE_FOLDER, BB_TEMPLATE_RETRIES, BB_imageCache, BB_missingTemplatesReported
    
    if (!BB_TEMPLATES.Has(templateName)) {
        if (!BB_missingTemplatesReported.Has(templateName)) {
            BB_updateStatusAndLog("Template '" . templateName . "' not found in BB_TEMPLATES", true, true)
            BB_missingTemplatesReported[templateName] := true
        }
        return false
    }
    
    templateFile := BB_TEMPLATE_FOLDER . "\" . BB_TEMPLATES[templateName]
    if (!FileExist(templateFile)) {
        if (!BB_missingTemplatesReported.Has(templateName)) {
            BB_updateStatusAndLog("Template file not found: " . templateFile, true, true)
            BB_missingTemplatesReported[templateName] := true
        }
        return false
    }
    
    cacheKey := templateName . (searchArea ? StrJoin(searchArea, ",") : "")
    if (BB_imageCache.Has(cacheKey)) {
        cachedResult := BB_imageCache[cacheKey]
        if (cachedResult.success) {
            FoundX := cachedResult.x
            FoundY := cachedResult.y
            BB_updateStatusAndLog("Template '" . templateName . "' found in cache at x=" . FoundX . ", y=" . FoundY)
            return true
        }
        return false
    }
    
    if (!searchArea) {
        if (templateName = "automine_button") {
            ; Search a large area on the left side of the screen (based on 1920x1080 resolution)
            searchArea := [50, 300, 250, 600]
        } else if (templateName = "merchant_window") {
            ; Search the center-right of the screen for the merchant window
            searchArea := [A_ScreenWidth//2 - 200, A_ScreenHeight//2 - 200, A_ScreenWidth - 100, A_ScreenHeight//2 + 200]
        } else if (templateName = "error_message" || templateName = "error_message_alt1" || templateName = "connection_lost") {
            ; Search the center of the screen for error messages
            searchArea := [A_ScreenWidth//2 - 300, A_ScreenHeight//2 - 200, A_ScreenWidth//2 + 300, A_ScreenHeight//2 + 200]
        } else {
            ; Default to full screen for other templates
            searchArea := [0, 0, A_ScreenWidth, A_ScreenHeight]
        }
    }
    
    loop BB_TEMPLATE_RETRIES {
        try {
            BB_updateStatusAndLog("Searching for '" . templateName . "' in area [" . searchArea[1] . "," . searchArea[2] . "," . searchArea[3] . "," . searchArea[4] . "]")
            variation := (templateName = "automine_button") ? "*150" : "*75"
            if (ImageSearch(&FoundX, &FoundY, searchArea[1], searchArea[2], searchArea[3], searchArea[4], variation . " " . templateFile)) {
                BB_updateStatusAndLog("Template '" . templateName . "' found at x=" . FoundX . ", y=" . FoundY)
                BB_imageCache[cacheKey] := {success: true, x: FoundX, y: FoundY}
                return true
            }
        } catch as err {
            BB_updateStatusAndLog("ImageSearch failed for '" . templateName . "': " . err.Message, true, true)
        }
        Sleep(500)
    }
    
    BB_updateStatusAndLog("Template '" . templateName . "' not found after " . BB_TEMPLATE_RETRIES . " attempts", true)
    BB_imageCache[cacheKey] := {success: false}
    return false
}

; ===================== INITIALIZATION =====================

BB_setupGUI()
BB_loadConfig()
BB_checkForUpdates()

Hotkey("F1", BB_startAutomation)  ; Add F1 to start automation
Hotkey(BB_BOMB_HOTKEY, (*) => BB_useBomb())
Hotkey(BB_TNT_CRATE_HOTKEY, (*) => BB_useTntCrate())
Hotkey(BB_TNT_BUNDLE_HOTKEY, (*) => BB_useTntBundle())
BB_updateStatusAndLog("Explosives hotkeys bound successfully")
BB_updateStatusAndLog("Script initialized. Press F1 to start automation.")

TrayTip("Initialized! Press F1 to start.", "🐝 BeeBrained's PS99 Mining Event Macro", 0x10)
