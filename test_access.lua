package.path = "/usr/local/nginx/lua/?.lua;/usr/local/nginx/lua/lib/?.lua;"

-- flag
local flag = true
-- redis
local redis = require "resty.redis"
local conn = redis.new()
local host = '10.5.0.80'
local port = '6300'
local auth = '123123'
local db = '1'

-- config
local mx_day = 100
local mx_hou = 50
local mx_min = 25
local mx_sec = 5
local block_times = 5
local block_days = 4


-- get ip
local function get_client_ip()
    local ip = ngx.var.http_x_forwarded_for or ngx.var.remote_addr
    return ip
end

-- init key
local function init_keys(conn, key, t)
    conn:set(key,0)
    conn:expire(key,t)
end

-- block ip & capture
local function block_ip_2_cap(conn, ip)
    conn:init_pipeline()
    conn:set('blk:'..ip, 1)
    conn:expire('blk:'..ip, block_days*24*3600)
    init_keys(conn, 'vis:hh:'..ip, 3600)
    init_keys(conn, 'vis:dd:'..ip, 3600*24)
    init_keys(conn, 'vis:mm:'..ip, 60)
    init_keys(conn, 'vis:ss:'..ip, 1)
    res, err = conn:commit_pipeline()
end

-- close redis by connecting pool
local function close_redis(red)  
    if not red then  
        return  
    end   
    local pool_max_idle_time = 10000  --毫秒  
    local pool_size =  100 --连接池大小  
    local ok, err = red:set_keepalive(pool_max_idle_time, pool_size)  
    if not ok then  
        red:close()
    end
end

function main() 
    conn:set_timeout(2000)
    local ok = conn.connect(conn,host,port)
    if not ok then
        return -1
    end
    ok = conn:auth(auth)
    if not ok then 
        return -1
    end

    conn:select(db)

    local ip = get_client_ip()
    local uri = ngx.var.request_uri
    local scheme = ngx.var.scheme
    local headers = ngx.req.get_headers()  
    local host = headers['host']
    local ua = headers['user-agent']    

    local resp = conn:sismember('whitelist',ip)  
    if tonumber(resp) == 1 then
	return 0
    end
    
    if ua == nil or host == nil then
        local source = scheme..'://'..host..uri
        local dest = "http://cap.169kang.com/index.php?continue="..source
        block_ip_2_cap(conn, ip)
        ngx.redirect(dest,302)
        return -1
    end
   
    local enterblk, err = conn:get('enterblk:'..ip)
    if enterblk ~= ngx.null and tonumber(enterblk) >= block_times  then
        conn:expire('enterblk:'..ip, block_days*24*3600)
        local source = scheme..'://'..host..uri
        local dest = "http://cap.169kang.com/index.php?continue="..source
        ngx.redirect('http://cap.169kang.com/404.html',302)
        return -1
    end

    if string.find(ua,'Baiduspider') or string.find(ua,'360spider') then return 0 end
    if string.find(ua, 'Sogou web spider') or string.find(ua, 'YisouSpider') then return 0 end
    if string.find(ua,'360so')  then return 0 end

    -- sogou ---
    if 'Mozilla/5.0 (Linux; U; Android 4.1.1; zh-CN; GT-N7100 Build/JRO03C) AppleWebKit/534.31 (KHTML, like Gecko) UCBrowser/9.3.0.321 U3/0.8.0 Mobile Safari/534.31' == ua then return 0 end
    if 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:51.0) Gecko/20100101 Firefox/51.0' == ua then return 0 end
    
    -- mip --
    if 'Mozilla/5.0 (Linux;u;Android 4.2.2;zh-cn;) AppleWebKit/534.46 (KHTML,like Gecko) Version/5.1 Mobile Safari/10600.6.3 (compatible; baidumib;mip; + https://www.mipengine.org)' == ua then return 0 end
     
    local isblk, err = conn:get('blk:'..ip)
    if isblk ~= ngx.null then
        conn:incr('blk:'..ip)
        local source = scheme..'://'..host..uri
        local dest = "http://cap.169kang.com/index.php?continue="..source
        ngx.redirect(dest,302) 
        return -1
    end
    
    local ss, err = conn:get('vis:ss:'..ip)    
    local mm, err = conn:get('vis:mm:'..ip)
    local hh, err = conn:get('vis:hh:'..ip)  
    local dd, err = conn:get('vis:dd:'..ip)

    if dd == ngx.null then
        conn:init_pipeline()
        init_keys(conn, 'vis:ss:'..ip, 1)
        init_keys(conn, 'vis:mm:'..ip, 60)
        init_keys(conn, 'vis:hh:'..ip, 3600)
        init_keys(conn, 'vis:dd:'..ip, 3600*24)
        local res, err = conn:commit_pipeline()
        if res == ngx.null then
           return -1
        end
        dd, err = conn:get('vis:dd:'..ip)
        ss, err = conn:get('vis:ss:'..ip)
        mm, err = conn:get('vis:mm:'..ip)
        hh, err = conn:get('vis:hh:'..ip)
    end
    
    if hh == ngx.null then
        conn:init_pipeline()
        init_keys(conn, 'vis:ss:'..ip, 1)
        init_keys(conn, 'vis:mm:'..ip, 60) 
        init_keys(conn, 'vis:hh:'..ip, 3600)
        local res, err = conn:commit_pipeline()
        if res == ngx.null then
            return -1
        end
        hh, err = conn:get('vis:hh:'..ip)
        ss, err = conn:get('vis:ss:'..ip)
        mm, err = conn:get('vis:mm:'..ip)
    end
   
    if mm == ngx.null then
        conn:init_pipeline()
        init_keys(conn, 'vis:ss:'..ip, 1)
        init_keys(conn, 'vis:mm:'..ip, 60)
        local res, err = conn:commit_pipeline()
        if res == ngx.null then
            return -1
        end
        mm, err = conn:get('vis:mm:'..ip)
        ss, err = conn:get('vis:ss:'..ip)
    end
     
    if ss == ngx.null then
        conn:init_pipeline()
        init_keys(conn, 'vis:ss:'..ip, 1)
        local res, err = conn:commit_pipeline()
        if res == ngx.null then
            return -1
        end
        ss, err = conn:get('vis:ss:'..ip)
    end

    if tonumber(ss) >= mx_sec or tonumber(mm) >= mx_min then
        flag = false
    end 
    if tonumber(hh) >= mx_hou or tonumber(dd) >= mx_day then
        flag = false
    end
    
    local kind = headers['accept']  
    if flag then
        if  (not kind) or ( kind and (string.match(kind, 'text/html') or kind == '*/*'))  then
            conn:init_pipeline()
            conn:incr('vis:ss:'..ip)
            conn:incr('vis:mm:'..ip)
            conn:incr('vis:hh:'..ip)
            conn:incr('vis:dd:'..ip)
            local respTable, err = conn:commit_pipeline()  
            if respTable == ngx.null then  
                return -1
            end
        end
    else
        local source = scheme..'://'..host..uri
        local dest = "http://cap.169kang.com/index.php?continue="..source
        block_ip_2_cap(conn, ip)
        conn:incr('enterblk:'..ip)
        return -1
    end
    return 1
end

local status = main()
close_redis(conn)
