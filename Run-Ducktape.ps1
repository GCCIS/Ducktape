# Imports data from the RIT API into an Exchange Calendar
# 
# Author:  Jimmy McNatt

[CmdletBinding()]

param
(
	[Parameter(Position = 0, Mandatory = $false)]
	[String] $ConfigFilePath,
	
	[Parameter(Position = 1, Mandatory = $false)]
	[Switch] $FixedDays,
	
	[Parameter(Position = 2, Mandatory = $false)]
	[DateTime] $StartTime,
	
	[Parameter(Position = 3, Mandatory = $false)]
	[DateTime] $EndTime,
	
	[Parameter(Position = 4, Mandatory = $false)]
	[Int] $Days
)

begin
{	
	# Global Event PSObject array
	$script:Rooms = @()
	
	function Write-Event
	{
        ###############################################################################################################################################
	    #.SYNOPSIS
	    # Writes an event to the log file, and prints the information in the Powershell window (if used).
	    # 
	    #.DESCRIPTION
	    # This function should be used to write all informational, warning, and error-related messages.
	    # It uses the $LogEnabled variable imported from the configuration file to determine whether or not to write to the event log file.
	    # The $LogFilePath is used to determine the location of the log file.
	    #
	    #.PARAMETER Type
	    # The type of event.  Should be either "Info" "Warning" or "Error."
	    #
	    #.PARAMETER Message
	    # The message to write.
	    #
	    #.EXAMPLE
	    # Write-Event -Type "Info" -Message "This is an awesome informational message."
	    #
	    #.EXAMPLE
	    # Write-Event -Type "Error" -Message "This is a terrible error.  You should probably do something about it."
	    ###############################################################################################################################################

		[CmdletBinding()]
		
		param
		(			
			[Parameter(Position = 0, Mandatory = $true)]
			[ValidateSet("Info", "Error", "Warning")]
			[String] $Type,
			
			[Parameter(Position = 1, Mandatory = $true, ValueFromPipeLine = $true)]
			[ValidateNotNullOrEmpty()]
			[String] $Message
		)
		
		if ($private:Type -like "Info")
		{ 
			Write-Host -Object ((Get-Variable MyInvocation -Scope 1).Value.MyCommand.Name + ': ') -ForegroundColor Green -NoNewline
			Write-Host -Object $private:Message
		}
		
		elseif ($private:Type -like "Warning") { Write-Warning $private:Message -WarningAction Continue }
		elseif ($private:Type -like "Error") { Write-Error -CategoryReason (Get-Variable MyInvocation -Scope 1).Value.MyCommand.Name -Message $private:Message }
		
		if ($script:LogEnabled)
		{
			Out-File -Append -FilePath $script:LogFilePath -Encoding Unicode -InputObject ((Get-Variable MyInvocation -Scope 1).Value.MyCommand.Name + ": " + $private:Message)
		}
	}		
		
	function Load-Configuration
	{
        ###############################################################################################################################################
	    #.SYNOPSIS
	    # Loads the configuration file into global variables used by other functions.
	    # 
	    #.DESCRIPTION
	    # This function should be called in the process{} block of the script to populate global variables.
	    # The configuration file path can be specified on the command line, or it can be contained in the directory of the executable. If the
	    # configuration file is invalid, the entire script will exit.
	    ###############################################################################################################################################


		# Attempt to open the XML configuration file.
		# It could be specified by the -ConfigFilePath parameter, and if not, the script will look for .\config.xml in the current directory.
		# Failure to open this file will hault the script.
		if (-not $script:ConfigFilePath)
		{
			$script:ConfigFilePath = ".\config.xml"
			Write-Event -Type "Info" -Message "ConfigFilePath was not specified as an arguement. Looking for 'config.xml' in the executable directory."
		}
		
		try
		{
			[XML] $private:Config = Get-Content $script:ConfigFilePath -ErrorAction Stop
		}
		
		catch
		{
			Write-Event -Type "Error" -Message "Error loading configuration file. Check the file contents and documentation for proper file formatting."
			Exit
		}		
		
		# SECTION 1 - (Config --> Settings)
		# Get the RefresInterval setting (Config --> Settings -> RefreshInterval)
		if (-not $private:Config.Config.Settings.RefreshInterval)
		{
			$script:RefreshInterval = 900
			Write-Event -Type "Warning" -Message "Could not determine the RefreshInterval. Using '900' as default value."
		}
		
		else
		{
			$script:RefreshInterval = $private:Config.Config.Settings.RefreshInterval
			Write-Event -Type "Info" -Message "RefreshInterval is $script:RefreshInterval"
		}
		
		# Get the OutputDirectory setting (Config --> Settings --> OutputDirectory)
		if (-not $private:Config.Config.Settings.OutputDirectory)
		{
			$script:OutputDirectory = '.\'
			Write-Event -Type "Warning" -Message "Could not determine the output directory for JSON. The output will be the executable directory."
		}
		
		else
		{
			$script:OutputDirectory = $private:Config.Config.Settings.OutputDirectory
			Write-Event -Type "Info" -Message "Output directory for JSON is $script:OutputDirectory"
		}
		
		# Get the EWSPath setting (Config --> Settings --> EWSPath)
		if ($private:Config.Config.Settings.EWSPath)
		{
			if (Test-Path $private:Config.Config.Settings.EWSPath)
			{
				$script:EWSPath = $private:Config.Config.Settings.EWSPath
				Write-Event -Type "Info" -Message "EWS path is $script:EWSPath"
			}
			
			else
			{
				Write-Event -Type "Error" -Message "Could not load the EWS dll. Check the path specified in the configuration file."
				Exit
			}
		}
		
		else
		{
			$private:EWSDefaultPath = "C:\Program Files\Microsoft\Exchange\Web Services\2.2\Microsoft.Exchange.WebServices.dll"
			Write-Event -Type "Warning" -Message "Could not determine the EWSPath for the EWS dll. Attempting to use the default EWS 2.2 install path."
			if (-not (Test-Path $private:EWSDefaultPath))
			{
				Write-Event -Type "Error" -Message "Could not load the EWS dll. Check the configuration file and ensure the Exchange Web Services API files are installed."
				Exit
			}
			
			else
			{
				$script:EWSPath = $private:EWSDefaultPath
				Write-Event -Type "Info" -Message "EWS path is $script:EWSPath"
			}
		}
		
		# Get the ApiPath setting (Config --> Settings --> ApiPath
		if ($private:Config.Config.Settings.ApiPath)
		{
			$script:ApiPath = $private:Config.Config.Settings.ApiPath
			Write-Event -Type "Info" -Message "ApiPath is $script:ApiPath"
		}
		
		else
		{
			$private:DefaultApiPath = "http://api.rit.edu"
			Write-Event -Type "Warning" -Message "Could not determine API Path. The ApiPath is set to $private:DefaultApiPath"
			$script:ApiPath = $private:DefaultApiPath
		}
		
		# Get the ApiKey setting (Config --> Settings --> ApiKey)
		if ($private:Config.Config.Settings.ApiKey)
		{
			$script:ApiKey = $private:Config.Config.Settings.ApiKey
			Write-Event -Type "Info" -Message "ApiKey is `"$script:ApiKey`""
		}
		
		else
		{
			Write-Event -Type "Warning" -Message "ApiKey is not defined. This could cause 401 Unauthorized messages to be returned from the API."
		}
		
		# Determine the start and end times based on the configuration file or the parameters of this script.
		# The configuration XML path is (Config --> Settings --> StartTime) and (Config --> Settings --> EndTime)
		# If the parameters of this script are not specified, the configuration file will be used.
		# If the configuration file is not valid AND the parameters are not specified, the script will sync a room from this current day to 60 days from now.
		# If the -FixedDays switch is thrown on the script:
		#    * The -Days parameter will determine the EndTime based on the StartTime.
		#    * If the -StartTime parameter is not specified, the script will use this current day.
		#    * The configuration file StartTime and EndTime are always ignored when the -FixedDays switch is thrown.
		if ($script:FixedDays -and $script:Days)
		{
			if (-not $script:StartTime)
			{
				Write-Event -Type "Info" -Message "Parameter -StartTime not specified. Using today's date as StartTime."
				$script:StartTime = Get-Date -Uformat "%Y-%m-%d"
			}
			
			else
			{
				$script:EndTime = ($script:StartTime.AddDays($script:Days)).AddMinutes(-1)
			}
		}
		
		else
		{
			if ($script:FixedDays)
			{
				Write-Event -Type "Warning" -Message "Parameter -FixedDays specified, but the -Days parameter was not specified. `
					Using configuration file for StartTime and EndTime."
			}
			
			if ($private:Config.Config.Settings.StartTime)
			{
				try
				{
					$script:StartTime = [DateTime] $private:Config.Config.Settings.StartTime
				}
				
				catch
				{
					Write-Event -Type "Error" -Message "Error parsing StartTime from configuration file. Invalid DateTime specified."
					$script:StartTime = Get-Date -Uformat "%Y-%m-%d"
				}
			}
			
			else
			{
				Write-Event -Type "Warning" -Message "Could not determine StartTime from configuration file. Using today's date as StartTime."
				$script:StartTime = Get-Date -Uformat "%Y-%m-%d"
			}
			
			if ($private:Config.Config.Settings.EndTime)
			{
				try
				{
					$script:EndTime = [DateTime] $private:Config.Config.Settings.EndTime
				}
				
				catch
				{
					Write-Event -Type "Error" -Message "Error parsing EndTime from configuration file. Invalid DateTime specified."
					$script:EndTime = (($script:StartTime.AddDays(60)).AddMinutes(-1)).AddSeconds(59)
				}
			}
			
			else
			{
				Write-Event -Type "Warning" -Message "Could not deterine EndTime from configuration file. EndTime will be set to 60 days from today's date."
				$script:EndTime = (($script:StartTime.AddDays(60)).AddMinutes(-1)).AddSeconds(59)
			}
		}
		
		Write-Event -Type "Info" -Message "StartTime is $script:StartTime."
		Write-Event -Type "Info" -Message "EndTime is $script:EndTime."
		
		# SECTION 2 - (Config --> Credentials)
		# Get the credentials from the configuration file
		if ($private:Config.Config.Credentials.Username -and $private:Config.Config.Credentials.Password)
		{
			$script:Username = $private:Config.Config.Credentials.Username
			$script:Password = $private:Config.Config.Credentials.Password
			Write-Event -Type "Info" -Message "Exchange username is '$script:Username'."
		}
		
		else
		{
			Write-Event -Type "Error" -Message "Could not determine the username and/or password from configuration file. Check the configuration file `
				and ensure the username and password values are set."
		}
		
		$script:Domain = $private:Config.Config.Credentials.Domain
		Write-Event -Type "Info" -Message "Exchange domain is '$script:Domain'."
		
		# Section 3
		# Get each Room defined in the config
		foreach ($Room in $private:Config.Config.Room)
		{
			if ($private:Room.Name -and $private:Room.Number -and $private:Room.Calendar -and $private:Room.FileName)
			{
				$private:ThisRoom = @{
					"Name" = $private:Room.Name;
					"Number" = $private:Room.Number;
					"Calendar" = $private:Room.Calendar;
					"FileName" = $private:Room.FileName;
				}
				
				$script:Rooms += $private:ThisRoom
				Write-Event -Type "Info" -Message ($private:Room.Name.ToString() + " loaded successfully.")
			}
			
			else
			{
				Write-Event -Type "Error" -Message "Could not load room. Check configuration file and ensure rooms are defined correctly."
			}
		}
	}
	
	function Sync-Room
	{
		[CmdletBinding()]
		
		param
		(
			[Parameter(Position = 1, Mandatory = $true)]
			[Microsoft.Exchange.WebServices.Data.ExchangeService] $Service,
			
			[Parameter(Position = 2, Mandatory = $true)]
			[String] $RoomNumber,
			
			[Parameter(Position = 3, Mandatory = $true)]
			[String] $MailboxAddress
		)
		
		# Get the Exchange calendar folder
		$private:Service.AutoDiscoverUrl($MailboxAddress)
		$private:FolderID = New-Object Microsoft.Exchange.WebServices.Data.FolderID([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Calendar,$private:MailboxAddress)
		$private:CalendarFolder = [Microsoft.Exchange.WebServices.Data.CalendarFolder]::Bind($private:Service, $private:FolderID)
		if (-not $private:CalendarFolder) { throw "Exchange bind was unsuccessful" }
		else { Write-Event -Type "Info" -Message "$($private:MailboxAddress): Exchange bind was successful." }
				
		# Get all meetings in the room from the API
		$private:ApiRoomEventObjects = ConvertJsonTo-EventObjects -Room $private:RoomNumber
		$private:ApiRoomEventObjectsCount = $private:ApiRoomEventObjects.Count
		Write-Event -Type "Info" -Message "$private:ApiRoomEventObjectsCount event objects converted from API."
		
		# Get all meetings in the room from Exchange
		$private:ExchangeRoomEventObjects = ConvertExchangeAppointmentsTo-EventObjects -CalendarFolder $private:CalendarFolder
		$private:ExchangeRoomEventObjectsCount = $private:ExchangeRoomEventObjects.Count
		Write-Event -Type "Info" -Message "$private:ExchangeRoomEventObjectsCount event objects converted from Exchange."

		
		# STEP 1
		# Interate through all API event objects
		#   If they exist in Exchange, make sure they are correct
		#   Else, create a new exchange object
		#	If they exist in the database, make they are correct
		#	Else, create a new row
		foreach ($Key in $private:ApiRoomEventObjects.Keys)
		{
			$private:ApiRoomEventObject = $private:ApiRoomEventObjects.Get_Item($private:Key)			

			if ($private:ExchangeRoomEventObjects.ContainsKey($private:Key))
			{
				$private:ExchangeRoomEventObject = $private:ExchangeRoomEventObjects.Get_Item($private:Key)
					
				Update-ExchangeAppointment -Service $private:Service -FolderId $private:FolderId -ExchangeRoomEventObject $private:ExchangeRoomEventObject -ApiEventObject $private:ApiRoomEventObject
			}
			
			else
			{
				ConvertEventObjectTo-ExchangeAppointment -Service $private:Service -FolderId $private:FolderId -EventObject $private:ApiRoomEventObject
			}
		}
					
	}
	
	function Get-EventTitle
	{
		[CmdletBinding()]
		
		param
		(
			[Parameter(Position = 0, Mandatory = $false)]
			[String] $Course,
			
			[Parameter(Position = 1, Mandatory = $false)]
			[String] $Section,
			
			[Parameter(Position = 2, Mandatory = $false)]
			[System.Collections.Specialized.OrderedDictionary[]] $Instructors,
			
			[Parameter(Position = 3, Mandatory = $false)]
			[String] $MeetingTitle
		)
		
		if ($private:MeetingTitle -and -not $private:Course -and -not $private:Section)
		{
			return $private:MeetingTitle
		}
		
		$private:Title = "$private:Course $private:Section"
		
		if ($private:Instructors.Length -eq 1)
		{
			$private:Title += (' (' + $Instructors[0].LastName + ')')
		}
		
		elseif ($private:Instructors.Length -gt 1)
		{
			$private:Title += ' ('
			
			for ($private:i = 0; $private:i -lt $private:Instructors.Length; $private:i++)
			{
				$private:Title += $private:Instructors[$private:i].LastName
				if ($private:i -le ($private:Instructors.Length - 1))
				{
					$private:Title += ', '
				}
			}
			
			$private:Title += ')'
		}
			
		return $private:Title
	}		
		
    function Format-BodyText
    {
        ###############################################################################################################################################
	    #.SYNOPSIS
        # Converts an EventObject hashmap into text stored in an Exchange appointment
        #
        #.DESCRIPTION
        # This function is used when creating or modifying an Exchange appointment. It takes the data collected into an EventObject
        # hashmap and formats it into the body of the Exchange appointment. This information, formatted in a specific way, can then
        # be read by the ConvertExchangeAppointmentTo-EventObject function. If the format of the body text is changed, that function
        # must also be changed.
        #
        #.PARAMETER EventObject
        # The event object hashmap that will be used to generate the body text
        #
        #.EXAMPLE
        # $BodyText = Format-BodyText -EventObject $EventObject
        ###############################################################################################################################################

        [CmdletBinding()]

        param
        (
            [Parameter(Position = 0, Mandatory = $false)]
            [System.Collections.Specialized.OrderedDictionary] $EventObject
        )

        $private:BodyText = @()
        $private:BodyText += '# Generated by DuckTape - DO NOT EDIT'
        $private:BodyText += "# Id: $($private:EventObject.Id)"
        $private:BodyText += "# Source: $($private:EventObject.Source)"
        $private:BodyText += "# Title: $($private:EventObject.Title)"
        $private:BodyText += "# AllDay: $($private:EventObject.AllDay)"
        $private:BodyText += "# Start: $($private:EventObject.Start)"
        $private:BodyText += "# End: $($private:EventObject.End)"
        $private:BodyText += "# MeetingType: $($private:EventObject.MeetingType)"
        $private:BodyText += "# Location: $($private:EventObject.Location)"
        $private:BodyText += "# Term: $($private:EventObject.Term)"
        $private:BodyText += "# Course: $($private:EventObject.Course)"
        $private:BodyText += "# Section: $($private:EventObject.Section)"
        $private:BodyText += "# InstructorCount: $($private:EventObject.Instructors.Count)"

        # Interate through instructors and add their information into the body text
        # ConvertExchangeAppointmentTo-EventObject should be able to reconstruct this information based on the $InstructorCount
        for ($private:i = 0; $private:i -lt $private:EventObject.Instructors.Count; $private:i++)
        {
            $private:BodyText += "# Instructor: FirstName: $($private:EventObject.Instructors[$private:i].FirstName)"
            $private:BodyText += "# Instructor: LastName: $($private:EventObject.Instructors[$private:i].LastName)"
            $private:BodyText += "# Instructor: DisplayName: $($private:EventObject.Instructors[$private:i].DisplayName)"
            $private:BodyText += "# Instructor: Office: $($private:EventObject.Instructors[$private:i].Office)"
            $private:BodyText += "# Instructor: Title: $($private:EventObject.Instructors[$private:i].Title)"
            $private:BodyText += "# Instructor: Department: $($private:EventObject.Instructors[$private:i].Department)"
            $private:BodyText += "# Instructor: Division: $($private:EventObject.Instructors[$private:i].Division)"
            $private:BodyText += "# Instructor: Email: $($private:EventObject.Instructors[$private:i].Email)"
        }

        return $private:BodyText -join '<br />'
    }	

	function New-EventObject
	{  
	    ###############################################################################################################################################
	    #.SYNOPSIS
	    # Constructs a custom OrderedDictionary that represents a calendar event.
	    # 
	    #.DESCRIPTION
	    # The return object should be used to export to JSON with the ConvertTo-JSON.
	    # This returned object is built on the FullCalendar standard javascript object available here:
	    # http://fullcalendar.io/docs/event_data/Event_Object/
	    #
	    #.PARAMETER Id
	    # The unique identifier of the event.
	    #
	    #.PARAMETER Source
	    # The source that created the object.  This could be from SIS/API or EXCHANGE/<user>.
	    #
	    #.PARAMETER Title
	    # The title of the event.  The title is displayed in Outlook/Exchange and is the heading for the event.
	    #
	    #.PARAMETER AllDay
	    # A boolean that defines whether or not this event is all day.
	    #
	    #.PARAMETER Start
	    # The start date and time of the event.
	    #
	    #.PARAMETER End
	    # The end date and time of the event.
	    #
	    #.PARAMETER MeetingType
	    # The type of meeting.  The most common type is "Course," which aids in defining other characteristics of this object.
	    #
	    #.PARAMETER Location
	    # The location/room number of the event.
	    #
	    #.PARAMETER Term
	    # The term the event takes place.
	    #
	    #.PARAMTER Course
	    # The course associated with this event, if it is of the type "Course."
	    #
	    #.PARAMTER Section
	    # The section of the course associated with this event, if it is of the type "Course."
	    #
	    #.EXAMPLE
	    # $EventObject = New-EventObject -Source "sis/api" -Id 123456789 -MeetingType "Course" -Course "ISTE 140" -Section "01" -Term "2141" `
	    #			-Start "2014-08-25T8:00:00" -End "2014-08-25T8:50:00" -Location "GOL-2650" -Instructors $Instructors -Title "ISTE-140-01"
	    #
	    ###############################################################################################################################################

		[CmdletBinding()]
		
		param
		(
			[Parameter(Position = 0, Mandatory = $true)]
			[String] $Id,
			
			[Parameter(Position = 1, Mandatory = $true)]
			[String] $Source,
			
			[Parameter(Position = 2, Mandatory = $true)]
			[String] $Title,
			
			[Parameter(Position = 3, Mandatory = $false)]
			[bool] $AllDay = $false,
			
			[Parameter(Position = 4, Mandatory = $true)]
			[DateTime] $Start,
			
			[Parameter(Position = 5, Mandatory = $true)]
			[DateTime] $End,
			
			[Parameter(Position = 6, Mandatory = $false)]
			[String] $MeetingType,
			
			[Parameter(Position = 7, Mandatory = $true)]
			[String] $Location, 
			
			[Parameter(Position = 8, Mandatory = $false)]
			[String] $Term,
			
			[Parameter(Position = 9, Mandatory = $false)]
			[String] $Course,
			
			[Parameter(Position = 10, Mandatory = $false)]
			[String] $Section,
			
			[Parameter(Position = 11, Mandatory = $false)]
			[System.Collections.Specialized.OrderedDictionary[]] $Instructors,
			
			[Parameter(Position = 12, Mandatory = $false)]
			[Microsoft.Exchange.WebServices.Data.ItemId] $AppointmentId
		)
		
		$private:Event = New-Object System.Collections.Specialized.OrderedDictionary
		$private:Event.Id = $private:Id
		$private:Event.AppointmentId = $private:AppointmentId
		$private:Event.Source = $private:Source
		$private:Event.Title = $private:Title
		$private:Event.AllDay = $private:AllDay
		$private:Event.Start = $private:Start
		$private:Event.End = $private:End
		$private:Event.MeetingType = $private:MeetingType
		$private:Event.Location = $private:Location
		$private:Event.Term = $private:Term
		$private:Event.Course = $private:Course
		$private:Event.Section = $private:Section
		$private:Event.Instructors = $private:Instructors
		
		return $private:Event
	}
	
	function New-InstructorObject
	{
        ###############################################################################################################################################
	    #.SYNOPSIS
	    # Constructs a custom OrderedDictionary that represents an instructor.
	    # 
	    #.DESCRIPTION
	    # The return object should be used to export to JSON with the ConvertTo-JSON.
	    # The object can be embeded in an array within the EventObject OrderedDictionary.
	    #
	    #.PARAMETER FirstName
	    # The first name (given name) of the instructor.
	    #
	    #.PARAMETER LastName
	    # The last name (surname) of the instructor.
	    #
	    #.PARAMETER DisplayName
	    # The instructor's display name, possibly displaying a nickname.
	    #
	    #.PARAMETER Office
	    # The instructor's office number.
	    #
	    #.PARAMETER Title
	    # The instructor's title, such as "Instructional Faculty."
	    #
	    #.PARAMETER Department
	    # The department the instructor is associated with.
	    #
	    #.PARAMETER Division
	    # The division, or possible college, the instructor is associated with.
	    #
	    #.PARAMETER Email
	    # The instructor's primary email address.
	    #
	    ###############################################################################################################################################

		[CmdletBinding()]
		
		param
		(
			[Parameter(Position = 0, Mandatory = $false)]
			[String] $FirstName,
			
			[Parameter(Position = 1, Mandatory = $false)]
			[String] $LastName,
			
			[Parameter(Position = 2, Mandatory = $false)]
			[String] $DisplayName,
			
			[Parameter(Position = 3, Mandatory = $false)]
			[String] $Office,
			
			[Parameter(Position = 4, Mandatory = $false)]
			[String] $Title,
			
			[Parameter(Position = 5, Mandatory = $false)]
			[String] $Department,
			
			[Parameter(Position = 6, Mandatory = $false)]
			[String] $Division,
			
			[Parameter(Position = 7, Mandatory = $false)]
			[String] $Email
		)
		
		$private:Instructor = New-Object System.Collections.Specialized.OrderedDictionary
		$private:Instructor.FirstName = $private:FirstName
		$private:Instructor.LastName = $private:LastName
		$private:Instructor.DisplayName = $private:DisplayName
		$private:Instructor.Office = $private:Office
		$private:Instructor.Title = $private:Title
		$private:Instructor.Department = $private:Department
		$private:Instructor.Division = $private:Division
		$private:Instructor.Email = $private:Email
		
		return $Instructor
	}
	
	function ConvertJsonTo-EventObjects
	{
		[CmdletBinding()]
		
		param
		(
			[Parameter(Position = 0, Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[String] $Room
		)
		
		# Initialize variables for this function
		$private:EventObjectsFromJson = @{}
		
		$private:WebResponse = Invoke-WebRequest -Method Get -Uri ($script:ApiPath + "/v1/rooms/$Room/meetings?RITAuthorization=$script:ApiKey")
		
		if (-not $private:WebResponse)
		{
			Write-Event -Type "Error" -Message "Web response is null. Cannot parse room JSON data. Ensure the address is correct and the API is available."
			return $private:EventObjectsFromJson
		}
		
		elseif ([int] $private:WebResponse.StatusCode -ne 200)
		{
			Write-Event -Type "Error" -Message "Web StatusCode is $($private:WebResponse.StatusCode). Expecting 200"
			return $private:EventObjectsFromJson
		}
		
		elseif (-not $private:WebResponse.Content)
		{
			Write-Event -Type "Error" -Message "Web Response Data is Null" -Message "The web response data is null. No objects can be processed."
			return $private:EventObjectsFromJson
		}
		
		$private:WebResponseJson = ConvertFrom-Json -InputObject $private:WebResponse.Content
		
		if ($private:WebResponseJson.length -eq 0)
		{
			Write-Event -Type "Error" -Message "JSON Data Invalid. JSON data contains no entities."
			return $private:EventObjectsFromJson
		}
		
		foreach ($WebResponseJsonObject in $private:WebResponseJson.data)
		{
			# Skip events outside the desired time frame
			if (([DateTime] $private:WebResponseJsonObject.date -lt $script:StartTime) -or ([DateTime] $private:WebResponseJsonObject.date -gt $script:EndTime)) { continue }
			
			# Initialize an empty array for instructors
			$private:Instructors = @()
			
			# Retrieve meeting information from API and make sure we got it
			$private:MeetingWebResponse = Invoke-WebRequest -Method Get -Uri ($script:ApiPath + "/v1/meetings/" + $private:WebResponseJsonObject.id + "?RITAuthorization=$script:ApiKey")
			
			if (-not $private:MeetingWebResponse)
			{
				Write-Event -Type "Error" -Message "Web response is null. Cannot parse meeting JSON data."
				continue
			}
			
			elseif ([int] $private:MeetingWebResponse.StatusCode -ne 200)
			{
				Write-Event -Type "Error" -Message "Web StatusCode is $($private:WebResponse.StatusCode). Expecting 200"
				continue
			}
			
			elseif (-not $private:MeetingWebResponse.Content)
			{
				Write-Event -Type "Error" -Message "The web response data is null. No objects can be processed."
				continue
			}
			
			# Convert the meeting JSON into meaningful data
			$private:MeetingWebResponseJson = ConvertFrom-Json -InputObject $private:MeetingWebResponse.Content
			
			if ($private:MeetingWebResponseJson.length -eq 0)
			{
				Write-Event -Type "Error" -Message "JSON data contains no entities."
				continue
			}
			
			if ((Measure-Object -InputObject $private:MeetingWebResponseJson.data).Count -ne 1)
			{ 
				Write-Event -Type "Error" -Message "JSON meeting data contains more than one entry with the same unique ID."
				continue
			}			
			
			$private:MeetingSource = "sis/api"
			Write-Event -Type "Info" -Message "Event Source is $private:MeetingSource"
			
			$private:MeetingId = $private:MeetingWebResponseJson.data.id
			Write-Event -Type "Info" -Message "Event ID is $private:MeetingId"
			
			$private:MeetingType = $private:MeetingWebResponseJson.data.meetingType
			Write-Event -Type "Info" -Message "Event MeetingType is $private:MeetingType"
			
			$private:Term = $private:MeetingWebResponseJson.data.course.term
			Write-Event -Type "Info" -Message "Event Term is $private:Term"
			
			$private:Location = $private:WebResponseJsonObject.room.BuildingCode + "-" + $private:WebResponseJsonObject.room.room
			Write-Event -Type "Info" -Message "Event Location is $private:Location"
			
			$private:StartTime = [DateTime]::Parse($private:MeetingWebResponseJson.data.date + " " + $private:MeetingWebResponseJson.data.start)
			Write-Event -Type "Info" -Message "Event StartTime is $private:StartTime built from $($private:MeetingWebResponseJson.data.date) and $($private:MeetingWebResponseJson.data.start)"
			
			$private:EndTime = [DateTime]::Parse($private:MeetingWebResponseJson.data.date + " " + $private:MeetingWebResponseJson.data.end)
			Write-Event -Type "Info" -Message "Event EndTime is $private:EndTime built from $($private:MeetingWebResponseJson.data.date) and $($private:MeetingWebResponseJson.data.end)"
			
			# Deterimine course and section properties
			# We must have data in the data.course.section property of the JSON response
			if (($private:MeetingType -like "course") -and $private:MeetingWebResponseJson.data.course.section)
			{
				# Event Object Title, Course, Section
				$private:SectionPieces = $private:MeetingWebResponseJson.data.course.section -split '-'
				if ($private:SectionPieces.Length -eq 3)
				{
					$private:Section = $private:SectionPieces[2]
					$private:Course = $private:SectionPieces[0] + " " + $private:SectionPieces[1]
				}
				
				Write-Event -Type "Info" -Message "Event Section is $private:Section"
				Write-Event -Type "Info" -Message "Event Course is $private:Course"
			}
			
			# Obtain instructor information from JSON array
			foreach ($private:InstructorJson in $private:MeetingWebResponseJson.data.course.instructors)
			{
				$private:InstructorWebResponse = Invoke-WebRequest -Method Get -Uri ($script:ApiPath + "/v1/faculty/" + $private:InstructorJson + "?RITAuthorization=$script:ApiKey")
			
				if (-not $private:InstructorWebResponse)
				{
					Write-Event -Type "Error" -Message "Web response is null. Cannot parse instructor JSON data."
					continue
				}
				
				elseif ([int] $private:InstructorWebResponse.StatusCode -ne 200)
				{
					Write-Event -Type "Error" -Message "Web StatusCode is $($private:WebResponse.StatusCode). Expecting 200"
					continue
				}
				
				elseif (-not $private:InstructorWebResponse.Content)
				{
					Write-Event -Type "Error" -Message "The web response data is null. No objects can be processed."
					continue
				}
				
				$private:InstructorWebResponseJson = ConvertFrom-Json -InputObject $private:InstructorWebResponse.Content
				
				$private:InstructorFirstName = $private:InstructorWebResponseJson.data.givenname.0
				Write-Event -Type "Info" -Message "Instructor FirstName is $private:InstructorFirstName"
				
				$private:InstructorLastName = $private:InstructorWebResponseJson.data.sn.0
				Write-Event -Type "Info" -Message "Instructor LastName is $private:InstructorLastName"
				
				$private:InstructorDisplayName = $private:InstructorWebResponseJson.data.displayname.0
				Write-Event -Type "Info" -Message "Instructor DisplayName is $private:InstructorDisplayName"
				
				$private:InstructorOffice = $private:InstructorWebResponseJson.data.physicaldeliveryofficename.0
				Write-Event -Type "Info" -Message "Instructor Office is $private:InstructorOffice"
				
				$private:InstructorTitle = $private:InstructorWebResponseJson.data.title.0
				Write-Event -Type "Info" -Message "Instructor Title is $private:InstructorTitle"
				
				$private:InstructorDepartment = $private:InstructorWebResponseJson.data.department.0
				Write-Event -Type "Info" -Message "Instructor Department is $private:InstructorDepartment"
				
				$private:InstructorDivision = $private:InstructorWebResponseJson.data.division.0
				Write-Event -Type "Info" -Message "Instructor Division is $private:InstructorDivision"
				
				$private:InstructorEmail = $private:InstructorWebResponseJson.data.uid.0 + "@rit.edu"
				Write-Event -Type "Info" -Message "Instructor Email is $private:InstructorEmail"
								
				$private:InstructorObject = New-InstructorObject -FirstName $private:InstructorFirstName -LastName $private:InstructorLastName -DisplayName $private:InstructorDisplayName `
					-Office $private:InstructorOffice -Title $private:InstructorTitle -Department $private:InstructorDepartment -Division $private:InstructorDivision `
					-Email $private:InstructorEmail
				
				$private:Instructors += $private:InstructorObject
			}
			
			$private:Title = Get-EventTitle -Course $private:Course -Section $private:Section -Instructors $private:Instructors -MeetingTitle $private:MeetingWebResponseJson.data.meeting
			Write-Event -Type "Info" -Message "Title is $private:Title"
				
			$private:EventObject = New-EventObject -Source $private:MeetingSource -Id $private:MeetingId -MeetingType $private:MeetingType -Course $private:Course `
				-Section $private:Section -Term $private:Term -Start $private:StartTime -End $private:EndTime -Location $private:Location -Instructors $private:Instructors `
				-Title $private:Title
			
			$private:EventObjectsFromJson.Add($private:MeetingId, $private:EventObject)
		}
		
		return $private:EventObjectsFromJson
	}
	
	function ConvertExchangeAppointmentsTo-EventObjects
	{
		[CmdletBinding()]
		
		param
		(
			[Parameter(Position = 0, Mandatory = $true)]
			[Microsoft.Exchange.WebServices.Data.CalendarFolder] $CalendarFolder
		)		
		
		# Initialize an empty hash table for potential Event Objects
		$private:EventObjectsFromExchange = @{}
		
		# Get the calendar view of all appointments within the timeframe
		$private:CalendarView = New-Object Microsoft.Exchange.WebServices.Data.CalendarView($StartTime, $EndTime)
		
		if (-not $private:CalendarView)
		{
			Write-Event -Type "Error" -Message "CalendarView is null. Unable to retrieve appointment data."
			return $private:EventObjectsFromExchange
		}
		
		$private:CalendarView.PropertySet = New-Object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
		
		$private:CalendarResult = $private:CalendarFolder.FindAppointments($private:CalendarView)
		
		# Interate through each Exchange calendar appointment and construct an Event Object
		foreach ($private:AppointmentObject in $private:CalendarResult.Items)
		{
			# Load the FirstClass Properties, needed to read the text from the body
			$private:PropertySet = New-Object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
			$private:PropertySet.RequestedBodyType = [Microsoft.Exchange.WebServices.Data.BodyType]::Text
			$private:AppointmentObject.Load($private:PropertySet)
			
			$private:MeetingSource = "exchange"
			if ($private:AppointmentObject.Organizer) { $private:MeetingSource += ("/" + ($private:AppointmentObject.Organizer).Name) }
			Write-Event -Type "Info" -Message "Event Source is $private:MeetingSource"
			
			$private:AppointmentId = $private:AppointmentObject.Id
			Write-Event -Type "Info" -Message "Appointment Id is $private:AppointmentId"
			
			$private:MeetingTitle = $private:AppointmentObject.Subject
			Write-Event -Type "Info" -Message "Event Title is $private:MeetingTitle"
			
			$private:StartTime = $private:AppointmentObject.Start
			Write-Event -Type "Info" -Message "Event StartTime is $private:StartTime"
			
			$private:EndTime = $private:AppointmentObject.End
			Write-Event -Type "Info" -Message "Event EndTime is $private:EndTime"
			
			$private:Location = $private:AppointmentObject.Location
			Write-Event -Type "Info" -Message "Event Location is $private:Location"
			
			$private:AllDay = $private:AppointmentObject.IsAllDayEvent
			Write-Event -Type "Info" -Message "Event AllDay is $private:AllDay"

			if ($private:AppointmentObject.Body.Text)
			{
                $private:AppointmentText = $private:AppointmentObject.Body.Text -split "\r\n"
				for ($private:i = 0; $private:i -lt $private:AppointmentText.Length; $private:i++)
				{
					if ($private:AppointmentText[$private:i] -like "# Id*")
					{
						$private:Results = $private:AppointmentText[$private:i].Split(':')
						if ($private:Results[1])
						{
							$private:MeetingId = $private:Results[1] -replace '^\s+', ''
							Write-Event -Type "Info" -Message "Event Id is $private:MeetingId"
						}

                        else
                        {
                            $private:MeedingId = ''
                        }
					}
					
					elseif ($private:AppointmentText[$private:i] -like "# MeetingType*")
					{
						$private:Results = $private:AppointmentText[$private:i].Split(':')
						if ($private:Results[1])
						{
							$private:MeetingType = $private:Results[1] -replace '^\s+', ''
							Write-Event -Type "Info" -Message "MeetingType is $private:MeetingType"
						}

                        else
                        {
                            $private:MeetingType = ''
                        }
					}
					
					elseif ($private:AppointmentText[$private:i] -like "# Term*")
					{
						$private:Results = $private:AppointmentText[$private:i].Split(':')
						if ($private:Results[1])
						{
							$private:Term = $private:Results[1] -replace '^\s+', ''
							Write-Event -Type "Info" -Message "Event Term is $private:Term"
						}

                        else
                        {
                            $private:Term = ''
                        }
					}
					
					elseif ($private:AppointmentText[$private:i] -like "# Section*")
					{
						$private:Results = $private:AppointmentText[$private:i].Split(':')
						if ($private:Results[1])
						{
							$private:Section = $private:Results[1] -replace '^\s+', ''
							Write-Event -Type "Info" -Message "Event Section is $private:Section"
						}

                        else
                        {
                            $private:Section = ''
                        }
					}

                    elseif ($private:AppointmentText[$private:i] -like "# Course*")
                    {
                        $private:Results = $private:AppointmentText[$private:i].Split(':')
                        if ($private:Results[1])
                        {
                            $private:Course = $private:Results[1] -replace '^\s+', ''
                            Write-Event -Type "Info" -Message "Event Course is $private:Course"
                        }

                        else
                        {
                            $private:Course = ''
                        }
                    }
                    
                    elseif ($private:AppointmentText[$private:i] -like "# InstructorCount*")
                    {
                        $private:Results = $private:AppointmentText[$private:i].Split(':')
                        $private:InstructorCount = $private:Results[1] -replace '^\s+', ''
                        [System.Collections.Specialized.OrderedDictionary[]] $private:Instructors = @()

                        if ([int] $private:InstructorCount -gt 0)
                        {
                            for ($private:k = 0; $private:k -lt $private:InstructorCount; $private:k++)
                            {
                                $private:Instructor = New-InstructorObject

                                # An instructor object has 8 properties, all of which should be in the body text
                                for ($private:j = 0; $private:j -lt 8; $private:j++)
                                {
                                    # Increment the master counter which tells the function what line in the body text to use
                                    # But it can only do that if more lines exist
                                    # This protects the function from overstepping the array 
                                    if (($private:i + 1) -lt $private:AppointmentText.Length) { $private:i++ }

                                    if ($private:AppointmentText[$private:i] -like "# Instructor: FirstName*")
                                    {
                                        $private:Results = $private:AppointmentText[$private:i].Split(':')
                                        $private:Instructor.FirstName = $private:Results[2] -replace '^\s+', ''
                                        Write-Event -Type "Info" -Message "Instructor $private:k FirstName is $($private:Instructor.FirstName)"
                                    }

                                    elseif ($private:AppointmentText[$private:i] -like "# Instructor: LastName*")
                                    {
                                        $private:Results = $private:AppointmentText[$private:i].Split(':')
                                        $private:Instructor.LastName = $private:Results[2] -replace '^\s+', ''
                                        Write-Event -Type "Info" -Message "Instructor $private:k LastName is $($private:Instructor.LastName)"
                                    }

                                    else { Write-Host "Nope" }
                                }

                                $private:Instructors += $private:Instructor
                            }
                        }
                    }
				}
			}
			
			# ID must be defined. If it was not pulled from the appointment body text, let's pull it from Exchange
			if (-not $private:MeetingId)
			{
				$private:MeetingId = $private:AppointmentObject.Id
				Write-Event -Type "Info" -Message "Event ID is $private:MeetingId from Exchange"
			}
			
			$private:EventObject = New-EventObject -Source $private:MeetingSource -Id $private:MeetingId -MeetingType $private:MeetingType -Course $private:Course `
				-Section $private:Section -Term $private:Term -Start $private:StartTime -End $private:EndTime -Location $private:Location -Instructors $private:Instructors `
				-Title $private:MeetingTitle -AppointmentId $private:AppointmentId		

			$private:EventObjectsFromExchange.Add($private:MeetingId, $private:EventObject)
		}
		
		return $private:EventObjectsFromExchange
	}
	
	function ConvertEventObjectTo-ExchangeAppointment
	{
		[CmdletBinding()]
		
		param
		(
			[Parameter(Position = 0, Mandatory = $true)]
			[Microsoft.Exchange.WebServices.Data.ExchangeService] $Service,
			
			[Parameter(Position = 1, Mandatory = $true)]
			[Microsoft.Exchange.WebServices.Data.FolderID] $FolderID,
			
			[Parameter(Position = 2, Mandatory = $true)]
			[ValidateNotNull()]
			[System.Collections.Specialized.OrderedDictionary] $EventObject
		)
		
		$private:Appointment = New-Object Microsoft.Exchange.WebServices.Data.Appointment($private:Service)
		$private:Appointment.Subject = $private:EventObject.Title
		$private:Appointment.Start = [DateTime] $private:EventObject.Start
		$private:Appointment.End = [DateTime] $private:EventObject.End
		$private:Appointment.Location = $private:EventObject.Location
		$private:Appointment.IsAllDayEvent = $private:EventObject.AllDay
		
		$private:BodyText = @()
		
		foreach ($private:Key in $EventObject.Keys)
		{
			$private:BodyText += ($private:Key + ":" + $private:EventObject.Get_Item($private:Key))
		}
		
		$private:Appointment.Body = Format-BodyText -EventObject $private:EventObject
		
		try
		{
			$private:Appointment.Save($private:FolderID)
			Write-Event -Type "Info" -Message "$($private:EventObject.Title) created in $private:FolderId"
		}
		
		catch
		{
			Write-Event -Type "Error" -Message "Could not create Appointment $($private:EventObject.Title) in $private:FolderId"
		}
	}
	
	function Update-ExchangeAppointment
	{
		[CmdletBinding()]
		
		param
		(
			[Parameter(Position = 0, Mandatory = $true)]
			[ValidateNotNull()]
			[Microsoft.Exchange.WebServices.Data.ExchangeService] $Service,

            [Parameter(Position = 1, Mandatory = $true)]
            [ValidateNotNull()]
			[Microsoft.Exchange.WebServices.Data.FolderID] $FolderID,
			
			[Parameter(Position = 2, Mandatory = $false)]
			[System.Collections.Specialized.OrderedDictionary] $ExchangeRoomEventObject,
			
			[Parameter(Position = 3, Mandatory = $true)]
			[System.Collections.Specialized.OrderedDictionary] $ApiEventObject
		)
		
		if (-not $private:ExchangeRoomEventObject.AppointmentId)
		{
			Write-Event -Type "Warning" -Message "Cannot determine AppointmentId from Event Object. Appointment will not be modified."
			return
		}
		
		
        $private:ItemId = New-Object Microsoft.Exchange.WebServices.Data.ItemId($private:ExchangeRoomEventObject.AppointmentId)
		
	    try
		{
			$private:Appointment = [Microsoft.Exchange.WebServices.Data.Appointment]::Bind($private:Service, $private:ItemId)
		}
		
		catch
		{
			Write-Event -Type "Error" -Message "Could not bind Appointment `"$($private:ApiEventObject.Title)`" to Exchange."
			return
		}
		
		$private:Changed = $false
		
		if ($private:ApiEventObject.Title -ne $private:ExchangeRoomEventObject.Title)
		{
			$private:Changed = $true
			$private:NewTitle = Get-EventTitle -Course $private:ApiEventObject.Course -Section $private:ApiEventObject.Section -Instructors $private:ApiEventObject.Instructors `
				-MeetingTitle $private:ApiEventObject.Title
			$private:Appointment.Subject = $private:NewTitle
			Write-Event -Type "Info" -Message "Exchange Appointment $private:ExchangeRoomEventObject.AppointmentId Title changed to `"$private:NewTitle`""
		}
		
		if ($private:ApiEventObject.Start -ne $private:ExchangeRoomEventObject.Start)
		{
			$private:Changed = $true
			$private:Appointment.Start = $ApiEventObject.Start
			Write-Event -Type "Info" -Message "Exchange Appointment $private:ExchangeRoomEventObject.AppointmentId Start changed to $($private:ApiEventObject.Start)"
		}

        if ($private:ApiEventObject.End -ne $private:ExchangeRoomEventObject.End)
        {
            $private:Changed = $true
            $private:Appointment.End = $ApiEventObject.End
            Write-Event -Type "Info" -Message "Exchange Appointment $private:ExchangeRoomEventObject.AppointmentId End changed to $($private:ApiEventObject.End)"
        }

        if ($private:ApiEventObject.MeetingType -ne $private:ExchangeRoomEventObject.MeetingType)
        {
            $private:Changed = $true
            Write-Event -Type "Info" -Message "Exchange Appointment $private:ExchangeRoomEventObject.AppointmentId MeetingType changed to $($private:ApiEventObject.MeetingType)"
        }
        
        if ($private:ApiEventObject.AllDay -ne $private:ExchangeRoomEventObject.AllDay)
        {
            $private:Changed = $true
            $private:Appointment.IsAllDayEvent = $true
            Write-Event -Type "Info" -Message "Exchange Appointment $private:ExchangeRoomEventObject.AppointmentId AllDay changed to ($private:ApiRoomEventObject.AllDay)"
        }

        if ($private:ApiEventObject.Location -ne $private:ExchangeRoomEventObject.Location)
        {
            $private:Changed = $true
            Write-Event -Type "Warning" -Message "Exchange Appointment $private:ExchangeRoomEventObject.AppointmentId Location changed to $($private:ApiEventObject.Location)"
        }

        if ($private:ApiEventObject.Term -ne $private:ExchangeRoomEventObject.Term)
        {
            $private:Changed = $true
            Write-Event -Type "Info" -Message "Exchange Appointment $private:ExchangeRoomEventObject.AppointmentId Term changed to $($private:ApiEventObject.Term)"
        }

        if ($private:ApiEventObject.Course -ne $private:ExchangeRoomEventObject.Course)
        {
            $private:Changed = $true
            Write-Event -Type "Info" -Message "Exchange Appointment $private:ExchangeRoomEventObject.AppointmentId Course changed to $($private:ApiEventObject.Course)"
        }

        if ($private:ApiEventObject.Section -ne $private:ExchangeRoomEventObject.Section)
        {
            $private:Changed = $true
            Write-Event -Type "Info" -Message "Exchange Appointment $private:ExchangeRoomEventObject.AppointmentId Section changed to $($private:ApiEventObject.Section)"
        }

        if ($private:Changed)
        {
            $private:BodyText = Format-BodyText -EventObject $private:ApiEventObject
            $private:Appointment.Body = $private:BodyText
        }  
	}
	
	function Remove-ExchangeAppointment
	{
		[CmdletBinding()]
		
		param
		(
			[Parameter(Position = 0, Mandatory = $true)]
			[ValidateNotNull()]
			[Microsoft.Exchange.WebServices.Data.ExchangeService] $Service,
			
			[Parameter(Position = 1, Mandatory = $false)]
			[Microsoft.Exchange.WebServices.Data.ItemId] $ItemId
		)
		
		if (-not $private:ItemId)
		{
			Write-Event -Type "Warning" -Message "Cannot determine AppointmentID from Event Object. Appointment will not be deleted."
			return
		}
		
		$private:Appointment = New-Object Microsoft.Exchange.WebServices.Data.Appointment($private:Service)
		
		try
		{
			$private:Appointment.Bind($private:Service, $private:ItemId)
			$private:Appointment.Delete([Microsoft.Exchange.WebServices.Data.DeleteMode]::HardDelete)
		}
		
		catch
		{
			Write-Event -Type "Error" -Message "Could not delete Exchange appointment"
		}
	}
}	

process
{
	# Load the configuration
	Load-Configuration
	
	# Load Exchange Assembly
	try
	{
		[void][Reflection.Assembly]::LoadFile($script:EWSPath)
	}
	
	catch
	{
		Write-Event -Type "Error" -Function "Process" -Message "Could not load EWS DLL. Check the configuration file and ensure the EWS API is installed."
		Exit
	}
	
	try
	{
		$script:Service = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService([Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2010)
		$script:Service.Credentials = New-Object Microsoft.Exchange.WebServices.Data.WebCredentials($script:Username, $script:Password, $script:Domain)
	}
	
	catch
	{
		Write-Event -Type "Error" -Message "Could not create ExchangeService object. Exchange version should be 2010."
		Exit
	}
	
	foreach ($Room in $script:Rooms)
	{
		Write-Event -Type "Info" -Message "Synchronizing $($private:Room.Name) with $($private:Room.Calendar) to output file $($private:Room.FileName)`."
		Sync-Room -Service $script:Service -RoomNumber $private:Room.Number -MailboxAddress $private:Room.Calendar
	}
	
	Write-Host "Complete."
}