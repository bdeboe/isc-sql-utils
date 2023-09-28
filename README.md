![Repo-GitHub](https://img.shields.io/badge/dynamic/xml?color=blue&label=ZPM%20version&version&prefix=v&query=%2F%2FVersion&url=https%3A%2F%2Fraw.githubusercontent.com%2Fbdeboe%2Fisc-sql-utils%2Fmaster%2Fmodule.xml)
[![Quality Gate Status](https://community.objectscriptquality.com/api/project_badges/measure?project=intersystems_iris_community%2Fisc-sql-utils&metric=alert_status)](https://community.objectscriptquality.com/dashboard?id=intersystems_iris_community%2Fisc-sql-utils)


# IRIS SQL Utilities

Various recipes from my SQL cookbook for baking your finest storage, all the way from baguette to croissant and back. This is *not* an official InterSystems repository but rather a practical way to exchange experiments and sample code. The repository also includes utilities that aren't a good fit for including in a fixed IRIS release as they may evolve more quickly than the general platform release stream allows, as well as making sense on older releases. 

To install, either import the contents of the `/src` folder or use [ZPM](https://github.com/intersystems-community/zpm):
```ObjectScript
zpm install bdb-sql-utils
```

Use at your own risk, or yell at me in the Issues section :-)

- [Storage Utilities](#storage-utilities)
  - [Table Storage Consumption](#table-storage-consumption)
  - [Exporting a table and its contents](#exporting-a-table-and-its-contents)
- [Stream utilities](#stream-utilities)
  - [Compressing existing stream data](#compressing-existing-stream-data)
- [Statement Index utilities](#statement-index-utilities)
  - [Taking a snapshot of your Statement Index](#taking-a-snapshot-of-your-statement-index)
  - [Table Usage Stats](#table-usage-stats)
- [Miscellaneous](#miscellaneous)
  - [Inferring table structure](#inferring-table-structure)
  - [Generic table logging](#generic-table-logging)
  - [Adopting Extent Sets](#adopting-extent-sets)
  - [Projecting a table from a different namespace](#projecting-a-table-from-a-different-namespace)
  - [Projecting a "list of" collection property](#projecting-a-list-of-collection-property)


## Storage Utilities

### Table Storage Consumption

If you're looking for a handy way to check the size of your IRIS SQL table on disk, try this simple classmethod or query:

```ObjectScript
do ##class(bdb.sql.StorageUtils).TableSize("MySchema.MyTable")
```

```SQL
SELECT * FROM bdb_sql.TableSize('MySchema.MyTable')
```

### Exporting a table and its contents

#### Physical export

This one will likely find its way into the product after a little more polishing, but it does exactly what the title says: exporting the table definition and corresponding global data to an IRIS export file (XML). 
For tables with regular storage, only the master map globals will be exported and indices will be rebuilt when running the `ImportTable()` method.

```ObjectScript
do ##class(bdb.sql.StorageUtils).ExportTable("SQLUser.NATION","/tmp/table.xml.gz")
...
do ##class(bdb.sql.StorageUtils).ImportTable("/tmp/table.xml.gz")
```

#### Logical export

If you need to dump a table's contents to a more portable format that adheres to simple SQL semantics, use `bdb.sql.Dump`, which supports the same set of parameters as IRIS SQL's `LOAD DATA` command:

```ObjectScript
do ##class(bdb.sql.Dump).Dump("SQLUser.NATION", "/tmp/table.csv")
```
or in SQL
```SQL
CALL bdb_sql.Dump('NATION', '/tmp/table.csv')
```


## Stream utilities

### Compressing existing stream data

InterSystems IRIS 2021.2 expands the use of Stream Compression, making it the default for all globals-based stream types. New data inserted into `%Stream.GlobalCharacter` or `%Stream.GlobalBinary` will now automatically be compressed and may reduce their storage footprint by up to 80%, depending on the data (note that data that is already compressed, such as JPEG files, will be left untouched as there's no benefit in compressing it twice).

This interactive command-line utility allows you to compress pre-existing stream data, without affecting the class definitions:
```ObjectScript
do ##class(bdb.sql.StreamUtils).CompressStreams("MyPackage.MyClass")
```

If your application is still using old stream field types such as `%GlobalCharacterStream`, a utility method is provided to convert the stream headers into the (compressible) format of corresponding newer datatypes in the `%Stream` package, compressing them on the fly:
```ObjectScript
do ##class(bdb.sql.StreamUtils).ChangeStreamType("MyPackage.MyClass")
```

The (default) interactive version of these methods will check if stream types are eligible for compression / conversion and allow you to abort if something unexpected is found. Please refer to the class reference for additional options.


## Statement Index utilities

### Taking a snapshot of your Statement Index

The SQL Statement Index is a treasure trove of information on the statements executed on your system, but it's somewhat "local" to your instance. If you're in a support or POC context, it may be practical to export this data and then import it in another environment, or simply take a snapshot before you pull apart your schema to try something new.

```ObjectScript
do ##class(bdb.sql.StatementUtils).Snapshot()
do ##class(bdb.sql.StatementUtils).ExportSnapshot("\tmp\SI-export.xml")
```

### Table Usage Stats

The SQL Statement Index includes detailed information at the statement level, which we can aggregate to the table level, telling you how many statements actually tried to SELECT, INSERT, UPDATE or DELETE each table. Starting with IRIS 2022.1, these additional stats will also include the aggregated ROWCOUNT for such operations.

```ObjectScript
do ##class(bdb.sql.StatementUtils).AddTableUsageStats("MySchema")
```


## Miscellaneous

### Inferring table structure

Often the first step in building out a demo or project is loading data from a source file into a table that has yet to be created. The `bdb.sql.InferSchema` class helps with that, including a one-stop-shop method that scans a directory, creates a table for each file in there and then loads it.
```ObjectScript
do ##class(bdb.sql.InferSchema).BuildAll("/tmp/data-dump/*.csv", { "verbose": 1, "targetSchema": "MySchema" })
```

Alternatively, on IRIS 2023.1 and above, you can create <a href="https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GSQL_tables#GSQL_tables_foreign">Foreign Tables</a> for one or more files using the following command:
```ObjectScript
do ##class(bdb.sql.InferSchema).CreateForeignTables("/tmp/data-dump/*.csv", { "verbose": 1, "targetSchema": "MySchema", "serverName": "MySchema.FServer" })
```

### Generic table logging

Many customers leverage Triggers to automatically log updates to a row as kind of an application-level audit facility. This utility class will automatically generate an UPDATE/DELETE trigger for logging any field changes to the `bdb.logme.Log`. All you need to do is have your `%Persistent` class inherit from `bdb.logme.Trigger` and the proper trigger code will be generated for you. See the class reference for more details on fine-tuning the default behaviour.

Please note this is meant as a fine-grained convenience utility and should not be used as a replacement for the fully-secured [IRIS Auditing feature](https://docs.intersystems.com/iris20212/csp/docbook/DocBook.UI.Page.cls?KEY=AAUDIT).

### Adopting Extent Sets

We've been recommending the use of [extent sets](https://docs.intersystems.com/irislatest/csp/documatic/%25CSP.Documatic.cls?&LIBRARY=%25SYS&CLASSNAME=%25Library.Persistent#USEEXTENTSET) for many years now, but sadly cannot make this the default behaviour for newly created classes because of backwards compatibility issues it'd cause. 

If you want to modernize your storage with just a little more than a paint job, you can already adopt `USEEXTENTSET=1` and just wire your existing master and index map to their current global locations, so that all _new_ maps will get their proper global. Specifically, you could drop and recreate your indices so they all get their own global.

```ObjectScript
write ##class(bdb.sql.StorageUtils).ConvertToUseExtentSets("My.Ancient.CustomerClass")
```

See the class method's argument list for further options.


Notes:
* When trying to convert classes in a hierarchy, you should aim this method at the superclass defining the storage. It will return an error if you try it on a subclass first, but will convert any subclasses along if you use it on a superclass.
* This method performs a very simple check on non-bitmap indices to see if they still work after swapping the storage (for which it keeps a backup). It may not be watertight, so make sure to run your own regression / unit tests.
* This method does not (yet) provide an option to perform the described drop-and-recreate-indices procedure
* A future version of this method may also move the data from that long-ish D global into a proper extent global


### Projecting a table from a different namespace

As a developer you may find yourself longing for that perfect test table or bulky test dataset in a different namespace. Use `CreateMappedTable()` to create a projection in the current namespace of a table in another one.

```ObjectScript
write ##class(bdb.sql.StorageUtils).CreateMappedTable("ORIGINAL","My_Very.BestTable")
```

See the class method's argument list for more ways to tweak what gets generated.

Note that this method just creates a one-off projection and does not refresh it if the source table / storage changes.


### Projecting a "list of" collection property

Before 2022.1, only array-style collection properties support [projecting as a table](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GOBJ_propcoll#GOBJ_propcoll_sqlproj). This utility helps you build a read-only table projecting list-style collection properties on earlier versions. Note that the generated class has no link to the original class so you'll have to drop / recreate it if you change the original one (which I'm not touching).

```ObjectScript
write ##class(bdb.sql.CollectionUtils).BuildProjection("Sample.Person","FavoriteColors")
```
