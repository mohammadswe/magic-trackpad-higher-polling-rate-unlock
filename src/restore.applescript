on run
    set appPath to POSIX path of (path to me)
    set scriptPath to appPath & "Contents/Resources/bin/trackpad-unlock.sh"
    
    tell application "System Events"
        if not (exists file scriptPath) then
            set projectRoot to POSIX path of ((path to me) & ":::")
            set scriptPath to projectRoot & "bin/trackpad-unlock.sh"
        end if
    end tell
    
    try
        do shell script "/bin/bash " & quoted form of scriptPath & " disable"
    on error errMsg number errNum
        display alert "Restore Error" message errMsg as critical
    end try
end run
