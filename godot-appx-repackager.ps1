# godot-appx-repackager: Powershell script to correctly repackage broken APPX files generated by Godot 3.5.
# · Developed by Pablo Navarro, from RAWRLAB Games. 2023
# · License: MIT. But feel free to do as you please with this!
# · Usage: .\godot-appx-repackager.ps1 game.appx
# · Tips: 
#  - X64 only!
#  - UWP export fields must be 4 characters long at least.
#  - publisherName must match with the one provided in the Godot UWP export field (CN=RAWRLAB).
#  - A self-signed PFX certificate will be generated if you don't provide one.
#  - Avoid spaces and special characters in any paths, just in case.
# ----------------------------------

# Configuration
$certFilePFX = ""
$certPass = "amazingPassword"
$publisherName = "RAWRLAB"
$mainFolder = $env:TEMP + "\appx-repack"
$appxFileName = ""

# ---------------------------- 
# Other variables
$buildToolsURL = "https://globalcdn.nuget.org/packages/microsoft.windows.sdk.buildtools.10.0.22621.756.nupkg"
$angleURL = "https://globalcdn.nuget.org/packages/angle.windowsstore.2.1.13.nupkg"

$gameExtractionFolder = $mainFolder + "\game"
$toolsExtractionFolder = $mainFolder + "\tools"

$toolsFolder = $toolsExtractionFolder + "\bin\10.0.22621.0\x64"
$makeappxPath = $toolsFolder + "\makeappx.exe"
$makecertPath = $toolsFolder + "\makecert.exe"
$pvk2pfxPath = $toolsFolder + "\pvk2pfx.exe"
$signtoolPath = $toolsFolder + "\signtool.exe"

$angleFolder = $toolsExtractionFolder + "\bin\UAP\x64"
$libEGLPath = $angleFolder + "\libEGL.dll"
$libGLESPath = $angleFolder + "\libGLESv2.dll"

# ------------------------

# If a certificate isn't configured, just generate one
if(!$certFilePFX) {
	$certFilePFX = $mainFolder + "\MyKey.pfx"
}

# Check if the script was called with something as $args[0], luckily an APPX path
if (!$appxFileName) {
	if ($args.Count -eq 1) {
		$appxFileName = $args[0]
	} else {
		Write-Output "Please provide an APPX as a command-line argument."
		return
	}
}

# Check if APPX file exists
if (!(Test-Path -Path $appxFileName)) {
	Write-Output "Provided APPX file does not exist."
	return	
}

# Create directories if they don't exit
New-Item -ItemType Directory -Path $toolsExtractionFolder -Force | Out-Null
New-Item -ItemType Directory -Path $gameExtractionFolder -Force | Out-Null

# If libEGL.dll does not exist, download Angle DLLs
if (!(Test-Path -Path $libEGLPath)) {
    $tempZipFile = $env:TEMP + "\temp.zip"
    Invoke-WebRequest -Uri $angleURL -OutFile $tempZipFile
    Expand-Archive -Path $tempZipFile -DestinationPath $toolsExtractionFolder -Force
    Remove-Item $tempZipFile
}

if (!(Test-Path -Path $libEGLPath)) {
	Write-Output "Could not download or extract the Angle DLLs."
	return
}

# If makeappx.exe does not exist, download Windows build tools
if (!(Test-Path -Path $makeappxPath)) {
    $tempZipFile = $env:TEMP + "\temp.zip"
    Invoke-WebRequest -Uri $buildToolsURL -OutFile $tempZipFile
    Expand-Archive -Path $tempZipFile -DestinationPath $toolsExtractionFolder -Force
    Remove-Item $tempZipFile
}

if (!(Test-Path -Path $makeappxPath)) {
	Write-Output "Could not download or extract the Windows build tools."
	return
}

# If cert file does not exist, generate one
if (!(Test-Path -Path $certFilePFX)) {
	$securePassword = ConvertTo-SecureString -String $certPass -AsPlainText -Force
	$newCert = New-SelfSignedCertificate -CertStoreLocation Cert:\CurrentUser\My -Subject ('CN=' + $publisherName) -HashAlgorithm 'SHA256' -TextExtension @( "2.5.29.37={text}1.3.6.1.5.5.7.3.3,1.3.6.1.4.1.311.84.3.1", "2.5.29.19={text}false")
	Export-PfxCertificate -FilePath $certFilePFX -Password $securePassword -Cert $newCert
}

if (!(Test-Path -Path $certFilePFX)) {
	Write-Output "Error: Could not generate a test certificate."
	return
}

# Extract broken APPX file and delete it
Rename-Item -Path $appxFileName -NewName ($appxFileName + ".zip") -Force
Expand-Archive -Path ($appxFileName + ".zip") -DestinationPath $gameExtractionFolder -Force

# Copy the Angle DLLs
Copy-Item -Path $libEGLPath -Destination $gameExtractionFolder -Force
Copy-Item -Path $libGLESPath -Destination $gameExtractionFolder -Force

# Repackage it with makeappx
& $makeappxPath pack /d $gameExtractionFolder /p $appxFileName

if (!(Test-Path -Path $appxFileName)) {
	Rename-Item -Path ($appxFileName + ".zip") -NewName $appxFileName -Force
	Write-Output "Error: Could not repackage the APPX file."
	return
}

# Delete the extracted game folder and the old APPX
Remove-Item -Path ($appxFileName + ".zip") -Force
Remove-Item -Recurse -Path $gameExtractionFolder -Force

# Sign it with signtool
& $signtoolPath sign /fd SHA256 /a /f $certFilePFX /p $certPass $appxFileName

if (!$?) {
	Write-Output "Error: Could not sign the APPX file."
	return	
} else {
	Write-Output "Process completed succesfully!"
	return		
}