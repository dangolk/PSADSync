,#region import modules
$ThisModule = "$($MyInvocation.MyCommand.Path -replace '\.Tests\.ps1$', '').psd1"
$ThisModuleName = (($ThisModule | Split-Path -Leaf) -replace '\.psd1')
Get-Module -Name $ThisModuleName -All | Remove-Module -Force

Import-Module -Name $ThisModule -Force -ErrorAction Stop
#endregion

describe 'Module-level tests' {
	
	it 'should validate the module manifest' {
	
		{ Test-ModuleManifest -Path $ThisModule -ErrorAction Stop } | should not throw
	}

	it 'should pass all error-level script analyzer rules' {

		$excludedRules = @(
			'PSUseShouldProcessForStateChangingFunctions',
			'PSUseToExportFieldsInManifest',
			'PSAvoidInvokingEmptyMembers',
			'PSUsePSCredentialType',
			'PSAvoidUsingPlainTextForPassword'
		)

		Invoke-ScriptAnalyzer -Path $PSScriptRoot -ExcludeRule $excludedRules -Severity Error | should benullorempty
	}
}

InModuleScope $ThisModuleName {

	$script:AllAdsiUsers = 0..10 | ForEach-Object {
		$i = $_
		$adsiUser = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
		$amParams = @{
			MemberType = 'NoteProperty'
			Force = $true
		}
		$props = @{
			'Name' = 'nameval'
			'Enabled' = $true
			'SamAccountName' = 'samval'
			'GivenName' = 'givennameval'
			'Surname' = 'surnameval'
			'DisplayName' = 'displaynameval'
			'OtherProperty' = 'otherval'
			'EmployeeId' = 1
			'Title' = 'titleval'
		}
		$props.GetEnumerator() | ForEach-Object {
			if ($_.Key -eq 'Enabled') {
				if ($i % 2) {
					$adsiUser | Add-Member @amParams -Name $_.Key -Value $false
				} else {
					$adsiUser | Add-Member @amParams -Name $_.Key -Value $true
				}
			} else {
				$adsiUser | Add-Member @amParams -Name $_.Key -Value "$($_.Value)$i"
			}
		}
		if ($i -eq 5) {
			$adsiUser | Add-Member @amParams -Name 'samAccountName' -Value $null
		}
		if ($i -eq 6) { 
			$adsiUser | Add-Member @amParams -Name 'EmployeeId' -Value $null
		}
		$adsiUser
	}

	$script:AllCsvUsers = 0..15 | ForEach-Object {
		$i = $_
		$output = @{ 
			AD_LOGON = "nameval$i"
			PERSON_NUM = "1$i" 
			ExcludeCol = 'dontexcludeme'
		}
		if ($i -eq (Get-Random -Maximum 9)) {
			$output.'AD_LOGON' = $null
			$output.ExcludeCol = 'excludeme'
		}
		if ($i -eq (Get-Random -Maximum 9)) {
			$output.'PERSON_NUM' = $null
		}
		[pscustomobject]$output 
	}

	describe 'Get-CompanyCsvUser' {
	
		$commandName = 'Get-CompanyCsvUser'
	
		#region Mocks
			$script:csvUsers = @(
				[pscustomobject]@{
					AD_LOGON = 'foo'
					PERSON_NUM = 123
					OtherAtrrib = 'x'
					ExcludeCol = 'excludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
				[pscustomobject]@{
					AD_LOGON = 'foo2'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'excludeme'
				}
				[pscustomobject]@{
					AD_LOGON = 'notinAD'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
				[pscustomobject]@{
					AD_LOGON = $null
					PERSON_NUM = 12345
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
			)

			mock 'Import-Csv' {
				$script:csvUsers
			}

			mock 'Test-Path' {
				$true
			}

			$script:csvUsersNullConvert = $script:csvUsers | ForEach-Object { if (-not $_.'AD_LOGON') { $_.'AD_LOGON' = 'null' } $_ }
		#endregion
		
		$parameterSets = @(
			@{
				CsvFilePath = 'C:\users.csv'
				TestName = 'All users'
			}
			@{
				CsvFilePath = 'C:\users.csv'
				Exclude = @{ ExcludeCol = 'excludeme' }
				TestName = 'Exclude 1 col'
			}
			@{
				CsvFilePath = 'C:\users.csv'
				Exclude = @{ ExcludeCol = 'excludeme';ExcludeCol2 = 'excludeme' }
				TestName = 'Exclude 2 cols'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			Exclude = $parameterSets.where({$_.ContainsKey('Exclude')})
			Exclude1Col = $parameterSets.where({$_.ContainsKey('Exclude') -and ($_.Exclude.Keys.Count -eq 1)})
			Exclude2Cols = $parameterSets.where({$_.ContainsKey('Exclude') -and ($_.Exclude.Keys.Count -eq 2)})
			NoExclusions = $parameterSets.where({ -not $_.ContainsKey('Exclude')})
		}

		context 'when at least one column is excluded' {

			mock 'Where-Object' {
				[pscustomobject]@{
					AD_LOGON = 'foo2'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'excludeme'
				}
				[pscustomobject]@{
					AD_LOGON = 'notinAD'
					PERSON_NUM = 1234
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
				[pscustomobject]@{
					AD_LOGON = $null
					PERSON_NUM = 12345
					OtherAtrrib = 'x'
					ExcludeCol = 'dontexcludeme'
					ExcludeCol2 = 'dontexcludeme'
				}
			} -ParameterFilter { $FilterScript.ToString() -notmatch '\*' }
		
			it 'should create the expected where filter: <TestName>' -TestCases $testCases.Exclude {
				param($CsvFilePath,$Exclude)
			
				& $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'Where-Object'
					Times = $script:csvUsers.Count
					Exactly = $true
					Scope = 'It'
					ParameterFilter = { 
						$PSBoundParameters.FilterScript.ToString() -like "(`$_.`'*' -ne '*')*" }
				}
				Assert-MockCalled @assMParams
			}
		
		}

		it 'when excluding no cols, should return all expected users: <TestName>' -TestCases $testCases.NoExclusions {
			param($CsvFilePath,$Exclude)
		
			$result = & $commandName @PSBoundParameters

			(Compare-Object $script:csvUsersNullConvert.'AD_LOGON' $result.'AD_LOGON').InputObject | should benullorempty
		}

		it 'when excluding 1 col, should return all expected users: <TestName>' -TestCases $testCases.Exclude1Col {
			param($CsvFilePath,$Exclude)
		
			$result = & $commandName @PSBoundParameters

			(Compare-Object @('foo2','notinAD','null') $result.'AD_LOGON').InputObject | should benullorempty
		}
	
		it 'when excluding 2 cols, should return all expected users: <TestName>' -TestCases $testCases.Exclude2Cols {
			param($CsvFilePath,$Exclude)
		
			$result = & $commandName @PSBoundParameters

			(Compare-Object @('notinAD','null') $result.'AD_LOGON').InputObject | should benullorempty
		}
	}

	describe 'GetCsvColumnHeaders' {
		
		#region Mocks
			mock 'Get-Content' {
				@(
					'"Header1","Header2","Header3"'
					'"Value1","Value2","Value3"'
					'"Value4","Value5","Value6"'
				)
			}
		#endregion

		it 'should return expected headers' {
		
			$result = & GetCsvColumnHeaders -CsvFilePath 'foo.csv'
			Compare-Object $result @('Header1','Header2','Header3') | should benullorempty
		}
		
	}

	describe 'TestCsvHeaderExists' {
		
		#region Mocks
			mock 'GetCsvColumnHeaders' {
				'Header1','Header2','Header3'
			}
		#endregion


		context 'when a header is not in the CSV' {
		
			it 'should return $false' {
			
				TestCsvHeaderExists -CsvFilePath 'foo.csv' -Header 'nothere' | should be $false
			}	
		
		}

		context 'when all headers are in the CSV' {

			it 'should return $true' {
				TestCsvHeaderExists -CsvFilePath 'foo.csv' -Header 'Header1','Header2','Header3' | should be $true
			}
	
		}

		context 'when one header is in the CSV' {

			it 'should return $true' {		
				TestCsvHeaderExists -CsvFilePath 'foo.csv' -Header 'Header1' | should be $true
			}

		}
		
	}

	describe 'Get-CompanyAdUser' {
	
		$commandName = 'Get-CompanyAdUser'

	
		#region Mocks
			mock 'GetAdUser' {
				$script:AllAdsiUsers | Where-Object { $_.Enabled }
			} -ParameterFilter { $LdapFilter }

			mock 'GetAdUser' {
				$script:AllAdsiUsers
			} -ParameterFilter { -not $LdapFilter }
		#endregion
		
		$parameterSets = @(
			@{
				TestName = 'All users'
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}

		it 'should return all users: <TestName>' -TestCases $testCases.All {
			param($All,$Credential)
		
			$result = & $commandName @PSBoundParameters
			@($result).Count | should be @($script:AllAdsiUsers).Count
		}

	}

	describe 'FindUserMatch' {
	
		$commandName = 'FindUserMatch'
		
	
		#region Mocks
			mock 'Write-Warning'

			$script:csvUserMatchOnOneIdentifer = @(
				[pscustomobject]@{
					AD_LOGON = 'foo'
					PERSON_NUM = 'nomatch'
				}
			)

			$script:csvUserMatchOnAllIdentifers = @(
				[pscustomobject]@{
					AD_LOGON = 'foo'
					PERSON_NUM = 123
				}
			)

			$script:OneblankCsvUserIdentifier = @(
				[pscustomobject]@{
					PERSON_NUM = $null
					AD_LOGON = 'foo'				
				}
			)

			$script:AllblankCsvUserIdentifier = @(
				[pscustomobject]@{
					AD_LOGON = $null
					PERSON_NUM = $null
				}
			)
			
			$script:noBlankCsvUserIdentifier = @(
				[pscustomobject]@{
					AD_LOGON = 'ffff'
					PERSON_NUM = '111111'
				}
			)

			$script:csvUserNoMatch = @(
				[pscustomobject]@{
					AD_LOGON = 'NotInAd'
					PERSON_NUM = 'nomatch'
				}
			)

			$script:AdUsers = @(
				[pscustomobject]@{
					samAccountName = 'foo'
					EmployeeId = 123
				}
				[pscustomobject]@{
					samAccountName = 'foo2'
					EmployeeId = 111
				}
				[pscustomobject]@{
					samAccountName = 'NotinCSV'
					EmployeeId = 12345
				}
			)

			mock 'Write-Verbose'
		#endregion
		
		$parameterSets = @(
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserMatchOnOneIdentifer
				TestName = 'Match on 1 ID'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserMatchOnAllIdentifers
				TestName = 'Match on all IDs'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:csvUserNoMatch
				TestName = 'No Match'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:OneblankCsvUserIdentifier
				TestName = 'One Blank ID'
			}
			@{
				AdUsers = $script:AdUsers
				CsvUser = $script:AllblankCsvUserIdentifier
				TestName = 'All Blank IDs'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			MatchOnOneId = $parameterSets.where({$_.TestName -eq 'Match on 1 ID'})
			MatchOnAllIds = $parameterSets.where({$_.TestName -eq 'Match on all IDs'})
			NoMatch = $parameterSets.where({$_.TestName -eq 'No Match'})
			OneBlankId = $parameterSets.where({ $_.CsvUser.AD_LOGON -and (-not $_.CsvUser.PERSON_NUM) })
			AllBlankIds = $parameterSets.where({ -not $_.CsvUser.AD_LOGON -and (-not $_.CsvUser.PERSON_NUM) })
		}

		context 'When no matches could be found' {
			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.NoMatch {
				param($AdUsers,$CsvUser)
			
				& $commandName @PSBoundParameters | should benullorempty
			}
		}

		context 'When one match can be found' {

			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.MatchOnOneId {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1
			}

			it 'should find matches as expected and return the expected property values: <TestName>' -TestCases $testCases.MatchOnOneId {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters

				$result.MatchedAdUser.EmployeeId | should be 123
				$result.CsvIdMatchedOn | should be 'AD_LOGON'
				$result.AdIdMatchedOn | should be 'samAccountName'

			}
		}

		context 'When multiple matches could be found' {

			it 'should return the expected number of objects: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1
			}

			it 'should find matches as expected and return the expected property values: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters

				$result.MatchedAdUser.EmployeeId | should be 123
				$result.CsvIdMatchedOn | should be 'PERSON_NUM'
				$result.AdIdMatchedOn | should be 'employeeid'

			}
		}

		context 'when a blank identifier is queried before finding a match' {

			it 'should do nothing: <TestName>' -TestCases $testCases.OneBlankId {
				param($AdUsers,$CsvUser)
			
				& $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'Write-Verbose'
					Times = 1
					Exactly = $true
					Scope = 'It'
					ParameterFilter = { $PSBoundParameters.Message -match '^CSV field match value' }
				}
				Assert-MockCalled @assMParams
			}

			it 'should return the expected object properties: <TestName>' -TestCases $testCases.OneBlankId {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters
				$result.MatchedAdUser.samAccountName | should be 'foo'
				$result.CsvIdMatchedOn | should be 'AD_LOGON'
				$result.AdIdMatchedOn | should be 'samAccountName'
			}

		}

		context 'when all identifers are blank' {

			it 'should do nothing: <TestName>' -TestCases $testCases.AllBlankIds {
				param($AdUsers,$CsvUser)
			
				& $commandName @PSBoundParameters

				$assMParams = @{
					CommandName = 'Write-Verbose'
					Times = 2
					Exactly = $true
					Scope = 'It'
					ParameterFilter = { $PSBoundParameters.Message -match '^CSV field match value' }
				}
				Assert-MockCalled @assMParams
			}

		}

		context 'when all identifiers are valid' {
		
			it 'should return the expected object properties: <TestName>' -TestCases $testCases.MatchOnAllIds {
				param($AdUsers,$CsvUser)
			
				$result = & $commandName @PSBoundParameters
				@($result.MatchedAdUser).foreach({
					$_.PSObject.Properties.Name -contains 'EmployeeId' | should be $true
				})
				$result.CsvIdMatchedOn | should be 'PERSON_NUM'
				$result.AdIdMatchedOn | should be 'employeeId'
			}
		
		}
	}

	describe 'FindAttributeMismatch' {
	
		$commandName = 'FindAttributeMismatch'
		
	
		#region Mocks
			mock 'Write-Verbose'

			$script:csvUserMisMatch = [pscustomobject]@{
				AD_LOGON = 'foo'
				PERSON_NUM = 123
				OtherAtrrib = 'x'
			}

			$script:csvUserNoMisMatch = [pscustomobject]@{
				AD_LOGON = 'foo'
				PERSON_NUM = 1111
				OtherAtrrib = 'y'
			}

			$script:AdUserMisMatch = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
			$script:AdUserMisMatch | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'foo'
			$script:AdUserMisMatch | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value $null -PassThru

			$script:AdUserNoMisMatch = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
			$script:AdUserNoMisMatch | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'foo'
			$script:AdUserNoMisMatch | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value 1111 -PassThru

			mock 'Get-Member' {
				[pscustomobject]@{
					Name = 'samAccountName'
				}
				[pscustomobject]@{
					Name = 'EmployeeId'
				}
			}
		#endregion
		
		$parameterSets = @(
			@{
				AdUser = $script:AdUserMisMatch
				CsvUser = $script:csvUserMisMatch
				TestName = 'Mismatch'
			}
			@{
				AdUser = $script:AdUserNoMisMatch
				CsvUser = $script:csvUserNoMisMatch
				TestName = 'No Mismatch'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			Mismatch = $parameterSets.where({$_.TestName -eq 'Mismatch'})
			NoMismatch = $parameterSets.where({$_.TestName -eq 'No Mismatch'})
		}

		it 'should find the correct AD property names: <TestName>' -TestCases $testCases.All {
			param($AdUser,$CsvUser)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Write-Verbose'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Message -eq "ADUser props: [samAccountName,EmployeeId]" }
			}
			Assert-MockCalled @assMParams
		}

		it 'should find the correct CSV property names: <TestName>' -TestCases $testCases.All {
			param($AdUser,$CsvUser)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Write-Verbose'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Message -eq 'CSV properties are: [AD_LOGON,PERSON_NUM,OtherAtrrib]' }
			}

			Assert-MockCalled @assMParams
		}

		context 'when a mismatch is found' {

			it 'should return the expected objects: <TestName>' -TestCases $testCases.Mismatch {
				param($AdUser,$CsvUser)
			
				$result = & $commandName @PSBoundParameters
				@($result).Count | should be 1
				$result | should beoftype 'hashtable'
				$result.CSVAttributeName | should be 'PERSON_NUM'
				$result.CSVAttributeValue | should be 123
				$result.ADAttributeName | should be 'EmployeeId'
				$result.ADAttributeValue | should be ''
			}
		}

		context 'when no mismatches are found' {

			it 'should return nothing: <TestName>' -TestCases $testCases.NoMismatch {
				param($AdUser,$CsvUser)
			
				& $commandName @PSBoundParameters | should benullorempty
			}

		}
		
		context 'when a non-terminating error occurs in the function' {

			mock 'Write-Verbose' {
				Write-Error -Message 'error!'
			}

			it 'should throw an exception: <TestName>' -TestCases $testCases.All {
				param($AdUser,$CsvUser)
			
				$params = @{} + $PSBoundParameters
				{ & $commandName @params } | should throw 'error!'
			}
		}
	
	}

	describe 'SetAduser' {
	
		$commandName = 'SetAduser'
		

		mock 'SaveAdUser'

		mock 'GetAdUser' {
			$obj = New-MockObject -Type 'System.DirectoryServices.SearchResult'
			$obj | Add-Member -MemberType NoteProperty -Name 'Properties' -PassThru -Force -Value ([pscustomobject]@{
				adsPath = 'adspathhere'
			})
		} -ParameterFilter { $OutputAs -eq 'SearchResult' }

		mock 'GetAdUser' {
			New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
		} -ParameterFilter { $OutputAs -ne 'SearchResult' }
	
		$parameterSets = @(
			@{
				Identity = @{ samAccountName = 'samnamehere'}
				Attribute = @{ employeeId = 'empidhere' }
			}
			@{
				Identity = @{ employeeId = 'empidhere'}
				Attribute = @{ displayName = 'displaynamehere' }
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}
	
		it 'returns nothing' -TestCases $testCases.All {
			param($Identity,$Attribute)

			& $commandName @PSBoundParameters | should benullorempty
		}

		it 'should save the expected attribute' -TestCases $testCases.All {
			param($Identity,$Attribute)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'SaveAdUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					(-not (Compare-Object $PSBoundParameters.Parameters.Attribute.Keys $Attribute.Keys)) -and
					(-not (Compare-Object $PSBoundParameters.Parameters.Attribute.Values $Attribute.Values))
				}
			}
			Assert-MockCalled @assMParams
		}

		it 'should save on the expected identity' -TestCases $testCases.All {
			param($Identity,$Attribute)

			& $commandName @PSBoundParameters
		
			$assMParams = @{
				CommandName = 'SaveAdUser'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Parameters.AdsPath -eq 'adspathhere'
				}
			}
			Assert-MockCalled @assMParams
		}
	
	}

	describe 'SyncCompanyUser' {
	
		$commandName = 'SyncCompanyUser'
		

		$script:AdUserUpn = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
		$script:AdUserUpn | Add-Member -MemberType NoteProperty -Name 'samAccountName' -Force -Value 'foo'
		$script:AdUserUpn | Add-Member -MemberType NoteProperty -Name 'EmployeeId' -Force -Value $null -PassThru

		$script:csvUser = [pscustomobject]@{
			AD_LOGON = 'foo'
			PERSON_NUM = 123
			OtherAtrrib = 'x'
		}

		mock 'SetAduser'
	
		$parameterSets = @(
			@{
				AdUser = $script:AdUserUpn
				CsvUser = $script:csvUser
				Attributes = @{ 
					ADAttributeName = 'EmployeeId'
					ADAttributeValue = $null
					CSVAttributeName = 'username'
					CSVAttributeValue = 'userhere'
			 	}
				Identifier = 'samAccountName'
				Confirm = $false
				TestName = 'Single attribute'
			}
			@{
				AdUser = $script:AdUserUpn
				CsvUser = $script:csvUser
				Attributes = @(@{ 
					ADAttributeName = 'EmployeeId'
					ADAttributeValue = $null
					CSVAttributeName = 'username'
					CSVAttributeValue = 'userhere'
			 	},
				 @{ 
					ADAttributeName = 'EmployeeId'
					ADAttributeValue = $null
					CSVAttributeName = 'username'
					CSVAttributeValue = 'userhere'
			 	})
				Identifier = 'employeeId'
				Confirm = $false
				TestName = 'Multiple attributes'
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}
	
		it 'should change only those attributes in the Attributes parameter: <TestName>' -TestCases $testCases.All {
			param($AdUser,$CsvUser,$Identifier,$Attributes)
		
			& $commandName @PSBoundParameters -Confirm:$false

			$assMParams = @{
				CommandName = 'SetAdUser'
				Times = @($Attributes).Count
				Exactly = $true
				Scope = 'It'
				ParameterFilter = {
					foreach ($i in $Attributes) {
						$PSBoundParameters.Attribute.($i.ADAttributeName) -eq ($i.CSVAttributeValue)
					}
					
				 }
			}
			Assert-MockCalled @assMParams
		}

		it 'should change attributes on the expected user account: <TestName>' -TestCases $testCases.All {
			param($AdUser,$CsvUser,$Identifier,$Attributes)
		
			& $commandName @PSBoundParameters -Confirm:$false

			$assMParams = @{
				CommandName = 'SetAdUser'
				Times = @($Attributes).Count
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$PSBoundParameters.Identity.$Identifier -eq $AdUser.$Identifier }
			}
			Assert-MockCalled @assMParams
		}

		context 'when a non-terminating error occurs in the function' {

			mock 'Write-Verbose' {
				Write-Error -Message 'error!'
			}

			it 'should throw an exception: <TestName>' -TestCases $testCases.All {
				param($AdUser,$CsvUser,$Identifier,$Attributes)
			
				$params = @{} + $PSBoundParameters
				{ & $commandName @params -Confirm:$false } | should throw 'error!'
			}
		}
	}
		
	describe 'WriteLog' {
	
		$commandName = 'WriteLog'
		

		mock 'Get-Date' {
			'time'
		}

		mock 'Export-Csv'
	
		$parameterSets = @(
			@{
				FilePath = 'C:\log.csv'
				CSVIdentifierValue = 'username'
				CSVIdentifierField = 'employeeid'
				Attributes = @{ 
					ADAttributeName = 'EmployeeId'
					ADAttributeValue = $null
					CSVAttributeName = 'PERSON_NUM'
					CSVAttributeValue = 123
				}
				TestName = 'Standard'
			}
		)
	
		$testCases = @{
			All = $parameterSets
		}
	
		it 'should export a CSV to the expected path: <TestName>' -TestCases $testCases.All {
			param($FilePath,$CSVIdentifierValue,$CSVIdentifierField,$Attributes)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Export-Csv'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { $PSBoundParameters.Path -eq $FilePath }
			}
			Assert-MockCalled @assMParams
		}

		it 'should appends to the CSV: <TestName>' -TestCases $testCases.All {
			param($FilePath,$CSVIdentifierValue,$CSVIdentifierField,$Attributes)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Export-Csv'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { $Append }
			}
			Assert-MockCalled @assMParams
		}

		it 'should export as CSV with the expected values: <TestName>' -TestCases $testCases.All {
			param($FilePath,$CSVIdentifierValue,$CSVIdentifierField,$Attributes)
		
			& $commandName @PSBoundParameters

			$assMParams = @{
				CommandName = 'Export-Csv'
				Times = 1
				Exactly = $true
				Scope = 'It'
				ParameterFilter = { 
					$InputObject.Time -eq 'time' -and
					$InputObject.CSVIdentifierValue -eq $CSVIdentifierValue -and
					$InputObject.CSVIdentifierField -eq $CSVIdentifierField -and
					$InputObject.ADAttributeName -eq 'EmployeeId' -and
					$InputObject.ADAttributeValue -eq $null -and
					$InputObject.CSVAttributeName -eq 'PERSON_NUM' -and
					$InputObject.CSVAttributeValue -eq 123
				}
			}
			Assert-MockCalled @assMParams
		}
	}

	describe 'Invoke-AdSync' {
	
		$commandName = 'Invoke-AdSync'
		

		#region Mocks

			mock 'Get-CompanyAdUser' {
				$adsiUser = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
				$amParams = @{
					MemberType = 'NoteProperty'
					Force = $true
				}
				$props = @{
					'Name' = 'nameval'
					'Enabled' = $true
					'SamAccountName' = 'samval'
					'GivenName' = 'givennameval'
					'Surname' = 'surnameval'
					'DisplayName' = 'displaynameval'
					'OtherProperty' = 'otherval'
					'EmployeeId' = 1
					'Title' = 'titleval'
				}
				$props.GetEnumerator() | ForEach-Object {
					$adsiUser | Add-Member @amParams -Name $_.Key -Value $_.Value
				}
				$adsiUser
			}

			mock 'Get-CompanyCsvUser' {
				[pscustomobject]@{ 
					AD_LOGON = "nameval"
					PERSON_NUM = "1" 
				}
			}

			mock 'WriteLog'
			
			mock 'Test-Path' {
				$true
			}

			mock 'SyncCompanyUser'

			mock 'Write-Warning'

			mock 'TestCsvHeaderExists' {
				$true
			}
		#endregion
		
	
		$parameterSets = @(
			@{
				CsvFilePath = 'C:\log.csv'
				TestName = 'Sync'
			}
			@{
				CsvFilePath = 'C:\log.csv'
				ReportOnly = $true
				TestName = 'Report'
			}
			@{
				CsvFilePath = 'C:\log.csv'
				Exclude = @{ ExcludeCol = 'excludeme' }
				TestName = 'Excluded valid col'
			}
			@{
				CsvFilePath = 'C:\log.csv'
				Exclude = @{ ColNotHere = 'excludeme' }
				TestName = 'Exclude bogus col'
			}
		)
	
		$testCases = @{
			All = $parameterSets
			ReportOnly = $parameterSets.where({$_.ContainsKey('ReportOnly')})
			Sync = $parameterSets.where({-not $_.ContainsKey('ReportOnly')})
			NoExclusions = $parameterSets.where({-not $_.ContainsKey('Exclude')})
			ExcludeCol = $parameterSets.where({$_.ContainsKey('Exclude') -and (-not $_.Exclude.Keys.Contains('ColNotHere'))})
			ExcludeBogusCol = $parameterSets.where({$_.ContainsKey('Exclude') -and ($_.Exclude.Keys.Contains('ColNotHere'))})
		}

		context 'when a user match cannot be found' {

			mock 'FindUserMatch'
		
			context 'when all CSV ID fields are null in the CSV' {

				mock 'Get-CompanyCsvUser' {
					[pscustomobject]@{ 
						AD_LOGON = $null
						PERSON_NUM = $null
					}
				}
			
				it 'should write a warning: <TestName>' -TestCases $testCases.All {
					param($CsvFilePath,$ReportOnly,$Exclude)
				
					& $commandName @PSBoundParameters

					$assMParams = @{
						CommandName = 'Write-Warning'
						Times = 1
						Exactly = $true
						Scope = 'It'
						ParameterFilter = { 
							$Message -eq 'No CSV user identifier could be found' 
						}
					}
					Assert-MockCalled @assMParams
				}

				it 'should write the expected contents to the log file: <TestName>' -TestCases $testCases.All {
					param($CsvFilePath,$ReportOnly,$Exclude)
				
					& $commandName @PSBoundParameters

					$assMParams = @{
						CommandName = 'WriteLog'
						Times = 1
						Exactly = $true
						Scope = 'It'
						ParameterFilter = { 
							$PSBoundParameters.CSVIdentifierField -eq 'PERSON_NUM,AD_LOGON' -and
							$PSBoundParameters.CSVIdentifierValue -eq 'N/A' -and
							$PSBoundParameters.Attributes.CSVAttributeName -eq 'NoMatch' -and
							$PSBoundParameters.Attributes.CSVAttributeValue -eq 'NoMatch' -and
							$PSBoundParameters.Attributes.ADAttributeName -eq 'NoMatch' -and
							$PSBoundParameters.Attributes.ADAttributeValue -eq 'NoMatch'
						}
					}
					Assert-MockCalled @assMParams
				}
			}

			context 'when at least one CSV ID field is populated in the CSV' {

				mock 'Get-CompanyCsvUser' {
					[pscustomobject]@{ 
						AD_LOGON = $null
						PERSON_NUM = 999
					}
				}

				it 'should write the expected contents to the log file: <TestName>' -TestCases $testCases.All {
					param($CsvFilePath,$ReportOnly,$Exclude)
				
					& $commandName @PSBoundParameters

					$assMParams = @{
						CommandName = 'WriteLog'
						Times = 1
						Exactly = $true
						Scope = 'It'
						ParameterFilter = { 
							$PSBoundParameters.CSVIdentifierField -eq 'PERSON_NUM,AD_LOGON' -and
							$PSBoundParameters.CSVIdentifierValue -eq '999,' -and
							$PSBoundParameters.Attributes.CSVAttributeName -eq 'NoMatch' -and
							$PSBoundParameters.Attributes.CSVAttributeValue -eq 'NoMatch' -and
							$PSBoundParameters.Attributes.ADAttributeName -eq 'NoMatch' -and
							$PSBoundParameters.Attributes.ADAttributeValue -eq 'NoMatch'
						}
					}
					Assert-MockCalled @assMParams
				}
			
			}
		}

		context 'when a user match can be found' {

			$matchedAdUser = New-MockObject -Type 'System.DirectoryServices.AccountManagement.UserPrincipal'
			$amParams = @{
				MemberType = 'NoteProperty'
				Force = $true
			}
			$props = @{
				'Name' = 'nameval'
				'Enabled' = $true
				'SamAccountName' = 'samval'
				'GivenName' = 'givennameval'
				'Surname' = 'surnameval'
				'DisplayName' = 'displaynameval'
				'OtherProperty' = 'otherval'
				'EmployeeId' = 1
				'Title' = 'titleval'
			}
			$props.GetEnumerator() | ForEach-Object {
				$matchedAdUser | Add-Member @amParams -Name $_.Key -Value $_.Value
			}

			mock 'FindUserMatch' {
				[pscustomobject]@{
					MatchedAdUser = $matchedAdUser
					CsvIdMatchedOn = 'PERSON_NUM'
					AdIdMatchedOn = 'EmployeeId'
				}
			}
		
			context 'when no attribute mismatches can be found' {
				
				mock 'FindAttributeMismatch'

				it 'should write the expected contents to the log file: <TestName>' -TestCases $testCases.All {
					param($CsvFilePath,$ReportOnly,$Exclude)
				
					& $commandName @PSBoundParameters

					$assMParams = @{
						CommandName = 'WriteLog'
						Times = 1
						Exactly = $true
						Scope = 'It'
						ParameterFilter = { 
							$IdentifierValu3 -eq 'foo' -and
							$CSVIdentifierField -eq 'EmployeeId'
							$Attributes.CSVAttributeName -eq 'AlreadyInSync' -and
							$Attributes.CSVAttributeValue -eq 'AlreadyInSync' -and
							$Attributes.ADAttributeName -eq 'AlreadyInSync' -and
							$Attributes.ADAttributeValue -eq 'AlreadyInSync'
						}
					}
					Assert-MockCalled @assMParams
				}
			}

			context 'when an attribute mismatch is found' {

				mock 'FindAttributeMismatch' {
					@{
						CSVAttributeName = 'PERSON_NUM'
						CSVAttributeValue = '1'
						ADAttributeName = 'EmployeeId'
						ADAttributeValue = $null
					}
				}
			
				it 'when ReportOnly is used, should not attempt to sync the user: <TestName>' -TestCases $testCases.ReportOnly {
					param($CsvFilePath,$ReportOnly,$Exclude)
				
					& $commandName @PSBoundParameters

					$assMParams = @{
						CommandName = 'SyncCompanyUser'
						Times = 0
					}
					Assert-MockCalled @assMParams
				}

				it 'when ReportOnly is not used, should attempt to sync the user: <TestName>' -TestCases $testCases.Sync {
					param($CsvFilePath,$ReportOnly,$Exclude)
				
					& $commandName @PSBoundParameters

					$assMParams = @{
						CommandName = 'SyncCompanyUser'
						Times = 1
					}
					Assert-MockCalled @assMParams
				}
			
			}
		}

		context 'when a column is attempted to be excluded does not exist' {

			mock 'TestCsvHeaderExists' {
				$false
			}

			it 'should throw an exception: <TestName>' -TestCases $testCases.ExcludeBogusCol {
				param($CsvFilePath,$ReportOnly,$Exclude)
			
				$params = @{} + $PSBoundParameters
				{ & $commandName @params } | should throw 'One or more CSV headers excluded with -Exclude do not exist in the CSV file'
			}
		
		}

		context 'when an exception is thrown' {

			mock 'Get-CompanyAdUser' {
				throw 'error!'
			}

			it 'should return a non-terminating error: <TestName>' -TestCases $testCases.All {
				param($CsvFilePath,$ReportOnly,$Exclude)
			
				try { $null = & $commandName @PSBoundParameters -ErrorAction SilentlyContinue -ErrorVariable err } catch { $null }
				$err | should not benullorempty
			}

		}

		it 'should return nothing: <TestName>' -TestCases $testCases.All {
			param($CsvFilePath,$ReportOnly,$Exclude)
		
			& $commandName @PSBoundParameters | should benullorempty
		}
	}

	Remove-Variable -Name allAdsiUsers -Scope Script
	Remove-Variable -Name allCsvUsers -Scope Script
}
