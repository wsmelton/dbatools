<#
	The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1","")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

<#
	Unit test is required for any command added
#>
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
	Context "Validate parameters" {
		<#
			The $paramCount is adjusted based on the parameters your command will have.

			The $defaultParamCount is adjusted based on what type of command you are writing the test for:
				- Commands that *do not* include SupportShouldProcess, set defaultParamCount    = 11
				- Commands that *do* include SupportShouldProcess, set defaultParamCount        = 13
		#>
		$paramCount = 6
		$defaultParamCount = 11
		[object[]]$params = (Get-ChildItem function:\Test-DbaVirtualLogFile).Parameters.Keys
		$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IncludeSystemDbs', 'EnableException'
		It "Should contain our specific parameters" {
			( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
		}
		It "Should only contain $paramCount parameters" {
			$params.Count - $defaultParamCount | Should Be $paramCount
		}
	}
}
# Get-DbaNoun
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	BeforeAll {
		$server = Connect-DbaInstance -SqlInstance $script:instance1
		$db1 = "dbatoolsci_testvlf"
		$server.Query("CREATE DATABASE $db1")
		$needed = Get-DbaDatabase -SqlInstance $script:instance1 -Database $db1
		$setupright = $true
		if ($needed.Count -ne 1) {
			$setupright = $false
			it "has failed setup" {
				Set-TestInconclusive -message "Setup failed"
			}
		}
	}
	AfterAll {
		if (-not $appveyor) {
			Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database $db1
		}
	}
	
	Context "Command actually works" {
		$results = Test-DbaVirtualLogFile -SqlInstance $script:instance1 -Database $db1
		
		It "Should have correct properties" {
			$ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Database,Total,Inactive,Active,LogFileName,LogFileGrowth,LogFileGrowthType'.Split(',')
			($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
		}

		It "Should have database name of $db1" {
			foreach ($result in $results) {
				$result.Database | Should Be $db1
			}
		}
	}
}