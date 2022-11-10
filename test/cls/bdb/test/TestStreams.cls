Class bdb.test.TestStreams Extends %Persistent
{

Parameter USEEXTENTSET = 0;

Property SemiOldCharStream As bdb.test.SemiOldCharStream;

Property OldCharStream As bdb.test.OldCharStream;

Property VeryOldCharStream As %Library.GlobalCharacterStream;

ClassMethod LoadRows(n = 100) As %Status
{
    set sc = $$$OK
    try {
        set stream = ..AStreamOfNoise(2000)
        for i = 1:1:n {
            set row = ..%New()
            do row.SemiOldCharStream.Write("This is the SemiOldCharStream")
            do row.SemiOldCharStream.CopyFrom(stream)
            do row.OldCharStream.Write("This is the OldCharStream")
            do row.OldCharStream.CopyFrom(stream)
            do row.VeryOldCharStream.Write("This is the VeryOldCharStream")
            do row.VeryOldCharStream.CopyFrom(stream)
            set sc = row.%Save()
            quit:$$$ISERR(sc)
        }
    } catch (ex) {
        set sc = ex.AsStatus()
    }
    quit sc
}

ClassMethod LoadGlobal(n = 100) As %Status
{
    set sc = $$$OK
    try {

    } catch (ex) {
        set sc = ex.AsStatus()
    }
    quit sc
}

ClassMethod Reset() As %Status
{
    do ..%KillExtent()
    kill ^CacheStream, ^bdb.test.TestStreamsS, ^bdb.test.MoreStreamsS
    quit $$$OK
}

ClassMethod AStreamOfNoise(length As %Integer = 1000, seed As %Integer = 123) As %Stream.Object
{
    set stream = ##class(%Stream.TmpCharacter).%New(), l = 0, sl = $l(seed)
    while (l<length) {
        do stream.WriteLine("This is a stream of utter noise. And hey, it's seeded with "_seed_"!")
        set l = l+61+sl
    }
    quit stream
}

Storage Default
{
<Data name="TestStreamsDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>OldCharStream</Value>
</Value>
<Value name="3">
<Value>VeryOldCharStream</Value>
</Value>
<Value name="4">
<Value>SemiOldCharStream</Value>
</Value>
</Data>
<DataLocation>^bdb.test.TestStreamsD</DataLocation>
<DefaultData>TestStreamsDefaultData</DefaultData>
<IdLocation>^bdb.test.TestStreamsD</IdLocation>
<IndexLocation>^bdb.test.TestStreamsI</IndexLocation>
<StreamLocation>^bdb.test.TestStreamsS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
