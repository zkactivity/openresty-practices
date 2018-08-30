local args = ngx.req.get_uri_args()
local action = args['action']

local mysql = require 'resty.mysql'
local cjson = require 'cjson'

local db_master_config = {
	host = '172.18.0.8',
	port = 3306,
	database = 'users',
	user = 'root',
	password = 'su123456',
	table = 'account'
}

local db_slave_config = {
	host = '172.18.0.9',
	port = 3306,
	database = 'users',
	user = 'root',
	password = 'su123456',
	table = 'account'
}

--[[
local db_slave_config = {
	host = '172.18.0.8',
	port = 3306,
	database = 'test',
	user = 'root',
	password = '123456',
	table = 'tb_user'
}
]]--

local db_master, err = mysql:new()
local db_slave, err = mysql:new()
if not db_master or not db_slave then
	ngx.say(cjson.encode({code=500, message='未安装mysql客户端'}))
	return
end

local ok, err, errno, sqlstate = db_master:connect({
	host = db_master_config.host, 
	port = db_master_config.port, 
	database = db_master_config.database, 
	user = db_master_config.user, 
	password = db_master_config.password})
if not ok then
	ngx.say(cjson.encode({code=500, message='mysql主服务器连接不上  :  '..err}))
	return
end

local ok, err, errno, sqlstate = db_slave:connect({
	host = db_slave_config.host, 
	port = db_slave_config.port, 
	database = db_slave_config.database, 
	user = db_slave_config.user, 
	password = db_slave_config.password})
if not ok then
	ngx.say(cjson.encode({code=500, message='mysql从服务器连接不上  :  '..err}))
	return
end

--[[************************************************************************************************************]]--
local redis_cluster = require "resty.rediscluster"

local  redis_cluster_config = {
			serv_list = {
				{ip = "172.18.0.2", port = 6379},
				{ip = "172.18.0.3", port = 6379},
				{ip = "172.18.0.4", port = 6379},
				{ip = "172.18.0.5", port = 6379},
				{ip = "172.18.0.6", port = 6379},
				{ip = "172.18.0.7", port = 6379},
			},
			pool_timeout_ms = 10000, -- 连接池空闲时间
			pool_count = 200, -- 连接池大小
			slow_query_time_ms = 3000 -- 慢查询阈值
		}

local cluster = redis_cluster:new_cluster(redis_cluster_config)
if not cluster then 
	ngx.say('Redis cluster current invalid')
	return
end

function get_desc_from_redis_cluster()
	ngx.req.read_body()
	local post_args = ngx.req.get_post_args()
	local username = post_args['username']
	if not username then
		ngx.say(cjson.encode({code=400, message='缺少用户名'}))
		return
	end
	if cluster:exists(username) == 1 then
		local value = cluster:get(username)
		ngx.say(cjson.encode({code=200, message="", data=value}))
	else
		--need to update cache
		ngx.say('Need to update the redis cluster cache')
		cache_mysql_record_to_redis('username', username)
	end
end

function cache_mysql_record_to_redis(k, v)
	local sql = 'SELECT * FROM '..db_slave_config.table..' WHERE '..k..' = \''..v..'\';'
	local res, err, errno, sqlstate = db_slave:query(sql)
	if not res then 
		ngx.say(cjson.encode({code=500, message='没有数据'}))
	else
		ngx.say(cjson.encode({code=200, message="", data=res}))
		cluster:set(v, res)
	end
end

--[[
function set_desc_to_redis_cluster()

end
cluster:set("key", "myvalue")

local value = cluster:get("key")

ngx.print(value)
]]--
--[[************************************************************************************************************]]--

function find() 
	local data = {}
	ngx.req.read_body()
	local post_args = ngx.req.get_post_args()
	for k,v in pairs(post_args) do
		--ngx.say("[POST] key:", k, " v:", v)
		local sql = 'SELECT * FROM '..db_slave_config.table..' WHERE '..k..' = \''..v..'\';';
		--ngx.say('Current SQL is: '..sql);
		local res, err, errno, sqlstate = db_slave:query(sql)
		if not res then
			ngx.say(cjson.encode({code=200, message=err, data=nil}))
		else
			ngx.say(cjson.encode({code=200, message="", data=res}))
		end
	end
end

function get_self_desc()
	local data = {}
	ngx.req.read_body();
	local post_args = ngx.req.get_post_args()
	username = post_args['username']
	if not username then
		ngx.say(cjson.encode({code=400, message='错误的语法'}))
		return
	end
	local sql = 'SELECT selfdesc FROM '..db_slave_config.table..' WHERE username =\''..username..'\'';
	local res, err, errno, sqlstate = db_slave:query(sql)
	if not res then
		ngx.say(cjson.encode({code=200, message=err, data=nil}))
	else
		ngx.say(cjson.encode({code=200, message="", data=res}))
	end
end

function set_self_desc()
	local data = {}
	ngx.req.read_body();
	local post_args = ngx.req.get_post_args()
	username = post_args['username']
	if not username then
		ngx.say(cjson.encode({code=400, message='错误的语法'}))
		return
	end

	local newselfdesc = post_args['newselfdesc']

	local sql = 'UPDATE '..db_slave_config.table..' SET selfdesc = \''..newselfdesc..'\' WHERE username =\''..username..'\'';
	local res, err, errno, sqlstate = db_slave:query(sql)
	if not res then
		ngx.say(cjson.encode({code=200, message=err, data=nil}))
	else
		ngx.say(cjson.encode({code=200, message="", data=res}))
	end
end

-- 列表
function lists()
	local data = {}
	ngx.req.read_body()
	local posts = ngx.req.get_post_args()
	local page, pagesize, offset = 0, 15, 0
	if posts.page then
		page = posts.page
	end
	if posts.pagesize then
		pagesize = posts.pagesize
	end
	if page > 1 then
		offset = (page -1)*pagesize
	end

	local res, err, errno, sqlstate = db_slave:query('SELECT * FROM `'..db_slave_config.table..'` LIMIT '..offset..','..pagesize)
	if not res then
		ngx.say(cjson.encode({code=200, message=err, data=nil}))
	else
		ngx.say(cjson.encode({code=200, message="", data=res}))
	end
	
end

-- 添加操作
function add()
	ngx.req.read_body()
	local data = ngx.req.get_post_args()
	if  data.name ~= nil then
		local sql = 'INSERT INTO '..db_master_config.table..'(name) VALUES ("'..data.name..'")';
		local res, err, errno, sqlstate = db_master:query(sql)
		if not res then
			ngx.say(cjson.encode({code=501, message="添加失败"..err..';sql:'..sql, data=nil}))
		else
			ngx.say(cjson.encode({code=200, message="添加成功", data=res.insert_id}))
		end
	else
		ngx.say(cjson.encode({code=501, message="参数不对", data=nil}))
	end
end

-- 详情页
function detail()
	ngx.req.read_body()
	local post_args = ngx.req.get_post_args()
	if post_args.id ~= nil then
		local data, err, errno, sqlstate = db_slave:query('SELECT * FROM '..db_slave_config.table..' WHERE id='..post_args.id..' LIMIT 1', 1)
		local res = {}
		if data ~= nil then
			res.code = 200
			res.message = '请求成功'
			res.data = data[1]
		else
			res.code = 502
			res.message = '没有数据'
			res.data = data
		end
		ngx.say(cjson.encode(res))
	else
		ngx.say(cjson.encode({code = 501, message = '参数错误', data = nil}))
	end
	
end

-- 删除操作
function delete()
	ngx.req.read_body()
	local data = ngx.req.get_post_args()
	if data.id ~= nil then
		local res, err, errno, sqlstate = db_master:query('DELETE FROM '..db_slave_config.table..' WHERE id='..data.id)
		if not res or res.affected_rows < 1 then
			ngx.say(cjson.encode({code = 504, message = '删除失败', data = nil}))
		else
			ngx.say(cjson.encode({code = 200, message = '修改成功', data = nil}))
		end
	else
		ngx.say(cjson.encode({code = 501, message = '参数错误', data = nil}))
	end
end

-- 修改操作
function update()
	ngx.req.read_body()
	local post_args = ngx.req.get_post_args()
	if post_args.id ~= nil and post_args.name ~= nil then
		local res, err, errno, sqlstate = db_master:query('UPDATE '..db_slave_config.table..' SET `name` = "'..post_args.name..'" WHERE id='..post_args.id)
		if  not res or res.affected_rows < 1 then
			ngx.say(cjson.encode({code = 504, message = '修改失败', data = nil}));
		else
			ngx.say(cjson.encode({code = 200, message = '修改成功', data = nil}))
		end
	else
		ngx.say(cjson.encode({code = 501, message = '参数错误', data = nil}));
	end
end
if action == 'lists' then
	lists()
elseif action == 'detail' then
	detail()
elseif action == 'add' then
	add()
elseif action == 'delete' then
	delete()
elseif action == 'update' then
	update()
elseif action == 'find' then
	find()
elseif action == 'getselfdesc' then
	get_self_desc()
elseif action == 'setselfdesc' then
	set_self_desc()
elseif action == 'readrediscluster' then
	get_desc_from_redis_cluster()
elseif action == 'cache' then
	cache_mysql_record_to_redis('username', 'mike');
end

