on run
	set s to load script file ((path to home folder as text) & "Library:Application Scripts:com.apple.mail:MailAvatarSync.scpt")
	-- logo sources only: never replace one monogram with another
	set useMonogramFallback of s to false

	set report to {}
	tell application "Contacts"
		set members to people of group "MailAvatarSync"
		repeat with p in members
			set em to ""
			try
				set em to value of item 1 of emails of p
			end try
			if em is not "" then
				set dom to (s's extractDomain(em))
				if not (s's isGeneric(dom)) then
					set newPath to (s's findAvatar(em, (name of p), dom, false))
					if newPath is not "" then
						try
							set image of p to (read (POSIX file newPath) as picture)
							set end of report to "UPDATED " & em
						on error e
							set end of report to "FAILED  " & em & " " & e
						end try
						s's cleanUp(newPath)
					else
						set end of report to "kept    " & em
					end if
				else
					set end of report to "skip    " & em & " (freemail)"
				end if
			end if
		end repeat
		save
	end tell
	set AppleScript's text item delimiters to linefeed
	return report as string
end run
