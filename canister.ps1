<#
    Canister
    A micro web server to create modern, responsive web apps and RESTful APIs
    (c) Parul Jain paruljain@hotmail.com
    MIT License
#>

# The following .Net 4.5 library is required to find correct mime type for file extensions
try { Add-Type -AssemblyName System.Web -ErrorAction Stop }
catch { throw 'Unable to start the web server. .Net 4.5 is required' }

Update-TypeData -TypeName System.Net.HttpListenerResponse -MemberType ScriptMethod -MemberName SendText -Value {
    param([string]$text, [string]$contentType = 'text/plain')
    $this.ContentType = $contentType
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($text)
    $this.ContentLength64 = $buffer.length
    $this.OutputStream.Write($buffer, 0, $buffer.length)
    $this.OutputStream.Close()
}

Update-TypeData -TypeName System.Net.HttpListenerResponse -MemberType ScriptMethod -MemberName SendJson -Value {
    param($object, [string]$contentType = 'application/json')
    $this.ContentType = $contentType
    # ConvertTo-Json will not output array for single element array when input is sent on pipeline
    # thus always provide data as argument
    # Also there are a couple of open bugs in ConvertTo-Json in coding " and some other chars
    # The workaround is -compress switch
    $buffer = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $object -Compress))
    $this.ContentLength64 = $buffer.length
    $this.OutputStream.Write($buffer, 0, $buffer.length)
    $this.OutputStream.Close()
}

Update-TypeData -TypeName System.Net.HttpListenerRequest -MemberType ScriptMethod -MemberName GetBody -Value {
    $sr = New-Object System.IO.StreamReader $request.InputStream
    $sr.ReadToEnd()
    $sr.Close()
    $sr.Dispose()
}

Update-TypeData -TypeName System.Net.HttpListenerResponse -MemberType ScriptMethod -MemberName SendFile -Value {
    param([string]$fileName)
    if ($fileName -match '\.(\w+)$') {
        $this.ContentType = [System.Web.MimeMapping]::GetMimeMapping($matches[0])
    }
    try {
        $fs = New-Object System.IO.FileStream $fileName, Open
        $fs.CopyTo($this.OutputStream)
        $this.OutputStream.Close()
        $fs.Close()
        $fs.Dispose()
    } catch { $this.StatusCode = 404 }
}

function Canister-Start {
    param(
        [Parameter(Mandatory=$true)][Array]$handlers,
        [Parameter(Mandatory=$false)][switch]$https,
        [Parameter(Mandatory=$false)][uint32]$port = 8000,
        [Parameter(Mandatory=$false)][ValidateSet('Console','File','Off')][string]$log='Console',
        [Parameter(Mandatory=$false)][string]$logFile = ".\Canister.log"
    )
    write-host ''
    write-host 'Canister v0.22'
    write-host ''

    if ($handlers.Count -eq 0) { throw 'WebServer failed to start: No handlers added' }
    $strPort = $port.ToString()

    $listener = New-Object System.Net.HttpListener
    if ($https) { $prefix = "https://+:$strPort/" } else { $prefix = "http://+:$strPort/" }
    $listener.Prefixes.Add($prefix)
    try { $listener.Start() }
    catch {
        if ($_.Exception.Message -match 'Access is denied' -or 
                $_.Exception.Message -match 'conflicts with an existing registration') {
            write-host 'Port conflict or access denied'
            write-host 'Please run setup.ps1 from an administratively privileged command prompt'
            return
        }
        else { throw $_ }
    }
    write-host ('Canister server started on ' + $listener.Prefixes[0])

    while ($true) {
        $context = $listener.GetContext()
        try {
            $handlerFound = $false
            $request = $context.Request
            $response = $context.Response
            foreach ($handler in $handlers) {
                if (!$handler.method) { $handler['method'] = 'GET' }
                $route = $request.RawUrl.split('?')[0]
                if ($request.HttpMethod -eq $handler.method -and $route -match $handler.route) {
                    $handlerFound = $true
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
