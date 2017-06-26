# /*************************************************************************
# *
# * THIS SAMPLE CODE IS PROVIDED "AS IS" AND ANY EXPRESS OR IMPLIED
# * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# *
# *************************************************************************/

$SiteID = 1
$AuthenticationVirtualPath = "/Citrix/Authentication"
$authSummary = Get-DSAuthenticationServiceSummary -SiteID $SiteID -VirtualPath $AuthenticationVirtualPath
Install-DSStoreServiceAndConfigure -siteId $SiteId `
                                    -friendlyName $StoreFriendlyName `
                                    -virtualPath $StoreVirtualPath `
                                    -authSummary $authSummary `
                                    -farmName $FarmName `
                                    -servicePort $Port `
                                    -transportType $TransportType `
                                    -servers $FarmServers `
                                    -farmType $FarmType `
                                    -loadBalance $LoadBalance
