# The following .Net 4.5 library is required to find correct mime type for file extensions
try { [void][System.Reflection.Assembly]::LoadWithPartialName("System.Web") }
catch { throw 'Unable to start the web server. .Net 4.5 is required' }

$scriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition

function WebServer-Start {
    param(
        [Parameter(Mandatory=$true)][Array]$handlers,
        [Parameter(Mandatory=$false)][uint32]$port = 8000,
        [Parameter(Mandatory=$false)][ValidateSet('Console','File','Off')][string]$log='Console',
        [Parameter(Mandatory=$false)][string]$logFile = "$scriptPath\WebServer.log"
    )
    write-host ''
    write-host 'PowerShell WebServer v0.1'
    write-host '(c) Parul Jain paruljain@hotmail.com'
    write-host 'MIT License'
    write-host ''

    if ($handlers.Count -eq 0) { throw 'WebServer failed to start: No handlers added' }
    $strPort = $port.ToString()

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://+:$strPort/") # Must exactly match the netsh command issued part of install procedure
    try { $listener.Start() }
    catch {
        if ($_.Exception.Message -match 'Access is denied') {
            write-host 'First please run the following command from an administratively privileged command prompt:'
            write-host ''
            write-host ("netssh http add urlacl url=http://+$strPort/" + ' user=' + $env:USERDOMAIN +
                '\' + $env:USERNAME )
            write-host ''
            write-host 'Also you will need to open the port in Windows firewall if you want to allow connections from other computers to the web server'
            return
        }
        else { throw $_ }
    }
    write-host ('Web server started on ' + $listener.Prefixes[0])

    while ($true) {
        $context = $listener.GetContext()
        try {
            $handlerFound = $false
            $request = $context.Request
            $response = $context.Response
            foreach ($handler in $handlers) {
                if (!$handler.method) { $handler['method'] = 'GET' }
                if ($request.HttpMethod -match $handler.method -and $request.RawUrl -match $handler.route) {
                    $handlerFound = $true
                    $request | Add-Member -MemberType ScriptMethod -Name GetBody -Value {
                        (New-Object System.IO.StreamReader $request.InputStream).ReadToEnd()
                    }
                    
                    $response | Add-Member -MemberType ScriptMethod -Name SendJson -Value {
                        param([string]$jsonText)
                        $this.ContentType = 'application/json'
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonText)
                        $this.ContentLength64 = $buffer.length
                        $this.OutputStream.Write($buffer, 0, $buffer.length)
                        $this.OutputStream.Close()
                    }

                    $response | Add-Member -MemberType ScriptMethod -Name SendText -Value {
                        param([string]$text)
                        $this.ContentType = 'text/plain'
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($text)
                        $this.ContentLength64 = $buffer.length
                        $this.OutputStream.Write($buffer, 0, $buffer.length)
                        $this.OutputStream.Close()
                    }

                    $response | Add-Member -MemberType ScriptMethod -Name SendFile -Value {
                        param([string]$fileName)
                        if (Test-Path $fileName) {
                            if ($fileName -match '\.(\w+)$') {
                                $response.ContentType = [System.Web.MimeMapping]::GetMimeMapping($matches[0])
                            }
                            $buffer = Get-Content $fileName -Encoding Byte -ReadCount 0
                            $response.ContentLength64 = $buffer.length
                            $output = $response.OutputStream
                            $output.Write($buffer, 0, $buffer.length)
                            $output.Close()
                        }
                        else {
                            $response.StatusCode = 404
                        }
                    }

                    & $handler.handler $request $response
                    break
                }
            }

            if (!$handlerFound) { $response.StatusCode = 404 }
        }
        catch {
            $response.StatusCode = 400
            $response.StatusDescription = $_.Exception.Message
        }
        $logEntry = $request.RemoteEndPoint.Address.IPAddressToString + "`t-`t-`t" +
             ([DateTime]::Now.ToString('[dd/MMM/yyyy:HH:mm:ss zzz]') -replace ':(\d+])', '$1') + "`t" +
                '"' + $request.HttpMethod + ' ' + $request.RawUrl + ' HTTP/' + $request.ProtocolVersion +'"' +
                "`t" + $response.StatusCode + "`t" + $response.ContentLength64.ToString()
        if ($log -eq 'Console') { Write-Host $logEntry }
        elseif ($log -eq 'File') { $logEntry | Out-File $logFile -Append -ErrorAction Stop }
             
        $response.Close()
    }
}
