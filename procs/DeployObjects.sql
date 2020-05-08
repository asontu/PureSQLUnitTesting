if object_id(N'dbo.DeployObjects') is not null
	drop procedure dbo.DeployObjects

set ansi_nulls on
go
set quoted_identifier on
go
/**	Deploys existing stored procs, views and functions.
 */
create procedure DeployObjects(@deployment xml)
as begin
	set nocount on

	declare @objectNameFrom nvarchar(127),
			@objectNameTo nvarchar(127),
			@sql nvarchar(max),
			@continue bit = 1

	declare @types table (
		type char(2) collate Latin1_General_CI_AS_KS_WS,
		name varchar(50)
	)

	insert into @types
	values ('P', 'procedure'),
		('IF', 'function'),
		('V', 'view')

	declare DeployCursor cursor local forward_only static read_only for
		select de.ploy.value('.', 'nvarchar(127)')
		from @deployment.nodes('deployment/deploy')de(ploy)
	
		open DeployCursor
		fetch next from DeployCursor into @objectNameFrom
		while @@fetch_status = 0 and @continue = 1 begin

			set @sql = object_definition(object_id(@objectNameFrom))
			set @objectNameTo = @objectNameFrom

			if @sql is null begin
				set @continue = 0
				raiserror(N'No definition found for %s to deploy', 11, 1, @objectNameFrom)
			end else begin

				with replacements as (
					select
						de.ploy.value('@from', 'nvarchar(50)') search,
						de.ploy.value('@to', 'nvarchar(50)') replacement
					from @deployment.nodes('deployment/replace')de(ploy)
				)
				select @sql = replace(@sql, search, replacement),
					@objectNameTo = replace(@objectNameTo, search, replacement)
				from replacements

				if object_id(@objectNameTo) is not null begin
					select @sql = stuff(@sql, charindex('create ' + t.name, @sql), len('create'), 'alter')
					from sys.objects so
					join @types t on t.type = so.type
					where so.object_id = object_id(@objectNameTo)
				end

				exec sp_executesql @sql

			end

			fetch next from DeployCursor into @objectNameFrom
		end
		close DeployCursor
	deallocate DeployCursor
end
go

