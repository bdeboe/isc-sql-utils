/// Utilities for playing with / projecting collection properties. 
/// Methods to try:
/// <ol>
/// <li><method>BuildProjection</method></li>
/// <li><method>CreateMappedTable</method></li>
/// </ol>
Class bdb.sql.CollectionUtils
{

/// Builds a read-only table definition projecting the elements of list property
/// <var>property</var> in class <var>class</var>.
/// Note that this would get obsolete in IRIS 2022.1 once "list of" properties also support
/// <a href="https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GOBJ_propcoll#GOBJ_propcoll_sqlproj">SQLPROJECTION=table</a>
ClassMethod BuildProjection(class As %String, property As %String, overwrite As %Boolean = 1, verbose As %Boolean = 1) As %Status
{
	set sc = $$$OK
	try {
		set projectionClassName = class_property
		if $$$defClassDefined(projectionClassName) {
			if 'overwrite {
				set sc = $$$ERROR($$$GeneralError, "Class '"_projectionClassName_"' already exists")
				quit
			}
			set sc = $system.OBJ.Delete(projectionClassName, "-d")
			quit:$$$ISERR(sc)
		}
		
		set parentProp = ##class(%Dictionary.CompiledProperty).%OpenId(class_"||"_property,, .sc)
		quit:$$$ISERR(sc)
		
		// assuming default %Storage.Persistent storage named "Default"
		set parentStorage = ##class(%Dictionary.CompiledStorage).%OpenId(class_"||Default",, .sc)
		quit:$$$ISERR(sc)
		set global = parentStorage.DataLocation
		
		// derive position within parent storage, assume there's only one right now
		set positionInParent = 0
		#dim valueDef as %Dictionary.CompiledStorageDataValue
		for i = 1:1:parentStorage.Data.GetAt(1).Values.Count() {
			set valueDef = parentStorage.Data.GetAt(1).Values.GetAt(i)
			if valueDef.Value = property {
				set positionInParent = valueDef.Name
				quit
			}
		}
		if 'positionInParent {
			set sc = $$$ERROR($$$GeneralError, "Could not find storage location for property '"_property_"' in class '"_class_"'")
			quit
		}
		
		set projectionClass = ##class(%Dictionary.ClassDefinition).%New()
		set projectionClass.Name = projectionClassName
		set projectionClass.Super = "%Persistent"
		set projectionClass.ProcedureBlock = 1
		set projectionClass.Final = 1
		set projectionClass.StorageStrategy = "SQL"
		
		set param = ##class(%Dictionary.ParameterDefinition).%New()
		do projectionClass.Parameters.Insert(param)
		set param.Name = "READONLY"
		set param.Default = 1
		
		set propP = ##class(%Dictionary.PropertyDefinition).%New()
		do projectionClass.Properties.Insert(propP)
		set propP.Name = $piece(class,".",*)
		set propP.Type = class
		set propP.Description = "Reference to parent object"
		
		set propC = ##class(%Dictionary.PropertyDefinition).%New()
		do projectionClass.Properties.Insert(propC)
		set propC.Name = property
		set propC.Type = parentProp.Type
		set propC.Description = "Reference to child object (in collection property)"
		
		set propL = ##class(%Dictionary.PropertyDefinition).%New()
		do projectionClass.Properties.Insert(propL)
		set propL.Name = "ListIndex"
		set propL.Type = $s($$$LOWER(parentProp.Collection)="list":"%Integer", 1:"%String")
		set propL.Description = "Key within collection"
		
		set key = ##class(%Dictionary.IndexDefinition).%New()
		do projectionClass.Indices.Insert(key)
		set key.Name = "IDKey"
		set key.Properties = propP.Name_",ListIndex"
		set key.Unique = 1
		set key.IdKey = 1
		
		set storage = ##class(%Dictionary.StorageDefinition).%New()
		do projectionClass.Storages.Insert(storage)
		set storage.Name = "SQL"
		set storage.Type = "%Storage.SQL"
		
		set map = ##class(%Dictionary.StorageSQLMapDefinition).%New()
		do storage.SQLMaps.Insert(map)
		set map.Name = "MainMap"
		set map.Global = global
		set map.RowReference = "$lg($lg($lg("_global_"({L1}),"_positionInParent_"),{L2}))"
		set map.Type = "data"
		
		set data = ##class(%Dictionary.StorageSQLMapDataDefinition).%New()
		do map.Data.Insert(data)
		set data.Name = propC.Name
		
		/* 
		// not sure why, but this RowIdSpec seems to break SELECT * with no WHERE clause
		// it doesn't seem to harm to just leave it out either
		set rowidspec = ##class(%Dictionary.StorageSQLMapRowIdSpecDefinition).%New()
		do map.RowIdSpecs.Insert(rowidspec)
		set rowidspec.Name = 1
		set rowidspec.Field = propP.Name
		
		set rowidspec = ##class(%Dictionary.StorageSQLMapRowIdSpecDefinition).%New()
		do map.RowIdSpecs.Insert(rowidspec)
		set rowidspec.Name = 2
		set rowidspec.Field = propL.Name
		*/
		
		set subscript = ##class(%Dictionary.StorageSQLMapSubDefinition).%New()
		do map.Subscripts.Insert(subscript)
		set subscript.Name = 1
		set subscript.Expression = "{"_propP.Name_"}"
		
		set subscript = ##class(%Dictionary.StorageSQLMapSubDefinition).%New()
		do map.Subscripts.Insert(subscript)
		set subscript.Name = 2
		set subscript.Expression = "{"_propL.Name_"}"
		set subscript.AccessType = "Other"
		set subscript.NextCode = " s {L2}=$i({L2})"_$c(13,10)_" if {L2}>$ll($lg("_global_"({L1}),"_positionInParent_")) s {L2}="""" QUIT "_$c(13,10)
		
		set sc = projectionClass.%Save()
		quit:$$$ISERR(sc)
		
		set sc = $system.OBJ.Compile(projectionClass.Name, "c-d"_$s(verbose:"d", 1:"-d"))
		write:verbose !
		
	} catch (ex) {
		set sc = ex.AsStatus()
	}
	if $$$ISERR(sc) && verbose {
		do $system.OBJ.DisplayError(sc)
		write !
	}
	quit sc
}

}
