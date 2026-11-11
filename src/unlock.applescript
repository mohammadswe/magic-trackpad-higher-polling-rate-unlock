on run
    set appPath to POSIX path of (path to me)
    set scriptPath to appPath & "Contents/Resources/bin/trackpad-unlock.sh"
    
    -- Fallback to project root if running from development repo
    tell application "System Events"
        if not (exists file scriptPath) then
            set projectRoot to POSIX path of ((path to me) & ":::")
            set scriptPath to projectRoot & "bin/trackpad-unlock.sh"
        end if
    end tell
    
    try
        do shell script "/bin/bash " & quoted form of scriptPath & " enable"
    on error errMsg number errNum
        if errNum is not 2 and errNum is not 9 then
            display alert "Magic Trackpad Unlock Error" message errMsg as critical
        end if
    end try
end run
