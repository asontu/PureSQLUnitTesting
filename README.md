PureSQLUnitTesting
==================

With these purely T-SQL procedures it's easy to make UnitTests for Stored Procedures. It's a very minimalist approach, which brings some limitations, but also provides a very low barrier of entry to start UnitTesting SQL code. For full usage documentation check out the [DOCS](./DOCS.md).

The approach of PureSQLUnitTesting is that your Stored Procedures are copied and modified to do their work on temporary tables rather than the actual tables in the database. The modification is done with a simple `replace()`, which means the writing of the Stored Procedures themselves needs to use prefixes to accommodate this. There's two approaches possible to achieve this, both examples below work on this table definition:

```sql
create table MyTable (
	id int identity primary key,
	description nvarchar(max),
	price decimal(20, 5)
)
```

### Develop normally, deploy UnitTest variant

Write your code like you're used to, but be consistent and prefix the schema (`dbo.`) in front of any tables:

```sql
create procedure AddTotalsLine(@description nvarchar(255) = null)
as begin
	insert into dbo.MyTable(description, price)
	select 'Subtotal' + isnull(' ' + @description, ''), isnull(sum(price), 0)
	from dbo.MyTable
	where isnull(description, '') not like 'Subtotal%'
end
```

"Deploy" the Stored Procedure to a UnitTest variant, where `dbo.` get replaced with `#unittest_` and the Stored Procedure name `AddTotalsLine` turns into `AddTotalsLine_UTST`.

```sql
exec DeployObjects
	'<deployment>
		<replace from="dbo." to="#unittest_" />
		<replace from="AddTotalsLine" to="AddTotalsLine_UTST" />
	
		<deploy>AddTotalsLine</deploy>
	</deployment>'
```

With this UnitTest variant you can then perform UnitTests:

```sql
exec RunUnitTests
	'<unittests>
		<test name="Add Subtotal line with sum of price from apples and pears lines">
			<prefix dev="dbo." ut="#unittest_" />
			<mock>
				<MyTable description="apples" price="1.25" />
				<MyTable description="pears" price="1.45" />
			</mock>
			<act>exec AddTotalsLine_UTST</act>
			<assert expected=" = 3">
				select count(*) from #unittest_MyTable
			</assert>
			<assert expected=" = 2.70">
				select top 1 price from #unittest_MyTable where description like ''Subtotal%''
			</assert>
		</test>
	</unittests>'
```

### TDD: develop based on UnitTests, then deploy

Alternatively, you can write code that operates on the temporary tables and UnitTest until everything passes, then deploy:

```sql
create procedure AddTotalsLine_UTST(@description nvarchar(255) = null)
as begin
	insert into #unittest_MyTable(description, price)
	select 'Subtotal' + isnull(' ' + @description, ''), isnull(sum(price), 0)
	from #unittest_MyTable
	where isnull(description, '') not like 'Subtotal%'
end
go

exec RunUnitTests
	'<unittests>
		<test name="Add Subtotal line with sum of price from apples and pears lines">
			<prefix ut="#unittest_" />
			<mock>
				<MyTable description="apples" price="1.25" />
				<MyTable description="pears" price="1.45" />
			</mock>
			<act>exec AddTotalsLine_UTST</act>
			<assert expected=" = 3">
				select count(*) from #unittest_MyTable
			</assert>
			<assert expected=" = 2.70">
				select top 1 price from #unittest_MyTable where description like ''Subtotal%''
			</assert>
		</test>
	</unittests>'
go

exec DeployObjects
	'<deployment>
		<replace from="#unittest_" to="dbo." />
		<replace from="_UTST" to="" />
	
		<deploy>AddTotalsLine_UTST</deploy>
	</deployment>'
```

Installation
------------

To install, simply run the `Release.sql` file on your SQL server to add the procedures.