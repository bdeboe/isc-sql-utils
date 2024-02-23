/// Helper class for <class>bdb.logme.Log</class>
Class bdb.logme.LogField Extends %SerialObject
{

Property OldValue As %String(MAXLEN = 300);

Property NewValue As %String(MAXLEN = 300);

Method %OnNew(old As %String, new As %String) As %Status [ Internal, ServerOnly = 1 ]
{
    set i%OldValue = old
    set:$d(new) i%NewValue = new
    quit $$$OK
}

Storage Default
{
<Data name="LogFieldState">
<Value name="1">
<Value>OldValue</Value>
</Value>
<Value name="2">
<Value>NewValue</Value>
</Value>
</Data>
<State>LogFieldState</State>
<StreamLocation>^bdb.logme.LogFieldS</StreamLocation>
<Type>%Storage.Serial</Type>
}

}
