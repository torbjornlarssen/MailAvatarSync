(*
   MailAvatarSync - Auto Avatar Fetcher for macOS Mail
   Version 2.0

   Changes vs 1.3.1:
     - api.faviconkit.com now returns a 1x1 placeholder PNG for every domain (dead service)
     - logo.clearbit.com no longer resolves in DNS (shut down)
     Both are replaced with DuckDuckGo + Google favicon services.
     - Added a locally drawn monogram fallback so every sender gets something.
     - Logs on every path, so silence now means "never ran" rather than "found nothing".

   Install:
     1. Save as "MailAvatarSync.scpt" in ~/Library/Application Scripts/com.apple.mail/
     2. Mail > Settings > Rules > Run AppleScript
     3. Quit and reopen Mail (it caches the compiled script)
   Watch it work:  tail -f ~/Library/Logs/MailAvatarSync.log
*)

-- === CONFIGURATION ===

property targetGroupName : "MailAvatarSync"
property addNoteSignature : true

-- Draw a coloured initials avatar when no real logo/photo exists.
-- This is what takes you from "almost nothing" to "every sender". Set to false
-- if you only want genuine logos and photos.
property useMonogramFallback : true

-- Log every decision (not just errors) to Console.
property verboseLogging : true

-- Domains where a company logo makes no sense (senders are individuals).
property freemailDomains : {"gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "icloud.com", "me.com", "mac.com", "yahoo.com", "yandex.ru", "mail.ru", "bk.ru", "inbox.ru", "proton.me", "protonmail.com", "fastmail.com", "gmx.net", "web.de", "online.no", "hotmail.no"}

-- Bulk mail arrives from subdomains like news.email.example.com, which usually have
-- no website and no favicon of their own. We walk up to email.example.com, then
-- example.com.
property multiPartSuffixes : {"co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "net.uk", "com.au", "net.au", "org.au", "edu.au", "gov.au", "co.nz", "net.nz", "org.nz", "co.jp", "or.jp", "ne.jp", "com.br", "com.mx", "com.cn", "com.tr", "co.za", "co.in", "com.sg", "com.hk", "co.kr", "com.pl", "com.ar", "com.tw"}

-- Ask the sender's own web server for /apple-touch-icon.png. This gives the best
-- quality (often 180px vs DuckDuckGo's 32px) and finds logos the icon aggregators
-- have never indexed -- but it does reveal your IP address to the sender's server.
-- Set to false to rely only on DuckDuckGo and Google.
property probeSenderDomain : true

property monogramSource : "ObjC.import('Cocoa'); function run(a){var t=a[0],h=parseFloat(a[1]),o=a[2],S=256; var i=$.NSImage.alloc.initWithSize($.NSMakeSize(S,S)); i.lockFocus; $.NSColor.colorWithCalibratedHueSaturationBrightnessAlpha(h,0.55,0.70,1.0).set; $.NSBezierPath.bezierPathWithOvalInRect($.NSMakeRect(0,0,S,S)).fill; var d=$.NSMutableDictionary.alloc.init; d.setObjectForKey($.NSFont.systemFontOfSizeWeight(t.length>1?104:128,0.3),'NSFont'); d.setObjectForKey($.NSColor.whiteColor,'NSColor'); var s=$(t); var z=s.sizeWithAttributes(d); s.drawAtPointWithAttributes($.NSMakePoint((S-z.width)/2,(S-z.height)/2),d); i.unlockFocus; var r=$.NSBitmapImageRep.imageRepWithData(i.TIFFRepresentation); r.representationUsingTypeProperties(4,$.NSDictionary.dictionary).writeToFileAtomically($(o),true); return 'ok';}"


using terms from application "Mail"
	on perform mail action with messages theMessages for rule theRule
		repeat with eachMessage in theMessages
			try
				set senderString to sender of eachMessage
				set theEmail to my extractEmail(senderString)
				set theName to my extractName(senderString)
				if theEmail is not "" then my processEmail(theName, theEmail)
			on error errMsg
				my logIt("error reading message: " & errMsg)
			end try
		end repeat
	end perform mail action with messages
end using terms from


-- === Main Logic ===

on processEmail(rawName, rawEmail)
	set theEmail to my trimStr(rawEmail)
	set theName to my trimStr(rawName)
	if theEmail does not contain "@" then return

	set theDomain to my extractDomain(theEmail)
	set isFreemail to my isGeneric(theDomain)

	-- Bail out before any network traffic if this sender is already sorted.
	try
		tell application "Contacts"
			set matches to (every person whose value of emails contains theEmail)
			if matches is not {} then
				if (image of (item 1 of matches)) is not missing value then
					my logIt("skip, already has a photo: " & theEmail)
					return
				end if
			end if
		end tell
	on error errMsg
		my logIt("Contacts lookup failed (is Mail allowed to control Contacts in System Settings > Privacy & Security > Automation?): " & errMsg)
		return
	end try

	set avatarPath to my findAvatar(theEmail, theName, theDomain, isFreemail)
	if avatarPath is "" then
		my logIt("no avatar available for " & theEmail)
		return
	end if

	try
		set imgData to (read (POSIX file avatarPath) as picture)
	on error errMsg
		my logIt("could not read image for " & theEmail & ": " & errMsg)
		my cleanUp(avatarPath)
		return
	end try

	try
		tell application "Contacts"
			if not (exists group targetGroupName) then
				make new group with properties {name:targetGroupName}
				save
			end if
			set theGroup to group targetGroupName

			set foundPeople to (every person whose value of emails contains theEmail)

			if foundPeople is not {} then
				set targetPerson to item 1 of foundPeople
				if (image of targetPerson) is missing value then
					set image of targetPerson to imgData
					my logIt("added photo to existing contact: " & (name of targetPerson))
				end if
				set groupPersonIDs to id of people of theGroup
				if (id of targetPerson) is not in groupPersonIDs then add targetPerson to theGroup
			else
				set noteText to ""
				if addNoteSignature then
					set noteText to "Auto-created by MailAvatarSync on " & ((current date) as text)
				end if

				if isFreemail then
					-- A human: store as a normal person so Mail shows the name properly.
					set nameParts to my splitName(theName, theEmail)
					set newPerson to make new person with properties ¬
						{first name:(item 1 of nameParts), last name:(item 2 of nameParts), note:noteText}
				else
					set orgName to theName
					if orgName is "" or orgName is theEmail then set orgName to theDomain
					set newPerson to make new person with properties ¬
						{organization:orgName, company:true, first name:"", last name:"", note:noteText}
				end if

				make new email at end of emails of newPerson with properties {label:"work", value:theEmail}
				set image of newPerson to imgData
				add newPerson to theGroup
				my logIt("created contact for " & theEmail)
			end if
			save
		end tell
	on error errMsg
		my logIt("Contacts write failed for " & theEmail & ": " & errMsg)
	end try

	my cleanUp(avatarPath)
end processEmail


-- === Avatar Fetching Strategy ===

on findAvatar(emailAddr, theName, domainPart, isFreemail)
	-- 1. Gravatar: a real photo the person chose. Always worth trying first.
	set p to my downloadImage("https://www.gravatar.com/avatar/" & my getMD5(emailAddr) & "?d=404&s=256")
	if p is not "" then
		my logIt("gravatar hit: " & emailAddr)
		return p
	end if

	-- 2. Logo, walking from the full sending host up to the registrable domain.
	if not isFreemail and domainPart is not "" then
		repeat with dRef in my domainCandidates(domainPart)
			set d to dRef as string

			if probeSenderDomain then
				set p to my downloadImage("https://" & d & "/apple-touch-icon.png")
				if p is not "" then
					my logIt("apple-touch-icon " & d & " (sender " & domainPart & ")")
					return p
				end if
				set p to my downloadImage("https://" & d & "/apple-touch-icon-precomposed.png")
				if p is not "" then
					my logIt("apple-touch-icon-precomposed " & d)
					return p
				end if
			end if

			set p to my downloadImage("https://icons.duckduckgo.com/ip3/" & d & ".ico")
			if p is not "" then
				my logIt("duckduckgo " & d & " (sender " & domainPart & ")")
				return p
			end if

			set p to my downloadImage("https://www.google.com/s2/favicons?domain=" & d & "&sz=128")
			if p is not "" then
				my logIt("google " & d & " (sender " & domainPart & ")")
				return p
			end if
		end repeat
	end if

	-- 3. Locally drawn initials. No network, works for every sender.
	if useMonogramFallback then
		set p to my makeMonogram(emailAddr, theName)
		if p is not "" then
			my logIt("monogram: " & emailAddr)
			return p
		end if
	end if

	return ""
end findAvatar


on downloadImage(urlStr)
	try
		set tmpFile to do shell script "mktemp -t mas_dl"
		try
			do shell script "curl -L -s -f --connect-timeout 3 --max-time 5 " & quoted form of urlStr & " -o " & quoted form of tmpFile
		on error
			my cleanUp(tmpFile)
			return ""
		end try

		-- A 1x1 or 16x16 tracking pixel is worse than no avatar at all, so judge
		-- by real pixel dimensions rather than file size.
		set pngFile to tmpFile & ".png"
		do shell script "sips -s format png --resampleHeightWidthMax 256 " & quoted form of tmpFile & " --out " & quoted form of pngFile & " >/dev/null 2>&1 || true"
		my cleanUp(tmpFile)

		try
			set w to (do shell script "sips -g pixelWidth " & quoted form of pngFile & " 2>/dev/null | awk '/pixelWidth/{print $2}'") as integer
		on error
			my cleanUp(pngFile)
			return ""
		end try

		if w < 32 then
			my cleanUp(pngFile)
			return ""
		end if
		return pngFile
	on error
		return ""
	end try
end downloadImage


on makeMonogram(emailAddr, theName)
	try
		set initials to my getInitials(theName, emailAddr)
		-- Deterministic colour, so a sender keeps the same one forever.
		set hueHex to text 1 thru 2 of my getMD5(emailAddr)
		set hueVal to (do shell script "printf '%.3f' $(echo 'scale=4; ' $((16#" & hueHex & ")) ' / 255' | bc)")

		set scriptPath to (do shell script "echo \"$TMPDIR\"") & "mas_monogram.js"
		do shell script "printf '%s' " & quoted form of monogramSource & " > " & quoted form of scriptPath

		set outFile to (do shell script "mktemp -t mas_mono") & ".png"
		do shell script "osascript -l JavaScript " & quoted form of scriptPath & " " & quoted form of initials & " " & quoted form of hueVal & " " & quoted form of outFile & " >/dev/null 2>&1"

		do shell script "test -s " & quoted form of outFile
		return outFile
	on error errMsg
		my logIt("monogram generation failed: " & errMsg)
		return ""
	end try
end makeMonogram


on domainCandidates(host)
	set res to {}
	set cur to host
	repeat
		set end of res to cur
		set n to my countLabels(cur)
		if n < 2 then exit repeat
		set minLabels to 2
		if my lastTwoLabels(cur) is in multiPartSuffixes then set minLabels to 3
		if n <= minLabels then exit repeat
		set oldDelims to AppleScript's text item delimiters
		set AppleScript's text item delimiters to "."
		set parts to text items of cur
		set cur to (items 2 thru -1 of parts) as string
		set AppleScript's text item delimiters to oldDelims
	end repeat
	return res
end domainCandidates

on countLabels(h)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "."
	set n to count of (text items of h)
	set AppleScript's text item delimiters to oldDelims
	return n
end countLabels

on lastTwoLabels(h)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "."
	set parts to text items of h
	if (count of parts) < 2 then
		set AppleScript's text item delimiters to oldDelims
		return h
	end if
	set res to ((item -2 of parts) & "." & (item -1 of parts))
	set AppleScript's text item delimiters to oldDelims
	return res
end lastTwoLabels


-- === Utilities ===

on extractEmail(s)
	if s contains "<" then
		set oldDelims to AppleScript's text item delimiters
		set AppleScript's text item delimiters to {"<", ">"}
		try
			set res to text item 2 of s
		on error
			set res to s
		end try
		set AppleScript's text item delimiters to oldDelims
		return res
	end if
	return s
end extractEmail

on extractName(s)
	if s contains "<" then
		set oldDelims to AppleScript's text item delimiters
		set AppleScript's text item delimiters to "<"
		set res to text item 1 of s
		set AppleScript's text item delimiters to oldDelims
		return res
	end if
	return ""
end extractName

on extractDomain(e)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "@"
	try
		set res to text item 2 of e
	on error
		set res to ""
	end try
	set AppleScript's text item delimiters to oldDelims
	return res
end extractDomain

on splitName(theName, theEmail)
	set n to my trimStr(theName)
	if n is "" or n is theEmail then return {theEmail, ""}
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to " "
	set parts to text items of n
	set AppleScript's text item delimiters to oldDelims
	if (count of parts) is 1 then return {n, ""}
	set firstN to item 1 of parts
	set lastN to ""
	repeat with i from 2 to (count of parts)
		if lastN is "" then
			set lastN to item i of parts
		else
			set lastN to lastN & " " & item i of parts
		end if
	end repeat
	return {firstN, lastN}
end splitName

on getInitials(theName, theEmail)
	set n to my trimStr(theName)
	if n is "" or n is theEmail then
		set oldDelims to AppleScript's text item delimiters
		set AppleScript's text item delimiters to "@"
		set n to text item 1 of theEmail
		set AppleScript's text item delimiters to oldDelims
		set n to my replaceText(my replaceText(my replaceText(n, ".", " "), "-", " "), "_", " ")
	end if
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to " "
	set parts to text items of n
	set AppleScript's text item delimiters to oldDelims

	set letters to ""
	repeat with p in parts
		set pp to my trimStr(p as string)
		if pp is not "" and (length of letters) < 2 then set letters to letters & (character 1 of pp)
	end repeat
	if letters is "" then set letters to "?"
	return do shell script "printf '%s' " & quoted form of letters & " | tr '[:lower:]' '[:upper:]'"
end getInitials

on replaceText(s, findStr, replStr)
	set oldDelims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to findStr
	set parts to text items of s
	set AppleScript's text item delimiters to replStr
	set res to parts as string
	set AppleScript's text item delimiters to oldDelims
	return res
end replaceText

on trimStr(s)
	set t to s as string
	repeat while t is not "" and (character 1 of t is in {" ", tab, quote})
		if (length of t) is 1 then return ""
		set t to text 2 thru -1 of t
	end repeat
	repeat while t is not "" and (character -1 of t is in {" ", tab, quote})
		if (length of t) is 1 then return ""
		set t to text 1 thru -2 of t
	end repeat
	return t
end trimStr

on getMD5(s)
	return do shell script "printf '%s' " & quoted form of s & " | tr '[:upper:]' '[:lower:]' | md5 -q"
end getMD5

on isGeneric(d)
	if d is "" then return true
	return (d is in freemailDomains)
end isGeneric

on cleanUp(f)
	try
		do shell script "rm -f " & quoted form of f
	end try
end cleanUp

on logIt(msg)
	if not verboseLogging then return
	-- logger output is Info-level and is NOT persisted, so `log show` will never
	-- find it after the fact; only `log stream` catches it live. The file is the
	-- one you can actually read later.
	try
		do shell script "logger -t 'MailAvatarSync' " & quoted form of msg
	end try
	try
		do shell script "printf '%s %s\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" " & quoted form of msg & " >> \"$HOME/Library/Logs/MailAvatarSync.log\""
	end try
end logIt
