#Requires AutoHotkey v2.0
; 🐝 BeeBrained's PS99 Mining Event Automation 🐝
; Last Updated: March 22, 2025

; ===================== GLOBAL VARIABLES =====================

global BB_running := false
global BB_paused := false
global BB_automationState := "Idle"  ; State machine: Idle, Teleporting, Shopping, Mining, Error
global BB_stateHistory := []         ; Track state transitions for debugging
global BB_TEMPLATE_FOLDER := A_Temp "\BB_MiningTemplates"
global BB_BACKUP_TEMPLATE_FOLDER := A_ScriptDir "\backup_templates"
global BB_TEMPLATES := Map()
global BB_TEMPLATE_HASHES := Map()   ; For hash verification
global BB_validTemplates := 0
global BB_totalTemplates := 0
global BB_lastError := "None"
global BB_ENABLE_LOGGING := true
global BB_logFile := A_ScriptDir "\mining_log.txt"
global BB_CONFIG_FILE := A_ScriptDir "\mining_config.ini"
global BB_SAFE_MODE := false         ; Safe mode for testing
global BB_imageCache := Map()        ; Cache for image search results
global BB_performanceData := Map()   ; Track operation times

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

; ===================== UTILITY FUNCTIONS =====================

BB_setState(newState) {
    global BB_automationState, BB_stateHistory
    BB_stateHistory.Push({state: BB_automationState, time: A_Now})
    if (BB_stateHistory.Length > 10)
        BB_stateHistory.RemoveAt(1)
    BB_automationState := newState
    BB_updateStatusAndLog("State changed: " newState)
}

BB_updateStatusAndLog(message, isError := false, takeScreenshot := false) {
    global BB_ENABLE_LOGGING, BB_logFile, BB_lastError
    if BB_ENABLE_LOGGING {
        timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        logMessage := "[" timestamp "] " (isError ? "ERROR: " : "") message "`n"
        FileAppend(logMessage, BB_logFile)
    }
    if isError
        BB_lastError := message
    if takeScreenshot {
        ; Placeholder for screenshot functionality
        ; BB_takeScreenshot()
    }
}

BB_validateImage(filePath) {
    if !FileExist(filePath)
        return "File does not exist"
    ext := StrLower(SubStr(filePath, -3))
    if (ext != ".png")
        return "Invalid extension: " ext " (expected .png)"
    try {
        fileSize := FileGetSize(filePath)
        if (fileSize < 100)
            return "File too small: " fileSize " bytes (minimum 100 bytes)"
    } catch as err {
        return "Failed to get file size: " err.Message
    }
    try {
        file := FileOpen(filePath, "r")
        header := file.Read(8)
        file.Close()
        if (header != Chr(0x89) "PNG" Chr(0x0D) Chr(0x0A) Chr(0x1A) Chr(0x0A))
            return "Invalid PNG header"
    } catch as err {
        return "Failed to read PNG header: " err.Message
    }
    return "Valid"
}

BB_downloadTemplate(templateName, fileName) {
    global BB_TEMPLATE_FOLDER, BB_BACKUP_TEMPLATE_FOLDER, BB_TEMPLATE_HASHES
    templateUrl := "https://raw.githubusercontent.com/xXGeminiXx/BMATMiner/main/mining_templates/" fileName
    localPath := BB_TEMPLATE_FOLDER "\" fileName
    backupPath := BB_BACKUP_TEMPLATE_FOLDER "\" fileName
    try {
        Download(templateUrl, localPath)
        validationResult := BB_validateImage(localPath)
        if (validationResult = "Valid") {
            if BB_TEMPLATE_HASHES.Has(templateName) {
                calculatedHash := BB_calculateFileHash(localPath)
                if (calculatedHash != BB_TEMPLATE_HASHES[templateName]) {
                    BB_updateStatusAndLog("Hash mismatch for " fileName ", using backup")
                    FileCopy(backupPath, localPath, 1)
                }
            }
            BB_updateStatusAndLog("Downloaded and validated template: " fileName)
        } else {
            BB_updateStatusAndLog("Template " fileName " validation failed: " validationResult, true, true)
            FileDelete(localPath)
            if FileExist(backupPath) {
                FileCopy(backupPath, localPath, 1)
                BB_updateStatusAndLog("Using backup template for " fileName)
            }
        }
    } catch as err {
        BB_updateStatusAndLog("Failed to download " fileName ": " err.Message, true, true)
        if FileExist(backupPath) {
            FileCopy(backupPath, localPath, 1)
            BB_updateStatusAndLog("Using backup template for " fileName)
        }
    }
}

BB_calculateFileHash(filePath) {
    ; Placeholder: Implement MD5/SHA1 hash calculation here
    return "placeholder_hash"
}

BB_robustWindowActivation(hwnd) {
    methods := [
        {name: "Standard Activation", fn: () => WinActivate(hwnd)},
        {name: "Focus Control", fn: () => ControlFocus("", hwnd)},
        {name: "Alt-Tab Sequence", fn: () => (SendInput("{Alt down}{Tab}{Tab}{Alt up}"), Sleep(300))}
    ]
    for method in methods {
        try {
            method.fn()
            if WinWaitActive("ahk_id " hwnd, , 2) {
                BB_updateStatusAndLog("Window activated using " method.name)
                return true
            }
        } catch as err {
            BB_updateStatusAndLog("Activation method failed: " method.name)
            Sleep(500)
            continue
        }
    }
    BB_updateStatusAndLog("All window activation methods failed", true)
    return false
}

BB_smartTemplateMatch(templateName, &FoundX, &FoundY, searchArea := "") {
    global BB_TEMPLATE_FOLDER, BB_TEMPLATES, BB_imageCache
    cacheKey := templateName (searchArea ? "_" StrJoin(searchArea, "_") : "")
    if BB_imageCache.Has(cacheKey) {
        coords := BB_imageCache[cacheKey]
        FoundX := coords.x
        FoundY := coords.y
        BB_updateStatusAndLog("Used cached coordinates for " templateName)
        return true
    }
    confidenceLevels := [10, 20, 30, 40]
    for confidence in confidenceLevels {
        try {
            templatePath := BB_TEMPLATE_FOLDER "\" BB_TEMPLATES[templateName]
            if searchArea != ""
                ImageSearch(&FoundX, &FoundY, searchArea[1], searchArea[2], searchArea[3], searchArea[4], "*" confidence " " templatePath)
            else
                ImageSearch(&FoundX, &FoundY, 0, 0, A_ScreenWidth, A_ScreenHeight, "*" confidence " " templatePath)
            if (FoundX != "" && FoundY != "") {
                BB_imageCache[cacheKey] := {x: FoundX, y: FoundY}
                BB_updateStatusAndLog("Found " templateName " at confidence " confidence)
                return true
            }
        } catch as err {
            continue
        }
    }
    variantNames := [templateName "_alt1", templateName "_alt2"]
    for variant in variantNames {
        if BB_TEMPLATES.Has(variant) {
            try {
                templatePath := BB_TEMPLATE_FOLDER "\" BB_TEMPLATES[variant]
                if searchArea != ""
                    ImageSearch(&FoundX, &FoundY, searchArea[1], searchArea[2], searchArea[3], searchArea[4], "*20 " templatePath)
                else
                    ImageSearch(&FoundX, &FoundY, 0, 0, A_ScreenWidth, A_ScreenHeight, "*20 " templatePath)
                if (FoundX != "" && FoundY != "") {
                    BB_imageCache[cacheKey] := {x: FoundX, y: FoundY}
                    BB_updateStatusAndLog("Found " templateName " using variant " variant)
                    return true
                }
            } catch as err {
                continue
            }
        }
    }
    return false
}

StrJoin(arr, delimiter) {
    result := ""
    for i, value in arr
        result .= (i > 1 ? delimiter : "") value
    return result
}

BB_checkForError() {
    global BB_automationState
    FoundX := "", FoundY := ""
    if BB_smartTemplateMatch("error_message", &FoundX, &FoundY) {
        errorActions := Map(
            "Teleporting", () => (SendInput("t"), Sleep(500)),
            "Shopping", () => (SendInput("{Esc}"), Sleep(500)),
            "Mining", () => (SendInput("{f down}"), Sleep(100), SendInput("{f up}"), Sleep(500))
        )
        action := errorActions.Has(BB_automationState) ? errorActions[BB_automationState] : errorActions["Mining"]
        action()
        BB_updateStatusAndLog("Error detected and handled in state " BB_automationState)
        return true
    }
    return false
}

; ===================== STATE MACHINE =====================

BB_miningAutomationLoop() {
    global BB_running, BB_paused, BB_automationState
    if (!BB_running || BB_paused)
        return
    switch BB_automationState {
        case "Idle":
            Sleep(IniRead(BB_CONFIG_FILE, "Timing", "CYCLE_INTERVAL", 60000))
            BB_setState("Teleporting")
        case "Teleporting":
            FoundX := "", FoundY := ""
            if BB_smartTemplateMatch("teleport_button", &FoundX, &FoundY) {
                Click(FoundX, FoundY)
                Sleep(IniRead(BB_CONFIG_FILE, "Timing", "CLICK_DELAY_MIN", 500))
                BB_setState("Shopping")
            } else {
                SendInput("t")  ; Keyboard alternative
                Sleep(500)
                if BB_smartTemplateMatch("area_4_button", &FoundX, &FoundY) {
                    Click(FoundX, FoundY)
                    BB_setState("Shopping")
                } else {
                    BB_setState("Error")
                }
            }
        case "Shopping":
            if BB_smartTemplateMatch("mining_merchant", &FoundX, &FoundY) {
                Click(FoundX, FoundY)
                Sleep(1000)
                if BB_smartTemplateMatch("buy_button", &FoundX, &FoundY) {
                    Click(FoundX, FoundY)
                    BB_setState("Mining")
                } else {
                    BB_setState("Error")
                }
            } else {
                BB_setState("Error")
            }
        case "Mining":
            if BB_smartTemplateMatch("automine_button", &FoundX, &FoundY) {
                Click(FoundX, FoundY)
                Sleep(5000)  ; Simulate mining duration
                BB_setState("Idle")
            } else {
                BB_setState("Error")
            }
        case "Error":
            if BB_checkForError() {
                BB_setState("Idle")
            } else {
                BB_updateStatusAndLog("Unhandled error detected", true)
                BB_setState("Idle")
            }
    }
}

; ===================== INITIALIZATION =====================

BB_loadConfig() {
    global BB_CONFIG_FILE, BB_TEMPLATES, BB_TEMPLATE_HASHES, BB_SAFE_MODE
    if !FileExist(BB_CONFIG_FILE)
        FileAppend(defaultIni, BB_CONFIG_FILE)
    for section in ["Timing", "Window", "Features", "Templates", "Hotkeys", "Retries", "Logging"] {
        for key, value in IniRead(BB_CONFIG_FILE, section)
            if (section = "Templates")
                BB_TEMPLATES[key] := value
    }
    BB_SAFE_MODE := IniRead(BB_CONFIG_FILE, "Features", "SAFE_MODE", "false") = "true"
    ; Placeholder hashes (replace with actual values)
    BB_TEMPLATE_HASHES["teleport_button"] := "placeholder_hash"
}

BB_setupTemplates() {
    global BB_TEMPLATES, BB_TEMPLATE_FOLDER, BB_BACKUP_TEMPLATE_FOLDER
    DirCreate(BB_TEMPLATE_FOLDER)
    DirCreate(BB_BACKUP_TEMPLATE_FOLDER)
    for templateName, fileName in BB_TEMPLATES
        if !FileExist(BB_TEMPLATE_FOLDER "\" fileName)
            BB_downloadTemplate(templateName, fileName)
}

BB_setupGUI() {
    ; Placeholder for GUI setup
}

$F1::
{
    global BB_running
    BB_running := !BB_running
    if BB_running {
        BB_setupTemplates()
        SetTimer(() => BB_miningAutomationLoop(), 1000)
        TrayTip("Automation Started", "🐝 BeeBrained's PS99 Mining Event Macro", 0x10)
    } else {
        SetTimer(() => BB_miningAutomationLoop(), 0)
        TrayTip("Automation Stopped", "🐝 BeeBrained's PS99 Mining Event Macro", 0x10)
    }
}

BB_loadConfig()
BB_setupGUI()
TrayTip("Ready! Press F1 to start.", "🐝 BeeBrained's PS99 Mining Event Macro", 0x10)
