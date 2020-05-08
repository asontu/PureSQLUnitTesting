if object_id(N'dbo.RunUnitTests') is not null
	drop procedure dbo.RunUnitTests

set ansi_nulls on
go
set quoted_identifier on
go
/**	Run UnitTests based on input xml
 *	Example input xml:
 *
 *	<unittests>
 *		<test name="name of test">
 *			<prefix dev="tblprefix_" ut="#" />
 *			<mock>
 *				<mytable mycol="testvalue" />
 *			</mock>
 *			<act>exec MyStoredProc</act>
 *			<returns>
 *				<returncol type="varchar(10)" />
 *			</returns>
 *			<assert expected=" = 'testvalue'">
 *				select returncol from #utreturns
 *			</assert>
 *		</test>
 *	</unittests>
 *
 * The above snippet would mock existing table
 * [tbleprefix_mytable] with 1 row of data. This
 * row would have "testvalue" for its [mycol]-
 * column.
 * It would then run exec MyStoredProc and
 * expect a resultset of 1 column with type
 * varchar(10). It would then look at 
 * (select returncol from #utreturns) and assert
 * that it = 'testvalue'.
 */
create procedure RunUnitTests(@unittests xml)
as begin
	set nocount on

	if object_id('tempdb..#testresults') is not null
		drop table #testresults

	create table #testresults (
		id int identity,
		name nvarchar(255),
		test nvarchar(255),
		expected nvarchar(255),
		actual nvarchar(255),
		pass bit,
		testxml xml,
		fullquery nvarchar(max)
	)

	declare @nl nchar(2) = char(13) + char(10)
	declare @testxml xml
	declare @name nvarchar(255)
	declare @utprefix nvarchar(255)
	declare @envprefix nvarchar(255)
	declare @sqlpre nvarchar(max)
	declare @sqlact nvarchar(max)
	declare @sqlassert nvarchar(max)
	declare @sqlpost nvarchar(max)
	declare @sqltotal nvarchar(max)

	declare TestCursor cursor local forward_only static read_only for
		select te.st.query('.')
		from @unittests.nodes('unittests/test')te(st)
	
		open TestCursor
		fetch next from TestCursor into @testxml
		while @@fetch_status = 0 begin

			set @name = @testxml.value('(test/@name)[1]', 'nvarchar(255)')
			set @utprefix = @testxml.value('(test/prefix/@ut)[1]', 'nvarchar(255)')
			set @envprefix = @testxml.value('(test/prefix/@dev)[1]', 'nvarchar(255)')

			;with mockdata as (
				select
					tablename = mo.ck.value('local-name(.)', 'nvarchar(255)'),
					tablecolumns =
					(
						select ', ' +
							'[' + co.l.value('local-name(.)', 'nvarchar(255)') + ']'
						from mo.ck.nodes('./@*')co(l)
						order by co.l.value('local-name(.)', 'nvarchar(255)')
						for xml path(''), type
					)
					.value('fn:substring(., 3)', 'nvarchar(max)'),
					tablevalues =
					(
						select ', ' + 
							'''' + co.l.value('.', 'nvarchar(255)') + ''''
						from mo.ck.nodes('./@*')co(l)
						order by co.l.value('local-name(.)', 'nvarchar(255)')
						for xml path(''), type
					)
					.value('fn:substring(., 3)', 'nvarchar(max)')
				from @testxml.nodes('test/mock/*')mo(ck)
			), returntable as (
				select 
					colname = ret.urns.value('local-name(.)', 'nvarchar(50)'),
					coltype = ret.urns.value('./@type', 'nvarchar(50)')
				from @testxml.nodes('test/returns/*')ret(urns)
			), assertions as (
				select
					examen   = ass.ert.value('.', 'nvarchar(255)'),
					expected = ass.ert.value('@expected', 'nvarchar(1000)')
				from @testxml.nodes('test/assert')ass(ert)
			)
			select
				@sqlpost =
				(
					select
						'if object_id(''tempdb..' + @utprefix + t.tablename + ''') is not null' + @nl +
						'	drop table ' + @utprefix + t.tablename + @nl + @nl
					from mockdata t
					group by t.tablename
					for xml path(''), type
				)
				.value('.', 'nvarchar(max)'),
				@sqlpre = 
				(
					select @nl + @nl +
						'select top 0 *' + @nl + 
						'into ' + @utprefix  + t.tablename + @nl +
						'from ' + @envprefix + t.tablename + @nl +
						(
							select @nl +
								'insert into ' + @utprefix + c.tablename + '(' + c.tablecolumns + ')' + @nl +
								'values' +
								(
									select ',' + @nl +
										'	(' + d.tablevalues + ')'
									from mockdata d
									where d.tablename = c.tablename
									  and d.tablecolumns = c.tablecolumns
									for xml path(''), type
								)
								.value('fn:substring(., 2)', 'nvarchar(max)')
							from mockdata c
							where c.tablename = t.tablename
							group by c.tablename, c.tablecolumns
							for xml path(''), type
						)
						.value('.', 'nvarchar(max)')
					from mockdata t
					group by t.tablename
					for xml path(''), type
				)
				.value('.', 'nvarchar(max)') + @nl + @nl +
				case (select count(*) from returntable) when 0 then '' else
					'if object_id(''tempdb..#utreturns'') is not null' + @nl +
					'	drop table #utreturns' + @nl + @nl +
					'create table #utreturns (' + @nl +
					(
						select ',' + @nl +
							'	' + colname + ' ' + coltype
						from returntable
						for xml path(''), type
					)
					.value('fn:substring(., 4)', 'nvarchar(max)') + @nl +
					')'
				end,
				@sqlact = 'declare @error varchar(1000)' + @nl +
				'begin try' + @nl +
				case (select count(*) from returntable) when 0 then '' else
					'	insert into #utreturns(' +
					(
						select ',' + colname
						from returntable
						for xml path(''), type
					)
					.value('fn:substring(., 2)', 'nvarchar(max)') + ')' + @nl
				end +
				'	' + trim(@testxml.value('(test/act)[1]', 'nvarchar(max)')) + @nl +
				'end try' + @nl +
				'begin catch' + @nl +
				'	set @error = error_message()' + @nl +
				'end catch',
				@sqlassert =
				(
					select @nl + @nl +
						'insert into #testresults(name, test, expected, actual, pass, testxml, fullquery)' + @nl +
						'select ' + @nl +
						'	''' + replace(@name,    '''', '''''') + ''',' + @nl +
						'	''' + replace(examen,   '''', '''''') + ''',' + @nl +
						'	''' + replace(expected, '''', '''''') + ''',' + @nl +
						'	isnull(@error, cast((' + examen + ') as varchar(255))),' + @nl +
						'	isnull(case when @error is not null then 0 when (' + examen + ') ' + expected + ' then 1 end, 0),' + @nl +
						'	@testxml,' + @nl +
						'	@sqltotal'
					from assertions
					for xml path(''), type
				)
				.value('.', 'nvarchar(max)')

			set @sqltotal = @sqlpost + @sqlpre + @nl + @nl + @sqlact + @sqlassert + @nl + @nl + @sqlpost

			exec sp_executesql @sqltotal,
				N'@testxml xml, @sqltotal nvarchar(max)', @testxml, @sqltotal

			fetch next from TestCursor into @testxml
		end
		close TestCursor
	deallocate TestCursor

	select *
	from #testresults
	order by id

	if object_id('tempdb..#testresults') is not null
		drop table #testresults
end
go