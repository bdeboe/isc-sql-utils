Class bdb.test.sql.DumpTest Extends %UnitTest.TestCase
{

Method TestParty() As %Status
{
    quit ..DumpLoad("Party.Orders", {})
}

Method DumpLoad(table As %String, qualifiers As %DynamicObject) As %Status
{
    set sc = $$$OK
    try {
        set file = $SYSTEM.Util.DataDirectory()_"DumpTest.csv"

        // first dump the data
        do $$$AssertStatusOK(##class(bdb.sql.Dump).Dump(table, file, , qualifiers), "Dumping "_table_" to file "_file)

        // create second table to test load
        set rs = ##class(%SQL.Statement).%ExecDirect(,"CREATE TABLE "_table_"ZZZ AS SELECT * FROM "_table_" WHERE 1=0")
        do $$$AssertTrue(rs.%SQLCODE=0,"Creating second table for LOAD DATA test")

        // LOAD DATA
        set rs = ##class(%SQL.Statement).%ExecDirect(,"LOAD DATA FROM FILE '"_file_"' INTO "_table_"ZZZ USING "_qualifiers.%ToJSON())
        do $$$AssertTrue(rs.%SQLCODE=0,"LOAD DATA into second table - "_rs.%Message)

        // test number of records
        set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM "_table)
        set originalCount = $s(rs.%Next():rs.%GetData(1), 1:-1)
        set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM "_table_"ZZZ")
        set newCount = $s(rs.%Next():rs.%GetData(1), 1:-1)
        do $$$AssertEquals(originalCount,newCount,"Check if second table has same number of rows")

    } catch (ex) {
        set sc = ex.AsStatus()
		do ..Manager.LogAssert(0,"Unexpected exception",$system.Status.GetErrorText(sc))
    }
    if ##class(%File).Exists(file) {
        do $$$AssertStatusOK(##class(%File).Delete(file),"Deleting output file")
    }
    if $system.SQL.Schema.TableExists(table_"ZZZ",.md) {
        do $$$AssertStatusOK($system.OBJ.Delete($lg(md,3),"e-d"),"Dropping table "_table_"ZZZ")
    }
    quit sc
}

}
