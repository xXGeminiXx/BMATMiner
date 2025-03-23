#Requires AutoHotkey v2.0
; 🐝 BeeBrained's PS99 Mining Event Automation 🐝
; Last Updated: March 22, 2025

; ===================== REQUIRED GLOBAL VARIABLES =====================

global BB_running := false                    ; Script running state
global BB_paused := false                     ; Script paused state
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
global BB_TEMPLATE_FOLDER := A_ScriptDir "\mining_templates"  ; Template images folder
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
global BB_MAX_BUY_ATTEMPTS := 6               ; Maximum number of buy buttons to click
global BB_isAutofarming := false              ; Tracks autofarm state
global BB_lastBombStatus := "Idle"            ; Tracks last bomb usage
global BB_lastTntCrateStatus := "Idle"        ; Tracks last TNT crate usage
global BB_lastTntBundleStatus := "Idle"       ; Tracks last TNT bundle usage

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

[Hotkeys]
BOMB_HOTKEY=^b
TNT_CRATE_HOTKEY=^t
TNT_BUNDLE_HOTKEY=^n

[Retries]
TEMPLATE_RETRIES=3
MAX_FAILED_INTERACTIONS=5
MAX_BUY_ATTEMPTS=6

[Logging]
ENABLE_LOGGING=true
)"

; ===================== LOAD CONFIGURATION =====================

BB_loadConfig() {
    global BB_CONFIG_FILE, BB_logFile, BB_ENABLE_LOGGING, BB_WINDOW_TITLE, BB_EXCLUDED_TITLES
    global BB_CLICK_DELAY_MIN, BB_CLICK_DELAY_MAX, BB_INTERACTION_DURATION, BB_CYCLE_INTERVAL
    global BB_TEMPLATE_FOLDER, BB_TEMPLATES, BB_TEMPLATE_RETRIES, BB_MAX_FAILED_INTERACTIONS
    global BB_ANTI_AFK_INTERVAL, BB_RECONNECT_CHECK_INTERVAL, BB_BOMB_INTERVAL
    global BB_TNT_CRATE_INTERVAL, BB_TNT_BUNDLE_INTERVAL, BB_ENABLE_EXPLOSIVES
    global BB_BOMB_HOTKEY, BB_TNT_CRATE_HOTKEY, BB_TNT_BUNDLE_HOTKEY, BB_MAX_BUY_ATTEMPTS

    if !FileExist(BB_CONFIG_FILE) {
        FileAppend(defaultIni, BB_CONFIG_FILE)
        BB_updateStatusAndLog("Created default mining_config.ini")
    }
    
    BB_INTERACTION_DURATION := IniRead(BB_CONFIG_FILE, "Timing", "INTERACTION_DURATION", 5000)
    BB_CYCLE_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "CYCLE_INTERVAL", 60000)
    BB_CLICK_DELAY_MIN := IniRead(BB_CONFIG_FILE, "Timing", "CLICK_DELAY_MIN", 500)
    BB_CLICK_DELAY_MAX := IniRead(BB_CONFIG_FILE, "Timing", "CLICK_DELAY_MAX", 1500)
    BB_ANTI_AFK_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "ANTI_AFK_INTERVAL", 300000)
    BB_RECONNECT_CHECK_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "RECONNECT_CHECK_INTERVAL", 10000)
    BB_BOMB_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "BOMB_INTERVAL", 10000)
    BB_TNT_CRATE_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "TNT_CRATE_INTERVAL", 30000)
    BB_TNT_BUNDLE_INTERVAL := IniRead(BB_CONFIG_FILE, "Timing", "TNT_BUNDLE_INTERVAL", 15000)
    
    BB_WINDOW_TITLE := IniRead(BB_CONFIG_FILE, "Window", "WINDOW_TITLE", "Pet Simulator 99")
    excludedStr := IniRead(BB_CONFIG_FILE, "Window", "EXCLUDED_TITLES", "Roblox Account Manager")
    BB_EXCLUDED_TITLES := StrSplit(excludedStr, ",")
    
    BB_ENABLE_EXPLOSIVES := IniRead(BB_CONFIG_FILE, "Features", "ENABLE_EXPLOSIVES", false)
    
    BB_TEMPLATE_FOLDER := A_ScriptDir "\mining_templates"
    BB_TEMPLATES["automine_button"] := IniRead(BB_CONFIG_FILE, "Templates", "automine_button", "automine_button.png")
    BB_TEMPLATES["go_to_top_button"] := IniRead(BB_CONFIG_FILE, "Templates", "go_to_top_button", "go_to_top_button.png")
    BB_TEMPLATES["teleport_button"] := IniRead(BB_CONFIG_FILE, "Templates", "teleport_button", "teleport_button.png")
    BB_TEMPLATES["area_4_button"] := IniRead(BB_CONFIG_FILE, "Templates", "area_4_button", "area_4_button.png")
    BB_TEMPLATES["area_5_button"] := IniRead(BB_CONFIG_FILE, "Templates", "area_5_button", "area_5_button.png")
    BB_TEMPLATES["mining_merchant"] := IniRead(BB_CONFIG_FILE, "Templates", "mining_merchant", "mining_merchant.png")
    BB_TEMPLATES["buy_button"] := IniRead(BB_CONFIG_FILE, "Templates", "buy_button", "buy_button.png")
    BB_TEMPLATES["merchant_window"] := IniRead(BB_CONFIG_FILE, "Templates", "merchant_window", "merchant_window.png")
    BB_TEMPLATES["autofarm_on"] := IniRead(BB_CONFIG_FILE, "Templates", "autofarm_on", "autofarm_on.png")
    BB_TEMPLATES["autofarm_off"] := IniRead(BB_CONFIG_FILE, "Templates", "autofarm_off", "autofarm_off.png")
    BB_TEMPLATES["error_message"] := IniRead(BB_CONFIG_FILE, "Templates", "error_message", "error_message.png")
    
    BB_BOMB_HOTKEY := IniRead(BB_CONFIG_FILE, "Hotkeys", "BOMB_HOTKEY", "^b")
    BB_TNT_CRATE_HOTKEY := IniRead(BB_CONFIG_FILE, "Hotkeys", "TNT_CRATE_HOTKEY", "^t")
    BB_TNT_BUNDLE_HOTKEY := IniRead(BB_CONFIG_FILE, "Hotkeys", "TNT_BUNDLE_HOTKEY", "^n")
    
    BB_TEMPLATE_RETRIES := IniRead(BB_CONFIG_FILE, "Retries", "TEMPLATE_RETRIES", 3)
    BB_MAX_FAILED_INTERACTIONS := IniRead(BB_CONFIG_FILE, "Retries", "MAX_FAILED_INTERACTIONS", 5)
    BB_MAX_BUY_ATTEMPTS := IniRead(BB_CONFIG_FILE, "Retries", "MAX_BUY_ATTEMPTS", 6)
    
    BB_ENABLE_LOGGING := IniRead(BB_CONFIG_FILE, "Logging", "ENABLE_LOGGING", true)
}

; ===================== GUI SETUP =====================

BB_setupGUI() {
    global BB_myGUI
    BB_myGUI := Gui("+AlwaysOnTop", "🐝 BeeBrained’s PS99 Mining Event Macro 🐝")
    BB_myGUI.OnEvent("Close", BB_exitApp)
    BB_myGUI.Add("Text", "x10 y10 w380 h20", "🐝 F1: Start, F2: Stop, p: Pause, F3: Explosives, Esc: Exit 🐝")
    BB_myGUI.Add("Text", "x10 y40 w380 h20", "Status: Idle").Name := "Status"
    BB_myGUI.Add("Text", "x10 y60 w380 h20", "Active Windows: 0").Name := "WindowCount"
    BB_myGUI.Add("Text", "x10 y80 w380 h20", "Autofarm: Unknown").Name := "AutofarmStatus"
    BB_myGUI.Add("Text", "x10 y100 w380 h20", "Explosives: OFF").Name := "ExplosivesStatus"
    BB_myGUI.Add("Text", "x10 y120 w380 h20", "Bomb: Idle").Name := "BombStatus"
    BB_myGUI.Add("Text", "x10 y140 w380 h20", "TNT Crate: Idle").Name := "TntCrateStatus"
    BB_myGUI.Add("Text", "x10 y160 w380 h20", "TNT Bundle: Idle").Name := "TntBundleStatus"
    BB_myGUI.Add("Text", "x10 y180 w380 h20", "Last Action: None").Name := "LastAction"
    BB_myGUI.Add("Button", "x10 y200 w120 h30", "Reload Config").OnEvent("Click", BB_loadConfigFromFile)
    BB_myGUI.Show("x0 y0 w400 h240")
}

; ===================== HOTKEYS =====================

Hotkey("F1", BB_startAutomation)
Hotkey("F2", BB_stopAutomation)
Hotkey("p", BB_togglePause)
Hotkey("F3", BB_toggleExplosives)
Hotkey("Esc", BB_exitApp)

; ===================== CORE FUNCTIONS =====================

BB_updateStatusAndLog(action, updateGUI := true) {
    global BB_ENABLE_LOGGING, BB_logFile, BB_myGUI, BB_isAutofarming
    global BB_lastBombStatus, BB_lastTntCrateStatus, BB_lastTntBundleStatus
    if BB_ENABLE_LOGGING {
        FileAppend(A_Now ": " action "`n", BB_logFile)
    }
    if updateGUI && IsObject(BB_myGUI) {
        BB_myGUI["Status"].Text := "Status: " (BB_running ? (BB_paused ? "Paused" : "Running") : "Idle")
        BB_myGUI["WindowCount"].Text := "Active Windows: " BB_active_windows.Length
        BB_myGUI["AutofarmStatus"].Text := "Autofarm: " (BB_isAutofarming ? "ON" : "OFF")
        BB_myGUI["ExplosivesStatus"].Text := "Explosives: " (BB_ENABLE_EXPLOSIVES ? "ON" : "OFF")
        BB_myGUI["BombStatus"].Text := "Bomb: " BB_lastBombStatus
        BB_myGUI["TntCrateStatus"].Text := "TNT Crate: " BB_lastTntCrateStatus
        BB_myGUI["TntBundleStatus"].Text := "TNT Bundle: " BB_lastTntBundleStatus
        BB_myGUI["LastAction"].Text := "Last Action: " action
    }
    ToolTip action, 0, 100
    SetTimer(() => ToolTip(), -3000)
}

BB_startAutomation(*) {
    global BB_running, BB_paused
    if BB_running {
        BB_updateStatusAndLog("Already running, ignoring F1 press")
        return
    }
    BB_running := true
    BB_paused := false
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
    SetTimer(BB_miningAutomationLoop, BB_CYCLE_INTERVAL)
}

BB_stopAutomation(*) {
    global BB_running, BB_paused
    BB_running := false
    BB_paused := false
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
    for hwnd in WinGetList() {
        try {
            title := WinGetTitle(hwnd)
            processName := WinGetProcessName(hwnd)
            if (InStr(title, BB_WINDOW_TITLE) && !BB_hasExcludedTitle(title) && processName = "RobloxPlayerBeta.exe") {
                BB_active_windows.Push(hwnd)
                BB_updateStatusAndLog("Found Roblox window: " title " (hwnd: " hwnd ", process: " processName ")")
            } else {
                BB_updateStatusAndLog("Skipped window: " title " (process: " processName ")")
            }
        } catch as err {
            BB_updateStatusAndLog("Error checking window " hwnd ": " err.Message)
        }
    }
    BB_last_window_check := currentTime
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

BB_bringToFront(hwnd) {
    try {
        WinActivate(hwnd)
        if WinWaitActive(hwnd, , 2) {
            BB_updateStatusAndLog("Window activated: " hwnd)
            return true
        }
        BB_updateStatusAndLog("Window activation failed: " hwnd)
        return false
    } catch as err {
        BB_updateStatusAndLog("Window activation error for hwnd " hwnd ": " err.Message)
        return false
    }
}

BB_clickAt(x, y) {
    global BB_CLICK_DELAY_MIN, BB_CLICK_DELAY_MAX
    hwnd := WinGetID("A")
    if (!hwnd || WinGetProcessName(hwnd) != "RobloxPlayerBeta.exe") {
        BB_updateStatusAndLog("No Roblox window active for clicking at x=" x ", y=" y)
        return false
    }
    WinGetPos(&winX, &winY, &winW, &winH, hwnd)
    if (x < winX || x > winX + winW || y < winY || y > winY + winH) {
        BB_updateStatusAndLog("Click coordinates x=" x ", y=" y " are outside window")
        return false
    }
    delay := Random(BB_CLICK_DELAY_MIN, BB_CLICK_DELAY_MAX)
    MouseMove(x, y, 10)
    Sleep(delay)
    Click
    BB_updateStatusAndLog("Clicked at x=" x ", y=" y)
    return true
}

BB_templateMatch(templateName, &FoundX, &FoundY, searchArea := "") {
    global BB_TEMPLATE_FOLDER, BB_TEMPLATES, BB_TEMPLATE_RETRIES, BB_missingTemplatesReported
    templatePath := BB_TEMPLATE_FOLDER "\" BB_TEMPLATES[templateName]
    if !FileExist(templatePath) {
        if !BB_missingTemplatesReported.Has(templateName) {
            BB_updateStatusAndLog("Template file not found: " templatePath)
            BB_missingTemplatesReported[templateName] := true
        }
        return false
    }
    
    retryCount := 0
    while (retryCount < BB_TEMPLATE_RETRIES) {
        try {
            if searchArea != "" {
                BB_updateStatusAndLog("Searching for " templateName " in area: " searchArea[1] "," searchArea[2] " to " searchArea[3] "," searchArea[4])
                ImageSearch(&FoundX, &FoundY, searchArea[1], searchArea[2], searchArea[3], searchArea[4], "*10 " templatePath)
            } else {
                BB_updateStatusAndLog("Searching for " templateName " on entire screen")
                ImageSearch(&FoundX, &FoundY, 0, 0, A_ScreenWidth, A_ScreenHeight, "*10 " templatePath)
            }
            if (FoundX != "" && FoundY != "") {
                BB_updateStatusAndLog("Found " templateName " at x=" FoundX ", y=" FoundY " (attempt " (retryCount + 1) ")")
                return true
            }
        } catch as err {
            BB_updateStatusAndLog("ImageSearch failed for " templateName ": " err.Message " (attempt " (retryCount + 1) ")")
        }
        retryCount++
        Sleep(500)
    }
    BB_updateStatusAndLog("Failed to find " templateName " after " BB_TEMPLATE_RETRIES " retries")
    return false
}

; ===================== ERROR HANDLING =====================

BB_checkForError() {
    FoundX := "", FoundY := ""
    if BB_templateMatch("error_message", &FoundX, &FoundY) {
        BB_updateStatusAndLog("Detected 'Oops! You cannot do that here!' error")
        SendInput("{f down}")
        Sleep(100)
        SendInput("{f up}")
        BB_updateStatusAndLog("Sent F key to dismiss error")
        Sleep(500)
        return true
    }
    return false
}

; ===================== MINING AUTOMATION FUNCTIONS =====================

BB_isAutofarming() {
    global BB_isAutofarming
    FoundX := "", FoundY := ""
    
    ; Check for green circle (autofarm on)
    if BB_templateMatch("autofarm_on", &FoundX, &FoundY) {
        BB_updateStatusAndLog("Autofarm is ON (green circle detected)")
        BB_isAutofarming := true
        return true
    }
    
    ; Check for red circle (autofarm off)
    if BB_templateMatch("autofarm_off", &FoundX, &FoundY) {
        BB_updateStatusAndLog("Autofarm is OFF (red circle detected)")
        BB_isAutofarming := false
        return false
    }
    
    BB_updateStatusAndLog("Could not determine autofarm state")
    return BB_isAutofarming  ; Return last known state if detection fails
}

BB_disableAutomine() {
    FoundX := "", FoundY := ""
    if BB_templateMatch("automine_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Disabled automining")
        Sleep(1000)
        return true
    }
    BB_updateStatusAndLog("Failed to disable automining")
    return false
}

BB_goToTop() {
    FoundX := "", FoundY := ""
    if BB_templateMatch("go_to_top_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Clicked Go to Top")
        Sleep(2000)
        return true
    }
    BB_updateStatusAndLog("Failed to go to top")
    return false
}

BB_openTeleportMenu() {
    FoundX := "", FoundY := ""
    if BB_templateMatch("teleport_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Opened teleport menu")
        Sleep(1000)
        return true
    }
    BB_updateStatusAndLog("Failed to open teleport menu")
    return false
}

BB_teleportToArea(areaTemplate) {
    FoundX := "", FoundY := ""
    if BB_templateMatch(areaTemplate, &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Teleported to " areaTemplate)
        Sleep(2000)
        return true
    }
    BB_updateStatusAndLog("Failed to teleport to " areaTemplate)
    return false
}

BB_interactWithMerchant() {
    FoundX := "", FoundY := ""
    if BB_templateMatch("mining_merchant", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Interacting with merchant")
        Sleep(1000)
        return true
    }
    BB_updateStatusAndLog("Failed to interact with merchant")
    return false
}

BB_buyMerchantItems() {
    global BB_MAX_BUY_ATTEMPTS
    FoundX := "", FoundY := ""
    if !BB_templateMatch("merchant_window", &FoundX, &FoundY) {
        BB_updateStatusAndLog("Merchant window not detected")
        return false
    }
    
    searchArea := [FoundX, FoundY + 50, FoundX + 500, FoundY + 300]
    buyCount := 0
    while (buyCount < BB_MAX_BUY_ATTEMPTS) {
        FoundX := "", FoundY := ""
        if BB_templateMatch("buy_button", &FoundX, &FoundY, searchArea) {
            BB_clickAt(FoundX, FoundY)
            BB_updateStatusAndLog("Clicked buy button " (buyCount + 1))
            buyCount++
            Sleep(500)
        } else {
            BB_updateStatusAndLog("No more buy buttons found after " buyCount " purchases")
            break
        }
    }
    return true
}

BB_enableAutomine() {
    FoundX := "", FoundY := ""
    if BB_templateMatch("automine_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Enabled automining")
        Sleep(1000)
        return true
    }
    BB_updateStatusAndLog("Failed to enable automining")
    return false
}

; ===================== EXPLOSIVES FUNCTIONS =====================

BB_sendHotkeyWithDownUp(hotkey) {
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

    SendInput("{" key " down}")
    Sleep(100)
    SendInput("{" key " up}")

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
}

BB_useBomb() {
    global BB_BOMB_HOTKEY, BB_lastBombStatus
    BB_sendHotkeyWithDownUp(BB_BOMB_HOTKEY)
    BB_lastBombStatus := "Used at " A_Now
    BB_updateStatusAndLog("Used bomb with hotkey: " BB_BOMB_HOTKEY)
    BB_checkForError()
}

BB_useTntCrate() {
    global BB_TNT_CRATE_HOTKEY, BB_lastTntCrateStatus
    BB_sendHotkeyWithDownUp(BB_TNT_CRATE_HOTKEY)
    BB_lastTntCrateStatus := "Used at " A_Now
    BB_updateStatusAndLog("Used TNT crate with hotkey: " BB_TNT_CRATE_HOTKEY)
    BB_checkForError()
}

BB_useTntBundle() {
    global BB_TNT_BUNDLE_HOTKEY, BB_lastTntBundleStatus
    BB_sendHotkeyWithDownUp(BB_TNT_BUNDLE_HOTKEY)
    BB_lastTntBundleStatus := "Used at " A_Now
    BB_updateStatusAndLog("Used TNT bundle with hotkey: " BB_TNT_BUNDLE_HOTKEY)
    BB_checkForError()
}

BB_bombLoop() {
    global BB_running, BB_paused, BB_ENABLE_EXPLOSIVES, BB_isAutofarming
    if (BB_running && !BB_paused && BB_ENABLE_EXPLOSIVES && BB_isAutofarming) {
        BB_useBomb()
    } else {
        BB_updateStatusAndLog("Bomb loop skipped (not running, paused, explosives off, or not autofarming)")
    }
}

BB_tntCrateLoop() {
    global BB_running, BB_paused, BB_ENABLE_EXPLOSIVES, BB_isAutofarming
    if (BB_running && !BB_paused && BB_ENABLE_EXPLOSIVES && BB_isAutofarming) {
        BB_useTntCrate()
    } else {
        BB_updateStatusAndLog("TNT crate loop skipped (not running, paused, explosives off, or not autofarming)")
    }
}

BB_tntBundleLoop() {
    global BB_running, BB_paused, BB_ENABLE_EXPLOSIVES, BB_isAutofarming
    if (BB_running && !BB_paused && BB_ENABLE_EXPLOSIVES && BB_isAutofarming) {
        BB_useTntBundle()
    } else {
        BB_updateStatusAndLog("TNT bundle loop skipped (not running, paused, explosives off, or not autofarming)")
    }
}

; ===================== MAIN AUTOMATION LOOP =====================

BB_miningAutomationLoop() {
    global BB_running, BB_paused, BB_FAILED_INTERACTION_COUNT, BB_MAX_FAILED_INTERACTIONS
    if (!BB_running || BB_paused) {
        BB_updateStatusAndLog("Automation loop skipped (not running or paused)")
        return
    }

    windows := BB_updateActiveWindows()
    if (windows.Length = 0) {
        BB_updateStatusAndLog("No Roblox windows found")
        return
    }

    BB_updateStatusAndLog("Starting automation cycle (" windows.Length " windows)")
    for hwnd in windows {
        if (!BB_running || BB_paused) {
            BB_updateStatusAndLog("Automation loop interrupted")
            break
        }
        BB_updateStatusAndLog("Processing window: " hwnd)
        if !BB_bringToFront(hwnd) {
            BB_FAILED_INTERACTION_COUNT++
            BB_updateStatusAndLog("Skipping window due to activation failure")
            continue
        }

        ; Check for errors before proceeding
        BB_checkForError()

        ; Update autofarm state
        wasAutofarming := BB_isAutofarming()

        if wasAutofarming {
            BB_updateStatusAndLog("Autofarming detected, disabling automine")
            if !BB_disableAutomine() {
                BB_FAILED_INTERACTION_COUNT++
                BB_updateStatusAndLog("Failed to disable automining, skipping window")
                continue
            }
            if !BB_goToTop() {
                BB_FAILED_INTERACTION_COUNT++
                BB_updateStatusAndLog("Failed to go to top, skipping window")
                continue
            }
        } else {
            BB_updateStatusAndLog("Not autofarming, proceeding to merchant steps")
        }

        if !BB_openTeleportMenu() {
            BB_FAILED_INTERACTION_COUNT++
            BB_updateStatusAndLog("Failed to open teleport menu, skipping window")
            continue
        }
        if !BB_teleportToArea("area_4_button") {
            BB_FAILED_INTERACTION_COUNT++
            BB_updateStatusAndLog("Failed to teleport to Area 4, skipping window")
            continue
        }
        if !BB_interactWithMerchant() {
            BB_FAILED_INTERACTION_COUNT++
            BB_updateStatusAndLog("Failed to interact with merchant, skipping window")
            continue
        }
        if !BB_buyMerchantItems() {
            BB_FAILED_INTERACTION_COUNT++
            BB_updateStatusAndLog("Failed to buy items, skipping window")
            continue
        }
        if !BB_openTeleportMenu() {
            BB_FAILED_INTERACTION_COUNT++
            BB_updateStatusAndLog("Failed to open teleport menu (second time), skipping window")
            continue
        }
        if !BB_teleportToArea("area_5_button") {
            BB_FAILED_INTERACTION_COUNT++
            BB_updateStatusAndLog("Failed to teleport to Area 5, skipping window")
            continue
        }
        if wasAutofarming {
            if !BB_enableAutomine() {
                BB_FAILED_INTERACTION_COUNT++
                BB_updateStatusAndLog("Failed to enable automining, continuing")
            }
        }

        BB_updateStatusAndLog("Cycle completed for window: " hwnd)
        BB_FAILED_INTERACTION_COUNT := 0
    }

    if (BB_FAILED_INTERACTION_COUNT >= BB_MAX_FAILED_INTERACTIONS) {
        BB_updateStatusAndLog("Too many failed interactions (" BB_FAILED_INTERACTION_COUNT "), stopping")
        BB_stopAutomation()
        return
    }
    BB_updateStatusAndLog("Cycle completed, next in " BB_CYCLE_INTERVAL // 1000 "s")
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
    MsgBox("Configuration reloaded from " BB_CONFIG_FILE)
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
TrayTip("Ready! Press F1 to start.", "🐝 BeeBrained's PS99 Mining Event Macro", 0x10)
