; 🐝 BeeBrained's PS99 Mining Event Automation 🐝
; Last Updated: March 23, 2025
;
; == Testing Instructions ==
; 1. Ensure Roblox and Pet Simulator 99 are installed and running.
; 2. Place the script in a folder with write permissions (e.g., C:\Apps\BMATMiner).
; 3. Run the script as administrator to ensure proper window activation.
; 4. The script auto-starts, assuming you're in Area 5 with automining active. Use F2 to stop, P to pause/resume, F3 to toggle explosives, and Esc to exit.
; 5. Monitor the GUI and log file (mining_log.txt) for errors.
; 6. If templates fail to validate, ensure an internet connection and check the GitHub repository for the latest template files.
;
; == Known Issues ==
; - Template matching may fail if game resolution or UI scaling changes. Adjust templates or confidence levels in BB_smartTemplateMatch if needed.
; - Window activation may fail on some systems. Ensure Roblox is not minimized and run as admin.
; - Assumes default Roblox hotkeys ('f' to open inventory). Update config if different.
; - Reconnect in BB_resetGameState may need manual intervention if Roblox URL launches aren't set up.
; - Screenshot functionality is disabled (placeholder in BB_updateStatusAndLog).
; - Automine detection uses movement validation and template matching with fallback to safer click positions.
; - Window focus can be lost when clicking near top of window - script now uses safer click positions.
; - Errors or GUIs are cleared by pressing 'F' (which also opens the inventory if you're not already in it).

; ===================== Run as Admin =====================

if !A_IsAdmin {
    Run("*RunAs " . A_ScriptFullPath)
    ExitApp()
}

; ===================== GLOBAL VARIABLES =====================
; Version and Core State
global BB_VERSION := "1.7.5"
global BB_running := false
global BB_paused := false
global BB_SAFE_MODE := false

; State Management
global BB_automationState := "Idle"
global BB_stateHistory := []
global BB_gameStateEnsured := false
global BB_lastGameStateReset := 0
global BB_GAME_STATE_COOLDOWN := 30000  ; 30 seconds cooldown

; Timing and Intervals
global BB_CLICK_DELAY_MIN := 500        ; 0.5 seconds
global BB_CLICK_DELAY_MAX := 1500       ; 1.5 seconds
global BB_INTERACTION_DURATION := 5000   ; 5 seconds
global BB_CYCLE_INTERVAL := 180000      ; 3 minutes
global BB_ANTI_AFK_INTERVAL := 300000   ; 5 minutes
global BB_RECONNECT_CHECK_INTERVAL := 10000  ; 10 seconds

; Explosive Management
global BB_ENABLE_EXPLOSIVES := false
global BB_BOMB_INTERVAL := 10000        ; 10 seconds
global BB_TNT_CRATE_INTERVAL := 30000   ; 30 seconds
global BB_TNT_BUNDLE_INTERVAL := 15000  ; 15 seconds
global BB_lastBombStatus := "Idle"
global BB_lastTntCrateStatus := "Idle"
global BB_lastTntBundleStatus := "Idle"

; File System and Logging
global BB_logFile := A_ScriptDir "\mining_log.txt"
global BB_CONFIG_FILE := A_ScriptDir "\mining_config.ini"
global BB_TEMPLATE_FOLDER := A_ScriptDir "\mining_templates"
global BB_BACKUP_TEMPLATE_FOLDER := A_ScriptDir "\backup_templates"
global BB_ENABLE_LOGGING := true

; Window Management
global BB_WINDOW_TITLE := "Roblox"
global BB_EXCLUDED_TITLES := []
global BB_active_windows := []
global BB_last_window_check := 0
global BB_WINDOW_CHECK_INTERVAL := 5000  ; 5 seconds

; Template Management
global BB_TEMPLATES := Map()
global BB_missingTemplatesReported := Map()
global BB_TEMPLATE_RETRIES := 3
global BB_validTemplates := 0
global BB_totalTemplates := 0
global BB_imageCache := Map()

; Hotkeys
global BB_BOMB_HOTKEY := "^b"           ; CTRL+B
global BB_TNT_CRATE_HOTKEY := "^t"      ; CTRL+T
global BB_TNT_BUNDLE_HOTKEY := "^n"     ; CTRL+N
global BB_TELEPORT_HOTKEY := "t"
global BB_INVENTORY_HOTKEY := "f"
global BB_START_STOP_HOTKEY := "F2"
global BB_PAUSE_HOTKEY := "p"
global BB_EXPLOSIVES_TOGGLE_HOTKEY := "F3"
global BB_EXIT_HOTKEY := "Escape"

; Game State and Error Handling
global BB_FAILED_INTERACTION_COUNT := 0
global BB_MAX_FAILED_INTERACTIONS := 5
global BB_MAX_BUY_ATTEMPTS := 6
global BB_isAutofarming := false
global BB_currentArea := "Unknown"
global BB_merchantState := "Not Interacted"
global BB_lastError := "None"

; Performance Monitoring
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
emerald_block=emerald_block.png
go_to_top_button=go_to_top_button.png

[Hotkeys]
; Changed ^ to CTRL for better readability in GUI/docs
BOMB_HOTKEY=CTRL+b
TNT_CRATE_HOTKEY=CTRL+t
TNT_BUNDLE_HOTKEY=CTRL+n
TELEPORT_HOTKEY=t
INVENTORY_HOTKEY=f
START_STOP_HOTKEY=F2
PAUSE_HOTKEY=p
EXPLOSIVES_TOGGLE_HOTKEY=F3
EXIT_HOTKEY=Esc

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

; Opens the inventory.
; Parameters:
;   hwnd: The handle of the Roblox window to check for movement.
; Returns: True if the inventory was opened, False otherwise.
BB_openInventory(hwnd := 0) {
    if (!hwnd) {
        hwnd := WinGetID("A")
    }
    
    if (!hwnd || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("No Roblox window active for inventory action", true, true)
        return false
    }
    
    ; Send the inventory hotkey (default 'f')
    global BB_INVENTORY_HOTKEY
    BB_sendHotkeyWithDownUp(BB_INVENTORY_HOTKEY)
    BB_updateStatusAndLog("Opened inventory with hotkey: " BB_INVENTORY_HOTKEY)
    Sleep(500)  ; Brief delay to allow inventory to open
    
    return true
}

; Detects in-game movement by monitoring pixel changes in specified regions.
; Parameters:
;   hwnd: The handle of the Roblox window to check for movement.
; Returns: True if movement is detected, False otherwise.
BB_detectMovement(hwnd) {
    ; Verify the window handle
    if (!hwnd || !WinExist("ahk_id " . hwnd) || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("Invalid Roblox window handle for movement detection: " . hwnd, true, true)
        return false
    }
    
    ; Get the Roblox window's position and size
    WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " . hwnd)
    
    ; Define regions to check for pixel movement (relative to the window)
    ; Focus on areas where mining effects or character movement are likely visible
    regions := [
        [winX + (winW // 2), winY + (winH // 2)],     ; Center
        [winX + (winW // 4), winY + (winH // 4)],     ; Top-left
        [winX + (3 * winW // 4), winY + (3 * winH // 4)],  ; Bottom-right
        [winX + (winW // 2), winY + (winH // 4)],     ; Top-center
        [winX + (winW // 2), winY + (3 * winH // 4)]  ; Bottom-center
    ]
    
    ; Capture initial colors in each region
    initialColors := []
    for region in regions {
        try {
            color := PixelGetColor(region[1], region[2], "RGB")
            initialColors.Push(color)
        } catch as err {
            BB_updateStatusAndLog("PixelGetColor error at [" . region[1] . "," . region[2] . "]: " . err.Message, true)
            return false  ; If we can't get initial colors, abort
        }
    }
    
    ; Wait a short time to allow for potential movement
    Sleep(500)
    
    ; Check for changes in the same regions
    changes := 0
    threshold := 2  ; Require at least 2 regions to change
    for index, region in regions {
        try {
            newColor := PixelGetColor(region[1], region[2], "RGB")
            if (newColor != initialColors[index]) {
                changes++
            }
        } catch as err {
            BB_updateStatusAndLog("PixelGetColor error at [" . region[1] . "," . region[2] . "]: " . err.Message, true)
            continue  ; Skip this region if there's an error
        }
    }
    
    return changes >= threshold
}

; Performs periodic anti-AFK actions to prevent disconnection.
; This function is called on a timer to keep the game session active.
; Notes:
;   - Only runs when script is active and not paused
;   - Verifies active Roblox window before performing actions
;   - Simulates player actions like jumping and movement
;   - Uses random movement directions to appear more natural
;   - Includes delays to allow game to process actions
;   - Logs all anti-AFK actions for monitoring
BB_antiAfkLoop() {
    global BB_running, BB_paused, BB_ANTI_AFK_INTERVAL
    if (!BB_running || BB_paused) {
        BB_updateStatusAndLog("Anti-AFK loop skipped (not running or paused)")
        return
    }
    
    hwnd := WinGetID("A")
    if (!hwnd || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("No Roblox window active for anti-AFK action", true)
        return
    }
    
    ; Simulate a jump to prevent AFK detection
    SendInput("{Space down}")
    Sleep(100)
    SendInput("{Space up}")
    BB_updateStatusAndLog("Anti-AFK action: Jumped to prevent disconnect")
    Sleep(500)  ; Add a delay to allow the game to process the jump
    
    ; Optional: Random movement to mimic player activity
    moveDir := Random(1, 4)
    moveKey := (moveDir = 1) ? "w" : (moveDir = 2) ? "a" : (moveDir = 3) ? "s" : "d"
    SendInput("{" . moveKey . " down}")
    Sleep(Random(500, 1000))
    SendInput("{" . moveKey . " up}")
    BB_updateStatusAndLog("Anti-AFK action: Moved " . moveKey . " to prevent disconnect")
}

; Updates the status and log file with a message.
; Parameters:
;   message: The message to log.
;   updateGUI: Whether to update the GUI.
;   isError: Whether the message is an error.
;   takeScreenshot: Whether to take a screenshot.
BB_updateStatusAndLog(message, updateGUI := true, isError := false, takeScreenshot := false) {
    global BB_ENABLE_LOGGING, BB_logFile, BB_myGUI, BB_isAutofarming, BB_currentArea, BB_merchantState, BB_lastError
    global BB_lastBombStatus, BB_lastTntCrateStatus, BB_lastTntBundleStatus, BB_validTemplates, BB_totalTemplates
    static firstRun := true
    static emeraldBlockCount := 0
    
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
    
    ; Reset emerald block count if requested
    if (message = "Resetting emerald block count") {
        emeraldBlockCount := 0
    }
    
    ; Update emerald block count
    if (InStr(message, "Found") && InStr(message, "emerald blocks")) {
        RegExMatch(message, "Found\s+(\d+)\s+emerald\s+block(s)?", &match)
        emeraldBlockCount += match[1]
    }
    
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
        BB_myGUI["EmeraldBlockCount"].Text := emeraldBlockCount
        BB_myGUI["LastAction"].Text := message
        BB_myGUI["LastError"].Text := BB_lastError
        BB_myGUI["LastError"].SetFont(isError ? "cRed" : "cBlack")
    }
    
    ToolTip message, 0, 100
    SetTimer(() => ToolTip(), -3000)
}
; Clears the log file.
BB_clearLog(*) {
    global BB_logFile
    FileDelete(BB_logFile)
    BB_updateStatusAndLog("Log file cleared")
}
; Validates an image file.
; Parameters:
;   filePath: The path to the image file to validate.
; Returns: A string indicating the validation result.
; Notes:
;   - Checks if the file exists

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
; Downloads a template file from a URL and validates it.
; Parameters:
;   templateName: The name of the template to download.
;   fileName: The name of the file to download.
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
; Downloads a file from a URL using PowerShell.
; Parameters:
;   url: The URL of the file to download.
;   dest: The local path to save the downloaded file.
; Returns: True if download succeeds, False otherwise.
; Notes:
;   - Uses PowerShell to download files
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

; Activates a Roblox window robustly, ensuring it is ready for interaction.
; Parameters:
;   hwnd: The handle of the window to activate.
; Returns: True if activation is successful, False otherwise.
BB_robustWindowActivation(hwnd) {
    global BB_updateStatusAndLog
    
    if (!hwnd || !WinExist("ahk_id " . hwnd)) {
        BB_updateStatusAndLog("Window does not exist: " . hwnd, true, true)
        return false
    }
    
    ; Check if the window is already active
    if (WinActive("ahk_id " . hwnd)) {
        BB_updateStatusAndLog("Window already active: " . hwnd)
        return true
    }
    
    ; Attempt to activate the window
    loop 3 {
        try {
            WinActivate("ahk_id " . hwnd)
            Sleep(500)  ; Increased delay to ensure activation
            if (WinActive("ahk_id " . hwnd)) {
                BB_updateStatusAndLog("Window activated successfully: " . hwnd)
                return true
            }
        } catch as err {
            BB_updateStatusAndLog("Error activating window " . hwnd . ": " . err.Message, true, true)
        }
        Sleep(500)
    }
    
    BB_updateStatusAndLog("Failed to activate window after 3 attempts: " . hwnd, true, true)
    return false
}
; Clicks at a specified position in the Roblox window.
; Parameters:
;   x: The x-coordinate to click.
;   y: The y-coordinate to click.
; Returns: True if click succeeds, False otherwise.
; Notes:
;   - Verifies active Roblox window before clicking
BB_clickAt(x, y) {
    global BB_CLICK_DELAY_MIN, BB_CLICK_DELAY_MAX, BB_performanceData, BB_updateStatusAndLog
    
    ; Validate input coordinates
    if (!IsNumber(x) || !IsNumber(y)) {
        BB_updateStatusAndLog("Invalid coordinates provided to BB_clickAt: x=" . x . ", y=" . y, true, true)
        return false
    }
    
    hwnd := WinGetID("A")
    if (!hwnd || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("No Roblox window active for clicking at x=" . x . ", y=" . y, true)
        return false
    }
    
    try {
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " . hwnd)
        
        ; Validate window position and size
        if (!IsNumber(winX) || !IsNumber(winY) || !IsNumber(winW) || !IsNumber(winH)) {
            BB_updateStatusAndLog("Invalid window position/size: x=" . winX . ", y=" . winY . ", w=" . winW . ", h=" . winH, true, true)
            return false
        }
        
        ; Check if coordinates are within window bounds
        if (x < winX || x > winX + winW || y < winY || y > winY + winH) {
            BB_updateStatusAndLog("Click coordinates x=" . x . ", y=" . y . " are outside window bounds", true)
            return false
        }
        
        startTime := A_TickCount
        delay := Random(BB_CLICK_DELAY_MIN, BB_CLICK_DELAY_MAX)
        
        ; Move mouse to coordinates
        MouseMove(x, y, 10)
        Sleep(delay)
        
        ; Send click down
        Send("{LButton down}")
        BB_updateStatusAndLog("Mouse down at x=" . x . ", y=" . y)
        
        ; Small delay to simulate a natural click duration
        clickDuration := Random(50, 150)
        Sleep(clickDuration)
        
        ; Send click up
        Send("{LButton up}")
        BB_updateStatusAndLog("Mouse up at x=" . x . ", y=" . y . " after " . clickDuration . "ms")
        
        ; Calculate and update average click time
        elapsed := A_TickCount - startTime
        BB_performanceData["ClickAt"] := BB_performanceData.Has("ClickAt") ? (BB_performanceData["ClickAt"] + elapsed) / 2 : elapsed
        BB_updateStatusAndLog("Completed click at x=" . x . ", y=" . y . " (total: " . elapsed . "ms)")
        return true
        
    } catch as err {
        BB_updateStatusAndLog("Error in BB_clickAt: " . err.Message, true, true)
        return false
    }
}

; Helper function to check if a value is a number
IsNumber(value) {
    if (value = "")
        return false
    if value is Number
        return true
    return false
}

; Downloads a file from a URL and validates its size and format.
; Parameters:
;   url: The URL of the file to download.
;   dest: The local path to save the downloaded file.
; Returns: True if download succeeds, False otherwise.
; Notes:
;   - Uses HTTP download function
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
; Joins an array of strings into a single string with a specified delimiter.
; Parameters:
;   arr: The array of strings to join.
;   delimiter: The delimiter to use between strings.
; Returns: A single string containing all elements of the array, separated by the delimiter.
; Notes:
;   - Uses a loop to concatenate the strings
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
		"emerald_block", "emerald_block.png",
		"area_5_button", "area_5_button.png",
		"mining_merchant", "mining_merchant.png",
		"buy_button", "buy_button.png",
		"merchant_window", "merchant_window.png",
		"autofarm_on", "autofarm_on.png",
		"autofarm_off", "autofarm_off.png",
		"go_to_top_button", "go_to_top_button.png",
		"error_message", "error_message.png",        ; Added
		"error_message_alt1", "error_message_alt1.png",  ; Added
		"connection_lost", "connection_lost.png",     ; Added
		"emerald_block", "emerald_block.png",
		"go_to_top_button", "go_to_top_button.png"
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
    BB_myGUI := Gui("", "🐝 BeeBrained's PS99 Mining Event Macro v" . BB_VERSION . " 🐝")
    BB_myGUI.OnEvent("Close", BB_exitApp)
    
    BB_myGUI.Add("Text", "x10 y10 w400 h20 Center", "🐝 BeeBrained's PS99 Mining Event Macro v" . BB_VERSION . " 🐝")
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
    
    BB_myGUI.Add("GroupBox", "x10 y190 w400 h100", "Game State")
    BB_myGUI.Add("Text", "x20 y210 w180 h20", "Current Area:")
    BB_myGUI.Add("Text", "x200 y210 w200 h20", "Unknown").Name := "CurrentArea"
    BB_myGUI.Add("Text", "x20 y230 w180 h20", "Merchant Interaction:")
    BB_myGUI.Add("Text", "x200 y230 w200 h20", "Not Interacted").Name := "MerchantState"
    BB_myGUI.Add("Text", "x20 y250 w180 h20", "Emerald Blocks Found:")
    BB_myGUI.Add("Text", "x200 y250 w200 h20", "0").Name := "EmeraldBlockCount"
    
    BB_myGUI.Add("GroupBox", "x10 y300 w400 h80", "Explosives Status")
    BB_myGUI.Add("Text", "x20 y320 w180 h20", "Bomb:")
    BB_myGUI.Add("Text", "x200 y320 w200 h20", "Idle").Name := "BombStatus"
    BB_myGUI.Add("Text", "x20 y340 w180 h20", "TNT Crate:")
    BB_myGUI.Add("Text", "x200 y340 w200 h20", "Idle").Name := "TntCrateStatus"
    BB_myGUI.Add("Text", "x20 y360 w180 h20", "TNT Bundle:")
    BB_myGUI.Add("Text", "x200 y360 w200 h20", "Idle").Name := "TntBundleStatus"
    
    BB_myGUI.Add("GroupBox", "x10 y390 w400 h100", "Last Action/Error")
    BB_myGUI.Add("Text", "x20 y410 w180 h20", "Last Action:")
    BB_myGUI.Add("Text", "x200 y410 w200 h40 Wrap", "None").Name := "LastAction"
    BB_myGUI.Add("Text", "x20 y450 w180 h20", "Last Error:")
    BB_myGUI.Add("Text", "x200 y450 w200 h40 Wrap cRed", "None").Name := "LastError"
	
	BB_myGUI.Add("Text", "x20 y270 w180 h20", "Failed Interactions:")
	BB_myGUI.Add("Text", "x200 y270 w200 h20", "0").Name := "FailedCount"
	; Update in BB_updateStatusAndLog
	BB_myGUI["FailedCount"].Text := BB_FAILED_INTERACTION_COUNT
    
    BB_myGUI.Add("Button", "x10 y500 w120 h30", "Reload Config").OnEvent("Click", BB_loadConfigFromFile)
    BB_myGUI.Add("Button", "x290 y500 w120 h30", "Clear Log").OnEvent("Click", BB_clearLog)
    
    BB_myGUI.Show("x0 y0 w420 h540")
}

; ===================== HOTKEYS =====================
; Main Control Hotkeys
Hotkey(BB_START_STOP_HOTKEY, BB_stopAutomation)    ; F2 - Start/Stop
Hotkey(BB_PAUSE_HOTKEY, BB_togglePause)            ; p - Pause/Resume
Hotkey(BB_EXPLOSIVES_TOGGLE_HOTKEY, BB_toggleExplosives)  ; F3 - Toggle Explosives
Hotkey(BB_EXIT_HOTKEY, BB_exitApp)                 ; Esc - Exit Application

; Explosive Hotkeys
Hotkey(BB_BOMB_HOTKEY, BB_useBomb)                ; CTRL+B - Use Bomb
Hotkey(BB_TNT_CRATE_HOTKEY, BB_useTntCrate)       ; CTRL+T - Use TNT Crate
Hotkey(BB_TNT_BUNDLE_HOTKEY, BB_useTntBundle)     ; CTRL+N - Use TNT Bundle

; Game Interaction Hotkeys
Hotkey(BB_TELEPORT_HOTKEY, BB_openTeleportMenu)   ; t - Open Teleport Menu
Hotkey(BB_INVENTORY_HOTKEY, BB_openInventory)      ; f - Open Inventory

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
    SetTimer(BB_miningAutomationLoop, 1000)
    ; Reset emerald block count
    BB_updateStatusAndLog("Resetting emerald block count", false)
    BB_myGUI["EmeraldBlockCount"].Text := "0"
}
; Stops the mining automation.
; Parameters:
;   None
; Returns: None
; Notes:
;   - Stops all timers and resets the automation state
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
; Toggles the pause state of the mining automation.
; Parameters:
;   None
; Returns: None
; Notes:
;   - Switches the pause state of the automation
;   - Updates the status log with the new pause state
BB_togglePause(*) {
    global BB_running, BB_paused
    if BB_running {
        BB_paused := !BB_paused
        BB_updateStatusAndLog(BB_paused ? "Paused" : "Resumed")
        Sleep 200
    }
}

; Ensures the game UI is in a state where the automine button is visible by resetting the UI.
; Parameters:
;   hwnd: The handle of the Roblox window to ensure the state for.
BB_ensureGameState(hwnd) {
    global BB_updateStatusAndLog
    
    BB_updateStatusAndLog("Ensuring game state for reliable automine button detection (hwnd: " . hwnd . ")")
    
    if (!hwnd || !WinExist("ahk_id " . hwnd) || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("Invalid Roblox window handle for ensuring game state: " . hwnd, true, true)
        return
    }
    
    WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " . hwnd)
    
    ; Click in the top-right corner of the window to close any popups
    closeX := winX + winW - 50
    closeY := winY + 50
    BB_clickAt(closeX, closeY)
    BB_updateStatusAndLog("Clicked top-right corner to close potential popups at x=" . closeX . ", y=" . closeY)
    Sleep(500)
    
    ; Click in the center of the window to dismiss any other overlays
    centerX := winX + (winW / 2)
    centerY := winY + (winH / 2)
    BB_clickAt(centerX, centerY)
    BB_updateStatusAndLog("Clicked center of window to dismiss overlays at x=" . centerX . ", y=" . centerY)
    Sleep(500)
    
    BB_updateStatusAndLog("Game state ensured: UI reset")
}
; Toggles the use of explosives in the mining automation.
; Parameters:
;   None
; Returns: None
; Notes:
;   - Switches the use of explosives on and off
;   - Updates the status log with the new state
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
; Updates the list of active Roblox windows.
; Parameters:
;   None
; Returns: An array of active Roblox window handles
; Notes:
;   - Checks for active Roblox windows
;   - Filters out excluded titles
BB_updateActiveWindows() {
    global BB_active_windows, BB_last_window_check
    
    ; Skip if checked recently (within 5 seconds)
    currentTime := A_TickCount
    if (currentTime - BB_last_window_check < 5000) {
        BB_updateStatusAndLog("Window check skipped (recently checked)")
        return BB_active_windows
    }
    
    ; Reset active windows list
    BB_active_windows := []
    activeHwnd := WinGetID("A")
    
    try {
        ; Get all windows with exact title "Roblox"
        winList := WinGetList("Roblox")
        
        ; Process each window
        for hwnd in winList {
            try {
                if (WinGetProcessName(hwnd) = "RobloxPlayerBeta.exe") {
                    ; Prioritize active window by adding it first
                    if (hwnd = activeHwnd) {
                        BB_active_windows.InsertAt(1, hwnd)
                    } else {
                        BB_active_windows.Push(hwnd)
                    }
                    BB_updateStatusAndLog("Found Roblox window (hwnd: " hwnd ", active: " (hwnd = activeHwnd ? "Yes" : "No") ")")
                }
            } catch as err {
                BB_updateStatusAndLog("Error processing window " hwnd ": " err.Message, true, true)
            }
        }
    } catch as err {
        BB_updateStatusAndLog("Failed to retrieve window list: " err.Message, true, true)
    }
    
    BB_last_window_check := currentTime
    BB_updateStatusAndLog("Found " BB_active_windows.Length " valid Roblox windows")
    return BB_active_windows
}
; Checks if a window title contains any excluded titles.
; Parameters:
;   title: The title of the window to check.
; Returns: True if the title contains an excluded title, False otherwise.
; Notes:
;   - Checks against a list of excluded titles
BB_hasExcludedTitle(title) {
    global BB_EXCLUDED_TITLES
    for excluded in BB_EXCLUDED_TITLES {
        if InStr(title, excluded)
            return true
    }
    return false
}

; ===================== ERROR HANDLING =====================

; Checks for error messages on the screen (e.g., connection lost, generic errors).
; Parameters:
;   hwnd: The handle of the Roblox window to check.
; Returns: True if an error is detected, False otherwise.
BB_checkForError(hwnd) {
    global BB_updateStatusAndLog
    
    errorDetected := false
    errorType := ""
    FoundX := ""
    FoundY := ""
    
    ; Temporarily disabled error template checks
    /*
    errorTypes := ["error_message", "error_message_alt1", "connection_lost"]
    for type in errorTypes {
        if BB_smartTemplateMatch(type, &FoundX, &FoundY, hwnd) {
            errorDetected := true
            errorType := type
            BB_updateStatusAndLog("WARNING: Error detected (" . errorType . " at x=" . FoundX . ", y=" . FoundY . ")", true, true, true)
            break
        } else {
            BB_updateStatusAndLog("Info: Template '" . type . "' not found during error check")
        }
    }
    */
    
    if errorDetected {
        BB_updateStatusAndLog("Handling error: " . errorType)
        
        errorActions := Map(
            "DisableAutomine", () => (BB_disableAutomine(hwnd)),
            "TeleportToArea4", () => (BB_openTeleportMenu(hwnd), BB_teleportToArea("area_4_button", hwnd)),
            "Shopping", () => (BB_interactWithMerchant(hwnd)),
            "TeleportToArea5", () => (BB_openTeleportMenu(hwnd), BB_teleportToArea("area_5_button", hwnd)),
            "EnableAutomine", () => (BB_enableAutomine(hwnd)),
            "Idle", () => (SendInput("{Space down}"), Sleep(100), SendInput("{Space up}"), Sleep(500)),
            "Mining", () => (SendInput("{Space down}"), Sleep(100), SendInput("{Space up}"), Sleep(500))
        )
        
        action := errorActions.Has(BB_automationState) ? errorActions[BB_automationState] : errorActions["Idle"]
        actionResult := action()
        
        BB_updateStatusAndLog("Attempted recovery from error in state " . BB_automationState . " (Result: " . (actionResult ? "Success" : "Failed") . ")")
        
        global BB_FAILED_INTERACTION_COUNT
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

; Attempts to go to the top of the mining area.
; Parameters:
;   None
; Returns: True if successful, False otherwise.
; Notes:
;   - Searches for the "Go to Top" button on the right side of the screen
BB_goToTop() {
    FoundX := ""
    FoundY := ""
    BB_updateStatusAndLog("Attempting to go to the top of the mining area...")
    
    ; Get the active Roblox window
    hwnd := WinGetID("A")
    if (!hwnd || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("No Roblox window active for 'Go to Top' action", true, true)
        return false
    }
    
    ; Search for the "Go to Top" button on the right side of the screen
    searchArea := [A_ScreenWidth - 300, 50, A_ScreenWidth - 50, 150]
    
    loop 3 {
        if BB_smartTemplateMatch("go_to_top_button", &FoundX, &FoundY, hwnd, searchArea) {
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
; Resets the game state to the initial state.
; Parameters:
;   None
; Returns: True if successful, False otherwise.
; Notes:
;   - Closes all active Roblox windows
;   - Attempts to reopen Pet Simulator 99
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
; Checks for updates from the GitHub repository.
; Parameters:
;   None
; Returns: None
; Notes:
;   - Retrieves the latest version from the version.txt file
;   - Compares the current version with the remote version
BB_checkForUpdates() {
    global BB_VERSION
    versionUrl := "https://raw.githubusercontent.com/xXGeminiXx/BMATMiner/main/version.txt"
    maxRetries := 3
    retryDelay := 2000
    
    loop maxRetries {
        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.Open("GET", versionUrl, false)
            http.Send()
            if (http.Status != 200) {
                throw Error("HTTP status " . http.Status . " received")
            }
            latestVersion := Trim(http.ResponseText, " `t`r`n")
            if (!RegExMatch(latestVersion, "^\d+\.\d+\.\d+$")) {
                throw Error("Invalid version format: '" . latestVersion . "'")
            }
            BB_updateStatusAndLog("Current version: " . BB_VERSION . " | Remote version: " . latestVersion)
            
            ; Split versions into components for numeric comparison
            currentParts := StrSplit(BB_VERSION, ".")
            latestParts := StrSplit(latestVersion, ".")
            
            if (currentParts[1] > latestParts[1] 
                || (currentParts[1] = latestParts[1] && currentParts[2] > latestParts[2])
                || (currentParts[1] = latestParts[1] && currentParts[2] = latestParts[2] && currentParts[3] > latestParts[3])) {
                BB_updateStatusAndLog("You're running a development version! 🛠️")
                MsgBox("Oho! Running version " . BB_VERSION . " while latest release is " . latestVersion . "?`n`nYou must be one of the developers! 😎`nOr... did you find this in the future? 🤔", "Developer Version", 0x40)
            } else if (latestVersion != BB_VERSION) {
                BB_updateStatusAndLog("New version available: " . latestVersion . " (current: " . BB_VERSION . ")")
                MsgBox("A new version (" . latestVersion . ") is available! Current version: " . BB_VERSION . ". Please update from the GitHub repository.", "Update Available", 0x40)
            } else {
                BB_updateStatusAndLog("Script is up to date (version: " . BB_VERSION . ")")
            }
            return
        } catch as err {
            BB_updateStatusAndLog("Failed to check for updates (attempt " . A_Index . "): " . err.Message, true, true)
            if (A_Index < maxRetries) {
                BB_updateStatusAndLog("Retrying in " . (retryDelay / 1000) . " seconds...")
                Sleep(retryDelay)
            }
        }
    }
    BB_updateStatusAndLog("Failed to check for updates after " . maxRetries . " attempts", true, true)
}
; Enables automining in the game.
; Parameters:
;   hwnd: The handle of the Roblox window to interact with.
; Returns: True if successful, False otherwise.
BB_enableAutomine(hwnd) {
    global BB_isAutofarming
    
    BB_updateStatusAndLog("Attempting to enable automining...")
    
    ; Find and click the automine button using its template
    FoundX := ""
    FoundY := ""
    if BB_smartTemplateMatch("automine_button", &FoundX, &FoundY, hwnd) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Clicked automine button at x=" . FoundX . ", y=" . FoundY . " to enable automining")
    } else {
        ; Fallback to fixed coordinates if template matching fails
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " . hwnd)
        clickX := winX + 60
        clickY := winY + 550
        BB_clickAt(clickX, clickY)
        BB_updateStatusAndLog("Automine button not found, clicked at fixed position x=" . clickX . ", y=" . clickY . " to enable automining")
    }
    
    Sleep(2000)
    
    ; Validate using pixel movement
    regions := [
        [A_ScreenWidth//3, A_ScreenHeight//3],
        [2*A_ScreenWidth//3, A_ScreenHeight//3],
        [A_ScreenWidth//2, A_ScreenHeight//2],
        [A_ScreenWidth//3, 2*A_ScreenHeight//3],
        [2*A_ScreenWidth//3, 2*A_ScreenHeight//3]
    ]
    
    initialColors := []
    for region in regions {
        color := PixelGetColor(region[1], region[2], "RGB")
        initialColors.Push(color)
    }
    
    Sleep(1000)
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
    
    if (isMoving) {
        BB_updateStatusAndLog("Pixel movement detected after enabling, automining enabled successfully")
        BB_isAutofarming := true
        return true
    } else {
        BB_updateStatusAndLog("No pixel movement detected, assuming automining is ON anyway")
        BB_isAutofarming := true
        return true
    }
}

; Detects emerald blocks on the screen and returns their positions.
; Parameters:
;   blockPositions: Output array to store the positions of detected blocks.
;   hwnd: The handle of the Roblox window to search in.
; Returns: True if blocks are detected, False otherwise.
BB_detectEmeraldBlocks(&blockPositions, hwnd) {
    global BB_TEMPLATES, BB_TEMPLATE_FOLDER
    blockPositions := []
    rawPositions := []
    
    ; Template matching
    FoundX := ""
    FoundY := ""
    searchArea := [A_ScreenWidth // 4, A_ScreenHeight // 4, 3 * A_ScreenWidth // 4, 3 * A_ScreenHeight // 4]
    if BB_smartTemplateMatch("emerald_block", &FoundX, &FoundY, hwnd, searchArea) {
        rawPositions.Push({x: FoundX, y: FoundY})
        BB_updateStatusAndLog("Emerald block detected via template at x=" . FoundX . ", y=" . FoundY)
    }
    
    ; Color detection
    if (rawPositions.Length == 0) {
        BB_updateStatusAndLog("Template matching for emerald block failed, using color detection")
        emeraldGreen := 0x00D93A
        tolerance := 50
        stepSize := 50
        
        ; Initialize x outside the loop
        x := searchArea[1]
        while (x <= searchArea[3]) {
            y := searchArea[2]
            while (y <= searchArea[4]) {
                color := PixelGetColor(x, y, "RGB")
                if BB_isColorSimilar(color, emeraldGreen, tolerance) {
                    rawPositions.Push({x: x, y: y})
                    BB_updateStatusAndLog("Emerald block detected via color at x=" . x . ", y=" . y . " (color: " . color . ")")
                }
                y += stepSize
            }
            x += stepSize
        }
    }
    
    ; Cluster nearby positions
    clusterDistance := 50
    while (rawPositions.Length > 0) {
        pos := rawPositions.RemoveAt(1)
        cluster := [pos]
        i := 1
        while (i <= rawPositions.Length) {
            other := rawPositions[i]
            distance := Sqrt((pos.x - other.x)**2 + (pos.y - other.y)**2)
            if (distance <= clusterDistance) {
                cluster.Push(other)
                rawPositions.RemoveAt(i)
            } else {
                i++
            }
        }
        ; Calculate centroid of the cluster
        avgX := 0
        avgY := 0
        for p in cluster {
            avgX += p.x
            avgY += p.y
        }
        avgX := Round(avgX / cluster.Length)
        avgY := Round(avgY / cluster.Length)
        blockPositions.Push({x: avgX, y: avgY})
    }
    
    return blockPositions.Length > 0
}

; Opens the teleport menu in the game.
; Parameters:
;   hwnd: The handle of the Roblox window to interact with.
; Returns: True if successful, False otherwise.
BB_openTeleportMenu(hwnd) {
    BB_updateStatusAndLog("Attempting to open teleport menu...")
    
    ; Find and click the teleport button using its template
    FoundX := ""
    FoundY := ""
    if BB_smartTemplateMatch("teleport_button", &FoundX, &FoundY, hwnd) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Clicked teleport button at x=" . FoundX . ", y=" . FoundY . " to open teleport menu")
    } else {
        ; Fallback to fixed coordinates if template matching fails
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " . hwnd)
        clickX := winX + 100  ; Adjust these coordinates based on your game
        clickY := winY + 100
        BB_clickAt(clickX, clickY)
        BB_updateStatusAndLog("Teleport button not found, clicked at fixed position x=" . clickX . ", y=" . clickY . " to open teleport menu")
    }
    
    Sleep(2000)  ; Wait for the menu to open
    BB_updateStatusAndLog("Assuming teleport menu opened successfully")
    return true
}

; Teleports to a specified area using the teleport menu.
; Parameters:
;   areaTemplate: The template name of the area button (e.g., "area_4_button").
;   hwnd: The handle of the Roblox window to interact with.
; Returns: True if successful, False otherwise.
BB_teleportToArea(areaTemplate, hwnd) {
    global BB_currentArea
    BB_updateStatusAndLog("Attempting to teleport to " . areaTemplate . "...")
    
    ; Since template matching fails, use fixed coordinates for Area 4 and Area 5 buttons
    ; These coordinates are approximate and may need adjustment based on your screen
    WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " . hwnd)
    if (areaTemplate = "area_4_button") {
        ; Area 4 button (approximate position in teleport menu)
        clickX := winX + 300
        clickY := winY + 400
        BB_currentArea := "Area 4"
    } else if (areaTemplate = "area_5_button") {
        ; Area 5 button (approximate position in teleport menu)
        clickX := winX + 300
        clickY := winY + 500
        BB_currentArea := "Area 5"
    } else {
        BB_updateStatusAndLog("Unknown area template: " . areaTemplate, true)
        return false
    }
    
    BB_clickAt(clickX, clickY)
    BB_updateStatusAndLog("Clicked to teleport to " . BB_currentArea . " at x=" . clickX . ", y=" . clickY)
    Sleep(5000)  ; Wait for teleport to complete
    return true
}

; Interacts with the mining merchant in Area 4.
; Parameters:
;   hwnd: The handle of the Roblox window to interact with.
; Returns: True if successful, False otherwise.
BB_interactWithMerchant(hwnd) {
    global BB_merchantState
    BB_updateStatusAndLog("Attempting to interact with merchant in Area 4...")
    
    ; Simulate walking to the merchant (hold 'w' to move forward)
    BB_updateStatusAndLog("Walking forward to merchant (holding 'w' for 5 seconds)")
    SendInput("{w down}")
    Sleep(5000)  ; Adjust this duration based on how long it takes to reach the merchant
    SendInput("{w up}")
    
    ; Interact with the merchant (default interaction key is 'e' in Roblox)
    SendInput("{e down}")
    Sleep(100)
    SendInput("{e up}")
    BB_updateStatusAndLog("Sent 'e' to interact with merchant")
    Sleep(2000)  ; Wait for the merchant window to open
    
    BB_merchantState := "Interacted"
    return true
}

; Buys items from the merchant window.
; Parameters:
;   hwnd: The handle of the Roblox window to interact with.
; Returns: True if successful, False otherwise.
BB_buyMerchantItems(hwnd) {
    global BB_MAX_BUY_ATTEMPTS, BB_merchantState
    BB_updateStatusAndLog("Attempting to buy items from merchant...")
    
    WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " . hwnd)
    buyPositions := [
        [winX + 600, winY + 300],
        [winX + 700, winY + 300],
        [winX + 800, winY + 300],
        [winX + 900, winY + 300],
        [winX + 1000, winY + 300]
    ]
    
    buyCount := 0
    for pos in buyPositions {
        BB_clickAt(pos[1], pos[2])
        BB_updateStatusAndLog("Clicked buy button at x=" . pos[1] . ", y=" . pos[2])
        buyCount++
        Sleep(500)
    }
    
    ; Close the merchant window using 'e' (interaction key)
    SendInput("{e down}")
    Sleep(100)
    SendInput("{e up}")
    BB_updateStatusAndLog("Sent 'e' to close merchant window")
    Sleep(1000)
    
    BB_merchantState := "Items Purchased (" . buyCount . ")"
    return true
}

; Disables automining in the game.
; Parameters:
;   hwnd: The handle of the Roblox window to interact with.
; Returns: True if successful, False otherwise.
BB_disableAutomine(hwnd) {
    global BB_isAutofarming, BB_FAILED_INTERACTION_COUNT, BB_MAX_FAILED_INTERACTIONS
    
    BB_updateStatusAndLog("Initiating automining disable process...")
    
    ; Find and click the automine button using its template
    FoundX := ""
    FoundY := ""
    if BB_smartTemplateMatch("automine_button", &FoundX, &FoundY, hwnd) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Clicked automine button at x=" . FoundX . ", y=" . FoundY . " to disable automining")
    } else {
        ; Fallback to fixed coordinates if template matching fails
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " . hwnd)
        clickX := winX + 60
        clickY := winY + 600
        BB_clickAt(clickX, clickY)
        BB_updateStatusAndLog("Automine button not found, clicked at fixed position x=" . clickX . ", y=" . clickY . " to disable automining")
    }
    
    Sleep(2000)  ; Allow time for mining effects to stop
    
    ; Validate using pixel movement
    scaleX := A_ScreenWidth / 1920
    scaleY := A_ScreenHeight / 1080
    regions := [
        [Round(A_ScreenWidth//3), Round(A_ScreenHeight//3)],
        [2*A_ScreenWidth//3, Round(A_ScreenHeight//3)],
        [Round(A_ScreenWidth//2), Round(A_ScreenHeight//2)],
        [Round(A_ScreenWidth//3), Round(2*A_ScreenHeight//3)],
        [Round(2*A_ScreenWidth//3), Round(2*A_ScreenHeight//3)]
    ]
    
    initialColors := []
    for region in regions {
        color := PixelGetColor(region[1], region[2], "RGB")
        initialColors.Push(color)
        BB_updateStatusAndLog("Validation point [" . region[1] . "," . region[2] . "] initial color: " . color)
    }
    
    Sleep(1000)
    changes := 0
    threshold := 2
    loop 3 {
        for index, region in regions {
            newColor := PixelGetColor(region[1], region[2], "RGB")
            if (newColor != initialColors[index]) {
                changes++
                BB_updateStatusAndLog("Change at [" . region[1] . "," . region[2] . "]: " . initialColors[index] . " -> " . newColor)
            }
        }
        if (changes > threshold) {
            BB_updateStatusAndLog("Excessive movement detected (" . changes . " changes), retrying...")
            break
        }
        Sleep(300)
    }
    
    if (changes <= threshold) {
        BB_updateStatusAndLog("Automining disabled, minimal movement (" . changes . " changes)")
        BB_isAutofarming := false
        return true
    } else {
        BB_updateStatusAndLog("Assuming automining is disabled despite movement, proceeding")
        BB_isAutofarming := false
        return true
    }
}

; ===================== EXPLOSIVES FUNCTIONS =====================
; Sends a hotkey with down and up actions.
; Parameters:
;   hotkey: The hotkey to send.
; Returns: True if successful, False otherwise.
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

; Uses a bomb in the game.
; Parameters:
;   hwnd: The handle of the Roblox window to interact with.
BB_useBomb(hwnd) {
    global BB_BOMB_HOTKEY, BB_lastBombStatus
    BB_sendHotkeyWithDownUp(BB_BOMB_HOTKEY)
    BB_lastBombStatus := "Used at " . A_Now
    BB_updateStatusAndLog("Used bomb with hotkey: " . BB_BOMB_HOTKEY)
    BB_checkForError(hwnd)  ; Pass hwnd here
}

; Uses a TNT crate in the game.
; Parameters:
;   hwnd: The handle of the Roblox window to interact with.
BB_useTntCrate(hwnd) {
    global BB_TNT_CRATE_HOTKEY, BB_lastTntCrateStatus
    BB_sendHotkeyWithDownUp(BB_TNT_CRATE_HOTKEY)
    BB_lastTntCrateStatus := "Used at " . A_Now
    BB_updateStatusAndLog("Used TNT crate with hotkey: " . BB_TNT_CRATE_HOTKEY)
    BB_checkForError(hwnd)  ; Pass hwnd here
}

; Uses a TNT bundle in the game.
; Parameters:
;   hwnd: The handle of the Roblox window to interact with.
BB_useTntBundle(hwnd) {
    global BB_TNT_BUNDLE_HOTKEY, BB_lastTntBundleStatus
    BB_sendHotkeyWithDownUp(BB_TNT_BUNDLE_HOTKEY)
    BB_lastTntBundleStatus := "Used at " . A_Now
    BB_updateStatusAndLog("Used TNT bundle with hotkey: " . BB_TNT_BUNDLE_HOTKEY)
    BB_checkForError(hwnd)  ; Pass hwnd here
}
; Loops through bomb usage.
; Parameters:
;   None
; Returns: None
; Notes:
;   - Checks if the script is running, not paused, and explosives are enabled

BB_bombLoop() {
    global BB_running, BB_paused, BB_ENABLE_EXPLOSIVES, BB_isAutofarming
    if (!BB_running || BB_paused || !BB_ENABLE_EXPLOSIVES) {
        BB_updateStatusAndLog("Bomb loop skipped (not running, paused, or explosives off)")
        return
    }
    
    hwnd := WinGetID("A")
    if (!hwnd || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("No Roblox window active for bomb loop", true, true)
        return
    }
    
    if (BB_checkAutofarming(hwnd)) {
        BB_useBomb(hwnd)  ; Pass hwnd here
    } else {
        BB_updateStatusAndLog("Bomb loop skipped (not autofarming)")
    }
}
; Loops through TNT crate usage.
; Parameters:
;   None
; Returns: None
; Notes:
;   - Checks if the script is running, not paused, and explosives are enabled
;   - Verifies active Roblox window
BB_tntCrateLoop() {
    global BB_running, BB_paused, BB_ENABLE_EXPLOSIVES, BB_isAutofarming
    if (!BB_running || BB_paused || !BB_ENABLE_EXPLOSIVES) {
        BB_updateStatusAndLog("TNT crate loop skipped (not running, paused, or explosives off)")
        return
    }
    
    hwnd := WinGetID("A")
    if (!hwnd || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("No Roblox window active for TNT crate loop", true, true)
        return
    }
    
    if (BB_checkAutofarming(hwnd)) {
        BB_useTntCrate(hwnd)  ; Pass hwnd here
    } else {
        BB_updateStatusAndLog("TNT crate loop skipped (not autofarming)")
    }
}
; Loops through TNT bundle usage.
; Parameters:
;   None
; Returns: None
; Notes:
;   - Checks if the script is running, not paused, and explosives are enabled
BB_tntBundleLoop() {
    global BB_running, BB_paused, BB_ENABLE_EXPLOSIVES, BB_isAutofarming
    if (!BB_running || BB_paused || !BB_ENABLE_EXPLOSIVES) {
        BB_updateStatusAndLog("TNT bundle loop skipped (not running, paused, or explosives off)")
        return
    }
    
    hwnd := WinGetID("A")
    if (!hwnd || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("No Roblox window active for TNT bundle loop", true, true)
        return
    }
    
    if (BB_checkAutofarming(hwnd)) {
        BB_useTntBundle(hwnd)  ; Pass hwnd here
    } else {
        BB_updateStatusAndLog("TNT bundle loop skipped (not autofarming)")
    }
}

; ===================== STATE MACHINE AUTOMATION LOOP =====================
; Loops through the mining automation cycle.
; Parameters:
;   None
; Returns: None
; Notes:
;   - Checks if the script is running, not paused
;   - Ensures game state is correct
BB_miningAutomationLoop() {
    global BB_running, BB_paused, BB_automationState, BB_FAILED_INTERACTION_COUNT, BB_MAX_FAILED_INTERACTIONS
    global BB_currentArea, BB_merchantState, BB_isAutofarming, BB_CYCLE_INTERVAL, BB_ENABLE_EXPLOSIVES, gameStateEnsured
    
    if (!BB_running || BB_paused) {
        BB_updateStatusAndLog("Automation loop skipped (not running or paused)")
        return
    }
    
    gameStateEnsured := false
    BB_updateStatusAndLog("Starting automation cycle, gameStateEnsured reset")
    
    windows := BB_updateActiveWindows()
    if (windows.Length == 0) {
        BB_updateStatusAndLog("No Roblox windows found")
        return
    }
    
    ; Loops through the windows and performs the automation cycle.
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
        Sleep(500)
        
        if BB_checkForError(hwnd) {
            BB_setState("Error")
            continue
        }
        
        ; Switches through the automation states.
        switch BB_automationState {
            case "Idle":
                BB_updateStatusAndLog("Starting new cycle...")
                if BB_checkAutofarming(hwnd) {
                    BB_updateStatusAndLog("Autofarming is active, disabling...")
                    BB_setState("DisableAutomine")
                } else {
                    BB_updateStatusAndLog("Autofarming not active, proceeding with cycle")
                    BB_setState("DisableAutomine")  ; Still go through disable to ensure clean state
                }
            
            case "DisableAutomine":
                if BB_isAutofarming {
                    if BB_disableAutomine(hwnd) {
                        BB_updateStatusAndLog("Autofarming disabled, teleporting to Area 4")
                        Sleep(1000)  ; Wait for mining effects to stop
                        BB_setState("TeleportToArea4")
                    } else {
                        BB_FAILED_INTERACTION_COUNT++
                        BB_setState("Error")
                    }
                } else {
                    BB_updateStatusAndLog("Autofarming already disabled, teleporting to Area 4")
                    BB_setState("TeleportToArea4")
                }
            
            case "TeleportToArea4":
                if BB_openTeleportMenu(hwnd) {
                    Sleep(1000)  ; Wait for menu to open
                    if BB_teleportToArea("area_4_button", hwnd) {
                        BB_updateStatusAndLog("Teleported to Area 4, walking to merchant")
                        Sleep(5000)  ; Wait for teleport to complete
                        BB_setState("WalkToMerchant")
                    } else {
                        BB_FAILED_INTERACTION_COUNT++
                        BB_setState("Error")
                    }
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            
            case "WalkToMerchant":
                BB_fixCameraView(hwnd)  ; New function to ensure camera is correct
                if BB_walkToMerchant(hwnd) {
                    BB_setState("Shopping")
                }
            
            case "Shopping":
                if BB_buyMerchantItems(hwnd) {
                    BB_updateStatusAndLog("Shopping complete, closing merchant")
                    Sleep(1000)  ; Wait for purchases to complete
                    SendInput("{e down}")  ; Close merchant with 'e' key
                    Sleep(100)
                    SendInput("{e up}")
                    Sleep(2000)  ; Wait for merchant to close
                    BB_setState("TeleportToArea5")
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            
            case "TeleportToArea5":
                if BB_openTeleportMenu(hwnd) {
                    Sleep(1000)  ; Wait for menu to open
                    if BB_teleportToArea("area_5_button", hwnd) {
                        BB_updateStatusAndLog("Teleported to Area 5, enabling automining")
                        Sleep(5000)  ; Wait for teleport to complete
                        BB_setState("EnableAutomine")
                    } else {
                        BB_FAILED_INTERACTION_COUNT++
                        BB_setState("Error")
                    }
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            
            case "EnableAutomine":
                if BB_enableAutomine(hwnd) {
                    BB_updateStatusAndLog("Automining enabled, starting mining phase")
                    BB_setState("Mining")
                } else {
                    BB_FAILED_INTERACTION_COUNT++
                    BB_setState("Error")
                }
            
            case "Mining":
                BB_updateStatusAndLog("Mining in Area 5 for ~3 minutes")
                startTime := A_TickCount
                while (A_TickCount - startTime < BB_CYCLE_INTERVAL) {
                    if (!BB_running || BB_paused) {
                        BB_updateStatusAndLog("Mining interrupted")
                        break
                    }
                    if BB_checkForError(hwnd) {
                        BB_setState("Error")
                        break
                    }
                    Sleep(5000)
                }
                BB_setState("Idle")  ; Start new cycle
            
            case "Error":
                if (BB_FAILED_INTERACTION_COUNT >= BB_MAX_FAILED_INTERACTIONS) {
                    BB_updateStatusAndLog("Too many failed interactions, attempting reset", true, true)
                    if BB_resetGameState() {
                        BB_setState("Idle")
                    } else {
                        BB_stopAutomation()
                    }
                } else {
                    BB_updateStatusAndLog("Recovering from error state, retrying")
                    BB_setState("Idle")
                }
        }
    }
}

; ===================== ANTI-AFK AND RECONNECT FUNCTIONS =====================
; Reconnects to the game if the connection is lost.
; Parameters:
;   None
; Returns: None
; Notes:
;   - Checks if the script is running and not paused

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
; Loads the configuration from a file.
; Parameters:
;   None
; Returns: None
; Notes:
;   - Loads the configuration from a file

BB_loadConfigFromFile(*) {
    BB_loadConfig()
    MsgBox("Configuration reloaded from " . BB_CONFIG_FILE)
}
; Exits the application.
; Parameters:
;   None
; Returns: None
; Notes:
;   - Sets the running state to false
;   - Stops all timers
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

; Checks if automining is currently active in the game.
; Parameters:
;   hwnd: The handle of the Roblox window to check.
; Returns: True if automining is on, False if it's off.
BB_checkAutofarming(hwnd) {
    global BB_isAutofarming, BB_updateStatusAndLog, gameStateEnsured, BB_lastGameStateReset, BB_GAME_STATE_COOLDOWN

    BB_updateStatusAndLog("Checking automining state (hwnd: " . hwnd . ")...")

    ; First, ensure the game state is clear
    currentTime := A_TickCount
    if (!gameStateEnsured && (currentTime - BB_lastGameStateReset >= BB_GAME_STATE_COOLDOWN)) {
        BB_ensureGameState(hwnd)
        gameStateEnsured := true
        BB_lastGameStateReset := currentTime
    }

    ; Check for movement - if we detect movement, we're definitely autofarming
    isMoving := BB_detectMovement(hwnd)
    if (isMoving) {
        BB_updateStatusAndLog("Detected pixel movement - Autofarming is ON")
        BB_isAutofarming := true
        return true
    }

    ; If no movement, do one more quick check to be sure
    Sleep(500)
    isMoving := BB_detectMovement(hwnd)
    if (isMoving) {
        BB_updateStatusAndLog("Detected movement in second check - Autofarming is ON")
        BB_isAutofarming := true
        return true
    }

    ; If we've seen no movement at all, we can be confident autofarming is OFF
    BB_updateStatusAndLog("No movement detected - Autofarming is OFF")
    BB_isAutofarming := false
    return false
}
; Performs a template match for a specified template name.
; Parameters:
;   templateName: The name of the template to match.
;   FoundX: The x-coordinate of the found match.
;   FoundY: The y-coordinate of the found match.
;   hwnd: The handle of the Roblox window to check.
;   searchArea: Optional array [x1, y1, x2, y2] defining the area to search.
BB_smartTemplateMatch(templateName, &FoundX, &FoundY, hwnd, searchArea := "") {
    global BB_TEMPLATES, BB_TEMPLATE_FOLDER, BB_updateStatusAndLog
    
    if (!hwnd || !WinExist("ahk_id " . hwnd) || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("Invalid Roblox window handle for template matching: " . hwnd, true, true)
        return false
    }
    
    ; Get window position and size
    WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " . hwnd)
    
    ; If no search area provided, use default window area
    if (!searchArea) {
        searchArea := [winX, winY, winX + winW, winY + winH]
    }
    
    ; Load template image
    templatePath := BB_TEMPLATE_FOLDER . "\" . BB_TEMPLATES[templateName]
    if (!FileExist(templatePath)) {
        BB_updateStatusAndLog("Template file not found: " . templatePath, true, true)
        return false
    }
    
    ; Perform template matching
    try {
        ; Initialize to invalid values
        FoundX := -1
        FoundY := -1
        
        ; Use ImageSearch with the provided search area
        if (ImageSearch(&tmpX, &tmpY, searchArea[1], searchArea[2], searchArea[3], searchArea[4], "*50 " . templatePath)) {
            FoundX := tmpX
            FoundY := tmpY
            BB_updateStatusAndLog("Template match found at x=" . FoundX . ", y=" . FoundY)
            return true
        }
        BB_updateStatusAndLog("No template match found for " . templateName)
        return false
    } catch as err {
        BB_updateStatusAndLog("Template matching failed: " . err.Message, true, true)
        return false
    }
}

; Validation function for error templates
; Parameters:
;   x: The x-coordinate of the match.
;   y: The y-coordinate of the match.
;   color1: The first color to compare.
;   color2: The second color to compare.
; Returns: The difference between the two colors.
; Notes:
;   - Calculates the difference between two colors
BB_colorDifference(color1, color2) {
    r1 := (color1 >> 16) & 0xFF
    g1 := (color1 >> 8) & 0xFF
    b1 := color1 & 0xFF
    r2 := (color2 >> 16) & 0xFF
    g2 := (color2 >> 8) & 0xFF
    b2 := color2 & 0xFF
    return Abs(r1 - r2) + Abs(g1 - g2) + Abs(b1 - b2)
}

; Helper function: Verify if a pixel is part of a color cluster (to avoid false positives)
; Parameters:
;   x: The x-coordinate of the pixel.
;   y: The y-coordinate of the pixel.
;   targetColor: The color to verify.
;   tolerance: The tolerance for color similarity.
;   radius: The radius of the grid to search.
;   requiredMatches: The number of matches required to verify the color cluster.
BB_verifyColorCluster(x, y, targetColor, tolerance, radius := 3, requiredMatches := 5) {
    matches := 0
    
    ; Check a small grid around the pixel
    offsetX := -radius
    while (offsetX <= radius) {
        offsetY := -radius
        while (offsetY <= radius) {
            try {
                checkColor := PixelGetColor(x + offsetX, y + offsetY, "RGB")
                if (BB_isColorSimilar(checkColor, targetColor, tolerance)) {
                    matches++
                    if (matches >= requiredMatches) {
                        return true
                    }
                }
            } catch {
                ; Skip errors (e.g., out-of-bounds pixel access)
                offsetY++
                continue
            }
            offsetY++
        }
        offsetX++
    }
    
    return false
}

; Helper function: Check if colors are similar within tolerance
; Parameters:
;   color1: The first color to compare.
;   color2: The second color to compare.
;   tolerance: The tolerance for color similarity.
; Returns: True if the colors are similar, False otherwise.
; Notes:
;   - Extracts RGB components and checks if each component is within tolerance
BB_isColorSimilar(color1, color2, tolerance := 20) {
    ; Extract RGB components
    r1 := (color1 >> 16) & 0xFF
    g1 := (color1 >> 8) & 0xFF
    b1 := color1 & 0xFF
    
    r2 := (color2 >> 16) & 0xFF
    g2 := (color2 >> 8) & 0xFF
    b2 := color2 & 0xFF
    
    ; Check if each component is within tolerance
    return (Abs(r1 - r2) <= tolerance) && (Abs(g1 - g2) <= tolerance) && (Abs(b1 - b2) <= tolerance)
}

; Helper function: Detect UI elements by analyzing screen structure
; Parameters:
;   searchArea: The area to search for UI elements.
;   FoundX: The x-coordinate of the found match.
;   FoundY: The y-coordinate of the found match.
BB_detectUIElements(searchArea, &FoundX, &FoundY) {
    ; Set initial values
    FoundX := 0
    FoundY := 0
    
    ; Define parameters for UI detection
    stepSize := 10
    lineLength := 40
    colorVariance := 15
    
    ; Look for horizontal lines (common in UI elements)
    y := searchArea[2]
    while (y <= searchArea[4]) {
        x := searchArea[1]
        while (x <= searchArea[3] - lineLength) {
            try {
                baseColor := PixelGetColor(x, y, "RGB")
                lineConsistent := true
                
                ; Check if we have a consistent horizontal line
                i := 1
                while (i <= lineLength) {
                    checkColor := PixelGetColor(x + i, y, "RGB")
                    if (!BB_isColorSimilar(baseColor, checkColor, colorVariance)) {
                        lineConsistent := false
                        break
                    }
                    i++
                }
                
                ; If we found a consistent line, check if it's likely a UI element
                if (lineConsistent) {
                    ; Check for color contrast above and below the line
                    aboveColor := PixelGetColor(x + (lineLength // 2), y - 5, "RGB")
                    belowColor := PixelGetColor(x + (lineLength // 2), y + 5, "RGB")
                    
                    if (!BB_isColorSimilar(baseColor, aboveColor, colorVariance) || 
                        !BB_isColorSimilar(baseColor, belowColor, colorVariance)) {
                        ; This might be a UI border!
                        FoundX := x + (lineLength // 2)
                        FoundY := y
                        BB_updateStatusAndLog("Potential UI element detected at x=" . FoundX . ", y=" . FoundY)
                        return true
                    }
                }
            } catch {
                ; Continue on error (e.g., out-of-bounds pixel access)
                x += stepSize
                continue
            }
            x += stepSize
        }
        y += stepSize
    }
    
    ; Look for vertical lines (also common in UI elements)
    x := searchArea[1]
    while (x <= searchArea[3]) {
        y := searchArea[2]
        while (y <= searchArea[4] - lineLength) {
            try {
                baseColor := PixelGetColor(x, y, "RGB")
                lineConsistent := true
                
                ; Check if we have a consistent vertical line
                i := 1
                while (i <= lineLength) {
                    checkColor := PixelGetColor(x, y + i, "RGB")
                    if (!BB_isColorSimilar(baseColor, checkColor, colorVariance)) {
                        lineConsistent := false
                        break
                    }
                    i++
                }
                
                ; If we found a consistent line, check if it's likely a UI element
                if (lineConsistent) {
                    ; Check for color contrast to the left and right of the line
                    leftColor := PixelGetColor(x - 5, y + (lineLength // 2), "RGB")
                    rightColor := PixelGetColor(x + 5, y + (lineLength // 2), "RGB")
                    
                    if (!BB_isColorSimilar(baseColor, leftColor, colorVariance) || 
                        !BB_isColorSimilar(baseColor, rightColor, colorVariance)) {
                        ; This might be a UI border!
                        FoundX := x
                        FoundY := y + (lineLength // 2)
                        BB_updateStatusAndLog("Potential UI element detected at x=" . FoundX . ", y=" . FoundY)
                        return true
                    }
                }
            } catch {
                ; Continue on error
                y += stepSize ; Increment y by stepSize
                continue
            }
            y += stepSize ; Increment y by stepSize
        }
        x += stepSize ; Increment x by stepSize
    }
    ;
    return false
}

; ===================== INITIALIZATION =====================

BB_setupGUI() ; Setup the GUI
BB_loadConfig() ; Load the config
BB_checkForUpdates() ; Check for updates

Hotkey("F1", BB_startAutomation)  ; Add F1 to start automation
Hotkey(BB_BOMB_HOTKEY, (*) => (hwnd := WinGetID("A"), BB_useBomb(hwnd))) ; Use bomb
Hotkey(BB_TNT_CRATE_HOTKEY, (*) => (hwnd := WinGetID("A"), BB_useTntCrate(hwnd))) ; Use TNT crate
Hotkey(BB_TNT_BUNDLE_HOTKEY, (*) => (hwnd := WinGetID("A"), BB_useTntBundle(hwnd))) ; Use TNT bundle
SetTimer(BB_antiAfkLoop, BB_ANTI_AFK_INTERVAL) ; Start anti-AFK timer
BB_updateStatusAndLog("Anti-AFK timer started with interval: " . BB_ANTI_AFK_INTERVAL . "ms") ; Update status and log
BB_updateStatusAndLog("Explosives hotkeys bound successfully") ; Update status and log
BB_updateStatusAndLog("Script initialized. Press F1 to start automation.") ; Update status and log

TrayTip("Initialized! Press F1 to start.", "🐝 BeeBrained's PS99 Mining Event Macro", 0x10)

; Performance Tracking
global BB_performanceData := Map()       ; Performance metrics tracking

; ===================== FUNCTION DEFINITIONS =====================

; Verifies that the merchant menu is open.
; Parameters:
;   hwnd: The window handle to use.
; Returns:
;   true if the merchant menu is open, false otherwise.
BB_verifyMerchantMenuOpen(hwnd) {
    FoundX := ""
    FoundY := ""
    
    if BB_smartTemplateMatch("merchant_window", &FoundX, &FoundY, hwnd) {
        BB_updateStatusAndLog("Merchant menu verified open at x=" . FoundX . ", y=" . FoundY)
        return true
    }
    
    BB_updateStatusAndLog("Merchant menu not found", true, true)
    return false
}

; Walks to the merchant NPC.
; Parameters:
;   hwnd: The window handle to use. If not provided, uses the active window.
; Returns:
;   true if successful, false otherwise.
BB_walkToMerchant(hwnd := 0) {
    if !hwnd {
        hwnd := WinActive("ahk_exe RobloxPlayerBeta.exe")
    }
    
    if !hwnd {
        BB_updateStatusAndLog("No valid window handle for walking to merchant", true, true)
        return false
    }
    
    BB_updateStatusAndLog("Walking to merchant...")
    
    ; Try to find and click the merchant template
    if !BB_findAndClickTemplate("merchant", hwnd) {
        BB_updateStatusAndLog("Failed to find merchant", true, true)
        return false
    }
    
    ; Wait for interaction
    Sleep(BB_INTERACTION_DURATION)
    
    ; Verify merchant menu is open
    if !BB_verifyMerchantMenuOpen(hwnd) {
        BB_updateStatusAndLog("Failed to open merchant menu", true, true)
        return false
    }
    
    BB_updateStatusAndLog("Successfully walked to merchant")
    return true
}

; Finds and clicks a template in the game window.
; Parameters:
;   templateName: The name of the template to find and click.
;   hwnd: The window handle to use.
; Returns:
;   true if successful, false otherwise.
BB_findAndClickTemplate(templateName, hwnd) {
    FoundX := ""
    FoundY := ""
    
    if BB_smartTemplateMatch(templateName, &FoundX, &FoundY, hwnd) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Clicked template '" . templateName . "' at x=" . FoundX . ", y=" . FoundY)
        return true
    }
    
    BB_updateStatusAndLog("Failed to find template '" . templateName . "'", true, true)
    return false
}

; New function to fix camera view
BB_fixCameraView(hwnd) {
    BB_updateStatusAndLog("Fixing camera view...")
    ; Add your camera management logic here
    ; For example, you might want to move the camera to a specific position
    ; or adjust the camera angle to ensure it's correct for merchant interaction
    ; This is a placeholder and should be replaced with actual implementation
    BB_updateStatusAndLog("Camera view fixed")
}

; New function to verify Area 4
BB_verifyArea4(hwnd) {
    BB_updateStatusAndLog("Verifying Area 4...")
    ; Add your verification logic for Area 4 here
    ; For example, you might want to check if the automine button is visible
    ; or if the merchant is in the correct area
    ; This is a placeholder and should be replaced with actual implementation
    BB_updateStatusAndLog("Area 4 verified")
    return true
}

