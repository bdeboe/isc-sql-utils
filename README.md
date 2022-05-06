![Repo-GitHub](https://img.shields.io/badge/dynamic/xml?color=blue&label=ZPM%20version&version&prefix=v&query=%2F%2FVersion&url=https%3A%2F%2Fraw.githubusercontent.com%2Fbdeboe%2Fisc-sql-utils%2Fmaster%2Fmodule.xml)
[![Quality Gate Status](https://community.objectscriptquality.com/api/project_badges/measure?project=intersystems_iris_community%2Fisc-sql-utils&metric=alert_status)](https://community.objectscriptquality.com/dashboard?id=intersystems_iris_community%2Fisc-sql-utils)


# IRIS SQL Utilities

Various recipes from my SQL cookbook for baking your finest storage, all the way from baguette to croissant and back. This is *not* an official InterSystems repository but rather a practical way to exchange experiments and sample code. 

To install, either import the contents of the `/src` folder or use [ZPM](https://github.com/intersystems-community/zpm):
```ObjectScript
zpm install bdb-sql-utils
```

Use at your own risk, or yell at me in the Issues section :-)

## Table Storage Consumption

If you're looking for a handy way to check the size of your IRIS SQL table on disk, try this simple classmethod or query:

```ObjectScript
do ##class(bdb.sql.StorageUtils).TableSize("MySchema.MyTable")
```

```SQL
CALL bdb_sql.TableSize('MySchema.MyTable')
```

## Exporting a table and its contents

This one will likely find its way into the product after a little more polishing, but it does exactly what the title says. For tables with regular storage, only the master map globals will be exported and indices will be rebuilt when running the `ImportTable()` method.

```ObjectScript
do ##class(bdb.sql.StorageUtils).ExportTable("SQLUser.NATION","/tmp/table.xml.gz")
...
do ##class(bdb.sql.StorageUtils).ImportTable("/tmp/table.xml.gz")
```

## Adopting Extent Sets

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


## Projecting from a different namespace

As a developer you may find yourself longing for that perfect test table or bulky test dataset in a different namespace. Use `CreateMappedTable()` to create a projection in the current namespace of a table in another one.

```ObjectScript
write ##class(bdb.sql.StorageUtils).CreateMappedTable("ORIGINAL","My_Very.BestTable")
```

See the class method's argument list for more ways to tweak what gets generated.

Note that this method just creates a one-off projection and does not refresh it if the source table / storage changes.


## Projecting a "list of" collection property

Before 2022.1, only array-style collection properties support [projecting as a table](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GOBJ_propcoll#GOBJ_propcoll_sqlproj). This utility helps you build a read-only table projecting list-style collection properties on earlier versions. Note that the generated class has no link to the original class so you'll have to drop / recreate it if you change the original one (which I'm not touching).

```ObjectScript
write ##class(bdb.sql.CollectionUtils).BuildProjection("Sample.Person","FavoriteColors")
```

## Taking a snapshot of your Statement Index

The SQL Statement Index is a treasure trove of information on the statements executed on your system, but it's somewhat "local" to your instance. If you're in a support or POC context, it may be practical to export this data and then import it in another environment, or simply take a snapshot before you pull apart your schema to try something new.

```ObjectScript
do ##class(bdb.sql.StatementUtils).Snapshot()
do ##class(bdb.sql.StatementUtils).ExportSnapshot("\tmp\SI-export.xml")
```
