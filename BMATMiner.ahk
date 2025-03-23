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
global BB_WINDOW_TITLE := "Roblox"            ; Target window title
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
global BB_TNT_CRATE_HOTKEY := "^t"            ; Hotkey for TNT crates (Ctrl+T, placeholder)
global BB_TNT_BUNDLE_HOTKEY := "^n"           ; Hotkey for TNT bundles (Ctrl+N, placeholder)
global BB_MAX_BUY_ATTEMPTS := 6               ; Maximum number of buy buttons to click

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
WINDOW_TITLE=Roblox
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
    
    BB_WINDOW_TITLE := IniRead(BB_CONFIG_FILE, "Window", "WINDOW_TITLE", "Roblox")
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
    BB_myGUI.Add("Text", "x10 y10 w380 h20", "🐝 Use F1 to start, F2 to stop, p to pause, F3 to toggle explosives, Esc to exit 🐝")
    BB_myGUI.Add("Text", "x10 y40 w380 h20", "Status: Idle").Name := "Status"
    BB_myGUI.Add("Text", "x10 y60 w380 h20", "Active Windows: 0").Name := "WindowCount"
    BB_myGUI.Add("Text", "x10 y80 w380 h20", "Explosives: OFF").Name := "ExplosivesStatus"
    BB_myGUI.Add("Button", "x10 y100 w120 h30", "Reload Config").OnEvent("Click", BB_loadConfigFromFile)
    BB_myGUI.Show("x0 y0 w400 h140")
}

; ===================== HOTKEYS =====================

Hotkey("F1", BB_startAutomation)
Hotkey("F2", BB_stopAutomation)
Hotkey("p", BB_togglePause)
Hotkey("F3", BB_toggleExplosives)
Hotkey("Esc", BB_exitApp)

; ===================== CORE FUNCTIONS =====================

BB_updateStatusAndLog(action, updateGUI := true) {
    global BB_ENABLE_LOGGING, BB_logFile, BB_myGUI
    if BB_ENABLE_LOGGING {
        FileAppend(A_Now ": " action "`n", BB_logFile)
    }
    if updateGUI && IsObject(BB_myGUI) && BB_myGUI.HasProp("Status") {
        statusText := "Status: " (BB_running ? (BB_paused ? "Paused" : "Running") : "Idle")
        if action != ""
            statusText .= " - " action
        BB_myGUI["Status"].Text := statusText
    }
    ToolTip action, 0, 100
    SetTimer(() => ToolTip(), -1000)
}

BB_startAutomation(*) {
    global BB_running, BB_paused
    if BB_running
        return
    BB_running := true
    BB_paused := false
    BB_updateStatusAndLog("Running - Starting Mining Automation")
    SetTimer(BB_antiAFKLoop, BB_ANTI_AFK_INTERVAL)
    SetTimer(BB_reconnectCheckLoop, BB_RECONNECT_CHECK_INTERVAL)
    SetTimer(BB_miningAutomationLoop, BB_CYCLE_INTERVAL)
    if BB_ENABLE_EXPLOSIVES {
        SetTimer(BB_bombLoop, BB_BOMB_INTERVAL)
        SetTimer(BB_tntCrateLoop, BB_TNT_CRATE_INTERVAL)
        SetTimer(BB_tntBundleLoop, BB_TNT_BUNDLE_INTERVAL)
    }
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
    BB_updateStatusAndLog("Idle")
}

BB_togglePause(*) {
    global BB_running, BB_paused
    if BB_running {
        BB_paused := !BB_paused
        BB_updateStatusAndLog(BB_paused ? "Paused" : "Running")
        Sleep 200
    }
}

BB_toggleExplosives(*) {
    global BB_ENABLE_EXPLOSIVES, BB_myGUI
    BB_ENABLE_EXPLOSIVES := !BB_ENABLE_EXPLOSIVES
    BB_myGUI["ExplosivesStatus"].Text := "Explosives: " (BB_ENABLE_EXPLOSIVES ? "ON" : "OFF")
    if BB_ENABLE_EXPLOSIVES {
        SetTimer(BB_bombLoop, BB_BOMB_INTERVAL)
        SetTimer(BB_tntCrateLoop, BB_TNT_CRATE_INTERVAL)
        SetTimer(BB_tntBundleLoop, BB_TNT_BUNDLE_INTERVAL)
        BB_updateStatusAndLog("Explosives Enabled")
    } else {
        SetTimer(BB_bombLoop, 0)
        SetTimer(BB_tntCrateLoop, 0)
        SetTimer(BB_tntBundleLoop, 0)
        BB_updateStatusAndLog("Explosives Disabled")
    }
}

BB_updateActiveWindows() {
    global BB_active_windows, BB_last_window_check, BB_WINDOW_TITLE, BB_EXCLUDED_TITLES, BB_myGUI
    currentTime := A_TickCount
    if (currentTime - BB_last_window_check < 5000) {
        return BB_active_windows
    }
    
    BB_active_windows := []
    for hwnd in WinGetList() {
        title := WinGetTitle(hwnd)
        if (InStr(title, BB_WINDOW_TITLE) && !BB_hasExcludedTitle(title) && WinGetProcessName(hwnd) = "RobloxPlayerBeta.exe") {
            BB_active_windows.Push(hwnd)
        }
    }
    if IsObject(BB_myGUI) && BB_myGUI.HasProp("WindowCount") {
        BB_myGUI["WindowCount"].Text := "Active Windows: " BB_active_windows.Length
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
    WinRestore(hwnd)
    WinActivate(hwnd)
    if WinWaitActive(hwnd, , 2) {
        return true
    } else {
        BB_updateStatusAndLog("Failed to activate window: " hwnd)
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
    return true
}

BB_templateMatch(templateName, &FoundX, &FoundY, searchArea := "") {
    global BB_TEMPLATE_FOLDER, BB_TEMPLATES, BB_TEMPLATE_RETRIES, BB_missingTemplatesReported
    templatePath := BB_TEMPLATE_FOLDER "\" BB_TEMPLATES[templateName]
    if !FileExist(templatePath) {
        if !BB_missingTemplatesReported.Has(templateName) {
            BB_updateStatusAndLog("Template not found: " templatePath)
            BB_missingTemplatesReported[templateName] := true
        }
        return false
    }
    
    retryCount := 0
    while (retryCount < BB_TEMPLATE_RETRIES) {
        try {
            if searchArea != "" {
                ImageSearch(&FoundX, &FoundY, searchArea[1], searchArea[2], searchArea[3], searchArea[4], "*10 " templatePath)
            } else {
                ImageSearch(&FoundX, &FoundY, 0, 0, A_ScreenWidth, A_ScreenHeight, "*10 " templatePath)
            }
            if (FoundX != "" && FoundY != "") {
                BB_updateStatusAndLog("Found " templateName " at x=" FoundX ", y=" FoundY)
                return true
            }
        } catch {
            BB_updateStatusAndLog("ImageSearch failed for " templateName)
        }
        retryCount++
        Sleep(500)
    }
    BB_updateStatusAndLog("Failed to find " templateName " after " BB_TEMPLATE_RETRIES " retries")
    return false
}

; ===================== MINING AUTOMATION FUNCTIONS =====================

BB_disableAutomine() {
    FoundX := "", FoundY := ""
    if BB_templateMatch("automine_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Disabled automining")
        Sleep(1000)
        return true
    } else {
        BB_updateStatusAndLog("Failed to find automine button")
        return false
    }
}

BB_goToTop() {
    FoundX := "", FoundY := ""
    if BB_templateMatch("go_to_top_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Clicked Go to Top")
        Sleep(2000)  ; Wait for teleport
        return true
    } else {
        BB_updateStatusAndLog("Failed to find Go to Top button")
        return false
    }
}

BB_openTeleportMenu() {
    FoundX := "", FoundY := ""
    if BB_templateMatch("teleport_button", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Opened teleport menu")
        Sleep(1000)
        return true
    } else {
        BB_updateStatusAndLog("Failed to find teleport button")
        return false
    }
}

BB_teleportToArea(areaTemplate) {
    FoundX := "", FoundY := ""
    if BB_templateMatch(areaTemplate, &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Teleported to " areaTemplate)
        Sleep(2000)  ; Wait for teleport
        return true
    } else {
        BB_updateStatusAndLog("Failed to find " areaTemplate)
        return false
    }
}

BB_interactWithMerchant() {
    FoundX := "", FoundY := ""
    if BB_templateMatch("mining_merchant", &FoundX, &FoundY) {
        BB_clickAt(FoundX, FoundY)
        BB_updateStatusAndLog("Interacting with merchant")
        Sleep(1000)
        return true
    } else {
        BB_updateStatusAndLog("Failed to find merchant")
        return false
    }
}

BB_buyMerchantItems() {
    global BB_MAX_BUY_ATTEMPTS
    ; Verify merchant window is open by checking for the "Merchant!" title
    FoundX := "", FoundY := ""
    if !BB_templateMatch("merchant_window", &FoundX, &FoundY) {
        BB_updateStatusAndLog("Merchant window not detected")
        return false
    }
    
    ; Define a search area around the merchant window (approximate, adjust as needed)
    ; Using the position of the "Merchant!" title to estimate the button area
    searchArea := [FoundX, FoundY + 50, FoundX + 500, FoundY + 300]  ; Adjust these coordinates based on your resolution
    
    ; Repeatedly search for green buy buttons
    buyCount := 0
    while (buyCount < BB_MAX_BUY_ATTEMPTS) {
        FoundX := "", FoundY := ""
        if BB_templateMatch("buy_button", &FoundX, &FoundY, searchArea) {
            BB_clickAt(FoundX, FoundY)
            BB_updateStatusAndLog("Clicked buy button " (buyCount + 1))
            buyCount++
            Sleep(500)  ; Wait for the button to disappear after purchase
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
    } else {
        BB_updateStatusAndLog("Failed to find automine button")
        return false
    }
}

; ===================== EXPLOSIVES FUNCTIONS =====================

BB_useBomb() {
    global BB_BOMB_HOTKEY
    Send(BB_BOMB_HOTKEY)
    BB_updateStatusAndLog("Used bomb with hotkey: " BB_BOMB_HOTKEY)
    Sleep(100)
}

BB_useTntCrate() {
    global BB_TNT_CRATE_HOTKEY
    Send(BB_TNT_CRATE_HOTKEY)
    BB_updateStatusAndLog("Used TNT crate with hotkey: " BB_TNT_CRATE_HOTKEY)
    Sleep(100)
}

BB_useTntBundle() {
    global BB_TNT_BUNDLE_HOTKEY
    Send(BB_TNT_BUNDLE_HOTKEY)
    BB_updateStatusAndLog("Used TNT bundle with hotkey: " BB_TNT_BUNDLE_HOTKEY)
    Sleep(100)
}

BB_bombLoop() {
    global BB_running, BB_paused, BB_ENABLE_EXPLOSIVES
    if BB_running && !BB_paused && BB_ENABLE_EXPLOSIVES {
        BB_useBomb()
    }
}

BB_tntCrateLoop() {
    global BB_running, BB_paused, BB_ENABLE_EXPLOSIVES
    if BB_running && !BB_paused && BB_ENABLE_EXPLOSIVES {
        BB_useTntCrate()
    }
}

BB_tntBundleLoop() {
    global BB_running, BB_paused, BB_ENABLE_EXPLOSIVES
    if BB_running && !BB_paused && BB_ENABLE_EXPLOSIVES {
        BB_useTntBundle()
    }
}

; ===================== MAIN AUTOMATION LOOP =====================

BB_miningAutomationLoop() {
    global BB_running, BB_paused, BB_FAILED_INTERACTION_COUNT, BB_MAX_FAILED_INTERACTIONS
    if (!BB_running || BB_paused)
        return

    windows := BB_updateActiveWindows()
    if (windows.Length = 0) {
        BB_updateStatusAndLog("No Roblox windows found")
        return
    }

    BB_updateStatusAndLog("Running Mining Automation (" windows.Length " windows)")
    for hwnd in windows {
        if (!BB_running || BB_paused)
            break
        if BB_bringToFront(hwnd) {
            ; Step 1: Disable automining
            if !BB_disableAutomine() {
                BB_FAILED_INTERACTION_COUNT++
                continue
            }

            ; Step 2: Go to top
            if !BB_goToTop() {
                BB_FAILED_INTERACTION_COUNT++
                continue
            }

            ; Step 3: Open teleport menu
            if !BB_openTeleportMenu() {
                BB_FAILED_INTERACTION_COUNT++
                continue
            }

            ; Step 4: Teleport to Area 4
            if !BB_teleportToArea("area_4_button") {
                BB_FAILED_INTERACTION_COUNT++
                continue
            }

            ; Step 5: Interact with merchant
            if !BB_interactWithMerchant() {
                BB_FAILED_INTERACTION_COUNT++
                continue
            }

            ; Step 6: Buy items
            if !BB_buyMerchantItems() {
                BB_FAILED_INTERACTION_COUNT++
                continue
            }

            ; Step 7: Open teleport menu again
            if !BB_openTeleportMenu() {
                BB_FAILED_INTERACTION_COUNT++
                continue
            }

            ; Step 8: Teleport to Area 5
            if !BB_teleportToArea("area_5_button") {
                BB_FAILED_INTERACTION_COUNT++
                continue
            }

            ; Step 9: Enable automining
            if !BB_enableAutomine() {
                BB_FAILED_INTERACTION_COUNT++
                continue
            }

            ; Reset failed count on success
            BB_FAILED_INTERACTION_COUNT := 0
        } else {
            BB_FAILED_INTERACTION_COUNT++
        }

        if (BB_FAILED_INTERACTION_COUNT >= BB_MAX_FAILED_INTERACTIONS) {
            BB_updateStatusAndLog("Too many failed interactions, stopping")
            BB_stopAutomation()
            return
        }
    }
    BB_updateStatusAndLog("Completed cycle, next cycle in " BB_CYCLE_INTERVAL // 1000 "s")
}

; ===================== ANTI-AFK AND RECONNECT FUNCTIONS =====================

BB_antiAFKLoop() {
    global BB_running, BB_paused
    if (!BB_running || BB_paused)
        return
    Send("{space down}")
    Sleep(100)
    Send("{space up}")
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
