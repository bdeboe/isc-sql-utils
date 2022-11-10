Class bdb.test.LogTest Extends (%Persistent, bdb.logme.Trigger)
{

Property Prop1 As %String;

Property Prop2 As %Date;

Storage Default
{
<Data name="LogTestDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Prop1</Value>
</Value>
<Value name="3">
<Value>Prop2</Value>
</Value>
</Data>
<DataLocation>^bdb.test.LogTestD</DataLocation>
<DefaultData>LogTestDefaultData</DefaultData>
<IdLocation>^bdb.test.LogTestD</IdLocation>
<IndexLocation>^bdb.test.LogTestI</IndexLocation>
<StreamLocation>^bdb.test.LogTestS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
