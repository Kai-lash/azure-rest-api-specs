[CmdletBinding()]
param (
)
Set-StrictMode -Version 3

. $PSScriptRoot/ChangedFiles-Functions.ps1
. $PSScriptRoot/Logging-Functions.ps1

$repoPath = Resolve-Path "$PSScriptRoot/../.."
$pathsWithErrors = @()

$filesToCheck = @(Get-ChangedSwaggerFiles).Where({
  ($_ -notmatch "/(examples|scenarios|restler|common|common-types)/") -and
  ($_ -match "specification/(?<relSpecPath>[^/]+/(data-plane|resource-manager).*?/(preview|stable)/([^/]+))/[^/]+\.json$")
})

if (!$filesToCheck) {
  LogInfo "No OpenAPI files found to check"
}
else {
  # Example: specification/foo/resource-manager/Microsoft.Foo/stable/2023-01-01/Foo.json
  # - Forward slashes on both Linux and Windows
  foreach ($file in $filesToCheck) {
    LogInfo "Checking $file"

    $jsonContent = Get-Content (Join-Path $repoPath $file) | ConvertFrom-Json -AsHashtable

    if ($null -ne ${jsonContent}?["info"]?["x-typespec-generated"]) {
      LogInfo "  OpenAPI was generated from TypeSpec (contains '/info/x-typespec-generated')"

      # ToDo: Verify spec folder includes *.tsp and tspconfig.yaml, to prevent spec authors committing
      # openapi generated from TypeSpec, without also including the TypeSpec sources.

      # Skip further checks, since spec is already using TypeSpec
      continue
    }
    else {
      LogInfo "  OpenAPI was not generated from TypeSpec (missing '/info/x-typespec-generated')"
    }

    # Example: specification/foo/resource-manager/Microsoft.Foo
    $pathToServiceName = ($file -split '/')[0..3] -join '/'

    # ToDo: Fetch main and query local git repo to prevent issues with rate limiting
    $urlToStableFolder = "https://github.com/Azure/azure-rest-api-specs/tree/main/$pathToServiceName/stable"

    try {
      $response = Invoke-WebRequest -Uri $urlToStableFolder -Method Head -SkipHttpErrorCheck
      if ($response.StatusCode -eq 200) {
        LogInfo "  Branch 'main' contains path '$pathToServiceName/stable', so spec already exists and is not required to use TypeSpec"
      }
      elseif ($response.StatusCode -eq 404) {
        LogInfo "  Branch 'main' does not contain path '$pathToServiceName/stable', so spec is new and must use TypeSpec"
        $pathsWithErrors += $file
      }
      else {
        LogError "Unexpected response from ${urlToStableFolder}: ${response.StatusCode}"
        LogJobFailure
        exit 1
      }
    }
    catch {
      LogError "  Exception making web request to ${urlToStableFolder}: $_"
      LogJobFailure
      exit 1
    }
  }
}

if ($pathsWithErrors.Count -gt 0)
{
  # DevOps only adds the first 4 errors to the github checks list so lets always add the generic one first
  # and then as many of the individual ones as can be found afterwards
  LogError "New specs must use TypeSpec.  For more detailed docs see https://aka.ms/azsdk/typespec"
  LogJobFailure

  foreach ($path in $pathsWithErrors)
  {
    LogErrorForFile $path "OpenAPI was not generated from TypeSpec, and spec appears to be new"
  }
  exit 1
}

exit 0
