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

--*************MySQL and Redis Initialized*************--

function mysql_get_record(k, v)
	local sql = 'SELECT * FROM '..db_slave_config.table..' WHERE '..k..' = \''..v..'\';'
	local res, err, errno, sqlstate = db_slave:query(sql)
	return res
end

function mysql_get_record_by_username(username)
	local res = mysql_get_record('username', username)
end
