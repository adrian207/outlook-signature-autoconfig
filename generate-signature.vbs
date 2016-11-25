'
' Create an HTML file for each user found on the LDAP user base
' to be used as signature on their email clients.
'
' Author: Jardel Weyrich
' Date  : Jan 28 2016
'
' Example usage:
'
'     cscript generate-signature.vbs 2> errors.txt && notepad errors.txt
'

Option Explicit

'----------------------------------------------------------------------------------------

Sub Include(ByVal filePath)
	Const ForReading = 1
	Dim currentScriptPath: currentScriptPath = Wscript.ScriptFullName
	Dim fso: Set fso = CreateObject("Scripting.FileSystemObject")
	Dim currentScriptFile: Set currentScriptFile = fso.GetFile(currentScriptPath)
	Dim currentScriptDirectory: currentScriptDirectory = fso.GetParentFolderName(currentScriptFile)
	Set currentScriptFile = Nothing
	Dim file: Set file = fso.OpenTextFile(currentScriptDirectory & "\" & filePath & ".vbs", ForReading)
	Dim fileData: fileData = file.ReadAll
	file.Close
	Set file = Nothing
	Set fso = Nothing
	ExecuteGlobal fileData
End Sub

'----------------------------------------------------------------------------------------

Include "app_config"
Include "common"
Include "log"
Include "array"
Include "regex"
Include "string"
Include "filesystem"
Include "network"

'----------------------------------------------------------------------------------------

Function FormatPhoneNumber(ByVal input)
	' Example of input: 9(048)3031-3450
	' Example of return: [ "48", "3031-3450" ]
	
	If Not VarType(input) = vbString Then
		FormatPhoneNumber = vbEmpty
		Exit Function
	End If
	
	' To debug the RegEx you can use https://myregextester.com/
	Dim re
	Set re = new RegExp
	re.Global = True
	re.Pattern = "\d?\(0*(\d+?)\)(\d+-\d+)"
	
	Dim matches
	Set matches = re.Execute(input)
	'LogDebug("matches.Count=" & matches.Count & " matches(0)=" & matches(0))
	
	Dim result(2)

	If matches.Count > 0 Then
		Dim match
		Set match = matches(0)
		'LogDebug("match.SubMatches.Count=" & match.SubMatches.Count)
		If match.SubMatches.Count = 2 Then
			Dim ddd: ddd = match.SubMatches(0)
			Dim number: number = match.SubMatches(1)
			result(0) = ddd
			result(1) = number
			FormatPhoneNumber = result
			Exit Function
		End If
	End If
	
	result(0) = "INVALID_DDD_FORMAT"
	result(1) = "INVALID_PHONE_FORMAT"
	FormatPhoneNumber = result
End Function

'----------------------------------------------------------------------------------------

Function ConvertToString(ByRef value)
	Select Case VarType(value)
		' vbEmpty			0		Empty (uninitialized)
		Case vbEmpty				ConvertToString = ""
		' vbNull			1		Null (no valid data)
		Case vbNull					ConvertToString = ""
		' vbInteger			2		Integer
		Case vbInteger				ConvertToString = FormatNumber(value)
		' vbLong			3		Long integer
		Case vbLong					ConvertToString = FormatNumber(value)
		' vbSingle			4		Single-precision floating-point number
		Case vbSingle				ConvertToString = FormatNumber(value) ' Single precision
		' vbDouble			5		Double-precision floating-point number
		Case vbDouble				ConvertToString = FormatNumber(value) ' Double precision
		' vbCurrency		6		Currency
		Case vbCurrency				ConvertToString = FormatCurrency(value)
		' vbDate			7		Date
		Case vbDate					ConvertToString = FormatDateTime(value, vbGeneralDate)
		' vbString			8		String
		Case vbString				ConvertToString = value
		' vbObject			9		Automation object
		Case vbObject				ConvertToString = "<vbObject>"
		' vbError			10		Error
		Case vbError				ConvertToString = "<vbError>"
		' vbBoolean			11		Boolean
		Case vbBoolean				ConvertToString = "<vbBoolean>"
		' vbVariant			12		Variant (used only with arrays of Variants)
		Case vbVariant				ConvertToString = "<vbVariant>"
		' vbDataObject		13		A data-access object
		Case vbDataObject			ConvertToString = "<vbDataObject>"
		Case vbDecimal				ConvertToString = "<vbDecimal>"
		' vbByte			17		Byte
		Case vbByte					ConvertToString = "<vbByte>"
		' vbArray			8192	Array
		Case vbArray				ConvertToString = Join(value, ", ")
		Case vbArray Or vbVariant	ConvertToString = Join(value, ", ")
		Case Else 					ConvertToString = "<UnhandledVarType:" & VarType(value) & ">" 
	End Select
End Function

'----------------------------------------------------------------------------------------

' Return the relevant portion of the group name. Example: "assinaturas-SOMETHING" -> "SOMETHING"
Function ParseGroupName(ByVal groupDN)
	Dim result: result = RegexCaptureSingleLine(groupDN, "CN=assinaturas-(.+?),.+", 0)
	ParseGroupName = result
End Function

'----------------------------------------------------------------------------------------

Function ParseGroups(ByRef inMemberOfArray, ByRef outResultArray())
	' Find the groups named assinaturas-SOMETHING and store all SOMETHING's in `outResultArray`
	Dim memberOfArraySize: memberOfArraySize = UBound(inMemberOfArray)
	ReDim outResultArray(memberOfArraySize)
	Dim groupDN
	Dim countGroup: countGroup = 0
	For Each groupDN in inMemberOfArray
		Dim groupName: groupName = ParseGroupName(groupDN)
		If Not IsNull(groupName) Then ' Found a matching name
			outResultArray(countGroup) = groupName
			countGroup = countGroup + 1
		End If
	Next
	ParseGroups = countGroup
End Function

'----------------------------------------------------------------------------------------

Function DebugGroups(ByRef signatureGroupNames, ByVal signatureGroupNamesCount)
	Dim i
	For i = 0 to signatureGroupNamesCount - 1
		Dim AsignatureGroupName: AsignatureGroupName = signatureGroupNames(i)
		LogDebug(attrEmail & " -> signatureGroupName[" & i & "] = " & AsignatureGroupName)
	Next
End Function

'----------------------------------------------------------------------------------------

' This function creates one or more signature files (<targetDirectory>\<username>-<signatureGroup>.htm), for the provided user,
' where <signatureGroup> is anything after the "-" in "assinaturas-ANYTHING".
Function CreateSignatureFilesForLdapUser(ByVal targetDirectory, ByVal templateDirectory, ByRef objLdapUser)
	CreateFolderRecursive(targetDirectory)

	Dim attrEmail: attrEmail = ConvertToString(objLdapUser.Fields("mail"))
	
	' Retrieve user groups
	Dim memberOfArray: memberOfArray = objLdapUser.Fields("memberOf")
	If IsNull(memberOfArray) Then
		LogError("Warnings for user " & attrEmail & ":" & vbCrlf & "- memberOf is empty" & vbCrlf)
		Exit Function
	End If
	If Not IsArrayOf(memberOfArray, vbString) Then
		LogError("Warnings for user " & attrEmail & ":" & vbCrlf & "- memberOf is not an array" & vbCrlf)
		Exit Function
	End If
	
	' Find the groups named assinaturas-SOMETHING and store all SOMETHING's in `signatureGroupNames`
	Dim signatureGroupNames()
	Dim signatureGroupNamesCount: signatureGroupNamesCount = ParseGroups(memberOfArray, signatureGroupNames)
	If signatureGroupNamesCount = 0 Then
		LogError("Warnings for user " & attrEmail & ":" & vbCrlf & "- not a memberOf assinaturas-*" & vbCrlf)
		Exit Function
	End If
	
	'
	' Read user attributes
	'
	Dim nomeUsuario: nomeUsuario = ConvertToString(objLdapUser.Fields("sAMAccountName"))
	Dim attrNomeCompleto: attrNomeCompleto = ConvertToString(objLdapUser.Fields("displayName"))
	Dim attrCargo: attrCargo = ConvertToString(objLdapUser.Fields("title"))
	
	Dim attrEmpresa: attrEmpresa = ConvertToString(objLdapUser.Fields("company"))
	Dim hasValidAttrEmpresa: hasValidAttrEmpresa = Not IsNullOrEmptyStr(attrEmpresa)
	
	Dim rawAttrTelefone: rawAttrTelefone = ConvertToString(objLdapUser.Fields("homePhone"))
	Dim hasAttrTelefone: hasAttrTelefone = Not IsNullOrEmptyStr(rawAttrTelefone)
	Dim attrTelefone: attrTelefone = FormatPhoneNumber(rawAttrTelefone)
	
	Dim attrRamal: attrRamal = ConvertToString(objLdapUser.Fields("telephoneNumber"))

	Dim rawAttrCelular: rawAttrCelular = ConvertToString(objLdapUser.Fields("mobile"))
	Dim hasAttrCelular: hasAttrCelular = Not IsNullOrEmptyStr(rawAttrCelular)
	Dim attrCelular: attrCelular = FormatPhoneNumber(rawAttrCelular) ' Optional
	
	'
	' Validate missing required fields
	'
	Dim errorMessage: errorMessage = ""
	If IsNullOrEmptyStr(nomeUsuario)		Then errorMessage = errorMessage & "- sAMAccountName is missing" & vbCrlf
	If IsNullOrEmptyStr(attrNomeCompleto)	Then errorMessage = errorMessage & "- displayName is missing" & vbCrlf
	If IsNullOrEmptyStr(attrCargo)			Then errorMessage = errorMessage & "- title is missing" & vbCrlf
	If IsNullOrEmptyStr(attrEmpresa)		Then errorMessage = errorMessage & "- company is missing" & vbCrlf
	If IsNullOrEmptyStr(rawAttrTelefone)	Then errorMessage = errorMessage & "- homePhone is missing" & vbCrlf
	If IsNullOrEmptyStr(attrRamal)			Then errorMessage = errorMessage & "- telephoneNumber is missing" & vbCrlf
	
	'
	' Validate invalid formatted fields
	'
	
	' Only show warning about homePhone format if the user informed it.
	If hasAttrTelefone And (attrTelefone(0) = "INVALID_DDD_FORMAT" Or attrTelefone(1) = "INVALID_PHONE_FORMAT") Then
		errorMessage = errorMessage & "- homePhone expects format 9(0XX)XXXX-XXXX" & vbCrlf
	End If
	
	' Only show warning about mobile format if the user informed it.
	If hasAttrCelular And (attrCelular(0) = "INVALID_DDD_FORMAT" Or attrCelular(1) = "INVALID_PHONE_FORMAT") Then
		errorMessage = errorMessage & "- mobile expects format 9(0XX)XXXX-XXXX" & vbCrlf
	End If
	
	If Not IsNullOrEmptyStr(errorMessage) Then
		LogError("Warnings for user " & attrEmail & ":" & vbCrlf & errorMessage)
	End If
	
	' Write the signature files
	Const ForReading = 1
	
	' DebugGroups(signatureGroupNames, signatureGroupNamesCount)
		
	Dim i
	For i = 0 to signatureGroupNamesCount - 1
		Dim signatureGroupName: signatureGroupName = signatureGroupNames(i)
		Dim objFSO
		
		' Read the template file.
		Dim inputTemplateContent
		If Not IsNullOrEmptyStr(templateDirectory) Then
			' Default template
			Dim templateFilePath: templateFilePath = templateDirectory & "\" & "DEFAULT.htm.template"
			If Not IsNullOrEmptyStr(signatureGroupName) Then
				templateFilePath = templateDirectory & "\" & signatureGroupName & ".htm"
			End If
			
			If Not FileExists(templateFilePath) Then
				LogError("Warnings for user " & attrEmail & ": Template file does not exist - " & templateFilePath & vbCrlf)
				Exit Function
			End If
			
			Set objFSO = CreateObject("Scripting.FileSystemObject")
			
			Dim objFile
			Set objFile = objFSO.OpenTextFile(templateFilePath, ForReading)
			
			inputTemplateContent = objFile.ReadAll
			
			objFile.Close
			Set objFile = Nothing
			Set objFSO = Nothing
		End If
		
		' Create the signature file.
		Set objFSO = CreateObject("Scripting.FileSystemObject")
		Dim signatureFileDirectory: signatureFileDirectory = targetDirectory & "\" & nomeUsuario
		Dim signatureFilePath: signatureFilePath = signatureFileDirectory & "\" & signatureGroupName & ".htm"
		
		CreateFolderRecursive(signatureFileDirectory)
		
		Dim signatureFile
		Set signatureFile = objFSO.CreateTextFile(signatureFilePath, True)
		
		' Prepare the template
		Dim outputTemplateContent
		If Not IsNullOrEmptyStr(inputTemplateContent) Then
			outputTemplateContent = inputTemplateContent
		Else
			outputTemplateContent = "" _
				& "Atenciosamente," & vbCrlf _
				& vbCrlf _
				& "__ATTR_NOME_COLABORADOR__" & vbCrlf _
				& "__ATTR_CARGO__" & vbCrlf _
				& vbCrlf _
				& "__ATTR_NOME_EMPRESA__" & vbCrlf _
				& "Fone: __ATTR_TELEFONE__ | DDR: __ATTR_RAMAL__" _
					& IIf(IsNullOrEmptyStr(rawAttrCelular), "", " | Cel: __ATTR_CELULAR__") & vbCrlf _
				& vbCrlf _
				& "[__ATTR_IMAGEM_URL__](__ATTR_IMAGEM_LINK__)" & vbCrlf
		End If
		
		' Replace template placeholders.
		outputTemplateContent = Replace(outputTemplateContent, "__ATTR_NOME_COLABORADOR__", attrNomeCompleto)
		outputTemplateContent = Replace(outputTemplateContent, "__ATTR_CARGO__", attrCargo)
		outputTemplateContent = Replace(outputTemplateContent, "__ATTR_NOME_EMPRESA__", attrEmpresa)
		outputTemplateContent = Replace(outputTemplateContent, "__ATTR_TELEFONE_DDD__", attrTelefone(0))
		outputTemplateContent = Replace(outputTemplateContent, "__ATTR_TELEFONE__", attrTelefone(1))
		outputTemplateContent = Replace(outputTemplateContent, "__ATTR_RAMAL__", attrRamal)
		outputTemplateContent = Replace(outputTemplateContent, "__ATTR_MOSTRA_CELULAR__", IIf(hasAttrCelular, "Mostra", "Esconde"))
		outputTemplateContent = Replace(outputTemplateContent, "__ATTR_CELULAR_DDD__", attrCelular(0))
		outputTemplateContent = Replace(outputTemplateContent, "__ATTR_CELULAR__", attrCelular(1))
		outputTemplateContent = Replace(outputTemplateContent, "__ATTR_IMAGEM_LINK__", "<TODO:__ATTR_IMAGEM_LINK__>")
		outputTemplateContent = Replace(outputTemplateContent, "__ATTR_IMAGEM_URL__", "<TODO:__ATTR_IMAGEM_URL__>")
		
		' Write it.
		signatureFile.Write(outputTemplateContent)
		
		' Close it.
		signatureFile.Close
		Set signatureFile = Nothing
		Set objFSO = Nothing
	Next
End Function

'----------------------------------------------------------------------------------------

Function GetLdapUsers(ByVal ldapServer, ByVal ldapBaseDN, ByVal ldapFilter, ByVal ldapAttributes)
	'Dim rootDSE
	'Set rootDSE = GetObject("LDAP://RootDSE")
	'Dim domainContainer: domainContainer = rootDSE.Get("defaultNamingContext")
	'Set rootDSE = Nothing
	
	Dim adoConn
	Set adoConn = CreateObject("ADODB.Connection")
	adoConn.Provider = "ADSDSOObject"
	adoConn.Open "generate-signature"

	Dim adoCmd
	Set adoCmd = CreateObject("ADODB.Command")
	adoCmd.ActiveConnection = adoConn
	adoCmd.Properties("Page Size") = 100
	adoCmd.Properties("Cache Results") = True
	adoCmd.CommandText = "<LDAP://" & ldapServer & "/" & ldapBaseDN & ">;" & ldapFilter & ";" & ldapAttributes & ";subtree"
	'LogDebug(adoCmd.CommandText)
		
	Dim recordSet
	Set recordSet = adoCmd.Execute
	
	LogInfo("Users found: " & recordSet.RecordCount)
	'Do While Not recordSet.EOF
	'	LogDebug(recordSet.Fields("displayName"))
	'	recordSet.MoveNext
	'	Exit Do
	'Loop
	
	Set GetLdapUsers = recordSet
	
	Set adoCmd = Nothing
	'Set recordSet = Nothing
	Set adoConn = Nothing
End Function

'----------------------------------------------------------------------------------------

Sub Main()
	' Get current User/Domain
	Dim userName: userName = GetCurrentUsername()
	Dim domainName: domainName = GetCurrentDomainName()
	
	' Get AD/LDAP users
    Dim ldapServer: ldapServer = gConfigLdapServer
    Dim ldapBaseDN: ldapBaseDN = gConfigLdapBaseDN
    Dim ldapFilter: ldapFilter = gConfigLdapFilter
    Dim ldapAttributes: ldapAttributes = gConfigLdapAttributes
	
	Dim recordSet
	Set recordSet = GetLdapUsers(ldapServer, ldapBaseDN, ldapFilter, ldapAttributes)
	
	Do While Not recordSet.EOF
		CreateSignatureFilesForLdapUser gConfigSignaturesSourceLocation, gConfigTemplatesSourceLocation, recordSet
		recordSet.MoveNext
	Loop
	
	Set recordSet = Nothing
End Sub

'----------------------------------------------------------------------------------------

Main()