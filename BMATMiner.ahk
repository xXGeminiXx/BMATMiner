#Requires AutoHotkey v2.0
; 🐝 BeeBrained's PS99 Mining Event Automation 🐝
; Last Updated: March 22, 2025
;
; == Testing Instructions ==
; 1. Ensure Roblox and Pet Simulator 99 are installed and running.
; 2. Place the script in a folder with write permissions (e.g., C:\Apps\Automation Stuff).
; 3. Run the script as administrator to ensure proper window activation.
; 4. Press F1 to start the automation. Use F2 to stop, P to pause/resume, F3 to toggle explosives, and Esc to exit.
; 5. Monitor the GUI and log file (mining_log.txt) for errors.
; 6. If templates fail to validate, ensure an internet connection and check the GitHub repository for the latest template files.
;
; == Known Issues ==
; - Template matching may fail if the game resolution or UI scaling changes. Adjust templates or confidence levels in BB_smartTemplateMatch if needed.
; - Window activation may fail on some systems. Ensure Roblox is not minimized and try running the script as administrator.
; - The script assumes the default Roblox hotkeys (e.g., 't' for teleport, 'f' for automine). Update the config if your hotkeys differ.
; - The reconnect feature in BB_resetGameState may not work if Roblox is not set up to handle URL launches. Manual intervention may be required.
; - Screenshot functionality is disabled (placeholder left in BB_updateStatusAndLog for future implementation).

; ===================== GLOBAL VARIABLES =====================
global BB_VERSION := "1.1.1"                  ; Script version
global BB_running := false                    ; Script running state
global BB_paused := false                     ; Script paused state
global BB_automationState := "Idle"           ; State machine: Idle, DisableAutomine, GoToTop, TeleportToArea4, Shopping, TeleportToArea5, EnableAutomine, Error
global BB_stateHistory := []                  ; Track state transitions for debugging
global BB_CLICK_DELAY_MAX := 1500             ; Maximum click delay (ms)
global BB_CLICK_DELAY_MIN := 500              ; Minimum click delay (ms)
global BB_INTERACTION_DURATION := 5000        ; Duration for interactions (ms)
global BB_CYCLE_INTERVAL := 60000             ; Interval between automation cycles (ms)
global BB_ENABLE_EXPLOSIVES := false          ; Explosives feature toggle
global BB_BOMB_INTERVAL := 10000              ; Bomb usage interval (ms)
global BB_TNT_CRATE_INTERVAL := 30000         ; TNT crate usage interval (ms)
global BB_TNT_BUNDLE_INTERVAL := 15000        ; TNT bundle usage interval (ms)
global BB_logFile := A_ScriptDir "\mining_log.txt"  ; Log file path
global BB_CONFIG_FILE := A_ScriptDir "\mining_config.ini"  ; Config file path
global BB_ENABLE_LOGGING := true              ; Logging toggle
global BB_TEMPLATE_FOLDER := A_ScriptDir "\mining_templates"  ; Use script directory with mining_templates subfolder
global BB_BACKUP_TEMPLATE_FOLDER := A_ScriptDir "\backup_templates"  ; Backup folder for templates
global BB_WINDOW_TITLE := "Pet Simulator 99"  ; Updated to match likely window title
global BB_EXCLUDED_TITLES := []               ; Titles to exclude from targeting
global BB_TEMPLATES := Map()                  ; Map of template names to filenames
global BB_missingTemplatesReported := Map()   ; Tracks reported missing templates
global BB_TEMPLATE_RETRIES := 3               ; Number of retries for template matching
global BB_FAILED_INTERACTION_COUNT := 0       ; Count of consecutive failed interactions
global BB_MAX_FAILED_INTERACTIONS := 5        ; Max failed interactions before stopping
global BB_ANTI_AFK_INTERVAL := 300000         ; Anti-AFK interval (ms)
global BB_RECONNECT_CHECK_INTERVAL := 10000   ; Reconnect check interval (ms)
global BB_active_windows := []                ; List of active Roblox windows
global BB_last_window_check := 0              ; Timestamp of last window check
global BB_myGUI := ""                         ; GUI object
global BB_BOMB_HOTKEY := "^b"                 ; Hotkey for bombs (Ctrl+B)
global BB_TNT_CRATE_HOTKEY := "^t"            ; Hotkey for TNT crates (Ctrl+T)
global BB_TNT_BUNDLE_HOTKEY := "^n"           ; Hotkey for TNT bundles (Ctrl+N)
global BB_TELEPORT_HOTKEY := "t"              ; Hotkey for teleport menu
global BB_MAX_BUY_ATTEMPTS := 6               ; Maximum number of buy buttons to click
global BB_isAutofarming := false              ; Tracks autofarm state
global BB_lastBombStatus := "Idle"            ; Tracks last bomb usage
global BB_lastTntCrateStatus := "Idle"        ; Tracks last TNT crate usage
global BB_lastTntBundleStatus := "Idle"       ; Tracks last TNT bundle usage
global BB_currentArea := "Unknown"            ; Tracks current game area
global BB_merchantState := "Not Interacted"   ; Tracks merchant interaction state
global BB_lastError := "None"                 ; Tracks last error message
global BB_validTemplates := 0                 ; Tracks number of valid templates
global BB_totalTemplates := 0                 ; Tracks total number of templates
global BB_SAFE_MODE := false                  ; Safe mode for testing
global BB_imageCache := Map()                 ; Cache for image search results
global BB_performanceData := Map()            ; Track operation times for adaptive timing

; ===================== DEFAULT CONFIGURATION =====================

defaultIni := "
(
[Timing]
INTERACTION_DURATION=5000
CYCLE_INTERVAL=60000
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
go_to_top_button=go_to_top_button.png
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
    global BB_automationState, BB_stateHistory
    BB_stateHistory.Push({state: BB_automationState, time: A_Now})
    if (BB_stateHistory.Length > 10)
        BB_stateHistory.RemoveAt(1)
    BB_automationState := newState
    BB_updateStatusAndLog("State changed: " . newState)
}

BB_updateStatusAndLog(message, updateGUI := true, isError := false, takeScreenshot := false) {
    global BB_ENABLE_LOGGING, BB_logFile, BB_myGUI, BB_isAutofarming, BB_currentArea, BB_merchantState, BB_lastError
    global BB_lastBombStatus, BB_lastTntCrateStatus, BB_lastTntBundleStatus, BB_validTemplates, BB_totalTemplates
    if BB_ENABLE_LOGGING {
        timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        logMessage := "[" . timestamp . "] " . (isError ? "ERROR: " : "") . message . "`n"
        FileAppend(logMessage, BB_logFile)
    }
    if isError
        BB_lastError := message
    ; if takeScreenshot {
    ;     ; Placeholder for screenshot functionality (GDI+ removed as per user request)
    ;     ; BB_takeScreenshot()
    ; }
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
    if !FileExist(filePath)
        return "File does not exist"
    
    ; Extract the extension including the dot and convert to lowercase
    ext := StrLower(SubStr(filePath, -4)) ; Extract last 5 characters (e.g., ".png")
    if (ext != ".png")
        return "Invalid extension: " . ext . " (expected .png)"
    
    try {
        fileSize := FileGetSize(filePath)
        if (fileSize < 100)
            return "File too small: " . fileSize . " bytes (minimum 100 bytes)"
    } catch as err {
        return "Failed to get file size: " . err.Message
    }
    
    try {
        file := FileOpen(filePath, "r")
        header := file.Read(8)
        file.Close()
        if (header != Chr(0x89) . "PNG" . Chr(0x0D) . Chr(0x0A) . Chr(0x1A) . Chr(0x0A))
            return "Invalid PNG header"
    } catch as err {
        return "Failed to read PNG header: " . err.Message
    }
    
    return "Valid"
}

BB_downloadTemplate(templateName, fileName) {
    global BB_TEMPLATE_FOLDER, BB_BACKUP_TEMPLATE_FOLDER, BB_validTemplates, BB_totalTemplates
    BB_totalTemplates++
    templateUrl := "https://raw.githubusercontent.com/xXGeminiXx/BMATMiner/main/mining_templates/" . fileName
    localPath := BB_TEMPLATE_FOLDER . "\" . fileName
    backupPath := BB_BACKUP_TEMPLATE_FOLDER . "\" . fileName
    
    ; Function to download with status code checking
    downloadWithStatus(url, dest) {
        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.Open("GET", url, false)
            http.Send()
            if (http.Status != 200) {
                throw Error("HTTP status " . http.Status . " received")
            }
            file := FileOpen(dest, "w")
            file.RawWrite(http.ResponseBody)
            file.Close()
            return true
        } catch as err {
            throw Error("Download failed: " . err.Message)
        }
    }
    
    if !FileExist(localPath) {
        try {
            downloadWithStatus(templateUrl, localPath)
            validationResult := BB_validateImage(localPath)
            if (validationResult = "Valid") {
                BB_validTemplates++
                BB_updateStatusAndLog("Downloaded and validated template: " . fileName)
            } else {
                BB_updateStatusAndLog("Template " . fileName . " validation failed: " . validationResult, true, true)
                FileDelete(localPath)
                if FileExist(backupPath) {
                    FileCopy(backupPath, localPath, 1)
                    validationResult := BB_validateImage(localPath)
                    if (validationResult = "Valid") {
                        BB_validTemplates++
                        BB_updateStatusAndLog("Using backup template for " . fileName)
                    } else {
                        BB_updateStatusAndLog("Backup template invalid: " . validationResult, true, true)
                        FileDelete(localPath)
                    }
                }
            }
        } catch as err {
            BB_updateStatusAndLog("Failed to download " . fileName . ": " . err.Message, true, true)
            if FileExist(backupPath) {
                FileCopy(backupPath, localPath, 1)
                validationResult := BB_validateImage(localPath)
                if (validationResult = "Valid") {
                    BB_validTemplates++
                    BB_updateStatusAndLog("Using backup template for " . fileName)
                } else {
                    BB_updateStatusAndLog("Backup template invalid: " . validationResult, true, true)
                    FileDelete(localPath)
                }
            } else {
                BB_updateStatusAndLog("No backup available for " . fileName . ". Please ensure the template exists locally or at the download URL.", true, true)
            }
        }
    } else {
        validationResult := BB_validateImage(localPath)
        if (validationResult = "Valid") {
            BB_validTemplates++
            BB_updateStatusAndLog("Template already exists and is valid: " . fileName)
        } else {
            BB_updateStatusAndLog("Existing template invalid: " . validationResult . " - Redownloading", true, true)
            FileDelete(localPath)
            BB_downloadTemplate(templateName, fileName)  ; Recursive call to redownload
        }
    }
}

BB_robustWindowActivation(hwnd) {
    methods := [
        {name: "Standard Activation", fn: () => WinActivate(hwnd)},
        {name: "Focus Control", fn: () => ControlFocus("", hwnd)},
        {name: "Alt-Tab Sequence", fn: () => (SendInput("{Alt down}{Tab}{Tab}{Alt up}"), Sleep(300))}
    ]
    for method in methods {
        try {
            startTime := A_TickCount
            method.fn()
            if WinWaitActive("ahk_id " . hwnd, , 2) {
                elapsed := A_TickCount - startTime
                BB_performanceData[method.name] := BB_performanceData.Has(method.name) ? (BB_performanceData[method.name] + elapsed) / 2 : elapsed
                BB_updateStatusAndLog("Window activated using " . method.name . " (" . elapsed . "ms)")
                return true
            }
        } catch as err {
            BB_updateStatusAndLog("Activation method failed: " . method.name . " - " . err.Message, true)
            Sleep(500)
            continue
        }
    }
    BB_updateStatusAndLog("All window activation methods failed", true, true)
    return false
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

BB_smartTemplateMatch(templateName, &FoundX, &FoundY, searchArea := "") {
    global BB_TEMPLATE_FOLDER, BB_TEMPLATES, BB_TEMPLATE_RETRIES, BB_missingTemplatesReported, BB_imageCache, BB_performanceData
    cacheKey := templateName . (searchArea ? "_" . StrJoin(searchArea, "_") : "")
    if BB_imageCache.Has(cacheKey) {
        coords := BB_imageCache[cacheKey]
        FoundX := coords.x
        FoundY := coords.y
        BB_updateStatusAndLog("Used cached coordinates for " . templateName)
        return true
    }
    templatePath := BB_TEMPLATE_FOLDER . "\" . BB_TEMPLATES[templateName]
    validationResult := BB_validateImage(templatePath)
    if (validationResult != "Valid") {
        if !BB_missingTemplatesReported.Has(templateName) {
            BB_updateStatusAndLog("Template validation failed for " . templateName . ": " . validationResult . " (Path: " . templatePath . ")", true, true)
            BB_missingTemplatesReported[templateName] := true
        }
        return false
    }
    confidenceLevels := [10, 20, 30, 40]
    for confidence in confidenceLevels {
        retryCount := 0
        while (retryCount < BB_TEMPLATE_RETRIES) {
            try {
                startTime := A_TickCount
                fileSize := FileGetSize(templatePath)
                screenRes := A_ScreenWidth . "x" . A_ScreenHeight
                if searchArea != "" {
                    BB_updateStatusAndLog("Searching for " . templateName . " in area: " . searchArea[1] . "," . searchArea[2] . " to " . searchArea[3] . "," . searchArea[4] . " (Size: " . fileSize . " bytes, Screen: " . screenRes . ")")
                    ImageSearch(&FoundX, &FoundY, searchArea[1], searchArea[2], searchArea[3], searchArea[4], "*" . confidence . " " . templatePath)
                } else {
                    BB_updateStatusAndLog("Searching for " . templateName . " on entire screen (Size: " . fileSize . " bytes, Screen: " . screenRes . ")")
                    ImageSearch(&FoundX, &FoundY, 0, 0, A_ScreenWidth, A_ScreenHeight, "*" . confidence . " " . templatePath)
                }
                if (FoundX != "" && FoundY != "") {
                    elapsed := A_TickCount - startTime
                    BB_performanceData["ImageSearch_" . templateName] := BB_performanceData.Has("ImageSearch_" . templateName) ? (BB_performanceData["ImageSearch_" . templateName] + elapsed) / 2 : elapsed
                    BB_imageCache[cacheKey] := {x: FoundX, y: FoundY}
                    BB_updateStatusAndLog("Found " . templateName . " at x=" . FoundX . ", y=" . FoundY . " with confidence " . confidence . " (attempt " . (retryCount + 1) . ", " . elapsed . "ms)")
                    return true
                }
            } catch as err {
                BB_updateStatusAndLog("ImageSearch failed for " . templateName . ": " . err.Message . " (attempt " . (retryCount + 1) . ")", true, true)
            }
            retryCount++
            Sleep(500)
        }
    }
    variantNames := [templateName . "_alt1", templateName . "_alt2"]
    for variant in variantNames {
        if BB_TEMPLATES.Has(variant) {
            retryCount := 0
            while (retryCount < BB_TEMPLATE_RETRIES) {
                try {
                    startTime := A_TickCount
                    templatePath := BB_TEMPLATE_FOLDER . "\" . BB_TEMPLATES[variant]
                    if searchArea != ""
                        ImageSearch(&FoundX, &FoundY, searchArea[1], searchArea[2], searchArea[3], searchArea[4], "*20 " . templatePath)
                    else
                        ImageSearch(&FoundX, &FoundY, 0, 0, A_ScreenWidth, A_ScreenHeight, "*20 " . templatePath)
                    if (FoundX != "" && FoundY != "") {
                        elapsed := A_TickCount - startTime
                        BB_performanceData["ImageSearch_" . variant] := BB_performanceData.Has("ImageSearch_" . variant) ? (BB_performanceData["ImageSearch_" . variant] + elapsed) / 2 : elapsed
                        BB_imageCache[cacheKey] := {x: FoundX, y: FoundY}
                        BB_updateStatusAndLog("Found " . templateName . " using variant " . variant . " at x=" . FoundX . ", y=" . FoundY . " (attempt " . (retryCount + 1) . ", " . elapsed . "ms)")
                        return true
                    }
                } catch as err {
                    BB_updateStatusAndLog("ImageSearch failed for variant " . variant . ": " . err.Message . " (attempt " . (retryCount + 1) . ")", true, true)
                }
                retryCount++
                Sleep(500)
            }
        }
    }
    BB_updateStatusAndLog("Failed to find " . templateName . " after " . BB_TEMPLATE_RETRIES . " retries", true, true)
    return false
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

    ; Ensure folders exist
    if !DirExist(BB_TEMPLATE_FOLDER)
        DirCreate(BB_TEMPLATE_FOLDER)
    if !DirExist(BB_BACKUP_TEMPLATE_FOLDER)
        DirCreate(BB_BACKUP_TEMPLATE_FOLDER)

    ; Reset template counters
    BB_validTemplates := 0
    BB_totalTemplates := 0

    ; Download templates
    for templateName, fileName in Map(
        "automine_button", "automine_button.png",
        "go_to_top_button", "go_to_top_button.png",
        "teleport_button", "teleport_button.png",
        "area_4_button", "area_4_button.png",
        "area_5_button", "area_5_button.png",
        "mining_merchant", "mining_merchant.png",
        "buy_button", "buy_button.png",
        "merchant_window", "merchant_window.png",
        "autofarm_on", "autofarm_on.png",
        "autofarm_off", "autofarm_off.png",
        "error_message", "error_message.png",
        "error_message_alt1", "error_message_alt1.png",
        "connection_lost", "connection_lost.png"
    ) {
        BB_downloadTemplate(templateName, fileName)
        BB_TEMPLATES[templateName] := fileName
    }

    BB_updateStatusAndLog("Template validation summary: " . BB_validTemplates . "/" . BB_totalTemplates . " templates are valid")

    ; Load other settings
    BB_INTERACTION_DURATION := IniRead(BB_CONFIG_FILE, "Timing", "INTERACTION_DURATION", 5000)
    BB_CYCLE_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "CYCLE_INTERVAL", 60000)
    BB_CLICK_DELAY_MIN := IniRead(BB_CONFIG_FILE, "Timing", "CLICK_DELAY_MIN", 500)
    BB_CLICK_DELAY_MAX := IniRead(BB_CONFIG_FILE, "Timing", "CLICK_DELAY_MAX", 1500)
    BB_ANTI_AFK_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "ANTI_AFK_INTERVAL", 300000)
    BB_RECONNECT_CHECK_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "RECONNECT_CHECK_INTERVAL", 10000)
    BB_BOMB_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "BOMB_INTERVAL", 10000)
    BB_TNT_CRATE_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "TNT_CRATE_INTERVAL", 30000)
    BB_TNT_BUNDLE_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "TNT_BUNDLE_INTERVAL", 15000)

    ; Adaptive timing adjustment based on performance data
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
    BB_myGUI := Gui("+AlwaysOnTop", "🐝 BeeBrained’s PS99 Mining Event Macro v" . BB_VERSION . " 🐝")
    BB_myGUI.OnEvent("Close", BB_exitApp)
    
    ; Header
    BB_myGUI.Add("Text", "x10 y10 w400 h20 Center", "🐝 BeeBrained’s PS99 Mining Event Macro v" . BB_VERSION . " 🐝")
    hotkeyText := "Hotkeys: F1 (Start) | F2 (Stop) | P (Pause) | F3 (Explosives) | Esc (Exit)"
    hotkeyText .= " | " . BB_BOMB_HOTKEY . " (Bomb) | " . BB_TNT_CRATE_HOTKEY . " (TNT Crate) | " . BB_TNT_BUNDLE_HOTKEY . " (TNT Bundle)"
    BB_myGUI.Add("Text", "x10 y30 w400 h20 Center", hotkeyText)
    
    ; Script Status Section
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
    
    ; Game State Section
    BB_myGUI.Add("GroupBox", "x10 y190 w400 h80", "Game State")
    BB_myGUI.Add("Text", "x20 y210 w180 h20", "Current Area:")
    BB_myGUI.Add("Text", "x200 y210 w200 h20", "Unknown").Name := "CurrentArea"
    BB_myGUI.Add("Text", "x20 y230 w180 h20", "Merchant Interaction:")
    BB_myGUI.Add("Text", "x200 y230 w200 h20", "Not Interacted").Name := "MerchantState"
    
    ; Explosives Status Section
    BB_myGUI.Add("GroupBox", "x10 y280 w400 h80", "Explosives Status")
    BB_myGUI.Add("Text", "x20 y300 w180 h20", "Bomb:")
    BB_myGUI.Add("Text", "x200 y300 w200 h20", "Idle").Name := "BombStatus"
    BB_myGUI.Add("Text", "x20 y320 w180 h20", "TNT Crate:")
    BB_myGUI.Add("Text", "x200 y320 w200 h20", "Idle").Name := "TntCrateStatus"
    BB_myGUI.Add("Text", "x20 y340 w180 h20", "TNT Bundle:")
    BB_myGUI.Add("Text", "x200 y340 w200 h20", "Idle").Name := "TntBundleStatus"
    
    ; Last Action/Error Section
    BB_myGUI.Add("GroupBox", "x10 y370 w400 h100", "Last Action/Error")
    BB_myGUI.Add("Text", "x20 y390 w180 h20", "Last Action:")
    BB_myGUI.Add("Text", "x200 y390 w200 h40 Wrap", "None").Name := "LastAction"
    BB_myGUI.Add("Text", "x20 y430 w180 h20", "Last Error:")
    BB_myGUI.Add("Text", "x200 y430 w200 h40 Wrap cRed", "None").Name := "LastError"
    
    ; Buttons
    BB_myGUI.Add("Button", "x10 y480 w120 h30", "Reload Config").OnEvent("Click", BB_loadConfigFromFile)
    BB_myGUI.Add("Button", "x290 y480 w120 h30", "Clear Log").OnEvent("Click", BB_clearLog)
    
    BB_myGUI.Show("x0 y0 w420 h520")
}

; ===================== HOTKEYS =====================

Hotkey("F1", BB_startAutomation)
Hotkey("F2", BB_stopAutomation)
Hotkey("p", BB_togglePause)
Hotkey("F3", BB_toggleExplosives)
Hotkey("Esc", BB_exitApp)

; ===================== CORE FUNCTIONS =====================

BB_startAutomation(*) {
    global BB_running, BB_paused, BB_currentArea, BB_automationState, BB_SAFE_MODE
    if BB_running {
        BB_updateStatusAndLog("Already running, ignoring F1 press")
        return
    }
    if BB_SAFE_MODE {
        BB_updateStatusAndLog("Running in safe mode - limited functionality")
    }
    BB_running := true
    BB_paused := false
    BB_currentArea := "Unknown"
    BB_automationState := "Idle"
    BB_updateStatusAndLog("Running - Starting Mining Automation")
    SetTimer(BB_antiAFKLoop, BB_ANTI_AFK_INTERVAL)
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
    BB_miningAutomationLoop()  ; Run the first cycle immediately
    SetTimer(BB_miningAutomationLoop, 1000)
}

BB_stopAutomation(*) {
    global BB_running, BB_paused, BB_currentArea, BB_merchantState, BB_automationState
    BB_running := false
    BB_paused := false
    BB_currentArea := "Unknown"
    BB_merchantState := "Not Interacted"
    BB_automationState := "Idle"
    SetTimer(BB_miningAutomationLoop, 0)
    SetTimer(BB_antiAFKLoop, 0)
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
    activeHwnd := WinGetID("A")  ; Get the currently active window
    windows := WinGetList("ahk_exe RobloxPlayerBeta.exe")
    
    for hwnd in windows {
        try {
            title := WinGetTitle(hwnd)
            processName := WinGetProcessName(hwnd)
            if (processName != "RobloxPlayerBeta.exe") {
                BB_updateStatusAndLog("Skipped window: " . title . " (process: " . processName . ")")
                continue
            }
            if (!InStr(title, BB_WINDOW_TITLE) || BB_hasExcludedTitle(title)) {
                BB_updateStatusAndLog("Skipped window: " . title . " (does not match criteria)")
                continue
            }
            
            ; Add the window to the list, prioritizing the active window
            BB_active_windows.Push(hwnd)
            BB_updateStatusAndLog("Found Roblox window: " . title . " (hwnd: " . hwnd . ", process: " . processName . ") (active: " . (hwnd = activeHwnd ? "Yes" : "No") . ")")
        } catch as err {
            BB_updateStatusAndLog("Error checking window " . hwnd . ": " . err.Message, true, true)
        }
    }
    
    ; Sort windows to prioritize the active one
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
    FoundX := "", FoundY := ""
    errorTypes := ["error_message", "error_message_alt1", "connection_lost"]
    errorDetected := false
    errorType := ""
    
    ; Check for errors on screen
    for type in errorTypes {
        if BB_smartTemplateMatch(type, &FoundX, &FoundY) {
            errorDetected := true
            errorType := type
            break
        }
    }

    if errorDetected {
        BB_updateStatusAndLog("Error detected (" . errorType . ")", true, true, true)  ; Take screenshot on error
        
        ; Define recovery actions for each state
        errorActions := Map(
            "DisableAutomine", () => (SendInput("{f down}"), Sleep(100), SendInput("{f up}"), Sleep(500), BB_checkAutofarming()),
            "GoToTop", () => (SendInput("{f down}"), Sleep(100), SendInput("{f up}"), Sleep(500), BB_goToTop()),
            "TeleportToArea4", () => (SendInput("{Esc}"), Sleep(500), SendInput("{" . BB_TELEPORT_HOTKEY . "}"), Sleep(1000), BB_openTeleportMenu()),
            "Shopping", () => (SendInput("{Esc}"), Sleep(500), BB_interactWithMerchant()),
            "TeleportToArea5", () => (SendInput("{Esc}"), Sleep(500), SendInput("{" . BB_TELEPORT_HOTKEY . "}"), Sleep(1000), BB_openTeleportMenu()),
            "EnableAutomine", () => (SendInput("{f down}"), Sleep(100), SendInput("{f up}"), Sleep(500), BB_checkAutofarming()),
            "Idle", () => (SendInput("{Space down}"), Sleep(100), SendInput("{Space up}"), Sleep(500))
        )

        ; Execute the recovery action
        action := errorActions.Has(BB_automationState) ? errorActions[BB_automationState] : errorActions["Idle"]
        actionResult := action()
        
        ; Log the recovery attempt
        BB_updateStatusAndLog("Attempted recovery from error in state " . BB_automationState . " (Result: " . (actionResult ? "Success" : "Failed") . ")")
        
        ; Increment failure count and check if we should stop
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
    
    return false
}

BB_resetGameState() {
    global BB_currentArea, BB_merchantState, BB_isAutofarming, BB_automationState, BB_FAILED_INTERACTION_COUNT
    BB_updateStatusAndLog("Attempting to reset game state")
    
    ; Close the game (if possible) and reopen it
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
    
    ; Wait for the game to close
    Sleep(5000)
    
    ; Attempt to reopen Roblox (assuming the user has a shortcut or URL handler)
    try {
        Run("roblox://placeId=8737890210")  ; Replace with actual PS99 game link if different
        BB_updateStatusAndLog("Attempted to reopen Pet Simulator 99")
    } catch as err {
        BB_updateStatusAndLog("Failed to reopen Roblox: " . err.Message, true, true)
        return false
    }
    
    ; Wait for the game to load
    Sleep(30000)  ; Adjust based on typical load time
    
    ; Reset script state
    BB_currentArea := "Unknown"
    BB_merchantState := "Not Interacted"
    BB_isAutofarming := false
    BB_automationState := "Idle"
    BB_FAILED_INTERACTION_COUNT := 0
    
    ; Check if the game reopened successfully
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
        tempFile := A_Temp . "\bb_version.txt"
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.Open("GET", versionUrl, false)
        http.Send()
        if (http.Status != 200) {
            throw Error("HTTP status " . http.Status . " received")
        }
        file := FileOpen(tempFile, "w")
        file.Write(http.ResponseText)
        file.Close()
        latestVersion := Trim(FileRead(tempFile))
        FileDelete(tempFile)
        ; Validate version format (e.g., expecting something like "1.0.1")
        if (!RegExMatch(latestVersion, "^\d+\.\d+\.\d+$")) {
            throw Error("Invalid version format: " . latestVersion)
        }
        if (latestVersion != BB_VERSION) {
            BB_updateStatusAndLog("New version available: " . latestVersion . " (current: " . BB_VERSION . ")")
            MsgBox("A new version (" . latestVersion . ") is available! Please update the script.", "Update Available", 0x40)
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
    FoundX := "", FoundY := ""
    
    if BB_smartTemplateMatch("autofarm_on", &FoundX, &FoundY) {
        BB_updateStatusAndLog("Autofarm is ON (green circle detected)")
        BB_isAutofarming := true
        return true
    }
    
    if BB_smartTemplateMatch("autofarm_off", &FoundX, &FoundY) {
        BB_updateStatusAndLog("Autofarm is OFF (red circle detected)")
        BB_isAutofarming := false
        return false
    }
    
    BB_updateStatusAndLog("Could not determine autofarm state")
    return BB_isAutofarming
}

BB_disableAutomine() {
    FoundX := "", FoundY := ""
    if BB_smartTemplateMatch("automine_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Disabled automining")
        Sleep(1000)
        return true
    }
    BB_updateStatusAndLog("Failed to disable automining", true)
    return false
}

BB_goToTop() {
    FoundX := "", FoundY := ""
    if BB_smartTemplateMatch("go_to_top_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Clicked Go to Top")
        Sleep(2000)
        return true
    }
    BB_updateStatusAndLog("Failed to go to top", true)
    return false
}

BB_openTeleportMenu() {
    global BB_TELEPORT_HOTKEY
    FoundX := "", FoundY := ""
    if BB_smartTemplateMatch("teleport_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Opened teleport menu")
        Sleep(1000)
        return true
    }
    ; Fallback to keyboard shortcut
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
    FoundX := "", FoundY := ""
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
    FoundX := "", FoundY := ""
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
    FoundX := "", FoundY := ""
    if !BB_smartTemplateMatch("merchant_window", &FoundX, &FoundY) {
        BB_merchantState := "Window Not Detected"
        BB_updateStatusAndLog("Merchant window not detected", true)
        return false
    }
    
    searchArea := [FoundX, FoundY + 50, FoundX + 500, FoundY + 300]
    buyCount := 0
    while (buyCount < BB_MAX_BUY_ATTEMPTS) {
        FoundX := "", FoundY := ""
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
    FoundX := "", FoundY := ""
    if BB_smartTemplateMatch("automine_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Enabled automining")
        Sleep(1000)
        return true
    }
    BB_updateStatusAndLog("Failed to enable automining", true)
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
    global BB_currentArea, BB_merchantState, BB_isAutofarming, BB_SAFE_MODE
    static wasAutofarming := false
    static skippedActions := []

    if (!BB_running || BB_paused) {
        BB_updateStatusAndLog("Automation loop skipped (not running or paused)")
        return
    }

    windows := BB_updateActiveWindows()
    if (windows.Length = 0) {
        BB_updateStatusAndLog("No Roblox windows found")
        return
    }

    BB_updateStatusAndLog("Starting automation cycle (" . windows.Length . " windows)")
    for hwnd in windows {
        if (!BB_running || BB_paused) {
            BB_updateStatusAndLog("Automation loop interrupted")
            break
        }
        BB_updateStatusAndLog("Processing window: " . hwnd)
        if !BB_robustWindowActivation(hwnd) {
            BB_FAILED_INTERACTION_COUNT++
            BB_updateStatusAndLog("Skipping window due to activation failure")
            continue
        }

        ; Reset skipped actions for this cycle
        if BB_SAFE_MODE
            skippedActions := []

        ; Check for errors before proceeding
        if BB_checkForError() {
            BB_setState("Error")
        }

        switch BB_automationState {
            case "Idle":
                Sleep(IniRead(BB_CONFIG_FILE, "Timing", "CYCLE_INTERVAL", 60000))
                wasAutofarming := BB_checkAutofarming()
                if wasAutofarming {
                    BB_updateStatusAndLog("Autofarming detected, proceeding to disable automine")
                    BB_setState("DisableAutomine")
                } else {
                    BB_updateStatusAndLog("Not autofarming, proceeding to merchant steps")
                    BB_setState("TeleportToArea4")
                }
            case "DisableAutomine":
                if BB_SAFE_MODE {
                    BB_updateStatusAndLog("Safe mode: Skipping automine disable")
                    skippedActions.Push("DisableAutomine")
                    BB_setState("GoToTop")
                    continue
                }
                if BB_disableAutomine() {
                    BB_setState("GoToTop")
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            case "GoToTop":
                if BB_SAFE_MODE {
                    BB_updateStatusAndLog("Safe mode: Skipping go to top")
                    skippedActions.Push("GoToTop")
                    BB_setState("TeleportToArea4")
                    continue
                }
                if BB_goToTop() {
                    BB_setState("TeleportToArea4")
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            case "TeleportToArea4":
                if BB_openTeleportMenu() {
                    if BB_teleportToArea("area_4_button") {
                        BB_setState("Shopping")
                    } else {
                        BB_FAILED_INTERACTION_COUNT++
                        BB_setState("Error")
                    }
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            case "Shopping":
                if BB_SAFE_MODE {
                    BB_updateStatusAndLog("Safe mode: Skipping merchant interaction")
                    skippedActions.Push("Shopping")
                    BB_setState("TeleportToArea5")
                    continue
                }
                if BB_interactWithMerchant() {
                    if BB_buyMerchantItems() {
                        BB_setState("TeleportToArea5")
                    } else {
                        BB_FAILED_INTERACTION_COUNT++
                        BB_setState("Error")
                    }
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            case "TeleportToArea5":
                if BB_openTeleportMenu() {
                    if BB_teleportToArea("area_5_button") {
                        BB_setState(wasAutofarming ? "EnableAutomine" : "Idle")
                    } else {
                        BB_FAILED_INTERACTION_COUNT++
                        BB_setState("Error")
                    }
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            case "EnableAutomine":
                if BB_SAFE_MODE {
                    BB_updateStatusAndLog("Safe mode: Skipping automine enable")
                    skippedActions.Push("EnableAutomine")
                    BB_setState("Idle")
                    continue
                }
                if BB_enableAutomine() {
                    BB_setState("Idle")
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            case "Error":
                if (BB_FAILED_INTERACTION_COUNT >= BB_MAX_FAILED_INTERACTIONS) {
                    BB_updateStatusAndLog("Too many failed interactions (" . BB_FAILED_INTERACTION_COUNT . "), stopping", true, true)
                    BB_stopAutomation()
                    return
                }
                BB_updateStatusAndLog("Recovering from error state")
                BB_setState("Idle")
        }

        if BB_automationState = "Idle" {
            BB_updateStatusAndLog("Cycle completed for window: " . hwnd)
            if BB_SAFE_MODE && skippedActions.Length > 0 {
                BB_updateStatusAndLog("Safe mode summary: Skipped actions - " . StrJoin(skippedActions, ", "))
            }
            BB_FAILED_INTERACTION_COUNT := 0
        }
    }
}

; ===================== ANTI-AFK AND RECONNECT FUNCTIONS =====================

BB_antiAFKLoop() {
    global BB_running, BB_paused
    if (!BB_running || BB_paused)
        return
    SendInput("{Space down}")
    Sleep(100)
    SendInput("{Space up}")
    BB_updateStatusAndLog("Anti-AFK: Pressed space")
}

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
    SetTimer(BB_antiAFKLoop, 0)
    SetTimer(BB_reconnectCheckLoop, 0)
    SetTimer(BB_bombLoop, 0)
    SetTimer(BB_tntCrateLoop, 0)
    SetTimer(BB_tntBundleLoop, 0)
    BB_updateStatusAndLog("Script terminated")
    ExitApp()
}

; ===================== INITIALIZATION =====================

BB_setupGUI()
BB_loadConfig()
BB_checkForUpdates()

; Bind explosives hotkeys after functions are defined
try {
    Hotkey(BB_BOMB_HOTKEY, BB_useBomb)
    Hotkey(BB_TNT_CRATE_HOTKEY, BB_useTntCrate)
    Hotkey(BB_TNT_BUNDLE_HOTKEY, BB_useTntBundle)
    BB_updateStatusAndLog("Explosives hotkeys bound successfully")
} catch as err {
    BB_updateStatusAndLog("Failed to bind explosives hotkeys: " . err.Message, true, true)
}

TrayTip("Ready! Press F1 to start.", "🐝 BeeBrained's PS99 Mining Event Macro", 0x10)
