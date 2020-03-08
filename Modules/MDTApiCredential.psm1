################################################
######## Create MDTApi key #####################
################################################
Function New-MDTApiCredential {
    [CmdletBinding()]
    # create guid to use as ClientId
    $MDTClientId = (New-Guid).Guid
    # loop to make sure key is unique
    while (Test-Path $MDTKeyPath\$MDTClientId)
    {
        $MDTClientId = (New-Guid).Guid
    }
    # add type containg pw generator
    Add-Type -AssemblyName 'System.Web'
    # generate api key
    $MDTApiKey = [System.Web.Security.Membership]::GeneratePassword(32,0)
    # store the encrypted api key
    convertto-securestring $MDTApiKey -asplaintext -force | ConvertFrom-SecureString | out-file $MDTKeyPath\$MDTClientId -force
    # return the created MDTClientId and MDTApiKey
    Return @{'MDTClientId'=$MDTClientId;'MDTApiKey'=$MDTApiKey}
}
################################################
######## Get MDTApi key ########################
################################################
Function Get-MDTApiCredential {
    [CmdletBinding()]
    param ($MDTClientId)
    # receive the encrypted key
    $EncryptedKey = Get-Content $MDTKeyPath\$MDTClientId | ConvertTo-SecureString
    # marshal the binary key
    $bstr=[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($EncryptedKey)
    # decrypt the key into plain text
    $MDTApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    # send plain text key back
    Return $MDTApiKey
}
################################################
######## Remove MDTApi key #####################
################################################
Function Remove-MDTApiCredential {
    [CmdletBinding()]
    param ($MDTClientId)
    # if MDTClientId specified, delete key
    if ($MDTClientId) 
    {
        Remove-Item $MDTKeyPath\$MDTClientId
    }
}
################################################
######## Set Admin MDTApi key ##################
################################################
Function Set-MDTApiAdminCredential {
    [CmdletBinding()]
    param ($MDTApiKey)
    # if new key specified, encrypt and set the key to MDTApiAdmin
    if ($MDTApiKey)
    {
        convertto-securestring $MDTApiKey -asplaintext -force | ConvertFrom-SecureString | out-file $MDTKeyPath\MDTApiAdmin -force
    }
}
################################################
######## Test MDTApi key #######################
################################################
Function Test-MDTApiCredential {
    # expecting a Polaris request header
    param ($Headers)
    # test if header contains 'MDTApiKey' and 'MDTClientId'
    if ([string]::IsNullOrEmpty($Headers['MDTApiKey']) -or [string]::IsNullOrEmpty($Headers['MDTClientId']))
    {
        Return $false
    }
    # header contains 'MDTApiKey' and 'MDTClientId', test if key is correct
    else 
    {
        # Test if 'MDTKey' value matches stored akikey
        try {($Headers['MDTApiKey'] -eq (Get-MDTApiCredential $Headers['MDTClientId'] -ea SilentlyContinue))}
        # Something went wrong, return error
        catch {Return $false}
    }
}
