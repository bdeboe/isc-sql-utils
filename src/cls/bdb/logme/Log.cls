/// Simple log table populated by the <class>bdb.logme.Trigger</class> trigger.
/// This class uses a minimum set of indices to minimize ingestion overhead.
Class bdb.logme.Log Extends %Persistent [ Final ]
{

Parameter USEEXTENTSET = 1;

Parameter DEFAULTGLOBAL = "^bdb.logme";

Property TableName As %String(MAXLEN = 200);

Property Operation As %String(VALUELIST = ",INSERT,UPDATE,DELETE");

Property LogTime As %PosixTime [ InitialExpression = {##class(%PosixTime).CurrentTimeStamp()}, ReadOnly ];

Property UserName As %String(MAXLEN = 200) [ InitialExpression = {$username}, ReadOnly ];

Property ProcessID As %SmallInt [ InitialExpression = {$job}, ReadOnly ];

Property Changes As array Of LogField;

Index TableName On TableName [ Type = bitmap ];

Storage Default
{
<Data name="Changes">
<Attribute>Changes</Attribute>
<Structure>subnode</Structure>
<Subscript>"Changes"</Subscript>
</Data>
<Data name="LogDefaultData">
<Value name="1">
<Value>TableName</Value>
</Value>
<Value name="2">
<Value>Operation</Value>
</Value>
<Value name="3">
<Value>LogTime</Value>
</Value>
<Value name="4">
<Value>UserName</Value>
</Value>
<Value name="5">
<Value>ProcessID</Value>
</Value>
</Data>
<DataLocation>^bdb.logme.1</DataLocation>
<DefaultData>LogDefaultData</DefaultData>
<ExtentLocation>^bdb.logme</ExtentLocation>
<IdLocation>^bdb.logme.1</IdLocation>
<Index name="$Log">
<Location>^bdb.logme.2</Location>
</Index>
<Index name="IDKEY">
<Location>^bdb.logme.1</Location>
</Index>
<Index name="TableName">
<Location>^bdb.logme.3</Location>
</Index>
<IndexLocation>^bdb.logme.I</IndexLocation>
<StreamLocation>^bdb.logme.S</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
