Documentation
=============

This is the full documentation, for a quick overview take a look at the [README](./README.md).

Installation
------------

To install, simply run the `DeployObjects.sql` and `RunUnitTests.sql` files on the SQL server instance where the UnitTests will be run.

Prepare Stored Proc for testing
-------------------------------

The UnitTests run on an altered version of the stored procedures being tested. You can prepare the stored proc with `DeployObjects`, which makes it easy to create a copy of stored procedures with small alterations.

`DeployObjects` accepts the follow input XML:

`exec DeployObjects '<deployment>`
-	`<replace from="dbo." to="#unittest_" />` _(optional)_  
	One or more replace-operations that are applied to the contents and name of the Stored Proc being deployed.
-	`<deploy>TotalsPerCustomer</deploy>` **(mandatory)**  
	One or more objects to deploy. Because of historic reasons these can also be views or functions besides just stored procs. Currently PureSQLUnitTesting does not work with functions that query tables nor with views (which by definition query tables).

`</deployment>'`

### Test Driven Development: Flip the script

Since blindly replacing all instances of `dbo.` with `#unittest_` might not be the best approach in some cases, for instance if the stored procedures being tested calls other stored procedures with the same schema prefix `dbo.` as the tables it queries. In this case, it might be better to write the Stored Procedure as the UnitTest-variant, then run the UnitTests first, and only when all the UnitTests pass, use `DeployObjects` to deploy the stored proc to a production-ready variant.

In this case the `from=""` and `to=""` attribute values would be flipped:

```sql
exec DeployObjects '<deployment>
	<replace from="#unittest_" to="dbo." />
	<replace from="_UTST" to="" />
	<deploy>TotalsPerCustomer_UTST</deploy>
</deployment>'
```

Write and run a UnitTest
------------------------

UnitTests follow the basic **Arrange** -> **Act** -> **Assert** pattern. **Arranging** in this case means mocking tables (or views). As well, because stored procs often return result-sets, a little more time is spend on describing what that result-set looks like before moving on to **Assert** things about it.

The `RunUnitTests` proc accepts the following input XML:

`exec RunUnitTests '<unittests>`
-	`<test name="Name of this test">`
	-	`<prefix `
		-	`dev="dbo."` _(optional)_  
			The prefix for tables of the development environment that need to be mocked
		-	`ut="#unittest_" />` **(mandatory)**  
			The prefix for the temporary tables that the UnitTest works on, should be the same as the (deployed) UnitTest-variant of the stored proc.
	-	`<mock>`_(optional)_  
		Contains a list of tables that should be mocked for the test. The tag-name is the table name (without any prefixes) and attributes with values are column-names with the mocked value. For multiple rows you simply repeat the tag:
		-	`<customer id="1" name="John Doe" />`
		-	`<customer id="2" name="Jane Doe" />`
		-	`<order id="1" customer_id="2" vat_percent="10" />`
		-	`<orderline id="1" order_id="1" description="staplers" qty="5" unit_price="2.20" subtotal="11" />`
		-	`<orderline id="2" order_id="1" description="marker (red)" qty="3" unit_price="1.20" subtotal="3.60" />`
	-	`</mock>`
	-	`<act>exec TotalsPerCustomer_UTST</act>` **(mandatory)**  
		A snippet of T-SQL that invokes the procedure being tested. This should invoke the UnitTest-variant of the stored proc.
	-	`<returns>` _(optional)_  
		If the proc that's being tested returns a result-set (of even just one value), use this section to describe the list of columns and their type that the proc returns. Like the `<mock>` section above, the tag-name itself is used, this time as a column name. The attribute `type=""` is expected and must contain the type of that column. These columns are added to a table called `#utreturns`, which can then be queried in the `<assert>` statements.
		-	`<customer_name type="nvarchar(255)" />`
		-	`<orders type="int" />`
		-	`<total_excl_vat type="decimal(5,2)" />`
		-	`<total_incl_vat type="decimal(5,2)" />`
	-	`</returns>`
	-	`<assert` **(mandatory)**  
		A T-SQL snippet that should return a single value to be tested against the condition of the `expected` attribute below.
		-	`expected=" = 2">`  
			The attribute can contain any valid T-SQL condition, like `" = 'expected value'"`, `" <> 'wrong value'"`, `" > 1"`, `" like '%this%'"`, `" between 0 and 10"`, etc.
		-	`select count(*) from #utreturns`
	-	`</assert>`
	-	`<assert expected=" = 14.60">select total_excl_vat from #utreturns where customer_name = ''Jane Doe''</assert>`  
		_(single quotes doubled here because this xml is defined with a single quote delimited string)_
	-	`<assert expected=" = 16.06">select total_incl_vat from #utreturns where customer_name = ''Jane Doe''</assert>`
-	`</test>`

`</unittests>'`

Interpret test-results
----------------------

Running the above UnitTest might yield a result-set like this:

| id  |      name       |                                 test                                 | expected | actual | pass |                        testxml                        |             fullquery             |
| --- | --------------- | -------------------------------------------------------------------- | -------- | ------ | ---- | ----------------------------------------------------- | --------------------------------- |
|  1  |Name of this test|select total_excl_vat from #utreturns where customer_name = 'Jane Doe'|  = 14.60 |  14.6  |  1   |[<test name="Name of this ...](#interpret-test-results)|if object_id('tempdb..#unittest_...|
|  2  |Name of this test|select total_incl_vat from #utreturns where customer_name = 'Jane Doe'|  = 16.06 |  1.46  |  0   |[<test name="Name of this ...](#interpret-test-results)|if object_id('tempdb..#unittest_...|

It looks like the stored proc we're testing calculates the VAT correctly but doesn't add it to the total. Here's a detailed description of all the return columns:

1.	**id**  
	Auto-incremented number based on the order of **Assert** operations performed.
2.	**name**  
	The name as defined in the `<test name=""` attribute. _(same for all **Assertions** of the same test)_
3.	**test**  
	The value that was tested in the **Assertion** as defined in the `<assert>`-body.
4.	**expected**  
	The condition that the tested value is expected to meet as defined in the `<assert expected=""` attribute.
5.	**actual**  
	What the tested value actually returned. Or in case of an error, the contents of `error_message()`.
6.	**pass** _(bit)_  
	Whether this **Assertion** passed the test. Contains `1` if **actual** meets condition **expected** and no error was caught, otherwise contains `0`.
7.	**testxml**  
	The xml-snippet that this test was based on. Contains only the xml for that test, not the entire `<unittests>` xml document. _(same for all **Assertions** of the same test)_
8.	**fullquery**  
	The T-SQL query that was run to invoke the UnitTest. Useful for examining or debugging tests that don't pass. The query contains indentation which you might want to keep by [retaining CR/LF on copy](https://www.c-sharpcorner.com/blogs/retain-carriage-return-and-line-feeds-on-copy-or-save-in-sql-server-2016) in SSMS. _(same for all **Assertions** of the same test)_
