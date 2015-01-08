<#
    vSphere 5.0 workaround for CBT bug when VMDK size is > 127GB
    Deploys the workaround in a throttled manner so as to not overwhelm ESX storage
    
    Parul Jain
    CATE Storage and Backup Engineering
    parul.k.jain@citi.com
    Version 1.4

Pre-requisities
---------------

* vSphere 5.0 clusters that need remediation

* One or more vCenter instances managing the clusters that need to be fixed

* Windows desktop or server (here after referred to as "workstation") with:
    - PowerCLI: any version less than 3 years old; latest recommended
        To check PowerCLI version start PowerCLI from start menu and look at the title bar
    - PowerShell 2.0 or better
        To check PowerShell version run the following from command prompt:
            c:\> powershell get-host
    - Administrative access to enable running of PowerShell scripts

* Administrative access to all resources in the vSphere cluster

What is PowerShell?
-------------------

General purpose scripting language for Windows that replaces batch files and visual basic (VBS) scripts. Powershell
comes standard with Windows 7, 2008, and 2012 operating systems. PowerShell can directly use the entire .Net library
which allows it to be used as a general purpose programming language for business apps in addition to a scripting
platform for infrastructure automation


What is PowerCLI?
-----------------
PowerCLI is a library for PowerShell from vmware that makes it easy to write PowerShell scripts to control
vSphere and vCenter. PowerCLI is much more advanced that vCenter Orchestrator (vCO) in terms of features
supported and easy of use.

Setup
-----

* From a privileged command prompt on the workstation, execute the following:
    C:\> powershell set-executionpolicy unrestricted

    This only needs to be done once on the workstation

* Create a folder for the script and copy the script there. For purpose of this document
    we will assume that the folder where script is located is C:\myFolder

* From command prompt, start PowerShell

    C:\myFolder> powershell

* Load the script (notice the PowerShell prompt is prefixed with PS)

    PS C:\myFolder> import-module .\cbtfix.psm1

    Ignore warning message

* Connect to vCenter server managing the cluster(s) where you want to apply the fix, Note
    that the username should be an administrator for resources in the cluster
    
    PS C:\myFolder> Connect-VIServer -server myVCserver.nam.nsroot.net -user aa12345 -password mypass

    This may take upto a minute. Ignore any warning messages. If you fail to connect, please troubleshoot with
    vmware support

The Fix
-------
For all VMs that have (1) CBT turned on and (2) at least one VMDK greater than 127GB size, the
following must occur:
    
    Step 1: Disable change block tracking (CBT). This is a virtual machine reconfigure operation
    Step 2: Take a snapshot of the virtual machine
    Step 3: Remove the snapshot taken in Step 2

Approach
--------

Step 1, turning off CBT, is done sequentially, one VM at a time, on identified virtual machines.
Step 2, creating snapshot, is done in parallel on several virtual machines at a time. The number of
parallel snap operations is throttled to prevent overloading of ESX storage (datastore). The load
threshold is user configurable with the maxLoad parameter. The default value of maxLoad is 5000 (GB).

The maxLoad parameter specifies the maximum combined VMDK GB per datastore under create or remove
snapshot operation at any point in time. To understand this better, here is an example. Suppose there
are 2 virtual machines (VM), A and B, needing the fix. VM A has two VMDKs AV1 and AV2 on datastores D1
and D2 respectively. AV1 is 10GB and AV2 is 5GB. VM B also two VMDKs BV1 and BV2 on datastores D1 and
D2 respectively. BV1 is 5 GB and BV2 is 1 GB.

If a create snap operation is executed on A and B simultaneously, a total of AV1 + BV1 = 15GB will be
impacted on datastore D1, and a total of 6GB will be impacted on D2.

    * If maxLoad is set to 4 GB, the create/delete snap operation will not run
    * If maxLoad is set to 5 GB, the create/delete snap operation will only run on B
    * If maxLoad is set to 10GB, the create/delete snap operation will run on A and B sequentially
    * If maxLoad is set to 15GB or higher, the create/delete snap operation will run on A and B in parallel

There are no best practices from vmware related to how many simultaneous snap operations are safe, or how
many snaps can simultaneously exist per datastore safetly. The only guideline is to minimize the number of
snapshots per VM, which is not applicable in this situation.

The Operator running this script can adjust the maxLoad parameter based on their comfort level while balancing
with speed of remediation. A lower number will reduce parallel tasks and thus increase time to deploy the
fix.

Testing with one Virtual Machine
--------------------------------
Before you run the fix for all virtual machines in the cluster, it is a good idea to test the fix
against one or more low risk virtual machines. This will verify the runtime environment, connection
to vCenter and expose any bugs. Testing is also helpful in learning how this fairly sophisticated
script works. Issue the following commands on the PowerShell prompt opened during Setup phase described
above, after connecting to vCenter server.

    PS C:\myFolder> test -vmName someVirtualMachineName

Examine the log.csv created at the end of the run. Here is the meaning of the TaskStage column:

* TaskStage = 0: Indicates that Step 1, turning off Changed Block Tracking, failed. See ErrorMessage for reason

* TaskStage = 1: Indicates that Change Block Tracking (CBT) was turned off successfully, but no subsequent tasks
    (create and remove snaps) were completed

* TaskStage = 2: Indicates that CBT was turned off, and Create Snap task was submitted to vCenter

* TaskStage = 3: Indicates that CBT was turned off, snapshot was created, and Remove Snap task was submitted to vCenter

* TaskStage = 4: Indicates all tasks were completed successfully. Fix was deployed successfully

Advanced Testing and Running
----------------------------
Get a list of affected VMs in a cluster:

	PS C:\myFolder> Get-MyVMs -clusterName myCluster | % { $_.Name }

Affected virtual machines are those that have (1) CBT turned on and (2) have at least one
	VMDK that is > 127GB

Send the list to a text file:
	
	PS C:\myFolder> Get-MyVMs -clusterName myCluster | % { $_.Name } > vmlist.txt

Import list of VM names to be fixed from a text file. The file should have one name per line and there should
	not be any header

	PS C:\myFolder>	$vmList = Get-Content .\vmlist.txt | % { Get-VM -Name $_ }

Check imported list:

	PS C:\myFolder>	$vmList

Apply fix on first 10 of the imported list:

	PS C:\myFolder> Apply-Fix -vmList ($vmList | select -first 10) -maxLoad 5000

Apply fix on all of the imported list:

	PS C:\myFolder> Apply-Fix -vmList $vmList -maxLoad 5000

Apply fix on imported list where VM name begins with 'dev':

	PS C:\myFolder> Apply-Fix -vmList ($vmList | where { $_.Name -match '^dev' }) -maxLoad 5000

Apply fix on imported list where VM name ends with 'dev':

	PS C:\myFolder> Apply-Fix -vmList ($vmList | where { $_.Name -match 'dev$' }) -maxLoad 5000

Apply fix on imported list where VM name has 'dev':

	PS C:\myFolder> Apply-Fix -vmList ($vmList | where { $_.Name -match 'dev' }) -maxLoad 5000

Notice that the PowerShell -match operator takes a regular expression on the right side. It is possible
to contruct complex selection critera with some knowledge of regular expressions.

Here is how to apply fix to affected VMs that have "development" in the name, 10 VMs at a time:

    PS C:\myFolder> Apply-Fix -vmList (Get-MyVMs -clusterName myCluster | where { $_.Name -match 'development' } | select -first 10) -maxLoad 5000

Here is how to apply the fix to affected VMs, 100 VMs at a time:
    
    PS C:\myFolder> Apply-Fix -vmList (Get-MyVMs -clusterName myCluster | select -first 100) -maxLoad 5000

Note that when you run the above commands again, the next set of affected VMs will be processed. This is because Get-MyVMs
only picks VMs that have CBT enabled, and Step 1 in the fix is to disable CBT.

#>

if ( (Get-PSSnapin -Name vmware.vimautomation.core -ErrorAction SilentlyContinue) -eq $null )
{
    Add-PsSnapin vmware.vimautomation.core
}

$ErrorActionPreference = 'Stop'
$scriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition

function Get-MyVMs ([string]$clusterName) {
    # Logic to select VMs that need to be processed
    # It can be any logic that outputs one or more VM objects
    foreach ($vm in @(Get-Cluster $clusterName | Get-VM)) {
        if ($vm.ExtensionData.Config.ChangeTrackingEnabled) {
            foreach ($disk in @($vm | Get-HardDisk)) {
                if ($disk.CapacityGB -gt 127) {
                    $vm
                    break
                }
            }
        }
    }
}

function Ready-VM {
    # Gets VMs ready for processing by this script
    Process {
        $dsMap = @{}
        foreach ($disk in @($_ | Get-HardDisk)) {
            #write-host $disk
            $dsName = (Get-VIObjectByVIView $disk.ExtensionData.Backing.Datastore).Name
            $dsMap[$dsName] += $disk.CapacityGB
        }
        @{vm = $_; dsMap = $dsMap; errorMsg = $null; task = $null; taskStage = 0 }
    }
}

$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.ChangeTrackingEnabled = $false 

function Disable-CBTAsync {
    # Must pipe VM objects through Ready-VM before piping to this function
    Process {
        $vmObject = $_
        try {
            $vmObject.task = Get-VIObjectByVIView $vmObject.vm.ExtensionData.ReconfigVM_Task($spec)
            $vmObject.taskStage = 1
        } catch {
            $vmObject.errorMsg = $error[0].toString()
        }
        $vmObject
    }
}

$dsLoad = @{}

function Add-Load ($maxLoad = 5000) { # specifiy maxLoad as max GB under snap per datastore
    # Must pipe VM objects through Ready-VM before piping to this function
    # Filters out VMs that will cause excessive load on datastore
    # Those that are sent out are added to dsLoad hashtable that tracks load by datastore
    Process {
        $goodToGo = $true
        foreach ($datastore in $_.dsMap.Keys) {
            if (!$dsLoad.ContainsKey($datastore)) { $dsLoad.Add($datastore, 0) }
            if (($dsLoad[$datastore] + $_.dsMap[$datastore]) -gt $maxLoad) { $goodToGo = $false; break }
        }
        if ($goodToGo) {
            foreach ($datastore in $_.dsMap.Keys) {
                $dsLoad[$datastore] += $_.dsMap[$datastore]
            }
            $_
        }
    }
}

function Remove-Load {
    # Must pipe VM objects through Ready-VM before piping to this function
    # Removes load from dsLoad load tracker
    Process {
        foreach ($datastore in $_.dsMap.Keys) {
            if ($dsLoad.ContainsKey($datastore)) {
                $dsLoad[$datastore] -= $_.dsMap[$datastore]
                if ($dsLoad[$datastore] -lt 0) { $dsLoad[$datastore] = 0 }
            }
        }
        $_
    }
}

function Create-SnapAsync {
    # Must pipe VM objects through Ready-VM before piping to this function
    Process {
        $vmObject = $_
        try {
            $vmObject.task = $vmObject.vm | New-Snapshot -Name 'Disable CBT' -RunAsync
            $vmObject.taskStage = 2
        } catch {
            $vmObject.errorMsg = $error[0].toString()
        }
        $vmObject
    }
}

function Remove-SnapAsync {
    # Must pipe VM objects through Ready-VM before piping to this function
    Process {
        $vmObject = $_
        try {
            $snap = Get-Snapshot -VM $vmObject.vm -Name 'Disable CBT'
            $vmObject.task = $snap | Remove-Snapshot -confirm:$false -RunAsync
            $vmObject.taskStage = 3
        } catch {
            $vmObject.errorMsg = $error[0].toString()
        }
        $vmObject
    }
}

function Update-TaskStatus {
    # Must pipe VM objects through Ready-VM before piping to this function
    Process {
        $vmObject = $_
        if ($vmObject.task -ne $null ) {
            try {
                $vmObject.task = Get-Task -Id $vmObject.task.Id
                if ($vmObject.task.State -notmatch 'Running|Success') {
                    $vmObject.errorMsg = $vmObject.task.State
                }
            } catch {
                $vmObject.errorMsg = 'Unable to find task id ' + $vmObject.task.value + ' on vCenter'
            }
        }
        $vmObject
    }
}

function Export-Log {
    # Writes a neat CSV log
    Begin { $log = @() }
    Process {
        $logEntry = '' | select VM, TaskStage, ErrorMessage
        $logEntry.VM = $_.vm.Name
        $logEntry.TaskStage = $_.taskStage
        $logEntry.ErrorMessage = $_.errorMsg
        $log += $logEntry
    }
    End {
        $log | Export-Csv -NoTypeInformation "$scriptPath\log.csv"
        write-host "Log exported to $scriptPath\log.csv"
    }
}

function Apply-Fix ($vmList, $maxLoad = 5000) {
    Begin { $dsLoad.Clear() }
    Process {
        $vms = @(@($vmList) | Ready-VM)
        # Make sure that maxLoad is large enough to process largest VMDK
        $largestSize = 0
        foreach ($vm in $vms) {
            foreach ($key in @($vm.dsMap.Keys)) {
                if ($vm.dsMap[$key] -gt $largestSize) { $largestSize = $vm.dsMap[$key] }
            }
        }
        if ($largestSize -gt $maxLoad) {
            throw "MaxLoad setting is too low to process all virtual machines. It should be at least $largestSize. 10x of this value is recommended for adequate parallel processing"
        }

        write-host ('Processing ' + $vms.Count + ' virtual machines')
        $processed = 0
        while ($processed -lt $vms.Count) {
            
            $cbtDisabling = @($vms | where { $_.taskStage -eq 0 } | Add-Load -maxLoad $maxLoad | Disable-CBTAsync).Count
            write-host "Started $cbtDisabling VM reconfigure (disable CBT) tasks"

            Start-Sleep 10 #seconds

            $snapping = @($vms | Update-TaskStatus | where { $_.task.State -eq 'Success' -and $_.taskStage -eq 1 -and !$_.errorMsg } | Create-SnapAsync).Count
            write-host "Started $snapping create snap tasks"
            
            Start-Sleep 10
            
            $unSnaping = @($vms | Update-TaskStatus | where { $_.task.State -eq 'Success' -and $_.taskStage -eq 2 -and !$_.errorMsg } | Remove-SnapAsync).Count
            write-host "Started $unSnaping remove snap tasks"
            
            Start-Sleep 10
            
            # Remove any errored out VMs from load tracker dsLoad
            $errors = @($vms | Update-TaskStatus | where { $_.errorMsg } | Remove-Load).Count
            write-host "Tasks on $errors VMs failed. Continuing processing"

            # Remove completed VMs from load tracker
            $success = @($vms | where { $_.task.State -eq 'Success' -and $_.taskStage -eq 3 -and !$_.errorMsg } | % { $_.taskStage = 4; $_ } | Remove-Load).Count
            write-host "$success VMs finished processing successfully. Continuing processing"

            $processed = $errors + $success
        }

        $vms | Export-Log
        write-host 'Done'
    }
}

function Test ([string]$vmName, $maxLoad = 5000) {
    # For testing the script with one VM
    $vm = Get-VM -Name $vmName
    Apply-Fix -vmList $vm -maxLoad $maxLoad
}
