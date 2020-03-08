################################################
######## Settings ##############################
################################################
$ModulePath = 'C:\SomePath\Modules'
$MDTKeyPath = 'C:\SomePath\APIKeys'
$MyServerName = 'my.server.domain'
$APIPath = '/mdtapi'
$APIKeyAdminPath = '/mdtapikeyadmin'
$AdminClientId = 'MDTApiAdmin'
$MDTDatabaseServer = 'my.mdtdb.server'
$MDTDatabse = 'MDT'
$MDTComputerSettings = @'
$CurrentSettings = @{
    'OSDComputerName' = ($Request.Body.FQDN -split '.')[0];
    'AdminPassword' = (Get-MDTApiCredential "WindowsLocalAdminPassword");
    'TaskSequenceID' = $Request.Body.TestSequence;
    'OSDAdapter0DNSServerList' = ($Request.Body.DNSServers -join ',');
    'OSDAdapter0DNSSuffix' = 'my.domain';
    'OSDAdapter0EnableDHCP' = $false;
    'OSDAdapter0Gateways' = $Request.Body.Gateway;
    'OSDAdapter0IPAddressList' = $Request.Body.IPAddress;
    'OSDAdapter0MacAddress' = $Request.Body.MACAddress.ToUpper();
    'OSDAdapter0SubnetMask' = $Request.Body.NetMask;
    'OSDAdapterCount' = 1
}
'@

################################################
######## Load modules ##########################
################################################
Import-Module $ModulePath\Polaris\Polaris.psm1
Import-Module $ModulePath\MDTApiCredential.psm1
Import-Module $ModulePath\MDTApiParameter.psm1
Import-Module $ModulePath\MDTDB.psm1

################################################
######## Create the GET listener ###############
################################################
New-PolarisGetRoute -Path $APIPath -ScriptBlock {
    # test if request is authorized
    if (Test-MDTApiCredential $Request.Headers)
    {
        # Available parameters for method
        $Parameters = @('Serial','Deployed')
        # Haxx 2 build a psobject from strange string in request query
        $QueryObject = @{}
        foreach ($Param in $Parameters)
        {
            $QueryObject.$Param = $Request.Query[$Param]
        }
        # Test the parameters in request
        $TestedParameters = Test-MDTParameters -Parameters $Parameters -Body $QueryObject
        # Check if malformated input in request
        if ($TestedParameters.Malformated)
        {
            # return error
            $response.SetStatusCode(400)
            $response.Send("Parameter malformated: ($($TestedParameters.Malformated -join ', ')).")
            Return
        }
        # check if to return all computers
        elseif ($TestedParameters.Empty.Count -eq $Parameters.Count)
        {
            # return everything
            Connect-MDTDatabase -sqlServer $MDTDatabaseServer -database $MDTDatabase | Out-Null
            $response.SetStatusCode(200)
            $response.Send(((Get-MDTComputer) | ConvertTo-Json))
            Return
        }
        # build a filtered get
        else
        {
            # filter on specific serial
            if ($TestedParameters.Validated -contains 'Serial')
            {
                Connect-MDTDatabase -sqlServer $MDTDatabaseServer -database $MDTDatabase | Out-Null
                $response.SetStatusCode(200)
                $response.Send(((Get-MDTComputer -serialNumber $QueryObject.Serial) | ConvertTo-Json))
                Return
            }
            # filter on deployed status
            elseif ($TestedParameters.Validated -contains 'Deployed')
            {
                Connect-MDTDatabase -sqlServer $MDTDatabaseServer -database $MDTDatabase | Out-Null
                $response.SetStatusCode(200)
                $response.Send(((Get-MDTComputer -isDeployed $QueryObject.Deployed) | ConvertTo-Json))
                Return
            }
            # catch all rule
            else
            {
                $response.SetStatusCode(500)
                $response.Send("Unable to parse parameters ($($QueryObject -join ', '))")
                Return
            }
        }
    }
    # request not authorized
    else
    {
        $response.SetStatusCode(401)
        $response.Send('Not authorized.')
        Return
    }
} -Force

################################################
######## Create the DELETE listener ############
################################################
New-PolarisDeleteRoute -Path $APIPath -ScriptBlock {
    # Test if request is authorized
    if (Test-MDTApiCredential $Request.Headers)
    {
        # Available parameters for method
        $Parameters = @('Serial')
        # Haxx 2 build a psobject from strange string in request query
        $QueryObject = @{}
        foreach ($Param in $Parameters)
        {
            $QueryObject.$Param = $Request.Query[$Param]
        }
        # Test the parameters in request
        $TestedParameters = Test-MDTParameters -Parameters $Parameters -Body $QueryObject
        # Check if malformated input
        if ($TestedParameters.Malformated)
        {
            # return error
            $response.SetStatusCode(400)
            $response.Send("Parameter malformated: ($($TestedParameters.Malformated -join ', ')).")
            Return
        }
        # Test if parameters empty
        elseif ($TestedParameters.Empty.Count -eq $Parameters.Count)
        {
            # return error
            $response.SetStatusCode(400)
            $response.Send("Parameter missing: ($($TestedParameters.Empty -join ', ')).")
            Return
        }
        # Parameters validated delete machine(s)
        else
        {
            # Collect the machine(s) to delete
            Connect-MDTDatabase -sqlServer $MDTDatabaseServer -database $MDTDatabase | Out-Null
            $DeleteMDTMachines = Get-MDTComputer -serialNumber $QueryObject.Serial
            $response.SetStatusCode(200)
            $response.Send((($DeleteMDTMachines.id | %{Remove-MDTComputer -id $_}) | ConvertTo-Json))
            Return
        }
    }
    # request not authorized
    else
    {
        $response.SetStatusCode(401)
        $response.Send('Not authorized.')
        Return
    }
} -Force

################################################
######## Create the POST listener ##############
################################################
New-PolarisPostRoute -Path $APIPath -ScriptBlock {
    # test if request is authorized
    if (Test-MDTApiCredential $Request.Headers)
    {
        # Available parameters for method
        $TestParameters = @('Serial','TestSequence','IPAddress','NetMask','Gateway','DNSServers','MACAddress','FQDN')
        # test if payload json exist
        if ([string]::IsNullOrEmpty($Request.BodyString))
        {
            # return json
            $response.SetStatusCode(400)
            $response.Send('Missing json body.')
            Return
        }
        # payload json exist, continue
        else
        {
            # convert payload json to psobject
            try {$Request.Body = ($Request.BodyString | ConvertFrom-Json -ea stop)}
            catch {
                # json is malformated
                $response.SetStatusCode(400)
                $response.Send('Malformated json.')
                Return
            }
            # Test the parameters in request
            $TestedParameters = Test-MDTParameters -Parameters $TestParameters -Body $Request.Body
            # create an array to hold any validation error messages
            $ParameterValidationErrors = @()
            # collect missing parameters and add to error
            if ($TestedParameters.Empty)
            {
                $ParameterValidationErrors += "Parameter missing: ($($TestedParameters.Empty -join ', '))."
            }
            # collect malformated parameter values and add to error
            if ($TestedParameters.Malformated)
            {
                $ParameterValidationErrors += "Bad parameter value on: ($($TestedParameters.Malformated -join ', '))."
            }
            # everything is hunky dory, execute the stuff!
            if (($TestedParameters.Validated.count -eq $TestParameters.count) -and (!$ParameterValidationErrors))
            {
                # Ready to rock and roll
                Connect-MDTDatabase -sqlServer $MDTDatabaseServer -database $MDTDatabase | Out-Null
                # populate the mdt settings hash with input values to $CurrentSettings variable
                Invoke-Expression $MDTComputerSettings
                # execute and return
                $response.SetStatusCode(200)
                $response.Send(((New-MDTComputer -settings $CurrentSettings) | ConvertTo-Json))
                Return
            }
            # something is wrong with input, return error
            else
            {
                $response.SetStatusCode(400)
                $response.Send("Invalid input. $($ParameterValidationErrors -join '. ')")
                Return
            }
        }
    }
    # authentication failed
    else
    {
        $response.SetStatusCode(401)
        $response.Send('Not authorized.')
        Return
    }
} -Force

################################################
######## Create GET Api Key Admin ##############
################################################
New-PolarisGetRoute -Path $APIKeyAdminPath -ScriptBlock {
    # test if request is authorized as admin
    if (($Request.Headers['MDTClientId'] -eq $AdminClientId) -and ($Request.Headers['MDTApiKey'] -eq (Get-MDTApiCredential $AdminClientId -ea SilentlyContinue)))
    {
        # authorized, create key and return it
        $response.SetStatusCode(201)
        $response.Send(((New-MDTApiCredential) | ConvertTo-Json))
        Return
    }
    # request not authorized
    else
    {
        $response.SetStatusCode(401)
        $response.Send('Not authorized.')
        Return
    }
} -Force

################################################
######## Create DELETE Api Key Admin ###########
################################################
New-PolarisDeleteRoute -Path $APIKeyAdminPath -ScriptBlock {
    # test if request is authorized
    if (Test-MDTApiCredential $Request.Headers)
    {
        # Available parameters for method
        $Parameters = @('MDTClientId')
        # Haxx 2 build a psobject from strange string in request query
        $QueryObject = @{}
        foreach ($Param in $Parameters)
        {
            $QueryObject.$Param = $Request.Query[$Param]
        }
        # Test the parameters in request
        $TestedParameters = Test-MDTParameters -Parameters $Parameters -Body $QueryObject
        # Check if malformated input
        if ($TestedParameters.Malformated)
        {
            # return error
            $response.SetStatusCode(400)
            $response.Send("Parameter malformated: ($($TestedParameters.Malformated -join ', ')).")
            Return
        }
        # check if parameters missing
        elseif ($TestedParameters.Empty.Count -eq $Parameters.Count)
        {
            # return error
            $response.SetStatusCode(400)
            $response.Send("Parameter missing: ($($TestedParameters.Empty -join ', ')).")
            Return
        }
        # input validated, continue
        else
        {
            # check if admin or trying to delete own key
            if ((($Request.Headers['MDTClientId'] -eq $AdminClientId) -or ($Request.Headers['MDTClientId'] -eq $QueryObject.MDTClientId)) -and ($QueryObject.MDTClientId -notlike $AdminClientId))
            {
                # remove key
                try {Remove-MDTApiCredential -MDTClientId $QueryObject.MDTClientId -ea stop}
                catch {
                    # failed, key probably non existing
                    $response.SetStatusCode(500)
                    $response.Send("Unable to delete key for MDTClientId ($($QueryObject.MDTClientId -join ', ')). Key may not exist.")
                    Return
                }
                # key deleted, return response
                $response.SetStatusCode(200)
                $response.Send("Deleted Key for MDTClientId ($($QueryObject.MDTClientId -join ', ')).")
                Return
            }
            # not authorized to delete requested key
            else
            {
                $response.SetStatusCode(401)
                $response.Send("Not authorized to delete key for MDTClientId ($($QueryObject.MDTClientId -join ', ')).")
                Return
            }
        }
    }
    # request not authorized
    else
    {
        $response.SetStatusCode(401)
        $response.Send('Not authorized.')
        Return
    }
} -Force

# Make it go!
Start-Polaris -Port 443 -MinRunspaces 1 -MaxRunspaces 5 -Https -HostName $MyServerName
