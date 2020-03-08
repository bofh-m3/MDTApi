################################################
######## Validate MDT parameter values #########
################################################
Function Test-MDTParameters {
    param ($Parameters, $Body)
    # validation patterns for each available parameter. can be array with exact matches or regex.
    $SerialMatchVar = '^(?=.{5,256}$).*'                                                                                # match all characters (5-256)
    $TestSequenceMatchVar = @('a1','a2')                                                                                # exact sequences
    $IPAddressMatchVar = '\b((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}\b'                                        # ip address regex
    $NetMaskMatchVar = @('255.255.255.0','255.255.254.0')                                                               # exact netmask
    $GateWayMatchVar = '\b((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}\b'                                          # ip address regex
    $DNSServersMatchVar = '\b((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}\b'                                       # ip address regex
    $MACAddressMatchVar = '^([0-9A-F]{2}[:-]){5}([0-9A-F]{2})$'                                                         # mac address regex
    $FQDNMatchVar = '(^[a-z0-9]{1,15}).my.domain$'                                                                      # match 1-15 chars in hostname + domain
    $DeployedMatchVar = @('Yes','No')                                                                                   # exact matches
    $MDTClientIdMatchVar = '(^([0-9A-Fa-f]{8}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{4}[-][0-9A-Fa-f]{12})$)'  # GUID regex
    # hash table to hold the allowed amount of values for each parameter
    $ParametersAmountRequred = @{
        'Serial'=1;
        'TestSequence'=1;
        'IPAddress'=1;
        'NetMask'=1;
        'Gateway'=1;
        'DNSServers'=1..5;
        'MACAddress'=1;
        'FQDN'=1;
        'Deployed'=1;
        'MDTClientId'=1
    }
    #Create empty arrays to hold the validation results
    $Validated = @()
    $Malformated = @()
    $Empty = @()
    # loop through parameters and test them against validation patterns and amount of values
    foreach ($Parameter in $Parameters)
    {
        # check if empty value for parameter in body
        if ([string]::IsNullOrEmpty($Body.$Parameter))
        {
            $Empty += $Parameter
        }
        # check if proper amount of parameter values in body
        elseif ($Body.$Parameter.Count -notin $ParametersAmountRequred.$Parameter)
        {
            $Malformated += $Parameter
        }
        # parameter has multiple values in body, validate all
        elseif ($Body.$Parameter.count -ge 2)
        {
            # extract the curent validation pattern
            $CurrentMatchVar = (iex ('$' + $Parameter + 'MatchVar'))
            # valid until proven otherwise
            $ValError = $false
            # test if validation pattern is an array of exact matches
            if ($CurrentMatchVar.Count -ge 2)
            {
                # loop through each parameter value and test against array of exact matches
                foreach ($i in $Body.$Parameter)
                {
                    # Test if current value match pattern array
                    if ($i -notin $CurrentMatchVar) 
                    {
                        $ValError = $true
                    }
                }
            }
            # the validation pattern is a regex
            else
            {
                # loop through each parameter value and test against regex
                foreach ($i in $Body.$Parameter)
                {
                    if ($i -notmatch $CurrentMatchVar) 
                    {
                        $ValError = $true
                    }
                }
            }
            # check if all parameter values passed test
            if (!$ValError)
            {
                $Validated += $Parameter
            }
            # one or more parameter values failed test
            else
            {
                $Malformated += $Parameter
            }
        }
        # parameter has one value in body, validate it
        else
        {
            # extract the curent validation pattern
            $CurrentMatchVar = (iex ('$' + $Parameter + 'MatchVar'))
            # test if validation pattern is an array of exact matches
            if ($CurrentMatchVar.Count -ge 2)
            {
                # test if parameter value exist in pattern array
                if ($Body.$Parameter -notin $CurrentMatchVar)
                {
                    $Malformated += $Parameter
                }
                else 
                {
                    $Validated += $Parameter
                }
            }
            # the validation pattern is a regex
            else 
            {
                # test parameter value against regex
                if ($Body.$Parameter -notmatch $CurrentMatchVar) 
                {
                    $Malformated += $Parameter
                }
                else 
                {
                    $Validated += $Parameter
                }
            }
        }
    }
    # compose the result psobject and return it
    $Result = "" | select @{n="Validated";e={$Validated}},@{n="Malformated";e={$Malformated}},@{n="Empty";e={$Empty}}
    Return $Result
}
