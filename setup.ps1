<#
    Canister Network Setup
    (c) Parul Jain paruljain@hotmail.com
    MIT License
#>

$ErrorActionPreference = 'stop'

function Add-SelfSignedCertificate ([string]$CommonName='Canister') {
    $name = new-object -com "X509Enrollment.CX500DistinguishedName.1"
    $name.Encode("CN=$CommonName", 0)

    $key = new-object -com "X509Enrollment.CX509PrivateKey.1"
    $key.ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
    $key.KeySpec = 1
    $key.Length = 1024
    $key.SecurityDescriptor = "D:PAI(A;;0xd01f01ff;;;SY)(A;;0xd01f01ff;;;BA)(A;;0x80120089;;;NS)"
    $key.MachineContext = 1
    $key.Create()

    $serverauthoid = new-object -com "X509Enrollment.CObjectId.1"
    $serverauthoid.InitializeFromValue("1.3.6.1.5.5.7.3.1")
    $ekuoids = new-object -com "X509Enrollment.CObjectIds.1"
    $ekuoids.add($serverauthoid)
    $ekuext = new-object -com "X509Enrollment.CX509ExtensionEnhancedKeyUsage.1"
    $ekuext.InitializeEncode($ekuoids)

    $cert = new-object -com "X509Enrollment.CX509CertificateRequestCertificate.1"
    $cert.InitializeFromPrivateKey(2, $key, "")
    $cert.Subject = $name
    $cert.Issuer = $cert.Subject
    $cert.NotBefore = get-date
    $cert.NotAfter = $cert.NotBefore.AddDays(90)
    $cert.X509Extensions.Add($ekuext)
    $cert.Encode()

    $enrollment = new-object -com "X509Enrollment.CX509Enrollment.1"
    $enrollment.InitializeFromRequest($cert)
    $certdata = $enrollment.CreateRequest(1)
    $enrollment.InstallResponse(2, $certdata, 1, "")
    [Security.Cryptography.X509Certificates.X509Certificate2][Convert]::FromBase64String($certdata)
}

function Get-ServerCertificates {
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My","LocalMachine")
    $store.Open("ReadOnly")
    foreach ($cert in $store.Certificates) {
        $serverCert = $cert.EnhancedKeyUsageList | where FriendlyName -eq 'Server Authentication'
        if ($serverCert) { return $cert }
    }
}

function Is-Admin {
    ([System.Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Canister-Setup {
    'Canister network setup version 0.1'
    ''
    if (!(Is-Admin)) { 'Sorry you must run setup from an administratively privileged command prompt'; return }
    [uint32]$port = Read-Host -Prompt 'What port will you be running Canister on? [8000]'
    if (!$port) { $port = 8000 }
    $portStr = $port.ToString()
    [string]$ssl = Read-Host -Prompt 'Will you use HTTPS (in place of HTTP)? [Y/N]'
    if ($ssl -notmatch '^[ynYN]$') { 'Sorry please answer Y or N only'; return }

    "Executing: netsh http delete urlacl url=http://+:$portStr/"
    & netsh http delete urlacl url=http://+:$portStr/ | Out-Null
    "Executing: netsh http delete urlacl url=https://+:$portStr/"
    & netsh http delete urlacl url=https://+:$portStr/ | Out-Null

    if ($ssl -match 'n') {
      "Executing: netsh http add urlacl url=http://+:$portStr/ user=BUILTIN\Users"
      & netsh http add urlacl url=http://+:$portStr/ user=BUILTIN\Users
    } else {
        $cert = Get-ServerCertificates
        If (!$cert) {
            'Creating and adding a self-signed certificate'
            $cert = Add-SelfSignedCertificate
        } else { 'Existing server certificate will be used' }
        $certThumbPrint = $cert.Thumbprint
        $guid = '{' + [guid]::NewGuid().ToString() + '}'
        "Executing: netsh http delete sslcert ipport=0.0.0.0:$portStr"
        & netsh http delete sslcert ipport=0.0.0.0:$portStr | Out-Null
        "Executing: netsh http add sslcert ipport=0.0.0.0:$portStr certhash=$certThumbPrint appid=$guid"
        & netsh http add sslcert ipport=0.0.0.0:$portStr certhash=$certThumbPrint appid=$guid
        "Executing: netsh http add urlacl url=https://+:$portStr/ user=BUILTIN\Users"
        & netsh http add urlacl url=https://+:$portStr/ user=BUILTIN\Users
    }
    "Executing: netsh advfirewall firewall delete rule name=Canister Port $portStr"
    & netsh advfirewall firewall delete rule name="Canister Port $portStr" | Out-Null
    "Executing: netsh advfirewall firewall add rule name=Canister Port $portStr dir=in action=allow protocol=TCP localport=$portStr"
    & netsh advfirewall firewall add rule name="Canister Port $portStr" dir=in action=allow protocol=TCP localport=$portStr
}
