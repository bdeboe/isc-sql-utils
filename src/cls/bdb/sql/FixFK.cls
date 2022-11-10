/// Experimental.
/// This class helps fixing up an FK column after importing into a new table with an
/// auto-generated IDKEY
Class bdb.sql.FixFK Extends %Persistent [ Final ]
{

ClassMethod Load(tab, oldID) As %Status
{
    set sc = $$$OK
    try {
        set SQL = "INSERT %NOLOCK %NOCHECK %NOJOURN INTO bdb_sql.fixfk (tab, newID, oldID) /*#OPTIONS { ""PARALLEL_DML"": 1 } */ SELECT '"_tab_"' AS tab, %ID AS newID, "_oldID_" AS oldID FROM %PARALLEL "_tab
        set statement = ##class(%SQL.Statement).%New()
        set sc = statement.%Prepare(SQL)
        quit:$$$ISERR(sc)

        set rs = statement.%Execute()
        if (rs.%SQLCODE < 0) {
            set sc = $$$ERROR($$$GeneralError,"SQL Error: "_rs.%Message)
            quit
        }

    } catch (ex) {
        set sc = ex.AsStatus()
    }
    quit sc
}

ClassMethod Map(tab, Output done) As %Status
{
    set sc = $$$OK
    try {
        quit:'$SYSTEM.SQL.Schema.TableExists(tab, .metadata)
        set classname = $lg(metadata,3)

        // props of this type
        set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT parent->SqlSchemaName || '.' || parent->SqlTableName AS tab, parent AS cls, Name as prop, SqlFieldName AS col FROM %Dictionary.CompiledProperty WHERE Type = ?", classname)

        set stmt = ##class(%SQL.Statement).%New()
        while rs.%Next() {
            set refTab = rs.%Get("tab"), 
                refCls = rs.%Get("cls"),
                refCol = rs.%Get("col"),
                refProp = rs.%Get("prop")

            // check if we created a separate field b/o a type change
            if ##class(%Dictionary.CompiledProperty).%ExistsId(refCls_"||"_refProp_"FKOLD") {
                set refColSrc = refProp_"FKOLD"
            } else {
                set refColSrc = refCol
            }
            set sc = stmt.%Prepare("UPDATE %NOCHECK %NOLOCK %NOJOURN "_refTab_" t /*#OPTIONS { ""DML_PARALLEL"": 1 } */ SET "_refCol_" = (SELECT newID FROM bdb_sql.FixFK WHERE tab = '"_tab_"' AND oldID = t."_refColSrc_")")
            quit:$$$ISERR(sc)
            set rss = stmt.%Execute()
            if (rss.%SQLCODE < 0) {
                set sc = $$$ERROR($$$GeneralError,"SQL Error: "_rss.%Message)
                quit
            }
            set done(refTab, refCol) = "Field"
        }

        // FKs 
        set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT parent->SqlSchemaName || '.' || parent->SqlTableName AS tab, parent AS cls, Properties AS col FROM %Dictionary.CompiledForeignKey WHERE referencedClass = ?", classname)
        while rs.%Next() {
            set refTab = rs.%Get("tab"), 
                refProp = rs.%Get("col"), 
                refCls = rs.%Get("cls")
            set refCol = ##class(%Dictionary.CompiledProperty).%OpenId(refCls_"||"_refProp).SqlFieldName
            
            // check if we created a separate field b/o a type change
            if ##class(%Dictionary.CompiledProperty).%ExistsId(refCls_"||"_refProp_"FKOLD") {
                set refColSrc = refProp_"FKOLD"
            } else {
                set refColSrc = refCol
            }

            continue:$g(done(refTab, refCol))
            set sc = stmt.%Prepare("UPDATE %NOCHECK %NOLOCK %NOJOURN "_refTab_" t /*#OPTIONS { ""DML_PARALLEL"": 1 } */ SET "_refCol_" = (SELECT newID FROM bdb_sql.FixFK WHERE tab = '"_tab_"' AND oldID = t."_refColSrc_")")
            quit:$$$ISERR(sc)
            set rss = sc.%Execute()
            if (rss.%SQLCODE < 0) {
                set sc = $$$ERROR($$$GeneralError,"SQL Error: "_rss.%Message)
                quit
            }
            set done(refTab, refCol) = "FK"
        }

    } catch (ex) {
        set sc = ex.AsStatus()
    }
    quit sc
}

ClassMethod Drop(tab) As %Status
{
    set sc = $$$OK
    try {
        
        //set rs = ##class(%SQL.Statement).%ExecDirect(,"DELETE %NOCHECK %NOJOURN %NOLOCK FROM bdb_sql.FixFK /*#OPTIONS { ""DML_PARALLEL"": 1 } */ WHERE tab = ?",tab)
        /*
        if (rs.%SQLCODE < 0) {
            set sc = $$$ERROR($$$GeneralError,"SQL Error: "_rs.%Message)
            quit
        }
        */
        kill ^bdb.sql.FixFK(tab)

    } catch (ex) {
        set sc = ex.AsStatus()
    }
    quit sc
}

Property tab As %String(COLLATION = "EXACT", MAXLEN = 100) [ Required ];

Property oldID As %String(COLLATION = "EXACT") [ Required ];

Property newID As %Integer [ Required ];

Index IDKEY On (tab, oldID) [ IdKey, PrimaryKey, Unique ];

Storage Default
{
<Data name="FixFKDefaultData">
<Value name="1">
<Value>newID</Value>
</Value>
</Data>
<DataLocation>^bdb.sql.FixFK</DataLocation>
<DefaultData>FixFKDefaultData</DefaultData>
<IdLocation>^bdb.sql.FixFK</IdLocation>
<IndexLocation>^bdb.sql.FixFKI</IndexLocation>
<StreamLocation>^bdb.sql.FixFKS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
