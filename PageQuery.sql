
/**
	这是一个几乎没有任何限制及额外操作的通用分页存储过程	
	使用方式：假设传入SQL查询有N个结果集，我会将最后一个查询结果作为要分页的结果进行处理并返回N+1个结果集。
			我会按照原有sql顺序返回结果集，并再第N个结果集（最终我认为要分页的结果集）前插入一个分页信息结果集（所以是返回N+1个结果集）。
			如果结果只有一个结果集，也是同理
	注意事项：	1.如果你传入的@sql参数存在多个结果集，那么每个sql需要用英文分号;进行分割。
				2.传入的sql语句分号（;）具有特殊作用，所以sql语句中的''，/ *** /等。不能出现分号（;）否则会导致sql执行异常（特别是要执行分页的sql）
				3.不允许出现--注释。
				

	2025-09-02	1.第四版,也是最终版优化（以前是使用into临时表处理的，有很多问题处理起来很麻烦，现在将sql语句的order by 截取出来处理）。
	2025-10-22	1.第五版优化。优化思路：将要分页的数据写入临时表。然后再临时表中按照结果集顺序添加一个自增列并作为最终排序字段。如果查询的结果集中已存在自增列，那么则转为截取order语句，来排序
*/
create procedure [dbo].[PageQuery]       
	@page   int=1,				--要显示的页码   
	@size   int=20,				--每页的大小   
	@sql   nvarchar(4000)		--要执行的sql语句 
as   

if(1 = charindex('(',ltrim(@sql))) begin
	THROW 777777,'执行sql不能用（）包裹',1
end

if( len(@sql) > 4000) begin
	THROW 777777,'sql太长了，弄短点！',1
end

  
declare @execTime varchar(30)=SYSDATETIME()
declare @itemTime varchar(30)
  

  
set @sql= replace(@sql,'<','[lt]')
set @sql= replace(@sql,'>','[rt]')
set @sql= replace(@sql,'&','[@]')


  
create table #sql( idx int not null,sql nvarchar(4000) not null )



-- 不好判断;  暂时不判断
--insert into #sql values(0,@sql)
--if((select count(*) from #sql where sql like '%''%;%''%')>0) begin
--	THROW 777777,'不允许在字符串中出现分号（;）',1
--end
--if((select count(*) from #sql where sql like '%/*%;%*/%')>0) begin
--	THROW 777777,'不允许在注释中出现分号（;）',1
--end
--delete #sql

SELECT IDENTITY(int,1,1) as idx ,convert(nvarchar(4000),B.val) as sql into #sql_tmp
FROM (
	(SELECT [value] = CONVERT(XML, '<v>' + REPLACE(@sql, ';', '</v><v>') + '</v>') ) A 
OUTER APPLY
    (SELECT val = N.v.value('.', 'varchar(4000)') FROM A.[value].nodes('/v') N(v) ) B
)

insert into #sql
select idx,sql from #sql_tmp order by idx


delete #sql where len(ltrim(rtrim(sql)))=0


declare @sql_item varchar(4000)
declare @idx int
 
select top 1 @sql_item=lower(sql),@idx=idx from #sql order by idx desc

update #sql set idx=@idx+100 where idx=@idx
set @idx=@idx+100


create table #filter(id int identity(1,1) primary key not null,t varchar(4),s int,e int)


set @itemTime=SYSDATETIME()

declare @keyword_left int = charindex('/*',@sql_item)
declare @keyword int = 0
declare @keyword_right int = charindex('*/',@sql_item)
declare @isWhile varchar(1)='y'

  
while(@keyword_left>0) begin
	insert into #filter(t,s) values('注释',@keyword_left)
	set @keyword_left = charindex('/*',@sql_item,@keyword_left+2)
end
while(@keyword_right>0) begin
	update #filter set e=@keyword_right+2  where t='注释' and s=(select top 1 s from #filter where t='注释' and e is null order by s desc)
	set @keyword_right = charindex('*/',@sql_item,@keyword_right+2)
end

set @keyword_left= charindex('''',@sql_item)
while(@keyword_left>0) begin
	set @keyword_right = charindex('''',@sql_item,@keyword_left+1)+1;
	insert into #filter(t,s,e) values('字符',@keyword_left,@keyword_right)
	set @keyword_left = charindex('''',@sql_item,@keyword_right);
end

set @keyword_left= charindex('(',@sql_item)
if (@keyword_left > 0) begin
	declare @next_left int = 0
	declare @next_right int = 0
	while(@isWhile='y') begin		
		set @next_left  = charindex('(',@sql_item,@keyword_left + 1)
		set @next_right  = charindex(')',@sql_item,@keyword_left + 1)
		if(@next_right = 0) begin
			set @isWhile='n';
		end else begin
			if(@next_left<@next_right and @next_left <> 0) begin
				insert into #filter(t,s) values('括号',@next_left)
				set @keyword_left = @next_left+1
			end else begin
				update #filter set e=@next_right+1  where t='括号' and s=(select top 1 s from #filter where t='括号' and e is null order by s desc)
				set @keyword_left = @next_right+1
			end
		end
	end
end



declare @i int =1;
declare @count int = (select count(*) from #filter)
declare @id int =0;
declare @s int=0
declare @e int=0

set @keyword = charindex('--',@sql_item);  
while(@keyword>0) begin 
	select @id=count(*) from #filter where @keyword>=s and @keyword<e and t in ('字符','注释')  
	if(@id>0 and @keyword>0) begin
		set @keyword = charindex('--',@sql_item,@keyword+2);	
	end else begin 
		THROW 777777,'不允许出现注释（--）',1
		return ;
	end
end



declare @fromStartIndex int =0
set @keyword  = charindex('from',@sql_item)
if(@keyword > 0 ) begin	
	set @isWhile='y'
	while(@isWhile = 'y') begin
		select @id=count(*) from #filter where @keyword>=s and @keyword<e
		if(@id>0 and @keyword>0) begin
			set @keyword = charindex('from',@sql_item,@keyword+2);
		end else begin
			set @isWhile='n';
		end
	end
	set @fromStartIndex = @keyword-1;
 end else begin
	set @fromStartIndex = @keyword-1;
 end


set @keyword = charindex('order by',@sql_item);
if( @keyword > 0 ) begin	
	while(@keyword > 0) begin
		select @id=id,@s=s,@e=e from #filter where @keyword>=s and @keyword<e
		if((select count(*) from #filter where @keyword>=s and @keyword<e)=0) begin
			set @id=0
		end
		if(@e>0 and @s>0 and @id>0) begin
			set @keyword = charindex('order by',@sql_item,@e+1);	
			delete #filter where id=@id
		end else begin
			if(charindex('order by',@sql_item,@keyword+1)>0) begin
				set @keyword = charindex('order by',@sql_item,@keyword+1);
			end else begin
				break;
			end
		end
	end	
end
declare @orderStartIndex int =0
if( @keyword > 0 ) begin
	set @orderStartIndex=@keyword
end

print 'sql解析：'+ convert(varchar(10), datediff( ms, @itemTime,SYSDATETIME()))+'毫秒'


declare @temp_sql varchar(4000)=''
if(@orderStartIndex >0) begin
	set @temp_sql= SUBSTRING(@sql_item,0,@orderStartIndex)
end else begin
	set @temp_sql= @sql_item
end

select top 1 @sql_item=sql from #sql where idx=@idx

begin try	
	declare @tableName varchar(12)='#'+left(NewId(),8)
	declare @execSql nvarchar(max)
	set @execSql =ISNULL((SELECT  ';'+sql FROM #sql where idx <@idx order by idx FOR XML PATH('')),'')
	set @execSql = @execSql + SUBSTRING(@sql_item,0,@fromStartIndex)+',IDENTITY(int,1,1) as N_7777 into '+@tableName+' '+SUBSTRING(@sql_item,@fromStartIndex,len(@sql_item))
	set @execSql = replace(replace(replace(@execSql,'[lt]','<'),'[rt]','>'),'[@]','&')	
	set @execSql = @execSql + ';select '+convert(nvarchar(10) ,@page)+' as page,'+convert(nvarchar(10) ,@size)+' as size,CEILING(count(*)/convert(float,'+convert(nvarchar(10) ,@size)+')) as allPage,count(*) as allSize from '+@tableName
	set @execSql = @execSql + ';select * from '+@tableName+' order by N_7777 offset '+convert(nvarchar(10) ,((@page - 1) * @size))+' row fetch next '+convert(nvarchar(10) ,@size)+' row only'
	print @execSql
	exec sp_executesql @execSql	
	print '使用临时表处理'
	print '总用时：'+ convert(varchar(10), datediff( ms, @execTime,SYSDATETIME()))+'毫秒'
	return;
end try
begin catch
	insert into #sql(idx,sql) values(@idx-2,'declare @allSize int=0;select @allSize=count(*) from ('+@temp_sql+') as T7777')
	insert into #sql(idx,sql) values(@idx-1,'select '+convert(nvarchar(10) ,@page)+' as page,'+convert(nvarchar(10) ,@size)+' as size,CEILING(@allSize/convert(float,'+convert(nvarchar(10) ,@size)+')) as allPage,@allSize as allSize ')
	if(@orderStartIndex >0) begin
		set @sql_item = @sql_item+' offset '+convert(nvarchar(10) ,((@page - 1) * @size))+' row fetch next '+convert(nvarchar(10) ,@size)+' row only'
	end else begin
		set @sql_item = @sql_item+' ORDER BY (SELECT 1) offset '+convert(nvarchar(10) ,((@page - 1) * @size))+' row fetch next '+convert(nvarchar(10) ,@size)+' row only'	
	end
	print '使用普通查询处理'
end catch






update #sql set sql=@sql_item where idx=@idx


 declare @nsql nvarchar(max)
 set @nsql=(SELECT  ';'+sql FROM #sql order by idx FOR XML PATH(''))
 
set @nsql= replace(replace(replace(@nsql,'[lt]','<'),'[rt]','>'),'[@]','&')

print @nsql

begin try
	exec sp_executesql @nsql
end try
begin catch
	DECLARE @ErrorMessage NVARCHAR(4000);
	DECLARE @ErrorSeverity INT;
	DECLARE @ErrorState INT;
	SELECT @ErrorMessage = ERROR_MESSAGE(),@ErrorSeverity = ERROR_SEVERITY(),@ErrorState = ERROR_STATE();
	RAISERROR (@ErrorMessage,@ErrorSeverity, @ErrorState );
	return ;
end catch

print '总用时：'+ convert(varchar(10), datediff( ms, @execTime,SYSDATETIME()))+'毫秒'








