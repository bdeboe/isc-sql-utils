Class SQL.StorageUtils
{

/// Takes a class definition of a class with USEEXTENTSET=0 (or undefined), sets/adds the 
/// USEEXTENTSET=1 class parameter and adapts the storage definition to match the class'
/// existing globals so that everything remains accessible and any *new* storage maps
/// (notably indices) are written in the USEEXTENTSET=1 way.
ClassMethod ConvertToUseExtents(className As %String, shortGlobalNames As %Boolean = 0, verbose As %Boolean = 1) As %Status
{
	set sc = $$$OK
	try {
		set class = ##class(%Dictionary.ClassDefinition).%OpenId(className,4,.sc)
		quit:'$isobject(class)
		set compiledClass = ##class(%Dictionary.CompiledClass).%OpenId(className,,.sc)
		quit:'$isobject(compiledClass)
		write:verbose !,"Opening class definition for '",className,"'"

		// check if the storage is defined in a parent class with USEEXTENTSET=0
		set whoDefinesMyStorage = ..WhoDefinesMyStorage(className),
			isSubclass = (whoDefinesMyStorage '= className)
		if isSubclass && '##class(%Dictionary.CompiledParameter).%OpenId(whoDefinesMyStorage_"||USEEXTENTSET").Default {
			set sc = $$$ERROR($$$GeneralError, "Parent class '"_whoDefinesMyStorage_"' has USEEXTENTSET=0 and is the one in need of conversion.")
			quit
		}

		// build mini test set
		write:verbose !!,"Building mini test set"
		set tableName = $tr($p(className,".",1,*-1),".","_")_"."_compiledClass.SqlTableName
		set result = ##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 50 %ID FROM "_tableName), c = 0
		while result.%Next() {
			set testObjects(result.%GetData(1))=$CLASSMETHOD(className,"%OpenId",result.%GetData(1)), c = c+1
		}
		write:verbose !,"Gathered ",c," test records"
		set result = ##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM "_tableName)
		set totalCount = $s(result.%Next():result.%GetData(1), 1:0)
		write:verbose " out of ",totalCount," rows in the table"
		for i = 1:1:compiledClass.Indices.Count() {
			set index = compiledClass.Indices.GetAt(i)

			// don't test nontrivial indices right now
			if ((index.Type'="key") && (index.Type'="index")) || (index.TypeClass'="") {
				write:verbose !,"   WARNING: can't test ",index.Type," index '",index.Name,"'"
				continue
			}

			// skip extent and IDKEY indices
			continue:index.Properties=""

			set testIndices(index.Name) = index.Properties
			
			set id = ""
			for {
				set id = $order(testObjects(id),1,obj)
				quit:id=""
				kill subs
				set subs = $l(index.Properties,","),
					null = 0
				for j = 1:1:subs {
					set prop = $zstrip($p(index.Properties,",",j),"<>W"), 
						val = obj
					for k = 1:1:$l(prop,".") {
						set val = $property(val, $p(prop,".",k))
						if (val="") {
							set null = 1
							quit
						}
					}
					quit:null
					set subs(j) = val
				}
				continue:null // ignore these rows for our test
				if '$classmethod(className, index.Name_"Exists", subs...) {
					set sc = $$$ERROR($$$GeneralError, "Issues checking test sample for index '"_index.Name_"' for %ID "_id)
					quit
				}
				merge testIndices(index.Name, id) = subs
			}
			quit:$$$ISERR(sc)
			if $d(testIndices(index.Name))<10 {
				write:verbose !,"   WARNING: no valid test data for index '",index.Name,"'"
			}
		}
		
		// USEEXTENTSET class parameter
		if 'isSubclass {
			set param = ##class(%Dictionary.ParameterDefinition).%OpenId(className_"||USEEXTENTSET")
			write:verbose !!,"Setting USEEXTENTSET class parameter to 1"
			if $isobject(param) {
				if param.Default=1 { // nothing to do!
					write:verbose !,"Class '",className,"' already had USEEXTENTSET=1"
					quit
				} 
				set param.Default = 1
			} else {
				set param = ##class(%Dictionary.ParameterDefinition).%New()
				set param.parent = class
				set param.Name = "USEEXTENTSET"
				set param.Default = 1
			}
		} else {
			write:verbose !,"This is a subclass, inheriting USEEXTENTSET from '",whoDefinesMyStorage,"'"
		}
		
		// Identify applicable storage definition and create a backup
		set storage = ##class(%Dictionary.StorageDefinition).%OpenId(className_"||"_$s(class.StorageStrategy="":"Default", 1:class.StorageStrategy),,.sc)
		quit:'$isobject(storage)
		write:verbose !!,"Creating backup of current storage definition '",storage.Name,"'"
		set backup = storage.%ConstructClone(0)
		set backup.parent = class
		set backup.Name = storage.Name_"Backup", i=""
		while ##class(%Dictionary.StorageDefinition).%ExistsId(className_"||"_backup.Name) { 
			set i = i+1, backup.Name = storage.Name_"Backup"_i
		}
		set backup.parent = class
		
		// use base name minus D suffix as ExtentLocation
		if shortGlobalNames {
			set storage.ExtentLocation = $$generateExtentGlobal^%occStorageUtil(className)
		} else {
			set storage.ExtentLocation = $s($e(storage.DataLocation,*)="D":$e(storage.DataLocation,1,*-1), 1:storage.DataLocation)
		}
		write:verbose !!,"New extent location: ",storage.ExtentLocation
		
		// now add explicit mappings per index from the *compiled* class
		set compiledStorage = ##class(%Dictionary.CompiledStorage).%OpenId(className_"||"_storage.Name,,.sc)
		quit:'$isobject(compiledStorage)
		set indexLocation = compiledStorage.IndexLocation
		if $e(indexLocation,*)=")" {
			set indexLocation = $e(indexLocation,1,*-1)_","
		} else {
			set indexLocation = indexLocation_"("
		}
		
		// first build a list of the ones with an existing explicit location
		write:verbose !!,"Building a list of existing index locations"
		for i = 1:1:compiledStorage.Indices.Count() {
			set compiledIndexStorage = compiledStorage.Indices.GetAt(i)
			set locations(compiledIndexStorage.Name) = compiledIndexStorage.Location
		}
		
		write:verbose !,"Creating new index storage definitions:"
		do storage.Indices.Clear()
		for i = 1:1:compiledClass.Indices.Count() {
			set index = compiledClass.Indices.GetAt(i)
			if index.SystemAssigned && ($e(index.Name,1,5)="IDKEY") {
				set indexStorage = ##class(%Dictionary.StorageIndexDefinition).%New()
				set indexStorage.parent = storage
				set indexStorage.Name = index.Name
				set indexStorage.Location = compiledStorage.DataLocation
				write:verbose !,"   - ",indexStorage.Name," (system assigned) > ", indexStorage.Location
			} else {
				set indexStorage = ##class(%Dictionary.StorageIndexDefinition).%New()
				set indexStorage.parent = storage
				set indexStorage.Name = index.Name
				set indexStorage.Location = $get(locations(index.Name), indexLocation_$$$QUOTE(index.Name)_")")
				write:verbose !,"   - ",indexStorage.Name," > ", indexStorage.Location
			}
		}
		
		write:verbose !!,"Saving updated storage definition"
		set sc = class.%Save()
		quit:$$$ISERR(sc)
		set sc = storage.%Save()
		quit:$$$ISERR(sc)
		set sc = $system.OBJ.Compile(className, "ckf"_$s(verbose:"d", 1:"-d"))
		quit:$$$ISERR(sc)
		
		// run mini test
		write:verbose !!,"Verifying total record count: "
		set result = ##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM "_tableName)
		set newCount = $s(result.%Next():result.%GetData(1), 1:0)
		write:verbose newCount
		if totalCount'=newCount {
			set sc = $$$ERROR($$$GeneralError, "New record count doesn't match. Check extent/bitmap index map")
			quit
		}
		write:verbose !,"Verifying test records are still accessible"
		set id = ""
		for {
			set id = $order(testObjects(id))
			quit:id=""
			if '$classmethod(className,"%ExistsId",id) {
				set sc = $$$ERROR($$$GeneralError, "Unable to retrieve row "_id_" using %ExistsId()")
				quit
			}
		}
		set index = ""
		for {
			set index = $order(testIndices(index),1,props)
			quit:index=""
				
			write:verbose !," - Verifying index '",index,"' on ",props
			set id = "", c = 0
			for {
				set id = $order(testIndices(index,id))
				quit:id=""
				kill subs
				merge subs = testIndices(index,id)
				if '$classmethod(className, index_"Exists", subs...) {
					set sc = $$$ERROR($$$GeneralError, "Unable to retrieve row "_id_" using '",index,"' lookup")
					quit
				}
				set c = c+1
			}
			write:verbose " - OK (",c," rows tested)"
		}

		// now check for subclasses
		write:verbose !!,"Now checking for subclasses to convert"
		set result = ##class(%SQL.Statement).%ExecDirect(,"SELECT Name FROM %Dictionary.CompiledClass WHERE ','||Super||',' LIKE '%,"_className_",%'"), c = 0
		while result.%Next() {
			set subclass = result.%GetData(1)
			set sc = ..ConvertToUseExtents(subclass, shortGlobalNames, verbose)
			quit:$$$ISERR(sc)
			set c = c+1
		}
		if 'c {
			write:verbose " - none"
		} else {
			write:verbose !!,"Converted ",c," subclasses for '",className,"'"
		}

	} catch (ex) {
		set sc = ex.AsStatus()
	}
	write:verbose !
	if verbose && $$$ISERR(sc) {
		do $system.OBJ.DisplayError(sc)
		write !
	}
	quit sc
}

/// Helper method for ConvertToUseExtentSet()
ClassMethod WhoDefinesMyStorage(className As %String) As %String [ Internal ]
{
	// we're looking for the parent class that defines this class' extent / storage
	set class = ##class(%Dictionary.CompiledClass).%OpenId(className)

	// look at primary superclass only
	set super = $s(class.Inheritance="left":$p(class.Super,",",1), 1:$p(class.Super,",",*))
	
	// if this superclass isn't a %Persistent class, no need to dig any further.
	// the current class must be the one defining the extent
	if '$classmethod(super, "%Extends", "%Library.Persistent") {
		quit className
	}
	
	// if this superclass has NoExtent, no need to dig any further.
	// the current class must be the one defining the extent
	set superclass = ##class(%Dictionary.CompiledClass).%OpenId(super)
	if superclass.NoExtent {
		quit className
	}

	// if neither of these conditions hold, we need to look up super
	quit ..WhoDefinesMyStorage(super)
}

/// Creates a table <var>targetTableName</var> in the current namespace that maps to the same
/// storage as <var>sourceTableName</var> in the <var>sourceNS</var> namespace. 
/// Note that renaming is only available when there are no superclasses or property classes
/// to move along.
ClassMethod CreateMappedTable(sourceNS As %String, sourceTableName As %String, targetTableName As %String = "", includePropTypes As %Boolean = 1, includeFKeys As %Boolean = 0, verbose As %Boolean = 1) As %Status [ SqlName = CreateMappedTable, SqlProc ]
{
	set sc = $$$OK, ns = $namespace
	try {
		set $namespace = sourceNS
		if '$SYSTEM.SQL.Schema.TableExists(sourceTableName, .metadata) {
			set sc = $$$ERROR($$$TableDoesNotExist, sourceTableName)
			quit
		}
		
		set classname = $lg(metadata,3)
		set originalClassDef = ##class(%Dictionary.ClassDefinition).%OpenId(classname,,.sc)
		quit:$$$ISERR(sc)
		
		set classes(classname) = originalClassDef.%ConstructClone(1)
		set ancestors = ..AddRelated(originalClassDef, .classes, includePropTypes, includeFKeys)
		quit:$$$ISERR(sc)
		
		if ancestors && (targetTableName'="") {
			set sc = $$$ERROR($$$GeneralError, "Cannot specify alternate table name if class has ancestors")
			quit
		}
		
		// retrieve actual database location for all globals
		set c = ""
		for {
			set c = $order(classes(c), 1, originalClassDef)
			quit:c=""
			
			for i = 1:1:originalClassDef.Storages.Count() {
				#dim storage as %Dictionary.StorageDefinition = originalClassDef.Storages.GetAt(i)
				
				// these are OK as-is
				continue:(storage.Type="%Storage.Serial")
				
				if (storage.Type="%Storage.Persistent") {
				
					for loc = "DataLocation", "ExtentLocation", "IndexLocation", "StreamLocation", "CounterLocation", "IdLocation", "VersionLocation" {
						set:$property(storage,loc)'="" classes(c,i,"loc",loc) = $$GetExtendedRef($property(storage, loc))
					}
					
					for j = 1:1:storage.Indices.Count() {
						#dim index as %Dictionary.StorageIndexDefinition = storage.Indices.GetAt(j)
						set classes(c,i,"idx",j) = $$GetExtendedRef(index.Location)
					}
					
				} elseif (storage.Type="%Storage.SQL") {
					
					for j = 1:1:storage.SQLMaps.Count() {
						#dim sqlMap as %Dictionary.StorageSQLMapDefinition = storage.SQLMaps.GetAt(j)
						set classes(c,i,"sql",j) = $$GetExtendedRef(sqlMap.Global)
						
						// scan for special NextCode?
						for k = 1:1:sqlMap.Subscripts.Count() {
							#dim sub as %Dictionary.StorageSQLMapSubDefinition = sqlMap.Subscripts.GetAt(k)
							
							for l = 1:1:sub.Invalidconditions.Count() {
								#dim invc as %Dictionary.StorageSQLMapSubInvalidconditionDefinition = sub.Invalidconditions.GetAt(l)
								
								continue:'..ScanCode(invc.Expression, .newCode, sourceNS)
								set classes(c,i,"sql",j,"sub",k,"invc",l) = newCode
							}
							
							continue:'..ScanCode(sub.NextCode, .newCode, sourceNS)
							set classes(c,i,"sql",j,"sub",k,"next") = newCode
						}
					}
					
				} else {
					set sc = $$$ERROR($$$GeneralError, "Unsupported storage type: "_storage.Type)
					quit
				}
				
				set classes(c,"type") = storage.Type
			}
			quit:$$$ISERR(sc)
		}
		quit:$$$ISERR(sc)
		
		
		// now create copies in the target namespace
		set $namespace = ns
		#dim newdef as %Dictionary.ClassDefinition
		set c = ""
		for {
			set c = $order(classes(c), 1, newdef)
			quit:c=""
			
			if (c=classname) && (targetTableName'="") {
				set pkg = $piece(targetTableName,".",1), cls = $piece(targetTableName,".",2)
				set:cls="" cls = pkg, pkg = "User"
				set:pkg="SQLUser" pkg = "User"
				set pkg = $translate(pkg,"_","."), cls = $translate(cls,"_ ")
				set newdef.Name = pkg_"."_cls
			}
			
			if ##class(%Dictionary.CompiledClass).%ExistsId(newdef.Name) {
				set sc = $$$ERROR($$$ClassNameExists, newdef.Name)
				quit
			}
			
			// some convenience
			set newdef.DdlAllowed = 1
			set param = ""
			for i = 1:1:newdef.Parameters.Count() {
				if newdef.Parameters.GetAt(i).Name = "READONLY" {
					set param = newdef.Parameters.GetAt(i)
					quit
				}
			}
			if (param="") {
				set param = ##class(%Dictionary.ParameterDefinition).%New()
				set param.parent = newdef
				set param.Name = "READONLY"
			}
			set param.Default = 1
			
			if 'includeFKeys {
				do newdef.ForeignKeys.Clear()
			}
			
			// now apply extended references
			set i = ""
			for {
				set i = $order(classes(c,i))
				quit:i=""
				
				set storage = newdef.Storages.GetAt(i)
				
				if classes(c,"type")="%Storage.Persistent" {
					
					set loc = ""
					for {
						set loc = $order(classes(c,i,"loc",loc),1,glo)
						quit:loc=""
						set $property(storage,loc) = glo
					}
					
					set j = ""
					for {
						set j = $order(classes(c,i,"idx",j),1,glo)
						quit:j=""
						set storage.Indices.GetAt(j).Location = glo
					}
					
				} else { // %Storage.SQL
					
					set j = ""
					for {
						set j = $order(classes(c,i,"sql",j),1,glo)
						quit:j=""
						set storage.SQLMaps.GetAt(j).Global = glo
						
						set k = ""
						for {
							set k = $order(classes(c,i,"sql",j,"sub",k))
							quit:k=""
							
							if $d(classes(c,i,"sql",j,"sub",k,"next"),code) {
								set storage.SQLMaps.GetAt(j).Subscripts.GetAt(k).NextCode = code
							}
							
							set l = ""
							for {
								set l = $order(classes(c,i,"sql",j,"sub",k,"invc",l),1,code)
								quit:l=""
								set storage.SQLMaps.GetAt(j).Subscripts.GetAt(k).Invalidconditions.GetAt(l).Expression = code
							}
						}
					}
					
				}
			}
			
			// for computed fields, we need to update their code to run in the other NS
			for j = 1:1:newdef.Properties.Count() {
				#dim prop as %Dictionary.PropertyDefinition = newdef.Properties.GetAt(j)
				continue:'prop.SqlComputed
				set prop.SqlComputeCode = "	new $namespace  set $namespace = """_sourceNS_""""_$c(13,10)_prop.SqlComputeCode
			}
			
			set sc = newdef.%Save()
			quit:$$$ISERR(sc)
			
			set newdefs(newdef.Name)=""
		}
		quit:$$$ISERR(sc)
		
		set sc = $SYSTEM.OBJ.Compile(.newdefs, "ck"_$s(verbose:"d", 1:"-d"))
		quit:$$$ISERR(sc)
		
	} catch (ex) {
		set sc = ex.AsStatus()
	}
	set $namespace = ns
	quit sc
	
GetExtendedRef(glo)
	quit:glo="" ""
	// could also do di-level refs using $$getdest^%SYS.GXLINF1("ns","^glo")
	quit:$e(glo)'="^" glo
	quit "^["""_sourceNS_"""]"_$e(glo,2,*)
}

/// Helper method for CreateMappedTable(). Do not use directly.
/// Superficial scan for global references we need to rewire
ClassMethod ScanCode(oldCode, Output newCode, sourceNS As %String) As %Boolean [ Internal ]
{
	set newCode=""
	quit:oldCode="" 0
	set oldCode = $replace(oldCode,"^(",$c(0,0)) // naked global ref is OK
	quit:'$f(oldCode,"^") 0
	
	set pos = 0, 
		changed = 0
	for {
		set nextPos = $find(oldCode,"^",pos+1)
		quit:'nextPos
		
		// copy the code
		set newCode =newCode_$e(oldCode,pos,nextPos-2)_"^"
		
		// WARNING: shallow checks ahead!
		
		// ignore if this is clearly just a string: 'set x = "^"'
		if ($e(oldCode,nextPos)="""") || ($e(oldCode,nextPos-2)="""") {}
		
		// ignore if this is clearly just a routine call: "do ^test" or "d ^test"
		elseif ($e(oldCode,nextPos-4,nextPos-3)="do") ||
				($e(oldCode,nextPos-3)="d") {}
		
		// ignore if this is part of a function call: "set x = $$abc^xyz"
		elseif ($zstrip($e(oldCode,nextPos-2),"*AN")="") {}
		
		// this is likely a gloref, so squeeze in extended ref part
		else {
			set newCode =newCode_"["""_sourceNS_"""]",
				changed = 1
		}
		set pos=nextPos
	}
	quit:'changed 0
	
	// append the rest and restore naked global ref
	set newCode = $replace(newCode_$e(oldCode,pos,*),$c(0,0),"^(")
	quit 1
}

/// Helper method for CreateMappedTable(). Do not use directly.
ClassMethod AddRelated(def As %Dictionary.ClassDefinition, ByRef classes, includePropTypes As %Boolean, includeForeignKeys As %Boolean) As %Integer [ Internal, Private ]
{
	set super = def.Super, cnt = 0
	for i = 1:1:$l(super,",") {
		set s = $p(super,",",i)
		continue:s=""
		continue:$e(s)="%" 			// skip obvious system classes
		continue:$d(classes(s)) 	// skip classes we already listed
		set d = ##class(%Dictionary.ClassDefinition).%OpenId(s,,.sc)
		b:$$$ISERR(sc)
		continue:d.System 			// assume customers don't use/need this
		set classes(s) = d.%ConstructClone(1)
		set cnt = cnt + ..AddRelated(d, .classes, includePropTypes)
	}
	
	// Also consider picking up property types
	if (includePropTypes) {
		for i = 1:1:def.Properties.Count() {
			set t = def.Properties.GetAt(i).Type
			continue:$e(t)="%" 			// skip obvious system classes
			continue:$d(classes(t)) 	// skip classes we already listed
			set d = ##class(%Dictionary.ClassDefinition).%OpenId(t,,.sc)
			b:$$$ISERR(sc)
			continue:d.System 			// assume customers don't use/need this
			set classes(t) = d.%ConstructClone(1)
			set cnt = cnt + ..AddRelated(d, .classes, includePropTypes, includeForeignKeys)
		}
	}
	
	if (includeForeignKeys) {
		for i = 1:1:def.ForeignKeys.Count() {
			set t = def.ForeignKeys.GetAt(i).Type
			continue:$e(t)="%" 			// skip obvious system classes
			continue:$d(classes(t)) 	// skip classes we already listed
			set d = ##class(%Dictionary.ClassDefinition).%OpenId(t,,.sc)
			b:$$$ISERR(sc)
			continue:d.System 			// assume customers don't use/need this
			set classes(t) = d.%ConstructClone(1)
			set cnt = cnt + ..AddRelated(d, .classes, includePropTypes, includeForeignKeys)
		}
	}
	
	quit cnt
}

}
