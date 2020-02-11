

####################################
# Author:       Eric Austin
# Create date:  December 2019
# Description:  Used to automate the website publishing process (script goes in the Visual Studio website project directory and run from there)
#               Can either publish to website directory immediately or to a queue directory for automated publishing later            
# Notes:        Don't stop the website in IIS since that prevents the app_offline.html page from displaying
#               The presence of app_offline.html results in a user having to refresh the page anyways so there's no danger in anything user-related inadvertently surviving the publish
####################################

#set common variables
$CurrentDirectory=if ($PSScriptRoot -ne "") {$PSScriptRoot} else {(Get-Location).Path}
$ErrorActionPreference="Stop"
$PublishLogData=@()
$PublishLogLocation="$CurrentDirectory\PublishLog.csv"

#script variables
$Selection=0
$QueueDirectory=""
$WebsiteURL=""
$WebsiteDirectory=""
$ReleaseNotesPath=(Join-Path -Path $CurrentDirectory -ChildPath "Release notes.txt")
$ReleaseNotes=""

Try {

    Clear-Host

    Do {

        $Confirm=""

        Do {
            Write-Host ""    
            Write-Host "Options:"
            Write-Host "1. Publish to a queue directory for automated publishing later"
            Write-Host "2. Publish immediately to the live website directory"
            $Selection=Read-Host "Enter selection"
        }
        Until (($Selection -eq 1 ) -or ($Selection -eq 2))

        if ($Selection -eq 1)
        {
            $Confirm="y"    #automatically proceed with publishing to queue
        }
        elseif ($Selection -eq 2)
        {
            $Confirm=Read-Host "This will publish immediately to the live website directory. Are you sure you want to continue (y/n)?"  #confirm publishing to live
        }
    }
    Until ($Confirm -eq "y")
    
    #ensure the project builds successfully
    Write-Host "Ensuring project builds successfully..."
    dotnet build | Out-Null
    If ($LASTEXITCODE -ne 0) {
        Throw "dotnet build did not return a success code of 0"
    }

    #get the release notes (if any)
    if (Test-Path -Path $ReleaseNotesPath)
    {
        $ReleaseNotes=(Get-Content -Path $ReleaseNotesPath )
    }

    if ($Selection -eq 1)   #publish to a queue directory for automated publishing later
    {

        #ensure variables are populated
        if ([string]::IsNullOrWhiteSpace($QueueDirectory))
        {
            Throw "Queue directory variable is not populated. Publish aborted."
        }

        #change location to specified queue directory
        Write-Host "Switching to $($QueueDirectory)..."
        Set-Location $QueueDirectory | Out-Null

        #ensure queue directory is empty
        Write-Host "Removing any items from queue directory..."
        Remove-Item * -Recurse

        #change location to the project directory
        Write-Host "Switching to $($CurrentDirectory)..."
        Set-Location $CurrentDirectory | Out-Null

        #publish site to queue directory
        Write-Host "Publishing site to queue directory..."
        dotnet publish -o $QueueDirectory | Out-Null
        If ($LASTEXITCODE -ne 0) {
            Throw "dotnet publish did not return a success code of 0"
        }

        #set publish log message
        $PublishLogData+=New-Object -TypeName PSCustomObject -Property @{"Date"=(Get-Date).ToString(); "Result"="Success"; "Message"="Queue directory"; "Release Notes"=$ReleaseNotes}

        Write-Host "Successfully published to queue directory."

    }
    elseif ($Selection -eq 2)   #immedidately publish to live website directory
    {

        #ensure variables are populated
        if ([string]::IsNullOrWhiteSpace($WebsiteURL) -or [string]::IsNullOrWhiteSpace($WebsiteDirectory))
        {
            Throw "Website URL and/or website directory variable/s are not populated. Publish aborted."
        }

        #change location to specified website directory
        Write-Host "Switching to $($WebsiteDirectory)..."
        Set-Location $WebsiteDirectory | Out-Null

        #create app_offline.htm if it doesn't already exist (this can happen sometimes when performing multiple publishes in a short amount of time, ie for troubleshooting)
        if (Test-Path -Path ".\app_offline.htm"){
            Write-Host "app_offline.htm already present, will not try to create a new one"
        }
        else {
            Write-Host "Creating app_offline.htm..."
            New-Item -ItemType "File" -Name "app_offline.htm" -Value "Website is offline for maintenance and will be available again shortly." | Out-Null
        }
        
        #give IIS a few seconds to respond to the app_offline.htm file
        Write-Host "Allowing IIS time to respond to app_offline.htm..."
        Start-Sleep -Seconds 5

        #delete directory contents
        Write-Host "Deleting website directory contents except for app_offline.htm..."
        Get-ChildItem | Where-Object Name -NE "app_offline.htm" | ForEach-Object {
            Remove-Item -Path $_.FullName -Recurse -Force
        }

        #change location to the project directory
        Write-Host "Switching to $($CurrentDirectory)..."
        Set-Location $CurrentDirectory | Out-Null

        #publish site
        Write-Host "Publishing site..."
        dotnet publish -o $WebsiteDirectory | Out-Null
        If ($LASTEXITCODE -ne 0) {
            Throw "dotnet publish did not return a success code of 0"
        }

        #change location to specified website directory
        Write-Host "Switching to $($WebsiteDirectory)..."
        Set-Location $WebsiteDirectory | Out-Null
        
        #remove app_offline.htm (only remove it here, don't remove it in the catch or finally blocks, if something goes wrong at least the app_offline.htm file will still display)
        Write-Host "Removing app_offline.htm..."
        Get-ChildItem | Where-Object Name -EQ "app_offline.htm" | ForEach-Object {
            Remove-Item -Path $_.FullName
        }

        #set publish log message
        $PublishLogData+=New-Object -TypeName PSCustomObject -Property @{"Date"=(Get-Date).ToString(); "Result"="Success"; "Message"="Live website directory"; "Release Notes"=$ReleaseNotes}
        
        #open website
        Write-Host "Publish succeeded, opening website..."
        Start-Process $WebsiteURL
    }

}

Catch {

    #set publish log message
    $PublishLogData+=New-Object -TypeName PSCustomObject -Property @{"Date"=(Get-Date).ToString(); "Result"="Failed"; Message=$Error[0]; "Release Notes"=$ReleaseNotes}
    Write-Host "Publish failed, error message follows..."
    Write-Host $Error[0]

}

Finally {

    $PublishLogData | Select-Object Date, Result, Message | Export-Csv -Path $PublishLogLocation -Append -NoTypeInformation
    
    #clear out release notes (if any)
    if ($ReleaseNotes.Length -gt 0)
    {
        Set-Content -Path $ReleaseNotesPath -Value $null
    }

}