Class bdb.test.sql.InferTest Extends %UnitTest.TestCase
{

// zr  d ##class(%UnitTest.Manager).DebugRunTestCase(":bdb.test.sql.InferTest",,"/debug")

Method TestLocalSanity()
{
    set sc = $$$OK
    try {
        set stmt = ##class(%SQL.Statement).%New()
        if $system.SQL.Schema.TableExists("t") {
            do ##class(%SQL.Statement).%ExecDirect(,"DROP TABLE t")
        }

        for file = "TPCH\data\1\customer.tbl", "TPCH\data\1\orders.tbl", "NYTaxi\data\taxi_zones.csv", "NYTaxi\data\yellow_tripdata_2020-04.csv", "JOB\data\100\aka_name.csv", "JOB\data\100\cast_info.csv", "JOB\data\100\movie_info.csv" {
            set path = "C:\Users\bdeboe\GitHub\bdeboe\DASH\"_file
            continue:'$$$AssertStatusOK(##class(bdb.sql.InferSchema).ScanFile(.info, path, { "from": { "file": { "escapechar": "\\" }}}), "Test ScanFile() on '"_file_"'")

            set cols = ##class(bdb.sql.InferSchema).InferColumnList(path, info.qualifiers),
                ddl = "CREATE TABLE t ("_cols_")"
            continue:'$$$AssertStatusOK(stmt.%Prepare(ddl), "Testing DDL: "_ddl)
            set rs = stmt.%Execute()
            do $$$AssertEquals(rs.%Message,"","Checking output of CREATE TABLE: "_rs.%Message)

            set load = "LOAD DATA FROM FILE '"_path_"' INTO t USING "_info.qualifiers.%ToJSON()
            if $$$AssertStatusOK(stmt.%Prepare(load), "Testing LOAD DATA: "_load) {
                set rs = stmt.%Execute()
                do $$$AssertEquals(rs.%Message,"","Checking output of LOAD DATA: "_rs.%Message)
                do $$$AssertTrue(rs.%ROWCOUNT>0,"Loaded "_rs.%ROWCOUNT_" rows")
            }

            do ##class(%SQL.Statement).%ExecDirect(,"DROP TABLE t")
        }
        
    } catch (ex) {
        set sc = ex.AsStatus()
		do ..Manager.LogAssert(0,"Unexpected exception",$system.Status.GetErrorText(sc))
    }
    if $system.SQL.Schema.TableExists("t") {
        do ##class(%SQL.Statement).%ExecDirect(,"DROP TABLE t")
    }
    quit sc
}

}
