'
' Common module
'
' Author: Jardel Weyrich <jardel@teltecsolutions.com.br>
'

Option Explicit

Function IIf(ByVal boolClause, ByRef trueValue, ByRef falseValue)
    If CBool(boolClause) Then
        IIf = trueValue
    Else 
        IIf = falseValue
    End If
End Function
