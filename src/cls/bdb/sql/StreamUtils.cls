/// Utilities for working with Streams
/// <ul>
/// <li><method>CompressStreams</method></li>
/// </ul>
Class bdb.sql.StreamUtils
{

Parameter MINIMALCOMPRESSIONRATE = 0.8;

/// Inspects the stream fields in class <var>className</var> and, if they are compressible,
/// launches <var>jobs</var> jobs to try and compress them.
/// Use <var>verbose</var> for an interactive version.
ClassMethod CompressStreams(className As %String, verbose As %Boolean = 1, lock As %Boolean = 1, jobs As %Integer = {$SYSTEM.Util.NumberOfCPUs()}, minimalCompressionRate As %Numeric = {..#MINIMALCOMPRESSIONRATE}) As %Status
{
#define PromptContinue(%msg) write !,%msg,! ##continue
    read "Do you want to continue? [Y|n] ",yes#1 ##continue
    return:(yes'="")&&($$$UPPER(yes)'="Y") $$$OK 

    set sc = $$$OK
    try {

        set class = ##class(%Dictionary.CompiledClass).%OpenId(className,,.sc)
        quit:$$$ISERR(sc)
    	set storage = ##class(%Dictionary.CompiledStorage).%OpenId(className_"||"_class.StorageStrategy)
		
        write:verbose !,"Reviewing stream properties in class '",className,"'"

        for i = 1:1:class.Properties.Count() {
            set prop = class.Properties.GetAt(i)
            if $classmethod(prop.Type,"%IsA","%Stream.Object") {
                set location = prop.Parameters.GetAt("LOCATION")
                set:location="" location = storage.StreamLocation
                set compressMode = -1
                try {
                    set compressMode = $PARAMETER(prop.Type,"COMPRESS")
                } catch {}
                if (compressMode = "") {
                    write:verbose !,"- Property '",prop.Name,"' of type ",prop.Type," and stored at ",location," does not support compression"
                    set locations(location,0,prop.Name) = "", allGood=0
                } elseif (compressMode = -1) {
                    write:verbose !,"- Property '",prop.Name,"' of type ",prop.Type," and stored at ",location," has compression disabled"
                    set locations(location,0,prop.Name) = "", allGood=0
                } else {
                    write:verbose !,"- Property '",prop.Name,"' of type ",prop.Type," and stored at ",location," can be compressed"
                    set locations(location,1,prop.Name) = ""
                }
            }
        }

        write:verbose !
 
        set location = ""
        for {
            set location = $order(locations(location))
            quit:location=""

            // check if this location is shared with other classes
            &SQL(SELECT LIST(parent) INTO :lst FROM %Dictionary.CompiledStorage WHERE StreamLocation = :location AND parent != :className)
            if (lst'="") {
                return:'verbose $$$ERROR($$$GeneralError, "At least one stream location is shared with other classes: "_lst_". Run interactively for more options.")
                $$$PromptContinue("Global "_location_" is shared with other classes: "_lst_".")
            }
            &SQL(SELECT LIST(parent||':'||Name) INTO :lst FROM %Dictionary.CompiledProperty WHERE FOR SOME %ELEMENT (Parameters) (%key = 'LOCATION' AND %value = :location) AND parent != :className AND NOT parent %STARTSWITH '%')
            if (lst'="") {
                return:'verbose $$$ERROR($$$GeneralError, "At least one stream location is shared with fields in other classes: "_lst_". Run interactively for more options.")
                $$$PromptContinue("Global "_location_" is shared with fields in other classes: "_lst_".")
            }

            // check if all streams at this location are compressible
            if $d(locations(location,0)) {
                
                return:'verbose $$$ERROR($$$GeneralError, "At least one stream field does not support compression. Run interactively for more options.")

                if $d(locations(location,1)) {
                    $$$PromptContinue("Global "_location_" contains a mix of supported and unsupported stream fields and will be skipped.")
                    kill locations(location)
                    continue
                } else {
                    $$$PromptContinue("Global "_location_" contains unsupported stream fields and will be ignored.")
                    kill locations(location)
                    continue
                }
            }
        } 

        write:verbose !
        if '$d(locations) {
            write:verbose !,"Nothing left to compress..."
        }

        set:jobs>1 wqm = $SYSTEM.WorkMgr.Initialize("/multicompile=1")

        // Now go through the assembled locations, which by now should only have
        // compressible streams
        set location = ""
        for {
            set location = $order(locations(location))
            quit:location=""

            write:verbose !,"Now compressing strings in ",location,$s(jobs>1:" using "_jobs_" jobs",1:" using a single process")
            
            kill ^IRIS.Temp.CompressStreams($j)

            if jobs<=1 {

                set sc = ..CompressStreamsJob(location, "", "", lock, $job, minimalCompressionRate)
                quit:$$$ISERR(sc)

            } else {
                
                set split = $$SplitSize^%GSIZE($e(location,2,*), "N", jobs)
                continue:$lg(split)=3 // no data
                if $lg(split)'=1 {
                    set sc = $$$ERROR($$$GeneralError,$lg(split,2))
                    quit
                }
                set split = $lg(split,2)

                do wqm.Queue("##class("_$classname()_").CompressStreamsJob", location, "", $lg(split), lock, $job, minimalCompressionRate)
                for i = 1:1:$ll(split) {
                    do wqm.Queue("##class("_$classname()_").CompressStreamsJob", location, $lg(split,i), $lg(split,i+1), lock, $job, minimalCompressionRate)
                }

                set sc = wqm.WaitForComplete()
                quit:$$$ISERR(sc)
            }

            write:verbose !,"Compressed ",$g(^IRIS.Temp.CompressStreams($job,"c"))," streams (",$g(^IRIS.Temp.CompressStreams($job,"a"))," were compressed already, ",$g(^IRIS.Temp.CompressStreams($job,"l"))," were locked and ",$g(^IRIS.Temp.CompressStreams($job,"s"))," contained non-compressible data)"
            kill ^IRIS.Temp.CompressStreams($job)
        }

    } catch (ex) {
        set sc = ex.AsStatus()
    }
    
	if verbose {
		if $$$ISERR(sc) {
			do $system.OBJ.DisplayError()
		}
		write !
	}
    kill ^IRIS.Temp.CompressStreams($job)
    quit sc
}

/// INTERNAL METHOD - DO NOT INVOKE - see <method>CompressStreams</method>
ClassMethod CompressStreamsJob(location As %String, startSub As %Binary = "", endSub As %Binary = "", lock As %Boolean = 1, job As %Integer = 0, minimalCompressionRate As %Numeric = {..#MINIMALCOMPRESSIONRATE}) As %Status [ Internal ]
{
    set sc = $$$OK
    try {
        
        set i = startSub, 
            endSub = $s(endSub="":"", 1:$o(@location@(endSub))),
            (cCompressed, cAlreadyCompressed, cSkipped, cLocked) = 0,
            unlock = ""
        for {
            set i = $order(@location@(i),1,header)
            quit:i=endSub

            // check out the header format and compress
            if header [ "," {
                set maxNodeNo = $p(header,",",1), 
                    ioSize = $p(header,",",2),
                    compressed = $p(header,",",3)
                if compressed {
                    set cAlreadyCompressed = cAlreadyCompressed+1
                    continue
                }
            } else {
                set maxNodeNo = +header, 
                    ioSize = @location@(i,0)
            }

            if ..NotCompressible($g(@location@(i,1)), minimalCompressionRate) {
                set cSkipped = cSkipped+1
                continue
            }

            if lock {
                lock @location@(i):0
                if '$test {
                    // if we cannot acquire a lock, just skip. 
                    // These should be exceptions anyway
                    set cLocked = cLocked+1
                    continue
                } else {
                    set unlock = $NAME(@location@(i))
                }
            }

            for j = 1:1:maxNodeNo {
                set @location@(i,j) = $system.Util.Compress(@location@(i,j),"zstd")
            }

            set @location@(i) = maxNodeNo_","_ioSize_",1"
            kill @location@(i,0)

            if (unlock'="") {
                lock -@unlock
                set unlock=""
            }

            set cCompressed = cCompressed+1
        }
    } catch (ex) {
        set sc = ex.AsStatus()
    }

    if ($g(unlock)'="") {
        lock -@unlock
    }

    set x = $i(^IRIS.Temp.CompressStreams(job,"c"), cCompressed),
        x = $i(^IRIS.Temp.CompressStreams(job,"s"), cSkipped),
        x = $i(^IRIS.Temp.CompressStreams(job,"a"), cAlreadyCompressed),
        x = $i(^IRIS.Temp.CompressStreams(job,"l"), cLocked)

    quit sc
}

/// Return true if this buffer looks like it is not compressible.
/// Check for small buffer, known prefixes of compressed data and check a small segment of the buffer for compressibility
ClassMethod NotCompressible(data As %String, minimalCompressionRate As %Numeric = {..#MINIMALCOMPRESSIONRATE}) As %Boolean [ Internal, Private ]
{
	Set len=$length(data)
	#; Only compress when first block is at least 1k
	If len<1024 RETURN 1
	Set buf=$extract(data,1,10)
	#; Lots of formats at https://www.garykessler.net/library/file_sigs.html
	#; If we wish to add a lot more patterns we can optimize how it searches, for now simple linear scan is fine
	If $extract(buf,1,2)=$c(255,216) RETURN 1 ; jpeg
	If $extract(buf,1,4)=$c(80,75,3,4) RETURN 1  ; zip
	If $extract(buf,1,3)=$c(31,139,8) RETURN 1  ; gzip
	If $extract(buf,1,6)=$c(253,55,122,88,90,0) RETURN 1 ; xz
	If $extract(buf,1,2)=$c(31,157)||($extract(buf,1,2)=$c(31,160)) RETURN 1  ; compressed TAR
	If buf=$c(0,0,0,12,106,80,32,32,13,10) RETURN 1  ; jpeg2000
	If $extract(buf,1,4)=$c(0,0,1,183)||($extract(buf,1,4)=$c(0,0,1,185))||($extract(buf)=$c(255)&&($ascii(buf,2)>=224)) RETURN 1 ; mpeg
	If $extract(buf,1,6)=$c(55,122,188,175,39,28) RETURN 1 ; 7z
	If $extract(buf,1,3)=$c(66,90,104) RETURN 1 ; BZ2
	If $extract(buf,1,6)=$c(71,73,70,56,55,97)||($extract(buf,1,6)=$c(71,73,70,56,57,97)) RETURN 1 ; gif
	If $extract(buf,1,3)=$c(73,68,51) RETURN 1 ; mp3
	If $extract(buf,1,6)=$c(74,65,82,67,83,0)||($extract(buf,1,8)=$c(80,75,3,4,20,0,8,0))||($extract(buf,1,4)=$c(95,39,168,137)) RETURN 1 ; jar
	If $extract(buf,1,4)=$c(80,75,7,8)||($extract(buf,1,4)=$c(80,75,5,6)) RETURN 1 ; pkzip
	If $extract(buf,1,4)=$c(82,73,70,70) RETURN 1 ; avi
	If $extract(buf,1,6)=$c(82,97,114,33,26,7) RETURN 1 ; rar
	If $extract(buf,5,8)=$c(102,116,121,112) RETURN 1 ; mp4
	If $extract(buf,5,10)=$c(102,116,121,112,113,116)||($extract(buf,5,8)=$c(109,111,111,118)) RETURN 1 ; mov
	#; Try compressing first 4k, if this does not get a good compression ratio (80% or less) with lz4 skip compression
	If $length($System.Util.Compress($extract(data,1,4096),"zstd"))/$select(len>4096:4096,1:len)>minimalCompressionRate RETURN 1
	RETURN 0
}

ClassMethod ChangeStreamType(className As %String, verbose As %Boolean = 1, changeFrom As %List = {$lb("%Library.GlobalCharacterStream", "%Library.GlobalBinaryStream")}) As %Status
{
#define PromptContinue(%msg) write !,%msg,! ##continue
    read "Do you want to continue? [Y|n] ",yes#1 ##continue
    return:(yes'="")&&($$$UPPER(yes)'="Y") $$$OK 

    set sc = $$$OK
    try {

        set class = ##class(%Dictionary.CompiledClass).%OpenId(className,,.sc)
        quit:$$$ISERR(sc)
    	set storage = ##class(%Dictionary.CompiledStorage).%OpenId(className_"||"_class.StorageStrategy)
		
        write:verbose !,"Reviewing stream properties in class '",className,"' for types: ",$lts(changeFrom,", ")
        
        set ptr = 0
        while $listnext(changeFrom, ptr, c) { set changeFrom(c) = "" }

        kill try
        for i = 1:1:class.Properties.Count() {
            set prop = class.Properties.GetAt(i)
            continue:'$d(changeFrom(prop.Type))

            set try(prop.SqlFieldName) = prop
        }

        #dim storageData as %Dictionary.CompiledStorageData
        #dim storageValue as %Dictionary.CompiledStorageDataValue
        for i = 1:1:storage.Data.Count() {
            set storageData = storage.Data.GetAt(i) 
            for j = 1:1:storageData.Values.Count() {
                set storageValue = storageData.Values.GetAt(j), 
                    propName = storageValue.Value
                if (propName'="") && $d(try(propName), prop) {
                    set change(propName, "p") = prop, 
                        change(propName, "s") = storageValue
                    kill try(propName)
                }
            }
        }

        if $d(try) {
            if 'verbose {
                return $$$ERROR($$$GeneralError, "Unable to find storage location for some of the stream properties. Run interactively for more options.")
            } else {
                write !,"Unable to find storage location for these properties:"
                set propName = ""
                for {
                    set propName = $order(try(propName),1,prop)
                    quit:propName=""
                    write !,"   - ",prop.Name," (",prop.Type,")"
                }
            }
            if $d(change) {
                set propName = "", lst = ""
                for {
                    set propName = $order(try(propName),1,prop)
                    quit:propName=""
                    set lst = lst _ $lb(prop.Name)
                }
                $$$PromptContinue("Only the following properties can be changed: "_lst)
            } else {
                write:verbose !,"No properties left to change"
                return $$$OK
            }
        }

        // by now we have a set of properties and their storage location
        if verbose {
            write !!,"The following properties will be changed: "
            set propName = ""
            for {
                set propName = $order(change(propName))
                quit:propName=""
                write !,"   - ",propName," (",change(propName,"p").Type,")"
                set storageValue = change(propName,"s")
                set str = storage.DataLocation_"(%ID"_$s(storageValue.parent.Subscript'="":","_storageValue.parent.Subscript,1:"")_")"
                if (storageValue.parent.Structure="listnode") {
                    set str = "$lg("_str_", "_storageValue.Name_")"
                } elseif (storageValue.parent.Structure="piece") {
                    set str = "$piece("_str_", """_storageValue.parent.Delimiter_""", "_storageValue.Name_")"
                } else {
                    return $$$ERROR($$$GeneralError, "Unsupported storage structure: "_storageValue.parent.Structure)
                }
                write !,"         with %SID at ",str
                set str = change(propName,"p").Parameters.GetAt("LOCATION")
                set:str="" str = storage.StreamLocation
                set change(propName,"g")=str
                write !,"         and stream data at ",str,"(%SID)"
            }
        }

        // TODO: change class def - this is the easy part!

        // now scan through the extent and change individual stream references
        set glo = storage.DataLocation
        set id = ""
        for {
            set id = $order(@glo@(id),1,d)
            quit:id=""

            set propName = ""
            for {
                set propName = $order(change(propName))
                quit:propName=""

                set storageValue = change(propName,"s"),
                    sub = storageValue.parent.Subscript,
                    struc = storageValue.parent.Structure,
                    data = $s(sub="":d, 1:$g(@glo@(id,sub))),
                    sid = $lg($case(struc,"listnode":$lg(data,storageValue.Name),"piece":$p(data,storageValue.parent.Delimiter,storageValue.Name)))
                
                set:$e(sid)=$c(0) sid = $e(sid,2,*)
                
                // by now it should be $lb($lb("^global",sid),...)
                set sid = $lg($lg(sid),2)_""
                
                // now convert stream header to "<maxNodeNumber>,<iosize>"
                set header = $g(@(change(propName,"g"))@(+sid))_","_$g(@(change(propName,"g"))@(+sid,0))
                set @(change(propName,"g"))@(+sid) = header
                kill @(change(propName,"g"))@(+sid,0)

                // and set simple SID into data again
                if (sub)="" {
                    if (struc="listnode") {
                        set $li(@glo@(id),storageValue.Name) = sid
                    } else {
                        set $piece(@glo@(id), storageValue.parent.Delimiter, storageValue.Name) = sid
                    }
                } else {
                    if (struc="listnode") {
                        set $li(@glo@(id, sub),storageValue.Name) = sid
                    } else {
                        set $piece(@glo@(id, sub), storageValue.parent.Delimiter, storageValue.Name) = sid
                    }
                }
            }
        }

    } catch (ex) {
        set sc = ex.AsStatus()
    }
    
	if verbose {
		if $$$ISERR(sc) {
			do $system.OBJ.DisplayError()
		}
		write !
	}

    kill ^IRIS.Temp.ChangeStreamType($job)
    quit sc
}

}
